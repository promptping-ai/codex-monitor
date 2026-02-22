import CodexMonitorCore
import Foundation

public struct RepoDiscovery {
  public init() {}

  public func discoverRepos(roots: [String]) -> [URL] {
    var repos: [URL] = []

    for root in roots {
      let expanded = PathUtils.expandTilde(root)
      let rootURL = URL(fileURLWithPath: expanded)
      guard FileManager.default.fileExists(atPath: rootURL.path) else {
        continue
      }

      if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
        for case let url as URL in enumerator {
          let gitDir = url.appendingPathComponent(".git")
          if FileManager.default.fileExists(atPath: gitDir.path) {
            repos.append(url)
            enumerator.skipDescendants()
          }
        }
      }
    }

    return repos
  }
}
