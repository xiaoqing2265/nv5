import SwiftUI
import AppKit
import NVModel
import Combine

struct NoteEditor: NSViewRepresentable {
    let noteID: UUID
    let initialBody: String
    let initialAttributes: Data?
    let initialSelection: NSRange?
    let highlightQuery: String
    var focusRequest: Bool
    var onEscape: () -> Void
    let onCommit: (UUID, String, Data?, NSRange?) -> Void
    var returnInListPublisher: AnyPublisher<Void, Never>?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isFieldEditor = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.delegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)

        // nvALT 风格：注册编辑器到中心控制器
        MainWindowController.shared.registerEditor(textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if context.coordinator.currentNoteID != noteID {
            textView.window?.makeFirstResponder(nil)
            // 捕获并立即清除标志，避免泄漏到后续无关的笔记切换
            let shouldFocusAfterLoad = MainWindowController.shared.pendingFocusAfterLoad
            MainWindowController.shared.pendingFocusAfterLoad = false
            DispatchQueue.main.async {
                context.coordinator.commitPendingIfNeeded()
                context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)

                // nvALT 风格：笔记加载完成后立即高亮，返回第一个匹配位置
                let firstMatchRange = context.coordinator.applyHighlight(query: highlightQuery)

                // 如果没有保存的选区且找到了匹配，跳转到第一个匹配位置
                if (initialSelection == nil || initialSelection?.length == 0) && firstMatchRange.location != NSNotFound {
                    textView.setSelectedRange(firstMatchRange)
                    textView.scrollRangeToVisible(firstMatchRange)
                } else if let range = initialSelection {
                    // 否则滚动到保存的选区
                    textView.scrollRangeToVisible(range)
                }

                // 焦点转移在高亮和滚动之后
                if shouldFocusAfterLoad {
                    MainWindowController.shared.focusEditor()
                }
            }
        } else {
            // 笔记未切换：focusEditor() 已在 NVSearchBar 同步调用，消费标志防止泄漏
            MainWindowController.shared.pendingFocusAfterLoad = false
            // 笔记未切换但 query 可能变化，需要重新高亮
            _ = context.coordinator.applyHighlight(query: highlightQuery)
        }

        if focusRequest && !context.coordinator.lastFocusRequest {
            context.coordinator.bringFocus()
        }
        context.coordinator.lastFocusRequest = focusRequest
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NSTextView?
        var currentNoteID: UUID?
        var lastFocusRequest: Bool
        private var saveTask: Task<Void, Never>?
        private var undoManagers: [UUID: UndoManager] = [:]
        private var returnInListCancellable: AnyCancellable?

        var isDirty: Bool = false

        @MainActor init(parent: NoteEditor) {
            self.parent = parent
            self.lastFocusRequest = false
            super.init()
            returnInListCancellable = parent.returnInListPublisher?
                .sink { [weak self] _ in
                    self?.moveCursorToEnd()
                }
        }

        @MainActor func moveCursorToEnd() {
            guard let textView = textView else { return }
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            bringFocus()
        }

        func bringFocus() {
            guard let textView = textView else { return }
            Task { @MainActor in
                await Task.yield()
                guard let window = textView.window,
                      window.firstResponder != textView else { return }
                window.makeFirstResponder(textView)
            }
        }

        @MainActor func loadNote(id: UUID, body: String, attributes: Data?, selection: NSRange?) {
            guard let textView = textView else { return }

            commitPendingIfNeeded()
            currentNoteID = id
            isDirty = false

            let attributed: NSAttributedString
            if let data = attributes,
               let restored = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtfd],
                   documentAttributes: nil) {
                attributed = restored
            } else {
                attributed = NSAttributedString(
                    string: body,
                    attributes: [.font: NSFont.systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.labelColor])
            }

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(attributed)
            textView.textStorage?.endEditing()

            // 恢复保存的选区（滚动由调用方在高亮后决定）
            if let range = selection, NSMaxRange(range) <= textView.string.utf16.count {
                textView.setSelectedRange(range)
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }

            let undo = undoManagers[id] ?? UndoManager()
            undoManagers[id] = undo
            if undoManagers.count > 10 {
                let oldest = undoManagers.keys.filter { $0 != id }.dropLast(9)
                oldest.forEach { undoManagers.removeValue(forKey: $0) }
            }

            if let storage = textView.textStorage {
                TextDecoratorPipeline.runAll(on: storage)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            isDirty = true
            saveTask?.cancel()
            let snapshotID = currentNoteID
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.currentNoteID == snapshotID else { return }
                    if let storage = textView.textStorage {
                        TextDecoratorPipeline.runAll(on: storage)
                    }
                    self?.commitPendingIfNeeded()
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            commitPendingIfNeeded()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        @MainActor func commitPendingIfNeeded() {
            guard isDirty,
                  let id = currentNoteID,
                  let textView = textView,
                  let storage = textView.textStorage else { return }
            
            let plain = storage.string
            let rtfd = try? storage.data(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            let selection = textView.selectedRange()
            parent.onCommit(id, plain, rtfd, selection)
            isDirty = false
        }

        @MainActor func applyHighlight(query: String) -> NSRange {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage,
                  storage.length > 0,
                  textView.window != nil else { return NSMakeRange(NSNotFound, 0) }

            let fullRange = NSRange(location: 0, length: storage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            guard !query.isEmpty else { return NSMakeRange(NSNotFound, 0) }

            let terms = query.split(separator: " ").map(String.init)
            let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)
            let nsString = storage.string as NSString

            // nvALT 风格：记录第一个匹配位置
            var firstMatchRange = NSMakeRange(NSNotFound, 0)

            for term in terms where !term.isEmpty {
                var searchStart = 0
                while searchStart < nsString.length {
                    let searchRange = NSRange(location: searchStart, length: nsString.length - searchStart)
                    let found = nsString.range(of: term, options: .caseInsensitive, range: searchRange)
                    if found.location == NSNotFound { break }

                    // 记录第一个匹配位置（最靠前的）
                    if firstMatchRange.location == NSNotFound || found.location < firstMatchRange.location {
                        firstMatchRange = found
                    }

                    layoutManager.addTemporaryAttribute(
                        .backgroundColor, value: highlightColor, forCharacterRange: found
                    )
                    searchStart = found.location + found.length
                }
            }

            return firstMatchRange
        }
    }
}