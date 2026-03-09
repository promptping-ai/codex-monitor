import ArgumentParser
import Foundation
import PullRequestPing
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

// MARK: - Output Format

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
  case plain
  case markdown
  case json

  static var defaultValueDescription: String { "plain" }
}

@main
struct PullRequestPingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pull-request-ping",
    abstract: "View and interact with PR comments (GitHub, GitLab, Azure)",
    discussion: """
      View, reply to, and resolve PR comments, including inline code review comments.
      Supports translation between French and English using Apple Foundation Models.

      Examples:
        pull-request-ping 29                              # View comments for PR #29
        pull-request-ping 29 --with-body                  # Include PR description
        pull-request-ping --current                       # View current branch's PR
        pull-request-ping 29 --provider gitlab            # Use specific provider
        pull-request-ping 29 --language en                # Translate to English
        pull-request-ping 29 --format markdown | glow     # Markdown for Glow viewer
        pull-request-ping reply 29 --message "Done!"      # Reply to PR
        pull-request-ping reply 29 -m "Bien!" --translate-to en  # Reply in English
      """,
    subcommands: [View.self, Reply.self, ReplyTo.self, Resolve.self, ReviewGroup.self],
    defaultSubcommand: View.self
  )
}

// MARK: - View Subcommand

struct View: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "view",
    abstract: "View PR comments in a readable format"
  )

  @Argument(help: "PR number or URL")
  var prNumber: String?

  @Flag(name: .long, help: "Use PR from current branch")
  var current: Bool = false

  @Flag(name: .long, help: "Include PR body/description")
  var withBody: Bool = false

  @Flag(name: .long, help: "Show only unresolved review threads")
  var unresolved: Bool = false

  @Flag(name: .long, help: "Show only resolved review threads")
  var resolved: Bool = false

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?

  @Option(
    name: .shortAndLong,
    help:
      "Display language (en, fr, nl, de, es, it, ja, ko, pt, ru, zh, ar, hi, id, pl, th, tr, uk, vi) - translates comments"
  )
  var language: String?

  @Option(name: .long, help: "Output format: plain, markdown, json")
  var format: OutputFormat = .plain

  func run() async throws {
    // Validate mutually exclusive flags
    if unresolved && resolved {
      throw ValidationError("Cannot use --unresolved and --resolved together")
    }

    // Determine PR identifier
    let prIdentifier: String
    if current {
      if prNumber != nil {
        throw ValidationError("Cannot specify both PR number and --current flag")
      }
      prIdentifier = ""  // Empty means current branch
    } else if let number = prNumber {
      prIdentifier = number
    } else {
      throw ValidationError("Must specify either a PR number or use --current flag")
    }

    // Create provider
    let factory = ProviderFactory()
    let providerType = try parseProviderType(provider)

    let prProvider = try await factory.createProvider(manualType: providerType)
    FileHandle.standardError.write("Using \(prProvider.name) provider\n".data(using: .utf8)!)

    // Fetch PR data
    var pr = try await prProvider.fetchPR(identifier: prIdentifier, repo: repo)

    // Translate if requested
    if let lang = language {
      guard let targetLanguage = Language(rawValue: lang) else {
        throw ValidationError("Invalid language '\(lang)'. Use 'en' or 'fr'.")
      }
      if targetLanguage == .auto {
        throw ValidationError("Cannot use 'auto' as target language")
      }

      let translator = TranslationService()
      if await translator.isAvailable {
        do {
          pr = try await translatePR(pr, to: targetLanguage, using: translator)
        } catch let error as TranslationError {
          // Graceful fallback with helpful message
          let message: String
          switch error {
          case .downloadRequired:
            message =
              "⚠️  Translation language not downloaded. Open System Settings → General → Language & Region → Translation Languages\n"
          case .languageNotSupported(let pair):
            message = "⚠️  Translation not supported for \(pair) - showing original text\n"
          case .translationFailed(let reason):
            message = "⚠️  Translation failed: \(reason) - showing original text\n"
          case .translationUnavailable:
            message = "⚠️  Translation unavailable - showing original text\n"
          }
          FileHandle.standardError.write(message.data(using: .utf8)!)
        }
      } else {
        FileHandle.standardError.write(
          "⚠️  Translation.framework not available - showing original text\n".data(using: .utf8)!)
      }
    }

    // Filter by resolution status if requested
    if unresolved || resolved {
      pr = filterByResolutionStatus(pr, showUnresolved: unresolved)
    }

    // Format and print
    let formatter = PRCommentsFormatter()
    let output: String

    switch format {
    case .plain:
      output = formatter.format(pr, includeBody: withBody)
    case .markdown:
      output = formatAsMarkdown(pr, includeBody: withBody)
    case .json:
      output = formatAsJSON(pr)
    }

    print(output)
  }

  private func translatePR(
    _ pr: PullRequest,
    to targetLanguage: Language,
    using translator: TranslationService
  ) async throws -> PullRequest {
    // Collect all translatable texts
    var textsToTranslate: [String] = []
    var textIndices: [(type: String, index: Int, subIndex: Int?)] = []

    // PR body
    if !pr.body.isEmpty {
      textsToTranslate.append(pr.body)
      textIndices.append((type: "body", index: 0, subIndex: nil))
    }

    // Comments
    for (i, comment) in pr.comments.enumerated() {
      textsToTranslate.append(comment.body)
      textIndices.append((type: "comment", index: i, subIndex: nil))
    }

    // Reviews
    for (i, review) in pr.reviews.enumerated() {
      if let body = review.body, !body.isEmpty {
        textsToTranslate.append(body)
        textIndices.append((type: "review_body", index: i, subIndex: nil))
      }
      if let comments = review.comments {
        for (j, comment) in comments.enumerated() {
          textsToTranslate.append(comment.body)
          textIndices.append((type: "review_comment", index: i, subIndex: j))
        }
      }
    }

    // Batch translate
    guard !textsToTranslate.isEmpty else { return pr }

    let results = try await translator.translateBatch(textsToTranslate, to: targetLanguage)

    // Build translated PR
    var translatedBody = pr.body
    var translatedComments = pr.comments
    var translatedReviews = pr.reviews

    for (index, result) in results.enumerated() {
      let info = textIndices[index]
      let indicator =
        "[\(result.sourceLanguage.rawValue.uppercased())→\(result.targetLanguage.rawValue.uppercased())] "

      switch info.type {
      case "body":
        translatedBody = indicator + result.translatedText
      case "comment":
        let orig = translatedComments[info.index]
        translatedComments[info.index] = Comment(
          id: orig.id,
          author: orig.author,
          authorAssociation: orig.authorAssociation,
          body: indicator + result.translatedText,
          createdAt: orig.createdAt,
          url: orig.url
        )
      case "review_body":
        let orig = translatedReviews[info.index]
        translatedReviews[info.index] = Review(
          id: orig.id,
          author: orig.author,
          authorAssociation: orig.authorAssociation,
          body: indicator + result.translatedText,
          submittedAt: orig.submittedAt,
          state: orig.state,
          comments: orig.comments
        )
      case "review_comment":
        if let subIndex = info.subIndex, var comments = translatedReviews[info.index].comments {
          let orig = comments[subIndex]
          comments[subIndex] = ReviewComment(
            id: orig.id,
            path: orig.path,
            line: orig.line,
            body: indicator + result.translatedText,
            createdAt: orig.createdAt
          )
          let review = translatedReviews[info.index]
          translatedReviews[info.index] = Review(
            id: review.id,
            author: review.author,
            authorAssociation: review.authorAssociation,
            body: review.body,
            submittedAt: review.submittedAt,
            state: review.state,
            comments: comments
          )
        }
      default:
        break
      }
    }

    return PullRequest(
      body: translatedBody,
      comments: translatedComments,
      reviews: translatedReviews,
      files: pr.files
    )
  }

  private func formatAsMarkdown(_ pr: PullRequest, includeBody: Bool) -> String {
    var lines: [String] = []

    lines.append("# PR Comments")
    lines.append("")

    if includeBody && !pr.body.isEmpty {
      lines.append("## Description")
      lines.append("")
      lines.append(pr.body)
      lines.append("")
    }

    if !pr.comments.isEmpty {
      lines.append("## Comments (\(pr.comments.count))")
      lines.append("")
      for comment in pr.comments {
        lines.append("**@\(comment.author.login)** • \(comment.createdAt)")
        lines.append("")
        lines.append(comment.body)
        lines.append("")
        lines.append("---")
        lines.append("")
      }
    }

    let reviewsWithComments = pr.reviews.filter {
      ($0.comments?.isEmpty == false) || ($0.body?.isEmpty == false)
    }
    if !reviewsWithComments.isEmpty {
      lines.append("## Reviews (\(reviewsWithComments.count))")
      lines.append("")
      for review in reviewsWithComments {
        let stateEmoji = reviewStateEmoji(review.state)
        lines.append("### \(stateEmoji) @\(review.author.login)")
        lines.append("")
        if let body = review.body, !body.isEmpty {
          lines.append(body)
          lines.append("")
        }
        if let comments = review.comments, !comments.isEmpty {
          lines.append("**Code Comments:**")
          lines.append("")
          for comment in comments {
            let location = comment.line.map { ":\($0)" } ?? ""
            lines.append("📍 `\(comment.path ?? "")\(location)`")
            lines.append("")
            lines.append(comment.body)
            lines.append("")
          }
        }
        lines.append("---")
        lines.append("")
      }
    }

    return lines.joined(separator: "\n")
  }

  private func formatAsJSON(_ pr: PullRequest) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(pr),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{\"error\": \"Failed to encode PR as JSON\"}"
    }
    return json
  }

  private func reviewStateEmoji(_ state: String) -> String {
    switch state.uppercased() {
    case "APPROVED": return "✅"
    case "CHANGES_REQUESTED": return "❌"
    case "COMMENTED": return "💭"
    case "DISMISSED": return "🚫"
    case "PENDING": return "⏳"
    default: return "📋"
    }
  }
}

