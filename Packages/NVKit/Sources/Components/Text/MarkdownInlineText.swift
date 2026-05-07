import SwiftUI

public struct MarkdownInlineText: View {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }

    public var body: some View {
        if let attr = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
        } else {
            Text(raw)
        }
    }
}

#Preview("MarkdownInlineText") {
    MarkdownInlineText("This is **bold** and *italic* text")
        .padding()
}