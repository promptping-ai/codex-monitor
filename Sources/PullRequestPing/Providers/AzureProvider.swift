import Foundation

/// Azure DevOps provider using `az` CLI
public struct AzureProvider: PRProvider {
  public var name: String { "Azure DevOps" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let azPath = try await cli.findExecutable(name: "az")

    // Fetch basic PR info - Azure PRs are uniquely identified by ID across the org
    let prArgs: [String] = ["repos", "pr", "show", "--id", identifier, "--output", "json"]
    let prOutput = try await cli.execute(executable: azPath, arguments: prArgs)

    // Parse PR to get project and repository info for thread lookup
    let decoder = JSONDecoder()
    let azurePR = try decoder.decode(AzurePR.self, from: Data(prOutput))

    // Fetch PR threads using devops invoke (REST API)
    // Azure DevOps requires project and repository for thread lookup
    let threadsArgs: [String] = [
      "devops", "invoke",
      "--area", "git",
      "--resource", "pullRequestThreads",
      "--route-parameters",
      "project=\(azurePR.repository.project.name)",
      "repositoryId=\(azurePR.repository.name)",
      "pullRequestId=\(identifier)",
      "--output", "json",
    ]

    var azureThreads: [AzurePRThread] = []
    do {
      let threadsOutput = try await cli.execute(executable: azPath, arguments: threadsArgs)
      let threadsResponse = try decoder.decode(AzureThreadsResponse.self, from: Data(threadsOutput))
      azureThreads = threadsResponse.value
    } catch {
      // Log warning but continue with empty threads (e.g., permissions issue)
      FileHandle.standardError.write(
        Data("⚠️ Warning: Failed to fetch PR threads: \(error)\n".utf8)
      )
    }

    return azurePR.toPullRequest(threads: azureThreads)
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let azPath = try await cli.findExecutable(name: "az")

    // Azure: commentId is the thread ID, use thread comment create
    var args = [
      "repos", "pr", "thread", "comment", "create",
      "--thread-id", commentId,
      "--content", body,
      "--pull-request-id", prIdentifier,
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repository", repo])
    }

    _ = try await cli.execute(executable: azPath, arguments: args)
  }

  public func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws {
    let azPath = try await cli.findExecutable(name: "az")

    // Azure thread status update - "fixed" marks as resolved
    var args = [
      "repos", "pr", "thread", "update",
      "--thread-id", threadId,
      "--status", "fixed",
      "--pull-request-id", prIdentifier,
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repository", repo])
    }

    _ = try await cli.execute(executable: azPath, arguments: args)
  }

  public func submitReview(
    prIdentifier: String,
    submission: ReviewSubmission,
    repo: String?
  ) async throws -> ReviewSubmissionResult {
    let azPath = try await cli.findExecutable(name: "az")

    var reviewPosted = false

    // Step 1: Set vote based on decision
    // Azure vote values: approve, approve-with-suggestions, wait-for-author, reject, reset
    let vote: String
    switch submission.decision {
    case .approve: vote = "approve"
    case .requestChanges: vote = "wait-for-author"
    case .comment: vote = "reset"  // No vote, just commenting
    }

    var voteArgs = [
      "repos", "pr", "set-vote",
      "--id", prIdentifier,
      "--vote", vote,
    ]
    if let repo = repo {
      voteArgs.append(contentsOf: ["--repository", repo])
    }
    _ = try await cli.execute(executable: azPath, arguments: voteArgs)
    reviewPosted = true

    // Step 2: Post summary as a top-level thread
    let summaryPrefix =
      switch submission.decision {
      case .approve: "**Approved**\n\n"
      case .requestChanges: "**Changes Requested**\n\n"
      case .comment: ""
      }

    let summaryBody = "\(summaryPrefix)\(submission.summary)"
    let summaryThreadBody: [String: Any] = [
      "comments": [["content": summaryBody]],
      "status": "active",
    ]
    let summaryJSON = try JSONSerialization.data(withJSONObject: summaryThreadBody)

    // Fetch PR details to get project/repo for thread creation
    let prShowArgs = ["repos", "pr", "show", "--id", prIdentifier, "--output", "json"]
    let prOutput = try await cli.execute(executable: azPath, arguments: prShowArgs)
    let decoder = JSONDecoder()
    let azurePR = try decoder.decode(AzurePR.self, from: Data(prOutput))

    let createThreadArgs = [
      "devops", "invoke",
      "--area", "git",
      "--resource", "pullRequestThreads",
      "--route-parameters",
      "project=\(azurePR.repository.project.name)",
      "repositoryId=\(azurePR.repository.name)",
      "pullRequestId=\(prIdentifier)",
      "--http-method", "POST",
      "--in-file", "/dev/stdin",
      "--output", "json",
    ]

    _ = try await cli.execute(
      executable: azPath,
      arguments: createThreadArgs,
      stdin: Array(summaryJSON)
    )

    // Step 3: Post inline comments as threads with file context
    var commentsPosted = 0
    var failures: [InlineCommentFailure] = []

    for comment in submission.comments {
      do {
        let body = Self.formatCommentBody(comment)
        let threadBody: [String: Any] = [
          "comments": [["content": body]],
          "status": "active",
          "threadContext": [
            "filePath": "/\(comment.path)",
            "rightFileStart": ["line": comment.line, "offset": 1],
            "rightFileEnd": ["line": comment.line, "offset": 1],
          ],
        ]

        let threadJSON = try JSONSerialization.data(withJSONObject: threadBody)

        _ = try await cli.execute(
          executable: azPath,
          arguments: createThreadArgs,
          stdin: Array(threadJSON)
        )
        commentsPosted += 1
      } catch {
        failures.append(
          InlineCommentFailure(comment: comment, reason: error.localizedDescription))
      }
    }

    return ReviewSubmissionResult(
      reviewPosted: reviewPosted,
      commentsPosted: commentsPosted,
      commentsFailed: failures.count,
      failures: failures
    )
  }

