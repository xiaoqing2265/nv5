import SwiftUI
import AppKit

struct NVSearchBar: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = InterceptingSearchField()
        field.placeholderString = "Search or create..."
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.fieldChanged(_:))
        field.onSubmit = onSubmit
        field.onArrowDown = onArrowDown
        field.onArrowUp = onArrowUp
        field.focusRingType = .none
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let f = nsView as? InterceptingSearchField {
            f.onSubmit = onSubmit
            f.onArrowDown = onArrowDown
            f.onArrowUp = onArrowUp
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: NVSearchBar
        init(_ parent: NVSearchBar) { self.parent = parent }

        @objc func fieldChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }
    }
}

final class InterceptingSearchField: NSSearchField {
    var onSubmit: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onSubmit?()
        case 125:
            onArrowDown?()
        case 126:
            onArrowUp?()
        default:
            super.keyDown(with: event)
        }
    }
}