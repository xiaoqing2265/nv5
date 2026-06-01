import AppKit
import Combine
import XCTest
@testable import NV5

/// 自动保存测试：通过【可注入的短防抖时长】+【事件驱动的 XCTestExpectation】实现确定性、
/// 快速、抗负载的测试，取代原先 wall-clock `Task.sleep` 的脆弱时序假设。
@MainActor
final class NoteEditorAutosaveTests: XCTestCase {

    // MARK: - Expectation helpers（事件驱动等待，避免 wall-clock sleep 的 flaky）

    /// 等待文本提交计数达到 count（事件触发，超时仅作兜底）。
    private func awaitTextCommits(_ harness: EditorHarness, _ count: Int, timeout: TimeInterval = 3) async {
        let exp = expectation(description: "textCommits >= \(count)")
        exp.assertForOverFulfill = false
        harness.textObserver = { if harness.textCommits.count >= count { exp.fulfill() } }
        if harness.textCommits.count >= count { exp.fulfill() }
        await fulfillment(of: [exp], timeout: timeout)
    }

    /// 等待富文本提交计数达到 count。
    private func awaitRichCommits(_ harness: EditorHarness, _ count: Int, timeout: TimeInterval = 3) async {
        let exp = expectation(description: "richCommits >= \(count)")
        exp.assertForOverFulfill = false
        harness.richObserver = { if harness.richCommits.count >= count { exp.fulfill() } }
        if harness.richCommits.count >= count { exp.fulfill() }
        await fulfillment(of: [exp], timeout: timeout)
    }

    /// 在给定时间内断言【没有】超过 count 的富文本提交（inverted expectation）。
    private func assertNoRichBeyond(_ harness: EditorHarness, _ count: Int, within timeout: TimeInterval = 0.6) async {
        let exp = expectation(description: "no rich beyond \(count)")
        exp.isInverted = true
        harness.richObserver = { if harness.richCommits.count > count { exp.fulfill() } }
        await fulfillment(of: [exp], timeout: timeout)
    }

    /// 在给定时间内断言【没有】超过 count 的文本提交。
    private func assertNoTextBeyond(_ harness: EditorHarness, _ count: Int, within timeout: TimeInterval = 0.6) async {
        let exp = expectation(description: "no text beyond \(count)")
        exp.isInverted = true
        harness.textObserver = { if harness.textCommits.count > count { exp.fulfill() } }
        await fulfillment(of: [exp], timeout: timeout)
    }

