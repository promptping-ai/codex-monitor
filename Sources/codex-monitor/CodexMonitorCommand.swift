import ArgumentParser
import CodexMonitorCore
import CodexMonitorDaemon
import CodexMonitorMCP
import Foundation
import Logging

@main
struct CodexMonitorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "codex-monitor",
    abstract: "Monitor PR checks, comments, and roadmap alignment.",
    subcommands: [Monitor.self, MCPServer.self, Build.self],
    defaultSubcommand: Monitor.self
  )
}

struct Monitor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "monitor",
    abstract: "Run the codex monitor daemon"
  )

  @Flag(name: .long, help: "Run once and exit")
  var once: Bool = false

  @Option(name: .long, help: "Polling interval in minutes")
  var interval: Int = 15

  @Option(name: .long, help: "Path to config.json")
  var config: String?

  func run() async throws {
    let configURL = config.map { URL(fileURLWithPath: $0) }
    let loadedConfig = try CodexMonitorConfig.load(from: configURL)
    let database = try CodexMonitorDatabase.open()
    let daemon = CodexMonitorDaemon(config: loadedConfig, database: database)

    if once {
      await daemon.runOnce()
    } else {
      await daemon.run(intervalMinutes: interval)
    }
  }
}

struct MCPServer: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Run the MCP server for Codex Monitor"
  )

  @Option(name: .long, help: "Path to config.json")
  var config: String?

  func run() async throws {
    let _ = try CodexMonitorConfig.load(from: config.map { URL(fileURLWithPath: $0) })
    let database = try CodexMonitorDatabase.open()
    let queries = CodexMonitorQueries(database: database.writer)
    let server = CodexMonitorMCPServer(queries: queries)
    try await server.start()
  }
}

struct Build: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
    abstract: "Run a build command and capture step screenshots"
  )

  @Argument(parsing: .captureForPassthrough, help: "Command to execute")
  var command: [String] = []

  func run() async throws {
    guard !command.isEmpty else {
      throw ValidationError("Provide a build command after --")
    }

    let database = try CodexMonitorDatabase.open()
    let queries = CodexMonitorQueries(database: database.writer)
    let runner = BuildRunner(logger: Logger(label: "codex-monitor.build"), queries: queries)
    try await runner.run(command: command)
  }
}
