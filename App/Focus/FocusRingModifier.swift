import SwiftUI

struct FocusRingModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: isActive ? 2 : 0)
            )
    }
}

extension View {
    func focusRing(active: Bool = true) -> some View {
        modifier(FocusRingModifier(isActive: active))
    }
}
