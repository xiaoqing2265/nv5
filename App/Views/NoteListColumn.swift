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

    private var filteredNotes: [Note] {
        if selectedItem == .archived {
            if coordinator.query.isEmpty {
                return store.archivedNotes
            }
            return searchNotes(store.archivedNotes, query: coordinator.query)
        }

        let base: [Note] = coordinator.query.isEmpty
            ? store.notes
            : store.search(query: coordinator.query, includeArchived: false)

        switch selectedItem {
        case .all, .archived: return base
        case .label(let label): return base.filter { $0.labels.contains(label) }
        }
    }

    private func searchNotes(_ notes: [Note], query: String) -> [Note] {
        let tokens = query.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        return notes.filter { note in
            tokens.allSatisfy { token in
                note.title.range(of: token, options: .caseInsensitive) != nil
                || note.body.range(of: token, options: .caseInsensitive) != nil
                || note.labels.contains { $0.range(of: token, options: .caseInsensitive) != nil }
            }
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
    }

    private var searchBar: some View {
        NVSearchBar(
            text: Binding(
                get: { coordinator.query },
                set: { coordinator.query = $0 }
            ),
            isFocused: focusCoordinator.current == .searchField,
            onSubmit: { searchBarReturn() },
            onArrowDown: { searchBarArrowDown() },
            onArrowUp: { searchBarArrowUp() },
            onEscape: { focusCoordinator.escapeToSearch() },
            onEscapeEmpty: { focusCoordinator.escapeToList() },
            focusCoordinator: focusCoordinator
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .focusRing(active: focusCoordinator.current == .searchField)
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
            return .handled
        }
        return .ignored
    }

    private func onDownArrow(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, !filteredNotes.isEmpty else { return .ignored }
        if event.modifiers.contains(.shift) {
            shiftSelect(by: 1)
            return .handled
        }
        return .ignored
    }

    private func onSpace(_ event: KeyPress) -> KeyPress.Result {
        guard listFocused, let id = coordinator.selectedNoteID else { return .ignored }
        if let note = store.notes.first(where: { $0.id == id }) ?? store.archivedNotes.first(where: { $0.id == id }) {
            previewNote = note
            return .handled
        }
        return .ignored
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

    private func noteRowWithMenu(_ note: Note) -> some View {
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

    private func handleNotesChange(_ newNotes: [Note], proxy: ScrollViewProxy) {
        if let createdID = coordinator.recentlyCreatedNoteID {
            if newNotes.contains(where: { $0.id == createdID }) {
                coordinator.selectedNoteID = createdID
                coordinator.recentlyCreatedNoteID = nil
                focusCoordinator.focus(.editor)
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
        if notes.isEmpty && !coordinator.query.isEmpty {
            Task { _ = await coordinator.newNoteFromQuery() }
        } else if !notes.isEmpty {
            if coordinator.selectedNoteID == nil {
                coordinator.selectedNoteID = notes.first?.id
            }
            focusCoordinator.focus(.noteList)
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

    private func delete(_ note: Note) {
        Task { try? await store.softDelete(id: note.id) }
    }
}

struct NoteRow: View {
    let note: Note

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
