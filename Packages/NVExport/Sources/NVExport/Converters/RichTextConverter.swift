import AppKit
import NVModel

public enum RichTextConverter {
    public static func convert(_ note: Note) throws -> ExportContent {
        let attributed: NSAttributedString
        if let data = note.bodyAttributes,
           let restored = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil
           ) {
            attributed = restored
        } else {
            attributed = NSAttributedString(string: note.body)
        }

        // 标题作为第一行加粗
        let result = NSMutableAttributedString()
        if !note.title.isEmpty {
            let titleAttr = NSAttributedString(
                string: note.title + "\n\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
            )
            result.append(titleAttr)
        }
        result.append(attributed)

        let range = NSRange(location: 0, length: result.length)
        do {
            let rtfData = try result.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            return .rtfData(rtfData)
        } catch {
            throw ExportError.conversionFailed(format: .richText, underlying: error)
        }
    }
}