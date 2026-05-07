import SwiftUI
import AppKit

public enum NVTheme {
    public enum Colors {
        public static let wikiLink = Color.purple
        public static let externalLink = Color.blue
        public static let doneTag = Color.gray
        public static let highlight = Color.yellow.opacity(0.4)
        public static let dirtyIndicator = Color.accentColor
        public static let conflictMarker = Color.orange
    }

    public enum Fonts {
        public static let listTitle = Font.system(.body, design: .default, weight: .medium)
        public static let listSnippet = Font.caption
        public static let listMeta = Font.caption2
        public static let editorBody = Font.system(size: 14)
        public static let editorTitle = Font.title2.weight(.semibold)
    }

    public enum Metrics {
        public static let listRowVerticalPadding: CGFloat = 4
        public static let editorContentInset: CGFloat = 16
        public static let toolbarItemSpacing: CGFloat = 8
    }
}

public extension NSFont {
    static func nvEditorBody(size: CGFloat = 14) -> NSFont {
        .systemFont(ofSize: size)
    }

    static func nvEditorHeading(level: Int) -> NSFont {
        let size = max(14, 26 - CGFloat(level * 2))
        return .boldSystemFont(ofSize: size)
    }
}