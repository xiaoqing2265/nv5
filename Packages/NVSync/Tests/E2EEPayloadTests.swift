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
}
