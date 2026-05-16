import SwiftUI
import NVStore

struct LabelSidebar: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @Binding var selectedItem: SidebarItem
    @FocusState private var sidebarFocused: Bool

    private var allLabels: [(name: String, count: Int)] {
        let counts = store.notes.reduce(into: [String: Int]()) { dict, note in
            for label in note.labels { dict[label, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List(selection: $selectedItem) {
            Section {
                Label("所有笔记", systemImage: "tray.full")
                    .tag(SidebarItem.all)
                Label("已归档", systemImage: "archivebox")
                    .tag(SidebarItem.archived)
            }
            Section("标签") {
                ForEach(allLabels, id: \.name) { item in
                    HStack {
                        Label(item.name, systemImage: "tag")
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .tag(SidebarItem.label(item.name))
                }
            }
        }
        .listStyle(.sidebar)
        .focused($sidebarFocused)
        .onChange(of: focusCoordinator.current) { _, new in
            sidebarFocused = (new == .sidebar)
        }
        .onChange(of: sidebarFocused) { _, new in
            if new && focusCoordinator.current != .sidebar {
                focusCoordinator.focus(.sidebar)
            }
        }
        .focusRing()
    }
}
