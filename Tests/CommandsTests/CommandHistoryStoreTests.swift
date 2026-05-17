import XCTest
@testable import NV5

@MainActor
final class CommandHistoryStoreTests: XCTestCase {
    var store: CommandHistoryStore!

    override func setUp() {
        super.setUp()
        store = CommandHistoryStore()
        // 清空历史记录
        UserDefaults.standard.removeObject(forKey: "command_history_v1")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "command_history_v1")
        store = nil
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

    func test_sorting_by_use_count_when_not_recent() {
        store.record("command.a")
        store.record("command.a")
        store.record("command.a")
        store.record("command.b")

        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.first?.commandID, "command.a")
        XCTAssertEqual(recent.first?.useCount, 3)
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

        let newStore = CommandHistoryStore()
        let recent = newStore.recent(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.commandID, "test.command")
        XCTAssertEqual(recent.first?.useCount, 2)
    }
}