// MARK: - Reply Subcommand

struct Reply: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reply",
    abstract: "Reply to a PR with optional translation"
  )

  @Argument(help: "PR number")
  var prNumber: String

  @Option(name: .shortAndLong, help: "Reply message")
  var message: String?

  @Option(name: .long, help: "Translate message to language before sending (en, fr)")
  var translateTo: String?

  @Flag(name: .long, help: "Preview translation without sending")
  var preview: Bool = false

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?

  func run() async throws {
    // Get message from argument or stdin
    let replyMessage: String
    if let msg = message {
      replyMessage = msg
    } else {
      FileHandle.standardError.write("Enter your reply (Ctrl+D when done):\n".data(using: .utf8)!)
      var inputLines: [String] = []
      while let line = readLine() {
        inputLines.append(line)
      }
      replyMessage = inputLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
    }

    guard !replyMessage.isEmpty else {
      throw ValidationError("Message cannot be empty")
    }

    // Translate if requested
    var finalMessage = replyMessage
    var translationIndicator = ""

    if let lang = translateTo {
      guard let targetLanguage = Language(rawValue: lang) else {
        throw ValidationError("Invalid language '\(lang)'. Use 'en' or 'fr'.")
      }
      if targetLanguage == .auto {
        throw ValidationError("Cannot use 'auto' as target language")
      }

      let translator = TranslationService()
      if await translator.isAvailable {
        let result = try await translator.translate(replyMessage, to: targetLanguage)
        finalMessage = result.translatedText
        translationIndicator =
          "[\(result.sourceLanguage.rawValue.uppercased())→\(result.targetLanguage.rawValue.uppercased())]"

        if preview {
          print("─── Original ───")
          print(replyMessage)
          print("")
          print("─── Translated \(translationIndicator) ───")
          print(finalMessage)
          return
        }
      } else {
        throw ValidationError("Foundation Models not available for translation")
      }
    }

    if preview {
      print("─── Preview ───")
      print(finalMessage)
      print("")
      print("Use without --preview to send this reply.")
      return
    }

    // Create provider and post comment
    let factory = ProviderFactory()
    let providerType = try parseProviderType(provider)

    let prProvider = try await factory.createProvider(manualType: providerType)

    // Post the comment using the provider's CLI
    try await postComment(
      prNumber: prNumber, message: finalMessage, provider: prProvider, repo: repo)

    if !translationIndicator.isEmpty {
      print("✅ Reply sent \(translationIndicator)")
    } else {
      print("✅ Reply sent")
    }
  }

  private func postComment(prNumber: String, message: String, provider: PRProvider, repo: String?)
    async throws
  {
    switch provider.name {
    case "GitHub":
      var args = ["pr", "comment", prNumber, "--body", message]
      if let r = repo {
        args.append(contentsOf: ["--repo", r])
      }
      let result = try await Subprocess.run(
        .name("gh"),
        arguments: Arguments(args),
        output: .bytes(limit: 1024),
        error: .discarded
      )
      guard result.terminationStatus.isSuccess else {
        throw ValidationError("Failed to post comment via gh CLI")
      }

    case "GitLab":
      // glab mr note <mr-id> --message "..."
      var args = ["mr", "note", prNumber, "--message", message]
      if let r = repo {
        args.append(contentsOf: ["--repo", r])
      }
      let result = try await Subprocess.run(
        .name("glab"),
        arguments: Arguments(args),
        output: .bytes(limit: 1024),
        error: .discarded
      )
      guard result.terminationStatus.isSuccess else {
        throw ValidationError("Failed to post comment via glab CLI")
      }

    case "Azure":
      // az repos pr thread create --id <id> --content "..."
      var args = [
        "repos", "pr", "thread", "create",
        "--id", prNumber,
        "--content", message,
      ]
      if let r = repo {
        args.append(contentsOf: ["--repository", r])
      }
      let result = try await Subprocess.run(
        .name("az"),
        arguments: Arguments(args),
        output: .bytes(limit: 1024),
        error: .discarded
      )
      guard result.terminationStatus.isSuccess else {
        throw ValidationError("Failed to post comment via az CLI")
      }

    default:
      throw ValidationError("Reply not supported for provider: \(provider.name)")
    }
  }
}

