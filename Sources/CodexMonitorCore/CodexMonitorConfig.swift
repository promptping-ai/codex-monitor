import Foundation

public struct CodexMonitorConfig: Codable, Sendable {
  public var repoRoots: [String]
  public var projectMapping: ProjectMapping
  public var notifications: NotificationConfig
  public var llmScoring: LLMScoringConfig?

  public init(
    repoRoots: [String] = ["~/Developer/promptping-ai"],
    projectMapping: ProjectMapping = .default,
    notifications: NotificationConfig = .default,
    llmScoring: LLMScoringConfig? = nil
  ) {
    self.repoRoots = repoRoots
    self.projectMapping = projectMapping
    self.notifications = notifications
    self.llmScoring = llmScoring
  }

  public static var `default`: CodexMonitorConfig {
    CodexMonitorConfig()
  }

  public static func load(from url: URL? = nil) throws -> CodexMonitorConfig {
    let configURL = url ?? defaultConfigURL()
    if FileManager.default.fileExists(atPath: configURL.path) {
      let data = try Data(contentsOf: configURL)
      return try JSONDecoder().decode(CodexMonitorConfig.self, from: data)
    }

    return .default
  }

  public static func defaultConfigURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
      .appendingPathComponent(".codex-monitor", isDirectory: true)
      .appendingPathComponent("config.json")
  }

  public func save(to url: URL? = nil) throws {
    let configURL = url ?? Self.defaultConfigURL()
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(self)
    try data.write(to: configURL, options: .atomic)
  }
}

public struct ProjectMapping: Codable, Sendable {
  public var corporateRoots: [String]
  public var clientRootBase: String
  public var project3Id: String
  public var project4Id: String
  public var project3Name: String
  public var project4Name: String

  public init(
    corporateRoots: [String],
    clientRootBase: String,
    project3Id: String,
    project4Id: String,
    project3Name: String,
    project4Name: String
  ) {
    self.corporateRoots = corporateRoots
    self.clientRootBase = clientRootBase
    self.project3Id = project3Id
    self.project4Id = project4Id
    self.project3Name = project3Name
    self.project4Name = project4Name
  }

  public static let `default` = ProjectMapping(
    corporateRoots: ["~/Developer/promptping-ai"],
    clientRootBase: "~/Developer",
    project3Id: "PVT_kwDODtlhAc4BKpro",
    project4Id: "PVT_kwDODtlhAc4BMY-w",
    project3Name: "promptping-marketplace launch",
    project4Name: "Vente Publique - Roadmap"
  )
}

public struct NotificationConfig: Codable, Sendable {
  public var minSeverity: String
  public var notifyOnFailures: Bool
  public var notifyOnNewComments: Bool

  public init(
    minSeverity: String,
    notifyOnFailures: Bool,
    notifyOnNewComments: Bool
  ) {
    self.minSeverity = minSeverity
    self.notifyOnFailures = notifyOnFailures
    self.notifyOnNewComments = notifyOnNewComments
  }

  public static let `default` = NotificationConfig(
    minSeverity: "medium",
    notifyOnFailures: true,
    notifyOnNewComments: true
  )
}

public struct LLMScoringConfig: Codable, Sendable {
  public var enabled: Bool
  public var provider: String

  public init(enabled: Bool, provider: String) {
    self.enabled = enabled
    self.provider = provider
  }
}
