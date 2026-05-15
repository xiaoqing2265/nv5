import AppKit

enum PasteboardDestination {

    @discardableResult
    static func write(_ content: ExportContent, format: ExportFormat) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch (content, format) {
        case (.text(let s), .markdown):
            pb.setString(s, forType: .string)
            // 同时写入 Markdown UTI，让识别 MD 的 App 能拿到正确类型
            pb.setString(s, forType: NSPasteboard.PasteboardType(rawValue: format.utiIdentifier))
            return s.utf8.count

        case (.text(let s), .plainText):
            pb.setString(s, forType: .string)
            return s.utf8.count

        case (.rtfData(let d), .richText):
            pb.setData(d, forType: .rtf)
            // 同时提供纯文本兜底，让不识别 RTF 的目标应用也能粘贴
            if let attr = try? NSAttributedString(
                data: d,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                pb.setString(attr.string, forType: .string)
            }
            return d.count

        default:
            return 0
        }
    }
}