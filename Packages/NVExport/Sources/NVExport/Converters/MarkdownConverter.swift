import AppKit
import NVModel

public enum MarkdownConverter {

    public static func convert(_ note: Note) throws -> ExportContent {
        var output = ""

        if !note.title.isEmpty {
            output += "# \(note.title)\n\n"
        }

        guard let data = note.bodyAttributes else {
            output += note.body
            return .text(output)
        }

        let attributed = NSAttributedString.restore(from: data) ?? NSAttributedString(string: note.body)
        output += renderMarkdown(from: attributed)
        return .text(output)
    }

    private static func renderMarkdown(from attr: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attr.length)

        attr.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let substring = (attr.string as NSString).substring(with: range)
            result += wrap(substring, with: attrs)
        }

        return result
    }

    /// 根据属性字典把文本片段包裹成 Markdown 语法
    private static func wrap(_ text: String, with attrs: [NSAttributedString.Key: Any]) -> String {
        var output = text

        // 链接处理
        if let url = attrs[.link] as? URL {
            return "[\(text)](\(url.absoluteString))"
        } else if let urlString = attrs[.link] as? String {
            return "[\(text)](\(urlString))"
        }

        // 字体粗细 / 斜体
        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            if isBold && isItalic {
                output = "***\(output)***"
            } else if isBold {
                output = "**\(output)**"
            } else if isItalic {
                output = "*\(output)*"
            }
        }

        // 下划线 → Markdown 没有标准语法，用 HTML
        if attrs[.underlineStyle] != nil {
            output = "<u>\(output)</u>"
        }

        // 删除线
        if attrs[.strikethroughStyle] != nil {
            output = "~~\(output)~~"
        }

        return output
    }
}