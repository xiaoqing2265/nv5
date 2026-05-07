import SwiftUI

public struct EmptyStateView: View {
    public let title: String
    public let systemImage: String
    public let description: String?
    public let action: (label: String, handler: () -> Void)?

    public init(
        title: String,
        systemImage: String,
        description: String? = nil,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let desc = description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let action = action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("EmptyStateView") {
    EmptyStateView(
        title: "No Notes",
        systemImage: "doc.text",
        description: "Create your first note to get started",
        action: ("Create Note", { })
    )
}