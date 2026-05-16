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
        VStack(spacing: 0) {
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
                focusCoordinator: focusCoordinator
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .focusRing()

            Divider()

            ScrollViewReader { proxy in
                Group {
                    if coordinator.multiSelectionMode {
                        List(selection: Binding(
                            get: { coordinator.selectedNoteIDs },
                            set: { coordinator.selectedNoteIDs = $0 }
                        )) {
                            ForEach(filteredNotes) { note in
                                NoteRow(note: note)
                                    .tag(note.id)
                            }
                        }
                    } else {
                        List(selection: Binding(
                            get: { coordinator.selectedNoteID },
                            set: { coordinator.selectedNoteID = $0 }
                        )) {
                            ForEach(filteredNotes) { note in
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
                .listStyle(.inset)
                .focused($listFocused)
                .onKeyPress(.return) {
                    guard listFocused, coordinator.selectedNoteID != nil else { return .ignored }
                    focusCoordinator.returnInList()
                    return .handled
                }
                .onChange(of: focusCoordinator.current) { _, new in
                    listFocused = (new == .noteList)
                }
                .onChange(of: listFocused) { _, new in
                    if new && focusCoordinator.current != .noteList {
                        focusCoordinator.focus(.noteList)
                    }
                }
                .onChange(of: filteredNotes) { _, newNotes in
                    if let createdID = coordinator.recentlyCreatedNoteID {
                        if newNotes.contains(where: { $0.id == createdID }) {
                            coordinator.selectedNoteID = createdID
                            coordinator.recentlyCreatedNoteID = nil
                            coordinator.focusTarget = .none
                            coordinator.focusTarget = .editor
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
            }

            if coordinator.multiSelectionMode {
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
        }
    }

    private func searchBarReturn() {
        let notes = filteredNotes
        if notes.isEmpty && !coordinator.query.isEmpty {
            Task { _ = await coordinator.newNote() }
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
        // no-op or move to last item
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
                Text(note.title.isEmpty ? "Untitled" : note.title)
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
