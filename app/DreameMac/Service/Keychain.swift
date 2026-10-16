import Foundation
import Security

/// Where the Dreamehome password and refresh token are kept.
protocol SecretStore: Sendable {
    func string(for account: String) -> String?
    /// Stores `value`, or deletes the item if `value` is nil.
    func set(_ value: String?, for account: String)
}

extension SecretStore {
    func password(for user: String) -> String? { string(for: user) }
    func setPassword(_ password: String?, for user: String) { set(password, for: user) }
    func refreshToken(for user: String) -> String? { string(for: "\(user):refresh-token") }
    func setRefreshToken(_ token: String?, for user: String) { set(token, for: "\(user):refresh-token") }
}

/// Generic-password items in the login Keychain.
struct KeychainStore: SecretStore {
    private let service = "digital.jamon.dreamemac"

    func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
