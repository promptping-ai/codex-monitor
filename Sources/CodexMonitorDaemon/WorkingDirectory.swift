import Foundation

enum WorkingDirectory {
  static func withPath<T>(_ path: String, _ operation: () async throws -> T) async rethrows -> T {
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(path)
    defer {
      FileManager.default.changeCurrentDirectoryPath(previous)
    }
    return try await operation()
  }
}
