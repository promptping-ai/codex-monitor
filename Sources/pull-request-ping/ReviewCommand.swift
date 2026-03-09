import ArgumentParser
import Foundation
import PullRequestPing

// MARK: - Review Parent Command

struct ReviewGroup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "review",
    abstract: "PR review operations",
    subcommands: [ReviewSubmitCommand.self]
  )
}

// MARK: - Submit Subcommand

struct ReviewSubmitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "submit",
    abstract: "Submit a PR review with decision, summary, and inline comments"
  )

  @Option(name: .long, help: "PR number or identifier")
  var pr: String

  @Option(name: .long, help: "Review decision: approve, request-changes, or comment")
  var decision: String

  @Option(name: .long, help: "Review summary")
  var summary: String

  @Option(
    name: .long,
    parsing: .singleValue,
    help: "Inline comment in format path:line:body (repeatable)"
  )
  var comment: [String] = []

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?

  func run() async throws {
    // Parse decision
    let reviewDecision = try parseDecision(decision)

    // Parse inline comments
    let lineComments = try comment.map { try parseComment($0) }

    // Create provider
    let factory = ProviderFactory()
    let providerType = try parseProviderType(provider)
    let prProvider = try await factory.createProvider(manualType: providerType)

    FileHandle.standardError.write(
      "Submitting review via \(prProvider.name) provider\n".data(using: .utf8)!)

    // Build submission
    let submission = ReviewSubmission(
      decision: reviewDecision,
      summary: summary,
      comments: lineComments
    )

    // Submit
    let result = try await prProvider.submitReview(
      prIdentifier: pr,
      submission: submission,
      repo: repo
    )

    // Output result
    if result.reviewPosted {
      print("Review submitted: \(reviewDecision.rawValue)")
      if result.commentsPosted > 0 {
        print("Inline comments posted: \(result.commentsPosted)")
      }
      if result.commentsFailed > 0 {
        print("Inline comments failed: \(result.commentsFailed)")
        for failure in result.failures {
          print("  - \(failure.comment.path):\(failure.comment.line): \(failure.reason)")
        }
      }
      if let url = result.reviewURL {
        print("URL: \(url)")
      }
    } else {
      print("Failed to submit review")
      throw ExitCode.failure
    }
  }
}

// MARK: - Parsing Helpers

private func parseDecision(_ raw: String) throws -> ReviewDecision {
  switch raw.lowercased() {
  case "approve":
    return .approve
  case "request-changes", "request_changes", "changes":
    return .requestChanges
  case "comment":
    return .comment
  default:
    throw ValidationError(
      "Invalid decision '\(raw)'. Use: approve, request-changes, or comment")
  }
}

private func parseComment(_ raw: String) throws -> ReviewLineComment {
  // Format: path:line:body
  // Split on first two colons only — body may contain colons
  let parts = raw.split(separator: ":", maxSplits: 2)
  guard parts.count == 3 else {
    throw ValidationError(
      "Invalid comment format '\(raw)'. Expected path:line:body")
  }
  guard let line = Int(parts[1]) else {
    throw ValidationError(
      "Invalid line number '\(parts[1])' in comment '\(raw)'")
  }
  return ReviewLineComment(
    path: String(parts[0]),
    line: line,
    body: String(parts[2])
  )
}
