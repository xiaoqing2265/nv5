import SwiftUI
import NVModel

struct NoteListColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    let selectedLabel: String?
    @FocusState private var searchFieldFocused: Bool

    private var filteredNotes: [Note] {
        let store = coordinator.store
        let base: [Note]
        if coordinator.query.isEmpty {
            base = store?.notes ?? []
        } else {
            base = store?.search(query: coordinator.query) ?? []
        }
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

            List(selection: Binding(
                get: { coordinator.selectedNoteID },
                set: { coordinator.selectedNoteID = $0 }
            )) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note)
                        .tag(Optional(note.id))
                        .contextMenu {
                            Button("Pin", systemImage: "pin") { togglePin(note) }
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
        }
        .onChange(of: filteredNotes) { _, newNotes in
            if let currentID = coordinator.selectedNoteID {
                if !newNotes.contains(where: { $0.id == currentID }) {
                    coordinator.selectedNoteID = newNotes.first?.id
                }
            } else {
                coordinator.selectedNoteID = newNotes.first?.id
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

        // 优先级 1: 全局笔记完全匹配(忽略大小写)
        let allNotes = coordinator.store?.notes ?? []
        let exact = allNotes.first {
            $0.title.caseInsensitiveCompare(coordinator.query) == .orderedSame
        }
        if let match = exact {
            coordinator.selectedNoteID = match.id
            coordinator.focusTarget = .editor
            return
        }

        // 优先级 2: 列表非空,激活虚拟选中项(当前选中或第一条)
        let notes = filteredNotes
        if !notes.isEmpty {
            let targetID = coordinator.selectedNoteID ?? notes.first?.id
            if let id = targetID {
                if coordinator.store?.notes.contains(where: { $0.id == id }) == true {
                    coordinator.selectedNoteID = id
                    coordinator.focusTarget = .editor
                    return
                }
                if let first = notes.first {
                    coordinator.selectedNoteID = first.id
                    coordinator.focusTarget = .editor
                    return
                }
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

    private func togglePin(_ note: Note) {
        Task {
            var updated = note
            updated.pinned.toggle()
            try? await coordinator.store?.upsert(updated)
        }
    }

    private func delete(_ note: Note) {
        Task { try? await coordinator.store?.softDelete(id: note.id) }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .lineLimit(1)
                Text(note.body.replacingOccurrences(of: "\n", with: " ").prefix(120))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if note.localDirty {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
    }
}