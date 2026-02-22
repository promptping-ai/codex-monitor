import Foundation
import SQLiteData

public final class CodexMonitorQueries: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func upsertRepo(_ repo: Repo) async throws {
    try await database.write { db in
      try Repo.where { $0.id == repo.id }.delete().execute(db)
      try Repo.insert { Repo.Draft(repo) }.execute(db)
    }
  }

  public func upsertPullRequest(_ pr: PullRequestRecord) async throws {
    try await database.write { db in
      try PullRequestRecord.where { $0.id == pr.id }.delete().execute(db)
      try PullRequestRecord.insert { PullRequestRecord.Draft(pr) }.execute(db)
    }
  }

  public func replaceChecks(for prId: UUID, checks: [CheckRun]) async throws {
    try await database.write { db in
      try CheckRun.where { $0.prId == prId }.delete().execute(db)
      if !checks.isEmpty {
        try CheckRun.insert { checks.map { CheckRun.Draft($0) } }.execute(db)
      }
    }
  }

  public func replaceComments(for prId: UUID, comments: [PRComment]) async throws {
    try await database.write { db in
      try PRComment.where { $0.prId == prId }.delete().execute(db)
      if !comments.isEmpty {
        try PRComment.insert { comments.map { PRComment.Draft($0) } }.execute(db)
      }
    }
  }

  public func saveDailyContext(_ context: DailyContext) async throws {
    try await database.write { db in
      try DailyContext.insert { DailyContext.Draft(context) }.execute(db)
    }
  }

  public func upsertRoadmapMapping(_ mapping: RoadmapMapping) async throws {
    try await database.write { db in
      try RoadmapMapping.where { $0.repoId == mapping.repoId }.delete().execute(db)
      try RoadmapMapping.insert { RoadmapMapping.Draft(mapping) }.execute(db)
    }
  }

  public func replacePendingFixSuggestions(
    for prId: UUID,
    suggestions: [FixSuggestion]
  ) async throws {
    try await database.write { db in
      try FixSuggestion
        .where { $0.prId == prId && $0.status == "pending" }
        .delete()
        .execute(db)

      if !suggestions.isEmpty {
        try FixSuggestion.insert { suggestions.map { FixSuggestion.Draft($0) } }.execute(db)
      }
    }
  }

  public func pendingFixSuggestions(limit: Int = 50) async throws -> [FixSuggestion] {
    try await database.read { db in
      try FixSuggestion
        .where { $0.status == "pending" }
        .order { $0.createdAt.desc() }
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func approveFixSuggestion(id: UUID) async throws {
    try await database.write { db in
      try FixSuggestion
        .where { $0.id == id }
        .update { draft in
          draft.status = "approved"
        }
        .execute(db)
    }
  }

  public func failingChecks(limit: Int = 50) async throws -> [CheckRun] {
    try await database.read { db in
      try CheckRun
        .where { $0.conclusion != "success" }
        .order { $0.updatedAt.desc() }
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func unresolvedComments(limit: Int = 50) async throws -> [PRComment] {
    try await database.read { db in
      try PRComment
        .where { $0.isResolved == false }
        .order { $0.updatedAt.desc() }
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func latestDailyContext() async throws -> DailyContext? {
    try await database.read { db in
      try DailyContext
        .order { $0.date.desc() }
        .limit(1)
        .fetchOne(db)
    }
  }

  public func roadmapSummary() async throws -> [RoadmapSummary] {
    try await database.read { db in
      let mappings = try RoadmapMapping.fetchAll(db)
      let repos = try Repo.fetchAll(db)
      let prs = try PullRequestRecord.fetchAll(db)
      let checks = try CheckRun.fetchAll(db)
      let comments = try PRComment.fetchAll(db)

      let repoIds = Set(mappings.map { $0.repoId })
      let repoLookup = Dictionary(uniqueKeysWithValues: repos.map { ($0.id, $0) })
      let mappingLookup = Dictionary(uniqueKeysWithValues: mappings.map { ($0.repoId, $0) })

      var summaries: [String: RoadmapSummary] = [:]
      for mapping in mappings {
        summaries[mapping.projectId, default: RoadmapSummary(
          projectId: mapping.projectId,
          projectName: mapping.projectName,
          repoCount: 0,
          openPullRequestCount: 0,
          failingCheckCount: 0,
          unresolvedCommentCount: 0
        )].repoCount += 1
      }

      let prRepoLookup: [UUID: UUID] = Dictionary(uniqueKeysWithValues: prs.map { ($0.id, $0.repoId) })

      for pr in prs where repoIds.contains(pr.repoId) {
        if let mapping = mappingLookup[pr.repoId] {
          summaries[mapping.projectId]?.openPullRequestCount += 1
        }
      }

      for check in checks where (check.conclusion?.lowercased() ?? "unknown") != "success" {
        guard let repoId = prRepoLookup[check.prId],
              let mapping = mappingLookup[repoId],
              repoLookup[repoId] != nil
        else { continue }
        summaries[mapping.projectId]?.failingCheckCount += 1
      }

      for comment in comments where !comment.isResolved {
        guard let repoId = prRepoLookup[comment.prId],
              let mapping = mappingLookup[repoId],
              repoLookup[repoId] != nil
        else { continue }
        summaries[mapping.projectId]?.unresolvedCommentCount += 1
      }

      return summaries.values.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
    }
  }

  public func createBuildSession(_ session: BuildSession) async throws {
    try await database.write { db in
      try BuildSession.insert { BuildSession.Draft(session) }.execute(db)
    }
  }

  public func addBuildStep(_ step: BuildStep) async throws {
    try await database.write { db in
      try BuildStep.insert { BuildStep.Draft(step) }.execute(db)
    }
  }

  public func addScreenshot(_ screenshot: Screenshot) async throws {
    try await database.write { db in
      try Screenshot.insert { Screenshot.Draft(screenshot) }.execute(db)
    }
  }

  public func latestBuildTimeline(limit: Int = 6) async throws -> [BuildStepTimelineEntry] {
    try await database.read { db in
      let session = try BuildSession
        .order { draft in draft.startedAt.desc() }
        .limit(1)
        .fetchOne(db)
      guard let session else { return [] }

      let steps = try BuildStep
        .where { $0.sessionId == session.id }
        .order { draft in draft.stepIndex.asc() }
        .limit(limit)
        .fetchAll(db)

      let stepIds = Set(steps.map { $0.id })
      let screenshots = try Screenshot.fetchAll(db)
      let filtered = screenshots.filter { stepIds.contains($0.stepId) }
      let screenshotLookup = Dictionary(uniqueKeysWithValues: filtered.map { ($0.stepId, $0) })

      return steps.map { step in
        BuildStepTimelineEntry(
          stepId: step.id,
          sessionId: step.sessionId,
          stepIndex: step.stepIndex,
          title: step.title,
          timestamp: step.timestamp,
          screenshotPath: screenshotLookup[step.id]?.filePath
        )
      }
    }
  }
}
