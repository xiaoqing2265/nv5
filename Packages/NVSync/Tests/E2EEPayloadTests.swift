import XCTest
@testable import NVSync
import CryptoKit
@testable import NVModel
@testable import NVStore
@testable import NVCrypto

final class E2EEPayloadTests: XCTestCase {
    var dbURL: URL!
    var database: Database!
    var store: NoteStore!
    var crypto: CryptoEngine!
    var mockClient: MockWebDAVClient!
    var syncCoordinator: SyncCoordinator!

    @MainActor
    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        database = try Database(url: dbURL)
        store = NoteStore(database: database)
        // Initialize CryptoEngine with a dummy key
        crypto = CryptoEngine(key: SymmetricKey(size: .bits256))
        mockClient = MockWebDAVClient()
        syncCoordinator = SyncCoordinator(client: mockClient, store: store, database: database, crypto: crypto)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: dbURL)
    }

    @MainActor
    func testEncryptionWrapper() async throws {
        let noteID = UUID()
        var note = Note(title: "Secret Title")
        note.id = noteID
        note.body = "Secret Body"
        note.labels = ["TopSecret"]
        note.isEncrypted = false

        let payload = RemoteNotePayload(from: note)
        
        let encryptedPayload = try await syncCoordinator.encryptPayloadIfNeeded(payload)
        
        XCTAssertTrue(encryptedPayload.isEncrypted, "Payload should be marked as encrypted")
        XCTAssertEqual(encryptedPayload.title, "Encrypted", "Title must be masked")
        XCTAssertTrue(encryptedPayload.labels.isEmpty, "Labels must be masked")
        XCTAssertNotEqual(encryptedPayload.body, "Secret Body", "Body must be encrypted")
        XCTAssertFalse(encryptedPayload.body.contains("Secret Title"), "Body base64 should not contain plaintext title")
        XCTAssertFalse(encryptedPayload.body.contains("TopSecret"), "Body base64 should not contain plaintext label")

        let decryptedPayload = try await syncCoordinator.decryptPayloadIfNeeded(encryptedPayload, noteID: noteID)
        
        XCTAssertFalse(decryptedPayload.isEncrypted)
        XCTAssertEqual(decryptedPayload.title, "Secret Title")
        XCTAssertEqual(decryptedPayload.body, "Secret Body")
        XCTAssertEqual(decryptedPayload.labels, ["TopSecret"])
    }

    // MARK: - 负向 / 边界场景

    /// bodyAttributes（富文本属性）应随密文一起加密、解密后完整还原。
    @MainActor
    func test_bodyAttributes_survive_encryption_roundtrip() async throws {
        let noteID = UUID()
        var note = Note(title: "Rich", body: "Body")
        note.id = noteID
        note.bodyAttributes = Data([0x01, 0x02, 0x03, 0xFF, 0xFE])

        let payload = RemoteNotePayload(from: note)
        XCTAssertNotNil(payload.bodyAttributesBase64, "明文 payload 应携带 bodyAttributes")

        let enc = try await syncCoordinator.encryptPayloadIfNeeded(payload)
        XCTAssertTrue(enc.isEncrypted)
        XCTAssertNil(enc.bodyAttributesBase64, "加密后属性应并入密文、外层置空（不泄露）")

        let dec = try await syncCoordinator.decryptPayloadIfNeeded(enc, noteID: noteID)
        XCTAssertEqual(dec.bodyAttributesBase64, note.bodyAttributes?.base64EncodedString(),
                       "解密后 bodyAttributes 应完整还原")
    }

    /// 双重加密防护：对已加密的 payload 再次加密应为 no-op（不二次封装），且仍可一次解密还原。
    @MainActor
    func test_double_encryption_is_noop() async throws {
        let note = Note(title: "T", body: "B")
        let enc = try await syncCoordinator.encryptPayloadIfNeeded(RemoteNotePayload(from: note))
        let encAgain = try await syncCoordinator.encryptPayloadIfNeeded(enc)

        XCTAssertTrue(encAgain.isEncrypted)
        XCTAssertEqual(encAgain.body, enc.body, "已加密的 payload 不应被二次封装")

        let dec = try await syncCoordinator.decryptPayloadIfNeeded(encAgain, noteID: note.id)
        XCTAssertEqual(dec.body, "B", "一次解密即可还原（未被双重封装）")
    }

    /// 空笔记加密往返。
    @MainActor
    func test_empty_note_encryption_roundtrip() async throws {
        let note = Note(title: "", body: "")
        let enc = try await syncCoordinator.encryptPayloadIfNeeded(RemoteNotePayload(from: note))
        XCTAssertTrue(enc.isEncrypted)

        let dec = try await syncCoordinator.decryptPayloadIfNeeded(enc, noteID: note.id)
        XCTAssertEqual(dec.title, "")
        XCTAssertEqual(dec.body, "")
    }

    /// 用错误密钥解密应优雅失败（抛错），绝不返回乱码。
    @MainActor
    func test_decrypt_with_wrong_key_fails() async throws {
        let note = Note(title: "Secret", body: "Secret Body")
        let enc = try await syncCoordinator.encryptPayloadIfNeeded(RemoteNotePayload(from: note))

        // 另一个使用【不同密钥】的 coordinator
        let otherCrypto = CryptoEngine(key: SymmetricKey(size: .bits256))
        let otherCoordinator = SyncCoordinator(client: mockClient, store: store, database: database, crypto: otherCrypto)

        await XCTAssertThrowsErrorAsync {
            try await otherCoordinator.decryptPayloadIfNeeded(enc, noteID: note.id)
        }
    }
}

// MARK: - 异步抛错断言助手

