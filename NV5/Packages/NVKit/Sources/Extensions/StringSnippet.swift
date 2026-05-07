import Foundation
import SwiftUI

public extension String {
    func snippet(maxLength: Int = 120, removingMarkdown: Bool = true) -> String {
        var result = self.replacingOccurrences(of: "\n", with: " ")
                          .replacingOccurrences(of: "\t", with: " ")
        if removingMarkdown {
            result = result
                .replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\[\[(.+?)\]\]"#, with: "$1", options: .regularExpression)
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.count > maxLength {
            return String(result.prefix(maxLength)) + "…"
        }
        return result
    }
}

#Preview("String+Snippet") {
    let text = "## Hello World\n\nThis is **bold** and *italic* with [[wiki links]] and spaces  multiple   spaces"
    Text(text.snippet())
}