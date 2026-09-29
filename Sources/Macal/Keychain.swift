import Foundation
import Security

/// Refresh tokens, one generic password item per Google account. Items go
/// to the file-based login keychain (no `kSecUseDataProtectionKeychain`),
/// which works for an unsigned SwiftPM binary without entitlements.
enum Keychain {
    private static let service = "dev.macal.app.google-refresh-token"

    struct Failure: Error {
        let status: OSStatus
    }

    /// Updates the item in place, or adds it when missing, so a failed
    /// write never loses the previous token.
    static func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query(account)
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        default:
            throw Failure(status: status)
        }
    }

    /// `nil` when no token is stored. Throws on any other Keychain error
    /// (locked keychain, access denied), which is not a revoked token.
    static func read(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw Failure(status: errSecDecode) }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
