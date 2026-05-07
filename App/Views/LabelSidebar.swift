import SwiftUI

struct LabelSidebar: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Binding var selectedLabel: String?

    private var allLabels: [(name: String, count: Int)] {
        let counts = (coordinator.store?.notes ?? []).reduce(into: [String: Int]()) { dict, note in
            for label in note.labels { dict[label, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List(selection: $selectedLabel) {
            Section {
                Label("所有笔记", systemImage: "tray.full")
                    .tag(String?.none)
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
                    .tag(String?.some(item.name))
                }
            }
        }
        .listStyle(.sidebar)
    }
}