import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

/// Helper for executing CLI commands
public struct CLIHelper: Sendable {
  public init() {}

  /// Find an executable by name
  public func findExecutable(name: String) async throws -> Subprocess.Executable {
    // Try common paths
    let commonPaths = [
      "/usr/local/bin/\(name)",
      "/opt/homebrew/bin/\(name)",
      "/usr/bin/\(name)",
    ]

    for path in commonPaths {
      if FileManager.default.fileExists(atPath: path) {
        return .path(FilePath(path))
      }
    }

    // Try using `which`
    let whichResult = try await Subprocess.run(
      .name("which"),
      arguments: Arguments([name]),
      output: .bytes(limit: 1024),
      error: .discarded
    )

    if whichResult.terminationStatus.isSuccess {
      let path = String(decoding: whichResult.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !path.isEmpty {
        return .path(FilePath(path))
      }
    }

    throw PRProviderError.cliNotFound(name)
  }

  /// Execute a command and return stdout
  /// Note: Timeout handling would require Task.withTimeout wrapper (future enhancement)
  public func execute(
    executable: Subprocess.Executable,
    arguments: [String]
  ) async throws -> [UInt8] {
    let result = try await Subprocess.run(
      executable,
      arguments: Arguments(arguments),
      output: .bytes(limit: 10 * 1024 * 1024),  // 10MB limit
      error: .bytes(limit: 1024 * 1024)  // 1MB limit
    )

    guard result.terminationStatus.isSuccess else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
      throw PRProviderError.commandFailed(arguments.joined(separator: " "), stderr: stderr)
    }

    return result.standardOutput
  }

  /// Check if a CLI tool exists
  public func isInstalled(_ name: String) async -> Bool {
    do {
      _ = try await findExecutable(name: name)
      return true
    } catch {
      return false
    }
  }

  /// Get git remote URL for current repository
  public func getGitRemoteURL() async throws -> String {
    let gitPath = try await findExecutable(name: "git")
    let output = try await execute(
      executable: gitPath,
      arguments: ["config", "--get", "remote.origin.url"]
    )
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Execute a command with stdin input and return stdout
  public func execute(
    executable: Subprocess.Executable,
    arguments: [String],
    stdin stdinBytes: [UInt8]
  ) async throws -> [UInt8] {
    let result = try await Subprocess.run(
      executable,
      arguments: Arguments(arguments),
      input: .bytes(stdinBytes),
      output: .bytes(limit: 10 * 1024 * 1024),
      error: .bytes(limit: 1024 * 1024)
    )

    guard result.terminationStatus.isSuccess else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
      throw PRProviderError.commandFailed(arguments.joined(separator: " "), stderr: stderr)
    }

    return result.standardOutput
  }

  // MARK: - GraphQL Support

  /// Execute a GraphQL query/mutation via `gh api graphql`
  ///
  /// Uses GitHub's GraphQL API through the `gh` CLI, which handles authentication automatically.
  ///
  /// - Parameters:
  ///   - query: The GraphQL query or mutation string
  ///   - variables: Optional dictionary of variables to pass to the query
  /// - Returns: The raw JSON response bytes
  /// - Throws: `PRProviderError.commandFailed` if the command fails
  public func executeGraphQL(
    query: String,
    variables: [String: Any]? = nil
  ) async throws -> [UInt8] {
    let ghPath = try await findExecutable(name: "gh")

    var args = ["api", "graphql", "-f", "query=\(query)"]

    // Add variables as -F flags (gh handles JSON encoding)
    if let variables = variables {
      for (key, value) in variables {
        // Use -F for non-string values (numbers, booleans) and -f for strings
        if let stringValue = value as? String {
          args.append(contentsOf: ["-f", "\(key)=\(stringValue)"])
        } else if let intValue = value as? Int {
          args.append(contentsOf: ["-F", "\(key)=\(intValue)"])
        } else if let boolValue = value as? Bool {
          args.append(contentsOf: ["-F", "\(key)=\(boolValue)"])
        } else {
          // For complex types, JSON encode
          let jsonData = try JSONSerialization.data(withJSONObject: value)
          let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
          args.append(contentsOf: ["-f", "\(key)=\(jsonString)"])
        }
      }
    }

    return try await execute(executable: ghPath, arguments: args)
  }
}
