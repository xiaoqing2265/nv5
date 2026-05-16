import SwiftUI

struct FocusRingModifier: ViewModifier {
    @Environment(FocusCoordinator.self) private var focusCoordinator
    var capturesTab: Bool = true

    func body(content: Content) -> some View {
        content
            .onKeyPress { press in
                if press.key == .escape {
                    focusCoordinator.escapeToSearch()
                    return .handled
                }
                if capturesTab && press.key == .tab {
                    if press.modifiers.contains(.shift) {
                        focusCoordinator.focusPrevious()
                    } else {
                        focusCoordinator.focusNext()
                    }
                    return .handled
                }
                return .ignored
            }
    }
}

extension View {
    func focusRing(capturesTab: Bool = true) -> some View {
        modifier(FocusRingModifier(capturesTab: capturesTab))
    }
}
