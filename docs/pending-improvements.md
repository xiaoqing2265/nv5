# NV5 待完善开发文档

基于代码审计报告，本文档列出仍需完善的四个方向，按优先级排序。
每个任务包含：问题根因、验收标准、逐步实施指南、可直接使用的代码片段。

---

## ✅ 任务一：AppCoordinator 文件拆分（编译隔离）

### 问题根因

`AppCoordinator`（300+ 行）与 App 入口 `NV5App` 定义在同一文件 `App/NV5App.swift`（14.7 KB）。
项目中几乎所有文件都 import 了这个模块，导致每次修改 `AppCoordinator` 都触发全项目重编译。

### 验收标准

- `App/NV5App.swift` 只保留 `NV5App` struct 和 `KeyboardShortcuts.Name` extension，行数 ≤ 100 行
- `AppCoordinator` 移入独立文件 `App/AppCoordinator.swift`
- 构建通过，行为不变

### 实施步骤

**Step 1**：新建 `App/AppCoordinator.swift`，将 `AppCoordinator` 类定义完整移入。

文件头部：

```swift
import SwiftUI
import KeyboardShortcuts
import NVStore
import NVSync
import NVModel
import NVCrypto
import NVExport
```

移入内容：`AppCoordinator` 类的全部定义（从 `@MainActor @Observable public final class AppCoordinator` 到对应的闭合括号）。

**Step 2**：`App/NV5App.swift` 删除 `AppCoordinator` 类定义后，只保留：

```swift
import SwiftUI
import KeyboardShortcuts
import Sparkle

extension KeyboardShortcuts.Name {
    static let activateNV5 = Self("activateNV5", default: .init(.space, modifiers: [.command, .control]))
}

@main
struct NV5App: App {
    // ... 保持不变
}
```

**Step 3**：构建验证。

```bash
xcodebuild -scheme NV5App -destination 'platform=macOS' build
```

### 注意事项

- `AppCoordinator` 标注了 `public`，移到新文件后 `public` 可以去掉（同模块内不需要）
- `NV5App.swift` 中的 `import` 按需精简，只保留 `NV5App` struct 实际用到的

---

## ✅ 任务二：AppCoordinator 剩余职责拆分（NavigationCoordinator）

### 问题根因

完成任务一后，`AppCoordinator` 仍然混合了两类职责：

| 职责 | 当前位置 | 应该在哪 |
|---|---|---|
| 笔记 CRUD / 导出 | → `NoteActionManager` ✅ 已拆 | |
| 多选 / 范围选择 | → `SelectionManager` ✅ 已拆 | |
| 导航历史（前进/后退） | `AppCoordinator` | `NavigationCoordinator` |
| 搜索状态（query / typedQuery） | `AppCoordinator` | 可保留，与 UI 强耦合 |
| 同步配置 | `AppCoordinator` | 可保留，启动时一次性 |

导航历史逻辑（`previousNoteID`、`goBack`、`goForward`、`switchToPreviousNote`）与笔记选择逻辑耦合较少，适合独立。

### 验收标准

- 新建 `App/Navigation/NavigationCoordinator.swift`
- `AppCoordinator` 中的导航相关属性和方法委托给 `NavigationCoordinator`
- `NavigationHistory` 由 `NavigationCoordinator` 持有，不再直接暴露给 `AppCoordinator`
- 构建通过，前进/后退导航行为不变

### 实施步骤

**Step 1**：新建 `App/Navigation/NavigationCoordinator.swift`：

```swift
import Foundation
import NVModel

/// 笔记导航历史：前进、后退、上一条。
/// 不持有 observable 状态，通过返回值驱动 AppCoordinator 更新 selectedNoteID。
@MainActor
final class NavigationCoordinator {
    private let history = NavigationHistory()
    private(set) var previousNoteID: UUID?

    func didSelect(_ noteID: UUID, previous: UUID?) {
        previousNoteID = previous
        history.record(noteID)
    }

    /// 返回应该跳转到的 noteID，nil 表示无法后退
    func goBack() -> UUID? {
        history.goBack()
    }

    /// 返回应该跳转到的 noteID，nil 表示无法前进
    func goForward() -> UUID? {
        history.goForward()
    }

    /// 返回上一条笔记的 ID（用于 BackToPrevious 命令）
    func previousNote(existingIn notes: [Note], archived: [Note]) -> UUID? {
        guard let prev = previousNoteID else { return nil }
        let exists = notes.contains(where: { $0.id == prev })
            || archived.contains(where: { $0.id == prev })
        return exists ? prev : nil
    }
}
```

