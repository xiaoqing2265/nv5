import Foundation

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