  /// Format a comment body with optional severity prefix
  private static func formatCommentBody(_ comment: ReviewLineComment) -> String {
    guard let severity = comment.severity else { return comment.body }
    let prefix: String
    switch severity {
    case .critical: prefix = "**[Critical]**"
    case .warning: prefix = "**[Warning]**"
    case .suggestion: prefix = "**[Suggestion]**"
    case .nitpick: prefix = "**[Nitpick]**"
    }
    return "\(prefix) \(comment.body)"
  }

  public func isAvailable() async -> Bool {
    return await cli.isInstalled("az")
  }
}

// MARK: - Azure-specific models

/// Response wrapper for devops invoke (threads API)
private struct AzureThreadsResponse: Codable {
  let value: [AzurePRThread]
  let count: Int?
}

/// Azure Pull Request structure
private struct AzurePR: Codable {
  let title: String
  let description: String?
  let pullRequestId: Int
  let repository: AzureRepository
}

/// Azure Repository structure
private struct AzureRepository: Codable {
  let name: String
  let project: AzureProject
}

/// Azure Project structure
private struct AzureProject: Codable {
  let name: String
}

extension AzurePR {
  func toPullRequest(threads: [AzurePRThread]) -> PullRequest {
    // Convert Azure threads to our Review model
    let reviews = threads.map { thread in
      // Map Azure status to Review state:
      // - "active" or nil (system threads) → PENDING (unresolved)
      // - "fixed", "closed", etc. → APPROVED (resolved)
      let reviewState: String
      if let status = thread.status {
        reviewState = status == "active" ? "PENDING" : "APPROVED"
      } else {
        reviewState = "PENDING"  // System threads without status are treated as pending
      }

      return Review(
        id: String(thread.id),
        author: Author(login: thread.comments.first?.author.displayName ?? "Unknown"),
        authorAssociation: "CONTRIBUTOR",
        body: thread.comments.first?.content,
        submittedAt: thread.publishedDate,
        state: reviewState,
        // Include all thread comments, even without file context (PR-level comments)
        comments: convertToReviewComments(thread: thread)
      )
    }

    // Azure doesn't have separate top-level comments like GitHub
    // All comments are within threads
    return PullRequest(
      body: description ?? "",
      comments: [],
      reviews: reviews,
      files: nil,
      number: pullRequestId
    )
  }

  private func convertToReviewComments(thread: AzurePRThread) -> [ReviewComment] {
    // Azure status values: "active", "fixed", "closed", "wontFix", "byDesign", "pending"
    // System threads (reviewer added, etc.) don't have status - treat as unresolved
    let resolvedStatuses = ["fixed", "closed", "wontFix", "byDesign"]
    let isResolved = thread.status.map { resolvedStatuses.contains($0) } ?? false

    // Thread context is optional - PR-level comments don't have file/line info
    let filePath = thread.threadContext?.filePath ?? ""
    let line = thread.threadContext?.rightFileStart?.line

    return thread.comments.map { comment in
      ReviewComment(
        id: String(comment.id),
        path: filePath,
        line: line,
        body: comment.content ?? "",
        createdAt: comment.publishedDate ?? "",
        threadId: String(thread.id),
        isResolved: isResolved
      )
    }
  }
}

/// Azure PR Thread structure
private struct AzurePRThread: Codable {
  let id: Int
  /// Thread status: "active", "closed", "fixed", "wontFix", "byDesign", "pending"
  /// Optional because system-generated threads (reviewer added, etc.) don't have status
  let status: String?
  let comments: [AzurePRComment]
  let threadContext: AzureThreadContext?
  /// ISO 8601 date string, e.g. "2025-12-29T08:39:23.523Z"
  let publishedDate: String?

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case comments
    case threadContext
    case publishedDate
  }
}

/// Azure PR Comment structure
private struct AzurePRComment: Codable {
  let id: Int
  let author: AzureAuthor
  let content: String?
  /// ISO 8601 date string, e.g. "2025-12-29T08:39:23.523Z"
  let publishedDate: String?

  enum CodingKeys: String, CodingKey {
    case id
    case author
    case content
    case publishedDate
  }
}

/// Azure Thread Context (file location info)
private struct AzureThreadContext: Codable {
  let filePath: String?
  let rightFileStart: AzureLinePosition?

  enum CodingKeys: String, CodingKey {
    case filePath
    case rightFileStart
  }
}

/// Azure Line Position
private struct AzureLinePosition: Codable {
  let line: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case line
    case offset
  }
}

/// Azure Author structure
private struct AzureAuthor: Codable {
  let displayName: String

  enum CodingKeys: String, CodingKey {
    case displayName
  }
}
