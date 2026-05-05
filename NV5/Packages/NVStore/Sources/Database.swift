import Foundation
import GRDB
import NVModel

public final class Database {
    public let writer: DatabaseWriter

    public init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.writer = try DatabasePool(path: url.path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull().indexed()
                t.column("body", .text).notNull()
                t.column("bodyAttributes", .blob)
                t.column("labelsJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("modifiedAt", .datetime).notNull().indexed()
                t.column("lastSelectedLocation", .integer)
                t.column("lastSelectedLength", .integer)
                t.column("isEncrypted", .boolean).notNull().defaults(to: false)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("etag", .text)
                t.column("remotePath", .text).unique()
                t.column("lastSyncedAt", .datetime)
                t.column("localDirty", .boolean).notNull().defaults(to: true)
                t.column("deletedLocally", .boolean).notNull().defaults(to: false)
            }

            try db.create(virtualTable: "note_fts", using: FTS5()) { t in
                t.synchronize(withTable: "note")
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("title")
                t.column("body")
                t.column("labelsJSON")
            }
        }

        try migrator.migrate(writer)
    }
}

extension Note: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "note"

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let body = Column("body")
        static let bodyAttributes = Column("bodyAttributes")
        static let labelsJSON = Column("labelsJSON")
        static let createdAt = Column("createdAt")
        static let modifiedAt = Column("modifiedAt")
        static let lastSelectedLocation = Column("lastSelectedLocation")
        static let lastSelectedLength = Column("lastSelectedLength")
        static let isEncrypted = Column("isEncrypted")
        static let pinned = Column("pinned")
        static let etag = Column("etag")
        static let remotePath = Column("remotePath")
        static let lastSyncedAt = Column("lastSyncedAt")
        static let localDirty = Column("localDirty")
        static let deletedLocally = Column("deletedLocally")
    }

    public init(row: Row) throws {
        var note = Note()
        let idStr: String = row[Columns.id]
        note.id = UUID(uuidString: idStr)!
        note.title = row[Columns.title]
        note.body = row[Columns.body]
        note.bodyAttributes = row[Columns.bodyAttributes]
        let labelsString: String = row[Columns.labelsJSON]
        let labelsData = Data(labelsString.utf8)
        let labelsArray: [String] = (try? JSONDecoder().decode([String].self, from: labelsData)) ?? []
        note.labels = Set(labelsArray)
        note.createdAt = row[Columns.createdAt]
        note.modifiedAt = row[Columns.modifiedAt]
        let loc: Int? = row[Columns.lastSelectedLocation]
        let len: Int? = row[Columns.lastSelectedLength]
        if let l = loc, let le = len {
            note.lastSelectedRange = NSRange(location: l, length: le)
        }
        note.isEncrypted = row[Columns.isEncrypted]
        note.pinned = row[Columns.pinned]
        note.etag = row[Columns.etag]
        note.remotePath = row[Columns.remotePath]
        note.lastSyncedAt = row[Columns.lastSyncedAt]
        note.localDirty = row[Columns.localDirty]
        note.deletedLocally = row[Columns.deletedLocally]
        self = note
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.body] = body
        container[Columns.bodyAttributes] = bodyAttributes
        let labelsData = try JSONEncoder().encode(Array(labels))
        container[Columns.labelsJSON] = String(data: labelsData, encoding: .utf8)
        container[Columns.createdAt] = createdAt
        container[Columns.modifiedAt] = modifiedAt
        container[Columns.lastSelectedLocation] = lastSelectedRange?.location
        container[Columns.lastSelectedLength] = lastSelectedRange?.length
        container[Columns.isEncrypted] = isEncrypted
        container[Columns.pinned] = pinned
        container[Columns.etag] = etag
        container[Columns.remotePath] = remotePath
        container[Columns.lastSyncedAt] = lastSyncedAt
        container[Columns.localDirty] = localDirty
        container[Columns.deletedLocally] = deletedLocally
    }
}

extension Note {
    @MainActor static let fts5MatchAssociation = hasOne(NoteFTS.self, using: ForeignKey(["rowid"]))
}

struct NoteFTS: TableRecord {
    static let databaseTableName = "note_fts"
}

enum DatabaseError: Error {
    case invalidNoteID
}