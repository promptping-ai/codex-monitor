import ArgumentParser
import PullRequestPing

struct RequestChangesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "request-changes",
    abstract: "Submit a review requesting changes."
  )

  @Option(name: .long, help: "Pull request number.")
  var pr: String

  @Option(name: .long, help: "Review summary (markdown).")
  var summary: String

  @Option(
    name: .long,
    parsing: .singleValue,
    help: "Inline comment as path:line:body (repeatable)."
  )
  var comment: [String] = []

  @Option(name: .long, help: "Repository owner/repo. Auto-detected if omitted.")
  var repo: String?

  func run() async throws {
    let provider = try await ProviderFactory().createProvider()
    let comments = try comment.map { raw -> ReviewLineComment in
      let parts = raw.split(separator: ":", maxSplits: 2)
      guard parts.count == 3, let lineNum = Int(parts[1]) else {
        throw ValidationError("Bad format '\(raw)'. Use path:line:body")
      }
      return ReviewLineComment(
        path: String(parts[0]), line: lineNum, body: String(parts[2])
      )
    }
    let submission = ReviewSubmission(
      decision: .requestChanges,
      summary: summary,
      comments: comments
    )
    let result = try await provider.submitReview(
      prIdentifier: pr, submission: submission, repo: repo
    )
    if result.reviewPosted {
      print("Review: REQUEST_CHANGES (\(result.commentsPosted) comments)")
      if let url = result.reviewURL { print("  \(url)") }
    }
    if result.commentsFailed > 0 {
      print("\(result.commentsFailed) comment(s) failed")
      for failure in result.failures {
        print("  \(failure.comment.path):\(failure.comment.line) -- \(failure.reason)")
      }
    }
  }
}
