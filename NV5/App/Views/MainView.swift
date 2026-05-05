import SwiftUI
import NVModel
import NVStore

struct MainView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var visibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var selectedLabel: String? = nil

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            LabelSidebar(selectedLabel: $selectedLabel)
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 240)
        } content: {
            NoteListColumn(selectedLabel: selectedLabel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            EditorColumn()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.newNote()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStatusButton()
        }
    }
}

struct SyncStatusButton: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Button {
            coordinator.triggerSync()
        } label: {
            if let sync = coordinator.sync {
                switch sync.status {
                case .idle:
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                case .syncing:
                    ProgressView().controlSize(.small)
                case .error:
                    Label("Sync error", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(.red)
                }
            } else {
                Label("Configure WebDAV", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .help(syncTooltip)
    }

    private var syncTooltip: String {
        guard let sync = coordinator.sync else { return "Open Settings to configure WebDAV" }
        if let date = sync.lastSyncDate {
            return "Last synced: \(date.formatted(.relative(presentation: .named)))"
        }
        return "Not synced yet"
    }
}