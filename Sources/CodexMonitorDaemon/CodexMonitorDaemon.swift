import CodexMonitorCore
import Foundation
import Logging
import PullRequestPing

public struct CodexMonitorDaemon {
  private let logger: Logger
  private let config: CodexMonitorConfig
  private let database: CodexMonitorDatabase
  private let queries: CodexMonitorQueries
  private let mapper: RoadmapMapper

  public init(config: CodexMonitorConfig, database: CodexMonitorDatabase) {
    self.logger = Logger(label: "codex-monitor.daemon")
    self.config = config
    self.database = database
    self.queries = CodexMonitorQueries(database: database.writer)
    self.mapper = RoadmapMapper(mapping: config.projectMapping)
  }

  public func runOnce() async {
    let discovery = RepoDiscovery()
    let repos = discovery.discoverRepos(roots: config.repoRoots)
    logger.info("Discovered \(repos.count) repositories")

    let prIngestor = PRIngestor(logger: logger)
    let checkIngestor = CheckIngestor()
    let timeStory = TimeStoryClient(logger: logger)

    for repoURL in repos {
      await WorkingDirectory.withPath(repoURL.path) {
        await ingestRepository(
          repoURL: repoURL,
          prIngestor: prIngestor,
          checkIngestor: checkIngestor
        )
      }
    }

    if await shouldFetchDailyContext(),
       let dailyStory = await timeStory.fetchDailyStory()
    {
      let context = DailyContext(date: Date(), summaryMarkdown: dailyStory)
      try? await queries.saveDailyContext(context)
    }
  }

  public func run(intervalMinutes: Int) async {
    let interval = max(1, intervalMinutes)
    while true {
      await runOnce()
      try? await Task.sleep(nanoseconds: UInt64(interval) * 60 * 1_000_000_000)
    }
  }

  private func ingestRepository(
    repoURL: URL,
    prIngestor: PRIngestor,
    checkIngestor: CheckIngestor
  ) async {
    let repoPath = repoURL.path
    let repoName = repoURL.lastPathComponent
    let repoId = StableID.make(repoPath)
    let repo = Repo(id: repoId, name: repoName, path: repoPath, org: nil)

    do {
      try await queries.upsertRepo(repo)
    } catch {
      logger.error("Failed to upsert repo \(repoName): \(String(describing: error))")
    }

    do {
      let provider = try await ProviderFactory().createProvider()
      let prs = try await prIngestor.fetchOpenPullRequests()

      for pr in prs {
        let prId = StableID.make("\(repoPath)#\(pr.number)")
        let prRecord = PullRequestRecord(
          id: prId,
          repoId: repoId,
          number: pr.number,
          title: pr.title,
          author: pr.author?.login,
          url: pr.url,
          updatedAt: pr.updatedAt
        )

        try await queries.upsertPullRequest(prRecord)

        let details = try await prIngestor.fetchPRDetails(prNumber: pr.number, provider: provider)
        let comments = Self.flattenComments(details: details, prId: prId)
        try await queries.replaceComments(for: prId, comments: comments)

        let checks = try await checkIngestor.fetchChecks(prNumber: pr.number)
        let checkRuns = checks.map { check in
          CheckRun(
            id: StableID.make("\(repoPath)#\(pr.number)#\(check.name)"),
            prId: prId,
            name: check.name,
            status: check.status,
            conclusion: check.conclusion,
            detailsUrl: check.detailsUrl,
            updatedAt: check.completedAt ?? Date()
          )
        }
        try await queries.replaceChecks(for: prId, checks: checkRuns)

        let suggestions = Self.buildFixSuggestions(prId: prId, checks: checkRuns, comments: comments)
        try await queries.replacePendingFixSuggestions(for: prId, suggestions: suggestions)
      }
    } catch {
      logger.error("Failed to ingest repo \(repoName): \(String(describing: error))")
    }

    if let project = mapper.projectForRepoPath(repoPath) {
      let mapping = RoadmapMapping(
        repoId: repoId,
        projectId: project.projectId,
        projectName: project.projectName
      )
      try? await queries.upsertRoadmapMapping(mapping)
    }
  }

  private static func flattenComments(details: PullRequest, prId: UUID) -> [PRComment] {
    var results: [PRComment] = []

    for comment in details.comments {
      results.append(
        PRComment(
          prId: prId,
          commentId: comment.id,
          author: comment.author.login,
          body: comment.body,
          url: comment.url,
          isResolved: false,
          updatedAt: ISO8601DateFormatter().date(from: comment.createdAt) ?? Date()
        )
      )
    }

    for review in details.reviews {
      for reviewComment in review.comments ?? [] {
        let resolved = reviewComment.isResolved ?? false
        results.append(
          PRComment(
            prId: prId,
            commentId: reviewComment.id,
            author: review.author.login,
            body: reviewComment.body,
            url: "",
            isResolved: resolved,
            updatedAt: ISO8601DateFormatter().date(from: reviewComment.createdAt) ?? Date()
          )
        )
      }
    }

    return results
  }

  private func shouldFetchDailyContext() async -> Bool {
    if let latest = try? await queries.latestDailyContext() {
      return !Calendar.current.isDateInToday(latest.date)
    }
    return true
  }

  private static func buildFixSuggestions(
    prId: UUID,
    checks: [CheckRun],
    comments: [PRComment]
  ) -> [FixSuggestion] {
    var suggestions: [FixSuggestion] = []

    for check in checks where (check.conclusion?.lowercased() ?? "unknown") != "success" {
      let conclusion = check.conclusion ?? check.status
      let summary = "Check '\(check.name)' is \(conclusion)"
      let action =
        check.detailsUrl
        .map { "Review logs at \($0)." }
        ?? "Review check logs in GitHub."
      suggestions.append(
        FixSuggestion(
          prId: prId,
          summary: summary,
          severity: "high",
          recommendedAction: action
        )
      )
    }

    for comment in comments where !comment.isResolved {
      let summary = "Unresolved comment from \(comment.author)"
      let action =
        comment.url.isEmpty
        ? "Review unresolved comment in the PR."
        : "Review comment at \(comment.url)."
      suggestions.append(
        FixSuggestion(
          prId: prId,
          summary: summary,
          severity: "medium",
          recommendedAction: action
        )
      )
    }

    return suggestions
  }
}
