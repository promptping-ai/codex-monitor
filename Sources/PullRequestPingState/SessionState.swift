import Foundation

// MARK: - Session State Model

/// Session state data for cloud AI agents to communicate with the statusline
public struct SessionStateData: Codable, Sendable {
  public var planSubject: String?
  public var customStatusMessage: String?
  public var sessionId: String?
  public var projectPath: String?
  public let updatedAt: Date

  public init(
    planSubject: String? = nil,
    customStatusMessage: String? = nil,
    sessionId: String? = nil,
    projectPath: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.planSubject = planSubject
    self.customStatusMessage = customStatusMessage
    self.sessionId = sessionId
    self.projectPath = projectPath
    self.updatedAt = updatedAt
  }
}

// MARK: - Session State Manager

/// Thread-safe session state manager for MCP tools and CLI to share state
/// Uses actor isolation to prevent data races
///
/// Cloud AI agents can push state via MCP tools, and the CLI reads it
/// to display in the statusline.
public actor SessionState {
  public static let shared = SessionState()

  /// TTL for session state (10 minutes - sessions are long-lived)
  public let stateTTL: TimeInterval

  private let stateURL: URL
  private var state: SessionStateData?
  private var isLoaded = false

  /// Create a session state instance
  /// - Parameter stateTTL: How long state remains valid. Default 600s (10 minutes).
  public init(stateTTL: TimeInterval = 600) {
    self.stateTTL = stateTTL
    // Store in ~/.cache/claude-statusline/ for backward compat
    let cacheDir =
      FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/claude-statusline")
    self.stateURL = cacheDir.appendingPathComponent("session-state.json")
  }

  // MARK: - Public API

  /// Get the current session state if valid
  public func get() -> SessionStateData? {
    guard let state = state else { return nil }

    let age = Date().timeIntervalSince(state.updatedAt)
    if age > stateTTL {
      return nil
    }
    return state
  }

  /// Get the plan subject from session state
  public func getPlanSubject() -> String? {
    get()?.planSubject
  }

  /// Get the custom status message from session state
  public func getCustomStatusMessage() -> String? {
    get()?.customStatusMessage
  }

  /// Set the plan subject (called from MCP tool)
  public func setPlanSubject(_ subject: String?, projectPath: String? = nil) {
    var newState = state ?? SessionStateData()
    newState = SessionStateData(
      planSubject: subject,
      customStatusMessage: newState.customStatusMessage,
      sessionId: newState.sessionId,
      projectPath: projectPath ?? newState.projectPath,
      updatedAt: Date()
    )
    state = newState
  }

  /// Set a custom status message (called from MCP tool)
  public func setCustomStatusMessage(_ message: String?, projectPath: String? = nil) {
    var newState = state ?? SessionStateData()
    newState = SessionStateData(
      planSubject: newState.planSubject,
      customStatusMessage: message,
      sessionId: newState.sessionId,
      projectPath: projectPath ?? newState.projectPath,
      updatedAt: Date()
    )
    state = newState
  }

  /// Update session ID
  public func setSessionId(_ sessionId: String?) {
    var newState = state ?? SessionStateData()
    newState = SessionStateData(
      planSubject: newState.planSubject,
      customStatusMessage: newState.customStatusMessage,
      sessionId: sessionId,
      projectPath: newState.projectPath,
      updatedAt: Date()
    )
    state = newState
  }

  /// Clear all session state
  public func clear() {
    state = nil
  }

  // MARK: - Persistence

  /// Load state from disk
  public func load() {
    guard !isLoaded else { return }
    isLoaded = true

    guard FileManager.default.fileExists(atPath: stateURL.path) else { return }

    do {
      let data = try Data(contentsOf: stateURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      state = try decoder.decode(SessionStateData.self, from: data)
    } catch {
      FileHandle.standardError.write(
        Data("[SESSION] Failed to load state: \(error)\n".utf8)
      )
    }
  }

  /// Save state to disk
  public func save() {
    guard let state = state else { return }

    do {
      let cacheDir = stateURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: cacheDir,
        withIntermediateDirectories: true
      )

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(state)
      try data.write(to: stateURL)
    } catch {
      FileHandle.standardError.write(
        Data("[SESSION] Failed to save state: \(error)\n".utf8)
      )
    }
  }

  /// Invalidate cache (clear state and delete file)
  public func invalidate() {
    state = nil
    try? FileManager.default.removeItem(at: stateURL)
  }
}
