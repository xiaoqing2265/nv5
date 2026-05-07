import CryptoKit
import Foundation

public struct WebDAVCredentials: Codable, Sendable {
    public let config: WebDAVConfig
    public let password: String
    /// Master key for End-to-End Encryption (Base64 encoded)
    public let syncMasterKey: String
    
    public init(config: WebDAVConfig, password: String, syncMasterKey: String) {
        self.config = config
        self.password = password
        self.syncMasterKey = syncMasterKey
    }
}

public enum CredentialStore {
    private static var fileURL: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NV5", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("webdav.v2.credentials")
    }
    
    public static func save(_ credentials: WebDAVCredentials) throws {
        let key = try DeviceKey.deriveSubkey(purpose: "credentials")
        let plaintext = try JSONEncoder().encode(credentials)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        
        guard let combined = sealed.combined else {
            throw CredentialError.encryptionFailed
        }
        
        // Write with system-level file protection (only accessible after login)
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
        
        // Set POSIX permissions to owner read/write only (0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        
        // Exclude from Time Machine backups to prevent credentials leakage to external disks
        var url = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
    }
    
    public static func load() throws -> WebDAVCredentials? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        
        let data = try Data(contentsOf: fileURL)
        let key = try DeviceKey.deriveSubkey(purpose: "credentials")
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key)
        
        return try JSONDecoder().decode(WebDAVCredentials.self, from: plaintext)
    }
    
    public static func delete() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

public enum CredentialError: Error {
    case encryptionFailed
    case decryptionFailed
}
