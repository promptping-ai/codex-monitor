import Foundation
import CryptoKit

public enum StableID {
  public static func make(_ input: String) -> UUID {
    let digest = SHA256.hash(data: Data(input.utf8))
    let bytes = Array(digest.prefix(16))
    let uuid = UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
    return uuid
  }
}
