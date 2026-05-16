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

    public init(id: UUID, title: String, body: String, bodyAttributesBase64: String?, labels: [String], createdAt: Date, modifiedAt: Date, isEncrypted: Bool) {
        self.schemaVersion = 1
        self.id = id
        self.title = title
        self.body = body
        self.bodyAttributesBase64 = bodyAttributesBase64
        self.labels = labels
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isEncrypted = isEncrypted
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

    private var pollTask: Task<Void, Never>?
    private var settingsObserverTask: Task<Void, Never>?
    private var inflightSync: Task<Void, Error>?
    private let syncLock = NSLock()
    private var consecutiveFailures: Int = 0

    public init(client: any WebDAVClientProtocol, store: NoteStore, database: Database, crypto: CryptoEngine? = nil) {
        self.client = client
        self.store = store
        self.database = database
        self.crypto = crypto
        startPeriodicSync()
        observeSettingsChanges()
    }

    private nonisolated func currentInterval() -> TimeInterval {
        let m = UserDefaults.standard.double(forKey: "syncIntervalMinutes")
        return m > 0 ? m * 60 : 300
    }

    private func startPeriodicSync() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: TimeInterval
                let failures: Int
                if let s = self {
                    failures = s.syncLock.withLock { s.consecutiveFailures }
                    let base = s.currentInterval()
                    let backoff = min(base * pow(2.0, Double(failures)), 3600)
                    let jitter = Double.random(in: -0.1...0.1) * backoff
                    interval = backoff + jitter
                } else {
                    interval = 300
                    failures = 0
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                do {
                    try await self?.sync()
                    self?.syncLock.withLock { self?.consecutiveFailures = 0 }
                } catch {
                    self?.syncLock.withLock { self?.consecutiveFailures += 1 }
                    print("[Sync] periodic failed (\(failures + 1)): \(error)")
                }
            }
        }
    }

    private func observeSettingsChanges() {
        settingsObserverTask?.cancel()
        settingsObserverTask = Task { @MainActor [weak self] in
            let stream = NotificationCenter.default
                .notifications(named: UserDefaults.didChangeNotification)
                .map { _ in () }
            for await _ in stream {
                guard !Task.isCancelled else { break }
                if let s = self {
                    s.startPeriodicSync()
                }
            }
        }
    }

    public func sync() async throws {
        let task: Task<Void, Error> = syncLock.withLock {
            if let existing = inflightSync {
                return existing
            }
            let newTask = Task<Void, Error> { [weak self] in
                try await self?.performSync()
            }
            inflightSync = newTask
            return newTask
        }
        defer { syncLock.withLock { inflightSync = nil } }
        try await task.value
    }

    private func performSync() async throws {
        status = .syncing
        defer { if case .syncing = status { status = .idle } }

        do {
            print("[Sync] start")
            try await client.ensureBasePath()
            try await client.ensureDirectoryRecursively("notes")
            try await client.ensureDirectoryRecursively("tombstones")

            let snapshot = try await fetchRemoteSnapshot()
            print("[Sync] remote notes=\(snapshot.notes.count) tombstones=\(snapshot.tombstones.count)")

            try await applyNewTombstones(snapshot.tombstones)
            try await downloadNewRemoteNotes(snapshot)
            try await uploadLocalNewNotes()
            try await reconcileExistingNotes(snapshot)
            try await store.purgeDeletedAndSynced()

            lastSyncDate = Date()
            lastError = nil
            print("[Sync] done")
        } catch {
            lastError = error
            status = .error("\(error)")
            print("[Sync] error: \(error)")
            throw error
        }
    }

    private struct RemoteSnapshot {
        let notes: [UUID: WebDAVResource]
        let tombstones: Set<UUID>
    }

    private func fetchRemoteSnapshot() async throws -> RemoteSnapshot {
        let remoteNotes = try await client.listDirectory(path: "notes")
        let remoteTombstones = try await client.listDirectory(path: "tombstones")
        let notesByID: [UUID: WebDAVResource] = Dictionary(uniqueKeysWithValues:
            remoteNotes.compactMap { res in
                guard let id = uuidFromFilename(res.path) else { return nil }
                return (id, res)
            })
        let tombSet: Set<UUID> = Set(remoteTombstones.compactMap { uuidFromFilename($0.path) })
        return RemoteSnapshot(notes: notesByID, tombstones: tombSet)
    }

    private func applyNewTombstones(_ remoteTombstones: Set<UUID>) async throws {
        let alreadyApplied = try await store.appliedTombstoneIDs()
        let newTombs = remoteTombstones.subtracting(alreadyApplied)
        for id in newTombs {
            try await applyRemoteDeletion(id: id)
            try await store.markTombstoneApplied(id)
        }
    }

    private func applyRemoteDeletion(id: UUID) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.deletedLocally = true
            note.localDirty = false
            note.etag = nil
            note.remotePath = nil
            try note.update(db)
        }
    }

    private func downloadNewRemoteNotes(_ snapshot: RemoteSnapshot) async throws {
        let allLocal = try await fetchAllLocal()
        let localByID = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        for (id, resource) in snapshot.notes
            where localByID[id] == nil && !snapshot.tombstones.contains(id) {
            do {
                try await downloadAndInsert(id: id, resource: resource)
            } catch WebDAVError.notFound {
                continue
            }
        }
    }

    private func uploadLocalNewNotes() async throws {
        let allLocal = try await fetchAllLocal()
        for note in allLocal
            where note.remotePath == nil && note.localDirty && !note.deletedLocally {
            try await uploadNew(note)
        }
    }

    private func reconcileExistingNotes(_ snapshot: RemoteSnapshot) async throws {
        let allLocal = try await fetchAllLocal()
        for note in allLocal {
            guard let remote = snapshot.notes[note.id] else { continue }
            let etagsMatch = note.etag == remote.etag

            if note.deletedLocally && !note.localDirty {
                continue
            }
            if note.deletedLocally && note.localDirty {
                try await pushDeletion(note: note)
            } else if note.localDirty && etagsMatch {
                try await uploadUpdate(note: note, remoteEtag: remote.etag)
            } else if note.localDirty && !etagsMatch {
                try await resolveConflict(local: note, remoteResource: remote)
            } else if !note.localDirty && !etagsMatch {
                do {
                    try await downloadAndUpdate(id: note.id, resource: remote)
                } catch WebDAVError.notFound {
                    continue
                }
            }
        }
    }

    private func uploadNew(_ note: Note) async throws {
        let payload = try await encryptPayloadIfNeeded(RemoteNotePayload(from: note))
        let data = try JSONEncoder.iso8601.encode(payload)
        let path = remotePath(for: note)
        do {
            let etag = try await client.upload(path: path, data: data, ifMatch: nil, ifNoneMatch: "*")
            try await store.markSynced(id: note.id, etag: etag, remotePath: path)
        } catch WebDAVError.preconditionFailed {
            let list = try await client.listDirectory(path: "notes")
            if let res = list.first(where: { uuidFromFilename($0.path) == note.id }) {
                try await resolveConflict(local: note, remoteResource: res)
            }
        }
    }

    private func uploadUpdate(note: Note, remoteEtag: String?) async throws {
        let payload = try await encryptPayloadIfNeeded(RemoteNotePayload(from: note))
        let data = try JSONEncoder.iso8601.encode(payload)
        let path = note.remotePath ?? remotePath(for: note)
        do {
            let etag = try await client.upload(path: path, data: data, ifMatch: remoteEtag, ifNoneMatch: nil)
            try await store.markSynced(id: note.id, etag: etag, remotePath: path)
        } catch WebDAVError.preconditionFailed {
            let list = try await client.listDirectory(path: "notes")
            if let res = list.first(where: { uuidFromFilename($0.path) == note.id }) {
                try await resolveConflict(local: note, remoteResource: res)
            } else {
                try await uploadNew(note)
            }
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

    func resolveConflict(local: Note, remoteResource: WebDAVResource) async throws {
        let downloadResult: (Data, String?)?
        do {
            downloadResult = try await client.download(path: "notes/\(remoteResource.path)", ifNoneMatch: nil)
        } catch WebDAVError.notFound {
            try await uploadNew(local)
            return
        }
        guard let (data, etag) = downloadResult else { return }

        let rawPayload = try JSONDecoder.iso8601.decode(RemoteNotePayload.self, from: data)
        let remotePayload = try await decryptPayloadIfNeeded(rawPayload, noteID: local.id)

        if local.modifiedAt > remotePayload.modifiedAt {
            try await uploadUpdate(note: local, remoteEtag: remoteResource.etag)
        } else {
            var conflicted = local
            conflicted.id = UUID()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            conflicted.title = "\(local.title) (Conflict \(timestamp))"
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
                let r = remoteApplied
                try r.update(db)
                var c = conflicted
                try c.insert(db)
            }
        }
    }

    private func pushDeletion(note: Note) async throws {
        struct Tombstone: Codable { let id: UUID; let deletedAt: Date }
        let tombData = try JSONEncoder.iso8601.encode(Tombstone(id: note.id, deletedAt: Date()))
        _ = try await client.upload(
            path: tombstonePath(for: note.id),
            data: tombData,
            ifMatch: nil,
            ifNoneMatch: nil
        )
        if let path = note.remotePath {
            try? await client.delete(path: path, ifMatch: nil)
        }
        try await store.markTombstoneApplied(note.id)
        try await database.writer.write { db in
            guard var n = try Note.fetchOne(db, key: note.id.uuidString) else { return }
            n.localDirty = false
            try n.update(db)
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

    private func fetchAllLocal() async throws -> [Note] {
        try await database.writer.read { db in
            try Note.fetchAll(db)
        }
    }

    private struct EncryptedNoteContainer: Codable {
        let title: String
        let body: String
        let bodyAttributesBase64: String?
        let labels: [String]
    }

    func encryptPayloadIfNeeded(_ payload: RemoteNotePayload) async throws -> RemoteNotePayload {
        guard payload.isEncrypted else {
            guard let crypto = crypto else { return payload }
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
                isEncrypted: true
            )
        }
        guard crypto != nil else {
            throw SyncError.encryptionRequired(noteID: payload.id)
        }
        return payload
    }

    func decryptPayloadIfNeeded(_ payload: RemoteNotePayload, noteID: UUID) async throws -> RemoteNotePayload {
        guard payload.isEncrypted, let crypto = crypto else { return payload }
        guard let encryptedData = Data(base64Encoded: payload.body) else {
            throw SyncError.decryptionFailed(noteID: noteID, reason: "Invalid base64")
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
                isEncrypted: false
            )
        } else {
            throw SyncError.decryptionFailed(
                noteID: noteID,
                reason: "Decrypted payload does not match expected container schema"
            )
        }
    }
}

public enum SyncError: Error, LocalizedError {
    case decryptionFailed(noteID: UUID, reason: String)
    case encryptionRequired(noteID: UUID)
    public var errorDescription: String? {
        switch self {
        case .decryptionFailed(let id, let reason):
            return "无法解密笔记 (\(id.uuidString.prefix(8))…)：\(reason)"
        case .encryptionRequired(let id):
            return "无法加密笔记 (\(id.uuidString.prefix(8))…)，跳过同步以防止明文泄露"
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