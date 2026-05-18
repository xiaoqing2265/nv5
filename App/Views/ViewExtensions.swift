import SwiftUI

extension View {
    /// 添加列表导航快捷键支持（Home, End, Page Up/Down）
    func listNavigationKeyboardShortcuts(
        onHome: @escaping () -> Void,
        onEnd: @escaping () -> Void,
        onPageUp: @escaping () -> Void,
        onPageDown: @escaping () -> Void,
        onSelectAll: @escaping () -> Void
    ) -> some View {
        self
            .onKeyPress(.home) {
                onHome()
                return .handled
            }
            .onKeyPress(.end) {
                onEnd()
                return .handled
            }
            .onKeyPress(.pageUp) {
                onPageUp()
                return .handled
            }
            .onKeyPress(.pageDown) {
                onPageDown()
                return .handled
            }
    }

    /// 添加高对比度支持
    func highContrastSupport(_ increaseContrast: Bool) -> some View {
        if increaseContrast {
            return AnyView(self.brightness(0.1))
        } else {
            return AnyView(self)
        }
    }
}
