import SwiftUI
import KeyboardShortcuts
import NVStore
import NVSync
import NVModel
import NVCrypto

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
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
        CommandGroup(replacing: .newItem) {
            Button("新建笔记") { Task { _ = await coordinator.newNote() } }
                .keyboardShortcut("n", modifiers: .command)
        }
        }

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}

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
    var focusTarget: FocusTarget = .none
    private var isCreatingNote = false
    private var isBootstrapped = false

    @MainActor
    init() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NV5", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("notes.sqlite")
        let db = try! Database(url: dbURL)
        self.database = db
        self.store = NoteStore(database: db)
    }

    @MainActor
    func bootstrap() {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        WebDAVSettings.migrateIfNeeded()

        configureWebDAVIfAvailable()
        registerHotKey()
    }

    @MainActor
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

    @MainActor
    func newNote() async -> UUID? {
        guard !isCreatingNote else { return nil }
        isCreatingNote = true
        defer { isCreatingNote = false }
        let title = query.isEmpty ? "无标题" : query
        let note = Note(title: title)
        try? await store.upsert(note)
        self.query = ""
        self.selectedNoteID = note.id
        self.focusTarget = .editor
        return note.id
    }

    @MainActor
    func triggerSync() {
        Task { try? await sync?.sync() }
    }

    @MainActor
    func reconfigureSync() {
        sync = nil
        configureWebDAVIfAvailable()
    }
}