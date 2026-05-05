import SwiftUI
import NVModel

struct NoteListColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    let selectedLabel: String?

    @State private var filteredNotes: [Note] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NVSearchBar(
                text: Binding(
                    get: { coordinator.query },
                    set: { coordinator.query = $0 }
                ),
                onSubmit: { activateOrCreate() },
                onArrowDown: { moveSelection(by: 1) },
                onArrowUp: { moveSelection(by: -1) }
            )
            .focused($searchFocused)
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
                if let id = coordinator.selectedNoteID,
                   let note = filteredNotes.first(where: { $0.id == id }) {
                    delete(note)
                }
            }
        }
        .task(id: refreshKey) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            searchFocused = true
        }
    }

    private var refreshKey: String {
        "\(coordinator.query)|\(selectedLabel ?? "")|\(coordinator.store?.notes.count ?? 0)"
    }

    private func refresh() async {
        let base: [Note]
        if coordinator.query.isEmpty {
            base = coordinator.store?.notes ?? []
        } else {
            base = (try? await coordinator.store?.search(query: coordinator.query)) ?? []
        }
        if let label = selectedLabel {
            filteredNotes = base.filter { $0.labels.contains(label) }
        } else {
            filteredNotes = base
        }
    }

    private func activateOrCreate() {
        let exact = filteredNotes.first { $0.title.caseInsensitiveCompare(coordinator.query) == .orderedSame }
        if let match = exact {
            coordinator.selectedNoteID = match.id
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        } else if !coordinator.query.isEmpty {
            coordinator.newNote()
        } else if let first = filteredNotes.first {
            coordinator.selectedNoteID = first.id
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredNotes.isEmpty else { return }
        let currentIndex = filteredNotes.firstIndex { $0.id == coordinator.selectedNoteID } ?? -1
        let newIndex = max(0, min(filteredNotes.count - 1, currentIndex + delta))
        coordinator.selectedNoteID = filteredNotes[newIndex].id
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
                Text(snippet)
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

    private var snippet: String {
        let body = note.body.replacingOccurrences(of: "\n", with: " ")
        return String(body.prefix(120))
    }
}