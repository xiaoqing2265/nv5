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
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFindBar = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.delegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if context.coordinator.currentNoteID != noteID {
            context.coordinator.commitPendingIfNeeded()
            context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)
        }
        context.coordinator.applyHighlight(query: highlightQuery)

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

        init(parent: NoteEditor) {
            self.parent = parent
            self.lastFocusRequest = false
            super.init()
            returnInListCancellable = parent.returnInListPublisher?
                .sink { [weak self] _ in
                    self?.moveCursorToEnd()
                }
        }

        func moveCursorToEnd() {
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

        func loadNote(id: UUID, body: String, attributes: Data?, selection: NSRange?) {
            guard let textView = textView else { return }
            
            commitPendingIfNeeded()
            currentNoteID = id
            isDirty = false // Reset dirty flag for newly loaded note

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

            if let range = selection,
               NSMaxRange(range) <= textView.string.utf16.count {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
            }

            let undo = undoManagers[id] ?? UndoManager()
            undoManagers[id] = undo

            // Keep at most 10 undo managers to prevent unbounded memory growth
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
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { 
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

        func commitPendingIfNeeded() {
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

        func applyHighlight(query: String) {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: storage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            guard !query.isEmpty else { return }
            let terms = query.split(separator: " ").map(String.init)
            let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)
            let nsString = storage.string as NSString

            for term in terms where !term.isEmpty {
                var searchStart = 0
                while searchStart < nsString.length {
                    let searchRange = NSRange(location: searchStart, length: nsString.length - searchStart)
                    let found = nsString.range(of: term, options: .caseInsensitive, range: searchRange)
                    if found.location == NSNotFound { break }
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor, value: highlightColor, forCharacterRange: found
                    )
                    searchStart = found.location + found.length
                }
            }
        }
    }
}