// MARK: - ReplyTo Subcommand

struct ReplyTo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reply-to",
    abstract: "Reply to a specific comment or thread"
  )

  @Argument(help: "PR number")
  var prNumber: String

  @Argument(help: "Comment/Thread ID (shown in view output as 'ID:' or 'Thread:')")
  var commentId: String

  @Option(name: .shortAndLong, help: "Reply message")
  var message: String?

  @Option(name: .long, help: "Translate message to language before sending")
  var translateTo: String?

  @Flag(name: .long, help: "Preview translation without sending")
  var preview: Bool = false

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?

  func run() async throws {
    // Validate comment ID
    guard !commentId.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw ValidationError("Comment ID cannot be empty")
    }

    // Get message from argument or stdin
    let replyMessage: String
    if let msg = message {
      replyMessage = msg
    } else {
      FileHandle.standardError.write(
        "Enter your reply (Ctrl+D when done):\n".data(using: .utf8)!)
      var inputLines: [String] = []
      while let line = readLine() {
        inputLines.append(line)
      }
      replyMessage = inputLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
    }

    guard !replyMessage.isEmpty else {
      throw ValidationError("Message cannot be empty")
    }

    // Translate if requested
    var finalMessage = replyMessage
    var translationIndicator = ""

    if let lang = translateTo {
      let targetLanguage = try parseLanguage(lang)

      let translator = TranslationService()
      guard await translator.isAvailable else {
        throw ValidationError("Translation unavailable on this system")
      }

      let result = try await translator.translate(replyMessage, to: targetLanguage)
      finalMessage = result.translatedText
      translationIndicator =
        "[\(result.sourceLanguage.rawValue.uppercased())→\(result.targetLanguage.rawValue.uppercased())]"

      if preview {
        print("─── Original ───")
        print(replyMessage)
        print("")
        print("─── Translated \(translationIndicator) ───")
        print(finalMessage)
        return
      }
    } else if preview {
      print("─── Preview ───")
      print(finalMessage)
      return
    }

    // Send reply to specific comment
    let factory = ProviderFactory()
    let providerType = try parseProviderType(provider)
    let prProvider = try await factory.createProvider(manualType: providerType)

    try await prProvider.replyToComment(
      prIdentifier: prNumber,
      commentId: commentId,
      body: finalMessage,
      repo: repo
    )

    if !translationIndicator.isEmpty {
      print("✅ Reply sent to comment \(commentId) \(translationIndicator)")
    } else {
      print("✅ Reply sent to comment \(commentId)")
    }
  }
}

