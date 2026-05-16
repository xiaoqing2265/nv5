import SwiftUI

public extension Divider {
    @MainActor
    static func inset(leading: CGFloat = 16) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: leading)
            Divider()
        }
    }
}

#Preview("Divider Inset") {
    VStack {
        Text("Line 1")
        Divider.inset()
        Text("Line 2")
        Divider.inset(leading: 32)
        Text("Line 3")
    }
    .padding()
}