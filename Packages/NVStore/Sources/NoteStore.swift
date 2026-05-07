import Foundation
import GRDB
import NVModel
import Observation

@Observable
@MainActor
public final class NoteStore {
    public private(set) var notes: [Note] = []
    public private(set) var observationError: Error?

    private let database: Database
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    public init(database: Database) {
        self.database = database
        startObserving()
    }

    deinit {
        observationTask?.cancel()
    }

    private func startObserving() {
        let writer = database.writer
        observationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Note
                    .filter(Note.Columns.deletedLocally == false)
                    .order(Note.Columns.pinned.desc, Note.Columns.modifiedAt.desc)
                    .fetchAll(db)
            }

            do {
                for try await notes in observation.values(in: writer) {
                    await MainActor.run {
                        self?.notes = notes
                        self?.observationError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self?.observationError = error
                }
            }
        }
    }

    public func upsert(_ note: Note) async throws {
        let now = Date()
        try await database.writer.write { db in
            var toSave = note
            toSave.modifiedAt = now
            toSave.localDirty = true
            try toSave.save(db)
        }
    }

    public func updateBody(id: UUID, body: String, attributes: Data?, selection: NSRange?) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.body = body
            note.bodyAttributes = attributes
            note.lastSelectedRange = selection
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }
    }

    public func updateTitle(id: UUID, title: String) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.title = title
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.deletedLocally = true
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }
    }

    public func purgeDeletedAndSynced() async throws {
        try await database.writer.write { db in
            try Note
                .filter(Note.Columns.deletedLocally == true)
                .filter(Note.Columns.localDirty == false)
                .deleteAll(db)
        }
    }

    public func search(query: String) async throws -> [Note] {
        guard !query.isEmpty else { return notes }
        return try await database.writer.read { db in
            let ftsQuery = query.split(separator: " ").map { "\"\($0)\"*" }.joined(separator: " ")
            let sql = """
                SELECT note.* FROM note
                JOIN note_fts ON note.rowid = note_fts.rowid
                WHERE note_fts MATCH ?
                AND note.deletedLocally = 0
                ORDER BY note.pinned DESC, note.modifiedAt DESC
                """
            return try Note.fetchAll(db, sql: sql, arguments: [ftsQuery])
        }
    }

    public func dirtyNotes() async throws -> [Note] {
        try await database.writer.read { db in
            try Note.filter(Note.Columns.localDirty == true).fetchAll(db)
        }
    }

    public func markSynced(id: UUID, etag: String, remotePath: String) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.etag = etag
            note.remotePath = remotePath
            note.lastSyncedAt = Date()
            note.localDirty = false
            try note.update(db)
        }
    }
}