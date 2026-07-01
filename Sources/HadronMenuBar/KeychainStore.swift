import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Keyed on a fixed service string
/// so it works for a bare SPM binary (no bundle identifier required).
///
/// Stores two items: the long-lived OAuth access token and the dynamically
/// registered OAuth client id (cached so we don't re-register — and burn the
/// DCR rate limit — on every launch).
enum KeychainStore {
    private static let service = "com.hadron.macapp"

    enum Key: String {
        case accessToken = "access-token"
        case clientId = "oauth-client-id"
    }

    static func set(_ value: String?, for key: Key) {
        guard let value, !value.isEmpty else {
            delete(key)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        if status != errSecSuccess {
            // Surface the failure — a silently-dropped token loops sign-in.
            NSLog("KeychainStore: failed to store \(key.rawValue) (OSStatus \(status))")
        }
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
