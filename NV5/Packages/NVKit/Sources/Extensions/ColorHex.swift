import SwiftUI

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

#Preview("Color+Hex") {
    HStack(spacing: 8) {
        Circle().fill(Color(hex: "FF0000")).frame(width: 30, height: 30)
        Circle().fill(Color(hex: "00FF00")).frame(width: 30, height: 30)
        Circle().fill(Color(hex: "0000FF")).frame(width: 30, height: 30)
        Circle().fill(Color(hex: "FF000080")).frame(width: 30, height: 30)
    }
    .padding()
}