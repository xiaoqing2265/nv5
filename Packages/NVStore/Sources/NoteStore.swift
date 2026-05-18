import Foundation
import GRDB
import NVModel
import Observation

@Observable
@MainActor
public final class NoteStore {
    public private(set) var notes: [Note] = [] {
        didSet {
            // nvALT 风格：只在笔记数量变化（新增/删除）时清空搜索缓存
            // body/title 更新不影响搜索结果集合，保留缓存避免全量扫表
            if oldValue.count != notes.count {
                lastSearchQuery = ""
                lastSearchResults = []
            }
        }
    }
    public private(set) var archivedNotes: [Note] = []
    public private(set) var observationError: Error?

    private let database: Database
    private var observationTask: Task<Void, Never>?
    private var archivedObservationTask: Task<Void, Never>?

    // nvALT 风格：增量搜索缓存
    private var lastSearchQuery: String = ""
    private var lastSearchResults: [Note] = []

    public init(database: Database) {
        self.database = database
        startObserving()
        startArchivedObserving()
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
        _ = try await database.writer.write { db in
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

        guard !trimmed.isEmpty else {
            // 清空缓存
            lastSearchQuery = ""
            lastSearchResults = []
            return targetNotes
        }

        // nvALT 风格：增量搜索优化
        // Phase 1: 判断是否可以在当前结果中继续搜索
        let searchBase: [Note]
        let lowercaseTrimmed = trimmed.lowercased()
        let lowercaseLastQuery = lastSearchQuery.lowercased()

        if !includeArchived &&
           !lastSearchQuery.isEmpty &&
           lowercaseTrimmed.hasPrefix(lowercaseLastQuery) &&
           !lastSearchResults.isEmpty {
            // 新词是旧词的前缀，在当前结果中继续搜索（增量）
            searchBase = lastSearchResults
        } else {
            // 新词不是旧词的前缀，或缓存为空，从所有笔记开始（全量）
            searchBase = targetNotes
        }

        // Phase 2: 实际搜索
        let tokens = trimmed.split(separator: " ").map(String.init)

        let matched = searchBase.filter { note in
            tokens.allSatisfy { token in
                note.title.range(of: token, options: .caseInsensitive) != nil
                || note.body.range(of: token, options: .caseInsensitive) != nil
                || note.labels.contains { $0.range(of: token, options: .caseInsensitive) != nil }
            }
        }

        let sorted = matched.sorted { lhs, rhs in
            let lhsTitleHit = tokens.allSatisfy {
                lhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            let rhsTitleHit = tokens.allSatisfy {
                rhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            if lhsTitleHit != rhsTitleHit { return lhsTitleHit }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        // Phase 3: 缓存结果（只缓存非归档搜索）
        if !includeArchived {
            lastSearchQuery = trimmed
            lastSearchResults = sorted
        }

        return sorted
    }

    /// nvALT 风格：查找标题以指定前缀开头的笔记（用于自动补全）
    /// 返回最短的匹配标题（优先补全短标题）
    public func noteTitlePrefixedBy(_ prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }

        let lowercasePrefix = prefix.lowercased()
        let matches = notes.filter { note in
            note.title.lowercased().hasPrefix(lowercasePrefix)
        }

        // 返回最短的匹配标题（nvALT 的 prefixParents 逻辑）
        return matches.min(by: { $0.title.count < $1.title.count })?.title
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