import SwiftUI
import NVModel
import NVStore
import NVKit

enum SidebarItem: Hashable {
    case all
    case archived
    case label(String)
}

/// 笔记列表过滤的纯函数封装。
///
/// 单一职责：把 `NoteStore.search` 的结果按侧栏范围（全部 / 归档 / 标签）做内存级裁剪。
/// 关键词检索本身由 `NoteStore.search`（异步、命中数据库全文）负责；此处只做范围收窄，
/// 因而是同步纯函数，可在不依赖 SwiftUI / 数据库的情况下独立单元测试。
enum NoteListFilter {
    /// 按侧栏选中项裁剪笔记集合。
    /// - `.all` / `.archived`：不再二次裁剪（归档范围在检索阶段已用 `includeArchived` 处理）。
    /// - `.label`：仅保留含该标签的笔记。
    static func scope(_ notes: [NoteSummary], to item: SidebarItem) -> [NoteSummary] {
        switch item {
        case .all, .archived:
            return notes
        case .label(let label):
            return notes.filter { $0.labels.contains(label) }
        }
    }
}

struct MainView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @Environment(OverlayManager.self) private var overlayManager
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var selectedItem: SidebarItem = .all
    @AppStorage("isWindowPinned") private var isWindowPinned: Bool = false
    @State private var showKeyboardGuide: Bool = false

    var body: some View {
        contentView
            .navigationSplitViewStyle(.balanced)
            .toolbar { toolbarContent }
            .overlay(overlayContent)
        .sheet(isPresented: $showKeyboardGuide, onDismiss: {
            UserDefaults.standard.set(true, forKey: "hasShownKeyboardGuide")
        }) {
            KeyboardGuideView()
        }
            .onAppear {
                registerCommands()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    focusCoordinator.escapeToSearch()
                }
                if !UserDefaults.standard.bool(forKey: "hasShownKeyboardGuide") {
                    showKeyboardGuide = true
                }
                if isWindowPinned {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        updateWindowLevel(isWindowPinned)
                    }
                }
            }
            .onChange(of: isWindowPinned) { _, newValue in
                updateWindowLevel(newValue)
            }
            .onChange(of: focusCoordinator.sidebarVisible) { _, new in
                withAnimation {
                    visibility = new ? .all : .doubleColumn
                }
            }
            .onChange(of: coordinator.isFullScreenEditor) { _, newValue in
                withAnimation {
                    visibility = newValue ? .detailOnly : .all
                }
            }
            .onKeyPress(.tab, phases: .down) { event in
                guard !overlayManager.isAnyActive else { return .ignored }
                if event.modifiers.contains(.shift) {
                    focusCoordinator.focusPrevious()
                } else {
                    focusCoordinator.focusNext()
                }
                return .handled
            }
    }

    private var contentView: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            LabelSidebar(selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 240)
        } content: {
            NoteListColumn(selectedItem: selectedItem)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            EditorColumn()
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if overlayManager.isActive(.tagEditor) {
            TagEditor()
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func registerCommands() {
        CommandRegistry.shared.register(BuiltinCommands.all)
    }

    private func updateWindowLevel(_ isPinned: Bool) {
        for window in NSApp.windows where window.isKeyWindow || window.isMainWindow {
            window.level = isPinned ? .floating : .normal
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.multiSelectionMode.toggle()
                if !coordinator.multiSelectionMode {
                    coordinator.selectedNoteIDs.removeAll()
                }
            } label: {
                Label("批量选择", systemImage: coordinator.multiSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .foregroundStyle(coordinator.multiSelectionMode ? Color.accentColor : .secondary)
            .help("批量选择笔记")
            .accessibilityLabel("批量选择")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { _ = await coordinator.newNote() }
            } label: {
                Label("新建笔记", systemImage: "square.and.pencil")
            }
            .accessibilityLabel("新建笔记")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isWindowPinned.toggle()
            } label: {
                Label(isWindowPinned ? "取消窗口前置" : "窗口前置", systemImage: isWindowPinned ? "pin.fill" : "pin")
            }
            .foregroundStyle(isWindowPinned ? .orange : .secondary)
            .accessibilityLabel(isWindowPinned ? "取消窗口前置" : "窗口前置")
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStatusButton()
                .accessibilityLabel("同步状态")
        }
    }
}

struct SyncStatusButton: View {
    @Environment(AppCoordinator.self) private var coordinator

    private var indicatorState: NVKit.SyncStatusIndicator.State {
        guard let sync = coordinator.sync else { return .unconfigured }
        return SyncStatusBridge.uiState(
            from: sync.status,
            lastSync: sync.lastSyncDate,
            isConfigured: true
        )
    }

    var body: some View {
        NVKit.SyncStatusIndicator(state: indicatorState) {
            coordinator.triggerSync()
        }
    }
}
