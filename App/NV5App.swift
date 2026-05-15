import SwiftUI
import KeyboardShortcuts
import NVStore
import NVSync
import NVModel
import NVCrypto
import NVExport

extension KeyboardShortcuts.Name {
    static let activateNV5 = Self("activateNV5", default: .init(.space, modifiers: [.command, .control]))
}

@main
struct NV5App: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(coordinator)
                .environment(coordinator.store)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear { coordinator.bootstrap() }
                .onOpenURL { url in
                    let handler = URLSchemeHandler(coordinator: coordinator)
                    handler.handle(url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") { Task { _ = await coordinator.newNote() } }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("导出") {
                Button("复制为 Markdown") { coordinator.copyAsMarkdown() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("复制为富文本") { coordinator.copyAsRichText() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("复制为纯文本") { coordinator.copyAsPlainText() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("导出到文件") { coordinator.exportCurrentNote() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("导出选项...") { coordinator.showExportPanel() }
                    .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}

@MainActor
@Observable
final class AppCoordinator {
    enum FocusTarget: Hashable {
        case searchField
        case editor
        case titleField
        case none
    }

    var database: Database
    var store: NoteStore
    var sync: SyncCoordinator?
    var query: String = ""
    var selectedNoteID: UUID?
    var selectedNoteIDs: Set<UUID> = []
    var multiSelectionMode: Bool = false
    var focusTarget: FocusTarget = .none
    /// Set after newNote() to prevent onChange(filteredNotes) from overriding selection
    /// before ValueObservation has propagated the new note to store.notes
    var recentlyCreatedNoteID: UUID?
    private var isCreatingNote = false
    private var isBootstrapped = false

    private var exportService: ExportService
    private var servicesProvider: ServicesProvider?

    init() {
        self.exportService = ExportService()
        self.database = AppEnvironment.shared.database
        self.store = AppEnvironment.shared.store
    }

    func bootstrap() {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        WebDAVSettings.migrateIfNeeded()

        configureWebDAVIfAvailable()
        registerHotKey()

        let sp = ServicesProvider(coordinator: self)
        self.servicesProvider = sp
        NSApp.servicesProvider = sp
        NSUpdateDynamicServices()
    }

    private func configureWebDAVIfAvailable() {
        guard let credentials = WebDAVSettings.load() else {
            return
        }
        let client = WebDAVClient(config: credentials.config, password: credentials.password)
        let syncCrypto = try? CryptoEngine(base64Key: credentials.syncMasterKey)
        self.sync = SyncCoordinator(client: client, store: store, database: database, crypto: syncCrypto)
    }

    private func registerHotKey() {
        KeyboardShortcuts.onKeyUp(for: .activateNV5) { [weak self] in
            self?.toggleApp()
        }
    }

    private func toggleApp() {
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            self.focusTarget = .searchField
        }
    }

    func newNote() async -> UUID? {
        guard !isCreatingNote else {
            return nil
        }
        isCreatingNote = true
        defer { isCreatingNote = false }
        let title = query.isEmpty ? "无标题" : query
        let note = Note(title: title)
        do {
            try await store.upsert(note)
        } catch {
            print("[NV5] Failed to create note: \(error)")
            return nil
        }
        // Set selection BEFORE clearing query, so onChange(of: filteredNotes)
        // sees the new note ID and doesn't override it with the first item
        self.recentlyCreatedNoteID = note.id
        self.selectedNoteID = note.id
        self.focusTarget = .editor
        self.query = ""
        return note.id
    }

    func newNoteFromURL(title: String, body: String) async {
        let titleToUse = title.isEmpty ? "无标题" : title
        let note = Note(title: titleToUse, body: body)
        do {
            try await store.upsert(note)
            self.recentlyCreatedNoteID = note.id
            self.selectedNoteID = note.id
            self.focusTarget = .editor
            self.query = ""
        } catch {
            showError(error)
        }
    }

    func triggerSync() {
        Task {
            do {
                try await sync?.sync()
            } catch {
                // sync.status is already updated to .error inside sync()
                print("[NV5] Sync failed: \(error)")
            }
        }
    }

    func reconfigureSync() {
        sync = nil
        configureWebDAVIfAvailable()
    }

    // MARK: - Lifecycle

    func setArchived(id: UUID, archived: Bool) {
        Task {
            do {
                try await store.setArchived(id: id, archived: archived)
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
        }
    }

    // MARK: - Export

    func copyAsMarkdown() { copyToClipboard(as: .markdown) }

    func copyAsRichText() { copyToClipboard(as: .richText) }

    func copyAsPlainText() { copyToClipboard(as: .plainText) }

    private func copyToClipboard(as format: ExportFormat) {
        guard let id = selectedNoteID, let note = store.notes.first(where: { $0.id == id }) else { return }
        do {
            try exportService.copyToClipboard(note, as: format)
        } catch {
            showError(error)
        }
    }

    func exportCurrentNote() {
        if multiSelectionMode {
            exportSelectedNotes()
            return
        }

        guard let id = selectedNoteID, let note = store.notes.first(where: { $0.id == id }) else { return }
        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        guard let dir = ExportPreferences.exportDirectory else {
            showExportPanel()
            return
        }

        // request access to security scoped resource
        let accessing = dir.startAccessingSecurityScopedResource()

        Task {
            defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await exportService.exportToFile(note, as: format, in: dir)
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
        }
    }

    func exportSelectedNotes() {
        guard !selectedNoteIDs.isEmpty else { return }
        let notesToExport = store.notes.filter { selectedNoteIDs.contains($0.id) }

        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        guard let dir = ExportPreferences.exportDirectory else {
            showExportPanel()
            return
        }

        let accessing = dir.startAccessingSecurityScopedResource()

        Task {
            defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await exportService.exportToDirectory(notesToExport, as: format, in: dir)
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
        }
    }

    func shareCurrentNote(from view: NSView) {
        guard let id = selectedNoteID, let note = store.notes.first(where: { $0.id == id }) else { return }
        let formatStr = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? ExportFormat.markdown.rawValue
        let format = ExportFormat(rawValue: formatStr) ?? .markdown
        do {
            try exportService.share(note, as: format, from: view)
        } catch {
            showError(error)
        }
    }

    func showExportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择导出目录"
        if panel.runModal() == .OK, let url = panel.url {
            try? ExportPreferences.setExportDirectory(url)
            exportCurrentNote()
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