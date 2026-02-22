import AppKit
import CodexMonitorCore
import SwiftUI

@main
struct CodexMonitorApp: App {
  @StateObject private var model = CodexMonitorStatusModel()

  var body: some Scene {
    MenuBarExtra("Codex Monitor", systemImage: "bolt.circle") {
      CodexMonitorMenuView(model: model)
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class CodexMonitorStatusModel: ObservableObject {
  @Published var failingChecks: Int = 0
  @Published var unresolvedComments: Int = 0
  @Published var dailySummary: String = "No daily context yet"
  @Published var roadmapSummaries: [RoadmapSummary] = []
  @Published var buildTimeline: [BuildStepTimelineEntry] = []

  private var timer: Timer?

  init() {
    Task { @MainActor in
      self.refresh()
    }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  func refresh() {
    Task {
      do {
        let database = try CodexMonitorDatabase.open()
        let queries = CodexMonitorQueries(database: database.writer)
        let checks = try await queries.failingChecks(limit: 200)
        let comments = try await queries.unresolvedComments(limit: 200)
        let context = try await queries.latestDailyContext()
        let roadmap = try await queries.roadmapSummary()
        let timeline = try await queries.latestBuildTimeline(limit: 4)

        await MainActor.run {
          self.failingChecks = checks.count
          self.unresolvedComments = comments.count
          self.dailySummary = context?.summaryMarkdown ?? "No daily context yet"
          self.roadmapSummaries = roadmap
          self.buildTimeline = timeline
        }
      } catch {
        await MainActor.run {
          self.dailySummary = "Failed to load status"
        }
      }
    }
  }
}

struct CodexMonitorMenuView: View {
  @ObservedObject var model: CodexMonitorStatusModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Failing checks: \(model.failingChecks)")
      Text("Unresolved comments: \(model.unresolvedComments)")
      Divider()
      if !model.roadmapSummaries.isEmpty {
        Text("Roadmap")
          .font(.headline)
        ForEach(model.roadmapSummaries, id: \.projectId) { summary in
          VStack(alignment: .leading, spacing: 2) {
            Text(summary.projectName)
              .font(.subheadline)
            Text("Repos: \(summary.repoCount) · PRs: \(summary.openPullRequestCount)")
              .font(.caption)
            Text("Checks: \(summary.failingCheckCount) · Comments: \(summary.unresolvedCommentCount)")
              .font(.caption2)
          }
        }
        Divider()
      }
      if !model.buildTimeline.isEmpty {
        Text("Latest build")
          .font(.headline)
        ForEach(model.buildTimeline, id: \.stepId) { entry in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.stepIndex). \(entry.title)")
              .font(.caption)
            if let path = entry.screenshotPath,
               let image = NSImage(contentsOfFile: path)
            {
              Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 120)
            }
          }
        }
        Divider()
      }
      Text("Daily context")
        .font(.headline)
      ScrollView {
        Text(model.dailySummary)
          .font(.footnote)
          .frame(maxWidth: 240, alignment: .leading)
      }
      Divider()
      Button("Open Data Folder") {
        let url = CodexMonitorDatabase.defaultDatabaseURL().deletingLastPathComponent()
        NSWorkspace.shared.open(url)
      }
    }
    .padding(12)
    .frame(width: 280)
  }
}
