import SwiftUI
import AppKit
import Combine

struct NVSearchBar: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onEscape: () -> Void
    var onEscapeEmpty: () -> Void
    var focusCoordinator: FocusCoordinator

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
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
            escapeCount = 0
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            escapeCount = 0
            historyIndex = -1
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    historyStore.record(parent.text)
                }
                historyIndex = -1
                parent.onSubmit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !parent.text.isEmpty {
                    parent.text = ""
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
                    parent.text = history[safe: historyIndex] ?? ""
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
                        parent.text = history[safe: historyIndex] ?? ""
                    } else if historyIndex == 0 {
                        historyIndex = -1
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
