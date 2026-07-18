import Foundation
import Security

/// Minimal Keychain wrapper for the shared session secret. Items land in the shared keychain
/// access group (the single entry in both targets' `keychain-access-groups` entitlement), so the
/// app and the Share Extension read the same value — without the group being named in code.
///
/// The Keychain is hardware-encrypted and access-controlled, unlike the App-Group `UserDefaults`
/// plist the session cookie used to live in.
enum Keychain {
    private static let service = "org.syslinx.rhizome.session"

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)   // replace any existing item
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // readable after the first unlock so the Share Extension can post while the app is backgrounded
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}