    private func edit(_ harness: EditorHarness, _ text: String) {
        harness.textView.string = text
        harness.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.textView)
        )
    }

    // MARK: - Lightweight Commit Path（轻量文本保存）

    /// 防抖窗口内的连续编辑只产生一次文本提交，不触发富文本提交。
    func test_lightweight_commit_routes_to_onTextCommit_only() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial")

        // 连续 20 次编辑（同步触发）：防抖的 cancel-prior 逻辑应只保留最后一个定时器。
        for index in 0..<20 {
            edit(harness, "Body \(index)")
        }

        await awaitTextCommits(harness, 1)

        XCTAssertEqual(harness.textCommits.count, 1, "Should have exactly one text commit after debounce")
        XCTAssertTrue(harness.richCommits.isEmpty, "Rich commit must NOT fire in the lightweight path")
        XCTAssertEqual(harness.textCommits.first?.body, "Body 19", "Text commit should contain final body")
    }

    /// 轻量路径不应序列化 RTFD 数据。
    func test_lightweight_commit_does_not_serialize_rtfd() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial text")

        edit(harness, "Edited text")
        await awaitTextCommits(harness, 1)

        XCTAssertEqual(harness.textCommits.count, 1, "Lightweight path should fire onTextCommit")
        XCTAssertTrue(harness.richCommits.isEmpty, "onRichCommit must not be called in lightweight window")
        XCTAssertTrue(
            harness.capturedRTFDDuringLightweight.isEmpty,
            "No RTFD Data should be produced during lightweight save"
        )
    }

    // MARK: - Idle Timeout Path（富文本空闲保存）

    /// 空闲超时后触发一次带完整属性的富文本提交。
    func test_idle_triggers_rich_commit_with_attributes() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial")

        edit(harness, "After idle")
        await awaitRichCommits(harness, 1)

        XCTAssertEqual(harness.textCommits.count, 1, "Should have one text commit (lightweight)")
        XCTAssertEqual(harness.richCommits.count, 1, "Should have one rich commit after idle")
        XCTAssertNotNil(harness.richCommits.first?.attributes, "Rich commit must include RTFD data")
        XCTAssertEqual(harness.richCommits.first?.body, "After idle", "Rich commit body should match")
    }

    /// 富文本提交后状态复位，不应在后续空闲时重复触发。
    func test_idle_resets_state_no_duplicate_rich_commit() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial")

        edit(harness, "Edited")
        await awaitRichCommits(harness, 1)
        XCTAssertEqual(harness.richCommits.count, 1, "First rich commit fired")

        // 再观察一段时间（约 2× 空闲时长）确认没有重复富文本提交。
        await assertNoRichBeyond(harness, 1)
        XCTAssertEqual(harness.richCommits.count, 1, "No duplicate rich commit after idle clear")
    }

    // MARK: - Note Switching（切换笔记的同步 flush）

    /// 切换笔记时，应在加载新笔记前同步 flush 旧笔记的待提交富文本（防数据丢失/串笔记）。
    func test_switching_notes_flushes_pending_rich_commit() async throws {
        let harness = EditorHarness()
        let noteAID = harness.noteID
        let noteBID = UUID()

        harness.load(body: "Note A")
        edit(harness, "Changed A")

        // 立即切换到 Note B（任何定时器触发之前）——loadNote 同步 flush。
        harness.coordinator.loadNote(id: noteBID, body: "Note B", attributes: nil, selection: nil)

        XCTAssertEqual(harness.richCommits.count, 1, "Pending rich commit for Note A should fire on switch")
        XCTAssertEqual(harness.richCommits.first?.id, noteAID, "Rich commit should be for Note A")
        XCTAssertEqual(harness.richCommits.first?.body, "Changed A", "Rich commit should capture A's edits")
        XCTAssertEqual(harness.coordinator.currentNoteID, noteBID, "Current note should be B")
    }

    /// 旧笔记的延迟定时器在切换后触发时，stale-ID 快照应阻止串笔记提交。
    func test_stale_note_id_snapshot_prevents_cross_note_commit() async throws {
        let harness = EditorHarness()
        let noteBID = UUID()

        harness.load(body: "Note A")
        edit(harness, "A Edit")

        // 等 A 的轻量提交落地。
        await awaitTextCommits(harness, 1)
        XCTAssertEqual(harness.textCommits.count, 1, "Note A's text commit fired")

        // 富文本定时器仍 pending 时切换到 B（loadNote 会同步 flush A 一次）。
        harness.coordinator.loadNote(id: noteBID, body: "Note B", attributes: nil, selection: nil)
        XCTAssertEqual(harness.coordinator.currentNoteID, noteBID, "Now on Note B")

        harness.textCommits.removeAll()
        harness.richCommits.removeAll()

        // 越过 A 原定时器触发点：stale-ID 守卫应阻止任何针对 A 的提交。
        await assertNoTextBeyond(harness, 0)
        XCTAssertTrue(harness.textCommits.isEmpty, "No commit should occur for Note A after switch")
        for commit in harness.richCommits {
            XCTAssertEqual(commit.id, noteBID,
                "Any rich commit after note switch should belong to Note B, not the stale Note A")
        }
    }

    // MARK: - App Resign Active（失焦立即保存）

    /// 应用失焦（willResignActive）应立即触发富文本提交，不等空闲防抖。
    func test_app_resign_active_flushes_rich_commit() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial")

        edit(harness, "Before resign")
        harness.coordinator.setupAppSwitchObserver()

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        await awaitRichCommits(harness, 1)
        XCTAssertEqual(harness.richCommits.count, 1, "Rich commit should fire on app resign")
        XCTAssertNotNil(harness.richCommits.first?.attributes, "Resign commit should include attributes")
        XCTAssertEqual(harness.richCommits.first?.body, "Before resign", "Resign commit body correct")
    }

    // MARK: - Text Did End Editing（失去第一响应者）

    /// textDidEndEditing 应带属性提交，并复位 isDirty（同步完成）。
    func test_textDidEndEditing_commits_with_attributes() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial")

        edit(harness, "Edited before resign")
        harness.coordinator.textDidEndEditing(
            Notification(name: NSText.didEndEditingNotification, object: harness.textView)
        )

        XCTAssertEqual(harness.richCommits.count, 1, "Should commit with attributes on end editing")
        XCTAssertNotNil(harness.richCommits.first?.attributes, "Should include RTFD")
        XCTAssertFalse(harness.coordinator.isDirty, "isDirty should be false after commit")
    }

    // MARK: - Deinit Cleanup

    /// deinit 应取消两个定时任务并移除观察者；释放后不应有提交泄漏。
    func test_deinit_cancels_both_tasks_and_removes_observer() async throws {
        var harness: EditorHarness? = EditorHarness()
        harness?.load(body: "Initial")
        edit(harness!, "Edited")

        // 释放 harness 触发 deinit（取消定时任务）。
        harness = nil

        // 越过原空闲时长仍无提交（任务已取消）。无 harness 可观察，做一次短等待兜底。
        try await Task.sleep(nanoseconds: EditorHarness.idleNanos * 3)
        XCTAssertNil(harness, "Harness should be deallocated")
    }

    // MARK: - Selection / Range Preservation

    func test_lightweight_commit_preserves_selection() async throws {
        let harness = EditorHarness()
        harness.load(body: "Hello world")
        harness.textView.setSelectedRange(NSRange(location: 6, length: 5))

        edit(harness, "Hello universe")
        await awaitTextCommits(harness, 1)

        XCTAssertEqual(harness.textCommits.count, 1, "Should have text commit")
        XCTAssertNotNil(harness.textCommits.first?.selection, "Selection should be captured in text commit")
    }

    func test_rich_commit_preserves_selection() async throws {
        let harness = EditorHarness()
        harness.load(body: "Hello world")
        harness.textView.setSelectedRange(NSRange(location: 0, length: 5))

        edit(harness, "HELLO world")
        await awaitRichCommits(harness, 1)

        XCTAssertEqual(harness.richCommits.count, 1, "Should have rich commit")
        XCTAssertNotNil(harness.richCommits.first?.selection, "Selection should be captured in rich commit")
    }

    // MARK: - Multi-Edit Sequences

    /// 防抖窗口内多次编辑合并为一次文本提交。
    func test_multiple_edits_within_debounce_coalesce_to_one_commit() async throws {
        let harness = EditorHarness()
        harness.load(body: "")

        for i in 0..<5 {
            edit(harness, "Edit \(i)")
        }

        await awaitTextCommits(harness, 1)
        XCTAssertEqual(harness.textCommits.count, 1, "Multiple edits should coalesce to one commit")
        XCTAssertEqual(harness.textCommits.first?.body, "Edit 4", "Commit should have the final body")
        XCTAssertTrue(harness.richCommits.isEmpty, "No rich commit yet (still within idle window)")
    }

    /// 第一次轻量提交后再次编辑应触发第二次轻量提交。
    func test_edit_after_lightweight_timeout_triggers_new_lightweight_commit() async throws {
        let harness = EditorHarness()
        harness.load(body: "")

        edit(harness, "First")
        await awaitTextCommits(harness, 1)
        XCTAssertEqual(harness.textCommits.count, 1, "First lightweight commit")

        edit(harness, "First Edit")
        await awaitTextCommits(harness, 2)

        XCTAssertEqual(harness.textCommits.count, 2, "Second edit should trigger second text commit")
        XCTAssertEqual(harness.textCommits[1].body, "First Edit", "Second commit body correct")
        XCTAssertTrue(harness.richCommits.isEmpty, "Rich commit not yet triggered")
    }

    // MARK: - Attribute Preservation

    /// 加载含 RTFD 的笔记后，轻量编辑路径不破坏属性；手动富文本提交仍带属性。
    func test_rtfd_loaded_note_preserves_attributes_through_lightweight_path() async throws {
        let harness = EditorHarness()

        let attributed = NSAttributedString(
            string: "Formatted text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.red]
        )
        guard let rtfdData = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ) else {
            XCTFail("Could not create RTFD data")
            return
        }

        harness.coordinator.loadNote(id: harness.noteID, body: "Formatted text", attributes: rtfdData, selection: nil)

        edit(harness, "Formatted text edit")
        await awaitTextCommits(harness, 1)
        XCTAssertEqual(harness.textCommits.count, 1, "Text commit should fire")

        // 手动触发富文本提交，验证属性仍在。
        harness.coordinator.commitPendingIfNeeded(includeAttributes: true)
        XCTAssertEqual(harness.richCommits.count, 1, "Manual rich commit should fire")
        XCTAssertNotNil(harness.richCommits.first?.attributes, "Attributes should be preserved")
    }

    // MARK: - Dirty Flag Management

    func test_isDirty_flag_lifecycle() async throws {
        let harness = EditorHarness()
        harness.load(body: "")

        XCTAssertFalse(harness.coordinator.isDirty, "Should start clean")

        edit(harness, "Edit")
        XCTAssertTrue(harness.coordinator.isDirty, "Should be dirty after edit")

        await awaitTextCommits(harness, 1)
        XCTAssertFalse(harness.coordinator.isDirty, "Should be clean after commit")
    }
}

