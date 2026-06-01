import XCTest
@testable import NV5
@testable import NVModel
@testable import NVStore

/// 覆盖「从搜索词新建笔记」的创建逻辑（此前零测试）。
///
/// 注意：本测试只能覆盖 NoteActionManager 的【逻辑契约】（标题、回调、持久化）。
/// 真正回归过的「新建后编辑器是否获得焦点」属于 SwiftUI/AppKit 视图层时序问题，
/// 需要 XCUITest 级别的 UI 测试才能验证——本项目暂无该层测试，故那类回归
/// 无法被单元测试捕获（这也是本次回归得以溜进来的根因）。
@MainActor
final class NoteActionManagerTests: XCTestCase {
    private var tempDBURL: URL!
    private var store: NoteStore!
    private var manager: NoteActionManager!

    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDBURL = dir.appendingPathComponent("notes.sqlite")
        let database = try Database(url: tempDBURL)
        store = NoteStore(database: database)
        manager = NoteActionManager(store: store)
    }

    override func tearDown() async throws {
        manager = nil
        store = nil
        try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
        try await super.tearDown()
    }

    func test_newNoteFromQuery_uses_query_as_title_and_calls_onCreated() async throws {
        var created: Note?
        let id = await manager.newNoteFromQuery(query: "Buy milk") { created = $0 }
        XCTAssertNotNil(id, "应返回新笔记 id")
        XCTAssertEqual(created?.title, "Buy milk", "查询词应作为新笔记标题")
        XCTAssertEqual(created?.id, id, "onCreated 的笔记应与返回 id 一致")

        // 已持久化：完整笔记可查回
        let full = await store.fullNote(id: try XCTUnwrap(id))
        XCTAssertEqual(full?.title, "Buy milk", "新笔记应已写入数据库")
    }

    func test_newNoteFromQuery_empty_query_uses_placeholder_title() async throws {
        var created: Note?
        _ = await manager.newNoteFromQuery(query: "") { created = $0 }
        XCTAssertEqual(created?.title, "无标题", "空查询应使用占位标题")
    }

    func test_newNote_creates_empty_titled_note() async throws {
        var created: Note?
        let id = await manager.newNote { created = $0 }
        XCTAssertNotNil(id)
        XCTAssertEqual(created?.title, "", "新建空白笔记标题为空")
    }
}
