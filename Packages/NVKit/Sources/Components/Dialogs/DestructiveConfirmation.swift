import SwiftUI

public struct DestructiveConfirmation<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let actionLabel: String
    let action: () -> Void
    let content: () -> Content

    public init(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        actionLabel: String = "Delete",
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
        self.content = content
    }

    public var body: some View {
        content()
            .confirmationDialog(title, isPresented: $isPresented) {
                Button(actionLabel, role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let message = message { Text(message) }
            }
    }
}