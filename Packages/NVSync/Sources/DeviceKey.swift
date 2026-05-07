import CryptoKit
import Foundation
import IOKit

/// Utility to derive stable, hardware-bound keys without triggering Keychain prompts.
public enum DeviceKey {
    
    /// Derives a stable 256-bit symmetric key bound to this specific Mac's hardware UUID.
    /// - Parameter purpose: A unique string to separate different key domains (e.g., "credentials", "notes").
    /// - Returns: A derived SymmetricKey.
    public static func deriveSubkey(purpose: String) throws -> SymmetricKey {
        let hardwareUUID = try fetchHardwareUUID()
        let salt = "com.nv5.device-key.v1".data(using: .utf8)!
        
        // Use the Hardware UUID as the base input key material
        let baseKey = SymmetricKey(data: Data(hardwareUUID.utf8))
        
        // Derive a domain-specific subkey using HKDF
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: baseKey,
            salt: salt,
            info: Data("nv5-purpose-\(purpose)".utf8),
            outputByteCount: 32
        )
    }
    
    /// Fetches the IOPlatformUUID from the IORegistry.
    /// This is stable across OS reinstalls but changes if the logic board is replaced.
    private static func fetchHardwareUUID() throws -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else {
            throw DeviceKeyError.hardwareUUIDUnavailable
        }
        defer { IOObjectRelease(platformExpert) }
        
        guard let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else {
            throw DeviceKeyError.hardwareUUIDUnavailable
        }
        return uuid
    }
}

public enum DeviceKeyError: Error {
    case hardwareUUIDUnavailable
}
