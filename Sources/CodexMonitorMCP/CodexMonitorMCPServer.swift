import CodexMonitorCore
import Foundation
import Logging
import MCP

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
