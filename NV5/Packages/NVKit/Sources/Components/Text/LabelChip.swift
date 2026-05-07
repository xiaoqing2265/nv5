import SwiftUI

public struct LabelChip: View {
    public enum Style {
        case display
        case selectable(isSelected: Bool, action: () -> Void)
        case removable(action: () -> Void)
    }

    public let text: String
    public let style: Style
    public var color: Color = .secondary

    public init(_ text: String, style: Style = .display, color: Color = .secondary) {
        self.text = text
        self.style = style
        self.color = color
    }

    public var body: some View {
        switch style {
        case .display:
            content
        case .selectable(let isSelected, let action):
            Button(action: action) { content }
                .buttonStyle(.plain)
                .background(isSelected ? color.opacity(0.2) : .clear, in: Capsule())
        case .removable(let action):
            HStack(spacing: 2) {
                content
                Button(action: action) {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var content: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

#Preview("LabelChip variants") {
    VStack(spacing: 8) {
        LabelChip("work")
        LabelChip("urgent", style: .selectable(isSelected: true) {}, color: .red)
        LabelChip("draft", style: .removable {})
    }
    .padding()
}