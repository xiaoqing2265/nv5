import SwiftUI
import KeyboardShortcuts
import NVSync
import NVExport

// ── 语言枚举 ─────────────────────────────────────────────
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en     = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "自动（跟随系统）"
        case .zhHans: return "中文"
        case .en:     return "English"
        }
    }

    /// 写入 UserDefaults 的 AppleLanguages key 所需的值
    var appleLanguages: [String]? {
        switch self {
        case .system: return nil          // nil = 删除 key，恢复跟随系统
        case .zhHans: return ["zh-Hans"]
        case .en:     return ["en"]
        }
    }
}

// ── SettingsView ──────────────────────────────────────────
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gear") }
            AppearanceSettings()
                .tabItem { Label("外观", systemImage: "paintbrush") }
            EditorBehaviorSettings()
                .tabItem { Label("编辑", systemImage: "pencil.and.scribble") }
            WebDAVSettingsView()
                .tabItem { Label("同步", systemImage: "icloud") }
            ExportSettings()
                .tabItem { Label("导出", systemImage: "square.and.arrow.up") }
            ShortcutsSettingsView()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 700, height: 600)
    }
}

// ── GeneralSettings ───────────────────────────────────────
struct GeneralSettings: View {
    @AppStorage("editorFontSize")      private var fontSize: Double = 14
    @AppStorage("syncIntervalMinutes") private var syncInterval: Double = 5
    @AppStorage("appLanguage")         private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { newValue in
                appLanguageRaw = newValue.rawValue
                applyLanguage(newValue)
            }
        )
    }

    var body: some View {
        Form {
            // 字体大小
            Slider(value: $fontSize, in: 10...22, step: 1) {
                Text("编辑器字号：\(Int(fontSize))pt")
            }

            // 同步间隔
            Stepper("每 \(Int(syncInterval)) 分钟同步一次",
                    value: $syncInterval, in: 1...60, step: 1)

            Divider()

            // 语言选择
            Picker("语言", selection: appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.radioGroup)   // 三个选项用 radioGroup 最清晰

            if appLanguage.wrappedValue != .system {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("语言更改将在重启应用后生效")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // 把语言偏好写入 UserDefaults，macOS 下次启动时读取
    private func applyLanguage(_ language: AppLanguage) {
        if let langs = language.appleLanguages {
            UserDefaults.standard.set(langs, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        // 弹出重启提示
        let alert = NSAlert()
        alert.messageText = "需要重启应用"
        alert.informativeText = "语言更改将在重启后生效。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            // 重启应用
            let url = Bundle.main.bundleURL
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [url.path]
            task.launch()
            NSApp.terminate(nil)
        }
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

// MARK: - 主题枚举
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 编辑器字体枚举
enum EditorFont: String, CaseIterable, Identifiable {
    case menlo = "Menlo"
    case monaco = "Monaco"
    case inconsolata = "Inconsolata"
    case sourceCodePro = "Source Code Pro"
    case firaCode = "Fira Code"
    case jetbrainsMono = "JetBrains Mono"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

// MARK: - 颜色主题
struct ColorTheme {
    let name: String
    let textColor: Color
    let backgroundColor: Color
    let searchHighlightColor: Color
    let accentColor: Color
}

let defaultColorThemes: [String: ColorTheme] = [
    "default": ColorTheme(
        name: "默认",
        textColor: .primary,
        backgroundColor: .white,
        searchHighlightColor: Color(red: 1.0, green: 1.0, blue: 0.0, opacity: 0.3),
        accentColor: .blue
    ),
    "solarized-light": ColorTheme(
        name: "Solarized Light",
        textColor: Color(red: 0.396, green: 0.482, blue: 0.514),
        backgroundColor: Color(red: 0.992, green: 0.965, blue: 0.890),
        searchHighlightColor: Color(red: 1.0, green: 1.0, blue: 0.0, opacity: 0.3),
        accentColor: Color(red: 0.149, green: 0.545, blue: 0.824)
    ),
    "solarized-dark": ColorTheme(
        name: "Solarized Dark",
        textColor: Color(red: 0.839, green: 0.855, blue: 0.859),
        backgroundColor: Color(red: 0.0, green: 0.169, blue: 0.212),
        searchHighlightColor: Color(red: 1.0, green: 1.0, blue: 0.0, opacity: 0.3),
        accentColor: Color(red: 0.149, green: 0.545, blue: 0.824)
    ),
]

// MARK: - AppearanceSettings View
struct AppearanceSettings: View {
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("editorFont") private var fontRaw: String = EditorFont.menlo.rawValue
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("colorTheme") private var colorThemeKey: String = "default"
    @AppStorage("lineHeight") private var lineHeight: Double = 1.5
    @AppStorage("letterSpacing") private var letterSpacing: Double = 0

    private var theme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRaw) ?? .system },
            set: { themeRaw = $0.rawValue }
        )
    }

    private var font: Binding<EditorFont> {
        Binding(
            get: { EditorFont(rawValue: fontRaw) ?? .menlo },
            set: { fontRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("主题") {
                Picker("外观", selection: theme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            Section("字体") {
                Picker("编辑器字体", selection: font) {
                    ForEach(EditorFont.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }

                HStack {
                    Text("字号：\(Int(fontSize))pt")
                    Spacer()
                    Slider(value: $fontSize, in: 10...24, step: 1)
                        .frame(maxWidth: 150)
                }

                HStack {
                    Text("行高：\(String(format: "%.1f", lineHeight))")
                    Spacer()
                    Slider(value: $lineHeight, in: 1.0...2.0, step: 0.1)
                        .frame(maxWidth: 150)
                }

                HStack {
                    Text("字间距：\(String(format: "%.1f", letterSpacing))")
                    Spacer()
                    Slider(value: $letterSpacing, in: -0.5...0.5, step: 0.1)
                        .frame(maxWidth: 150)
                }
            }

            Divider()

            Section("颜色主题") {
                Picker("主题", selection: $colorThemeKey) {
                    ForEach(defaultColorThemes.keys.sorted(), id: \.self) { key in
                        if let theme = defaultColorThemes[key] {
                            Text(theme.name).tag(key)
                        }
                    }
                }

                if let currentTheme = defaultColorThemes[colorThemeKey] {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("预览")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(currentTheme.textColor)
                                    .frame(width: 16, height: 16)
                                Text("文本颜色")
                                    .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(currentTheme.backgroundColor)
                                    .stroke(Color.gray, lineWidth: 0.5)
                                    .frame(width: 16, height: 16)
                                Text("背景颜色")
                                    .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(currentTheme.searchHighlightColor)
                                    .frame(width: 16, height: 16)
                                Text("搜索高亮")
                                    .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(currentTheme.accentColor)
                                    .frame(width: 16, height: 16)
                                Text("强调色")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }

            Divider()

            Section("编辑器预览") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(.system(size: CGFloat(fontSize), design: .monospaced))
                        .lineSpacing(lineHeight - 1.0)
                        .tracking(letterSpacing)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
    }
}

// MARK: - Tab 键行为枚举
enum TabKeyBehavior: String, CaseIterable, Identifiable {
    case indent = "indent"
    case nextFocus = "nextFocus"
    case softIndent = "softIndent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indent: return "行缩进"
        case .nextFocus: return "移动到下一焦点"
        case .softIndent: return "软缩进（空格）"
        }
    }

    var description: String {
        switch self {
        case .indent: return "按 Tab 键时插入制表符"
        case .nextFocus: return "按 Tab 键时移动到下一个焦点"
        case .softIndent: return "按 Tab 键时插入空格"
        }
    }
}

// MARK: - EditorBehaviorSettings View
struct EditorBehaviorSettings: View {
    @AppStorage("tabKeyBehavior") private var tabBehaviorRaw: String = TabKeyBehavior.indent.rawValue
    @AppStorage("enableSpellCheck") private var enableSpellCheck: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30
    @AppStorage("preserveFormatting") private var preserveFormatting: Bool = true
    @AppStorage("makeLinksClickable") private var makeLinksClickable: Bool = true
    @AppStorage("suggestNoteLinks") private var suggestNoteLinks: Bool = true
    @AppStorage("autoSelectRelatedNote") private var autoSelectRelatedNote: Bool = true
    @AppStorage("confirmDelete") private var confirmDelete: Bool = true

    private var tabBehavior: Binding<TabKeyBehavior> {
        Binding(
            get: { TabKeyBehavior(rawValue: tabBehaviorRaw) ?? .indent },
            set: { tabBehaviorRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Tab 键行为") {
                Picker("Tab 键", selection: tabBehavior) {
                    ForEach(TabKeyBehavior.allCases) { behavior in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(behavior.displayName).tag(behavior)
                            Text(behavior.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            Section("拼写和语法") {
                Toggle("键入时检查拼写", isOn: $enableSpellCheck)
            }

            Divider()

            Section("自动保存") {
                HStack {
                    Text("自动保存间隔：\(Int(autoSaveInterval))秒")
                    Spacer()
                    Slider(value: $autoSaveInterval, in: 10...120, step: 10)
                        .frame(maxWidth: 150)
                }
                Text("设置为 0 禁用自动保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Section("格式和链接") {
                Toggle("复制时保留基本样式", isOn: $preserveFormatting)
                Toggle("链接可点击", isOn: $makeLinksClickable)
                Toggle("输入笔记链接时提供建议", isOn: $suggestNoteLinks)
            }

            Divider()

            Section("笔记行为") {
                Toggle("搜索时自动选择相关笔记", isOn: $autoSelectRelatedNote)
                Toggle("删除笔记时需要确认", isOn: $confirmDelete)
            }
        }
        .padding()
    }
}