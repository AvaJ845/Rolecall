import Foundation
import CryptoKit

/// Verifies that a downloaded `board.json` was signed by Rolecall's own key — not served
/// by a compromised CDN or injected by anything that got past TLS. The signature is a
/// detached Ed25519 signature over the exact board bytes, published alongside the board at
/// `<board>.sig` (hex-encoded).
enum BoardSignature {

    /// The Ed25519 public key, hex. Must equal `engine/board_pubkey.hex`. Rotating the key
    /// means shipping an app update — that's the point.
    static let publicKeyHex = "ff2cbfa3b434c7ead41f955b7bda7cd2ab78f6494feffe89d425f9e49d9bb92b"

    static var signatureURL: URL {
        BoardSource.remoteURL.deletingLastPathComponent().appendingPathComponent("board.json.sig")
    }

    /// True iff `signatureHex` is a valid Ed25519 signature of `board` under `keyHex`
    /// (the app's own `publicKeyHex` by default).
    static func isValid(board: Data, signatureHex: String, keyHex: String = publicKeyHex) -> Bool {
        let hex = signatureHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sig = Data(hexString: hex), sig.count == 64,
              let keyBytes = Data(hexString: keyHex),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        else { return false }
        return key.isValidSignature(sig, for: board)
    }
}

extension Data {
    init?(hexString: String) {
        let s = hexString.count % 2 == 0 ? hexString : "0" + hexString
        var out = Data(capacity: s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let byte = UInt8(s[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        self = out
    }
}
