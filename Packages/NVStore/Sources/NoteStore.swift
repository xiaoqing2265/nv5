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
        let noteID = note.id
        let noteTitle = note.title
        let noteBody = note.body
        let noteBodyAttributes = note.bodyAttributes
        let noteLabels = note.labels
        let notePinned = note.pinned
        let noteCreatedAt = note.createdAt
        let noteDeletedLocally = note.deletedLocally
        let noteEtag = note.etag
        let noteRemotePath = note.remotePath
        let noteLastSyncedAt = note.lastSyncedAt
        let noteLastSelectedRange = note.lastSelectedRange
        let noteIsEncrypted = note.isEncrypted

        try await database.writer.write { [noteID, noteTitle, noteBody, noteBodyAttributes, noteLabels, notePinned, noteCreatedAt, noteDeletedLocally, noteEtag, noteRemotePath, noteLastSyncedAt, noteLastSelectedRange, noteIsEncrypted, now] db in
            var toSave = Note(
                id: noteID,
                title: noteTitle,
                body: noteBody,
                bodyAttributes: noteBodyAttributes,
                labels: noteLabels,
                createdAt: noteCreatedAt,
                modifiedAt: now,
                lastSelectedRange: noteLastSelectedRange,
                isEncrypted: noteIsEncrypted,
                pinned: notePinned,
                etag: noteEtag,
                remotePath: noteRemotePath,
                lastSyncedAt: noteLastSyncedAt,
                localDirty: true,
                deletedLocally: noteDeletedLocally
            )
            try toSave.save(db)
        }

        let savedNote = Note(
            id: noteID,
            title: noteTitle,
            body: noteBody,
            bodyAttributes: noteBodyAttributes,
            labels: noteLabels,
            createdAt: noteCreatedAt,
            modifiedAt: now,
            lastSelectedRange: noteLastSelectedRange,
            isEncrypted: noteIsEncrypted,
            pinned: notePinned,
            etag: noteEtag,
            remotePath: noteRemotePath,
            lastSyncedAt: noteLastSyncedAt,
            localDirty: true,
            deletedLocally: noteDeletedLocally
        )

        var newNotes = notes
        if let idx = newNotes.firstIndex(where: { $0.id == savedNote.id }) {
            newNotes[idx] = savedNote
        } else {
            newNotes.insert(savedNote, at: 0)
        }
        notes = newNotes
    }

    public func softDelete(id: UUID) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.deletedLocally = true
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }

        notes = notes.filter { $0.id != id }
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

    public func search(query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }

        let tokens = trimmed.split(separator: " ").map(String.init)

        let matched = notes.filter { note in
            tokens.allSatisfy { token in
                note.title.range(of: token, options: .caseInsensitive) != nil
                || note.body.range(of: token, options: .caseInsensitive) != nil
                || note.labels.contains { $0.range(of: token, options: .caseInsensitive) != nil }
            }
        }

        return matched.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
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