**Step 2**：在 `AppCoordinator` 中替换：

```swift
// 删除
let navigationHistory = NavigationHistory()
var previousNoteID: UUID?

// 新增
private(set) var navigation = NavigationCoordinator()

// selectedNoteID.didSet 改为
var selectedNoteID: UUID? {
    didSet {
        navigation.didSelect(selectedNoteID ?? oldValue!, previous: oldValue)
    }
}
```

**Step 3**：更新调用方（`BuiltinCommands.swift` 中的 `NavigateBackCommand`、`NavigateForwardCommand`、`BackToPreviousCommand`）：

```swift
// 原来
coordinator.navigationHistory.goBack()
coordinator.previousNoteID

// 改为
coordinator.navigation.goBack()
coordinator.navigation.previousNote(existingIn: store.notes, archived: store.archivedNotes)
```

**Step 4**：删除 `AppCoordinator` 中的 `switchToPreviousNote()`，调用方改为直接使用 `navigation.previousNote(...)`。

---

## ✅ 任务三：写入失败错误上浮

### 问题根因

`EditorColumn` 和 `TitleBar` 中的写入失败只打印日志，不通知用户，可能导致数据静默丢失：

```swift
// EditorColumn.swift:63
print("[NV5] Failed to save note body (id=\(id)): \(error)")

// EditorColumn.swift:117
print("[NV5] Failed to save label removal (id=\(note.id)): \(error)")

// EditorColumn.swift:153
print("[NV5] Failed to update title (id=\(note.id)): \(error)")

// EditorColumn.swift:167
print("[NV5] Failed to add label (id=\(note.id)): \(error)")
```

正文 body 的保存失败尤其危险——用户编辑了内容，切换笔记，内容丢失，没有任何提示。

### 验收标准

- 上述四处失败场景，用户能看到错误提示（Toast 或 Alert）
- 正文保存失败时，提示信息明确（"笔记内容保存失败"）
- 标题/标签操作失败时，提示信息明确
- 不引入新的全局状态，通过现有 `AppCoordinator.showError()` 路由

### 实施步骤

**Step 1**：确认 `AppCoordinator.showError()` 的签名（当前在 `NV5App.swift` 中）：

```swift
func showError(_ error: Error) { ... }
```

**Step 2**：`EditorColumn` 已经通过 `@Environment(AppCoordinator.self)` 持有 coordinator，直接使用：

```swift
// EditorColumn.swift — onCommit 闭包
onCommit: { [coordinator] id, body, attrs, range in
    Task {
        do {
            try await store.updateBody(id: id, body: body, attributes: attrs, selection: range)
        } catch {
            coordinator.showError(error)
        }
    }
}
```

注意：`onCommit` 是一个逃逸闭包，需要显式捕获 `coordinator`（`[coordinator]`），否则在 SwiftUI 的 `@Observable` 环境下可能捕获到旧值。

**Step 3**：`TitleBar` 同理，四处 `print` 全部替换：

```swift
// commitTitle()
} catch {
    coordinator.showError(error)
}

// addLabel()
} catch {
    coordinator.showError(error)
}

// removeLabel（LabelChip 的 removable 闭包）
} catch {
    coordinator.showError(error)
}
```

**Step 4**：确认 `showError` 的实现能在主线程弹出提示。如果当前实现是 `NSAlert.runModal()`，需要确保调用在 `@MainActor` 上：

```swift
// AppCoordinator.swift
func showError(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "操作失败"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "确定")
    alert.runModal()
}
```

如果希望更轻量（不阻塞），可以改为 `OverlayManager` 的 Toast，但这需要先确认 `OverlayManager` 是否支持 Toast 类型。

### 边界情况

- **正文保存失败**：这是最高优先级。`updateBody` 在用户停止输入 300ms 后触发，失败时用户可能已经切换到其他笔记。提示应该包含笔记标题，方便用户定位。
- **标题更新失败**：400ms 防抖后触发，失败时 UI 上的标题已经显示为新值，但数据库没有更新。提示后应该将 `title` 状态回滚到 `note.title`。

标题回滚示例：

