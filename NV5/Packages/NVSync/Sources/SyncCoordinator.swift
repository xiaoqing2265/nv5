import Foundation
import NVModel
import NVStore

public struct RemoteNotePayload: Codable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let title: String
    public let body: String
    public let bodyAttributesBase64: String?
    public let labels: [String]
    public let createdAt: Date
    public let modifiedAt: Date
    public let isEncrypted: Bool
    public let pinned: Bool

    public init(from note: Note) {
        self.schemaVersion = 1
        self.id = note.id
        self.title = note.title
        self.body = note.body
        self.bodyAttributesBase64 = note.bodyAttributes?.base64EncodedString()
        self.labels = Array(note.labels)
        self.createdAt = note.createdAt
        self.modifiedAt = note.modifiedAt
        self.isEncrypted = note.isEncrypted
        self.pinned = note.pinned
    }

    public func toNote(preserving existing: Note? = nil) -> Note {
        var note = existing ?? Note()
        note.id = id
        note.title = title
        note.body = body
        note.bodyAttributes = bodyAttributesBase64.flatMap { Data(base64Encoded: $0) }
        note.labels = Set(labels)
        note.createdAt = createdAt
        note.modifiedAt = modifiedAt
        note.isEncrypted = isEncrypted
        note.pinned = pinned
        return note
    }
}

@MainActor
public final class SyncCoordinator: ObservableObject {
    @Published public private(set) var status: SyncStatus = .idle
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastError: Error?

    public enum SyncStatus: Equatable {
        case idle, syncing, error(String)
    }

    private let client: WebDAVClient
    private let store: NoteStore
    private let database: Database
    private var timer: Timer?

    public init(client: WebDAVClient, store: NoteStore, database: Database) {
        self.client = client
        self.store = store
        self.database = database
        startPeriodicSync(interval: 300)
    }

