import Foundation
import Testing

@testable import PullRequestPing

@Suite("Review Submission Models")
struct ReviewSubmissionModelTests {

  @Test("ReviewDecision raw values match GitHub API format")
  func testReviewDecisionRawValues() {
    #expect(ReviewDecision.approve.rawValue == "APPROVE")
    #expect(ReviewDecision.requestChanges.rawValue == "REQUEST_CHANGES")
    #expect(ReviewDecision.comment.rawValue == "COMMENT")
  }

  @Test("ReviewDecision is CaseIterable with 3 cases")
  func testReviewDecisionCases() {
    #expect(ReviewDecision.allCases.count == 3)
  }

  @Test("CommentSeverity raw values")
  func testCommentSeverityRawValues() {
    #expect(CommentSeverity.critical.rawValue == "critical")
    #expect(CommentSeverity.warning.rawValue == "warning")
    #expect(CommentSeverity.suggestion.rawValue == "suggestion")
    #expect(CommentSeverity.nitpick.rawValue == "nitpick")
  }

  @Test("ReviewLineComment init with all fields")
  func testReviewLineCommentInit() {
    let comment = ReviewLineComment(
      path: "Sources/Foo.swift",
      line: 42,
      body: "Use let here",
      severity: .suggestion
    )
    #expect(comment.path == "Sources/Foo.swift")
    #expect(comment.line == 42)
    #expect(comment.body == "Use let here")
    #expect(comment.severity == .suggestion)
  }

  @Test("ReviewLineComment init without severity defaults to nil")
  func testReviewLineCommentDefaultSeverity() {
    let comment = ReviewLineComment(path: "a.swift", line: 1, body: "Note")
    #expect(comment.severity == nil)
  }

  @Test("ReviewSubmission init with defaults")
  func testReviewSubmissionDefaults() {
    let submission = ReviewSubmission(
      decision: .approve,
      summary: "LGTM"
    )
    #expect(submission.decision == .approve)
    #expect(submission.summary == "LGTM")
    #expect(submission.comments.isEmpty)
    #expect(submission.commitSHA == nil)
  }

  @Test("ReviewSubmission init with comments and commitSHA")
  func testReviewSubmissionFull() {
    let comments = [
      ReviewLineComment(path: "a.swift", line: 10, body: "Fix this"),
      ReviewLineComment(path: "b.swift", line: 20, body: "And this", severity: .critical),
    ]
    let submission = ReviewSubmission(
      decision: .requestChanges,
      summary: "Needs work",
      comments: comments,
      commitSHA: "abc123"
    )
    #expect(submission.comments.count == 2)
    #expect(submission.commitSHA == "abc123")
  }

  @Test("ReviewSubmissionResult success case")
  func testSubmissionResultSuccess() {
    let result = ReviewSubmissionResult(
      reviewPosted: true,
      commentsPosted: 3,
      commentsFailed: 0,
      reviewURL: "https://github.com/owner/repo/pull/1#pullrequestreview-123"
    )
    #expect(result.reviewPosted)
    #expect(result.commentsPosted == 3)
    #expect(result.commentsFailed == 0)
    #expect(result.failures.isEmpty)
    #expect(result.reviewURL != nil)
  }

  @Test("ReviewSubmissionResult partial failure")
  func testSubmissionResultPartialFailure() {
    let failure = InlineCommentFailure(
      comment: ReviewLineComment(path: "deleted.swift", line: 999, body: "Gone"),
      reason: "File not in diff"
    )
    let result = ReviewSubmissionResult(
      reviewPosted: true,
      commentsPosted: 2,
      commentsFailed: 1,
      failures: [failure]
    )
    #expect(result.reviewPosted)
    #expect(result.commentsFailed == 1)
    #expect(result.failures.count == 1)
    #expect(result.failures[0].reason == "File not in diff")
  }

  @Test("InlineCommentFailure preserves original comment")
  func testInlineCommentFailure() {
    let comment = ReviewLineComment(path: "test.swift", line: 5, body: "Fix")
    let failure = InlineCommentFailure(comment: comment, reason: "Stale diff")
    #expect(failure.comment.path == "test.swift")
    #expect(failure.comment.line == 5)
    #expect(failure.reason == "Stale diff")
  }
}

@Suite("Review Submission JSON Encoding")
struct ReviewSubmissionCodingTests {

  @Test("ReviewSubmission round-trips through JSON")
  func testSubmissionRoundTrip() throws {
    let original = ReviewSubmission(
      decision: .requestChanges,
      summary: "Please address these issues",
      comments: [
        ReviewLineComment(path: "src/main.swift", line: 42, body: "Use guard let"),
        ReviewLineComment(
          path: "src/helper.swift", line: 10, body: "Missing doc", severity: .nitpick),
      ],
      commitSHA: "deadbeef"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ReviewSubmission.self, from: data)

    #expect(decoded.decision == original.decision)
    #expect(decoded.summary == original.summary)
    #expect(decoded.comments.count == original.comments.count)
    #expect(decoded.comments[0].path == "src/main.swift")
    #expect(decoded.comments[0].line == 42)
    #expect(decoded.comments[1].severity == .nitpick)
    #expect(decoded.commitSHA == "deadbeef")
  }

  @Test("ReviewSubmissionResult round-trips through JSON")
  func testResultRoundTrip() throws {
    let original = ReviewSubmissionResult(
      reviewPosted: true,
      commentsPosted: 5,
      commentsFailed: 1,
      failures: [
        InlineCommentFailure(
          comment: ReviewLineComment(path: "old.swift", line: 1, body: "Gone"),
          reason: "File removed"
        )
      ],
      reviewURL: "https://github.com/test/pr/1"
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ReviewSubmissionResult.self, from: data)

    #expect(decoded.reviewPosted == true)
    #expect(decoded.commentsPosted == 5)
    #expect(decoded.commentsFailed == 1)
    #expect(decoded.failures.count == 1)
    #expect(decoded.reviewURL == "https://github.com/test/pr/1")
  }

  @Test("ReviewDecision decodes from raw string values")
  func testDecisionDecoding() throws {
    let cases: [(String, ReviewDecision)] = [
      ("\"APPROVE\"", .approve),
      ("\"REQUEST_CHANGES\"", .requestChanges),
      ("\"COMMENT\"", .comment),
    ]
    let decoder = JSONDecoder()
    for (json, expected) in cases {
      let data = json.data(using: .utf8)!
      let decoded = try decoder.decode(ReviewDecision.self, from: data)
      #expect(decoded == expected)
    }
  }
}
