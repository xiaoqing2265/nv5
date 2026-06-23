import SwiftUI
import KeyboardShortcuts
import NVStore
import NVSync
import NVModel
import NVCrypto
import NVExport

@MainActor
@Observable
final class AppCoordinator {
    var database: Database
    var store: NoteStore
    var sync: SyncCoordinator?
    var query: String = ""
    var typedQuery: String = ""
    var selectedNoteID: UUID? {
        didSet {
            if let old = oldValue, old != selectedNoteID {
                navigationCoordinator.didSelect(selectedNoteID ?? old, previous: old)
            } else if let id = selectedNoteID {
                navigationCoordinator.didSelect(id, previous: nil)
            }
        }
    }
    var selectedNoteIDs: Set<UUID> = []
    var anchorNoteID: UUID?
    var multiSelectionMode: Bool = false
    var recentlyCreatedNoteID: UUID?
    var isFullScreenEditor: Bool = false
    private var isBootstrapped = false
    private weak var focusCoordinator: FocusCoordinator?
    
    let navigationCoordinator = NavigationCoordinator()

    private var servicesProvider: ServicesProvider?
    private(set) var selectionManager = SelectionManager()
    private(set) var noteActionManager: NoteActionManager

    public init() {
        let store = AppEnvironment.shared.store
        self.store = store
        self.database = AppEnvironment.shared.database
        self.noteActionManager = NoteActionManager(store: store)
    }

