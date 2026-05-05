import SwiftUI
import AppKit
import NVModel

struct NoteEditor: NSViewRepresentable {
    @Binding var note: Note
    let highlightQuery: String
    let onCommit: (String, Data?, NSRange?) -> Void

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
        context.coordinator.loadNote(note)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.currentNoteID != note.id {
            context.coordinator.loadNote(note)
        }
        context.coordinator.applyHighlight(query: highlightQuery)
        if context.coordinator.shouldFocus {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.shouldFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NSTextView?
        var currentNoteID: UUID?
        var shouldFocus = false
        private var saveTask: Task<Void, Never>?
        private var undoManagers: [UUID: UndoManager] = [:]

        init(parent: NoteEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                forName: .focusEditor, object: nil, queue: .main
            ) { [weak self] _ in self?.shouldFocus = true }
        }

        func loadNote(_ note: Note) {
            guard let textView = textView else { return }
            if let oldID = currentNoteID, oldID != note.id {
                commitNow()
            }
            currentNoteID = note.id

            let attributed: NSAttributedString
            if let data = note.bodyAttributes,
               let restored = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtfd],
                   documentAttributes: nil) {
                attributed = restored
            } else {
                attributed = NSAttributedString(
                    string: note.body,
                    attributes: [.font: NSFont.systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.labelColor])
            }

            textView.textStorage?.setAttributedString(attributed)

            if let range = note.lastSelectedRange,
               NSMaxRange(range) <= textView.string.utf16.count {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
            }

            let undo = undoManagers[note.id] ?? UndoManager()
            undoManagers[note.id] = undo
            textView.undoManager?.removeAllActions()

            TextDecoratorPipeline.runAll(on: textView.textStorage!)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.commitNow() }
            }
            TextDecoratorPipeline.runAll(on: textView.textStorage!)
        }

        func textDidEndEditing(_ notification: Notification) {
            commitNow()
        }

        private func commitNow() {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }
            let plain = storage.string
            let rtfd = try? storage.data(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            let selection = textView.selectedRange()
            parent.onCommit(plain, rtfd, selection)
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