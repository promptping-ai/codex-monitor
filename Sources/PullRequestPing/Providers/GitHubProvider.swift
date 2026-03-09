import Foundation

/// GitHub provider using `gh` CLI
public struct GitHubProvider: PRProvider {
  public var name: String { "GitHub" }

  private let cli = CLIHelper()

  // MARK: - GraphQL Queries

  /// Query to fetch review threads with their IDs for resolution
  private static let reviewThreadsQuery = """
    query($owner: String!, $repo: String!, $prNumber: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              path
              line
              comments(first: 1) {
                nodes {
                  id
                  body
                  author {
                    login
                  }
                }
              }
            }
          }
        }
      }
    }
    """

  /// Mutation to resolve a review thread
  private static let resolveThreadMutation = """
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread {
          id
          isResolved
        }
      }
    }
    """

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let ghPath = try await cli.findExecutable(name: "gh")

    // Build gh command for PR data
    var prArgs: [String] = ["pr", "view"]
    if !identifier.isEmpty {
      prArgs.append(identifier)
    }
    prArgs.append(contentsOf: ["--json", "body,comments,reviews,files,number"])

    if let repo = repo {
      prArgs.append(contentsOf: ["--repo", repo])
    }

    // Execute command
    let prOutput = try await cli.execute(executable: ghPath, arguments: prArgs)

    // Parse JSON response
    let decoder = JSONDecoder()
    var pr = try decoder.decode(PullRequest.self, from: Data(prOutput))

    // Fetch inline review comments separately (gh pr view doesn't include them)
    // Note: gh api doesn't support --repo flag, so we must expand the repo into the URL
    let prNum = pr.number.map(String.init) ?? identifier
    let apiPath: String
    if let repo = repo {
      // Explicitly use the repo in the URL
      apiPath = "repos/\(repo)/pulls/\(prNum)/comments"
    } else {
      // Let gh resolve {owner}/{repo} from current directory
      apiPath = "repos/{owner}/{repo}/pulls/\(prNum)/comments"
    }
    let apiArgs = ["api", apiPath]

    let commentsOutput = try await cli.execute(executable: ghPath, arguments: apiArgs)
    let inlineComments = try decoder.decode([GitHubReviewComment].self, from: Data(commentsOutput))

    // Merge inline comments into reviews
    pr = mergeInlineComments(pr: pr, inlineComments: inlineComments)

    // Fetch GraphQL thread IDs for resolution support
    if let prNumber = pr.number {
      do {
        let (owner, repoName) = try await parseRepoIdentifier(repo)
        let threads = try await fetchReviewThreadsGraphQL(
          owner: owner, repo: repoName, prNumber: prNumber)
        pr = mergeGraphQLThreads(pr: pr, threads: threads)
      } catch {
        // Log warning but don't fail - GraphQL is optional enhancement
        FileHandle.standardError.write(
          "⚠️  Could not fetch thread IDs: \(error.localizedDescription)\n".data(using: .utf8)!)
      }
    }

