import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let noteNew = Self("note.new", default: .init(.n, modifiers: [.command]))
    static let noteNewFromSearch = Self("note.new.fromSearch", default: .init(.n, modifiers: [.command, .shift]))
    static let noteDelete = Self("note.delete", default: .init(.delete, modifiers: [.command]))
    static let noteArchiveToggle = Self("note.archive.toggle", default: .init(.a, modifiers: [.command, .shift]))
    static let noteLabelAdd = Self("note.label.add", default: .init(.t, modifiers: [.command, .shift]))

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
    static let navBack = Self("navigation.back", default: .init(.leftBracket, modifiers: [.command]))
    static let navForward = Self("navigation.forward", default: .init(.rightBracket, modifiers: [.command]))

    static let appCommandPalette = Self("app.commandPalette", default: .init(.b, modifiers: [.command, .shift]))
    static let appPreferencesShortcuts = Self("app.preferences.shortcuts")
    
    static let viewToggleFullScreenEditor = Self("view.toggleFullScreenEditor", default: .init(.f, modifiers: [.command, .control]))
    
    static let helpCheatSheet = Self("help.cheatSheet", default: .init(.slash, modifiers: [.command]))
    static let helpFeedback = Self("help.feedback")
    static let helpExportCrashLog = Self("help.exportCrashLog")
    
    static let navFocusLabels = Self("navigation.focus.labels", default: .init(.g, modifiers: [.control]))

    // 编辑器中的上一篇/下一篇笔记
    static let navPreviousNote = Self("navigation.previousNote", default: .init(.leftArrow, modifiers: [.option, .command]))
    static let navNextNote = Self("navigation.nextNote", default: .init(.rightArrow, modifiers: [.option, .command]))

    // 列表导航
    static let listHome = Self("list.home", default: .init(.home))
    static let listEnd = Self("list.end", default: .init(.end))
    static let listPageUp = Self("list.pageUp", default: .init(.pageUp))
    static let listPageDown = Self("list.pageDown", default: .init(.pageDown))
    static let listSelectAll = Self("list.selectAll", default: .init(.a, modifiers: [.command]))
}
