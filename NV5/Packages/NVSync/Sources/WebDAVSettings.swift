import Foundation

public enum WebDAVSettings {
    private static let key = "NV5.WebDAVConfig"

    public static func save(_ config: WebDAVConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func load() -> WebDAVConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WebDAVConfig.self, from: data)
    }
}

public enum WebDAVKeychainError: Error, Sendable {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
}

public enum WebDAVKeychain {
    private static func service(for config: WebDAVConfig) -> String {
        "NV5.WebDAV.\(config.serverURL.host ?? "unknown")"
    }

    public static func storePassword(_ password: String, for config: WebDAVConfig) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: config.serverURL.host ?? "",
            kSecAttrAccount as String: config.username,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw WebDAVKeychainError.storeFailed(status) }
    }

    public static func loadPassword(for config: WebDAVConfig) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: config.serverURL.host ?? "",
            kSecAttrAccount as String: config.username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WebDAVKeychainError.loadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }
}