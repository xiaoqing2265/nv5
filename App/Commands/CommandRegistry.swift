import Observation

public struct ScoredCommand {
    public let command: AppCommand
    public let score: Double
}

extension AppCommand {
    func score(for query: String) -> Double? {
        FuzzyMatcher.score(query: query, title: title, keywords: keywords, subtitle: subtitle)
    }
}

@MainActor
@Observable
public final class CommandRegistry {
    public static let shared = CommandRegistry()

    public private(set) var commands: [AppCommand] = []

    public init() {}

    public func register(_ command: AppCommand) {
        precondition(!commands.contains { $0.id == command.id }, "Duplicate command id: \(command.id)")
        commands.append(command)
    }

    public func register(_ commands: [AppCommand]) {
        commands.forEach(register)
    }

    public func search(_ query: String, in context: CommandContext, limit: Int = 50) -> [ScoredCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = commands.filter { $0.isEnabled(in: context) }

        guard !trimmed.isEmpty else {
            return Array(candidates.prefix(limit)).map { ScoredCommand(command: $0, score: 0) }
        }

        return candidates
            .compactMap { cmd -> ScoredCommand? in
                guard let score = cmd.score(for: trimmed) else { return nil }
                return ScoredCommand(command: cmd, score: score)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
