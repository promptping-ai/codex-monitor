import Foundation
import Logging
import SQLiteData

public struct CodexMonitorDatabase {
  public let writer: any DatabaseWriter

  public init(writer: any DatabaseWriter) {
    self.writer = writer
  }

  public static func open(at url: URL? = nil, inMemory: Bool = false) throws -> CodexMonitorDatabase {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true

    let database: any DatabaseWriter
    if inMemory {
      database = try DatabaseQueue(configuration: configuration)
    } else {
      let databaseURL = url ?? defaultDatabaseURL()
      try FileManager.default.createDirectory(
        at: databaseURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    }

    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      let schema = """
        CREATE TABLE IF NOT EXISTS repo (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            org TEXT,
            updatedAt TEXT NOT NULL
        ) STRICT;

        CREATE TABLE IF NOT EXISTS pullRequest (
            id TEXT PRIMARY KEY NOT NULL,
            repoId TEXT NOT NULL,
            number INTEGER NOT NULL,
            title TEXT NOT NULL,
            author TEXT,
            url TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY(repoId) REFERENCES repo(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS checkRun (
            id TEXT PRIMARY KEY NOT NULL,
            prId TEXT NOT NULL,
            name TEXT NOT NULL,
            status TEXT NOT NULL,
            conclusion TEXT,
            detailsUrl TEXT,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY(prId) REFERENCES pullRequest(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS comment (
            id TEXT PRIMARY KEY NOT NULL,
            prId TEXT NOT NULL,
            commentId TEXT NOT NULL,
            author TEXT NOT NULL,
            body TEXT NOT NULL,
            url TEXT NOT NULL,
            isResolved INTEGER NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY(prId) REFERENCES pullRequest(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS roadmapMapping (
            id TEXT PRIMARY KEY NOT NULL,
            repoId TEXT NOT NULL,
            projectId TEXT NOT NULL,
            projectName TEXT NOT NULL,
            statusOptionId TEXT,
            updatedAt TEXT NOT NULL,
            FOREIGN KEY(repoId) REFERENCES repo(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS buildSession (
            id TEXT PRIMARY KEY NOT NULL,
            repoId TEXT,
            command TEXT NOT NULL,
            cwd TEXT NOT NULL,
            startedAt TEXT NOT NULL,
            FOREIGN KEY(repoId) REFERENCES repo(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS buildStep (
            id TEXT PRIMARY KEY NOT NULL,
            sessionId TEXT NOT NULL,
            stepIndex INTEGER NOT NULL,
            title TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            FOREIGN KEY(sessionId) REFERENCES buildSession(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS screenshot (
            id TEXT PRIMARY KEY NOT NULL,
            stepId TEXT NOT NULL,
            filePath TEXT NOT NULL,
            thumbnailPath TEXT,
            capturedAt TEXT NOT NULL,
            FOREIGN KEY(stepId) REFERENCES buildStep(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS dailyContext (
            id TEXT PRIMARY KEY NOT NULL,
            date TEXT NOT NULL,
            summaryMarkdown TEXT NOT NULL,
            createdAt TEXT NOT NULL
        ) STRICT;

        CREATE TABLE IF NOT EXISTS fixSuggestion (
            id TEXT PRIMARY KEY NOT NULL,
            prId TEXT NOT NULL,
            summary TEXT NOT NULL,
            severity TEXT NOT NULL,
            recommendedAction TEXT NOT NULL,
            status TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(prId) REFERENCES pullRequest(id)
        ) STRICT;

        CREATE TABLE IF NOT EXISTS notification (
            id TEXT PRIMARY KEY NOT NULL,
            type TEXT NOT NULL,
            severity TEXT NOT NULL,
            message TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            handledAt TEXT
        ) STRICT;
      """

      let statements =
        schema
        .split(separator: ";")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      for statement in statements {
        try db.execute(sql: statement + ";")
      }
    }

    try migrator.migrate(database)

    return CodexMonitorDatabase(writer: database)
  }

  public static func defaultDatabaseURL() -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser
    return base
      .appendingPathComponent("CodexMonitor", isDirectory: true)
      .appendingPathComponent("monitor.sqlite")
  }
}
