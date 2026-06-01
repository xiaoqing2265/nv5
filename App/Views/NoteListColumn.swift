import SwiftUI
import NVModel
import NVStore
import NVKit

struct NoteListColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    @Environment(FocusCoordinator.self) private var focusCoordinator
    let selectedItem: SidebarItem
    @FocusState private var listFocused: Bool
    @State private var cmdACancellable: Any?
    @State private var previewNote: Note?
    // 过滤结果由异步任务填充：store.search 命中数据库全文，天然异步。摘要级别（列表展示足够）。
    @State private var filteredNotes: [NoteSummary] = []
    @State private var filterTask: Task<Void, Never>?

    /// 唯一的检索意图来源 = `coordinator.typedQuery`（用户真实键入的关键词）。
    /// 列表过滤、新建笔记、编辑器高亮全部读它；`coordinator.query` 仅作搜索框显示，
    /// 不参与任何语义判断——这从结构上杜绝了「自动补全标题污染过滤器」导致的关键词消失。
    private func calculateFilteredNotes() async -> [NoteSummary] {
        let intent = coordinator.typedQuery

        if selectedItem == .archived {
            if intent.isEmpty { return store.archivedNotes }
            return await store.search(query: intent, includeArchived: true)
                .filter { $0.archived }
        }

        let base: [NoteSummary] = intent.isEmpty
            ? store.notes
            : await store.search(query: intent, includeArchived: false)
        return NoteListFilter.scope(base, to: selectedItem)
    }

    /// 重新计算过滤结果。`debounce` 用于键入场景，避免逐字符触发数据库查询。
    private func scheduleFilterUpdate(debounce: Bool) {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }
            let result = await calculateFilteredNotes()
            guard !Task.isCancelled else { return }
            filteredNotes = result
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                noteList
                if coordinator.multiSelectionMode {
                    multiSelectBar
                }
            }
            if let note = previewNote {
                NotePreviewOverlay(note: note) {
                    previewNote = nil
                }
            }
        }
        .onAppear { scheduleFilterUpdate(debounce: false) }
        .onDisappear {
            filterTask?.cancel()
            filterTask = nil
        }
        .onChange(of: coordinator.typedQuery) { _, _ in scheduleFilterUpdate(debounce: true) }
        .onChange(of: selectedItem) { _, _ in scheduleFilterUpdate(debounce: false) }
        .onChange(of: store.notes) { _, _ in scheduleFilterUpdate(debounce: false) }
        .onChange(of: store.archivedNotes) { _, _ in scheduleFilterUpdate(debounce: false) }
    }

    private var searchBar: some View {
        NVSearchBar(
            text: Binding(
                get: { coordinator.query },
                set: { coordinator.query = $0 }
            ),
            typedText: Binding(
                get: { coordinator.typedQuery },
                set: { coordinator.typedQuery = $0 }
            ),
            isFocused: focusCoordinator.current == .searchField,
            onSubmit: { searchBarReturn() },
            onArrowDown: { searchBarArrowDown() },
            onArrowUp: { searchBarArrowUp() },
            onEscape: { focusCoordinator.escapeToSearch() },
            onEscapeEmpty: { focusCoordinator.escapeToList() },
            focusCoordinator: focusCoordinator,
            store: store
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("搜索栏")
    }

    private var noteList: some View {
        ScrollViewReader { proxy in
            listWithHandlers
                .onAppear {
                    cmdACancellable = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        guard listFocused,
                              event.modifierFlags.contains(.command),
                              event.charactersIgnoringModifiers == "a" else { return event }
                        coordinator.selectAllNotes(in: filteredNotes)
                        return nil
                    }
                }
                .onDisappear {
                    if let token = cmdACancellable as? NSObject {
                        NSEvent.removeMonitor(token)
                    }
                    cmdACancellable = nil
                }
                .onChange(of: filteredNotes) { _, newNotes in
                    handleNotesChange(newNotes, proxy: proxy)
                }
        }
    }

    private var listWithHandlers: some View {
        listView
            .listStyle(.inset)
            .focused($listFocused)
            .accessibilityLabel("笔记列表")
            .accessibilityElement(children: .contain)
            .onKeyPress(.return, action: onReturn)
            .onKeyPress(.home, phases: .down, action: onHome)
            .onKeyPress(.end, phases: .down, action: onEnd)
            .onKeyPress(.pageUp, phases: .down, action: onPageUp)
            .onKeyPress(.pageDown, phases: .down, action: onPageDown)
            .onKeyPress(.upArrow, phases: .down, action: onUpArrow)
            .onKeyPress(.downArrow, phases: .down, action: onDownArrow)
            .onKeyPress(.space, phases: .down, action: onSpace)
            .onKeyPress(action: onAnyKey)  // nvALT 风格：任意键转发到搜索框
            .onChange(of: focusCoordinator.current) { _, new in
                listFocused = (new == .noteList)
            }
            .onChange(of: listFocused) { _, new in
                if new && focusCoordinator.current != .noteList {
                    focusCoordinator.focus(.noteList)
                }
            }
    }

    private func onReturn() -> KeyPress.Result {
        guard listFocused, coordinator.selectedNoteID != nil else { return .ignored }
        focusCoordinator.returnInList()
        return .handled
    }

    private func onHome(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        coordinator.selectedNoteID = filteredNotes.first?.id
        return .handled
    }

    private func onEnd(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        coordinator.selectedNoteID = filteredNotes.last?.id
        return .handled
    }

    private func onPageUp(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        pageMove(by: -20)
        return .handled
    }

    private func onPageDown(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        pageMove(by: 20)
        return .handled
    }

    private func onUpArrow(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        if event.modifiers.contains(.shift) {
            shiftSelect(by: -1)
        } else {
            moveSelection(by: -1)
        }
        return .handled
    }

    private func onDownArrow(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        if event.modifiers.contains(.shift) {
            shiftSelect(by: 1)
        } else {
            moveSelection(by: 1)
        }
        return .handled
    }

    private func moveSelection(by delta: Int) {
        let idx = filteredNotes.firstIndex(where: { $0.id == coordinator.selectedNoteID }) ?? -1
        let next = max(0, min(filteredNotes.count - 1, idx + delta))
        coordinator.selectedNoteID = filteredNotes[next].id
    }

    // nvALT 风格：列表中任意可打印字符转发到搜索框
    private func onAnyKey(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused else { return .ignored }

        // 获取按键字符
        guard let char = event.characters.first,
              char.isLetter || char.isNumber || char.isPunctuation || char == " " else {
            return .ignored
        }

        // 转发到搜索框：追加到现有检索意图（绝不覆盖整串），显示同步为意图本身。
        coordinator.typedQuery += String(char)
        coordinator.query = coordinator.typedQuery
        MainWindowController.shared.focusSearchField()
        focusCoordinator.focus(.searchField)

        return .handled
    }

    private func onSpace(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, let id = coordinator.selectedNoteID else { return .ignored }
        guard store.notes.contains(where: { $0.id == id })
              || store.archivedNotes.contains(where: { $0.id == id }) else { return .ignored }
        // 预览展示完整正文（store.notes 是摘要、body 截断），按 id 取完整 Note。
        Task {
            if let full = await store.fullNote(id: id) { previewNote = full }
        }
        return .handled
    }

    @ViewBuilder
    private var listView: some View {
        if coordinator.multiSelectionMode {
            List(selection: Binding(
                get: { coordinator.selectedNoteIDs },
                set: { coordinator.selectedNoteIDs = $0 }
            )) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note).tag(note.id)
                }
            }
        } else {
            List(selection: Binding(
                get: { coordinator.selectedNoteID },
                set: { coordinator.selectedNoteID = $0 }
            )) {
                ForEach(filteredNotes) { note in
                    noteRowWithMenu(note)
                }
            }
            .onDeleteCommand {
                let notes = filteredNotes
                if let id = coordinator.selectedNoteID,
                   let note = notes.first(where: { $0.id == id }) {
                    delete(note)
                }
            }
        }
    }

    private func noteRowWithMenu(_ note: NoteSummary) -> some View {
        NoteRow(note: note)
            .tag(Optional(note.id))
            .contextMenu {
                Button(note.archived ? "取消归档" : "归档", systemImage: note.archived ? "tray.and.arrow.up" : "archivebox") {
                    coordinator.setArchived(id: note.id, archived: !note.archived)
                }
                Button("分享...", systemImage: "square.and.arrow.up") {
                    if let window = NSApp.keyWindow,
                       let contentView = window.contentView {
                        coordinator.shareCurrentNote(from: contentView)
                    }
                }
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) {
                    delete(note)
                }
            }
    }

    @ViewBuilder
    private var multiSelectBar: some View {
        Divider()
        HStack {
            Text("已选择 \(coordinator.selectedNoteIDs.count) 项")
                .font(.caption)
            Spacer()
            Button("取消") {
                coordinator.multiSelectionMode = false
                coordinator.selectedNoteIDs.removeAll()
            }
            Button("导出") {
                coordinator.exportCurrentNote()
            }
            .disabled(coordinator.selectedNoteIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func pageMove(by delta: Int) {
        if let current = coordinator.selectedNoteID,
           let idx = filteredNotes.firstIndex(where: { $0.id == current }) {
            let target = min(filteredNotes.count - 1, max(0, idx + delta))
            coordinator.selectedNoteID = filteredNotes[target].id
        } else {
            coordinator.selectedNoteID = delta > 0 ? filteredNotes.first?.id : filteredNotes.last?.id
        }
    }

    private func shiftSelect(by delta: Int) {
        guard let current = coordinator.selectedNoteID,
              let currentIdx = filteredNotes.firstIndex(where: { $0.id == current }) else {
            if let first = filteredNotes.first {
                coordinator.selectedNoteID = first.id
                coordinator.anchorNoteID = first.id
                coordinator.selectedNoteIDs = [first.id]
            }
            return
        }
        let targetIdx = min(filteredNotes.count - 1, max(0, currentIdx + delta))
        let targetNote = filteredNotes[targetIdx]
        coordinator.selectedNoteID = targetNote.id
        if coordinator.anchorNoteID == nil {
            coordinator.anchorNoteID = current
            coordinator.selectedNoteIDs = [current]
        }
        coordinator.extendSelection(to: targetNote.id, allNotes: filteredNotes)
    }

    private func handleNotesChange(_ newNotes: [NoteSummary], proxy: ScrollViewProxy) {
        if let createdID = coordinator.recentlyCreatedNoteID {
            if newNotes.contains(where: { $0.id == createdID }) {
                coordinator.selectedNoteID = createdID
                coordinator.recentlyCreatedNoteID = nil
                focusCoordinator.focus(.editor)
                // 新笔记出现在列表后，通过 MainWindowController 直接聚焦编辑器
                // 这是 GRDB observation 异步推送后的兜底路径
                MainWindowController.shared.focusEditor()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation {
                        proxy.scrollTo(Optional(createdID), anchor: .top)
                    }
                }
            }
            return
        }
        if let currentID = coordinator.selectedNoteID {
            if !newNotes.contains(where: { $0.id == currentID }) {
                coordinator.selectedNoteID = newNotes.first?.id
            }
        } else {
            coordinator.selectedNoteID = newNotes.first?.id
        }
    }

    private func searchBarReturn() {
        let notes = filteredNotes
        if notes.isEmpty && !coordinator.typedQuery.isEmpty {
            Task { _ = await coordinator.newNoteFromQuery() }
        } else if !notes.isEmpty {
            if coordinator.selectedNoteID == nil ||
               !notes.contains(where: { $0.id == coordinator.selectedNoteID }) {
                coordinator.selectedNoteID = notes.first?.id
            }
            // 逻辑状态同步（焦点环显示）
            // 真正的焦点转移由 NVSearchBar 通过 MainWindowController 直接完成
            focusCoordinator.focus(.editor)
        }
    }

    private func searchBarArrowDown() {
        let notes = filteredNotes
        if !notes.isEmpty {
            if coordinator.selectedNoteID == nil {
                coordinator.selectedNoteID = notes.first?.id
            }
            focusCoordinator.focus(.noteList)
        }
    }

    private func searchBarArrowUp() {
        let notes = filteredNotes
        guard !notes.isEmpty else { return }
        coordinator.selectedNoteID = notes.last?.id
        focusCoordinator.focus(.noteList)
    }

    private func delete(_ note: NoteSummary) {
        Task {
            do {
                try await store.softDelete(id: note.id)
            } catch {
                coordinator.showError(error)
            }
        }
    }
}

struct NoteRow: View {
    let note: NoteSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(NVTheme.Fonts.listTitle)
                    .lineLimit(1)
                let snippet = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(snippet.isEmpty ? "无正文" : snippet.snippet(maxLength: 120))
                    .font(NVTheme.Fonts.listSnippet)
                    .foregroundStyle(snippet.isEmpty ? .quaternary : .secondary)
                    .lineLimit(2)
                RelativeTimeText(note.modifiedAt)
                    .font(NVTheme.Fonts.listMeta)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if note.localDirty {
                DirtyDot()
            }
        }
        .padding(.vertical, NVTheme.Metrics.listRowVerticalPadding)
    }
}

struct NotePreviewOverlay: View {
    let note: Note
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(note.displayTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                ScrollView {
                    // 注意：此处 note 来自 store.notes 摘要投影，body 可能被截断至 200 字、
                    // bodyAttributes 为 NULL。仅用于预览只读展示，严禁据此回写或当完整正文使用。
                    Text(note.body.isEmpty ? "无正文" : note.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)

                HStack {
                    Text("修改于 \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !note.labels.isEmpty {
                        FlowLayout {
                            ForEach(note.labels.sorted(), id: \.self) { label in
                                LabelChip(label)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(width: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }
}
