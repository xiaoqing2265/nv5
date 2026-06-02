import SwiftUI
import NVModel
import NVStore
import NVKit

struct EditorColumn: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    @Environment(FocusCoordinator.self) private var focusCoordinator
    @FocusState private var editorFocused: Bool
    // 完整笔记（未截断 body + bodyAttributes），直接查库。store.notes 是摘要投影，
    // 不能用于编辑，否则保存会用截断内容覆盖完整正文。
    @State private var fullNote: Note?

    var body: some View {
        Group {
            if coordinator.multiSelectionMode {
                EmptyStateView(
                    title: "已选择 \(coordinator.selectedNoteIDs.count) 项",
                    systemImage: "checkmark.circle",
                    description: "可以在左侧列表执行批量操作。"
                )
            } else if let id = coordinator.selectedNoteID,
               let summary = store.notes.first(where: { $0.id == id }) {
                editorView(summary: summary)
                    .onChange(of: focusCoordinator.current) { _, new in
                        editorFocused = (new == .editor)
                    }
                    .onChange(of: editorFocused) { _, new in
                        if new && focusCoordinator.current != .editor {
                            focusCoordinator.focus(.editor)
                        }
                    }
                    .accessibilityLabel("编辑器")
                    .accessibilityElement(children: .contain)
                    // 切换笔记时加载完整正文；id 不变（仅内容/标题变化）不会重跑，避免编辑中重载。
                    .task(id: id) {
                        fullNote = await store.fullNote(id: id)
                        // fullNote 异步加载使编辑器比 store.notes 晚一拍渲染，会错过
                        // handleNotesChange / 新建笔记时早发的 focusEditor()。编辑器渲染后补一次
                        // 聚焦——仅当逻辑焦点本就应在编辑器（新建、或按回车进入编辑），避免误抢列表焦点。
                        if focusCoordinator.current == .editor {
                            DispatchQueue.main.async {
                                MainWindowController.shared.focusEditor()
                            }
                        }
                    }
            } else {
                EmptyStateView(
                    title: "选择或创建笔记",
                    systemImage: "doc.text",
                    description: "在上方搜索栏输入；按回车以该标题创建新笔记。"
                )
            }
        }
    }

    @ViewBuilder
    private func editorView(summary: NoteSummary) -> some View {
        VStack(spacing: 0) {
            TitleBar(note: summary)   // 标题/标签未被截断，用摘要保持响应式更新
            Divider()
            if let full = fullNote {
                // 编辑器由【已加载的完整笔记 fullNote】驱动（而非 selectedNoteID）。
                // 契约：编辑器只接收 store.fullNote(id:) 的完整正文，绝不喂 summary（截断 body / 无属性）。
                // 切换笔记时 fullNote 仍是旧笔记，直到 .task 加载完新笔记——编辑器持续显示旧笔记，
                // 待新完整正文就绪，NoteEditor 的 noteID 变化 → 复用同一编辑器走「笔记切换」分支，
                // 先 flush 旧笔记未保存内容再载入新笔记。这样既不截断、又保留切换 flush、还无 Color.clear 闪烁。
                NoteEditor(
                    noteID: full.id,
                    initialBody: full.body,
                    initialAttributes: full.bodyAttributes,
                    initialSelection: full.lastSelectedRange,
                    highlightQuery: coordinator.typedQuery,
                    focusRequest: focusCoordinator.current == .editor,
                    onEscape: { focusCoordinator.escapeToSearch() },
                    onTextCommit: { id, body, range in
                        Task {
                            do {
                                try await store.updateBodyText(id: id, body: body, selection: range)
                            } catch {
                                coordinator.showError(error)
                            }
                        }
                    },
                    onRichCommit: { id, body, attrs, range in
                        Task {
                            do {
                                try await store.updateBody(
                                    id: id, body: body, attributes: attrs, selection: range
                                )
                            } catch {
                                coordinator.showError(error)
                            }
                        }
                    },
                    returnInListPublisher: focusCoordinator.returnInListSubject.eraseToAnyPublisher(),
                    // 可等待落盘：终止/同步前 flush 通过它 await 到 DB 写入完成（持久化保证）。
                    onFlush: { id, body, attrs, range in
                        do {
                            try await store.updateBody(id: id, body: body, attributes: attrs, selection: range)
                        } catch {
                            coordinator.showError(error)
                        }
                    }
                )
                .focused($editorFocused)
            } else {
                // 完整正文加载中（本地查库，近乎瞬时）。不渲染编辑器以免加载到截断内容。
                Color.clear
            }
        }
    }
}

struct TitleBar: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(NoteStore.self) private var store
    let note: NoteSummary
    @State private var title: String = ""
    @State private var labelInput: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(NVTheme.Fonts.editorTitle)
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: title) { _, _ in
                        debouncedCommit()
                    }

                Spacer()

                Button {
                    if let view = NSApp.keyWindow?.contentView {
                        coordinator.shareCurrentNote(from: view)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("分享笔记")
            }

            HStack(spacing: 6) {
                ForEach(Array(note.labels), id: \.self) { label in
                    LabelChip(label, style: .removable {
                        updateLabels { $0.remove(label) }
                    })
                }
                TextField("Add label…", text: $labelInput)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(maxWidth: 120)
                    .onSubmit { addLabel() }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, NVTheme.Metrics.editorContentInset)
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
        Task {
            do {
                try await store.updateTitle(id: note.id, title: title)
            } catch {
                coordinator.showError(error)
                title = note.title
            }
        }
    }

    private func addLabel() {
        let trimmed = labelInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateLabels { $0.insert(trimmed) }
        labelInput = ""
    }

    /// 标签写回必须基于【完整 Note】：note 是摘要投影，直接 upsert 摘要会把截断正文写回数据库。
    private func updateLabels(_ transform: @escaping (inout Set<String>) -> Void) {
        let id = note.id
        Task {
            guard var full = await store.fullNote(id: id) else { return }
            transform(&full.labels)
            do {
                try await store.upsert(full)
            } catch {
                coordinator.showError(error)
            }
        }
    }
}
