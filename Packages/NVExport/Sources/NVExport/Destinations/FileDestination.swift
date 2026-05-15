import Foundation

enum FileDestination {

    static func write(
        content: ExportContent,
        suggestedName: String,
        format: ExportFormat,
        in directory: URL
    ) async throws -> URL {
        return try await Task.detached {
            // 文件名清理：移除文件系统不允许的字符
            let sanitized = sanitize(suggestedName)
            let baseURL = directory.appendingPathComponent(sanitized)
            let finalURL = resolveCollision(baseURL: baseURL, ext: format.fileExtension)

            do {
                switch content {
                case .text(let s):
                    try s.write(to: finalURL, atomically: true, encoding: .utf8)
                case .rtfData(let d):
                    try d.write(to: finalURL, options: .atomic)
                }
                return finalURL
            } catch {
                throw ExportError.fileWriteFailed(url: finalURL, underlying: error)
            }
        }.value
    }

    /// 移除 `/`、`:`、控制字符等，最大长度 80
    private static func sanitize(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: disallowed).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }

    /// 同名文件存在时追加 `-2`、`-3`...
    private static func resolveCollision(baseURL: URL, ext: String) -> URL {
        let candidate = baseURL.appendingPathExtension(ext)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        for i in 2...999 {
            let url = baseURL.deletingPathExtension()
                .appendingPathComponent("")  // workaround，保持原 baseURL
            let alt = URL(fileURLWithPath: "\(baseURL.path)-\(i).\(ext)")
            if !FileManager.default.fileExists(atPath: alt.path) {
                return alt
            }
        }
        return baseURL.appendingPathExtension(ext)
    }
}