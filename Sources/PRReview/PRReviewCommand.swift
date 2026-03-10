import ArgumentParser

@main
struct PRReviewCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pr-review",
    abstract: "Post inline comments and request changes on pull requests.",
    subcommands: [InlineCommand.self, RequestChangesCommand.self]
  )
}