// MARK: - Resolve Subcommand

struct Resolve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "resolve",
    abstract: "Resolve a discussion thread"
  )

  @Argument(help: "PR number")
  var prNumber: String

  @Argument(help: "Thread ID (shown in view output as 'Thread:')")
  var threadId: String

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?

  func run() async throws {
    // Validate thread ID
    guard !threadId.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw ValidationError("Thread ID cannot be empty")
    }

    let factory = ProviderFactory()
    let providerType = try parseProviderType(provider)
    let prProvider = try await factory.createProvider(manualType: providerType)

    try await prProvider.resolveThread(
      prIdentifier: prNumber,
      threadId: threadId,
      repo: repo
    )

    print("✅ Thread \(threadId) resolved")
  }
}

// MARK: - Helper Functions

private func parseLanguage(_ code: String) throws -> Language {
  guard let lang = Language(rawValue: code.lowercased()), lang != .auto else {
    let validLanguages = Language.allCases.filter { $0 != .auto }.map(\.rawValue).joined(
      separator: ", ")
    throw ValidationError("Invalid language '\(code)'. Valid: \(validLanguages)")
  }
  return lang
}

func parseProviderType(_ str: String?) throws -> ProviderType? {
  guard let str = str else { return nil }
  // Match case-insensitively against known provider names
  switch str.lowercased() {
  case "github", "gh":
    return .github
  case "gitlab", "gl":
    return .gitlab
  case "azure", "azdo", "az":
    return .azure
  default:
    throw ValidationError("Invalid provider '\(str)'. Use: github, gitlab, or azure")
  }
}
