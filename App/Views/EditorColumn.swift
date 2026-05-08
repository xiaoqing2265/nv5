import SwiftUI
import NVModel
import NVStore

struct EditorColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if let id = coordinator.selectedNoteID,
               let note = store.notes.first(where: { $0.id == id }) {
                editorView(for: note)
                    .onChange(of: coordinator.focusTarget) { _, new in
                        editorFocused = (new == .editor)
                    }
                    .onChange(of: editorFocused) { _, new in
                        if new && coordinator.focusTarget != .editor {
                            coordinator.focusTarget = .editor
                        }
                    }
            } else {
                ContentUnavailableView(
                    "选择或创建笔记",
                    systemImage: "doc.text",
                    description: Text("在上方搜索栏输入；按回车以该标题创建新笔记。")
                )
            }
        }
    }

    private func editorView(for note: Note) -> some View {
        VStack(spacing: 0) {
            TitleBar(note: note)
            Divider()
            NoteEditor(
                noteID: note.id,
                initialBody: note.body,
                initialAttributes: note.bodyAttributes,
                initialSelection: note.lastSelectedRange,
                highlightQuery: coordinator.query,
                focusRequest: coordinator.focusTarget == .editor,
                onEscape: { coordinator.focusTarget = .searchField },
                onCommit: { body, attrs, range in
                    Task {
                        try? await store.updateBody(
                            id: note.id, body: body, attributes: attrs, selection: range
                        )
                    }
                }
            )
            .focused($editorFocused)
        }
    }
}

struct TitleBar: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
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
                    LabelChipView(label: label) {
                        Task {
                            var updated = note
                            updated.labels.remove(label)
                            try? await store.upsert(updated)
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
        Task { try? await store.updateTitle(id: note.id, title: title) }
    }

    private func addLabel() {
        let trimmed = labelInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            var updated = note
            updated.labels.insert(trimmed)
            try? await store.upsert(updated)
            await MainActor.run { labelInput = "" }
        }
    }
}

struct LabelChipView: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption)
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