import AppIntents
import NVModel
import Foundation

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

@MainActor
struct NoteEntityQuery: EntityStringQuery {
    private var repo: NoteRepository { AppEnvironment.shared.noteRepository }

    func entities(for identifiers: [String]) async throws -> [NoteEntity] {
        var notes: [Note] = []
        for idStr in identifiers {
            guard let id = UUID(uuidString: idStr) else { continue }
            if let note = try await repo.fetchNote(id: id) {
                notes.append(note)
            }
        }
        return notes.map { NoteEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        let notes = try await repo.fetchAllActiveNotes()
        return Array(notes.prefix(10)).map { NoteEntity(from: $0) }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = await repo.search(query: trimmed)
        return notes.map { NoteEntity(from: $0) }
    }
}