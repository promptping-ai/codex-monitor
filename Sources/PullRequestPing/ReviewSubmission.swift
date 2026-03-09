import Foundation

// MARK: - Review Submission Models

/// Decision for a PR review
public enum ReviewDecision: String, Sendable, Codable, CaseIterable {
  case approve = "APPROVE"
  case requestChanges = "REQUEST_CHANGES"
  case comment = "COMMENT"
}

/// Severity level for inline review comments
public enum CommentSeverity: String, Sendable, Codable, CaseIterable {
  case critical
  case warning
  case suggestion
  case nitpick
}

/// An inline comment attached to a specific file and line
public struct ReviewLineComment: Sendable, Codable {
  /// File path relative to repository root
  public let path: String
  /// Line number in the diff (right side / new file)
  public let line: Int
  /// Comment body (markdown supported)
  public let body: String
  /// Optional severity classification
  public let severity: CommentSeverity?

  public init(path: String, line: Int, body: String, severity: CommentSeverity? = nil) {
    self.path = path
    self.line = line
    self.body = body
    self.severity = severity
  }
}

/// A complete review submission with decision, summary, and inline comments
public struct ReviewSubmission: Sendable, Codable {
  /// The review decision (approve, request changes, or comment)
  public let decision: ReviewDecision
  /// Review summary body (markdown supported)
  public let summary: String
  /// Inline comments on specific lines
  public let comments: [ReviewLineComment]
  /// Optional commit SHA to pin the review to a specific commit
  public let commitSHA: String?

  public init(
    decision: ReviewDecision,
    summary: String,
    comments: [ReviewLineComment] = [],
    commitSHA: String? = nil
  ) {
    self.decision = decision
    self.summary = summary
    self.comments = comments
    self.commitSHA = commitSHA
  }
}

/// Records a single inline comment that failed to post
public struct InlineCommentFailure: Sendable, Codable {
  /// The comment that failed
  public let comment: ReviewLineComment
  /// Reason for the failure
  public let reason: String

  public init(comment: ReviewLineComment, reason: String) {
    self.comment = comment
    self.reason = reason
  }
}

/// Result of submitting a review
public struct ReviewSubmissionResult: Sendable, Codable {
  /// Whether the review itself was posted successfully
  public let reviewPosted: Bool
  /// Number of inline comments successfully posted
  public let commentsPosted: Int
  /// Number of inline comments that failed to post
  public let commentsFailed: Int
  /// Details of failed inline comments
  public let failures: [InlineCommentFailure]
  /// URL to the posted review (provider-specific)
  public let reviewURL: String?

  public init(
    reviewPosted: Bool,
    commentsPosted: Int,
    commentsFailed: Int,
    failures: [InlineCommentFailure] = [],
    reviewURL: String? = nil
  ) {
    self.reviewPosted = reviewPosted
    self.commentsPosted = commentsPosted
    self.commentsFailed = commentsFailed
    self.failures = failures
    self.reviewURL = reviewURL
  }
}

// MARK: - Comment Formatting

extension ReviewLineComment {
  /// Format the comment body with an optional severity prefix (e.g. "**[Critical]** ...")
  public var formattedBody: String {
    guard let severity else { return body }
    let prefix: String
    switch severity {
    case .critical: prefix = "**[Critical]**"
    case .warning: prefix = "**[Warning]**"
    case .suggestion: prefix = "**[Suggestion]**"
    case .nitpick: prefix = "**[Nitpick]**"
    }
    return "\(prefix) \(body)"
  }
}
