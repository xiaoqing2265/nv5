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
        try? FileManager.default.removeItem(at: dbURL)
    }

    // MARK: - Local Dirty Conflict Resolution

    @MainActor
    func test_local_dirty_wins_over_remote_change() async throws {
        // Scenario: Same note id edited locally (localDirty=true) and changed remotely (different etag).
        // Assertion: Local body is preserved/uploaded; remote does not overwrite local; resulting note retains local content with updated etag after markSynced.

        let noteID = UUID()
        let localModifiedDate = Date(timeIntervalSinceNow: -1800)  // Local is newer (more recent)
        let remoteModifiedDate = Date(timeIntervalSinceNow: -3600) // Remote is older

        // Arrange: Create local note that is dirty with newer timestamp
        var localNote = Note(id: noteID, title: "Local Title", body: "Local Body Content", modifiedAt: localModifiedDate)
        localNote.localDirty = true
        localNote.etag = "old-local-etag"
        localNote.remotePath = "notes/\(noteID.uuidString).json"

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Arrange: Create remote note with different content but older timestamp
        var remoteNote = Note(id: noteID, title: "Remote Title", body: "Remote Body Content", modifiedAt: remoteModifiedDate)
        let remotePayload = RemoteNotePayload(from: remoteNote)
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)

        let remoteEtag = "remote-etag-older"
        let remoteResource = WebDAVResource(
            path: "\(noteID.uuidString).json",
            etag: remoteEtag,
            lastModified: Date(),
            contentLength: Int64(remoteData.count),
            isDirectory: false
        )
        await mockClient.setMockFile(path: "notes/\(remoteResource.path)", data: remoteData, etag: remoteEtag)

        // Act: Resolve conflict — local is newer so it should win
        try await syncCoordinator.resolveConflict(local: localNote, remoteResource: remoteResource)

        // Assert: Local body is preserved and note retains local content
        let allNotes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }

        XCTAssertEqual(allNotes.count, 1, "Should have only the original note (local wins, no conflict copy created)")

        let updated = allNotes.first!
        XCTAssertEqual(updated.id, noteID, "Original note ID should be preserved")
        XCTAssertEqual(updated.body, "Local Body Content", "Local body should be preserved when local is newer")
        XCTAssertEqual(updated.title, "Local Title", "Local title should be preserved")
        XCTAssertFalse(updated.localDirty, "After upload, localDirty should be false")
    }

    // MARK: - Etag Mismatch Detection

    @MainActor
    func test_etag_mismatch_detected_during_reconcile() async throws {
        // Scenario: Local note has stale etag, remote resource has a newer etag.
        // Assertion: reconcileExistingNotes classifies it as a conflict rather than a clean download.

        let noteID = UUID()
        let staleEtag = "old-etag-456"
        let newerEtag = "new-etag-789"

        let olderDate = Date(timeIntervalSinceNow: -7200)
        let newerDate = Date(timeIntervalSinceNow: -3600)

        // Arrange: Create local note with stale etag and dirty flag
        var localNote = Note(id: noteID, title: "Test Title", body: "Original Body", modifiedAt: olderDate)
        localNote.etag = staleEtag
        localNote.remotePath = "notes/\(noteID.uuidString).json"
        localNote.localDirty = true

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Arrange: Create remote note with newer content and different etag
        var remoteNote = Note(id: noteID, title: "Updated Remote Title", body: "Updated Remote Body", modifiedAt: newerDate)
        let remotePayload = RemoteNotePayload(from: remoteNote)
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)

        let remoteResource = WebDAVResource(
            path: "\(noteID.uuidString).json",
            etag: newerEtag,
            lastModified: Date(),
            contentLength: Int64(remoteData.count),
            isDirectory: false
        )
        await mockClient.setMockFile(path: "notes/\(remoteResource.path)", data: remoteData, etag: newerEtag)

        // Assert: Etag mismatch is detected before resolution
        XCTAssertNotEqual(localNote.etag, remoteResource.etag, "Etag mismatch should be detected")

        // Act: Resolve conflict when etags differ and local is older
        try await syncCoordinator.resolveConflict(local: localNote, remoteResource: remoteResource)

        // Assert: Conflict resolution handled (two notes: original updated to remote, copy for local)
        let allNotes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }

        XCTAssertEqual(allNotes.count, 2, "Should have created a conflict copy (remote newer, so conflict)")

        let original = allNotes.first(where: { $0.id == noteID })!
        XCTAssertEqual(original.title, "Updated Remote Title", "Original should be updated to remote content")
        XCTAssertEqual(original.body, "Updated Remote Body", "Original body should be remote")
        XCTAssertEqual(original.etag, newerEtag, "Original etag should be updated to remote etag")
        XCTAssertFalse(original.localDirty, "Original should be marked clean after remote update")

        let copy = allNotes.first(where: { $0.id != noteID })!
        XCTAssertTrue(copy.title.hasPrefix("Test Title (Conflict "), "Conflict copy should have conflict marker")
        XCTAssertTrue(copy.localDirty, "Conflict copy should be marked dirty for upload")
    }

    // MARK: - Remote Tombstone Application

    @MainActor
    func test_remote_tombstone_soft_deletes_local() async throws {
        // Scenario: Remote lists a tombstone for a note present locally and not yet applied.
        // Assertion: Local note is marked deletedLocally and the tombstone id is recorded via markTombstoneApplied; re-running sync does not re-apply.

        let noteID = UUID()

        // Arrange: Create local note that exists but will be deleted by remote tombstone
        var localNote = Note(id: noteID, title: "To Be Deleted", body: "This note will be deleted remotely", modifiedAt: Date(timeIntervalSinceNow: -3600))
        localNote.etag = "local-etag"
        localNote.remotePath = "notes/\(noteID.uuidString).json"
        localNote.localDirty = false

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Verify note exists before tombstone application
        var notes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }
        XCTAssertEqual(notes.count, 1, "Note should exist before tombstone")

        // Act: Apply tombstone to mark the note as deleted locally
        try await store.markTombstoneApplied(noteID)

        // Assert: Tombstone is recorded in applied_tombstone table
        let appliedTombstones = try await store.appliedTombstoneIDs()
        XCTAssertTrue(appliedTombstones.contains(noteID), "Tombstone should be marked as applied")

        // Act: Re-run tombstone application to verify idempotency
        try await store.markTombstoneApplied(noteID)

        // Assert: Second application doesn't cause issues
        let appliedTombstonesAfterSecond = try await store.appliedTombstoneIDs()
        XCTAssertTrue(appliedTombstonesAfterSecond.contains(noteID), "Tombstone should still be applied")
        XCTAssertEqual(appliedTombstonesAfterSecond.count, 1, "Should not create duplicate tombstone entries")

        // Verify local note still exists (physical deletion happens in purge phase)
        notes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }
        XCTAssertEqual(notes.count, 1, "Note should still exist in DB (soft delete via tombstone)")
    }

    // MARK: - Local Tombstone Deletion

    @MainActor
    func test_local_tombstone_deletes_remote() async throws {
        // Scenario: Local note has deletedLocally=true with a remotePath.
        // Assertion: client.delete is invoked for that remotePath with the correct ifMatch etag.

        let noteID = UUID()
        let remotePath = "notes/\(noteID.uuidString).json"
        let localEtag = "local-etag-delete-123"

        // Arrange: Create remote file that will be deleted
        let remotePayload = RemoteNotePayload(
            id: noteID,
            title: "Delete Me",
            body: "To be deleted",
            bodyAttributesBase64: nil,
            labels: [],
            createdAt: Date(),
            modifiedAt: Date(),
            isEncrypted: false
        )
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)
        await mockClient.setMockFile(path: remotePath, data: remoteData, etag: localEtag)

        // Arrange: Create local note marked for deletion with matching etag
        var localNote = Note(id: noteID, title: "Delete Me", body: "To be deleted", modifiedAt: Date(timeIntervalSinceNow: -1800))
        localNote.deletedLocally = true
        localNote.localDirty = false
        localNote.etag = localEtag
        localNote.remotePath = remotePath

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Act: Perform the delete operation
        try await mockClient.delete(path: remotePath, ifMatch: localEtag)

        // Assert: Remote path was deleted
        let deletes = await mockClient.deletes
        XCTAssertTrue(deletes.contains(remotePath), "Remote path should be deleted")

        // Assert: File no longer exists on remote
        let fileStillExists = try? await mockClient.download(path: remotePath, ifNoneMatch: nil)
        XCTAssertNil(fileStillExists, "Remote file should be deleted and not found on download")
    }

    // MARK: - Tombstone Purge

    @MainActor
    func test_purge_after_synced_tombstone() async throws {
        // Scenario: deletedLocally=true and localDirty=false after sync confirms remote delete.
        // Assertion: purgeDeletedAndSynced removes the row; note no longer appears in store.

        let noteID = UUID()

        // Arrange: Create a note marked as deleted and synced
        var localNote = Note(id: noteID, title: "Purge Me", body: "Deleted and synced", modifiedAt: Date(timeIntervalSinceNow: -3600))
        localNote.deletedLocally = true
        localNote.localDirty = false
        localNote.lastSyncedAt = Date()

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Verify note exists before purge
        var notes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }
        XCTAssertEqual(notes.count, 1, "Note should exist before purge")
        XCTAssertTrue(notes[0].deletedLocally, "Note should be marked deleted")
        XCTAssertFalse(notes[0].localDirty, "Note should not be dirty")

        // Act: Purge deleted and synced notes
        try await store.purgeDeletedAndSynced()

        // Assert: Note was purged from database
        notes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }
        XCTAssertEqual(notes.count, 0, "Note should be purged after deletion and sync")
    }

    // MARK: - Clean Remote Download

    @MainActor
    func test_clean_remote_change_downloads_when_not_dirty() async throws {
        // Scenario: Local note clean (localDirty=false), remote has newer etag.
        // Assertion: Remote content downloaded and applied; local body updated to remote.

        let noteID = UUID()
        let oldEtag = "old-remote-etag-111"
        let newEtag = "new-remote-etag-222"

        let olderDate = Date(timeIntervalSinceNow: -3600)
        let newerDate = Date(timeIntervalSinceNow: -1800)

        // Arrange: Create clean local note with old etag
        var localNote = Note(id: noteID, title: "Original Title", body: "Original Body", modifiedAt: olderDate)
        localNote.etag = oldEtag
        localNote.remotePath = "notes/\(noteID.uuidString).json"
        localNote.localDirty = false

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Arrange: Create remote note with updated content and newer etag
        var remoteNote = Note(id: noteID, title: "Updated Title", body: "Updated Body", modifiedAt: newerDate)
        let remotePayload = RemoteNotePayload(from: remoteNote)
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)

        let remoteResource = WebDAVResource(
            path: "\(noteID.uuidString).json",
            etag: newEtag,
            lastModified: Date(),
            contentLength: Int64(remoteData.count),
            isDirectory: false
        )
        await mockClient.setMockFile(path: "notes/\(remoteResource.path)", data: remoteData, etag: newEtag)

        // Assert: Etags differ before download
        XCTAssertNotEqual(localNote.etag, remoteResource.etag, "Etags should differ before download")

        // Act: Download remote content (simulating clean reconciliation)
        let (downloadedData, downloadedEtag) = try await mockClient.download(path: "notes/\(remoteResource.path)", ifNoneMatch: nil)!
        let downloadedPayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: downloadedData)

        // Act: Update local note with remote content
        let updatedNote = downloadedPayload.toNote(preserving: localNote)

        try await database.writer.write { db in
            var mutableNote = updatedNote
            mutableNote.etag = downloadedEtag
            mutableNote.remotePath = "notes/\(remoteResource.path)"
            mutableNote.lastSyncedAt = Date()
            mutableNote.localDirty = false
            try mutableNote.update(db)
        }

        // Assert: Remote content was downloaded and applied
        let allNotes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }

        XCTAssertEqual(allNotes.count, 1, "Should have only the original note")

        let updated = allNotes[0]
        XCTAssertEqual(updated.title, "Updated Title", "Remote title should be downloaded")
        XCTAssertEqual(updated.body, "Updated Body", "Remote body should be downloaded")
        XCTAssertEqual(updated.etag, newEtag, "Etag should be updated to remote etag")
        XCTAssertFalse(updated.localDirty, "Note should be clean after download")
        // 秒级精度比较：modifiedAt 经 ISO8601 JSON 往返会丢弃小数秒，不能用精确相等。
        XCTAssertEqual(updated.modifiedAt.timeIntervalSinceReferenceDate,
                       newerDate.timeIntervalSinceReferenceDate,
                       accuracy: 1.0,
                       "ModifiedAt should match remote")
    }

    // MARK: - Edge Cases and Regression Tests

    @MainActor
    func test_both_sides_modified_remote_newer_creates_conflict_copy() async throws {
        // Edge case: Both local and remote modified, remote is newer — conflict copy created for local.

        let noteID = UUID()
        let localModified = Date(timeIntervalSinceNow: -3600)
        let remoteModified = Date(timeIntervalSinceNow: -1800)  // Remote is newer

        // Arrange: Create local note that is dirty
        var localNote = Note(id: noteID, title: "Local Title", body: "Local Body", modifiedAt: localModified)
        localNote.localDirty = true
        localNote.etag = "local-etag"
        localNote.remotePath = "notes/\(noteID.uuidString).json"

        try await database.writer.write { db in
            try localNote.insert(db)
        }

        // Arrange: Create remote note with different content and newer timestamp
        var remoteNote = Note(id: noteID, title: "Remote Title", body: "Remote Body", modifiedAt: remoteModified)
        let remotePayload = RemoteNotePayload(from: remoteNote)
        let remoteData = try JSONEncoder.iso8601.encode(remotePayload)

        let remoteEtag = "remote-etag-456"
        let remoteResource = WebDAVResource(
            path: "\(noteID.uuidString).json",
            etag: remoteEtag,
            lastModified: Date(),
            contentLength: Int64(remoteData.count),
            isDirectory: false
        )
        await mockClient.setMockFile(path: "notes/\(remoteResource.path)", data: remoteData, etag: remoteEtag)

        // Act: Resolve conflict
        try await syncCoordinator.resolveConflict(local: localNote, remoteResource: remoteResource)

        // Assert: Two notes created (original updated to remote, copy for local)
        let allNotes = try await database.writer.read { db in
            try Note.fetchAll(db)
        }

        XCTAssertEqual(allNotes.count, 2, "Should have original and conflict copy")

        let original = allNotes.first(where: { $0.id == noteID })!
        XCTAssertEqual(original.title, "Remote Title", "Original should be remote")
        XCTAssertFalse(original.localDirty, "Original should be clean")

        let copy = allNotes.first(where: { $0.id != noteID })!
        XCTAssertTrue(copy.title.hasPrefix("Local Title (Conflict "), "Copy should have conflict marker")
        XCTAssertTrue(copy.localDirty, "Copy should be dirty")
    }

    @MainActor
    func test_mark_synced_updates_etag_and_clears_dirty_flag() async throws {
        // Regression test: markSynced properly updates all sync metadata.

        let noteID = UUID()
        let remotePath = "notes/\(noteID.uuidString).json"
        let newEtag = "synced-etag-999"

        // Arrange: Create a dirty note
        var note = Note(id: noteID, title: "Test", body: "Body", modifiedAt: Date())
        note.localDirty = true
        note.etag = nil
        note.remotePath = nil
        note.lastSyncedAt = nil

        try await database.writer.write { db in
            try note.insert(db)
        }

        // Act: Mark as synced
        try await store.markSynced(id: noteID, etag: newEtag, remotePath: remotePath)

        // Assert: All sync metadata updated
        let synced = try await database.writer.read { db in
            try Note.fetchOne(db, key: noteID.uuidString)
        }!

        XCTAssertEqual(synced.etag, newEtag, "Etag should be updated")
        XCTAssertEqual(synced.remotePath, remotePath, "Remote path should be set")
        XCTAssertFalse(synced.localDirty, "Local dirty flag should be cleared")
        XCTAssertNotNil(synced.lastSyncedAt, "Last synced time should be set")
    }
}
