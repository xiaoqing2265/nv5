import CryptoKit
import Foundation
import Security

public actor CryptoEngine {
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public static func loadOrCreate(serviceName: String = "NV5.MasterKey") throws -> CryptoEngine {
        if let existing = try Keychain.loadKey(service: serviceName) {
            return CryptoEngine(key: existing)
        }
        let new = SymmetricKey(size: .bits256)
        try Keychain.storeKey(new, service: serviceName)
        return CryptoEngine(key: new)
    }

    public func seal(_ plaintext: String) throws -> Data {
        let data = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.sealFailed
        }
        return combined
    }

    public func open(_ ciphertext: Data) throws -> String {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        let data = try AES.GCM.open(box, using: key)
        guard let str = String(data: data, encoding: .utf8) else {
            throw CryptoError.openFailed
        }
        return str
    }
}

public enum CryptoError: Error {
    case sealFailed
    case openFailed
}

enum Keychain {
    static func storeKey(_ key: SymmetricKey, service: String) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "master",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    static func loadKey(service: String) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "master",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return SymmetricKey(data: data)
    }
}

public enum KeychainError: Error, Sendable {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
}