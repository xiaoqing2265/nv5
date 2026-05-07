import SwiftUI

public extension View {
    func focused<Value: Hashable>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value,
        onNotification name: Notification.Name
    ) -> some View {
        self.focused(binding, equals: value)
            .onReceive(NotificationCenter.default.publisher(for: name)) { _ in
                binding.wrappedValue = value
            }
    }
}