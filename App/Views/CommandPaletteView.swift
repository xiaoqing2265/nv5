import SwiftUI
import KeyboardShortcuts

struct CommandPaletteView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedIndex = 0

    private let registry = CommandRegistry.shared

    private var results: [ScoredCommand] {
        let context = CommandContext(coordinator: coordinator, focus: focusCoordinator)
        return registry.search(query, in: context)
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

            if results.isEmpty {
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
                    List(Array(results.enumerated()), id: \.offset, selection: Binding(
                        get: { selectedIndex },
                        set: { selectedIndex = $0 }
                    )) { idx, scored in
                        CommandRow(command: scored.command)
                            .tag(idx)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                    .listStyle(.plain)
                    .onChange(of: results.count) { _, _ in
                        selectedIndex = 0
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
        }
        .frame(width: 600, height: min(CGFloat(results.count) * 44 + 44, 480))
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
    }

    private func executeSelected() {
        guard !results.isEmpty, selectedIndex < results.count else { return }
        let context = CommandContext(coordinator: coordinator, focus: focusCoordinator)
        Task { await results[selectedIndex].command.run(in: context) }
        dismiss()
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
