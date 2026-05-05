import SwiftUI
import NVModel

struct EditorColumn: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Group {
            if let id = coordinator.selectedNoteID,
               let note = coordinator.store?.notes.first(where: { $0.id == id }) {
                editorView(for: note)
            } else {
                ContentUnavailableView(
                    "Select or Create a Note",
                    systemImage: "doc.text",
                    description: Text("Type in the search bar above; press Return to create a new note with that title.")
                )
            }
        }
    }

    private func editorView(for note: Note) -> some View {
        VStack(spacing: 0) {
            TitleBar(note: note)
            Divider()
            NoteEditor(
                note: .constant(note),
                highlightQuery: coordinator.query,
                onCommit: { body, attrs, range in
                    Task {
                        try? await coordinator.store?.updateBody(
                            id: note.id, body: body, attributes: attrs, selection: range
                        )
                    }
                }
            )
        }
        .id(note.id)
    }
}

struct TitleBar: View {
    @Environment(AppCoordinator.self) private var coordinator
    let note: Note
    @State private var title: String = ""
    @State private var labelInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .onSubmit { commitTitle() }
                .onChange(of: title) { _, _ in
                    debouncedCommit()
                }

            HStack(spacing: 6) {
                ForEach(Array(note.labels), id: \.self) { label in
                    LabelChip(text: label) {
                        Task {
                            var updated = note
                            updated.labels.remove(label)
                            try? await coordinator.store?.upsert(updated)
                        }
                    }
                }
                TextField("Add label…", text: $labelInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(maxWidth: 120)
                    .onSubmit { addLabel() }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { title = note.title }
        .onChange(of: note.id) { _, _ in title = note.title }
    }

    @State private var titleTask: Task<Void, Never>?

    private func debouncedCommit() {
        titleTask?.cancel()
        titleTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            commitTitle()
        }
    }

    private func commitTitle() {
        guard title != note.title else { return }
        Task { try? await coordinator.store?.updateTitle(id: note.id, title: title) }
    }

    private func addLabel() {
        let trimmed = labelInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            var updated = note
            updated.labels.insert(trimmed)
            try? await coordinator.store?.upsert(updated)
            await MainActor.run { labelInput = "" }
        }
    }
}

struct LabelChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(text).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }
}