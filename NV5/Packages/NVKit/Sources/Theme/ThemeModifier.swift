import SwiftUI

public extension View {
    func nvThemed() -> some View {
        self.tint(NVTheme.Colors.dirtyIndicator)
            .font(NVTheme.Fonts.editorBody)
    }
}