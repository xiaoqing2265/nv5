import SwiftUI
import KeyboardShortcuts

struct CommandPaletteView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @State private var query = ""
    @State private var selectedIndex = 0

    private let registry = CommandRegistry.shared

    private var groupedResults: [(category: CommandCategory?, command: ScoredCommand?)] {
        let context = CommandContext(coordinator: coordinator, focus: focusCoordinator)
        let results = registry.search(query, in: context)

        guard !results.isEmpty else { return [] }

        let grouped = Dictionary(grouping: results, by: { $0.command.category })
        var items: [(category: CommandCategory?, command: ScoredCommand?)] = []

        for category in CommandCategory.allCases {
            guard let group = grouped[category], !group.isEmpty else { continue }
            items.append((category: category, command: nil))
            for cmd in group {
                items.append((category: nil, command: cmd))
            }
        }
        return items
    }

    private var selectableIndices: [Int] {
        groupedResults.enumerated().compactMap { idx, item in
            item.command != nil ? idx : nil
        }
    }

    private var flatSelectionIndex: Int {
        let indices = selectableIndices
        guard !indices.isEmpty else { return -1 }
        let clamped = max(0, min(selectedIndex, indices.count - 1))
        return indices[clamped]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索命令…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { executeSelected() }
            }
            .padding(12)

            Divider()

            if groupedResults.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "command")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("没有匹配的命令")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(groupedResults.enumerated()), id: \.offset, selection: Binding(
                        get: { flatSelectionIndex },
                        set: { selectedIndex = $0 }
                    )) { idx, item in
                        if let category = item.category {
                            Text(category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12))
                                .listRowBackground(Color.clear)
                                .tag(-1)
                        } else if let scored = item.command {
                            CommandRow(command: scored.command)
                                .tag(idx)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: groupedResults.count) { _, _ in
                        selectedIndex = 0
                        if let first = selectableIndices.first {
                            proxy.scrollTo(first, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: min(CGFloat(selectableIndices.count) * 44 + (query.isEmpty ? 200 : 44), 480))
        .onKeyPress(.escape) {
            PaletteWindowManager.shared.hide()
            focusCoordinator.showPalette = false
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !selectableIndices.isEmpty else { return .ignored }
            let currentPos = selectableIndices.firstIndex(of: flatSelectionIndex) ?? 0
            let newPos = max(0, currentPos - 1)
            selectedIndex = newPos
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !selectableIndices.isEmpty else { return .ignored }
            let currentPos = selectableIndices.firstIndex(of: flatSelectionIndex) ?? -1
            let newPos = min(selectableIndices.count - 1, currentPos + 1)
            selectedIndex = max(0, newPos)
            return .handled
        }
    }

    private func executeSelected() {
        let idx = flatSelectionIndex
        guard idx >= 0, idx < groupedResults.count, let scored = groupedResults[idx].command else { return }
        let context = CommandContext(coordinator: coordinator, focus: focusCoordinator)
        Task { await scored.command.run(in: context) }
        PaletteWindowManager.shared.hide()
        focusCoordinator.showPalette = false
    }
}

struct CommandRow: View {
    let command: AppCommand

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.body)
                if let sub = command.subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let shortcut = shortcutBinding(for: command.id) {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func shortcutBinding(for commandID: String) -> String? {
        let name = KeyboardShortcuts.Name(commandID)
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        return shortcut.description
    }
}
