import SwiftUI
import AppKit

public struct KeyboardCapturingTextField: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var onSubmit: () -> Void = {}
    public var onArrow: (Direction) -> Void = { _ in }
    public var onEscape: () -> Void = {}

    public enum Direction { case up, down, left, right }

    public init(
        text: Binding<String>,
        placeholder: String = "",
        onSubmit: @escaping () -> Void = {},
        onArrow: @escaping (Direction) -> Void = { _ in },
        onEscape: @escaping () -> Void = {}
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.onArrow = onArrow
        self.onEscape = onEscape
    }

    public func makeNSView(context: Context) -> InterceptingTextField {
        let field = InterceptingTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        return field
    }

    public func updateNSView(_ nsView: InterceptingTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.onSubmit = onSubmit
        nsView.onArrow = onArrow
        nsView.onEscape = onEscape
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    public final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: KeyboardCapturingTextField
        init(_ parent: KeyboardCapturingTextField) { self.parent = parent }

        @objc func changed(_ sender: NSTextField) {
            parent.text = sender.stringValue
        }
    }

    public final class InterceptingTextField: NSTextField {
        public var onSubmit: (() -> Void)?
        public var onArrow: ((Direction) -> Void)?
        public var onEscape: (() -> Void)?

        public override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76: onSubmit?()
            case 53: onEscape?()
            case 125: onArrow?(.down)
            case 126: onArrow?(.up)
            case 123: onArrow?(.left)
            case 124: onArrow?(.right)
            default: super.keyDown(with: event)
            }
        }
    }
}