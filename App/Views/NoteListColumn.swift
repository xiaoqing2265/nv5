import SwiftUI
import NVModel
import NVStore
import NVKit

struct NoteListColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    let selectedLabel: String?
    @FocusState private var searchFieldFocused: Bool

    private var filteredNotes: [Note] {
        let base: [Note] = coordinator.query.isEmpty
            ? store.notes
            : store.search(query: coordinator.query)
        guard let label = selectedLabel else { return base }
        return base.filter { $0.labels.contains(label) }
    }

    var body: some View {
        VStack(spacing: 0) {
            NVSearchBar(
                text: Binding(
                    get: { coordinator.query },
                    set: { coordinator.query = $0 }
                ),
                isFocused: searchFieldFocused,
                onSubmit: { activateOrCreate() },
                onArrowDown: { moveSelection(by: 1) },
                onArrowUp: { moveSelection(by: -1) },
                onEscape: {
                    if coordinator.query.isEmpty {
                        NSApp.hide(nil)
                    } else {
                        coordinator.query = ""
                    }
                }
            )
            .focused($searchFieldFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { coordinator.selectedNoteID },
                    set: { coordinator.selectedNoteID = $0 }
                )) {
                    ForEach(filteredNotes) { note in
                        NoteRow(note: note)
                            .tag(Optional(note.id))
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(note)
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand {
                    let notes = filteredNotes
                    if let id = coordinator.selectedNoteID,
                       let note = notes.first(where: { $0.id == id }) {
                        delete(note)
                    }
                }
                .onChange(of: filteredNotes) { _, newNotes in
                    // If a note was just created, wait for it to appear in the list
                    if let createdID = coordinator.recentlyCreatedNoteID {
                        if newNotes.contains(where: { $0.id == createdID }) {
                            // New note has appeared via ValueObservation — select it and clear flag
                            coordinator.selectedNoteID = createdID
                            coordinator.recentlyCreatedNoteID = nil
                            // Re-trigger focus: editor wasn't rendered when focusTarget was first set,
                            // so onChange(focusTarget) missed it. Toggle to force a change event.
                            coordinator.focusTarget = .none
                            coordinator.focusTarget = .editor
                            
                            // 强制滚动到新建的笔记，避免 SwiftUI List 从空变满时的滚动偏移 bug
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                withAnimation {
                                    proxy.scrollTo(Optional(createdID), anchor: .top)
                                }
                            }
                        }
                        // Either way, don't override selection while waiting for the new note
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
        }
        .onChange(of: coordinator.focusTarget) { _, new in
            searchFieldFocused = (new == .searchField)
        }
        .onChange(of: searchFieldFocused) { _, new in
            if new && coordinator.focusTarget != .searchField {
                coordinator.focusTarget = .searchField
            }
        }
    }

    private func activateOrCreate() {
        // 短路检查:query 为空时直接激活当前选中项
        if coordinator.query.isEmpty {
            if coordinator.selectedNoteID != nil {
                coordinator.focusTarget = .editor
            }
            return
        }

        let notes = filteredNotes

        // 优先级 1: 当前列表内的完全匹配
        if let exact = notes.first(where: {
            $0.title.caseInsensitiveCompare(coordinator.query) == .orderedSame
        }) {
            coordinator.selectedNoteID = exact.id
            coordinator.focusTarget = .editor
            return
        }

        // 优先级 2: 列表非空,激活虚拟选中项(当前选中或第一条)
        if !notes.isEmpty {
            let targetID = coordinator.selectedNoteID
                .flatMap { id in notes.first(where: { $0.id == id })?.id }
                ?? notes.first?.id
            if let id = targetID {
                coordinator.selectedNoteID = id
                coordinator.focusTarget = .editor
                return
            }
        }

        // 优先级 3: 搜索词非空(去空白后)且列表为空,创建新笔记
        let trimmed = coordinator.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Task {
                _ = await coordinator.newNote()
            }
        }
        // 否则无操作(搜索词全是空白)
    }

    private func moveSelection(by delta: Int) {
        let notes = filteredNotes
        guard !notes.isEmpty else { return }
        let currentIndex = notes.firstIndex { $0.id == coordinator.selectedNoteID } ?? -1
        let newIndex = max(0, min(notes.count - 1, currentIndex + delta))
        coordinator.selectedNoteID = notes[newIndex].id
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