import AppKit

// MARK: - Note Commands

struct NewNoteCommand: AppCommand {
    let id = "note.new"
    let title = "新建笔记"
    let subtitle: String? = nil
    let keywords = ["new", "新建", "create"]
    let category: CommandCategory = .note
    let symbol = "square.and.pencil"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        _ = await context.coordinator.newNote()
        context.focus.focus(.editor)
    }
}

struct NewNoteFromSearchCommand: AppCommand {
    let id = "note.new.fromSearch"
    let title = "用搜索词新建笔记"
    let subtitle: String? = "即使有匹配也强制新建（query 为空时使用「无标题」）"
    let keywords = ["new", "强制新建", "force create"]
    let category: CommandCategory = .note
    let symbol = "plus.square"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        _ = await context.coordinator.newNoteFromQuery()
        context.focus.focus(.editor)
    }
}

struct DeleteNoteCommand: AppCommand {
    let id = "note.delete"
    let title = "删除当前笔记"
    let subtitle: String? = nil
    let keywords = ["delete", "删除", "trash"]
    let category: CommandCategory = .note
    let symbol = "trash"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async {
        guard let id = context.coordinator.selectedNoteID else { return }
        try? await context.coordinator.store.softDelete(id: id)
    }
}

struct ArchiveToggleCommand: AppCommand {
    let id = "note.archive.toggle"
    let title = "切换归档状态"
    let subtitle: String? = nil
    let keywords = ["archive", "归档", "unarchive"]
    let category: CommandCategory = .note
    let symbol = "archivebox"

    func isEnabled(in context: CommandContext) -> Bool {
        guard let id = context.coordinator.selectedNoteID else { return false }
        return context.coordinator.store.notes.contains { $0.id == id }
    }

    func run(in context: CommandContext) async {
        guard let id = context.coordinator.selectedNoteID,
              let note = context.coordinator.store.notes.first(where: { $0.id == id }) else { return }
        context.coordinator.setArchived(id: id, archived: !note.archived)
    }
}

struct AddLabelCommand: AppCommand {
    let id = "note.label.add"
    let title = "添加标签"
    let subtitle: String? = nil
    let keywords = ["label", "tag", "标签"]
    let category: CommandCategory = .note
    let symbol = "tag"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async {
        // Programmatic label addition handled via UI - focus editor for manual entry
        context.focus.focus(.editor)
    }
}

// MARK: - Export Commands

struct CopyMarkdownCommand: AppCommand {
    let id = "note.copy.markdown"
    let title = "复制为 Markdown"
    let subtitle: String? = "将当前笔记转为 Markdown 写入剪贴板"
    let keywords = ["copy", "markdown", "md"]
    let category: CommandCategory = .exportShare
    let symbol = "doc.on.clipboard"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async { context.coordinator.copyAsMarkdown() }
}

struct CopyRichTextCommand: AppCommand {
    let id = "note.copy.richText"
    let title = "复制为富文本"
    let subtitle: String? = "将当前笔记转为 RTF 写入剪贴板"
    let keywords = ["copy", "rich", "rtf", "富文本"]
    let category: CommandCategory = .exportShare
    let symbol = "doc.richtext"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async { context.coordinator.copyAsRichText() }
}

struct CopyPlainTextCommand: AppCommand {
    let id = "note.copy.plainText"
    let title = "复制为纯文本"
    let subtitle: String? = "将当前笔记转为纯文本写入剪贴板"
    let keywords = ["copy", "plain", "纯文本"]
    let category: CommandCategory = .exportShare
    let symbol = "text.alignleft"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async { context.coordinator.copyAsPlainText() }
}

struct ExportNoteCommand: AppCommand {
    let id = "note.export"
    let title = "导出到文件"
    let subtitle: String? = nil
    let keywords = ["export", "save", "导出"]
    let category: CommandCategory = .exportShare
    let symbol = "square.and.arrow.up"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async { context.coordinator.exportCurrentNote() }
}

struct ShareNoteCommand: AppCommand {
    let id = "note.share"
    let title = "分享..."
    let subtitle: String? = nil
    let keywords = ["share", "分享"]
    let category: CommandCategory = .exportShare
    let symbol = "square.and.arrow.up"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.selectedNoteID != nil }

    func run(in context: CommandContext) async {
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        context.coordinator.shareCurrentNote(from: contentView)
    }
}

// MARK: - Navigation Commands

struct FocusSearchCommand: AppCommand {
    let id = "navigation.focus.search"
    let title = "聚焦搜索栏"
    let subtitle: String? = nil
    let keywords = ["focus", "search", "搜索"]
    let category: CommandCategory = .navigation
    let symbol = "magnifyingglass"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async { context.focus.focus(.searchField) }
}

