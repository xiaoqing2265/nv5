import SwiftUI
import KeyboardShortcuts
import NVSync
import NVExport

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gear") }
            WebDAVSettingsView()
                .tabItem { Label("同步", systemImage: "icloud") }
            ExportSettings()
                .tabItem { Label("导出", systemImage: "square.and.arrow.up") }
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

struct ExportSettings: View {
    @State private var exportDirectoryURL: URL? = ExportPreferences.exportDirectory
    @AppStorage("defaultExportFormat") private var defaultFormat: String = ExportFormat.markdown.rawValue

    var body: some View {
        Form {
            Section("导出目录") {
                HStack {
                    Text(exportDirectoryURL?.path ?? "未配置")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("选择...") { chooseDirectory() }
                }
            }
            Section("默认格式") {
                Picker("⌘⇧E 使用", selection: $defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.rawValue) { f in
                        Text(f.displayName).tag(f.rawValue)
                    }
                }
            }
        }
        .padding()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            try? ExportPreferences.setExportDirectory(url)
            exportDirectoryURL = url
        }
    }
}

struct WebDAVSettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var serverInput: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var basePath: String = "NV5"
    @State private var testResult: String?
    @State private var isTesting = false

    private var parsedURL: URL? {
        ServerURLParser.parse(serverInput)
    }

    var body: some View {
        Form {
            Section("服务器") {
                TextField("服务器地址", text: $serverInput,
                         prompt: Text("192.168.1.1:5005 或 dav.example.com"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField("用户名", text: $username)
                    .textContentType(.username)
                SecureField("密码", text: $password)
                    .textContentType(.password)
                TextField("文件夹路径", text: $basePath, prompt: Text("NV5"))
            }

            if let url = parsedURL {
                let previewPath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                Text("将连接到：\(url.absoluteString)/\(previewPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !serverInput.isEmpty {
                Text("无法识别的地址格式")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Section {
                HStack {
                    Button("测试连接") { Task { await testConnection() } }
                        .disabled(isTesting || parsedURL == nil)
                    Button("保存并同步") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsedURL == nil || username.isEmpty)
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
        let url = credentials.config.serverURL
        let port = url.port.map { ":\($0)" } ?? ""
        serverInput = "\(url.host ?? "")\(port)"
        username = credentials.config.username
        basePath = credentials.config.basePath
        password = credentials.password
    }

    private func makeConfig() -> WebDAVConfig? {
        guard let url = parsedURL else { return nil }
        let cleanBasePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return WebDAVConfig(
            serverURL: url,
            username: username,
            basePath: cleanBasePath,
            allowsInsecure: url.scheme == "http"
        )
    }

    private func testConnection() async {
        guard let config = makeConfig() else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true
        defer { isTesting = false }
        let client = WebDAVClient(config: config, password: password)
        do {
            _ = try await client.listDirectory(path: "")
            testResult = "✓ 连接成功"
        } catch {
            testResult = "✗ \(error)"
        }
    }

    private func save() async {
        guard let config = makeConfig() else { return }

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