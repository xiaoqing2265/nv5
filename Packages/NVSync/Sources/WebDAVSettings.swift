import Foundation

public enum WebDAVSettings {
    /// Loads the WebDAV credentials from the silent CredentialStore.
    public static func load() -> WebDAVCredentials? {
        try? CredentialStore.load()
    }
    
    /// Saves the WebDAV credentials to the silent CredentialStore.
    public static func save(_ credentials: WebDAVCredentials) throws {
        try CredentialStore.save(credentials)
    }
    
    /// Performs a one-time migration from the old UserDefaults and Keychain storage to the new silent CredentialStore.
    /// This effectively stops the frequent system Keychain popups.
    public static func migrateIfNeeded() {
        // 1. Check if already migrated
        if (try? CredentialStore.load()) != nil { return }
        
        // 2. Try to load from old storage
        let oldKey = "NV5.WebDAVConfig"
        guard let data = UserDefaults.standard.data(forKey: oldKey),
              let config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return
        }
        
        // 3. Try to load password from old Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: config.serverURL.host ?? "",
            kSecAttrAccount as String: config.username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return
        }
        
        // 4. Migrate to new store
        // Generate a new random sync master key for End-to-End Encryption
        let masterKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let credentials = WebDAVCredentials(config: config, password: password, syncMasterKey: masterKey)
        
        do {
            try CredentialStore.save(credentials)
            
            // 5. Cleanup old storage to stop popups
            UserDefaults.standard.removeObject(forKey: oldKey)
            SecItemDelete(query as CFDictionary)
            
            print("Successfully migrated WebDAV credentials to silent store. Keychain popups resolved.")
        } catch {
            print("Failed to migrate credentials: \(error)")
        }
    }
}