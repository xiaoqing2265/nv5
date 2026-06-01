import SwiftUI
import AppKit
import NVModel
import Combine

struct NoteEditor: NSViewRepresentable {
    let noteID: UUID
    let initialBody: String
    let initialAttributes: Data?
    let initialSelection: NSRange?
    let highlightQuery: String
    var focusRequest: Bool
    var onEscape: () -> Void
    let onTextCommit: (UUID, String, NSRange?) -> Void
    let onRichCommit: (UUID, String, Data?, NSRange?) -> Void
    var returnInListPublisher: AnyPublisher<Void, Never>?
    /// 终止/同步前的【可等待】落盘闭包（默认 no-op，测试 harness 无需提供）。
    /// 与自动保存的同步闭包分离：commitPendingAndWait 通过它 await 到 DB 写入完成。
    var onFlush: (UUID, String, Data?, NSRange?) async -> Void = { _, _, _, _ in }
    /// 自动保存防抖时长（可注入）。生产用默认值；测试注入短值以实现确定性快速测试。
    var lightweightDebounceNanos: UInt64 = 300_000_000  // 轻量文本保存：300ms
    var idleDebounceNanos: UInt64 = 2_000_000_000        // 富文本空闲保存：2s

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isFieldEditor = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.delegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)

        // nvALT 风格：注册编辑器到中心控制器
        MainWindowController.shared.registerEditor(textView)

        // 注册 flush 钩子：终止/同步前 App 层据此把未保存击键提交到 DB 并【等待落盘】。
        MainWindowController.shared.registerEditorFlush(ownerID: ObjectIdentifier(context.coordinator)) { [weak coordinator = context.coordinator] in
            await coordinator?.commitPendingAndWait(includeAttributes: true)
        }

        // nvALT 风格：监听应用切换，立即保存（不依赖防抖定时器）
        context.coordinator.setupAppSwitchObserver()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if context.coordinator.currentNoteID != noteID {
            // 只在编辑器持有焦点时才清空，避免抢走列表焦点导致方向键失效
            if textView.window?.firstResponder == textView {
                textView.window?.makeFirstResponder(nil)
            }
            // 捕获并立即清除标志，避免泄漏到后续无关的笔记切换
            let shouldFocusAfterLoad = MainWindowController.shared.pendingFocusAfterLoad
            MainWindowController.shared.pendingFocusAfterLoad = false
            DispatchQueue.main.async {
                context.coordinator.commitPendingIfNeeded(includeAttributes: true)
                context.coordinator.loadNote(id: noteID, body: initialBody, attributes: initialAttributes, selection: initialSelection)

                // nvALT 风格：笔记加载完成后立即高亮，返回第一个匹配位置
                let firstMatchRange = context.coordinator.applyHighlight(query: highlightQuery)

                // 如果没有保存的选区且找到了匹配，跳转到第一个匹配位置
                if (initialSelection == nil || initialSelection?.length == 0) && firstMatchRange.location != NSNotFound {
                    textView.setSelectedRange(firstMatchRange)
                    textView.scrollRangeToVisible(firstMatchRange)
                } else if let range = initialSelection {
                    // 否则滚动到保存的选区
                    textView.scrollRangeToVisible(range)
                }

                // 焦点转移在高亮和滚动之后
                if shouldFocusAfterLoad {
                    MainWindowController.shared.focusEditor()
                }
            }
        } else {
            // 笔记未切换：始终重绘高亮（让黄色标记随正文实时同步），
            // 但只有当检索词【实际变化】时才跳转选区——编辑过程中的重渲染（自动保存、
            // 状态刷新等）检索词不变，绝不能把光标拉回匹配处并整段选中，否则按 delete 误删。
            let queryChanged = (context.coordinator.lastHighlightQuery != highlightQuery)
            let firstMatchRange = context.coordinator.applyHighlight(query: highlightQuery)
            if queryChanged && !highlightQuery.isEmpty && firstMatchRange.location != NSNotFound {
                textView.setSelectedRange(firstMatchRange)
                textView.scrollRangeToVisible(firstMatchRange)
            }
        }

        // 记录本次检索词，作为下次「是否变化」的判定基准（覆盖两个分支）。
        context.coordinator.lastHighlightQuery = highlightQuery

        if focusRequest && !context.coordinator.lastFocusRequest {
            context.coordinator.bringFocus()
        }
        context.coordinator.lastFocusRequest = focusRequest
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NSTextView?
        var currentNoteID: UUID?
        var lastFocusRequest: Bool
        // 记录上次应用的高亮检索词：仅当它【实际变化】时才把选区跳到首个匹配，
        // 避免编辑过程中的重渲染反复抢走光标（否则按 delete 会误删被选中的匹配文字）。
        var lastHighlightQuery: String?
        private var saveTask: Task<Void, Never>?
        private var richSaveTask: Task<Void, Never>?
        private var undoManagers: [UUID: UndoManager] = [:]
        private var returnInListCancellable: AnyCancellable?
        private var appSwitchObserver: Any?  // nvALT 风格：应用切换监听器

        var isDirty: Bool = false
        private var needsRichCommit: Bool = false

        @MainActor init(parent: NoteEditor) {
            self.parent = parent
            self.lastFocusRequest = false
            super.init()
            returnInListCancellable = parent.returnInListPublisher?
                .sink { [weak self] _ in
                    self?.moveCursorToEnd()
                }
        }

        deinit {
            saveTask?.cancel()
            richSaveTask?.cancel()
            if let observer = appSwitchObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            // flush 闭包用 weak 持有本 coordinator，释放后调用为 no-op；
            // 异步清空注册，但带 owner 校验：只清掉确实是本 coordinator 注册的那个，
            // 避免误清新编辑器（重建/交叠时）刚注册的闭包。
            let ownerID = ObjectIdentifier(self)
            Task { @MainActor in
                MainWindowController.shared.clearEditorFlush(ownerID: ownerID)
            }
        }

        // nvALT 风格：监听应用切换，立即保存
        func setupAppSwitchObserver() {
            appSwitchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.commitPendingIfNeeded(includeAttributes: true)
                }
            }
        }

        @MainActor func moveCursorToEnd() {
            guard let textView = textView else { return }
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            bringFocus()
        }

        func bringFocus() {
            guard let textView = textView else { return }
            Task { @MainActor in
                await Task.yield()
                guard let window = textView.window,
                      window.firstResponder != textView else { return }
                window.makeFirstResponder(textView)
            }
        }

        @MainActor func loadNote(id: UUID, body: String, attributes: Data?, selection: NSRange?) {
            guard let textView = textView else { return }

            commitPendingIfNeeded(includeAttributes: true)
            currentNoteID = id
            isDirty = false
            needsRichCommit = false

            let attributed: NSAttributedString
            if let data = attributes,
               let restored = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtfd],
                   documentAttributes: nil) {
                attributed = restored
            } else {
                attributed = NSAttributedString(
                    string: body,
                    attributes: [.font: NSFont.systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.labelColor])
            }

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(attributed)
            textView.textStorage?.endEditing()

            // 恢复保存的选区（滚动由调用方在高亮后决定）
            if let range = selection, NSMaxRange(range) <= textView.string.utf16.count {
                textView.setSelectedRange(range)
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }

            let undo = undoManagers[id] ?? UndoManager()
            undoManagers[id] = undo
            // 提高 undo 栈缓存容量（nvALT 在常用切换范围内不丢 undo）。
            if undoManagers.count > 50 {
                let oldest = undoManagers.keys.filter { $0 != id }.dropLast(49)
                oldest.forEach { undoManagers.removeValue(forKey: $0) }
            }

            if let storage = textView.textStorage {
                TextDecoratorPipeline.runAll(on: storage)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            isDirty = true
            needsRichCommit = true
            saveTask?.cancel()
            richSaveTask?.cancel()
            let snapshotID = currentNoteID
            let lightweightNanos = parent.lightweightDebounceNanos
            let idleNanos = parent.idleDebounceNanos
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: lightweightNanos)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.currentNoteID == snapshotID else { return }
                    if let storage = textView.textStorage {
                        TextDecoratorPipeline.runInteractive(on: storage)
                    }
                    self?.commitPendingIfNeeded(includeAttributes: false)
                }
            }
            richSaveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: idleNanos)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.currentNoteID == snapshotID else { return }
                    self?.commitPendingIfNeeded(includeAttributes: true)
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            commitPendingIfNeeded(includeAttributes: true)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        /// 自动保存路径：同步交付（保持原行为，时序敏感测试依赖此同步性）。
        @MainActor func commitPendingIfNeeded(includeAttributes: Bool) {
            guard isDirty || (includeAttributes && needsRichCommit),
                  let id = currentNoteID,
                  let textView = textView,
                  let storage = textView.textStorage else { return }

            let plain = storage.string
            let selection = textView.selectedRange()
            if includeAttributes {
                TextDecoratorPipeline.runAll(on: storage)
                let rtfd = try? storage.data(
                    from: NSRange(location: 0, length: storage.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                )
                parent.onRichCommit(id, plain, rtfd, selection)
                needsRichCommit = false
            } else {
                parent.onTextCommit(id, plain, selection)
            }
            isDirty = false
        }

        /// 终止/同步前的持久化路径：通过 onFlush 等待 DB 写入完成才返回
        /// （nvALT「落盘成功才继续」的等价物）。始终按富文本整体提交以保全属性。
        @MainActor func commitPendingAndWait(includeAttributes: Bool) async {
            guard isDirty || needsRichCommit,
                  let id = currentNoteID,
                  let textView = textView,
                  let storage = textView.textStorage else { return }

            let plain = storage.string
            let selection = textView.selectedRange()
            TextDecoratorPipeline.runAll(on: storage)
            let rtfd = try? storage.data(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            needsRichCommit = false
            isDirty = false
            await parent.onFlush(id, plain, rtfd, selection)
        }

        @MainActor func applyHighlight(query: String) -> NSRange {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage,
                  storage.length > 0,
                  textView.window != nil else { return NSMakeRange(NSNotFound, 0) }

            let fullRange = NSRange(location: 0, length: storage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            guard !query.isEmpty else { return NSMakeRange(NSNotFound, 0) }

            let terms = query.split(separator: " ").map(String.init)
            let highlightColor = NSColor.systemYellow.withAlphaComponent(0.4)
            let nsString = storage.string as NSString

            // 性能保护：限制最大匹配数，避免超长文档卡死
            let maxMatches = 500
            var totalMatches = 0

            // nvALT 风格：记录第一个匹配位置
            var firstMatchRange = NSMakeRange(NSNotFound, 0)

            for term in terms where !term.isEmpty {
                var searchStart = 0
                while searchStart < nsString.length && totalMatches < maxMatches {
                    let searchRange = NSRange(location: searchStart, length: nsString.length - searchStart)
                    let found = nsString.range(of: term, options: .caseInsensitive, range: searchRange)
                    if found.location == NSNotFound { break }

                    // 记录第一个匹配位置（最靠前的）
                    if firstMatchRange.location == NSNotFound || found.location < firstMatchRange.location {
                        firstMatchRange = found
                    }

                    layoutManager.addTemporaryAttribute(
                        .backgroundColor, value: highlightColor, forCharacterRange: found
                    )
                    searchStart = found.location + found.length
                    totalMatches += 1
                }
            }

            return firstMatchRange
        }
    }
}
