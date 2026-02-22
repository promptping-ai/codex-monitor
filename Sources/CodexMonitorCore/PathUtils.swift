import Foundation

public enum PathUtils {
  public static func expandTilde(_ path: String) -> String {
    if path.hasPrefix("~") {
      let home = FileManager.default.homeDirectoryForCurrentUser.path
      return path.replacingOccurrences(of: "~", with: home)
    }
    return path
  }
}
