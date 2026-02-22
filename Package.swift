// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "codex-monitor",
  platforms: [.macOS(.v26)],
  products: [
    // Backward-compatible PR comments library
    .library(
      name: "PullRequestPing",
      targets: ["PullRequestPing"]
    ),
    // New monitor core library
    .library(
      name: "CodexMonitorCore",
      targets: ["CodexMonitorCore"]
    ),
    // Optional gRPC types (placeholder for external consumers)
    .library(
      name: "CodexMonitorGRPC",
      targets: ["CodexMonitorGRPC"]
    ),
    // Legacy CLI tool (kept for compatibility)
    .executable(
      name: "pull-request-ping",
      targets: ["pull-request-ping"]
    ),
    // New monitor CLI/daemon
    .executable(
      name: "codex-monitor",
      targets: ["codex-monitor"]
    ),
    // Menu bar app (SwiftUI executable)
    .executable(
      name: "codex-monitor-app",
      targets: ["CodexMonitorApp"]
    ),
  ],
  dependencies: [
    // Modern async subprocess execution
    .package(
      url: "https://github.com/swiftlang/swift-subprocess.git",
      from: "0.1.0"
    ),
    // Markdown parsing for translation preservation
    .package(
      url: "https://github.com/swiftlang/swift-markdown.git",
      from: "0.5.0"
    ),
    // CLI argument parsing
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      from: "1.3.0"
    ),
    // Logging
    .package(
      url: "https://github.com/apple/swift-log.git",
      from: "1.6.0"
    ),
    // Service lifecycle (daemon + MCP)
    .package(
      url: "https://github.com/swift-server/swift-service-lifecycle.git",
      from: "2.9.0"
    ),
    // MCP SDK for Model Context Protocol server
    .package(
      url: "https://github.com/doozMen/swift-sdk.git",
      branch: "main"
    ),
    // SQLiteData for type-safe database access (includes GRDB)
    .package(
      url: "https://github.com/doozMen/sqlite-data.git",
      branch: "fix/ci-swift-version-matrix"
    ),
    // Local LLM for PR comment summarization (optional)
    .package(path: "../edgeprompt"),
  ],
  targets: [
    // MARK: - PullRequestPing (compat)
    .target(
      name: "PullRequestPing",
      dependencies: [
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "EdgePromptCore", package: "edgeprompt"),
      ],
      linkerSettings: [
        // Translation.framework for neural machine translation (macOS 14.4+)
        .linkedFramework("Translation", .when(platforms: [.macOS, .iOS]))
      ]
    ),

    .executableTarget(
      name: "pull-request-ping",
      dependencies: [
        "PullRequestPing",
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // MARK: - Codex Monitor Core
    .target(
      name: "CodexMonitorCore",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    .target(
      name: "CodexMonitorGRPC",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    .target(
      name: "CodexMonitorDaemon",
      dependencies: [
        "CodexMonitorCore",
        "PullRequestPing",
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    .target(
      name: "CodexMonitorMCP",
      dependencies: [
        "CodexMonitorCore",
        "CodexMonitorDaemon",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    .executableTarget(
      name: "codex-monitor",
      dependencies: [
        "CodexMonitorCore",
        "CodexMonitorDaemon",
        "CodexMonitorMCP",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    .executableTarget(
      name: "CodexMonitorApp",
      dependencies: [
        "CodexMonitorCore",
      ],
      linkerSettings: [
        .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
        .linkedFramework("AppKit", .when(platforms: [.macOS]))
      ]
    ),

    // Tests
    .testTarget(
      name: "PullRequestPingTests",
      dependencies: ["PullRequestPing"]
    ),
    .testTarget(
      name: "CodexMonitorCoreTests",
      dependencies: ["CodexMonitorCore"]
    ),
  ]
)
