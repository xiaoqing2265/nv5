import SwiftUI

public struct DirtyDot: View {
    public var color: Color = .accentColor
    public var size: CGFloat = 6

    public init(color: Color = .accentColor, size: CGFloat = 6) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

#Preview("DirtyDot") {
    HStack(spacing: 16) {
        DirtyDot()
        DirtyDot(color: .blue, size: 8)
        DirtyDot(color: .orange, size: 10)
    }
    .padding()
}