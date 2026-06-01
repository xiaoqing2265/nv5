import XCTest
@testable import NV5

@MainActor
final class CommandHistoryStoreTests: XCTestCase {
    var store: CommandHistoryStore!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // 每个测试用独立的 UserDefaults suite，彻底隔离全局状态，
        // 避免被测类 1s 异步防抖写盘在测试间互相污染。
        suiteName = "CommandHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = CommandHistoryStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_record_single_command() {
        store.record("test.command")
        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.commandID, "test.command")
        XCTAssertEqual(recent.first?.useCount, 1)
    }

    func test_record_increments_use_count() {
        store.record("test.command")
        store.record("test.command")
        store.record("test.command")
        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.useCount, 3)
    }

    func test_recent_returns_limited_entries() {
        for i in 0..<10 {
            store.record("command.\(i)")
        }
        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }

    func test_sorting_by_recent_time() {
        store.record("command.a")
        store.record("command.b")
        store.record("command.c")

        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.first?.commandID, "command.c")
        XCTAssertEqual(recent.last?.commandID, "command.a")
    }

    func test_sorting_by_use_count_when_not_recent() throws {
        // use-count 排序分支仅对【超过 24h 的旧记录】生效；record() 总是把 lastUsed 置为现在，
        // 无法用它构造旧记录。改为在隔离 suite 里种入两条 2 天前、使用次数不同的旧记录，
        // 再 record 一条新命令触发 sortEntries，验证旧记录之间按 useCount 排序。
        let old = Date().addingTimeInterval(-2 * 86400)
        let seeded = [
            CommandHistoryEntry(commandID: "command.b", lastUsed: old, useCount: 1),
            CommandHistoryEntry(commandID: "command.a", lastUsed: old, useCount: 3),
        ]
        defaults.set(try JSONEncoder().encode(seeded), forKey: "command_history_v1")

        let seededStore = CommandHistoryStore(defaults: defaults)
        seededStore.record("command.c")  // 新命令（最近）触发排序

        let recent = seededStore.recent(limit: 5)
        XCTAssertEqual(recent.first?.commandID, "command.c", "Most-recent command sorts first")
        // 两条旧记录之间，使用次数高的（a=3）应排在低的（b=1）之前。
        let oldOrder = recent.filter { $0.commandID != "command.c" }
        XCTAssertEqual(oldOrder.first?.commandID, "command.a", "Older entries sort by use count")
        XCTAssertEqual(oldOrder.first?.useCount, 3)
    }

    func test_query_history_returns_command_ids() {
        store.record("command.a")
        store.record("command.b")
        store.record("command.c")

        let history = store.queryHistory()
        XCTAssertEqual(history.count, 3)
        XCTAssertTrue(history.contains("command.a"))
        XCTAssertTrue(history.contains("command.b"))
        XCTAssertTrue(history.contains("command.c"))
    }

    func test_max_entries_limit() {
        for i in 0..<60 {
            store.record("command.\(i)")
        }
        let recent = store.recent(limit: 100)
        XCTAssertLessThanOrEqual(recent.count, 50)
    }

    func test_persistence_across_instances() {
        store.record("test.command")
        store.record("test.command")
        store.persistNow()  // 同步落盘（取消 1s 防抖），新实例才能读到

        let newStore = CommandHistoryStore(defaults: defaults)
        let recent = newStore.recent(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.commandID, "test.command")
        XCTAssertEqual(recent.first?.useCount, 2)
    }
}