```swift
private func commitTitle() {
    guard title != note.title else { return }
    Task {
        do {
            try await store.updateTitle(id: note.id, title: title)
        } catch {
            coordinator.showError(error)
            title = note.title  // 回滚 UI 状态
        }
    }
}
```

---

## ✅ 任务四：ExportService 职责清理

### 问题根因

`ExportService` 目前混合了两类职责：

1. **路由**：根据 `ExportFormat` 分发到对应 Converter（`render` 方法）
2. **业务逻辑**：`exportMergedFile` 中包含合并逻辑（字符串拼接、`---` 分隔符）

`exportMergedFile` 的合并逻辑属于业务规则，不属于"服务"层，且目前没有被任何调用方使用（可能是遗留代码）。

另外，`ExportService` 标注了 `@MainActor`，但其核心操作（文件写入、格式转换）都是 CPU/IO 密集型，不需要主线程。

### 验收标准

- 确认 `exportMergedFile` 是否有调用方；如果没有，删除
- `ExportService` 去掉 `@MainActor`，改为 `Sendable`
- `render` 方法提取为 `package` 或 `internal` 可见性，方便测试
- 构建通过，现有导出功能不变

### 实施步骤

**Step 1**：确认 `exportMergedFile` 的调用方：

```bash
grep -rn "exportMergedFile" /path/to/nv5 --include="*.swift"
```

如果无调用方，直接删除该方法。

**Step 2**：去掉 `@MainActor`，改为 `Sendable`：

```swift
// 修改前
@MainActor
public final class ExportService {

// 修改后
public final class ExportService: @unchecked Sendable {
```

注意：`ExportService` 内部没有可变状态（`init()` 是空的），`@unchecked Sendable` 是安全的。

**Step 3**：`render` 方法改为 `internal`（去掉 `private`），方便单元测试直接调用：

```swift
// 修改前
private func render(note: Note, as format: ExportFormat) throws -> ExportContent {

// 修改后
func render(note: Note, as format: ExportFormat) throws -> ExportContent {
```

**Step 4**：`NoteActionManager` 中创建 `ExportService` 的地方不需要 `MainActor.run`：

```swift
// 修改前（NV5Intents.swift）
let service = await MainActor.run { ExportService() }

// 修改后
let service = ExportService()
```

**Step 5**：为 `render` 方法补充单元测试（放在 `NVExportTests`）：

```swift
// RichTextConverterTests.swift 或新建 ExportServiceTests.swift
func test_render_markdown_returns_text() throws {
    let note = Note(title: "Hello", body: "World")
    let service = ExportService()
    let content = try service.render(note: note, as: .markdown)
    guard case .text(let s) = content else {
        XCTFail("Expected .text")
        return
    }
    XCTAssertTrue(s.contains("Hello"))
    XCTAssertTrue(s.contains("World"))
}
```

---

## 优先级总结

| 任务 | 影响 | 难度 | 建议顺序 |
|---|---|---|---|
| 一：AppCoordinator 文件拆分 | 编译速度 | 低（纯移动） | 第 1 个 |
| 三：写入失败错误上浮 | 数据安全 | 低 | 第 2 个 |
| 二：NavigationCoordinator | 代码清晰度 | 中 | 第 3 个 |
| 四：ExportService 清理 | 可测试性 | 低 | 第 4 个 |

任务一和任务三可以并行开发，互不依赖。
任务二依赖任务一完成后（AppCoordinator 在独立文件中更容易操作）。
任务四完全独立，随时可做。

---

## 已完成项（供参考，无需重复开发）

| 项目 | 完成状态 |
|---|---|---|
| NoteStore 缓存失效修复（count-based） | ✅ |
| Intents 层 NoteRepository 协议隔离 | ✅ |
| NoteActionManager 拆分 | ✅ |
| SelectionManager 拆分 | ✅ |
| NoteStoreSearchTests（search + noteTitlePrefixedBy） | ✅ |
| MainWindowController 多窗口断言 | ✅ |
| typedQuery / query 分离（高亮 bug 修复） | ✅ |
| 增量搜索（P2） | ✅ |
| AppCoordinator 文件拆分（任务一） | ✅ |
| NavigationCoordinator 提取（任务二） | ✅ |
| 写入失败错误上浮 + 标题回滚（任务三） | ✅ |
| ExportService 清理 + 单元测试（任务四） | ✅ |
