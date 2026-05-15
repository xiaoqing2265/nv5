import AppIntents
import NVModel
import NVStore
import NVExport
import Foundation
import AppKit
import GRDB

struct NV5ShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "在 \(.applicationName) 中新建笔记",
                "使用 \(.applicationName) 创建笔记"
            ],
            shortTitle: "新建笔记",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: ExportNotesByLabelIntent(),
            phrases: [
                "在 \(.applicationName) 中按标签导出笔记"
            ],
            shortTitle: "按标签导出",
            systemImageName: "square.and.arrow.up"
        )
    }
}

struct CreateNoteIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "新建笔记"
    nonisolated(unsafe) static var description = IntentDescription("在 NV5 中创建一条新笔记")

    @Parameter(title: "标题") var noteTitle: String
    @Parameter(title: "内容", default: "") var noteBody: String
    @Parameter(title: "标签") var labels: [String]?

    static var parameterSummary: some ParameterSummary {
        Summary("创建标题为 \(\.$noteTitle) 的笔记")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let note = Note(title: noteTitle, body: noteBody)
        var noteToUpsert = note
        if let lbls = labels {
            noteToUpsert.labels = Set(lbls)
        }
        
        let store = await AppEnvironment.shared.store
        try await store.upsert(noteToUpsert)
        
        return .result(value: NoteEntity(from: noteToUpsert))
    }
}

struct SearchNotesIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "搜索笔记"
    nonisolated(unsafe) static var description = IntentDescription("在 NV5 中搜索笔记")

    @Parameter(title: "搜索词") var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("搜索包含 \(\.$query) 的笔记")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        let notes = await MainActor.run {
            AppEnvironment.shared.store.search(query: query)
        }
        return .result(value: notes.map { NoteEntity(from: $0) })
    }
}

struct GetNoteIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "获取笔记内容"
    nonisolated(unsafe) static var description = IntentDescription("获取一条 NV5 笔记的完整内容")

    @Parameter(title: "笔记") var note: NoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("获取 \(\.$note) 的内容")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let fullNote = try await MainActor.run {
            try AppEnvironment.shared.database.writer.read { db in
                try Note.fetchOne(db, key: note.id)
            }
        }
        guard let note = fullNote else { throw IntentError.noteNotFound }
        return .result(value: note.body)
    }
}

struct ExportNoteIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "导出笔记"
    nonisolated(unsafe) static var description = IntentDescription("将一条 NV5 笔记导出为文件")

    @Parameter(title: "笔记") var note: NoteEntity
    @Parameter(title: "格式", default: "md") var formatExt: String
    @Parameter(title: "保存到 (目录路径)") var destinationPath: String

    static var parameterSummary: some ParameterSummary {
        Summary("将 \(\.$note) 导出为 \(\.$formatExt)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let fullNote = try await MainActor.run {
            try AppEnvironment.shared.database.writer.read { db in
                try Note.fetchOne(db, key: note.id)
            }
        }
        guard let note = fullNote else { throw IntentError.noteNotFound }

        let format = ExportFormat(rawValue: formatExt) ?? .markdown
        let dirURL = URL(fileURLWithPath: destinationPath)

        let service = await MainActor.run { ExportService() }
        let exportedURL = try await service.exportToFile(note, as: format, in: dirURL)

        return .result(value: IntentFile(fileURL: exportedURL))
    }
}

struct ExportNotesByLabelIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "按标签导出笔记"
    nonisolated(unsafe) static var description = IntentDescription("将带有特定标签的所有 NV5 笔记导出到指定文件夹")

    @Parameter(title: "标签") var label: String
    @Parameter(title: "格式", default: "md") var formatExt: String
    @Parameter(title: "保存到 (目录路径)") var destinationPath: String

    static var parameterSummary: some ParameterSummary {
        Summary("导出标签为 \(\.$label) 的笔记到 \(\.$destinationPath)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let allNotes = try await MainActor.run {
            try AppEnvironment.shared.database.writer.read { db in
                try Note.filter(Column("archived") == false)
                    .filter(Column("deletedLocally") == false)
                    .fetchAll(db)
            }
        }

        let filteredNotes = allNotes.filter { $0.labels.contains(label) }
        guard !filteredNotes.isEmpty else { return .result(value: []) }

        let format = ExportFormat(rawValue: formatExt) ?? .markdown
        let dirURL = URL(fileURLWithPath: destinationPath)

        let service = await MainActor.run { ExportService() }
        let exportedURLs = try await service.exportToDirectory(filteredNotes, as: format, in: dirURL)

        return .result(value: exportedURLs.map { IntentFile(fileURL: $0) })
    }
}

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noteNotFound
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noteNotFound: return "找不到该笔记"
        }
    }
}