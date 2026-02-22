import Foundation
import Subprocess

struct CheckIngestor {
  func fetchChecks(prNumber: Int) async throws -> [GHCheck] {
    let result = try await Subprocess.run(
      .name("gh"),
      arguments: ["pr", "checks", String(prNumber), "--json", "name,status,conclusion,detailsUrl,completedAt"],
      output: .bytes(limit: 2 * 1024 * 1024),
      error: .bytes(limit: 1024 * 1024)
    )

    guard result.terminationStatus.isSuccess else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
      throw CheckIngestError.commandFailed(stderr)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([GHCheck].self, from: Data(result.standardOutput))
  }
}

struct GHCheck: Decodable {
  let name: String
  let status: String
  let conclusion: String?
  let detailsUrl: String?
  let completedAt: Date?
}

enum CheckIngestError: Error {
  case commandFailed(String)
}