    func bootstrap(focusCoordinator: FocusCoordinator) {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        self.focusCoordinator = focusCoordinator

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
        // 注入 flush 钩子：所有同步（含后台周期同步）开始前先把编辑器未保存内容落到 DB，
        // 避免正在编辑、未到防抖点的内容被远端下行覆盖丢失。
        self.sync = SyncCoordinator(
            client: client, store: store, database: database, crypto: syncCrypto,
            preSyncFlush: { await MainWindowController.shared.flushActiveEditor() }
        )
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

    func newNote() async -> UUID? {
        await noteActionManager.newNote { [weak self] note in
            self?.recentlyCreatedNoteID = note.id
            self?.selectedNoteID = note.id
            self?.focusCoordinator?.focus(.editor)
        }
    }

    func newNoteFromQuery() async -> UUID? {
        let q = typedQuery
        return await noteActionManager.newNoteFromQuery(query: q) { [weak self] note in
            self?.recentlyCreatedNoteID = note.id
            self?.selectedNoteID = note.id
            self?.focusCoordinator?.focus(.editor)
            self?.query = ""
            self?.typedQuery = ""
        }
    }

    func newNoteFromURL(title: String, body: String) async {
        await noteActionManager.newNoteFromURL(title: title, body: body,
            onCreated: { [weak self] note in
                self?.recentlyCreatedNoteID = note.id
                self?.selectedNoteID = note.id
                self?.focusCoordinator?.focus(.editor)
                self?.query = ""
                self?.typedQuery = ""
            },
            onError: { [weak self] error in
                self?.showError(error)
            }
        )
    }

    func focusSearch() {
        assert(focusCoordinator != nil, "FocusCoordinator unbound")
        guard let fc = focusCoordinator else {
            print("[NV5] focusCoordinator not bound, focusSearch() skipped")
            return
        }
        fc.focus(.searchField)
    }

    /// 进入命令模式：在搜索框预填 `>` 前缀并聚焦，触发 NoteListColumn 的命令模式分支。
    /// Cmd+Shift+B 调用此方法，取代原先打开 PaletteWindowManager 的行为。
    func enterCommandMode(focusCoordinator: FocusCoordinator) {
        if !typedQuery.hasPrefix(">") {
            typedQuery = ">"
            query = ">"
        }
        focusCoordinator.focus(.searchField)
        MainWindowController.shared.focusSearchField()
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
            // 先把编辑器内存中未保存的内容落到 DB 并【等待写入完成】，使冲突矩阵能识别 localDirty。
            await MainWindowController.shared.flushActiveEditor()
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

    func checkForLocalChanges() async {
        // 同步前 flush 当前编辑器并【等待落盘】，避免正在编辑、尚未自动保存的内容被远端下行覆盖，
        // 也保证退出前未保存击键已持久化。
        await MainWindowController.shared.flushActiveEditor()
        do {
            try await sync?.sync()
        } catch {
            print("[NV5] Sync before termination failed: \(error)")
        }
    }

    func deleteCurrentNote() {
        guard let id = selectedNoteID else { return }
        let shouldConfirm = UserDefaults.standard.object(forKey: "confirmDelete")
                                .flatMap { $0 as? Bool } ?? true
        if shouldConfirm {
            let alert = NSAlert()
            alert.messageText = "确认删除笔记？"
            alert.informativeText = "删除后无法恢复。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            do {
                try await store.softDelete(id: id)
            } catch {
                showError(error)
            }
        }
    }

    func toggleArchiveCurrentNote() {
        guard let id = selectedNoteID,
              let note = store.notes.first(where: { $0.id == id }) else { return }
        setArchived(id: id, archived: !note.archived)
    }

    func switchToPreviousNote() {
        if let prev = navigationCoordinator.previousNote(
            existingIn: store.notes, archived: store.archivedNotes) {
            selectedNoteID = prev
        }
    }

    // MARK: - Lifecycle

    func setArchived(id: UUID, archived: Bool) {
        noteActionManager.setArchived(id: id, archived: archived)
    }

    // MARK: - Export

    /// 导出/复制/分享需要【完整正文】：store.notes 是摘要（body 截断、无属性），
    /// 必须按 id 取完整 Note，否则导出会被截断、富文本属性丢失。
    private func fullNotes(for ids: [UUID]) async -> [Note] {
        var result: [Note] = []
        for id in ids {
            if let note = await store.fullNote(id: id) { result.append(note) }
        }
        return result
    }

    func copyAsMarkdown() {
        Task {
            guard let id = selectedNoteID, let full = await store.fullNote(id: id) else { return }
            noteActionManager.copyAsMarkdown(selectedNoteID: id, notes: [full])
        }
    }

    func copyAsRichText() {
        Task {
            guard let id = selectedNoteID, let full = await store.fullNote(id: id) else { return }
            noteActionManager.copyAsRichText(selectedNoteID: id, notes: [full])
        }
    }

    func copyAsPlainText() {
        Task {
            guard let id = selectedNoteID, let full = await store.fullNote(id: id) else { return }
            noteActionManager.copyAsPlainText(selectedNoteID: id, notes: [full])
        }
    }

    func exportCurrentNote() {
        Task {
            let ids = multiSelectionMode ? Array(selectedNoteIDs) : (selectedNoteID.map { [$0] } ?? [])
            let full = await fullNotes(for: ids)
            noteActionManager.exportCurrentNote(
                multiSelectionMode: multiSelectionMode,
                selectedNoteID: selectedNoteID,
                selectedNoteIDs: selectedNoteIDs,
                notes: full
            )
        }
    }

    func exportSelectedNotes() {
        Task {
            let full = await fullNotes(for: Array(selectedNoteIDs))
            noteActionManager.exportSelectedNotes(selectedNoteIDs: selectedNoteIDs, notes: full)
        }
    }

    func shareCurrentNote(from view: NSView) {
        Task {
            guard let id = selectedNoteID, let full = await store.fullNote(id: id) else { return }
            noteActionManager.shareCurrentNote(from: view, selectedNoteID: id, notes: [full])
        }
    }

    func showExportPanel() {
        Task {
            let ids = (selectedNoteID.map { [$0] } ?? []) + Array(selectedNoteIDs)
            let full = await fullNotes(for: Array(Set(ids)))
            noteActionManager.showExportPanel(
                selectedNoteID: selectedNoteID,
                selectedNoteIDs: selectedNoteIDs,
                notes: full
            )
        }
    }

    func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "操作失败"
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
        if let noteID = navigationCoordinator.goBack() {
            selectedNoteID = noteID
        }
    }

    func navigateForward() {
        if let noteID = navigationCoordinator.goForward() {
            selectedNoteID = noteID
        }
    }

    func extendSelection(to noteID: UUID, allNotes: [NoteSummary]) {
        selectionManager.extendSelection(
            to: noteID, allNotes: allNotes,
            anchorNoteID: &anchorNoteID,
            selectedNoteIDs: &selectedNoteIDs,
            selectedNoteID: &selectedNoteID
        )
    }

    func selectAllNotes(in notes: [NoteSummary]) {
        selectionManager.selectAllNotes(in: notes, anchorNoteID: &anchorNoteID, selectedNoteIDs: &selectedNoteIDs)
    }
}
