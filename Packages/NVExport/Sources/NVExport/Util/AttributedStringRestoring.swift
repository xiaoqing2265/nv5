import AppKit

extension NSAttributedString {
    static func restore(from data: Data?) -> NSAttributedString? {
        guard let data else { return nil }
        for docType: NSAttributedString.DocumentType in [.rtfd, .rtf] {
            if let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: docType],
                documentAttributes: nil
            ) {
                return attr
            }
        }
        return nil
    }
}
