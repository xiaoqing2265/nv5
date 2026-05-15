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
    @State private var visibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var selectedItem: SidebarItem = .all
    @AppStorage("isWindowPinned") private var isWindowPinned: Bool = false

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
        .onChange(of: isWindowPinned) { _, newValue in
            updateWindowLevel(newValue)
        }
        .onAppear {
            if isWindowPinned {
                // Yield briefly to let window initialize before setting level
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    updateWindowLevel(isWindowPinned)
                }
            }
        }
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