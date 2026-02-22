import Foundation
import Logging
import MCP
import System

actor DevtoolsMCPClient {
  private struct CaptureResult: Decodable {
    let buildId: String
    let filePath: String
  }

  private let logger: Logger
  private let executable: String
  private let arguments: [String]

  private var process: Process?
  private var transport: StdioTransport?
  private var client: Client?
  private var stdinPipe: Pipe?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?

  init(
    logger: Logger,
    executable: String = "ios-dev-companion",
    arguments: [String] = ["mcp"]
  ) {
    self.logger = logger
    self.executable = executable
    self.arguments = arguments
  }

  func start() async -> Bool {
    do {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [executable] + arguments

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
        logger: Logger(label: "codex-monitor.devtools.transport")
      )

      let client = Client(name: "codex-monitor", version: "0.1.0")
      _ = try await client.connect(transport: transport)

      self.process = process
      self.transport = transport
      self.client = client
      self.stdinPipe = stdinPipe
      self.stdoutPipe = stdoutPipe
      self.stderrPipe = stderrPipe
      return true
    } catch {
      logger.warning("Devtools MCP unavailable: \(error.localizedDescription)")
      await stop()
      return false
    }
  }

  func stop() async {
    if let transport {
      await transport.disconnect()
    }

    stdinPipe?.fileHandleForWriting.closeFile()
    stdoutPipe?.fileHandleForReading.closeFile()
    stderrPipe?.fileHandleForReading.closeFile()

    if let process, process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }

    process = nil
    transport = nil
    client = nil
    stdinPipe = nil
    stdoutPipe = nil
    stderrPipe = nil
  }

  func captureScreenshot(buildId: UUID, stepIndex: Int, title: String) async throws -> String? {
    guard let client else { return nil }

    let args: [String: Value] = [
      "build_id": .string(buildId.uuidString),
      "step_index": .int(stepIndex),
      "step_title": .string(title),
    ]

    let result = try await client.callTool(name: "capture-screenshot", arguments: args)
    if result.isError == true {
      let errorText = result.content.compactMap { content -> String? in
        if case .text(let text) = content {
          return text
        }
        return nil
      }.joined(separator: "\n")
      logger.warning("Devtools MCP capture error: \(errorText)")
      return nil
    }

    guard let text = result.content.compactMap({ content -> String? in
      if case .text(let text) = content {
        return text
      }
      return nil
    }).first else {
      return nil
    }

    guard let data = text.data(using: .utf8),
          let payload = try? JSONDecoder().decode(CaptureResult.self, from: data)
    else {
      return nil
    }

    return payload.filePath
  }
}
