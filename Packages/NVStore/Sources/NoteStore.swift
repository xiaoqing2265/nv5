import Foundation
import GRDB
import NVModel
import Observation

@Observable
@MainActor
public final class NoteStore {
    public private(set) var notes: [NoteSummary] = [] {
        didSet {
            clearSearchCache()
        }
    }
    public private(set) var archivedNotes: [NoteSummary] = []
    public private(set) var observationError: Error?

    private let database: Database
    private var observationTask: Task<Void, Never>?
    private var archivedObservationTask: Task<Void, Never>?

    // nvALT 风格：增量搜索缓存
    private var lastSearchQuery: String = ""
    private var lastSearchResults: [NoteSummary] = []

    private func clearSearchCache() {
        lastSearchQuery = ""
        lastSearchResults = []
    }

    public init(database: Database) {
        self.database = database
        startObserving()
        startArchivedObserving()
    }

    /// 轻量观察：只查摘要列（body 截断 200 字符，不含 bodyAttributes），降低内存和 diff 开销
    // nonisolated：常量 SQL，需可从后台的 @Sendable 观察闭包引用（Swift 6 严格并发）。
    private nonisolated static let summarySQL = """
        SELECT id, title, substr(body, 1, 200) AS body, NULL AS bodyAttributes,
               labelsJSON, createdAt, modifiedAt, lastSelectedLocation, lastSelectedLength,
               isEncrypted, etag, remotePath, lastSyncedAt, localDirty, deletedLocally, archived
        FROM note WHERE deletedLocally = 0 AND archived = 0
        ORDER BY modifiedAt DESC
        """

    private func startObserving() {
        let writer = database.writer
        observationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Note.fetchAll(db, sql: NoteStore.summarySQL)
            }

            do {
                for try await notes in observation.values(in: writer, scheduling: .async(onQueue: DispatchQueue.global(qos: .userInitiated))) {
                    let summaries = notes.map(NoteSummary.init(from:))
                    await MainActor.run {
                        self?.notes = summaries
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

    private nonisolated static let archivedSummarySQL = """
        SELECT id, title, substr(body, 1, 200) AS body, NULL AS bodyAttributes,
               labelsJSON, createdAt, modifiedAt, lastSelectedLocation, lastSelectedLength,
               isEncrypted, etag, remotePath, lastSyncedAt, localDirty, deletedLocally, archived
        FROM note WHERE deletedLocally = 0 AND archived = 1
        ORDER BY modifiedAt DESC
        """

    private func startArchivedObserving() {
        let writer = database.writer
        archivedObservationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Note.fetchAll(db, sql: NoteStore.archivedSummarySQL)
            }

            do {
                for try await archived in observation.values(in: writer, scheduling: .async(onQueue: DispatchQueue.global(qos: .userInitiated))) {
                    let summaries = archived.map(NoteSummary.init(from:))
                    await MainActor.run {
                        self?.archivedNotes = summaries
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

    public func updateBodyText(id: UUID, body: String, selection: NSRange?) async throws {
        try await database.writer.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else { return }
            note.body = body
            note.lastSelectedRange = selection
            note.modifiedAt = Date()
            note.localDirty = true
            try note.update(db)
        }
    }

    /// 读取完整笔记（含未截断 body 与 bodyAttributes），用于编辑等需要完整内容的场景。
    /// 内存中的 notes/archivedNotes 与 search 结果都是摘要投影（body 截断 200 字、
    /// bodyAttributes 为 NULL），直接拿去编辑会在保存时用截断内容覆盖完整正文，造成数据丢失。
    public func fullNote(id: UUID) async -> Note? {
        try? await database.writer.read { db in
            try Note.fetchOne(db, key: id.uuidString)
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

    /// 搜索笔记：通过数据库 LIKE 查询全文（因为内存中 notes 只含截断 body）
    /// 结果同样为摘要级别（body 截断 200 字符，不含 bodyAttributes）
    public func search(query: String, includeArchived: Bool = false) async -> [NoteSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            clearSearchCache()
            return includeArchived ? notes + archivedNotes : notes
        }

        // nvALT 风格：增量搜索优化
        let lowercaseTrimmed = trimmed.lowercased()
        let lowercaseLastQuery = lastSearchQuery.lowercased()

        // 如果是前缀扩展且有缓存，直接在缓存中过滤（缓存已是摘要级别，title 匹配即可）
        if !includeArchived &&
           !lastSearchQuery.isEmpty &&
           lowercaseTrimmed.hasPrefix(lowercaseLastQuery) &&
           !lastSearchResults.isEmpty {
            let tokens = trimmed.split(separator: " ").map(String.init)
            let narrowed = lastSearchResults.filter { note in
                tokens.allSatisfy { token in
                    note.title.range(of: token, options: .caseInsensitive) != nil
                    || note.body.range(of: token, options: .caseInsensitive) != nil
                    || note.labels.contains { $0.range(of: token, options: .caseInsensitive) != nil }
                }
            }
            lastSearchQuery = trimmed
            lastSearchResults = narrowed
            return narrowed
        }

        // 全量搜索：通过数据库 LIKE 查询（body 可能很长，不适合内存扫描）
        let tokens = trimmed.split(separator: " ").map(String.init)
        let results: [Note] = (try? await database.writer.read { db in
            // 构建 WHERE 子句：每个 token 必须在 title/body/labelsJSON 中出现
            var conditions: [String] = ["deletedLocally = 0"]
            if !includeArchived {
                conditions.append("archived = 0")
            }
            var arguments: [String] = []
            for token in tokens {
                // 转义 LIKE 通配符（\ % _），按字面匹配——查询里的 % 和 _ 应作为
                // 普通字符，不能被当作通配或被删除（删除会改变语义，漏掉含下划线/百分号的笔记）。
                // SQLite 的 LIKE 对 ASCII 默认大小写不敏感，无需额外 COLLATE NOCASE。
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let like = "%\(escaped)%"
                conditions.append("(title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR labelsJSON LIKE ? ESCAPE '\\')")
                arguments.append(contentsOf: [like, like, like])
            }
            let whereClause = conditions.joined(separator: " AND ")
            let sql = """
                SELECT id, title, substr(body, 1, 200) AS body, NULL AS bodyAttributes,
                       labelsJSON, createdAt, modifiedAt, lastSelectedLocation, lastSelectedLength,
                       isEncrypted, etag, remotePath, lastSyncedAt, localDirty, deletedLocally, archived
                FROM note WHERE \(whereClause)
                ORDER BY modifiedAt DESC
                """
            return try Note.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }) ?? []

        // 转为摘要（DB 投影已截断 body、置空 bodyAttributes）
        let summaries = results.map(NoteSummary.init(from:))

        // 标题优先排序
        let sorted = summaries.sorted { lhs, rhs in
            let lhsTitleHit = tokens.allSatisfy {
                lhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            let rhsTitleHit = tokens.allSatisfy {
                rhs.title.range(of: $0, options: .caseInsensitive) != nil
            }
            if lhsTitleHit != rhsTitleHit { return lhsTitleHit }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        // 缓存结果（只缓存非归档搜索）
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
