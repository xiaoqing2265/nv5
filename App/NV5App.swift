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
    @State private var focusCoordinator = FocusCoordinator()

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
                Button("新建笔记") { Task { _ = await coordinator.newNote() } }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("导航") {
                Button("聚焦搜索栏") { focusCoordinator.focus(.searchField) }
                    .keyboardShortcut("l", modifiers: .command)
                Button("聚焦搜索栏") { focusCoordinator.focus(.searchField) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("聚焦笔记列表") { focusCoordinator.focus(.noteList) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("聚焦编辑器") { focusCoordinator.focus(.editor) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("聚焦侧栏") { focusCoordinator.focus(.sidebar) }
                    .keyboardShortcut("1", modifiers: .command)
            }
            CommandMenu("命令") {
                Button("打开命令面板") { focusCoordinator.showPalette = true }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
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
    var selectedNoteID: UUID? {
        didSet {
            if let old = oldValue, old != selectedNoteID {
                previousNoteID = old
            }
        }
    }
    var selectedNoteIDs: Set<UUID> = []
    var previousNoteID: UUID?
    var multiSelectionMode: Bool = false
    var focusTarget: FocusTarget = .none
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

    func bootstrap(focusCoordinator: FocusCoordinator) {
        guard !isBootstrapped else { return }
        isBootstrapped = true

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
        KeyboardShortcuts.onKeyUp(for: .appCommandPalette) {
            Task { @MainActor in await CommandPaletteCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .appPreferencesShortcuts) {
            Task { @MainActor in await ShortcutsPreferencesCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .focusSearchF) {
            Task { @MainActor in await FocusSearchCommand().run(in: ctx) }
        }
        KeyboardShortcuts.onKeyUp(for: .focusSearchZero) {
            Task { @MainActor in await FocusSearchCommand().run(in: ctx) }
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

    func switchToPreviousNote() {
        guard let prev = previousNoteID else { return }
        let exists = store.notes.contains(where: { $0.id == prev })
            || store.archivedNotes.contains(where: { $0.id == prev })
        if exists {
            selectedNoteID = prev
        }
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
}
