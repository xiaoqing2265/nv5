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
