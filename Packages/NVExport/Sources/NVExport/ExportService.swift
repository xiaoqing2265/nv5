import Foundation
import AppKit
import NVModel

/// 转换结果的载体。字符串用于 MD/TXT，Data 用于 RTF 的归档数据。
public enum ExportContent: Sendable {
    case text(String)
    case rtfData(Data)

    var byteCount: Int {
        switch self {
        case .text(let s): return s.utf8.count
        case .rtfData(let d): return d.count
        }
    }
}

public final class ExportService: @unchecked Sendable {

    public init() {}

    // MARK: - 单条笔记

    /// 把单条笔记的指定格式内容写入系统剪贴板。
    /// - Returns: 写入的字节数，用于 UI 显示反馈
    @discardableResult
    @MainActor
    public func copyToClipboard(_ note: Note, as format: ExportFormat) throws -> Int {
        let content = try render(note: note, as: format)
        return PasteboardDestination.write(content, format: format)
    }

    /// 把单条笔记导出到指定目录。文件名规则：`<sanitized-title>.<ext>`，重名自动追加 `-2`、`-3`...
    /// - Parameter directory: 用户配置的导出根目录
    /// - Returns: 实际写入的文件 URL
    @discardableResult
    public func exportToFile(
        _ note: Note,
        as format: ExportFormat,
        in directory: URL
    ) async throws -> URL {
        let content = try render(note: note, as: format)
        return try await FileDestination.write(
            content: content,
            suggestedName: note.title.isEmpty ? "Untitled" : note.title,
            format: format,
            in: directory
        )
    }

    @MainActor
    public func share(
        _ note: Note,
        as format: ExportFormat,
        from view: NSView
    ) throws {
        let content = try render(note: note, as: format)
        ShareDestination.share(content, format: format, from: view)
    }

    // MARK: - 批量笔记

    /// 把多条笔记导出为目录下的多个文件
    public func exportToDirectory(
        _ notes: [Note],
        as format: ExportFormat,
        in directory: URL
    ) async throws -> [URL] {
        var urls: [URL] = []
        for note in notes {
            let url = try await exportToFile(note, as: format, in: directory)
            urls.append(url)
        }
        return urls
    }

    // MARK: - Private

    /// 核心转换分发，所有格式由独立 Converter 完成
    nonisolated func render(note: Note, as format: ExportFormat) throws -> ExportContent {
        switch format {
        case .markdown:
            return try MarkdownConverter.convert(note)
        case .richText:
            return try RichTextConverter.convert(note)
        case .plainText:
            return try PlainTextConverter.convert(note)
        }
    }
}