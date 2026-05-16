import Foundation

struct CommandHistoryEntry: Codable {
    let commandID: String
    let lastUsed: Date
    let useCount: Int
}

@MainActor
final class CommandHistoryStore {
    static let shared = CommandHistoryStore()
    private let key = "command_history_v1"
    private let maxEntries = 50
    
    private var entries: [CommandHistoryEntry] = []
    private var dirty = false
    private var saveTask: Task<Void, Never>?
    
    private init() {
        entries = load()
    }
    
    func record(_ commandID: String) {
        if let idx = entries.firstIndex(where: { $0.commandID == commandID }) {
            entries[idx] = CommandHistoryEntry(
                commandID: commandID,
                lastUsed: Date(),
                useCount: entries[idx].useCount + 1
            )
        } else {
            entries.append(CommandHistoryEntry(commandID: commandID, lastUsed: Date(), useCount: 1))
        }
        sortEntries()
        entries = Array(entries.prefix(maxEntries))
        dirty = true
        scheduleSave()
    }
    
    func recent(limit: Int = 5) -> [CommandHistoryEntry] {
        Array(entries.prefix(limit))
    }
    
    func queryHistory() -> [String] {
        // 返回最近查询过的命令标题（用于 ↑/↓ 导航）
        // 这里简化实现，返回 commandID
        entries.map { $0.commandID }
    }
    
    private func sortEntries() {
        let now = Date()
        entries.sort { lhs, rhs in
            let lhsRecent = now.timeIntervalSince(lhs.lastUsed) < 86400
            let rhsRecent = now.timeIntervalSince(rhs.lastUsed) < 86400
            if lhsRecent != rhsRecent { return lhsRecent }
            if lhsRecent { return lhs.lastUsed > rhs.lastUsed }
            return lhs.useCount > rhs.useCount
        }
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒后写入
            guard !Task.isCancelled else { return }
            if dirty {
                save()
                dirty = false
            }
        }
    }
    
    private func load() -> [CommandHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let loaded = try? JSONDecoder().decode([CommandHistoryEntry].self, from: data) else {
            return []
        }
        return loaded
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
