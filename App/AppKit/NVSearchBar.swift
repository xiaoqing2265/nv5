import SwiftUI
import AppKit
import Combine
import NVStore

struct NVSearchBar: NSViewRepresentable {
    @Binding var text: String
    @Binding var typedText: String  // nvALT 风格：用户实际输入，不含自动补全部分
    var isFocused: Bool
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onEscape: () -> Void
    var onEscapeEmpty: () -> Void
    var focusCoordinator: FocusCoordinator
    var store: NoteStore

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "搜索或新建..."
        field.delegate = context.coordinator
        field.focusRingType = .none
        context.coordinator.selectAllCancellable = focusCoordinator.selectAllSubject
            .sink { _ in
                guard let editor = field.currentEditor() else { return }
                editor.selectAll(nil)
            }
        MainWindowController.shared.registerSearchField(field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.parent = self
        if isFocused && !context.coordinator.lastIsFocused {
            requestFocus(field: nsView)
        }
        context.coordinator.lastIsFocused = isFocused
    }

    private func requestFocus(field: NSSearchField) {
        Task { @MainActor in
            await Task.yield()
            guard let window = field.window,
                  window.firstResponder != field.currentEditor() else { return }
            window.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NVSearchBar
        var lastIsFocused = false
        var selectAllCancellable: AnyCancellable?
        private var escapeCount = 0
        private var historyIndex = -1
        private let historyStore = SearchHistoryStore.shared

        init(_ parent: NVSearchBar) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField,
                  let fieldEditor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }

            let newText = field.stringValue
            let oldText = parent.text
            escapeCount = 0

            // nvALT 风格：标题自动补全
            // 只在用户输入（不是删除）时触发
            if newText.count > oldText.count, !newText.isEmpty {
                if let matchedTitle = parent.store.noteTitlePrefixedBy(newText) {
                    let cursorPos = fieldEditor.selectedRange().location
                    if cursorPos < matchedTitle.count {
                        let remaining = String(matchedTitle.dropFirst(cursorPos))
                        // 插入补全部分并选中（用户继续输入会覆盖）
                        fieldEditor.insertText(remaining, replacementRange: NSRange(location: cursorPos, length: 0))
                        fieldEditor.setSelectedRange(NSRange(location: cursorPos, length: remaining.count))
                        // nvALT 风格：query 用完整标题过滤列表，typedText 保留用户实际输入用于高亮
                        parent.typedText = newText
                        parent.text = matchedTitle
                        return
                    }
                }
            }

            parent.typedText = newText
            parent.text = newText
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            escapeCount = 0
            historyIndex = -1
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // 记录真实检索意图，而非自动补全后的标题。
                if !parent.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    historyStore.record(parent.typedText)
                }
                historyIndex = -1
                parent.onSubmit()
                MainWindowController.shared.requestFocusAfterLoad()
                MainWindowController.shared.focusEditor()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !parent.text.isEmpty {
                    parent.text = ""
                    parent.typedText = ""
                    escapeCount = 1
                } else if escapeCount >= 1 {
                    parent.onEscapeEmpty()
                    escapeCount = 0
                } else {
                    parent.onEscape()
                    escapeCount = 0
                }
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    let history = historyStore.history()
                    guard !history.isEmpty else { return false }
                    historyIndex = min(historyIndex + 1, history.count - 1)
                    let restored = history[safe: historyIndex] ?? ""
                    parent.typedText = restored
                    parent.text = restored
                    return true
                }
                parent.onArrowUp()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    let history = historyStore.history()
                    guard !history.isEmpty else { return false }
                    if historyIndex > 0 {
                        historyIndex -= 1
                        let restored = history[safe: historyIndex] ?? ""
                        parent.typedText = restored
                        parent.text = restored
                    } else if historyIndex == 0 {
                        historyIndex = -1
                        parent.typedText = ""
                        parent.text = ""
                    }
                    return true
                }
                parent.onArrowDown()
                return true
            }
            return false
        }
    }
}
