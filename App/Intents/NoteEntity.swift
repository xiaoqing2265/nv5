import AppIntents
import NVModel
import NVStore
import Foundation
import GRDB

struct NoteEntity: AppEntity {
    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "笔记"
    nonisolated(unsafe) static var defaultQuery = NoteEntityQuery()

    let id: String
    @Property(title: "标题") var title: String
    @Property(title: "内容") var body: String
    @Property(title: "创建时间") var createdAt: Date
    @Property(title: "修改时间") var modifiedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(String(body.prefix(50)))")
    }
    
    init(from note: Note) {
        self.id = note.id.uuidString
        self.title = note.title
        self.body = note.body
        self.createdAt = note.createdAt
        self.modifiedAt = note.modifiedAt
    }
}

struct NoteEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NoteEntity] {
        return try await MainActor.run {
            let db = AppEnvironment.shared.database
            return try db.writer.read { db in
                try Note.fetchAll(db, keys: identifiers).map { NoteEntity(from: $0) }
            }
        }
    }
    
    func suggestedEntities() async throws -> [NoteEntity] {
        return try await MainActor.run {
            let db = AppEnvironment.shared.database
            return try db.writer.read { db in
                try Note.order(Note.Columns.modifiedAt.desc).limit(10).fetchAll(db).map { NoteEntity(from: $0) }
            }
        }
    }
    
    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await MainActor.run {
            let db = AppEnvironment.shared.database
            return try db.writer.read { db in
                try Note
                    .filter(Note.Columns.deletedLocally == false)
                    .filter(Note.Columns.archived == false)
                    .fetchAll(db)
                    .filter { note in
                        note.title.localizedCaseInsensitiveContains(trimmed)
                        || note.body.localizedCaseInsensitiveContains(trimmed)
                        || note.labels.contains { $0.localizedCaseInsensitiveContains(trimmed) }
                    }
                    .map { NoteEntity(from: $0) }
            }
        }
    }
}