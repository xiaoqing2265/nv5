import SwiftUI
import KeyboardShortcuts
import NVSync
import NVExport

// MARK: - 设置分类
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case appearance = "外观"
    case editor = "编辑"
    case notes = "笔记"
    case sync = "同步"
    case export = "导出"
    case shortcuts = "快捷键"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush"
        case .editor: return "pencil.and.scribble"
        case .notes: return "note.text"
        case .sync: return "icloud"
        case .export: return "square.and.arrow.up"
        case .shortcuts: return "keyboard"
        }
    }
}

// MARK: - 主设置视图（侧边栏导航）
struct SettingsNavigationView: View {
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            // MARK: - 左侧侧边栏
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                NavigationLink(value: category) {
                    Label(category.displayName, systemImage: category.systemImage)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            // MARK: - 右侧内容区
            Group {
                switch selectedCategory {
                case .general:
                    GeneralSettingsNew()
                case .appearance:
                    AppearanceSettingsNew()
                case .editor:
                    EditorBehaviorSettingsNew()
                case .notes:
                    NotesSettingsNew()
                case .sync:
                    SyncSettingsNew()
                case .export:
                    ExportSettingsNew()
                case .shortcuts:
                    ShortcutsSettingsNew()
                }
            }
            .navigationTitle(selectedCategory.displayName)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - 通用设置
struct GeneralSettingsNew: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("launchAtStartup") private var launchAtStartup: Bool = false
    @AppStorage("restoreWindowState") private var restoreWindowState: Bool = true
    @AppStorage("closeWindowToQuit") private var closeWindowToQuit: Bool = false
    @AppStorage("minimizeToTray") private var minimizeToTray: Bool = false

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
            Section("启动行为") {
                Toggle("启动时显示窗口", isOn: .constant(true))
                    .disabled(true)
                Toggle("恢复上次窗口状态", isOn: $restoreWindowState)
            }

            Section("窗口行为") {
                Toggle("关闭窗口时退出程序", isOn: $closeWindowToQuit)
                Toggle("最小化到托盘", isOn: $minimizeToTray)
            }

            Section("语言") {
                Picker("语言", selection: appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

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

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("0.9.0-rc1")
                        .foregroundStyle(.secondary)
                }
                Button("检查更新") {
                    // TODO: 检查更新
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyLanguage(_ language: AppLanguage) {
        if let langs = language.appleLanguages {
            UserDefaults.standard.set(langs, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        let alert = NSAlert()
        alert.messageText = "需要重启应用"
        alert.informativeText = "语言更改将在重启后生效。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = Bundle.main.bundleURL
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [url.path]
            task.launch()
            NSApp.terminate(nil)
        }
    }
}

// MARK: - 外观设置
struct AppearanceSettingsNew: View {
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("editorFont") private var fontRaw: String = EditorFont.menlo.rawValue
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("colorTheme") private var colorThemeKey: String = "default"
    @AppStorage("lineHeight") private var lineHeight: Double = 1.5

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
            }

            Section("编辑器字体") {
                Picker("字体", selection: font) {
                    ForEach(EditorFont.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }

                HStack {
                    Text("字号")
                    Spacer()
                    HStack(spacing: 12) {
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .frame(maxWidth: 120)
                        Text("\(Int(fontSize))pt")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("行高")
                    Spacer()
                    HStack(spacing: 12) {
                        Slider(value: $lineHeight, in: 1.0...2.0, step: 0.1)
                            .frame(maxWidth: 120)
                        Text(String(format: "%.1f", lineHeight))
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("颜色主题") {
                Picker("主题", selection: $colorThemeKey) {
                    ForEach(defaultColorThemes.keys.sorted(), id: \.self) { key in
                        if let theme = defaultColorThemes[key] {
                            Text(theme.name).tag(key)
                        }
                    }
                }
            }

            Section("预览") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(.system(size: CGFloat(fontSize), design: .monospaced))
                        .lineSpacing(lineHeight - 1.0)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 编辑器行为设置
struct EditorBehaviorSettingsNew: View {
    @AppStorage("tabKeyBehavior") private var tabBehaviorRaw: String = TabKeyBehavior.indent.rawValue
    @AppStorage("enableSpellCheck") private var enableSpellCheck: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30
    @AppStorage("preserveFormatting") private var preserveFormatting: Bool = true
    @AppStorage("makeLinksClickable") private var makeLinksClickable: Bool = true

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
                        Text(behavior.displayName).tag(behavior)
                    }
                }
            }

            Section("编辑体验") {
                Toggle("键入时检查拼写", isOn: $enableSpellCheck)
                Toggle("复制时保留基本样式", isOn: $preserveFormatting)
                Toggle("链接可点击", isOn: $makeLinksClickable)
            }

            Section("自动保存") {
                HStack {
                    Text("自动保存间隔")
                    Spacer()
                    HStack(spacing: 12) {
                        Slider(value: $autoSaveInterval, in: 10...120, step: 10)
                            .frame(maxWidth: 120)
                        Text("\(Int(autoSaveInterval))秒")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 笔记设置
struct NotesSettingsNew: View {
    @AppStorage("defaultNoteFormat") private var defaultFormat: String = "markdown"
    @AppStorage("autoSelectRelatedNote") private var autoSelectRelatedNote: Bool = true
    @AppStorage("confirmDelete") private var confirmDelete: Bool = true
    @AppStorage("showLabelCount") private var showLabelCount: Bool = true

    var body: some View {
        Form {
            Section("笔记格式") {
                Picker("默认格式", selection: $defaultFormat) {
                    Text("Markdown").tag("markdown")
                    Text("纯文本").tag("plaintext")
                }
            }

            Section("笔记行为") {
                Toggle("搜索时自动选择相关笔记", isOn: $autoSelectRelatedNote)
                Toggle("删除笔记时需要确认", isOn: $confirmDelete)
            }

            Section("标签显示") {
                Toggle("显示标签数量", isOn: $showLabelCount)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 同步设置
struct SyncSettingsNew: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var serverInput: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var basePath: String = "NV5"
    @State private var testResult: String?
    @State private var isTesting = false
    @AppStorage("syncIntervalMinutes") private var syncInterval: Double = 5
    @AppStorage("autoSync") private var autoSync: Bool = true

    private var parsedURL: URL? {
        ServerURLParser.parse(serverInput)
    }

    var body: some View {
        Form {
            Section("服务器配置") {
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

            Section("同步选项") {
                Toggle("自动同步", isOn: $autoSync)

                HStack {
                    Text("同步间隔")
                    Spacer()
                    HStack(spacing: 12) {
                        Slider(value: $syncInterval, in: 1...60, step: 1)
                            .frame(maxWidth: 120)
                        Text("\(Int(syncInterval))分钟")
                            .frame(width: 60, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .formStyle(.grouped)
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

// MARK: - 导出设置
struct ExportSettingsNew: View {
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
                Picker("导出格式", selection: $defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.rawValue) { f in
                        Text(f.displayName).tag(f.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
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

// MARK: - 快捷键设置
struct ShortcutsSettingsNew: View {
    var body: some View {
        ShortcutsSettingsView()
    }
}

// MARK: - 数据模型和枚举

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

    var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .zhHans: return ["zh-Hans"]
        case .en:     return ["en"]
        }
    }
}

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
}

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
