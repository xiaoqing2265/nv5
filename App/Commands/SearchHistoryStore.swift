import Foundation

@MainActor
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()
    private let key = "search_history_v1"
    private let maxEntries = 20

    private var queries: [String] = []
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    private init() {
        queries = load()
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queries.removeAll(where: { $0 == trimmed })
        queries.insert(trimmed, at: 0)
        queries = Array(queries.prefix(maxEntries))
        dirty = true
        scheduleSave()
    }

    func history() -> [String] {
        queries
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if dirty {
                save()
                dirty = false
            }
        }
    }

    private func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let loaded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return loaded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(queries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
