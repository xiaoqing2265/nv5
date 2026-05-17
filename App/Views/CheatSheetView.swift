import SwiftUI
import KeyboardShortcuts

struct CheatSheetView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @Environment(OverlayManager.self) private var overlayManager
    @State private var searchQuery = ""
    
    private let registry = CommandRegistry.shared
    
    private var grouped: [(category: CommandCategory, commands: [(title: String, shortcut: String)])] {
        let context = CommandContext(coordinator: coordinator, focus: focusCoordinator)
        var result: [(category: CommandCategory, commands: [(title: String, shortcut: String)])] = []
        
        for category in CommandCategory.allCases where category != .recent {
            let cmds = registry.commands.filter { $0.category == category && $0.isEnabled(in: context) }
            guard !cmds.isEmpty else { continue }
            
            let commandInfos = cmds.compactMap { cmd -> (title: String, shortcut: String)? in
                let name = KeyboardShortcuts.Name(cmd.id)
                guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
                return (cmd.title, shortcut.description)
            }
            
            guard !commandInfos.isEmpty else { continue }
            result.append((category, commandInfos))
        }
        return result
    }
    
    private var filtered: [(category: CommandCategory, commands: [(title: String, shortcut: String)])] {
        guard !searchQuery.isEmpty else { return grouped }
        return grouped.compactMap { category, commands in
            let filtered = commands.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) || $0.shortcut.localizedCaseInsensitiveContains(searchQuery) }
            guard !filtered.isEmpty else { return nil }
            return (category, filtered)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                TextField("搜索快捷键…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding(12)
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filtered, id: \.category) { category, commands in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                            
                            ForEach(commands, id: \.title) { cmd in
                                HStack {
                                    Text(cmd.title)
                                        .font(.body)
                                    Spacer()
                                    Text(cmd.shortcut)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 450)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear {
            overlayManager.open(.cheatSheet)
        }
        .onDisappear {
            overlayManager.close(.cheatSheet)
        }
        .onKeyPress(.escape) {
            overlayManager.close(.cheatSheet)
            return .handled
        }
    }
}
