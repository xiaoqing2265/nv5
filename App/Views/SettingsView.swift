import SwiftUI
import KeyboardShortcuts
import NVSync

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gear") }
            WebDAVSettingsView()
                .tabItem { Label("同步", systemImage: "icloud") }
            ShortcutsSettings()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
    }
}

struct ShortcutsSettings: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("激活 NV5", name: .activateNV5)
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
                Text("编辑器字号: \(Int(fontSize))pt")
            }
            Stepper("每 \(Int(syncInterval)) 分钟同步一次",
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
            Section("服务器") {
                TextField("服务器地址", text: $serverURL,
                         prompt: Text("https://dav.example.com/dav/"))
                    .textContentType(.URL)
                TextField("用户名", text: $username)
                    .textContentType(.username)
                SecureField("密码", text: $password)
                    .textContentType(.password)
                TextField("文件夹路径", text: $basePath, prompt: Text("NV5"))
            }

            Section {
                HStack {
                    Button("测试连接") { Task { await testConnection() } }
                        .disabled(isTesting || serverURL.isEmpty)
                    Button("保存并同步") { Task { await save() } }
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
        guard let credentials = WebDAVSettings.load() else { return }
        serverURL = credentials.config.serverURL.absoluteString
        username = credentials.config.username
        basePath = credentials.config.basePath
        password = credentials.password
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
            testResult = "✓ 连接成功"
        } catch {
            testResult = "✗ \(error)"
        }
    }

    private func save() async {
        guard let config = makeConfig() else { return }

        // Preserve existing sync master key if available, otherwise generate new
        let existing = WebDAVSettings.load()
        let masterKey = existing?.syncMasterKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()

        let credentials = WebDAVCredentials(config: config, password: password, syncMasterKey: masterKey)
        do {
            try WebDAVSettings.save(credentials)
            coordinator.reconfigureSync()
            testResult = "✓ 已保存"
        } catch {
            testResult = "✗ 保存失败：\(error.localizedDescription)"
        }
    }
}