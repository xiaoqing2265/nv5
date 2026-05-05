import Foundation
import GRDB
import Combine
import NVModel

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []

    private let database: Database
    private var cancellable: AnyCancellable?

    public init(database: Database) {
        self.database = database
        observeNotes()
    }

    private func observeNotes() {
        let observation = ValueObservation.tracking { db in
            try Note
                .filter(Note.Columns.deletedLocally == false)
                .order(Note.Columns.pinned.desc, Note.Columns.modifiedAt.desc)
                .fetchAll(db)
        }
        cancellable = observation
            .publisher(in: database.writer)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] notes in
                    self?.notes = notes
                }
            )
    }

    public func upsert(_ note: Note) async throws {
        let id = note.id
        let title = note.title
        let body = note.body
        let bodyAttributes = note.bodyAttributes
        let labels = note.labels
        let createdAt = note.createdAt
        let pinned = note.pinned
        let isEncrypted = note.isEncrypted
        let remotePath = note.remotePath
        let etag = note.etag
        let lastSyncedAt = note.lastSyncedAt
        let deletedLocally = note.deletedLocally
        let now = Date()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try database.writer.write { db in
                    var toSave = Note(id: id, title: title, body: body, bodyAttributes: bodyAttributes, labels: labels, createdAt: createdAt, modifiedAt: now, lastSelectedRange: nil, isEncrypted: isEncrypted, pinned: pinned, etag: etag, remotePath: remotePath, lastSyncedAt: lastSyncedAt, localDirty: true, deletedLocally: deletedLocally)
                    try toSave.save(db)
                }
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
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
            let pattern = "%\(query)%"
            return try Note
                .filter(Note.Columns.title.like(pattern) || Note.Columns.body.like(pattern))
                .filter(Note.Columns.deletedLocally == false)
                .order(Note.Columns.pinned.desc, Note.Columns.modifiedAt.desc)
                .fetchAll(db)
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