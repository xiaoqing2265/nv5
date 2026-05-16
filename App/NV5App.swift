import SwiftUI
import KeyboardShortcuts
import Sparkle
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
    @State private var focusCoordinator = FocusCoordinator()
    @StateObject private var updaterController = UpdaterController()

    init() {
        CrashReporter.install()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(coordinator)
                .environment(coordinator.store)
                .environment(focusCoordinator)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear { coordinator.bootstrap(focusCoordinator: focusCoordinator) }
                .onOpenURL { url in
                    let handler = URLSchemeHandler(coordinator: coordinator)
                    handler.handle(url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button { Task { _ = await coordinator.newNote() } } label: {
                    MenuShortcutLabel(text: "新建笔记", shortcutName: .noteNew)
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(controller: updaterController)
            }
            CommandMenu("导航") {
                Button { focusCoordinator.focus(.searchField) } label: {
                    MenuShortcutLabel(text: "聚焦搜索栏", shortcutName: .navSearch)
                }
                Button { focusCoordinator.focus(.noteList) } label: {
                    MenuShortcutLabel(text: "聚焦笔记列表", shortcutName: .navList)
                }
                Button { focusCoordinator.focus(.editor) } label: {
                    MenuShortcutLabel(text: "聚焦编辑器", shortcutName: .navEditor)
                }
                Button { focusCoordinator.focus(.sidebar) } label: {
                    MenuShortcutLabel(text: "聚焦侧栏", shortcutName: .navSidebar)
                }
            }
            CommandMenu("命令") {
                Button { focusCoordinator.showPalette = true } label: {
                    MenuShortcutLabel(text: "打开命令面板", shortcutName: .appCommandPalette)
                }
            }
            CommandMenu("导出") {
                Button { coordinator.copyAsMarkdown() } label: {
                    MenuShortcutLabel(text: "复制为 Markdown", shortcutName: .noteCopyMarkdown)
                }
                Button { coordinator.copyAsRichText() } label: {
                    MenuShortcutLabel(text: "复制为富文本", shortcutName: .noteCopyRichText)
                }
                Button { coordinator.copyAsPlainText() } label: {
                    MenuShortcutLabel(text: "复制为纯文本", shortcutName: .noteCopyPlainText)
                }
                Divider()
                Button { coordinator.exportCurrentNote() } label: {
                    MenuShortcutLabel(text: "导出到文件", shortcutName: .noteExport)
                }
                Button("导出选项...") { coordinator.showExportPanel() }
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
public final class AppCoordinator {
    var database: Database
    var store: NoteStore
    var sync: SyncCoordinator?
    var query: String = ""
    var selectedNoteID: UUID? {
        didSet {
            if let old = oldValue, old != selectedNoteID {
                previousNoteID = old
            }
            if let id = selectedNoteID {
                navigationHistory.record(id)
            }
        }
    }
    var selectedNoteIDs: Set<UUID> = []
    var previousNoteID: UUID?
    var multiSelectionMode: Bool = false
    var recentlyCreatedNoteID: UUID?
    var isFullScreenEditor: Bool = false
    private var isCreatingNote = false
    private var isBootstrapped = false
    private weak var focusCoordinator: FocusCoordinator?
    
    let navigationHistory = NavigationHistory()

    private var exportService: ExportService
    private var servicesProvider: ServicesProvider?

    public init() {
        self.exportService = ExportService()
        self.database = AppEnvironment.shared.database
        self.store = AppEnvironment.shared.store
    }

    func bootstrap(focusCoordinator: FocusCoordinator) {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        self.focusCoordinator = focusCoordinator

        WebDAVSettings.migrateIfNeeded()

        configureWebDAVIfAvailable()
        registerHotKey()
        registerCommandShortcuts(focusCoordinator: focusCoordinator)

        let sp = ServicesProvider(coordinator: self)
        self.servicesProvider = sp
        NSApp.servicesProvider = sp
        NSUpdateDynamicServices()
    }

    private func registerCommandShortcuts(focusCoordinator: FocusCoordinator) {
        let ctx = CommandContext(coordinator: self, focus: focusCoordinator)
        KeyboardShortcuts.onKeyUp(for: .noteNew) {
            Task { @MainActor in await NewNoteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteNewFromSearch) {
            Task { @MainActor in await NewNoteFromSearchCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteDelete) {
            Task { @MainActor in await DeleteNoteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteArchiveToggle) {
            Task { @MainActor in await ArchiveToggleCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteLabelAdd) {
            Task { @MainActor in await AddLabelCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteCopyMarkdown) {
            Task { @MainActor in await CopyMarkdownCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteCopyRichText) {
            Task { @MainActor in await CopyRichTextCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteCopyPlainText) {
            Task { @MainActor in await CopyPlainTextCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteExport) {
            Task { @MainActor in await ExportNoteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .noteShare) {
            Task { @MainActor in await ShareNoteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navSearch) {
            Task { @MainActor in await FocusSearchCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navSidebar) {
            Task { @MainActor in await FocusSidebarCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navList) {
            Task { @MainActor in await FocusListCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navEditor) {
            Task { @MainActor in await FocusEditorCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navToggleSidebar) {
            Task { @MainActor in await ToggleSidebarCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navBackToPrevious) {
            Task { @MainActor in await BackToPreviousCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navBack) {
            Task { @MainActor in await NavigateBackCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .navForward) {
            Task { @MainActor in await NavigateForwardCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .viewToggleFullScreenEditor) {
            Task { @MainActor in await ToggleFullScreenEditorCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .appCommandPalette) {
            Task { @MainActor in await CommandPaletteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .appPreferencesShortcuts) {
            Task { @MainActor in await ShortcutsPreferencesCommand().run(in: ctx) }
        }
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
            focusCoordinator?.focus(.searchField)
        }
    }

    /// macOS 标准 ⌘N：创建空标题笔记
    func newNote() async -> UUID? {
        guard !isCreatingNote else { return nil }
        isCreatingNote = true
        defer { isCreatingNote = false }
        let note = Note(title: "")
        do {
            try await store.upsert(note)
        } catch {
            print("[NV5] Failed to create note: \(error)")
            return nil
        }
        self.recentlyCreatedNoteID = note.id
        self.selectedNoteID = note.id
        focusCoordinator?.focus(.editor)
        return note.id
    }

    /// Search-or-Create / ⌘⇧N：用当前 query 作标题创建笔记
    func newNoteFromQuery() async -> UUID? {
        guard !isCreatingNote else { return nil }
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
        self.recentlyCreatedNoteID = note.id
        self.selectedNoteID = note.id
        focusCoordinator?.focus(.editor)
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
            focusCoordinator?.focus(.editor)
            self.query = ""
        } catch {
            showError(error)
        }
    }

    func switchToPreviousNote() {
        guard let prev = previousNoteID else { return }
        let exists = store.notes.contains(where: { $0.id == prev })
            || store.archivedNotes.contains(where: { $0.id == prev })
        if exists {
            selectedNoteID = prev
        }
    }

    func focusSearch() {
        assert(focusCoordinator != nil, "FocusCoordinator unbound")
        guard let fc = focusCoordinator else {
            print("[NV5] focusCoordinator not bound, focusSearch() skipped")
            return
        }
        fc.focus(.searchField)
    }

    func focusEditor() {
        assert(focusCoordinator != nil, "FocusCoordinator unbound")
        guard let fc = focusCoordinator else {
            print("[NV5] focusCoordinator not bound, focusEditor() skipped")
            return
        }
        fc.focus(.editor)
    }

    func triggerSync() {
        Task {
            do {
                try await sync?.sync()
            } catch {
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
    
    // MARK: - Full Screen Editor
    
    func toggleFullScreenEditor() {
        isFullScreenEditor.toggle()
    }
    
    // MARK: - Navigation History
    
    func navigateBack() {
        if let noteID = navigationHistory.goBack() {
            selectedNoteID = noteID
        }
    }
    
    func navigateForward() {
        if let noteID = navigationHistory.goForward() {
            selectedNoteID = noteID
        }
    }
}
