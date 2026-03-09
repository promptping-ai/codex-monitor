import Foundation

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

/// Protocol for PR comment providers (GitHub, GitLab, Azure DevOps, etc.)
public protocol PRProvider: Sendable {
  /// The name of the provider (e.g., "GitHub", "GitLab", "Azure DevOps")
  var name: String { get }

  /// Fetch PR data including comments and reviews
  /// - Parameters:
  ///   - identifier: PR number, URL, or empty for current branch
  ///   - repo: Optional repository identifier (format varies by provider)
  /// - Returns: PullRequest data with all comments
  func fetchPR(identifier: String, repo: String?) async throws -> PullRequest

  /// Reply to a specific comment
  /// - Parameters:
  ///   - prIdentifier: PR number or URL
  ///   - commentId: The ID of the comment to reply to
  ///   - body: The reply message
  ///   - repo: Optional repository identifier
  func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws

  /// Resolve a review thread
  /// - Parameters:
  ///   - prIdentifier: PR number or URL
  ///   - threadId: The ID of the thread to resolve
  ///   - repo: Optional repository identifier
  func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws

  /// Submit a review with decision, summary, and optional inline comments
  /// - Parameters:
  ///   - prIdentifier: PR number or URL
  ///   - submission: The review submission containing decision, summary, and comments
  ///   - repo: Optional repository identifier
  /// - Returns: Result indicating success/failure and any comment posting failures
  func submitReview(
    prIdentifier: String,
    submission: ReviewSubmission,
    repo: String?
  ) async throws -> ReviewSubmissionResult

  /// Check if the provider's CLI tool is available
  func isAvailable() async -> Bool
}

/// Errors that can occur when using PR providers
public enum PRProviderError: Error, CustomStringConvertible {
  case cliNotFound(String)
  case commandFailed(String, stderr: String)
  case unsupportedOperation(String)
  case invalidResponse(String)
  case invalidConfiguration(String)

  public var description: String {
    switch self {
    case .cliNotFound(let name):
      return "\(name) CLI not found. Please install it first."
    case .commandFailed(let command, let stderr):
      return "Command '\(command)' failed: \(stderr)"
    case .unsupportedOperation(let operation):
      return "Operation '\(operation)' is not supported by this provider"
    case .invalidResponse(let details):
      return "Invalid response from provider: \(details)"
    case .invalidConfiguration(let details):
      return "Invalid configuration: \(details)"
    }
  }
}

/// Provider detection based on git remote URL
public enum ProviderType: String, CaseIterable, Sendable {
  case github = "GitHub"
  case gitlab = "GitLab"
  case azure = "Azure DevOps"

  /// Detect provider from git remote URL
  public static func detect(from remoteURL: String) -> ProviderType? {
    let url = remoteURL.lowercased()

    if url.contains("github.com") {
      return .github
    } else if url.contains("gitlab.com") || url.contains("gitlab") {
      return .gitlab
    } else if url.contains("dev.azure.com") || url.contains("visualstudio.com") {
      return .azure
    }

    return nil
  }

  /// Create a provider instance for this type
  public func createProvider() -> any PRProvider {
    switch self {
    case .github:
      return GitHubProvider()
    case .gitlab:
      return GitLabProvider()
    case .azure:
      return AzureProvider()
    }
  }
}
