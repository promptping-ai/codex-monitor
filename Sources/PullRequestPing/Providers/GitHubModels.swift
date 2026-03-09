import Foundation

// MARK: - GitHub API Models (for fetching inline comments)

/// GitHub review comment from /pulls/{pr}/comments API
struct GitHubReviewComment: Codable {
  let id: Int
  let pullRequestReviewId: Int?
  let path: String
  let line: Int?
  let originalLine: Int?
  let body: String
  let createdAt: String
  let user: GitHubUser

  enum CodingKeys: String, CodingKey {
    case id
    case pullRequestReviewId = "pull_request_review_id"
    case path
    case line
    case originalLine = "original_line"
    case body
    case createdAt = "created_at"
    case user
  }
}

struct GitHubUser: Codable {
  let login: String
}

// MARK: - GitHub GraphQL Models (for thread resolution)

/// Response wrapper for GraphQL queries
struct GitHubGraphQLResponse<T: Codable>: Codable {
  let data: T?
  let errors: [GitHubGraphQLError]?
}

/// GraphQL error structure
struct GitHubGraphQLError: Codable {
  let message: String
  let type: String?
  let path: [String]?
}

/// Repository query response
struct GitHubRepositoryData: Codable {
  let repository: GitHubRepository?
}

/// Repository with pull request
struct GitHubRepository: Codable {
  let pullRequest: GitHubPullRequestGraphQL?
}

/// Pull request with review threads (GraphQL)
struct GitHubPullRequestGraphQL: Codable {
  let reviewThreads: GitHubReviewThreadConnection
}

/// Connection wrapper for review threads
struct GitHubReviewThreadConnection: Codable {
  let nodes: [GitHubReviewThread]
}

/// Review thread with resolution status
struct GitHubReviewThread: Codable {
  /// GraphQL node ID (e.g., "PRRT_kwDOQo0_Ns6aBcDe")
  let id: String
  let isResolved: Bool
  let path: String?
  let line: Int?
  let comments: GitHubReviewThreadCommentConnection
}

/// Connection wrapper for thread comments
struct GitHubReviewThreadCommentConnection: Codable {
  let nodes: [GitHubReviewThreadComment]
}

/// Comment within a review thread (GraphQL)
struct GitHubReviewThreadComment: Codable {
  let id: String
  let body: String
  let author: GitHubGraphQLAuthor?
}

/// Author in GraphQL responses
struct GitHubGraphQLAuthor: Codable {
  let login: String
}

// MARK: - GraphQL Mutation Response Models

/// Response for resolveReviewThread mutation
struct GitHubResolveThreadData: Codable {
  let resolveReviewThread: GitHubResolveThreadPayload?
}

/// Payload from resolveReviewThread mutation
struct GitHubResolveThreadPayload: Codable {
  let thread: GitHubResolvedThread?
}

/// Thread after resolution
struct GitHubResolvedThread: Codable {
  let id: String
  let isResolved: Bool
}

// MARK: - Review Submission Response

/// Response from POST /repos/{owner}/{repo}/pulls/{pr}/reviews
struct GitHubReviewResponse: Codable {
  let id: Int
  let htmlURL: String?

  enum CodingKeys: String, CodingKey {
    case id
    case htmlURL = "html_url"
  }
}
