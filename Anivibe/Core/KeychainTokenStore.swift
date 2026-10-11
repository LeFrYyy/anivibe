import Foundation
import Security
import AnivibeCore

/// Хранит сессию Supabase в Keychain (доступна только после первой разблокировки устройства).
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service = "app.anivibe.auth"
    private let account = "supabase-session"

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
