import SwiftUI

public struct HighlightedText: View {
    public let text: String
    public let highlights: [String]
    public var highlightColor: Color = .yellow.opacity(0.4)

    public init(_ text: String, highlighting terms: [String]) {
        self.text = text
        self.highlights = terms.filter { !$0.isEmpty }
    }

    public var body: some View {
        Text(buildAttributed())
    }

    private func buildAttributed() -> AttributedString {
        var attributed = AttributedString(text)
        for term in highlights {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: term, options: .caseInsensitive) {
                attributed[range].backgroundColor = highlightColor
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}

#Preview("HighlightedText") {
    HighlightedText("Hello world, this is a test", highlighting: ["hello", "test"])
        .padding()
}