    return pr
  }

  /// Merge inline review comments into their parent reviews
  ///
  /// GitHub's REST API returns `pull_request_review_id` as integers, but
  /// GraphQL returns review IDs as strings (e.g., `PRR_kwDOQo0_Ns...`).
  /// Since they can't be matched directly, we match by author instead.
  private func mergeInlineComments(pr: PullRequest, inlineComments: [GitHubReviewComment])
    -> PullRequest
  {
    guard !inlineComments.isEmpty else { return pr }

    // Group inline comments by author login
    var commentsByAuthor: [String: [ReviewComment]] = [:]
    for ghComment in inlineComments {
      let reviewComment = ReviewComment(
        id: String(ghComment.id),
        path: ghComment.path,
        line: ghComment.line ?? ghComment.originalLine,
        body: ghComment.body,
        createdAt: ghComment.createdAt
      )
      commentsByAuthor[ghComment.user.login, default: []].append(reviewComment)
    }

    // Build a map of reviews by author (most authors have one review)
    // If multiple reviews from same author, use the first one
    var reviewByAuthor: [String: Int] = [:]  // author -> index in reviews
    for (index, review) in pr.reviews.enumerated() {
      if reviewByAuthor[review.author.login] == nil {
        reviewByAuthor[review.author.login] = index
      }
    }

    // Update reviews with their author's inline comments
    var updatedReviews = pr.reviews
    var matchedAuthors: Set<String> = []

    for (authorLogin, comments) in commentsByAuthor {
      if let reviewIndex = reviewByAuthor[authorLogin] {
        // Found a matching review - add comments to it
        let review = updatedReviews[reviewIndex]
        let existingComments = review.comments ?? []
        updatedReviews[reviewIndex] = Review(
          id: review.id,
          author: review.author,
          authorAssociation: review.authorAssociation,
          body: review.body,
          submittedAt: review.submittedAt,
          state: review.state,
          comments: existingComments + comments
        )
        matchedAuthors.insert(authorLogin)
      }
    }

    // Create synthetic reviews for any authors with comments but no review
    for (authorLogin, comments) in commentsByAuthor where !matchedAuthors.contains(authorLogin) {
      // Find earliest comment date for synthetic review timestamp
      let earliestDate = comments.map(\.createdAt).min() ?? ""
      let syntheticReview = Review(
        id: "inline-\(authorLogin)",
        author: Author(login: authorLogin),
        authorAssociation: "NONE",
        body: nil,
        submittedAt: earliestDate,
        state: "COMMENTED",
        comments: comments
      )
      updatedReviews.append(syntheticReview)
    }

    return PullRequest(
      body: pr.body,
      comments: pr.comments,
      reviews: updatedReviews,
      files: pr.files,
      number: pr.number
    )
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let ghPath = try await cli.findExecutable(name: "gh")

    // Validate repo format if provided
    var owner: String?
    var repoName: String?
    if let repo = repo {
      let parts = repo.split(separator: "/", maxSplits: 1)
      guard parts.count == 2 else {
        throw PRProviderError.invalidConfiguration(
          "Invalid repo format '\(repo)'. Expected 'owner/repo'")
      }
      owner = String(parts[0])
      repoName = String(parts[1])
    }

    // Use gh api to post a comment reply
    // GitHub API: POST /repos/{owner}/{repo}/pulls/{pr}/comments with in_reply_to
    // Note: The /pulls/comments/{id}/replies endpoint doesn't exist - replies are
    // created as new comments with in_reply_to referencing the parent comment ID
    var args = [
      "api",
      "-X", "POST",
    ]

    if let owner = owner, let repoName = repoName {
      args.append("repos/\(owner)/\(repoName)/pulls/\(prIdentifier)/comments")
    } else {
      // Use placeholder syntax when repo not specified (gh will resolve from current repo)
      args.append("repos/{owner}/{repo}/pulls/\(prIdentifier)/comments")
    }

    args.append(contentsOf: ["-f", "body=\(body)"])
    args.append(contentsOf: ["-F", "in_reply_to=\(commentId)"])

    _ = try await cli.execute(executable: ghPath, arguments: args)
  }

  public func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws {
    // Validate thread ID format (should be PRRT_xxx or PRT_xxx)
    guard threadId.hasPrefix("PRRT_") || threadId.hasPrefix("PRT_") else {
      throw PRProviderError.invalidConfiguration(
        """
        Invalid GitHub thread ID '\(threadId)'. Expected format: PRRT_xxx or PRT_xxx
        (use 'pr-comments view' to find thread IDs)
        """
      )
    }

    // Execute the GraphQL mutation
    let output = try await cli.executeGraphQL(
      query: Self.resolveThreadMutation,
      variables: ["threadId": threadId]
    )

    // Parse response to verify success
    let decoder = JSONDecoder()
    let response = try decoder.decode(
      GitHubGraphQLResponse<GitHubResolveThreadData>.self,
      from: Data(output)
    )

    // Check for GraphQL errors
    if let errors = response.errors, !errors.isEmpty {
      let errorMessages = errors.map(\.message).joined(separator: "; ")
      if errorMessages.contains("Resource not accessible") {
        throw PRProviderError.commandFailed(
          "resolveReviewThread",
          stderr:
            "Resource not accessible by integration. (Hint: Ensure 'gh' is authenticated with 'repo' scope. Run 'gh auth refresh -s repo' to fix)"
        )
      }
      throw PRProviderError.commandFailed("GraphQL mutation", stderr: errorMessages)
    }

    // Verify the thread was resolved
    guard let thread = response.data?.resolveReviewThread?.thread else {
      throw PRProviderError.commandFailed(
        "resolveReviewThread",
        stderr: "Thread resolution failed or returned unexpected state"
      )
    }

    guard thread.isResolved else {
      throw PRProviderError.commandFailed(
        "resolveReviewThread",
        stderr: "Thread was not marked as resolved after mutation"
      )
    }
  }

  public func submitReview(
    prIdentifier: String,
    submission: ReviewSubmission,
    repo: String?
  ) async throws -> ReviewSubmissionResult {
    let ghPath = try await cli.findExecutable(name: "gh")
    let (owner, repoName) = try await parseRepoIdentifier(repo)

    let apiPath = "repos/\(owner)/\(repoName)/pulls/\(prIdentifier)/reviews"
    let args = ["api", "-X", "POST", apiPath, "--input", "-"]

    // Build the review JSON body for GitHub's Create Review API
    let jsonData = try buildReviewJSON(submission: submission, includeComments: true)

    do {
      let output = try await cli.execute(
        executable: ghPath,
        arguments: args,
        stdin: Array(jsonData)
      )

      let decoder = JSONDecoder()
      let response = try? decoder.decode(GitHubReviewResponse.self, from: Data(output))

      return ReviewSubmissionResult(
        reviewPosted: true,
        commentsPosted: submission.comments.count,
        commentsFailed: 0,
        reviewURL: response?.htmlURL
      )
    } catch let error as PRProviderError {
      // Check for specific retryable/reportable errors
      let errorDescription = error.description

      // Permission denied: GITHUB_TOKEN can't approve own PRs
      if errorDescription.contains("Can not approve your own pull request")
        || errorDescription.contains("Not Found")
          && submission.decision == .approve
      {
        throw PRProviderError.commandFailed(
          "submitReview",
          stderr:
            "Cannot approve: GitHub Actions GITHUB_TOKEN lacks permission to approve PRs. "
            + "Use a PAT or GitHub App token instead."
        )
      }

      // Stale diff positions: retry without inline comments
      if !submission.comments.isEmpty
        && (errorDescription.contains("pull_request_review_thread")
          || errorDescription.contains("Validation Failed")
          || errorDescription.contains("is not part of the diff"))
      {
        let retryJSON = try buildReviewJSON(submission: submission, includeComments: false)
        let retryOutput = try await cli.execute(
          executable: ghPath,
          arguments: args,
          stdin: Array(retryJSON)
        )

        let decoder = JSONDecoder()
        let response = try? decoder.decode(GitHubReviewResponse.self, from: Data(retryOutput))

        let failures = submission.comments.map {
          InlineCommentFailure(comment: $0, reason: "Stale diff position — line no longer in diff")
        }

        return ReviewSubmissionResult(
          reviewPosted: true,
          commentsPosted: 0,
          commentsFailed: submission.comments.count,
          failures: failures,
          reviewURL: response?.htmlURL
        )
      }

      throw error
    }
  }

  /// Build JSON body for the GitHub Create Review API
  private func buildReviewJSON(
    submission: ReviewSubmission,
    includeComments: Bool
  ) throws -> Data {
    var reviewBody: [String: Any] = [
      "event": submission.decision.rawValue,
      "body": submission.summary,
    ]

    if let commitSHA = submission.commitSHA {
      reviewBody["commit_id"] = commitSHA
    }

    if includeComments && !submission.comments.isEmpty {
      reviewBody["comments"] = submission.comments.map { comment -> [String: Any] in
        [
          "path": comment.path,
          "line": comment.line,
          "body": comment.formattedBody,
          "side": "RIGHT",
        ]
      }
    }

    return try JSONSerialization.data(withJSONObject: reviewBody)
  }

  public func isAvailable() async -> Bool {
    return await cli.isInstalled("gh")
  }

  // MARK: - GraphQL Helpers

  /// Parse a repo string into owner and name components
  /// - Parameter repo: Repository in "owner/repo" format, or nil to detect from current directory
  /// - Returns: Tuple of (owner, repoName)
  private func parseRepoIdentifier(_ repo: String?) async throws -> (owner: String, repo: String) {
    if let repo = repo {
      let parts = repo.split(separator: "/", maxSplits: 1)
      guard parts.count == 2 else {
        throw PRProviderError.invalidConfiguration(
          "Invalid repo format '\(repo)'. Expected 'owner/repo'"
        )
      }
      return (String(parts[0]), String(parts[1]))
    }

    // Try to get from current git remote
    let remoteURL = try await cli.getGitRemoteURL()
    return try parseGitRemoteURL(remoteURL)
  }

  /// Parse a git remote URL into owner and repo
  private func parseGitRemoteURL(_ url: String) throws -> (owner: String, repo: String) {
    // Handle SSH format: git@github.com:owner/repo.git
    if url.contains("git@") {
      let pattern = #"git@[^:]+:([^/]+)/(.+?)(?:\.git)?$"#
      if let match = url.range(of: pattern, options: .regularExpression) {
        let pathPart = url[match].dropFirst(
          url.distance(from: url.startIndex, to: match.lowerBound))
        let components = String(pathPart).components(separatedBy: ":")
        if components.count == 2 {
          let ownerRepo = components[1].replacingOccurrences(of: ".git", with: "")
          let parts = ownerRepo.split(separator: "/", maxSplits: 1)
          if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
          }
        }
      }
    }

    // Handle HTTPS format: https://github.com/owner/repo.git
    if let urlObj = URL(string: url) {
      let pathComponents = urlObj.pathComponents.filter { $0 != "/" }
      if pathComponents.count >= 2 {
        let owner = pathComponents[0]
        let repo = pathComponents[1].replacingOccurrences(of: ".git", with: "")
        return (owner, repo)
      }
    }

    throw PRProviderError.invalidConfiguration(
      "Could not parse repository from git remote URL: \(url)"
    )
  }

  /// Fetch review threads via GraphQL to get thread IDs for resolution
  private func fetchReviewThreadsGraphQL(
    owner: String,
    repo: String,
    prNumber: Int
  ) async throws -> [GitHubReviewThread] {
    let output = try await cli.executeGraphQL(
      query: Self.reviewThreadsQuery,
      variables: [
        "owner": owner,
        "repo": repo,
        "prNumber": prNumber,
      ]
    )

    let decoder = JSONDecoder()
    let response = try decoder.decode(
      GitHubGraphQLResponse<GitHubRepositoryData>.self,
      from: Data(output)
    )

    // Check for errors but don't fail - gracefully degrade to REST-only
    if let errors = response.errors, !errors.isEmpty {
      FileHandle.standardError.write(
        "⚠️  Could not fetch GraphQL thread IDs: \(errors.map(\.message).joined(separator: "; "))\n"
          .data(using: .utf8)!
      )
      return []
    }

    return response.data?.repository?.pullRequest?.reviewThreads.nodes ?? []
  }

  /// Thread info from GraphQL including resolution status
  private struct ThreadInfo {
    let id: String
    let isResolved: Bool
  }

  /// Merge GraphQL thread IDs and resolution status into REST API comments
  ///
  /// Matches threads to comments by path + line + author
  private func mergeGraphQLThreads(
    pr: PullRequest,
    threads: [GitHubReviewThread]
  ) -> PullRequest {
    guard !threads.isEmpty else { return pr }

    // Build a lookup map: (path, line, author) -> ThreadInfo
    var threadLookup: [String: ThreadInfo] = [:]
    for thread in threads {
      guard let firstComment = thread.comments.nodes.first,
        let author = firstComment.author?.login,
        let path = thread.path
      else { continue }

      let key = "\(path):\(thread.line ?? 0):\(author)"
      threadLookup[key] = ThreadInfo(id: thread.id, isResolved: thread.isResolved)
    }

    // Update reviews with thread IDs and resolution status
    let updatedReviews = pr.reviews.map { review -> Review in
      guard let comments = review.comments else { return review }

      let updatedComments = comments.map { comment -> ReviewComment in
        guard let path = comment.path, let line = comment.line else { return comment }
        let key = "\(path):\(line):\(review.author.login)"

        if let threadInfo = threadLookup[key] {
          return ReviewComment(
            id: comment.id,
            path: comment.path,
            line: comment.line,
            body: comment.body,
            createdAt: comment.createdAt,
            threadId: threadInfo.id,
            isResolved: threadInfo.isResolved
          )
        }
        return comment
      }

      return Review(
        id: review.id,
        author: review.author,
        authorAssociation: review.authorAssociation,
        body: review.body,
        submittedAt: review.submittedAt,
        state: review.state,
        comments: updatedComments
      )
    }

    return PullRequest(
      body: pr.body,
      comments: pr.comments,
      reviews: updatedReviews,
      files: pr.files,
      number: pr.number
    )
  }
}
