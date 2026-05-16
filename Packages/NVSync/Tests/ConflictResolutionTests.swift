import XCTest
@testable import NVSync
@testable import NVModel
@testable import NVStore

final class ConflictResolutionTests: XCTestCase {
    var dbURL: URL!
    var database: Database!
    var store: NoteStore!
    var mockClient: MockWebDAVClient!
    var syncCoordinator: SyncCoordinator!

    @MainActor
    override func setUp() async throws {
        dbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        database = try Database(url: dbURL)
        store = NoteStore(database: database)
        mockClient = MockWebDAVClient()
        syncCoordinator = SyncCoordinator(client: mockClient, store: store, database: database)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: dbURL)
    }

    @MainActor
    func testConflictResolutionBothModified() async throws {
        let noteID = UUID()
        let olderDate = Date(timeIntervalSinceNow: -3600)
        let newerDate = Date()
        
        var localNote = Note(title: "Local Title", modifiedAt: olderDate)
        localNote.id = noteID
        localNote.body = "Local Body"
        localNote.localDirty = true
        
        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Create remote payload with newer timestamp (remote wins)
        var remoteNote = Note(title: "Remote Title", modifiedAt: newerDate)
        remoteNote.id = noteID
        remoteNote.body = "Remote Body"
        let remotePayload = RemoteNotePayload(from: remoteNote)
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)
        
        let remoteEtag = "remote-etag-123"
        let remoteResource = WebDAVResource(path: "\(noteID.uuidString).json", etag: remoteEtag, lastModified: Date(), contentLength: 100, isDirectory: false)
        await mockClient.setMockFile(path: "notes/\(remoteResource.path)", data: remoteData, etag: remoteEtag)

        try await syncCoordinator.resolveConflict(local: localNote, remoteResource: remoteResource)

        let allNotes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }
        
        XCTAssertEqual(allNotes.count, 2, "Conflict should result in two notes: original remote and local copy")
        
        let original = allNotes.first(where: { $0.id == noteID })!
        XCTAssertEqual(original.title, "Remote Title", "Original ID should be overwritten with remote content")
        XCTAssertFalse(original.localDirty)
        
        let copy = allNotes.first(where: { $0.id != noteID })!
        XCTAssertTrue(copy.title.hasPrefix("Local Title (Conflict "), "Conflicted copy should retain local title with conflict suffix")
        XCTAssertTrue(copy.localDirty, "Conflicted copy should be marked localDirty so it gets uploaded on next sync")
    }
}
