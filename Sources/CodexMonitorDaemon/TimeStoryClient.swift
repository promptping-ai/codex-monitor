import Foundation
import Logging
import MCP
import System

struct TimeStoryClient {
  private struct DailyStoryResponse: Decodable {
    let success: Bool?
    let message: String?
    let summary: DailySummary?
  }

  private struct DailySummary: Decodable {
    let summaryMarkdown: String?
  }

  let logger: Logger
  let executable: String

  init(logger: Logger, executable: String = "timestory") {
    self.logger = logger
    self.executable = executable
  }

  func fetchDailyStory() async -> String? {
    do {
      let payload = try await callGenerateDailyStory()
      guard let payload else { return nil }
      return extractSummary(from: payload)
    } catch {
      logger.warning("TimeStory MCP call failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func callGenerateDailyStory() async throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable]

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let transport = StdioTransport(
      input: FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor),
      output: FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor),
      logger: Logger(label: "codex-monitor.timestory.transport")
    )

    let client = Client(name: "codex-monitor", version: "0.1.0")
    _ = try await client.connect(transport: transport)

    defer {
      Task { await transport.disconnect() }
      stdinPipe.fileHandleForWriting.closeFile()
      stdoutPipe.fileHandleForReading.closeFile()
      stderrPipe.fileHandleForReading.closeFile()
      if process.isRunning {
        process.terminate()
      }
      process.waitUntilExit()
    }

    let result = try await client.callTool(name: "generate_daily_story")
    if result.isError == true {
      let errorText = result.content.compactMap { content -> String? in
        if case .text(let text) = content {
          return text
        }
        return nil
      }.joined(separator: "\n")
      logger.warning("TimeStory returned error: \(errorText)")
      return nil
    }

    return result.content.compactMap { content -> String? in
      if case .text(let text) = content {
        return text
      }
      return nil
    }.first
  }

  private func extractSummary(from json: String) -> String {
    guard let data = json.data(using: .utf8),
          let response = try? JSONDecoder().decode(DailyStoryResponse.self, from: data)
    else {
      return json
    }

    if let summary = response.summary?.summaryMarkdown, !summary.isEmpty {
      return summary
    }

    if let message = response.message, !message.isEmpty {
      return message
    }

    return json
  }
}
