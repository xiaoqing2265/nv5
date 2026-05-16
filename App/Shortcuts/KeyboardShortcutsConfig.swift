import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let noteNew = Self("note.new", default: .init(.n, modifiers: [.command]))
    static let noteNewFromSearch = Self("note.new.fromSearch", default: .init(.n, modifiers: [.command, .shift]))
    static let noteDelete = Self("note.delete", default: .init(.delete, modifiers: [.command]))
    static let noteArchiveToggle = Self("note.archive.toggle", default: .init(.a, modifiers: [.command, .shift]))
    static let noteLabelAdd = Self("note.label.add", default: .init(.l, modifiers: [.command, .shift]))

    static let noteCopyMarkdown = Self("note.copy.markdown", default: .init(.c, modifiers: [.command, .shift]))
    static let noteCopyRichText = Self("note.copy.richText", default: .init(.r, modifiers: [.command, .shift]))
    static let noteCopyPlainText = Self("note.copy.plainText", default: .init(.t, modifiers: [.command, .shift]))
    static let noteExport = Self("note.export", default: .init(.e, modifiers: [.command, .shift]))
    static let noteShare = Self("note.share")

    static let navSearch = Self("navigation.focus.search", default: .init(.l, modifiers: [.command]))
    static let navSidebar = Self("navigation.focus.sidebar", default: .init(.one, modifiers: [.command]))
    static let navList = Self("navigation.focus.list", default: .init(.two, modifiers: [.command]))
    static let navEditor = Self("navigation.focus.editor", default: .init(.three, modifiers: [.command]))
    static let navToggleSidebar = Self("navigation.toggleSidebar", default: .init(.b, modifiers: [.command]))
    static let navBackToPrevious = Self("navigation.backToPrevious", default: .init(.quote, modifiers: [.command]))

    static let appCommandPalette = Self("app.commandPalette", default: .init(.b, modifiers: [.command, .shift]))
    static let appPreferencesShortcuts = Self("app.preferences.shortcuts")

    // §3.3 ⌘F — 同 ⌘L（macOS 习惯）
    static let focusSearchF = Self("navigation.focus.search.f", default: .init(.f, modifiers: [.command]))
    // §3.3 ⌘0 — 聚焦搜索栏
    static let focusSearchZero = Self("navigation.focus.search.zero", default: .init(.zero, modifiers: [.command]))
}
