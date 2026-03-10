import ArgumentParser
import PullRequestPing

struct InlineCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "inline",
    abstract: "Post an inline comment on a specific code line."
  )

  @Option(name: .long, help: "Pull request number.")
  var pr: String

  @Option(name: .long, help: "File path relative to repo root.")
  var path: String

  @Option(name: .long, help: "Line number in the new file.")
  var line: Int

  @Option(name: .long, help: "Comment body (markdown supported).")
  var body: String

  @Option(name: .long, help: "Severity: critical, warning, suggestion, nitpick.")
  var severity: String?

  @Option(name: .long, help: "Repository owner/repo. Auto-detected if omitted.")
  var repo: String?

  func run() async throws {
    let provider = try await ProviderFactory().createProvider()
    let comment = ReviewLineComment(
      path: path,
      line: line,
      body: body,
      severity: severity.flatMap { CommentSeverity(rawValue: $0) }
    )
    let submission = ReviewSubmission(
      decision: .comment,
      summary: "",
      comments: [comment]
    )
    let result = try await provider.submitReview(
      prIdentifier: pr, submission: submission, repo: repo
    )
    if result.reviewPosted {
      print("Posted comment on \(path):\(line)")
      if let url = result.reviewURL { print("  \(url)") }
    }
    if result.commentsFailed > 0 {
      for failure in result.failures {
        print("Failed: \(failure.comment.path):\(failure.comment.line) -- \(failure.reason)")
      }
      throw ExitCode.failure
    }
  }
}
