import CodexMonitorCore
import Foundation
import Logging

struct BuildRunner {
  let logger: Logger
  let queries: CodexMonitorQueries

  func run(command: [String]) async throws {
    let sessionId = UUID()
    let cwd = FileManager.default.currentDirectoryPath
    let commandString = command.joined(separator: " ")

    let session = BuildSession(
      id: sessionId,
      repoId: nil,
      command: commandString,
      cwd: cwd
    )
    try await queries.createBuildSession(session)

    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()

    let reader = pipe.fileHandleForReading
    var stepIndex = 0
    let devtoolsClient = DevtoolsMCPClient(logger: logger)
    let devtoolsStarted = await devtoolsClient.start()
    var useDevtools = devtoolsStarted
    defer {
      if devtoolsStarted {
        Task { await devtoolsClient.stop() }
      }
    }

    let pattern = try NSRegularExpression(pattern: "\\[(\\d+)/(\\d+)\\]\\s+(.*)")
    while let line = reader.readLine() {
      print(line)
      if let stepTitle = Self.extractStepTitle(from: line, using: pattern) {
        stepIndex += 1
        let step = BuildStep(
          sessionId: sessionId,
          stepIndex: stepIndex,
          title: stepTitle
        )
        try await queries.addBuildStep(step)
        var screenshot: Screenshot?
        if useDevtools {
          if let filePath = try? await devtoolsClient.captureScreenshot(
            buildId: sessionId,
            stepIndex: step.stepIndex,
            title: step.title
          ) {
            screenshot = Screenshot(stepId: step.id, filePath: filePath)
          } else {
            logger.warning("Devtools MCP capture failed, falling back to local screenshots")
            useDevtools = false
          }
        }

        if screenshot == nil, let local = try? captureLocalScreenshot(sessionId: sessionId, step: step) {
          screenshot = local
        }

        if let screenshot {
          try await queries.addScreenshot(screenshot)
        }
      }
    }

    process.waitUntilExit()
  }

  private func captureLocalScreenshot(sessionId: UUID, step: BuildStep) throws -> Screenshot {
    let base = CodexMonitorDatabase.defaultDatabaseURL()
      .deletingLastPathComponent()
      .appendingPathComponent("Screenshots", isDirectory: true)
      .appendingPathComponent(sessionId.uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    let filename = String(format: "step-%03d.png", step.stepIndex)
    let fileURL = base.appendingPathComponent(filename)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", fileURL.path]
    try process.run()
    process.waitUntilExit()

    return Screenshot(stepId: step.id, filePath: fileURL.path)
  }

  private static func extractStepTitle(from line: String, using regex: NSRegularExpression) -> String? {
    let range = NSRange(location: 0, length: line.utf16.count)
    if let match = regex.firstMatch(in: line, options: [], range: range),
       match.numberOfRanges >= 4,
       let titleRange = Range(match.range(at: 3), in: line)
    {
      return String(line[titleRange])
    }

    if line.contains("Compiling") || line.contains("Linking") || line.contains("Building") {
      return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return nil
  }
}

private extension FileHandle {
  func readLine() -> String? {
    var data = Data()
    while true {
      let chunk = try? self.read(upToCount: 1)
      guard let chunk, !chunk.isEmpty else {
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
      }
      if chunk == Data([0x0A]) { // newline
        return String(decoding: data, as: UTF8.self)
      }
      data.append(chunk)
    }
  }
}
