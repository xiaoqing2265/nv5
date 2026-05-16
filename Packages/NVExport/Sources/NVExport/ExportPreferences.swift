import Foundation

// NOTE: NV5 当前未启用 App Sandbox（见 NV5App.entitlements com.apple.security.app-sandbox=false）。
// security-scoped bookmark 在非沙盒环境下退化为普通 bookmark，行为兼容。
// 保留 .withSecurityScope 调用以便未来启用沙盒时无需修改代码。

public enum ExportPreferences {
    public static var exportDirectory: URL? {
        get {
            guard let bookmark = UserDefaults.standard.data(forKey: "exportDirectoryBookmark") else { return nil }
            var stale = false
            return try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &stale
            )
        }
    }

    public static func setExportDirectory(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: "exportDirectoryBookmark")
    }
}