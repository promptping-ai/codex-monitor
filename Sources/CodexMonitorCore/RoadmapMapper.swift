import Foundation

public struct RoadmapMapper: Sendable {
  private let mapping: ProjectMapping

  public init(mapping: ProjectMapping) {
    self.mapping = mapping
  }

  public func projectForRepoPath(_ path: String) -> (projectId: String, projectName: String)? {
    let expandedPath = PathUtils.expandTilde(path)
    let corporateRoots = mapping.corporateRoots.map { PathUtils.expandTilde($0) }

    for root in corporateRoots {
      if expandedPath.hasPrefix(root) {
        return (mapping.project3Id, mapping.project3Name)
      }
    }

    let clientBase = PathUtils.expandTilde(mapping.clientRootBase)
    if expandedPath.hasPrefix(clientBase) {
      return (mapping.project4Id, mapping.project4Name)
    }

    return nil
  }
}
