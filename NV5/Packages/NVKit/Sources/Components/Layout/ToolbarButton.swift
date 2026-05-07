import SwiftUI

public struct ToolbarButton: View {
    public let systemImage: String
    public let label: String
    public let action: () -> Void
    public var keyboardShortcut: KeyEquivalent? = nil
    public var modifiers: EventModifiers = .command

    public init(
        _ label: String,
        systemImage: String,
        shortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
        self.keyboardShortcut = shortcut
        self.modifiers = modifiers
    }

    public var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
        }
        .help(label)
        .modifier(ConditionalShortcut(shortcut: keyboardShortcut, modifiers: modifiers))
    }

    private struct ConditionalShortcut: ViewModifier {
        let shortcut: KeyEquivalent?
        let modifiers: EventModifiers

        func body(content: Content) -> some View {
            if let shortcut = shortcut {
                content.keyboardShortcut(shortcut, modifiers: modifiers)
            } else {
                content
            }
        }
    }
}

#Preview("ToolbarButton") {
    VStack {
        ToolbarButton("New Note", systemImage: "square.and.pencil", shortcut: "n") {}
        ToolbarButton("Sync", systemImage: "arrow.triangle.2.circlepath") {}
    }
    .padding()
}