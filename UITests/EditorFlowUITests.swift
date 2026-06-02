import XCTest

/// UI 测试：编辑器的焦点流转与笔记切换——单元测试触及不到的视图层行为。
///
/// app 生命周期由 setUp/tearDown 管理；每个用例自行 launch（可选预置笔记）。
final class EditorFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    /// 启动 app。seed=true 时预置两条已知笔记（AlphaNote / BetaNote）。
    private func launch(seed: Bool = false) {
        app.launchArguments = seed ? ["--uitesting", "--uitesting-seed"] : ["--uitesting"]
        app.launch()
        app.activate()  // 确保最前台，避免事件合成超时
    }

    /// 从搜索词新建一条笔记并进入编辑器；返回编辑器元素。
    @discardableResult
    private func createNote(title: String, body: String? = nil) -> XCUIElement {
        let search = app.searchFields["search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "搜索框应存在")
        search.click()
        search.typeText(title)
        search.typeText("\n")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "新建后编辑器应出现")
        if let body = body {
            app.typeText(body)
        }
        return editor
    }

    /// 轮询等待元素 value（大小写不敏感）包含指定子串。
    private func waitForValue(_ element: XCUIElement, contains needle: String, timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var value = ""
        while Date() < deadline {
            value = (element.value as? String) ?? ""
            if value.lowercased().contains(needle.lowercased()) { return value }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return value
    }

    /// 编辑器按 Esc 应把焦点交回搜索框（之后输入落到搜索框）。
    func test_escape_from_editor_returns_focus_to_search() throws {
        launch()
        let editor = createNote(title: "EscTestNote")
        editor.click()
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])  // Esc → 回搜索框

        let probe = "escprobexyz"
        app.typeText(probe)
        let search = app.searchFields["search-field"]
        let value = waitForValue(search, contains: probe, timeout: 5)
        XCTAssertTrue(value.lowercased().contains(probe), "编辑器 Esc 后焦点应回到搜索框；实际搜索框: 「\(value)」")
    }

    /// 在预置的两条笔记间切换：正确加载各自正文；切走再切回，未保存的追加编辑不丢失
    /// （守护 fullNote 门控曾引入的切换数据丢失回归）。
    func test_switching_notes_preserves_content() throws {
        launch(seed: true)
        let editor = app.textViews.firstMatch

        // 选 AlphaNote，应载入其正文
        let alpha = app.staticTexts["AlphaNote"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10), "列表应有 AlphaNote")
        alpha.click()
        let alphaLoaded = waitForValue(editor, contains: "alphauniquecontent")
        XCTAssertTrue(alphaLoaded.lowercased().contains("alphauniquecontent"), "选中 AlphaNote 应载入其正文；实际: 「\(alphaLoaded)」")

        // 在 AlphaNote 追加一段未保存编辑
        editor.click()
        app.typeText("APPENDED")

        // 切到 BetaNote（切换应 flush AlphaNote 的追加编辑），应载入 Beta 正文
        let beta = app.staticTexts["BetaNote"]
        XCTAssertTrue(beta.waitForExistence(timeout: 10), "列表应有 BetaNote")
        beta.click()
        let betaLoaded = waitForValue(editor, contains: "betacontent")
        XCTAssertTrue(betaLoaded.lowercased().contains("betacontent"), "选中 BetaNote 应载入其正文；实际: 「\(betaLoaded)」")

        // 切回 AlphaNote → 应保留刚才的追加编辑（切换不丢失）
        alpha.click()
        let back = waitForValue(editor, contains: "APPENDED")
        XCTAssertTrue(back.lowercased().contains("appended"), "切回 AlphaNote 应保留追加编辑（切换不丢失）；实际: 「\(back)」")
    }
}
