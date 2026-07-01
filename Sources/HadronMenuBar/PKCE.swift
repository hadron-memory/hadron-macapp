import Foundation
import CryptoKit

/// A PKCE pair (RFC 7636). The server supports the `S256` method only.
struct PKCEPair {
    let codeVerifier: String
    let codeChallenge: String
    let method = "S256"

    init() {
        let verifier = PKCEPair.randomURLSafeString(byteCount: 64)
        self.codeVerifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.codeChallenge = Data(digest).base64URLEncodedString()
    }

    /// Cryptographically-random base64url string with no padding.
    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// base64url (RFC 4648 §5) with padding stripped.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
