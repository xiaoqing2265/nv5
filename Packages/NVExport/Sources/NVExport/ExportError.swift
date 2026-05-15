import Foundation

public enum ExportError: Error, LocalizedError {
    case conversionFailed(format: ExportFormat, underlying: Error?)
    case fileWriteFailed(url: URL, underlying: Error)
    case noteEmpty
    case directoryNotConfigured

    public var errorDescription: String? {
        switch self {
        case .conversionFailed(let f, _):
            return "无法将笔记转换为 \(f.displayName) 格式"
        case .fileWriteFailed(let url, _):
            return "无法写入文件：\(url.lastPathComponent)"
        case .noteEmpty:
            return "笔记内容为空，无法导出"
        case .directoryNotConfigured:
            return "请先在设置中配置导出目录"
        }
    }
}