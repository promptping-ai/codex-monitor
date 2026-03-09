import CodexMonitorCore
import Foundation
import Logging
import MCP
import PullRequestPing
import PullRequestPingState

public actor CodexMonitorMCPServer {
  private let logger = Logger(label: "codex-monitor.mcp")
  private let server: Server
  private let queries: CodexMonitorQueries

  public init(queries: CodexMonitorQueries) {
    self.queries = queries
    self.server = Server(
      name: "codex-monitor",
      version: "0.1.0",
      instructions: "Codex Monitor MCP server for PR checks, comments, and roadmap status.",
      capabilities: Server.Capabilities(
        tools: Server.Capabilities.Tools(listChanged: false)
      )
    )
  }

  public func start() async throws {
    await registerHandlers()
    let transport = StdioTransport(logger: Logger(label: "codex-monitor.mcp.transport"))
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
  }

  private func registerHandlers() async {
    await server.withMethodHandler(ListTools.self) { [weak self] _ in
      guard let self else { throw MCPError.internalError("Server unavailable") }
      return ListTools.Result(tools: self.toolDefinitions())
    }

    await server.withMethodHandler(CallTool.self) { [weak self] params in
      guard let self else { throw MCPError.internalError("Server unavailable") }
      return try await self.handleToolCall(params)
    }
  }

  private nonisolated func toolDefinitions() -> [Tool] {
    [
      Tool(
        name: "list_unresolved_checks",
        description: "List failing or pending check runs.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "limit": .object([
              "type": .string("integer"),
              "description": .string("Maximum number of checks to return")
            ])
          ])
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "list_unresolved_comments",
        description: "List unresolved PR comments.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "limit": .object([
              "type": .string("integer"),
              "description": .string("Maximum number of comments to return")
            ])
          ])
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "get_daily_context",
        description: "Return the latest daily context from TimeStory.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([:])
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "get_roadmap_summary",
        description: "Summarize repos by roadmap project mapping.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([:])
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "list_fix_suggestions",
        description: "List pending fix suggestions.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "limit": .object([
              "type": .string("integer"),
              "description": .string("Maximum number of suggestions to return")
            ])
          ])
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "approve_fix",
        description: "Approve a fix suggestion by ID.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "id": .object([
              "type": .string("string"),
              "description": .string("Fix suggestion UUID")
            ])
          ]),
          "required": .array([.string("id")])
        ]),
        annotations: Tool.Annotations(readOnlyHint: false)
      ),
      Tool(
        name: "submit_review",
        description:
          "Submit a PR review with decision, summary, and optional inline comments.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "pr_identifier": .object([
              "type": .string("string"),
              "description": .string("PR number or identifier"),
            ]),
            "decision": .object([
              "type": .string("string"),
              "description": .string(
                "Review decision: approve, request-changes, or comment"),
            ]),
            "summary": .object([
              "type": .string("string"),
              "description": .string("Review summary body (markdown supported)"),
            ]),
            "comments": .object([
              "type": .string("array"),
              "description": .string(
                "Inline comments array, each with path, line, and body"),
              "items": .object([
                "type": .string("object"),
                "properties": .object([
                  "path": .object([
                    "type": .string("string"),
                    "description": .string("File path relative to repo root"),
                  ]),
                  "line": .object([
                    "type": .string("integer"),
                    "description": .string("Line number in the new file"),
                  ]),
                  "body": .object([
                    "type": .string("string"),
                    "description": .string("Comment body"),
                  ]),
                ]),
                "required": .array([
                  .string("path"), .string("line"), .string("body"),
                ]),
              ]),
            ]),
            "repo": .object([
              "type": .string("string"),
              "description": .string("Repository (owner/repo), auto-detected if omitted"),
            ]),
          ]),
          "required": .array([
            .string("pr_identifier"), .string("decision"), .string("summary"),
          ]),
        ]),
        annotations: Tool.Annotations(readOnlyHint: false)
      ),

      // MARK: - Statusline tools (migrated from claude-statusline-mcp)
      Tool(
        name: "push_plan_subject",
        description:
          "Set the current plan subject to display in the statusline. This appears in Line 1 next to the project name.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "subject": .object([
              "type": .string("string"),
              "description": .string(
                "The plan subject/title to display (e.g., 'Implementing auth flow')"),
            ]),
            "project_path": .object([
              "type": .string("string"),
              "description": .string("Optional: The project path this plan is for"),
            ]),
          ]),
          "required": .array([.string("subject")]),
        ])
      ),
      Tool(
        name: "push_status_message",
        description:
          "Add a custom status message to Line 2 of the statusline. Useful for showing current task or agent status.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "message": .object([
              "type": .string("string"),
              "description": .string(
                "The status message to display (e.g., 'Running tests...', 'Building...')"),
            ]),
            "project_path": .object([
              "type": .string("string"),
              "description": .string("Optional: The project path this status is for"),
            ]),
          ]),
          "required": .array([.string("message")]),
        ])
      ),
      Tool(
        name: "get_statusline",
        description:
          "Retrieve the current 3-line statusline output. Returns the formatted status including project, plan, PR info, and Graphite stack.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "project_path": .object([
              "type": .string("string"),
              "description": .string(
                "The project path to get status for (defaults to current directory)"),
            ])
          ]),
        ]),
        annotations: Tool.Annotations(readOnlyHint: true)
      ),
      Tool(
        name: "invalidate_cache",
        description:
          "Force a refresh of cached PR data. Use this after making changes that should be reflected in the statusline (e.g., pushing commits, creating PRs).",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "project_path": .object([
              "type": .string("string"),
              "description": .string("Optional: Specific project path to invalidate cache for"),
            ])
          ]),
        ])
      ),
    ]
  }

  private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
    switch params.name {
    case "list_unresolved_checks":
      let limit = params.arguments?["limit"]?.intValue ?? 50
      let checks = try await queries.failingChecks(limit: limit)
      return CallTool.Result(content: [
        .text(try encodeJSON(checks))
      ])

    case "list_unresolved_comments":
      let limit = params.arguments?["limit"]?.intValue ?? 50
      let comments = try await queries.unresolvedComments(limit: limit)
      return CallTool.Result(content: [
        .text(try encodeJSON(comments))
      ])

    case "get_daily_context":
      let context = try await queries.latestDailyContext()
      return CallTool.Result(content: [
        .text(try encodeJSON(context))
      ])

    case "get_roadmap_summary":
      let summary = try await queries.roadmapSummary()
      return CallTool.Result(content: [
        .text(try encodeJSON(summary))
      ])

    case "list_fix_suggestions":
      let limit = params.arguments?["limit"]?.intValue ?? 50
      let suggestions = try await queries.pendingFixSuggestions(limit: limit)
      return CallTool.Result(content: [
        .text(try encodeJSON(suggestions))
      ])

    case "approve_fix":
      guard let idValue = params.arguments?["id"]?.stringValue,
            let id = UUID(uuidString: idValue)
      else {
        throw MCPError.invalidRequest("Invalid id")
      }
      try await queries.approveFixSuggestion(id: id)
      return CallTool.Result(content: [
        .text("{\"status\":\"approved\",\"id\":\"\(id.uuidString)\"}")
      ])

    case "submit_review":
      guard let prIdentifier = params.arguments?["pr_identifier"]?.stringValue else {
        throw MCPError.invalidRequest("Missing pr_identifier")
      }
      guard let decisionRaw = params.arguments?["decision"]?.stringValue else {
        throw MCPError.invalidRequest("Missing decision")
      }
      guard let summary = params.arguments?["summary"]?.stringValue else {
        throw MCPError.invalidRequest("Missing summary")
      }

      // Parse decision
      let decision: ReviewDecision
      switch decisionRaw.lowercased() {
      case "approve":
        decision = .approve
      case "request-changes", "request_changes", "changes":
        decision = .requestChanges
      case "comment":
        decision = .comment
      default:
        throw MCPError.invalidRequest(
          "Invalid decision '\(decisionRaw)'. Use: approve, request-changes, or comment")
      }

      // Parse inline comments
      var lineComments: [ReviewLineComment] = []
      if case .array(let commentArray) = params.arguments?["comments"] {
        for item in commentArray {
          if case .object(let obj) = item,
            let path = obj["path"]?.stringValue,
            let line = obj["line"]?.intValue,
            let body = obj["body"]?.stringValue
          {
            lineComments.append(ReviewLineComment(path: path, line: line, body: body))
          }
        }
      }

      let repo = params.arguments?["repo"]?.stringValue

      // Create provider and submit
      let factory = ProviderFactory()
      let provider = try await factory.createProvider()
      let submission = ReviewSubmission(
        decision: decision,
        summary: summary,
        comments: lineComments
      )
      let result = try await provider.submitReview(
        prIdentifier: prIdentifier,
        submission: submission,
        repo: repo
      )
      return CallTool.Result(content: [
        .text(try encodeJSON(result))
      ])

    // MARK: - Statusline tools

    case "push_plan_subject":
      guard let subject = params.arguments?["subject"]?.stringValue else {
        throw MCPError.invalidRequest("Missing required parameter: subject")
      }
      let projectPath = params.arguments?["project_path"]?.stringValue
      await SessionState.shared.load()
      await SessionState.shared.setPlanSubject(subject, projectPath: projectPath)
      await SessionState.shared.save()
      return CallTool.Result(content: [
        .text("Plan subject set to: \(subject)")
      ])

    case "push_status_message":
      guard let message = params.arguments?["message"]?.stringValue else {
        throw MCPError.invalidRequest("Missing required parameter: message")
      }
      let projectPath = params.arguments?["project_path"]?.stringValue
      await SessionState.shared.load()
      await SessionState.shared.setCustomStatusMessage(message, projectPath: projectPath)
      await SessionState.shared.save()
      return CallTool.Result(content: [
        .text("Status message set to: \(message)")
      ])

    case "get_statusline":
      let projectPath =
        params.arguments?["project_path"]?.stringValue
        ?? FileManager.default.currentDirectoryPath
      await SessionState.shared.load()
      let state = await SessionState.shared.get()
      var lines: [String] = []
      let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
      var line1Parts = [projectName]
      if let planSubject = state?.planSubject {
        line1Parts.append("📋 \(planSubject)")
      }
      lines.append(line1Parts.joined(separator: " │ "))
      if let customMessage = state?.customStatusMessage {
        lines.append("  \(customMessage)")
      }
      if let updatedAt = state?.updatedAt {
        let formatter = ISO8601DateFormatter()
        lines.append("  Last updated: \(formatter.string(from: updatedAt))")
      }
      return CallTool.Result(content: [
        .text(lines.joined(separator: "\n"))
      ])

    case "invalidate_cache":
      await PRCache.shared.load()
      await PRCache.shared.clear()
      await PRCache.shared.save()
      await SessionState.shared.invalidate()
      return CallTool.Result(content: [
        .text("Cache invalidated successfully. Next statusline update will fetch fresh data.")
      ])

    default:
      throw MCPError.methodNotFound("Unknown tool: \(params.name)")
    }
  }

  private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }
}
