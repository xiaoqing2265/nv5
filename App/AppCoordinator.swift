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

    func newNote() async -> UUID? {
        await noteActionManager.newNote { [weak self] note in
            self?.recentlyCreatedNoteID = note.id
            self?.selectedNoteID = note.id
            self?.focusCoordinator?.focus(.editor)
        }
    }

    func newNoteFromQuery() async -> UUID? {
        let q = query
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

    func checkForLocalChanges() async {
        do {
            try await sync?.sync()
        } catch {
            print("[NV5] Sync before termination failed: \(error)")
        }
    }

    func deleteCurrentNote() {
        guard let id = selectedNoteID else { return }
        Task { try? await store.softDelete(id: id) }
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

    func copyAsMarkdown() {
        noteActionManager.copyAsMarkdown(selectedNoteID: selectedNoteID, notes: store.notes)
    }

    func copyAsRichText() {
        noteActionManager.copyAsRichText(selectedNoteID: selectedNoteID, notes: store.notes)
    }

    func copyAsPlainText() {
        noteActionManager.copyAsPlainText(selectedNoteID: selectedNoteID, notes: store.notes)
    }

    func exportCurrentNote() {
        noteActionManager.exportCurrentNote(
            multiSelectionMode: multiSelectionMode,
            selectedNoteID: selectedNoteID,
            selectedNoteIDs: selectedNoteIDs,
            notes: store.notes
        )
    }

    func exportSelectedNotes() {
        noteActionManager.exportSelectedNotes(selectedNoteIDs: selectedNoteIDs, notes: store.notes)
    }

    func shareCurrentNote(from view: NSView) {
        noteActionManager.shareCurrentNote(from: view, selectedNoteID: selectedNoteID, notes: store.notes)
    }

    func showExportPanel() {
        noteActionManager.showExportPanel(
            selectedNoteID: selectedNoteID,
            selectedNoteIDs: selectedNoteIDs,
            notes: store.notes
        )
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

    func extendSelection(to noteID: UUID, allNotes: [Note]) {
        selectionManager.extendSelection(
            to: noteID, allNotes: allNotes,
            anchorNoteID: &anchorNoteID,
            selectedNoteIDs: &selectedNoteIDs,
            selectedNoteID: &selectedNoteID
        )
    }

    func selectAllNotes(in notes: [Note]) {
        selectionManager.selectAllNotes(in: notes, anchorNoteID: &anchorNoteID, selectedNoteIDs: &selectedNoteIDs)
    }
}
