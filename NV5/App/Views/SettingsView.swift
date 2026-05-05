import SwiftUI
import KeyboardShortcuts
import NVSync

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
            WebDAVSettingsView()
                .tabItem { Label("Sync", systemImage: "icloud") }
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
    }
}

struct ShortcutsSettings: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Activate NV5", name: .activateNV5)
        }
        .padding()
    }
}

struct GeneralSettings: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("syncIntervalMinutes") private var syncInterval: Double = 5

    var body: some View {
        Form {
            Slider(value: $fontSize, in: 10...22, step: 1) {
                Text("Editor font size: \(Int(fontSize))pt")
            }
            Stepper("Sync every \(Int(syncInterval)) minutes",
                    value: $syncInterval, in: 1...60, step: 1)
        }
        .padding()
    }
}

struct WebDAVSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var basePath: String = "NV5"
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURL,
                         prompt: Text("https://dav.example.com/dav/"))
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                TextField("Folder path", text: $basePath, prompt: Text("NV5"))
            }

            Section {
                HStack {
                    Button("Test Connection") { Task { await testConnection() } }
                        .disabled(isTesting || serverURL.isEmpty)
                    Button("Save & Sync") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(serverURL.isEmpty || username.isEmpty)
                    Spacer()
                    if isTesting { ProgressView().controlSize(.small) }
                }
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                }
            }
        }
        .padding()
        .onAppear(perform: loadCurrent)
    }

    private func loadCurrent() {
        guard let cfg = WebDAVSettings.load() else { return }
        serverURL = cfg.serverURL.absoluteString
        username = cfg.username
        basePath = cfg.basePath
        password = (try? WebDAVKeychain.loadPassword(for: cfg)) ?? ""
    }

    private func makeConfig() -> WebDAVConfig? {
        guard let url = URL(string: serverURL) else { return nil }
        return WebDAVConfig(serverURL: url, username: username, basePath: basePath, allowsInsecure: false)
    }

    private func testConnection() async {
        guard let config = makeConfig() else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true
        defer { isTesting = false }
        let client = WebDAVClient(config: config, password: password)
        do {
            try await client.ensureDirectory(config.basePath)
            _ = try await client.listDirectory(path: "")
            testResult = "✓ Connection successful"
        } catch {
            testResult = "✗ \(error)"
        }
    }

    private func save() async {
        guard let config = makeConfig() else { return }
        WebDAVSettings.save(config)
        try? WebDAVKeychain.storePassword(password, for: config)
        coordinator.reconfigureSync()
        testResult = "✓ Saved"
    }
}