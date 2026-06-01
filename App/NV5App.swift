import SwiftUI
import KeyboardShortcuts
import Sparkle

extension KeyboardShortcuts.Name {
    static let activateNV5 = Self("activateNV5", default: .init(.space, modifiers: [.command, .control]))
}

@main
struct NV5App: App {
    @State private var coordinator = AppCoordinator()
    @State private var focusCoordinator = FocusCoordinator()
    @StateObject private var updaterController = UpdaterController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        CrashReporter.install()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(coordinator)
                .environment(coordinator.store)
                .environment(focusCoordinator)
                .environment(OverlayManager.shared)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear { appDelegate.coordinator = coordinator; coordinator.bootstrap(focusCoordinator: focusCoordinator) }
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
                Button("从搜索新建") { Task { _ = await coordinator.newNoteFromQuery() } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(controller: updaterController)
            }
            CommandMenu("笔记") {
                Button("删除笔记") { coordinator.deleteCurrentNote() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(coordinator.selectedNoteID == nil)
                Button("切换归档") { coordinator.toggleArchiveCurrentNote() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(coordinator.selectedNoteID == nil)
                Divider()
                Button("复制为 Markdown") { coordinator.copyAsMarkdown() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("复制为富文本") { coordinator.copyAsRichText() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("复制为纯文本") { coordinator.copyAsPlainText() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("导出到文件") { coordinator.exportCurrentNote() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("分享...") {
                    if let view = NSApp.keyWindow?.contentView {
                        coordinator.shareCurrentNote(from: view)
                    }
                }
                Button("导出选项...") { coordinator.showExportPanel() }
            }
            CommandMenu("导航") {
                Button("聚焦搜索栏") { focusCoordinator.focus(.searchField) }
                    .keyboardShortcut("l", modifiers: .command)
                Button("聚焦笔记列表") { focusCoordinator.focus(.noteList) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("聚焦编辑器") { focusCoordinator.focus(.editor) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("聚焦侧栏") { focusCoordinator.focus(.sidebar) }
                    .keyboardShortcut("1", modifiers: .command)
                Divider()
                Button("后退") { coordinator.navigateBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("前进") { coordinator.navigateForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("返回上一条") { coordinator.switchToPreviousNote() }
                    .keyboardShortcut("'", modifiers: .command)
                Divider()
                Button("切换侧栏") { focusCoordinator.toggleSidebar() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("全屏编辑器") { coordinator.toggleFullScreenEditor() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandMenu("命令") {
                Button("打开命令面板") { OverlayManager.shared.open(.commandPalette) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsNavigationView()
                .environment(coordinator)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else {
            return .terminateNow
        }
        // nvALT 风格：用 terminateLater 推迟退出，先【等待】把编辑器未保存击键落盘，
        // 再做网络同步，完成后才放行退出——不与退出赛跑。
        // checkForLocalChanges() 内部已先 await flushActiveEditor() 落盘，再 sync。
        Task { @MainActor in
            await coordinator.checkForLocalChanges()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
