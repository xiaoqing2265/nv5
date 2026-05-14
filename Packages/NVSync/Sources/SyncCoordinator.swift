import Foundation
import NVModel
import NVStore
import NVCrypto

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

    public init(id: UUID, title: String, body: String, bodyAttributesBase64: String?, labels: [String], createdAt: Date, modifiedAt: Date, isEncrypted: Bool, pinned: Bool) {
        self.schemaVersion = 1
        self.id = id
        self.title = title
        self.body = body
        self.bodyAttributesBase64 = bodyAttributesBase64
        self.labels = labels
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isEncrypted = isEncrypted
        self.pinned = pinned
    }

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

@Observable
@MainActor
public final class SyncCoordinator {
    public private(set) var status: SyncStatus = .idle
    public private(set) var lastSyncDate: Date?
    public private(set) var lastError: Error?

    public enum SyncStatus: Sendable, Equatable {
        case idle, syncing, error(String)
    }

    private let client: any WebDAVClientProtocol
    private let store: NoteStore
    private let database: Database
    private let crypto: CryptoEngine?
    private var timer: Timer?

    public init(client: any WebDAVClientProtocol, store: NoteStore, database: Database, crypto: CryptoEngine? = nil) {
        self.client = client
        self.store = store
        self.database = database
        self.crypto = crypto
        let intervalMinutes = UserDefaults.standard.double(forKey: "syncIntervalMinutes")
        let interval: TimeInterval = intervalMinutes > 0 ? intervalMinutes * 60 : 300
        startPeriodicSync(interval: interval)

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let newMinutes = UserDefaults.standard.double(forKey: "syncIntervalMinutes")
            let newInterval: TimeInterval = newMinutes > 0 ? newMinutes * 60 : 300
            self?.startPeriodicSync(interval: newInterval)
        }
    }

    private func startPeriodicSync(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                do {
                    try await self?.sync()
                } catch {
                    print("[NV5] Periodic sync failed: \(error)")
                }
            }
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
                if note.deletedLocally && (note.localDirty == false) {
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

    private struct EncryptedNoteContainer: Codable {
        let title: String
        let body: String
        let bodyAttributesBase64: String?
        let labels: [String]
    }

    func encryptPayloadIfNeeded(_ payload: RemoteNotePayload) async throws -> RemoteNotePayload {
        guard let crypto = crypto, !payload.isEncrypted else { return payload }
        let container = EncryptedNoteContainer(
            title: payload.title,
            body: payload.body,
            bodyAttributesBase64: payload.bodyAttributesBase64,
            labels: payload.labels
        )
        let data = try JSONEncoder().encode(container)
        let jsonString = String(decoding: data, as: UTF8.self)
        let encryptedData = try await crypto.seal(jsonString)
        return RemoteNotePayload(
            id: payload.id,
            title: "Encrypted",
            body: encryptedData.base64EncodedString(),
            bodyAttributesBase64: nil,
            labels: [],
            createdAt: payload.createdAt,
            modifiedAt: payload.modifiedAt,
            isEncrypted: true,
            pinned: payload.pinned
        )
    }

    func decryptPayloadIfNeeded(_ payload: RemoteNotePayload, noteID: UUID) async throws -> RemoteNotePayload {
        guard payload.isEncrypted, let crypto = crypto else { return payload }
        guard let encryptedData = Data(base64Encoded: payload.body) else {
            throw SyncError.decryptionFailed(noteID: noteID, reason: "Invalid base64 encoding")
        }
        let decryptedString = try await crypto.open(encryptedData)
        let decryptedData = Data(decryptedString.utf8)
        if let container = try? JSONDecoder().decode(EncryptedNoteContainer.self, from: decryptedData) {
            return RemoteNotePayload(
                id: payload.id,
                title: container.title,
                body: container.body,
                bodyAttributesBase64: container.bodyAttributesBase64,
                labels: container.labels,
                createdAt: payload.createdAt,
                modifiedAt: payload.modifiedAt,
                isEncrypted: false,
                pinned: payload.pinned
            )
        } else {
            // Backward compatibility for old schema where only body was encrypted
            guard let fallbackString = String(data: decryptedData, encoding: .utf8) else {
                throw SyncError.decryptionFailed(noteID: noteID, reason: "Invalid utf8 in fallback decryption")
            }
            return RemoteNotePayload(
                id: payload.id,
                title: payload.title,
                body: fallbackString,
                bodyAttributesBase64: payload.bodyAttributesBase64,
                labels: payload.labels,
                createdAt: payload.createdAt,
                modifiedAt: payload.modifiedAt,
                isEncrypted: false,
                pinned: payload.pinned
            )
        }
    }

    private func uploadNew(_ note: Note) async throws {
        let payload = try await encryptPayloadIfNeeded(RemoteNotePayload(from: note))
        let data = try JSONEncoder.iso8601.encode(payload)
        let path = remotePath(for: note)
        let etag = try await client.upload(path: path, data: data, ifMatch: nil)
        try await store.markSynced(id: note.id, etag: etag ?? "", remotePath: path)
    }

    private func uploadUpdate(note: Note, remoteEtag: String?) async throws {
        let payload = try await encryptPayloadIfNeeded(RemoteNotePayload(from: note))
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
        guard let (data, etag) = try await client.download(path: "notes/\(resource.path)", ifNoneMatch: nil) else { return }
        let rawPayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let payload = try await decryptPayloadIfNeeded(rawPayload, noteID: id)
        
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
        guard let (data, etag) = try await client.download(path: "notes/\(resource.path)", ifNoneMatch: nil) else { return }
        let rawPayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let payload = try await decryptPayloadIfNeeded(rawPayload, noteID: id)
        
        let remoteEtag = etag
        let remotePathStr = "notes/\(resource.path)"
        let finalPayload = payload
        try await database.writer.write { db in
            guard let existing = try Note.fetchOne(db, key: id.uuidString) else { return }
            var updated = finalPayload.toNote(preserving: existing)
            updated.etag = remoteEtag
            updated.remotePath = remotePathStr
            updated.lastSyncedAt = Date()
            updated.localDirty = false
            try updated.update(db)
        }
    }

    func resolveConflict(local: Note, remoteResource: WebDAVResource) async throws {
        guard let (data, etag) = try await client.download(path: "notes/\(remoteResource.path)", ifNoneMatch: nil) else { return }
        let rawPayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let remotePayload = try await decryptPayloadIfNeeded(rawPayload, noteID: local.id)

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

        try await database.writer.write { [remoteApplied, conflicted] db in
            guard let existing = try Note.fetchOne(db, key: remoteApplied.id.uuidString) else { return }
            var updated = remoteApplied
            try updated.update(db)
            var newConflicted = conflicted
            try newConflicted.insert(db)
        }
    }

    private func pushDeletion(note: Note) async throws {
        struct Tombstone: Codable {
            let id: UUID
            let deletedAt: Date
        }
        let tombData = try JSONEncoder.iso8601.encode(Tombstone(id: note.id, deletedAt: Date()))
        _ = try await client.upload(path: tombstonePath(for: note.id), data: tombData, ifMatch: nil)

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

public enum SyncError: Error, LocalizedError {
    case decryptionFailed(noteID: UUID, reason: String)

    public var errorDescription: String? {
        switch self {
        case .decryptionFailed(let id, let reason):
            return "无法解密笔记 (\(id.uuidString.prefix(8))…)：\(reason)"
        }
    }
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