/// 异步版 `XCTAssertThrowsError`（标准宏不支持 async）。用尾随闭包传入待测表达式。
fileprivate func XCTAssertThrowsErrorAsync<T>(
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws -> T
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown. \(message)", file: file, line: line)
    } catch {
        // 预期抛错——通过
    }
}

// MARK: - CryptoEngine 负向 / 安全单元测试

/// 对 AES-GCM 加密原语的全面负向 / 边界测试（此前整套 E2EE 仅 1 个正向测试）。
final class CryptoEngineTests: XCTestCase {

    private func makeEngine() -> CryptoEngine {
        CryptoEngine(key: SymmetricKey(size: .bits256))
    }

    // 正向 / 往返

    func test_seal_open_roundtrip() async throws {
        let engine = makeEngine()
        let ct = try await engine.seal("Hello, World")
        let pt = try await engine.open(ct)
        XCTAssertEqual(pt, "Hello, World")
    }

    func test_roundtrip_empty_string() async throws {
        let engine = makeEngine()
        let ct = try await engine.seal("")
        let pt = try await engine.open(ct)
        XCTAssertEqual(pt, "")
    }

    func test_roundtrip_unicode_and_emoji() async throws {
        let engine = makeEngine()
        let secret = "你好，世界 🔐 café Ω≈ç √∫ 𝕊"
        let ct = try await engine.seal(secret)
        let pt = try await engine.open(ct)
        XCTAssertEqual(pt, secret)
    }

    func test_roundtrip_large_payload() async throws {
        let engine = makeEngine()
        let big = String(repeating: "A秘密🔒", count: 50_000)  // 数百 KB
        let ct = try await engine.seal(big)
        let pt = try await engine.open(ct)
        XCTAssertEqual(pt, big)
    }

    // 负向：错误密钥 / 完整性

    /// 错误密钥无法解密——应优雅 throw，不崩溃、不返回乱码。
    func test_wrong_key_fails_to_decrypt() async throws {
        let a = makeEngine()
        let b = makeEngine()  // 不同密钥
        let ct = try await a.seal("classified")
        await XCTAssertThrowsErrorAsync { try await b.open(ct) }
    }

    /// 篡改密文中间字节，GCM 完整性校验应拒绝。
    func test_tampered_ciphertext_is_rejected() async throws {
        let engine = makeEngine()
        var ct = try await engine.seal("integrity matters")
        ct[ct.count / 2] ^= 0xFF
        await XCTAssertThrowsErrorAsync { try await engine.open(ct) }
    }

    /// 篡改末尾（GCM tag）字节应被拒绝。
    func test_tampered_tag_is_rejected() async throws {
        let engine = makeEngine()
        var ct = try await engine.seal("tag check")
        ct[ct.count - 1] ^= 0x01
        await XCTAssertThrowsErrorAsync { try await engine.open(ct) }
    }

    /// 截断密文应被拒绝。
    func test_truncated_ciphertext_is_rejected() async throws {
        let engine = makeEngine()
        let ct = try await engine.seal("truncate me please")
        let truncated = Data(ct.prefix(ct.count - 5))
        await XCTAssertThrowsErrorAsync { try await engine.open(truncated) }
    }

    /// 空数据不是合法 SealedBox，应 throw（不崩溃）。
    func test_empty_data_is_rejected() async throws {
        let engine = makeEngine()
        await XCTAssertThrowsErrorAsync { try await engine.open(Data()) }
    }

    /// 随机垃圾数据应被拒绝。
    func test_random_garbage_is_rejected() async throws {
        let engine = makeEngine()
        let garbage = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        await XCTAssertThrowsErrorAsync { try await engine.open(garbage) }
    }

    // 负向：nonce / 泄露

    /// 相同明文两次加密应产生不同密文（随机 nonce），且都能正确解密。
    func test_each_seal_uses_fresh_nonce() async throws {
        let engine = makeEngine()
        let ct1 = try await engine.seal("same plaintext")
        let ct2 = try await engine.seal("same plaintext")
        XCTAssertNotEqual(ct1, ct2, "随机 nonce 应使每次密文不同")
        let pt1 = try await engine.open(ct1)
        let pt2 = try await engine.open(ct2)
        XCTAssertEqual(pt1, "same plaintext")
        XCTAssertEqual(pt2, "same plaintext")
    }

    /// 密文不应包含明文字节（无泄露）。
    func test_ciphertext_does_not_leak_plaintext() async throws {
        let engine = makeEngine()
        let secret = "PLAINTEXT_MARKER_1234567890"
        let ct = try await engine.seal(secret)
        XCTAssertNil(ct.range(of: Data(secret.utf8)), "密文不应包含明文字节")
    }

    // 负向 / 正向：密钥构造

    /// 无效 base64 密钥应抛 CryptoError.invalidKey。
    func test_invalid_base64_key_throws_invalidKey() {
        XCTAssertThrowsError(try CryptoEngine(base64Key: "not valid base64 @#$%")) { error in
            guard case CryptoError.invalidKey = error else {
                return XCTFail("Expected CryptoError.invalidKey, got \(error)")
            }
        }
    }

    /// 有效 base64 密钥可用；同密钥的两个引擎可互相解密。
    func test_valid_base64_key_roundtrip_and_interop() async throws {
        let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let b64 = keyData.base64EncodedString()
        let a = try CryptoEngine(base64Key: b64)
        let b = try CryptoEngine(base64Key: b64)  // 相同密钥
        let ct = try await a.seal("interop")
        let opened = try await b.open(ct)
        XCTAssertEqual(opened, "interop", "同密钥的两个引擎应可互相解密")
    }
}
