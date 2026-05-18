import Foundation
import AppKit
import NVModel
import NVStore
import NVExport

/// 笔记 CRUD、导出、同步等业务逻辑。
/// 不持有 observable 状态，通过闭包回调更新 AppCoordinator 状态。
@MainActor
final class NoteActionManager {
    private var exportService = ExportService()
    private weak var store: NoteStore?
    private var isCreatingNote = false

    init(store: NoteStore?) {
        self.store = store
    }

    // MARK: - Create

    func newNote(onCreated: (Note) -> Void) async -> UUID? {
        guard !isCreatingNote else { return nil }
        isCreatingNote = true
        defer { isCreatingNote = false }
        let note = Note(title: "")
        do {
            try await store?.upsert(note)
        } catch {
            print("[NV5] Failed to create note: \(error)")
            return nil
        }
        onCreated(note)
        return note.id
    }

    func newNoteFromQuery(query: String, onCreated: (Note) -> Void) async -> UUID? {
        guard !isCreatingNote else { return nil }
        isCreatingNote = true
        defer { isCreatingNote = false }
        let title = query.isEmpty ? "无标题" : query
        let note = Note(title: title)
        do {
            try await store?.upsert(note)
        } catch {
            print("[NV5] Failed to create note: \(error)")
            return nil
        }
        onCreated(note)
        return note.id
    }

    func newNoteFromURL(title: String, body: String, onCreated: (Note) -> Void, onError: (Error) -> Void) async {
        let titleToUse = title.isEmpty ? "无标题" : title
        let note = Note(title: titleToUse, body: body)
        do {
            try await store?.upsert(note)
            onCreated(note)
        } catch {
            onError(error)
        }
    }

    // MARK: - Archive

    func setArchived(id: UUID, archived: Bool) {
        Task {
            do {
                try await store?.setArchived(id: id, archived: archived)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "操作失败"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Export

    func copyAsMarkdown(selectedNoteID: UUID?, notes: [Note]) {
        copyToClipboard(selectedNoteID: selectedNoteID, notes: notes, format: .markdown)
    }

    func copyAsRichText(selectedNoteID: UUID?, notes: [Note]) {
        copyToClipboard(selectedNoteID: selectedNoteID, notes: notes, format: .richText)
    }

    func copyAsPlainText(selectedNoteID: UUID?, notes: [Note]) {
        copyToClipboard(selectedNoteID: selectedNoteID, notes: notes, format: .plainText)
    }

    private func copyToClipboard(selectedNoteID: UUID?, notes: [Note], format: ExportFormat) {
        guard let id = selectedNoteID, let note = notes.first(where: { $0.id == id }) else { return }
        do {
            try exportService.copyToClipboard(note, as: format)
        } catch {
            showError(error)
        }
    }

    func exportCurrentNote(multiSelectionMode: Bool, selectedNoteID: UUID?, selectedNoteIDs: Set<UUID>, notes: [Note]) {
        if multiSelectionMode {
            exportSelectedNotes(selectedNoteIDs: selectedNoteIDs, notes: notes)
            return
        }
        guard let id = selectedNoteID, let note = notes.first(where: { $0.id == id }) else { return }
        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        guard let dir = ExportPreferences.exportDirectory else {
            showExportPanel(selectedNoteID: selectedNoteID, selectedNoteIDs: selectedNoteIDs, notes: notes)
            return
        }
        let accessing = dir.startAccessingSecurityScopedResource()
        Task {
            defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await exportService.exportToFile(note, as: format, in: dir)
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    func exportSelectedNotes(selectedNoteIDs: Set<UUID>, notes: [Note]) {
        guard !selectedNoteIDs.isEmpty else { return }
        let notesToExport = notes.filter { selectedNoteIDs.contains($0.id) }
        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        guard let dir = ExportPreferences.exportDirectory else {
            showExportPanel(selectedNoteID: nil, selectedNoteIDs: selectedNoteIDs, notes: notes)
            return
        }
        let accessing = dir.startAccessingSecurityScopedResource()
        Task {
            defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await exportService.exportToDirectory(notesToExport, as: format, in: dir)
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    func shareCurrentNote(from view: NSView, selectedNoteID: UUID?, notes: [Note]) {
        guard let id = selectedNoteID, let note = notes.first(where: { $0.id == id }) else { return }
        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        do {
            try exportService.share(note, as: format, from: view)
        } catch {
            showError(error)
        }
    }

    func showExportPanel(selectedNoteID: UUID?, selectedNoteIDs: Set<UUID>, notes: [Note]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择导出目录"
        if panel.runModal() == .OK, let url = panel.url {
            try? ExportPreferences.setExportDirectory(url)
            exportCurrentNote(
                multiSelectionMode: !selectedNoteIDs.isEmpty,
                selectedNoteID: selectedNoteID,
                selectedNoteIDs: selectedNoteIDs,
                notes: notes
            )
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "导出失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
