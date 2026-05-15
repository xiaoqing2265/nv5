import Foundation

public enum ExportFormat: String, CaseIterable, Sendable {
    case markdown = "md"
    case richText = "rtf"
    case plainText = "txt"

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .richText: return "Rich Text"
        case .plainText: return "Plain Text"
        }
    }

    public var fileExtension: String { rawValue }

    public var utiIdentifier: String {
        switch self {
        case .markdown: return "net.daringfireball.markdown"
        case .richText: return "public.rtf"
        case .plainText: return "public.plain-text"
        }
    }
}