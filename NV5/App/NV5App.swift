import SwiftUI
import KeyboardShortcuts
import NVStore
import NVSync
import NVModel

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
                .frame(minWidth: 800, minHeight: 500)
                .onAppear { coordinator.bootstrap() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { coordinator.newNote() }
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
    var database: Database!
    var store: NoteStore!
    var sync: SyncCoordinator?
    var query: String = ""
    var selectedNoteID: UUID?

    @MainActor
    func bootstrap() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NV5", isDirectory: true)
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbURL = appSupport.appendingPathComponent("notes.sqlite")
        self.database = try! Database(url: dbURL)
        self.store = NoteStore(database: database)

        configureWebDAVIfAvailable()
        registerHotKey()
    }

    @MainActor
    private func configureWebDAVIfAvailable() {
        guard let config = WebDAVSettings.load(),
              let password = try? WebDAVKeychain.loadPassword(for: config) else {
            return
        }
        let client = WebDAVClient(config: config, password: password)
        self.sync = SyncCoordinator(client: client, store: store, database: database)
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
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        }
    }

    @MainActor
    func newNote() {
        Task {
            let note = Note(title: query.isEmpty ? "Untitled" : query)
            try? await store.upsert(note)
            self.selectedNoteID = note.id
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
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

extension Notification.Name {
    static let focusSearchField = Notification.Name("NV5.focusSearchField")
    static let focusEditor = Notification.Name("NV5.focusEditor")
}