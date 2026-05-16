import AppKit

enum CommandCategory: String, CaseIterable, Sendable {
    case note = "笔记"
    case navigation = "导航"
    case editor = "编辑"
    case exportShare = "导出与分享"
    case view = "视图"
    case app = "应用"
}

@MainActor
struct CommandContext: Sendable {
    let coordinator: AppCoordinator
    let focus: FocusCoordinator
}

@MainActor
protocol AppCommand: Sendable {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var keywords: [String] { get }
    var category: CommandCategory { get }
    var symbol: String { get }

    func isEnabled(in context: CommandContext) -> Bool
    func run(in context: CommandContext) async
}
