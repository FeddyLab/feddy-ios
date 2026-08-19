import Foundation
import Security

/// Persists the anonymous contact id in the Keychain so it survives
/// app reinstalls and users keep their conversation history.
enum AnonIdStore {
    private static let service = "app.feddy.sdk"
    private static let account = "anon_id"

    static func anonId() -> String {
        if let existing = read(), existing.count >= 8, existing.count <= 128 {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        write(fresh)
        return fresh
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }
}
