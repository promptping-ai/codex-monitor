import Foundation

// MARK: - Cached Data Model

/// Cached PR and status data for a repository
public struct CachedPRData: Codable, Sendable {
  public let branch: String
  public let prNumber: Int?
  public let prState: String?
  public let checksStatus: String?
  public let checksDetail: String?
  public let commentInfo: String?
  public let criticalCount: Int
  public let graphiteStack: String?
  public let updatedAt: Date

  public init(
    branch: String,
    prNumber: Int? = nil,
    prState: String? = nil,
    checksStatus: String? = nil,
    checksDetail: String? = nil,
    commentInfo: String? = nil,
    criticalCount: Int = 0,
    graphiteStack: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.branch = branch
    self.prNumber = prNumber
    self.prState = prState
    self.checksStatus = checksStatus
    self.checksDetail = checksDetail
    self.commentInfo = commentInfo
    self.criticalCount = criticalCount
    self.graphiteStack = graphiteStack
    self.updatedAt = updatedAt
  }
}

// MARK: - Cache Manager

/// Thread-safe cache manager for PR status data
/// Uses actor isolation to prevent data races
public actor PRCache {
  public static let shared = PRCache()

  /// TTL for PR metadata (state, comments, stack) - longer lived (2 minutes)
  public let dataTTL: TimeInterval

  /// TTL for CI checks - shorter because they change rapidly (30 seconds)
  public let checksTTL: TimeInterval

  /// Legacy property for backward compatibility
  public var cacheTTL: TimeInterval { dataTTL }

  private let cacheURL: URL
  private var cache: [String: CachedPRData] = [:]
  private var isLoaded = false

  /// Create a cache instance with separate TTLs for data vs checks
  /// - Parameters:
  ///   - dataTTL: TTL for PR metadata (state, comments, stack). Default 120s.
  ///   - checksTTL: TTL for CI checks (status, detail). Default 30s.
  public init(dataTTL: TimeInterval = 120, checksTTL: TimeInterval = 30) {
    self.dataTTL = dataTTL
    self.checksTTL = checksTTL
    // Store in ~/.cache/claude-statusline/ for backward compat
    let cacheDir =
      FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/claude-statusline")
    self.cacheURL = cacheDir.appendingPathComponent("pr-cache.json")
  }

  /// Legacy initializer for backward compatibility (sets both TTLs to same value)
  public init(cacheTTL: TimeInterval) {
    self.dataTTL = cacheTTL
    self.checksTTL = cacheTTL
    let cacheDir =
      FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/claude-statusline")
    self.cacheURL = cacheDir.appendingPathComponent("pr-cache.json")
  }

  /// Generate cache key from repo path and branch
  private func cacheKey(path: String, branch: String) -> String {
    "\(path):\(branch)"
  }

  /// Get cached data for a repo/branch combination
  public func get(for path: String, branch: String) -> CachedPRData? {
    let key = cacheKey(path: path, branch: branch)
    guard let data = cache[key] else { return nil }

    let age = Date().timeIntervalSince(data.updatedAt)

    if age > dataTTL {
      return nil
    }

    if age > checksTTL {
      return CachedPRData(
        branch: data.branch,
        prNumber: data.prNumber,
        prState: data.prState,
        checksStatus: nil,
        checksDetail: nil,
        commentInfo: data.commentInfo,
        criticalCount: data.criticalCount,
        graphiteStack: data.graphiteStack,
        updatedAt: data.updatedAt
      )
    }

    return data
  }

  /// Store data in cache
  public func set(_ data: CachedPRData, for path: String) {
    let key = cacheKey(path: path, branch: data.branch)
    cache[key] = data
  }

  /// Load cache from disk
  public func load() {
    guard !isLoaded else { return }
    isLoaded = true

    guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }

    do {
      let data = try Data(contentsOf: cacheURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      cache = try decoder.decode([String: CachedPRData].self, from: data)
    } catch {
      FileHandle.standardError.write(
        Data("[CACHE] Failed to load cache: \(error)\n".utf8)
      )
    }
  }

  /// Save cache to disk
  public func save() {
    do {
      let cacheDir = cacheURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: cacheDir,
        withIntermediateDirectories: true
      )

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(cache)
      try data.write(to: cacheURL)
    } catch {
      FileHandle.standardError.write(
        Data("[CACHE] Failed to save cache: \(error)\n".utf8)
      )
    }
  }

  /// Clear all cached data
  public func clear() {
    cache.removeAll()
  }

  /// Get age of cached data in seconds
  public func age(for path: String, branch: String) -> TimeInterval? {
    guard let data = get(for: path, branch: branch) else { return nil }
    return Date().timeIntervalSince(data.updatedAt)
  }
}
