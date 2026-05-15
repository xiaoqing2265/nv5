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

@MainActor
public final class ExportService {

    public init() {}

    // MARK: - 单条笔记

    /// 把单条笔记的指定格式内容写入系统剪贴板。
    /// - Returns: 写入的字节数，用于 UI 显示反馈
    @discardableResult
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

    public func share(
        _ note: Note,
        as format: ExportFormat,
        from view: NSView
    ) throws {
        let content = try render(note: note, as: format)
        ShareDestination.share(content, format: format, from: view)
    }

    // MARK: - 批量笔记

    /// 把多条笔记合并导出为单个文件，每条之间用 `---` 分隔
    public func exportMergedFile(
        _ notes: [Note],
        as format: ExportFormat,
        to fileURL: URL
    ) async throws {
        var merged = ""
        for (idx, note) in notes.enumerated() {
            let content = try render(note: note, as: format)
            guard case .text(let s) = content else {
                throw ExportError.conversionFailed(format: format, underlying: nil)
            }
            merged += s
            if idx < notes.count - 1 {
                merged += "\n\n---\n\n"
            }
        }
        try await Task.detached {
            try merged.write(to: fileURL, atomically: true, encoding: .utf8)
        }.value
    }

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
    private func render(note: Note, as format: ExportFormat) throws -> ExportContent {
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