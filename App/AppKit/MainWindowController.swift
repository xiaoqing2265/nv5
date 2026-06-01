import AppKit

/// nvALT 风格的窗口控制器：作为焦点管理的中心枢纽
///
/// 设计理念来自 nvALT 的 AppController：
/// - 直接持有关键 UI 组件的引用（搜索框、编辑器）
/// - 所有焦点转移都通过这个 controller 同步执行
/// - 没有中间抽象层，没有异步，没有状态机
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    /// 当前活跃的编辑器 NSTextView（弱引用，类似 nvALT 的 IBOutlet）
    weak var editorTextView: NSTextView?

    /// 当前活跃的搜索框 NSSearchField（弱引用）
    weak var searchField: NSSearchField?

    /// 笔记换载完成后是否需要重新聚焦编辑器
    /// 用于处理 searchBarReturn 触发笔记切换时的时序问题
    var pendingFocusAfterLoad = false

    /// 当前活跃编辑器的 flush 闭包（nvALT 风格的 flushAllNoteChanges 钩子）。
    /// App 层（终止、同步前）通过它把编辑器内存中未保存的击键提交到 DB 并【等待落盘】。
    /// 用闭包桥接，避免本控制器依赖 NoteEditor.Coordinator 的具体类型。
    private var activeEditorFlush: (() async -> Void)?
    /// 注册者标识：保证旧编辑器 deinit 时不会误清掉新编辑器刚注册的闭包。
    private var flushOwnerID: ObjectIdentifier?

    private init() {}

    // MARK: - 注册组件（在 makeNSView 时调用）

    func registerEditor(_ textView: NSTextView) {
        self.editorTextView = textView
    }

    func unregisterEditor(_ textView: NSTextView) {
        if self.editorTextView === textView {
            self.editorTextView = nil
        }
    }

    func registerEditorFlush(ownerID: ObjectIdentifier, _ flush: @escaping () async -> Void) {
        self.activeEditorFlush = flush
        self.flushOwnerID = ownerID
    }

    /// 仅当请求者就是当前注册者时才清空——避免旧编辑器异步 deinit 误清新编辑器的注册。
    func clearEditorFlush(ownerID: ObjectIdentifier) {
        if flushOwnerID == ownerID {
            self.activeEditorFlush = nil
            self.flushOwnerID = nil
        }
    }

    /// 提交当前编辑器内存中未保存的内容到 DB，并【等待写入完成】才返回。
    /// 这是 nvALT flushAllNoteChanges 的等价物：终止/同步前调用，保证不丢未保存击键。
    func flushActiveEditor() async {
        await activeEditorFlush?()
    }

    func registerSearchField(_ field: NSSearchField) {
        self.searchField = field
    }

    // MARK: - 焦点转移（nvALT 风格：直接、同步、无异步）

    /// 将焦点移到编辑器（类似 nvALT 的 [window makeFirstResponder:textView]）
    func focusEditor() {
        guard let textView = editorTextView,
              let window = textView.window else { return }
        if window.firstResponder != textView {
            window.makeFirstResponder(textView)
        }
    }

    /// 请求在笔记换载完成后聚焦编辑器
    /// 用于 searchBarReturn 触发笔记切换的场景
    func requestFocusAfterLoad() {
        pendingFocusAfterLoad = true
    }

    /// 将焦点移到搜索框
    func focusSearchField() {
        guard let field = searchField,
              let window = field.window else { return }
        if window.firstResponder != field.currentEditor() {
            window.makeFirstResponder(field)
        }
    }
}