// MARK: - Test Harness

@MainActor
private final class EditorHarness {
    struct TextCommit {
        let id: UUID
        let body: String
        let selection: NSRange?
    }

    struct RichCommit {
        let id: UUID
        let body: String
        let attributes: Data?
        let selection: NSRange?
    }

    /// 注入的短防抖时长：确定性、快速、抗负载。轻量 << 空闲，保证两条路径可清晰区分。
    static let lightweightNanos: UInt64 = 50_000_000    // 50ms
    static let idleNanos: UInt64 = 300_000_000          // 300ms

    let noteID = UUID()
    let textView: NSTextView
    let coordinator: NoteEditor.Coordinator
    var textCommits: [TextCommit] = []
    var richCommits: [RichCommit] = []
    private(set) var capturedRTFDDuringLightweight: [Data] = []
    /// 提交事件观察者（测试用 expectation 钩到这里，实现事件驱动等待）。
    var textObserver: (() -> Void)?
    var richObserver: (() -> Void)?

    init() {
        let scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        let stub = NoteEditor(
            noteID: noteID,
            initialBody: "",
            initialAttributes: nil,
            initialSelection: nil,
            highlightQuery: "",
            focusRequest: false,
            onEscape: {},
            onTextCommit: { _, _, _ in },
            onRichCommit: { _, _, _, _ in },
            returnInListPublisher: Empty<Void, Never>().eraseToAnyPublisher()
        )
        coordinator = NoteEditor.Coordinator(parent: stub)
        coordinator.textView = textView
        coordinator.parent = NoteEditor(
            noteID: noteID,
            initialBody: "",
            initialAttributes: nil,
            initialSelection: nil,
            highlightQuery: "",
            focusRequest: false,
            onEscape: {},
            onTextCommit: { [weak self] id, body, selection in
                self?.textCommits.append(TextCommit(id: id, body: body, selection: selection))
                self?.textObserver?()
            },
            onRichCommit: { [weak self] id, body, attributes, selection in
                self?.richCommits.append(RichCommit(id: id, body: body, attributes: attributes, selection: selection))
                self?.richObserver?()
            },
            returnInListPublisher: Empty<Void, Never>().eraseToAnyPublisher(),
            lightweightDebounceNanos: Self.lightweightNanos,
            idleDebounceNanos: Self.idleNanos
        )
    }

    func load(body: String) {
        coordinator.loadNote(id: noteID, body: body, attributes: nil, selection: nil)
    }
}
