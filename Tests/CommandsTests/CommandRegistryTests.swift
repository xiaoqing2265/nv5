import XCTest
import NV5

@MainActor
final class CommandRegistryTests: XCTestCase {
    var registry: CommandRegistry!

    override func setUp() {
        super.setUp()
        registry = CommandRegistry()
    }

    override func tearDown() {
        registry = nil
        super.tearDown()
    }

    private func makeContext() -> CommandContext {
        let fc = FocusCoordinator()
        let ac = AppCoordinator()
        return CommandContext(coordinator: ac, focus: fc)
    }

    func test_register_single_command() {
        let cmd = TestCommand(id: "test.one", title: "Test One")
        registry.register(cmd)
        XCTAssertEqual(registry.commands.count, 1)
        XCTAssertEqual(registry.commands.first?.id, "test.one")
    }

    func test_register_multiple_commands() {
        let cmds = [
            TestCommand(id: "test.a", title: "A"),
            TestCommand(id: "test.b", title: "B"),
            TestCommand(id: "test.c", title: "C"),
        ]
        registry.register(cmds)
        XCTAssertEqual(registry.commands.count, 3)
    }

    func test_duplicate_id_precondition_fails() {
        registry.register(TestCommand(id: "dup", title: "First"))
        XCTExpectFailure("Duplicate command id should trigger precondition")
        registry.register(TestCommand(id: "dup", title: "Second"))
    }

    func test_empty_query_returns_all_enabled_commands() {
        registry.register([
            TestCommand(id: "a", title: "Alpha", isEnabled: true),
            TestCommand(id: "b", title: "Beta", isEnabled: true),
            TestCommand(id: "c", title: "Gamma", isEnabled: false),
        ])
        let ctx = makeContext()
        let results = registry.search("", in: ctx)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.command.isEnabled(in: ctx) })
    }

    func test_search_by_title_contains() {
        registry.register([
            TestCommand(id: "a", title: "导出到文件"),
            TestCommand(id: "b", title: "复制为 Markdown"),
        ])
        let ctx = makeContext()
        let results = registry.search("导出", in: ctx)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command.id, "a")
    }

    func test_search_by_keyword() {
        registry.register([
            TestCommand(id: "a", title: "导出", keywords: ["export", "save"]),
            TestCommand(id: "b", title: "复制", keywords: ["copy"]),
        ])
        let ctx = makeContext()
        let results = registry.search("export", in: ctx)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command.id, "a")
    }

    func test_search_no_match_returns_empty() {
        registry.register([
            TestCommand(id: "a", title: "新建笔记"),
        ])
        let ctx = makeContext()
        let results = registry.search("xyzabc", in: ctx)
        XCTAssertTrue(results.isEmpty)
    }

    func test_search_respects_limit() {
        for i in 0..<100 {
            registry.register(TestCommand(id: "cmd.\(i)", title: "命令\(i)", keywords: ["cmd"]))
        }
        let ctx = makeContext()
        let results = registry.search("cmd", in: ctx, limit: 10)
        XCTAssertLessThanOrEqual(results.count, 10)
    }

    func test_search_trims_whitespace() {
        registry.register([
            TestCommand(id: "a", title: "测试命令"),
        ])
        let ctx = makeContext()
        let results = registry.search("  测试  ", in: ctx)
        XCTAssertFalse(results.isEmpty)
    }
}

@MainActor
private struct TestCommand: AppCommand {
    let id: String
    let title: String
    let subtitle: String?
    let keywords: [String]
    let category: CommandCategory
    let symbol: String
    private let _isEnabled: Bool

    init(id: String, title: String, subtitle: String? = nil, keywords: [String] = [], category: CommandCategory = .note, symbol: String = "doc", isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.category = category
        self.symbol = symbol
        self._isEnabled = isEnabled
    }

    func isEnabled(in context: CommandContext) -> Bool { _isEnabled }
    func run(in context: CommandContext) async {}
}