struct FocusSidebarCommand: AppCommand {
    let id = "navigation.focus.sidebar"
    let title = "聚焦侧栏"
    let subtitle: String? = nil
    let keywords = ["sidebar", "侧栏"]
    let category: CommandCategory = .navigation
    let symbol = "sidebar.left"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async { context.focus.focus(.sidebar) }
}

struct FocusListCommand: AppCommand {
    let id = "navigation.focus.list"
    let title = "聚焦笔记列表"
    let subtitle: String? = nil
    let keywords = ["list", "列表"]
    let category: CommandCategory = .navigation
    let symbol = "list.bullet"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async { context.focus.focus(.noteList) }
}

struct FocusEditorCommand: AppCommand {
    let id = "navigation.focus.editor"
    let title = "聚焦编辑器"
    let subtitle: String? = nil
    let keywords = ["editor", "编辑器"]
    let category: CommandCategory = .navigation
    let symbol = "doc.text"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async { context.focus.focus(.editor) }
}

struct ToggleSidebarCommand: AppCommand {
    let id = "navigation.toggleSidebar"
    let title = "显示/隐藏侧栏"
    let subtitle: String? = nil
    let keywords = ["sidebar", "toggle"]
    let category: CommandCategory = .view
    let symbol = "sidebar.left"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async { context.focus.toggleSidebar() }
}

struct BackToPreviousCommand: AppCommand {
    let id = "navigation.backToPrevious"
    let title = "切换到上一篇笔记"
    let subtitle: String? = nil
    let keywords = ["back", "previous", "上一篇"]
    let category: CommandCategory = .navigation
    let symbol = "arrow.uturn.left"

    func isEnabled(in context: CommandContext) -> Bool { context.coordinator.previousNoteID != nil }

    func run(in context: CommandContext) async {
        context.coordinator.switchToPreviousNote()
    }
}

struct NavigateBackCommand: AppCommand {
    let id = "navigation.back"
    let title = "上一个笔记"
    let subtitle: String? = "导航历史后退"
    let keywords = ["back", "后退", "上一个"]
    let category: CommandCategory = .navigation
    let symbol = "arrow.left"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        context.coordinator.navigateBack()
    }
}

struct NavigateForwardCommand: AppCommand {
    let id = "navigation.forward"
    let title = "下一个笔记"
    let subtitle: String? = "导航历史前进"
    let keywords = ["forward", "前进", "下一个"]
    let category: CommandCategory = .navigation
    let symbol = "arrow.right"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        context.coordinator.navigateForward()
    }
}

struct ToggleFullScreenEditorCommand: AppCommand {
    let id = "view.toggleFullScreenEditor"
    let title = "全屏编辑器"
    let subtitle: String? = "隐藏侧栏和列表，专注编辑"
    let keywords = ["fullscreen", "全屏", "专注"]
    let category: CommandCategory = .view
    let symbol = "arrow.up.left.and.arrow.down.right"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        context.coordinator.toggleFullScreenEditor()
    }
}

// MARK: - App Commands

struct CommandPaletteCommand: AppCommand {
    let id = "app.commandPalette"
    let title = "打开命令面板"
    let subtitle: String? = nil
    let keywords = ["command", "palette", "命令"]
    let category: CommandCategory = .app
    let symbol = "command"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        context.focus.showPalette = true
    }
}

struct ShortcutsPreferencesCommand: AppCommand {
    let id = "app.preferences.shortcuts"
    let title = "偏好设置 - 快捷键"
    let subtitle: String? = "自定义快捷键绑定"
    let keywords = ["shortcuts", "偏好", "快捷键"]
    let category: CommandCategory = .app
    let symbol = "keyboard"

    func isEnabled(in context: CommandContext) -> Bool { true }

    func run(in context: CommandContext) async {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Registration

enum BuiltinCommands {
    static let all: [AppCommand] = [
        NewNoteCommand(),
        NewNoteFromSearchCommand(),
        DeleteNoteCommand(),
        ArchiveToggleCommand(),
        AddLabelCommand(),
        CopyMarkdownCommand(),
        CopyRichTextCommand(),
        CopyPlainTextCommand(),
        ExportNoteCommand(),
        ShareNoteCommand(),
        FocusSearchCommand(),
        FocusSidebarCommand(),
        FocusListCommand(),
        FocusEditorCommand(),
        ToggleSidebarCommand(),
        BackToPreviousCommand(),
        NavigateBackCommand(),
        NavigateForwardCommand(),
        ToggleFullScreenEditorCommand(),
        CommandPaletteCommand(),
        ShortcutsPreferencesCommand(),
    ]
}
