import Foundation
import GRDB
import NVModel
import NVStore

/// Intents 层依赖的笔记仓库协议，隔离对 @MainActor 具体类型的直接依赖。
public protocol NoteRepository: Sendable {
    func fetchNote(id: UUID) async throws -> Note?
    func search(query: String) async -> [Note]
    func upsert(_ note: Note) async throws
    func fetchAllActiveNotes() async throws -> [Note]
}

/// @MainActor 绑定的 NoteRepository 实现，包装 NoteStore + Database。
@MainActor
public final class MainActorNoteRepository: NoteRepository {
    private let store: NoteStore
    private let database: NVStore.Database

    init(store: NoteStore, database: NVStore.Database) {
        self.store = store
        self.database = database
    }

    public func fetchNote(id: UUID) async throws -> Note? {
        try await database.writer.read { db in
            try Note.fetchOne(db, key: id.uuidString)
        }
    }

    public func search(query: String) async -> [Note] {
        // store.search 返回摘要（截断 body）；Intents/Shortcuts 把 body 作为「内容」暴露，
        // 需要完整正文，故按匹配 id 取完整 Note。
        let summaries = await store.search(query: query)
        var results: [Note] = []
        for summary in summaries {
            if let full = await store.fullNote(id: summary.id) {
                results.append(full)
            }
        }
        return results
    }

    public func upsert(_ note: Note) async throws {
        try await store.upsert(note)
    }

    public func fetchAllActiveNotes() async throws -> [Note] {
        try await database.writer.read { db in
            try Note.filter(Note.Columns.archived == false)
                .filter(Note.Columns.deletedLocally == false)
                .fetchAll(db)
        }
    }
}
