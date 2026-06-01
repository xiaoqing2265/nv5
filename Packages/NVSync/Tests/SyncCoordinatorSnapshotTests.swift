import XCTest
@testable import NVModel
@testable import NVStore
@testable import NVSync

@MainActor
final class SyncCoordinatorSnapshotTests: XCTestCase {
    private var tempDBURL: URL!
    private var database: Database!
    private var store: NoteStore!
    private var client: MockWebDAVClient!
    private var coordinator: SyncCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5SyncPerf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
        database = try Database(url: tempDBURL)
        store = NoteStore(database: database)
        client = MockWebDAVClient()
        coordinator = SyncCoordinator(client: client, store: store, database: database)
    }

    override func tearDown() async throws {
        coordinator = nil
        client = nil
        store = nil
        database = nil
        try await super.tearDown()
    }

    func testSyncReadsLocalSnapshotOnceWhenUploadingNewLocalNotes() async throws {
        try await store.upsert(Note(title: "Local one", body: "Body"))
        try await store.upsert(Note(title: "Local two", body: "Body"))

        try await coordinator.sync()

        XCTAssertEqual(coordinator.localSnapshotReadCount, 1)
        let uploadCount = await client.uploadCount()
        XCTAssertEqual(uploadCount, 2)
    }

    func testSyncReadsLocalSnapshotOnceWhenDownloadingRemoteNotes() async throws {
        let remote = Note(title: "Remote", body: "Body", localDirty: false)
        let payload = RemoteNotePayload(from: remote)
        let data = try JSONEncoder.iso8601.encode(payload)
        await client.setMockFile(path: "notes/\(remote.id.uuidString).json", data: data, etag: "remote-etag")

        try await coordinator.sync()

        XCTAssertEqual(coordinator.localSnapshotReadCount, 1)
        let results = await store.search(query: "Remote")
        XCTAssertEqual(results.map(\.id), [remote.id])
    }
}
