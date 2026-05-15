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
                t.column("etag", .text)
                t.column("remotePath", .text).unique()
                t.column("lastSyncedAt", .datetime)
                t.column("localDirty", .boolean).notNull().defaults(to: true)
                t.column("deletedLocally", .boolean).notNull().defaults(to: false)
                t.column("archived", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "applied_tombstone") { t in
                t.column("id", .text).primaryKey()
                t.column("appliedAt", .datetime).notNull()
            }
        }

        try migrator.migrate(writer)
    }
}

extension Note: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "note"

    public enum Columns {
        public static let id = Column("id")
        public static let title = Column("title")
        public static let body = Column("body")
        public static let bodyAttributes = Column("bodyAttributes")
        public static let labelsJSON = Column("labelsJSON")
        public static let createdAt = Column("createdAt")
        public static let modifiedAt = Column("modifiedAt")
        public static let lastSelectedLocation = Column("lastSelectedLocation")
        public static let lastSelectedLength = Column("lastSelectedLength")
        public static let isEncrypted = Column("isEncrypted")
        public static let etag = Column("etag")
        public static let remotePath = Column("remotePath")
        public static let lastSyncedAt = Column("lastSyncedAt")
        public static let localDirty = Column("localDirty")
        public static let deletedLocally = Column("deletedLocally")
        public static let archived = Column("archived")
    }

    public init(row: Row) throws {
        var note = Note()
        let idStr: String = row[Columns.id]
        guard let noteID = UUID(uuidString: idStr) else {
            throw DatabaseError.invalidNoteID
        }
        note.id = noteID
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
        note.etag = row[Columns.etag]
        note.remotePath = row[Columns.remotePath]
        note.lastSyncedAt = row[Columns.lastSyncedAt]
        note.localDirty = row[Columns.localDirty]
        note.deletedLocally = row[Columns.deletedLocally]
        note.archived = row[Columns.archived]
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
        container[Columns.etag] = etag
        container[Columns.remotePath] = remotePath
        container[Columns.lastSyncedAt] = lastSyncedAt
        container[Columns.localDirty] = localDirty
        container[Columns.deletedLocally] = deletedLocally
        container[Columns.archived] = archived
    }
}

enum DatabaseError: Error {
    case invalidNoteID
}