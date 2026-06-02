import XCTest

/// UI 测试层（XCUITest）：覆盖单元测试无法触及的【视图 / 焦点时序】。
///
/// 首个用例守护 v1.1.0 → v1.1.1 的回归：从搜索词新建笔记后，必须自动进入编辑区且可输入。
/// 这类「编辑器何时挂载 / 是否获得 first responder」的问题，单元测试无法验证，只有
/// 启动真实 app 的 UI 测试能捕获——正是本项目此前缺失的一层。
final class NewNoteFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_create_note_from_query_enters_editor_and_is_editable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]  // 隔离临时数据库，绝不触碰用户真实笔记
        app.launch()

        // 1) 定位搜索框，输入一个不存在的关键词
        let search = app.searchFields["search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "搜索框应存在")
        search.click()
        search.typeText("UITestUniqueNote")

        // 2) 回车：无匹配 → 应新建笔记并进入编辑区
        search.typeText("\n")

        // 3) 等编辑器真正出现（新建经过若干异步跳变：建库→观察→加载完整正文→渲染）。
        //    NSTextView 嵌在 NSScrollView 内，按 id 查不稳，用 firstMatch（编辑器是唯一的 textView）。
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "新建后编辑器应出现")

        // 4) 编辑器应已获得焦点——直接输入正文（若未聚焦，输入不会落到编辑器，断言会失败）
        let body = "typed-into-editor-after-create"
        app.typeText(body)

        // 5) 验证编辑器内容包含刚输入的正文（证明焦点在编辑器且可编辑）
        let value = (editor.value as? String) ?? ""
        XCTAssertTrue(
            value.contains(body),
            "新建笔记后编辑器应自动获得焦点并可输入；实际编辑器内容: 「\(value)」"
        )
    }
}
