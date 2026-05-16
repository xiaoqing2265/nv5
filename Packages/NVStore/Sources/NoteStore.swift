import Foundation
import GRDB
import NVModel
import Observation

@Observable
@MainActor
public final class NoteStore {
    public private(set) var notes: [Note] = []
    public private(set) var archivedNotes: [Note] = []
    public private(set) var observationError: Error?

    private let database: Database
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?
    private nonisolated(unsafe) var archivedObservationTask: Task<Void, Never>?

    public init(database: Database) {
        self.database = database
        startObserving()
        startArchivedObserving()
    }

    deinit {
        observationTask?.cancel()
        archivedObservationTask?.cancel()
    }

    private func startObserving() {
        let writer = database.writer
        observationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Note
                    .filter(Note.Columns.deletedLocally == false)
                    .filter(Note.Columns.archived == false)
                    .order(Note.Columns.modifiedAt.desc)
                    .fetchAll(db)
            }

            do {
                for try await notes in observation.values(in: writer, scheduling: .async(onQueue: DispatchQueue.global(qos: .userInitiated))) {
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

    private func startArchivedObserving() {
        let writer = database.writer
        archivedObservationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Note
                    .filter(Note.Columns.deletedLocally == false)
                    .filter(Note.Columns.archived == true)
                    .order(Note.Columns.modifiedAt.desc)
                    .fetchAll(db)
            }

            do {
                for try await archived in observation.values(in: writer, scheduling: .async(onQueue: DispatchQueue.global(qos: .userInitiated))) {
                    await MainActor.run {
                        self?.archivedNotes = archived
                    }
                }
            } catch {
                // archived observation errors are non-critical, silently ignore
            }
        }
    }

    public func upsert(_ note: Note) async throws {
        let noteID = note.id
        let noteTitle = note.title
        let noteBody = note.body
        let noteBodyAttributes = note.bodyAttributes
        let noteLabels = note.labels
        let noteCreatedAt = note.createdAt
        let noteModifiedAt = note.modifiedAt
        let noteDeletedLocally = note.deletedLocally
        let noteEtag = note.etag
        let noteRemotePath = note.remotePath
        let noteLastSyncedAt = note.lastSyncedAt
        let noteLastSelectedRange = note.lastSelectedRange
        let noteIsEncrypted = note.isEncrypted
        let noteArchived = note.archived

        try await database.writer.write { [noteID, noteTitle, noteBody, noteBodyAttributes, noteLabels, noteCreatedAt, noteModifiedAt, noteDeletedLocally, noteEtag, noteRemotePath, noteLastSyncedAt, noteLastSelectedRange, noteIsEncrypted, noteArchived] db in
            var toSave = Note(
                id: noteID,
                title: noteTitle,
                body: noteBody,
                bodyAttributes: noteBodyAttributes,
                labels: noteLabels,
                createdAt: noteCreatedAt,
                modifiedAt: noteModifiedAt,
                lastSelectedRange: noteLastSelectedRange,
                isEncrypted: noteIsEncrypted,
                etag: noteEtag,
                remotePath: noteRemotePath,
                lastSyncedAt: noteLastSyncedAt,
                localDirty: true,
                deletedLocally: noteDeletedLocally,
                archived: noteArchived
            )
            try toSave.save(db)
        }
    }

    public func setArchived(id: UUID, archived: Bool) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.archived = archived
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }
    }

    public func archivedNotes() async throws -> [Note] {
        return try await database.writer.read { db in
            try Note
                .filter(Note.Columns.archived == true)
                .filter(Note.Columns.deletedLocally == false)
                .order(Note.Columns.modifiedAt.desc)
                .fetchAll(db)
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

    public func purgeDeletedAndSynced() async throws {
        try await database.writer.write { db in
            try Note
                .filter(Note.Columns.deletedLocally == true)
                .filter(Note.Columns.localDirty == false)
                .deleteAll(db)
        }
    }

    public func search(query: String, includeArchived: Bool = false) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let targetNotes: [Note]
        if includeArchived {
            targetNotes = (try? database.writer.read { db in
                try Note.filter(Note.Columns.deletedLocally == false).fetchAll(db)
            }) ?? notes
        } else {
            targetNotes = notes
        }
        
        guard !trimmed.isEmpty else { return targetNotes }

        let tokens = trimmed.split(separator: " ").map(String.init)

        let matched = targetNotes.filter { note in
            tokens.allSatisfy { token in
                note.title.range(of: token, options: .caseInsensitive) != nil
                || note.body.range(of: token, options: .caseInsensitive) != nil
                || note.labels.contains { $0.range(of: token, options: .caseInsensitive) != nil }
            }
        }

        return matched.sorted { lhs, rhs in
            let lhsTitleHit = tokens.allSatisfy {
                lhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            let rhsTitleHit = tokens.allSatisfy {
                rhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            if lhsTitleHit != rhsTitleHit { return lhsTitleHit }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    public func dirtyNotes() async throws -> [Note] {
        try await database.writer.read { db in
            try Note.filter(Note.Columns.localDirty == true).fetchAll(db)
        }
    }

    public func markSynced(id: UUID, etag: String?, remotePath: String) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.etag = etag
            note.remotePath = remotePath
            note.lastSyncedAt = Date()
            note.localDirty = false
            try note.update(db)
        }
    }

    public func appliedTombstoneIDs() async throws -> Set<UUID> {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id FROM applied_tombstone")
            return Set(rows.compactMap { (row: Row) -> UUID? in
                let s: String = row["id"]
                return UUID(uuidString: s)
            })
        }
    }

    public func markTombstoneApplied(_ id: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO applied_tombstone (id, appliedAt) VALUES (?, ?)",
                arguments: [id.uuidString, Date()]
            )
        }
    }
}