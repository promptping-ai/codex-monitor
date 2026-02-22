import Foundation
import SQLiteData

@Table("repo")
public struct Repo: Codable, Sendable {
  public let id: UUID
  public var name: String
  public var path: String
  public var org: String?
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    path: String,
    org: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.org = org
    self.updatedAt = updatedAt
  }
}

@Table("pullRequest")
public struct PullRequestRecord: Codable, Sendable {
  public let id: UUID
  public var repoId: UUID
  public var number: Int
  public var title: String
  public var author: String?
  public var url: String
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    repoId: UUID,
    number: Int,
    title: String,
    author: String? = nil,
    url: String,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.repoId = repoId
    self.number = number
    self.title = title
    self.author = author
    self.url = url
    self.updatedAt = updatedAt
  }
}

@Table("checkRun")
public struct CheckRun: Codable, Sendable {
  public let id: UUID
  public var prId: UUID
  public var name: String
  public var status: String
  public var conclusion: String?
  public var detailsUrl: String?
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    prId: UUID,
    name: String,
    status: String,
    conclusion: String? = nil,
    detailsUrl: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.prId = prId
    self.name = name
    self.status = status
    self.conclusion = conclusion
    self.detailsUrl = detailsUrl
    self.updatedAt = updatedAt
  }
}

@Table("comment")
public struct PRComment: Codable, Sendable {
  public let id: UUID
  public var prId: UUID
  public var commentId: String
  public var author: String
  public var body: String
  public var url: String
  public var isResolved: Bool
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    prId: UUID,
    commentId: String,
    author: String,
    body: String,
    url: String,
    isResolved: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.prId = prId
    self.commentId = commentId
    self.author = author
    self.body = body
    self.url = url
    self.isResolved = isResolved
    self.updatedAt = updatedAt
  }
}

@Table("roadmapMapping")
public struct RoadmapMapping: Codable, Sendable {
  public let id: UUID
  public var repoId: UUID
  public var projectId: String
  public var projectName: String
  public var statusOptionId: String?
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    repoId: UUID,
    projectId: String,
    projectName: String,
    statusOptionId: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.repoId = repoId
    self.projectId = projectId
    self.projectName = projectName
    self.statusOptionId = statusOptionId
    self.updatedAt = updatedAt
  }
}

public struct RoadmapSummary: Codable, Sendable {
  public let projectId: String
  public let projectName: String
  public var repoCount: Int
  public var openPullRequestCount: Int
  public var failingCheckCount: Int
  public var unresolvedCommentCount: Int

  public init(
    projectId: String,
    projectName: String,
    repoCount: Int,
    openPullRequestCount: Int,
    failingCheckCount: Int,
    unresolvedCommentCount: Int
  ) {
    self.projectId = projectId
    self.projectName = projectName
    self.repoCount = repoCount
    self.openPullRequestCount = openPullRequestCount
    self.failingCheckCount = failingCheckCount
    self.unresolvedCommentCount = unresolvedCommentCount
  }
}

@Table("buildSession")
public struct BuildSession: Codable, Sendable {
  public let id: UUID
  public var repoId: UUID?
  public var command: String
  public var cwd: String
  public var startedAt: Date

  public init(
    id: UUID = UUID(),
    repoId: UUID? = nil,
    command: String,
    cwd: String,
    startedAt: Date = Date()
  ) {
    self.id = id
    self.repoId = repoId
    self.command = command
    self.cwd = cwd
    self.startedAt = startedAt
  }
}

@Table("buildStep")
public struct BuildStep: Codable, Sendable {
  public let id: UUID
  public var sessionId: UUID
  public var stepIndex: Int
  public var title: String
  public var timestamp: Date

  public init(
    id: UUID = UUID(),
    sessionId: UUID,
    stepIndex: Int,
    title: String,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.sessionId = sessionId
    self.stepIndex = stepIndex
    self.title = title
    self.timestamp = timestamp
  }
}

@Table("screenshot")
public struct Screenshot: Codable, Sendable {
  public let id: UUID
  public var stepId: UUID
  public var filePath: String
  public var thumbnailPath: String?
  public var capturedAt: Date

  public init(
    id: UUID = UUID(),
    stepId: UUID,
    filePath: String,
    thumbnailPath: String? = nil,
    capturedAt: Date = Date()
  ) {
    self.id = id
    self.stepId = stepId
    self.filePath = filePath
    self.thumbnailPath = thumbnailPath
    self.capturedAt = capturedAt
  }
}

public struct BuildStepTimelineEntry: Codable, Sendable {
  public let stepId: UUID
  public let sessionId: UUID
  public var stepIndex: Int
  public var title: String
  public var timestamp: Date
  public var screenshotPath: String?

  public init(
    stepId: UUID,
    sessionId: UUID,
    stepIndex: Int,
    title: String,
    timestamp: Date,
    screenshotPath: String?
  ) {
    self.stepId = stepId
    self.sessionId = sessionId
    self.stepIndex = stepIndex
    self.title = title
    self.timestamp = timestamp
    self.screenshotPath = screenshotPath
  }
}

@Table("dailyContext")
public struct DailyContext: Codable, Sendable {
  public let id: UUID
  public var date: Date
  public var summaryMarkdown: String
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    date: Date,
    summaryMarkdown: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.date = date
    self.summaryMarkdown = summaryMarkdown
    self.createdAt = createdAt
  }
}

@Table("fixSuggestion")
public struct FixSuggestion: Codable, Sendable {
  public let id: UUID
  public var prId: UUID
  public var summary: String
  public var severity: String
  public var recommendedAction: String
  public var status: String
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    prId: UUID,
    summary: String,
    severity: String,
    recommendedAction: String,
    status: String = "pending",
    createdAt: Date = Date()
  ) {
    self.id = id
    self.prId = prId
    self.summary = summary
    self.severity = severity
    self.recommendedAction = recommendedAction
    self.status = status
    self.createdAt = createdAt
  }
}

@Table("notification")
public struct NotificationRecord: Codable, Sendable {
  public let id: UUID
  public var type: String
  public var severity: String
  public var message: String
  public var createdAt: Date
  public var handledAt: Date?

  public init(
    id: UUID = UUID(),
    type: String,
    severity: String,
    message: String,
    createdAt: Date = Date(),
    handledAt: Date? = nil
  ) {
    self.id = id
    self.type = type
    self.severity = severity
    self.message = message
    self.createdAt = createdAt
    self.handledAt = handledAt
  }
}
