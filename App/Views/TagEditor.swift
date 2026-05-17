import SwiftUI
import NVStore
import NVModel
import NVKit

struct TagEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @Environment(OverlayManager.self) private var overlayManager
    @State private var newLabel: String = ""
    @FocusState private var inputFocused: Bool

    private var currentNote: Note? {
        guard let id = coordinator.selectedNoteID else { return nil }
        return store.notes.first(where: { $0.id == id })
            ?? store.archivedNotes.first(where: { $0.id == id })
    }

    private var allLabels: [String] {
        let labels = store.notes.reduce(into: Set<String>()) { set, note in
            set.formUnion(note.labels)
        }
        return labels.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑标签")
                    .font(.headline)
                Spacer()
                Button {
                    overlayManager.close(.tagEditor)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let note = currentNote {
                if note.labels.isEmpty {
                    Text("当前笔记没有标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout {
                        ForEach(Array(note.labels), id: \.self) { label in
                            LabelChip(label, style: .removable {
                                Task {
                                    var updated = note
                                    updated.labels.remove(label)
                                    try? await store.upsert(updated)
                                }
                            })
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("输入新标签…", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                        .onSubmit { addLabel() }
                        .onKeyPress(.delete) {
                            if newLabel.isEmpty, let note = currentNote, !note.labels.isEmpty {
                                if let last = note.labels.sorted().last {
                                    Task {
                                        var updated = note
                                        updated.labels.remove(last)
                                        try? await store.upsert(updated)
                                    }
                                }
                                return .handled
                            }
                            return .ignored
                        }
                    Button("添加") {
                        addLabel()
                    }
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !allLabels.isEmpty {
                    Divider()
                    Text("所有标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(allLabels, id: \.self) { label in
                            let isSelected = currentNote?.labels.contains(label) ?? false
                            LabelChip(label, style: .selectable(isSelected: isSelected) {
                                toggleLabel(label)
                            })
                        }
                    }
                }
            } else {
                Text("请先选择一篇笔记")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear {
            inputFocused = true
            overlayManager.open(.tagEditor)
        }
        .onDisappear {
            overlayManager.close(.tagEditor)
        }
        .onKeyPress(.escape) {
            overlayManager.close(.tagEditor)
            return .handled
        }
    }

    private func addLabel() {
        let trimmed = newLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let note = currentNote else { return }
        Task {
            var updated = note
            updated.labels.insert(trimmed)
            try? await store.upsert(updated)
            await MainActor.run { newLabel = "" }
        }
    }

    private func toggleLabel(_ label: String) {
        guard let note = currentNote else { return }
        Task {
            var updated = note
            if updated.labels.contains(label) {
                updated.labels.remove(label)
            } else {
                updated.labels.insert(label)
            }
            try? await store.upsert(updated)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: position, anchor: .topLeading, proposal: proposal)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
