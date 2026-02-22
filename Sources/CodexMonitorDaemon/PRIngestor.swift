import Foundation
import Logging
import PullRequestPing
import Subprocess

struct PRIngestor {
  let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func fetchOpenPullRequests() async throws -> [GHPR] {
    let result = try await Subprocess.run(
      .name("gh"),
      arguments: ["pr", "list", "--state", "open", "--json", "number,title,author,url,updatedAt"],
      output: .bytes(limit: 2 * 1024 * 1024),
      error: .bytes(limit: 1024 * 1024)
    )

    guard result.terminationStatus.isSuccess else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
      throw PRIngestError.commandFailed(stderr)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([GHPR].self, from: Data(result.standardOutput))
  }

  func fetchPRDetails(prNumber: Int, provider: any PRProvider) async throws -> PullRequest {
    try await provider.fetchPR(identifier: String(prNumber), repo: nil)
  }
}

struct GHPR: Decodable {
  let number: Int
  let title: String
  let author: GHAuthor?
  let url: String
  let updatedAt: Date
}

struct GHAuthor: Decodable {
  let login: String
}

enum PRIngestError: Error {
  case commandFailed(String)
}
