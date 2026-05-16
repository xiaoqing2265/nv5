import XCTest
import GRDB
@testable import NVModel
@testable import NVStore

@MainActor
final class DatabaseMigrationTests: XCTestCase {

    private var tempDBURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
        try await super.tearDown()
    }

    func testFreshDatabaseHasAllColumns() async throws {
        let db = try Database(url: tempDBURL)
        _ = NoteStore(database: db)

        let hasArchived = try await db.writer.read { db in
            let sql = "PRAGMA table_info(note)"
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.contains { row in
                let name: String = row["name"]
                return name == "archived"
            }
        }
        XCTAssertTrue(hasArchived, "archived column should exist in fresh database")

        let hasTombstoneTable = try await db.writer.read { db in
            try db.tableExists("applied_tombstone")
        }
        XCTAssertTrue(hasTombstoneTable, "applied_tombstone table should exist in fresh database")

        let note = Note(title: "Test", body: "Body")
        try await db.writer.write { db in
            var n = note
            try n.insert(db)
        }

        let fetched = try await db.writer.read { db in
            try Note.fetchOne(db, key: note.id.uuidString)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test")
    }

    func testUpsertPreservesModifiedAt() async throws {
        let db = try Database(url: tempDBURL)
        let store = NoteStore(database: db)

        let originalDate = Date(timeIntervalSince1970: 1_000_000)
        let note = Note(id: UUID(), title: "Test", body: "Body", createdAt: originalDate, modifiedAt: originalDate)
        try await store.upsert(note)

        let fetched = try await db.writer.read { db in
            try Note.fetchOne(db, key: note.id.uuidString)
        }
        XCTAssertEqual(fetched?.modifiedAt, originalDate, "modifiedAt should be preserved from input note")
    }

    func testUpdateTitleSetsModifiedAt() async throws {
        let db = try Database(url: tempDBURL)
        let store = NoteStore(database: db)

        let note = Note(title: "Old Title", body: "Body")
        try await store.upsert(note)

        try await store.updateTitle(id: note.id, title: "New Title")

        let fetched = try await db.writer.read { db in
            try Note.fetchOne(db, key: note.id.uuidString)
        }
        XCTAssertGreaterThan(fetched?.modifiedAt ?? .distantPast, note.modifiedAt, "modifiedAt should be updated")
        XCTAssertEqual(fetched?.title, "New Title")
    }

    func testTombstoneApplication() async throws {
        let db = try Database(url: tempDBURL)
        let store = NoteStore(database: db)

        let tombstoneID = UUID()
        try await store.markTombstoneApplied(tombstoneID)

        let appliedIDs = try await store.appliedTombstoneIDs()
        XCTAssertTrue(appliedIDs.contains(tombstoneID))
    }
}
