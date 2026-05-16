import SwiftUI

struct FocusRingModifier: ViewModifier {
    @Environment(FocusCoordinator.self) private var focusCoordinator

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                focusCoordinator.escapeToSearch()
                return .handled
            }
    }
}

extension View {
    func focusRing() -> some View {
        modifier(FocusRingModifier())
    }
}