    private func startPeriodicSync(interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { try? await self?.sync() }
        }
    }

    public func sync() async throws {
        guard status != .syncing else { return }
        status = .syncing
        defer {
            if case .syncing = status { status = .idle }
        }

        do {
            try await client.ensureDirectory("notes")
            try await client.ensureDirectory("tombstones")

            let remoteNotes = try await client.listDirectory(path: "notes")
            let remoteTombstones = try await client.listDirectory(path: "tombstones")

            let remoteByID: [UUID: WebDAVResource] = Dictionary(uniqueKeysWithValues:
                remoteNotes.compactMap { res in
                    guard let id = uuidFromFilename(res.path) else { return nil }
                    return (id, res)
                })
            let tombstoneIDs: Set<UUID> = Set(remoteTombstones.compactMap { uuidFromFilename($0.path) })

            for tombID in tombstoneIDs {
                try await applyRemoteDeletion(id: tombID)
            }

            let allLocal = try await fetchAllLocal()
            let localByID: [UUID: Note] = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

            for (id, resource) in remoteByID where localByID[id] == nil && !tombstoneIDs.contains(id) {
                try await downloadAndInsert(id: id, resource: resource)
            }

            for note in allLocal where note.remotePath == nil && !note.deletedLocally {
                try await uploadNew(note)
            }

            for note in allLocal {
                guard let remote = remoteByID[note.id] else { continue }
                if note.deletedLocally && !note.localDirty == false {
                    try await pushDeletion(note: note)
                } else if note.localDirty && note.etag == remote.etag {
                    try await uploadUpdate(note: note, remoteEtag: remote.etag)
                } else if note.localDirty && note.etag != remote.etag {
                    try await resolveConflict(local: note, remoteResource: remote)
                } else if !note.localDirty && note.etag != remote.etag {
                    try await downloadAndUpdate(id: note.id, resource: remote)
                }
            }

            try await store.purgeDeletedAndSynced()

            lastSyncDate = Date()
            lastError = nil
        } catch {
            lastError = error
            status = .error("\(error)")
            throw error
        }
    }

    private func uuidFromFilename(_ path: String) -> UUID? {
        let name = (path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        return UUID(uuidString: base)
    }

    private func remotePath(for note: Note) -> String {
        "notes/\(note.id.uuidString).json"
    }

    private func tombstonePath(for id: UUID) -> String {
        "tombstones/\(id.uuidString).json"
    }

    private func uploadNew(_ note: Note) async throws {
        let payload = RemoteNotePayload(from: note)
        let data = try JSONEncoder.iso8601.encode(payload)
        let path = remotePath(for: note)
        let etag = try await client.upload(path: path, data: data, ifMatch: nil)
        try await store.markSynced(id: note.id, etag: etag ?? "", remotePath: path)
    }

    private func uploadUpdate(note: Note, remoteEtag: String?) async throws {
        let payload = RemoteNotePayload(from: note)
        let data = try JSONEncoder.iso8601.encode(payload)
        let path = note.remotePath ?? remotePath(for: note)
        do {
            let etag = try await client.upload(path: path, data: data, ifMatch: remoteEtag)
            try await store.markSynced(id: note.id, etag: etag ?? "", remotePath: path)
        } catch WebDAVError.preconditionFailed {
            return
        }
    }

    private func downloadAndInsert(id: UUID, resource: WebDAVResource) async throws {
        guard let (data, etag) = try await client.download(path: "notes/\(resource.path)") else { return }
        let payload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let note = payload.toNote()
        let etagValue = etag
        let pathValue = "notes/\(resource.path)"
        try await database.writer.write { db in
            var mutableNote = note
            mutableNote.etag = etagValue
            mutableNote.remotePath = pathValue
            mutableNote.lastSyncedAt = Date()
            mutableNote.localDirty = false
            try mutableNote.insert(db)
        }
    }

    private func downloadAndUpdate(id: UUID, resource: WebDAVResource) async throws {
        guard let (data, etag) = try await client.download(path: "notes/\(resource.path)") else { return }
        let payload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let remoteEtag = etag
        let remotePathStr = "notes/\(resource.path)"
        try await database.writer.write { db in
            guard let existing = try Note.fetchOne(db, key: id.uuidString) else { return }
            var updated = payload.toNote(preserving: existing)
            updated.etag = remoteEtag
            updated.remotePath = remotePathStr
            updated.lastSyncedAt = Date()
            updated.localDirty = false
            try updated.update(db)
        }
    }

    private func resolveConflict(local: Note, remoteResource: WebDAVResource) async throws {
        guard let (data, etag) = try await client.download(path: "notes/\(remoteResource.path)") else { return }
        let remotePayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)

        var conflicted = local
        conflicted.id = UUID()
        let formatter = ISO8601DateFormatter()
        conflicted.title = "\(local.title) (Conflict \(formatter.string(from: Date())))"
        conflicted.etag = nil
        conflicted.remotePath = nil
        conflicted.lastSyncedAt = nil
        conflicted.localDirty = true

        var remoteApplied = remotePayload.toNote(preserving: local)
        remoteApplied.etag = etag
        remoteApplied.remotePath = "notes/\(remoteResource.path)"
        remoteApplied.lastSyncedAt = Date()
        remoteApplied.localDirty = false

        let conflictedID = conflicted.id
        let conflictedTitle = conflicted.title
        let conflictedBody = conflicted.body
        let conflictedBodyAttributes = conflicted.bodyAttributes
        let conflictedLabels = conflicted.labels
        let conflictedCreatedAt = conflicted.createdAt
        let conflictedModifiedAt = conflicted.modifiedAt
        let conflictedLastSelectedRange = conflicted.lastSelectedRange
        let conflictedIsEncrypted = conflicted.isEncrypted
        let conflictedPinned = conflicted.pinned
        let conflictedEtag = conflicted.etag
        let conflictedRemotePath = conflicted.remotePath
        let conflictedLastSyncedAt = conflicted.lastSyncedAt
        let conflictedLocalDirty = conflicted.localDirty
        let conflictedDeletedLocally = conflicted.deletedLocally

        let remoteAppliedID = remoteApplied.id
        let remoteAppliedTitle = remoteApplied.title
        let remoteAppliedBody = remoteApplied.body
        let remoteAppliedBodyAttributes = remoteApplied.bodyAttributes
        let remoteAppliedLabels = remoteApplied.labels
        let remoteAppliedCreatedAt = remoteApplied.createdAt
        let remoteAppliedModifiedAt = remoteApplied.modifiedAt
        let remoteAppliedLastSelectedRange = remoteApplied.lastSelectedRange
        let remoteAppliedIsEncrypted = remoteApplied.isEncrypted
        let remoteAppliedPinned = remoteApplied.pinned
        let remoteAppliedEtag = remoteApplied.etag
        let remoteAppliedRemotePath = remoteApplied.remotePath
        let remoteAppliedLastSyncedAt = remoteApplied.lastSyncedAt
        let remoteAppliedLocalDirty = remoteApplied.localDirty
        let remoteAppliedDeletedLocally = remoteApplied.deletedLocally

        try await database.writer.write { db in
            guard let existing = try Note.fetchOne(db, key: remoteAppliedID.uuidString) else { return }
            var updated = existing
            updated.title = remoteAppliedTitle
            updated.body = remoteAppliedBody
            updated.bodyAttributes = remoteAppliedBodyAttributes
            updated.labels = remoteAppliedLabels
            updated.createdAt = remoteAppliedCreatedAt
            updated.modifiedAt = remoteAppliedModifiedAt
            updated.lastSelectedRange = remoteAppliedLastSelectedRange
            updated.isEncrypted = remoteAppliedIsEncrypted
            updated.pinned = remoteAppliedPinned
            updated.etag = remoteAppliedEtag
            updated.remotePath = remoteAppliedRemotePath
            updated.lastSyncedAt = remoteAppliedLastSyncedAt
            updated.localDirty = remoteAppliedLocalDirty
            updated.deletedLocally = remoteAppliedDeletedLocally
            try updated.update(db)

            try db.execute(sql: "INSERT INTO note (id, title, body, bodyAttributes, labelsJSON, createdAt, modifiedAt, lastSelectedLocation, lastSelectedLength, isEncrypted, pinned, etag, remotePath, lastSyncedAt, localDirty, deletedLocally) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         arguments: [conflictedID.uuidString, conflictedTitle, conflictedBody, conflictedBodyAttributes, labelsJSON(conflictedLabels), conflictedCreatedAt, conflictedModifiedAt, conflictedLastSelectedRange?.location, conflictedLastSelectedRange?.length, conflictedIsEncrypted, conflictedPinned, conflictedEtag, conflictedRemotePath, conflictedLastSyncedAt, conflictedLocalDirty, conflictedDeletedLocally])
        }
    }

    private func pushDeletion(note: Note) async throws {
        struct Tombstone: Codable {
            let id: UUID
            let deletedAt: Date
        }
        let tombData = try JSONEncoder.iso8601.encode(Tombstone(id: note.id, deletedAt: Date()))
        _ = try await client.upload(path: tombstonePath(for: note.id), data: tombData)

        if let path = note.remotePath {
            try? await client.delete(path: path, ifMatch: nil)
        }

        try await database.writer.write { db in
            guard var n = try Note.fetchOne(db, key: note.id.uuidString) else { return }
            n.localDirty = false
            try n.update(db)
        }
    }

    private func applyRemoteDeletion(id: UUID) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            if !note.deletedLocally {
                note.deletedLocally = true
                note.localDirty = false
                try note.update(db)
            }
        }
    }

    private func fetchAllLocal() async throws -> [Note] {
        try await database.writer.read { db in try Note.fetchAll(db) }
    }
}

private func labelsJSON(_ labels: Set<String>) -> String {
    let labelsData = try? JSONEncoder().encode(Array(labels))
    return String(data: labelsData ?? Data(), encoding: .utf8) ?? "[]"
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}