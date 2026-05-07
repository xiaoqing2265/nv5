import SwiftUI

public struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    let label: () -> Label
    @State private var isRunning = false

    public init(action: @escaping () async -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button {
            guard !isRunning else { return }
            Task {
                isRunning = true
                await action()
                isRunning = false
            }
        } label: {
            HStack(spacing: 6) {
                if isRunning { ProgressView().controlSize(.small) }
                label()
            }
        }
        .disabled(isRunning)
    }
}

#Preview("AsyncButton") {
    AsyncButton {
        try? await Task.sleep(for: .seconds(2))
    } label: {
        Text("Save")
    }
    .padding()
}