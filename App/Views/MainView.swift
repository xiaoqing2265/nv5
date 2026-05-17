import SwiftUI
import NVModel
import NVStore
import NVKit

enum SidebarItem: Hashable {
    case all
    case archived
    case label(String)
}

struct MainView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var selectedItem: SidebarItem = .all
    @AppStorage("isWindowPinned") private var isWindowPinned: Bool = false
    @State private var showTagEditor: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            LabelSidebar(selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 240)
        } content: {
            NoteListColumn(selectedItem: selectedItem)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            EditorColumn()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .overlay {
            if showTagEditor {
                TagEditor()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            registerCommands()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                focusCoordinator.escapeToSearch()
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
        .onChange(of: focusCoordinator.showPalette) { _, show in
            if show {
                PaletteWindowManager.shared.show(coordinator: coordinator, focusCoordinator: focusCoordinator)
            } else {
                PaletteWindowManager.shared.hide()
            }
        }
        .onChange(of: coordinator.isFullScreenEditor) { _, newValue in
            withAnimation {
                visibility = newValue ? .detailOnly : .all
            }
        }
        .onChange(of: focusCoordinator.isOverlayActive) { _, isActive in
            withAnimation {
                showTagEditor = isActive
            }
        }
        .onKeyPress(.tab, phases: .down) { event in
            guard !focusCoordinator.isOverlayActive && !focusCoordinator.showPalette else { return .ignored }
            if event.modifiers.contains(.shift) {
                focusCoordinator.focusPrevious()
            } else {
                focusCoordinator.focusNext()
            }
            return .handled
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
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { _ = await coordinator.newNote() }
            } label: {
                Label("新建笔记", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isWindowPinned.toggle()
            } label: {
                Label(isWindowPinned ? "取消窗口前置" : "窗口前置", systemImage: isWindowPinned ? "pin.fill" : "pin")
            }
            .foregroundStyle(isWindowPinned ? .orange : .secondary)
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStatusButton()
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
