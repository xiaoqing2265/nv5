import AppKit
import NVModel

public enum RichTextConverter {
    public static func convert(_ note: Note) throws -> ExportContent {
        let attributed = restoreAttributedString(from: note.bodyAttributes) ?? NSAttributedString(string: note.body)

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

    private static func restoreAttributedString(from data: Data?) -> NSAttributedString? {
        guard let data else { return nil }
        if let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) {
            return attr
        }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}