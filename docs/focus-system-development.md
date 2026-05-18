# NV5 焦点系统开发文档

日期：2026-05-18

## 背景

NV5 的核心价值是键盘优先的快速检索、定位和编辑。这个理念来源于 Notational Velocity / nvALT：用户不应该在“搜索”和“编辑”之间思考界面状态，输入、回车、编辑应当像同一个动作链一样连续。

当前测试暴露的问题是：在搜索框输入命中内容后按 Return，大多数情况下焦点不能稳定移动到编辑区，偶尔有效。进一步观察发现：

- 如果搜索词命中笔记正文，焦点通常能进入编辑区。
- 如果搜索词命中笔记标题，焦点更容易失败。

这说明问题不是简单的快捷键绑定失效，而是搜索结果选择、编辑器挂载/换载和焦点请求之间存在时序与语义建模问题。

## 当前焦点架构

GitNexus 当前索引显示，焦点系统的核心路径集中在：

- `FocusCoordinator`：维护全局焦点区状态。
- `NoteListColumn.searchBarReturn`：搜索框 Return 后选择笔记或创建笔记，并请求进入编辑区。
- `EditorColumn.editorView`：把 `focusCoordinator.current == .editor` 转换为 `NoteEditor` 的 `focusRequest`。
- `NoteEditor.updateNSView`：在 `focusRequest` 从 `false` 变成 `true` 时调用 `bringFocus()`。
- `NoteEditor.Coordinator.bringFocus()`：最终通过 `window.makeFirstResponder(textView)` 把 AppKit first responder 切到正文编辑器。

现有实现的关键特征：

```swift
// FocusCoordinator
public var current: FocusTarget = .searchField

public func focus(_ target: FocusTarget) {
    current = target
}

public func returnInList() {
    current = .editor
    returnInListSubject.send()
}
```

```swift
// EditorColumn
NoteEditor(
    ...
    focusRequest: focusCoordinator.current == .editor,
    ...
)
```

```swift
// NoteEditor.updateNSView
if focusRequest && !context.coordinator.lastFocusRequest {
    context.coordinator.bringFocus()
}
context.coordinator.lastFocusRequest = focusRequest
```

```swift
// NoteListColumn.searchBarReturn
if coordinator.selectedNoteID == nil {
    coordinator.selectedNoteID = notes.first?.id
}
Task { @MainActor in
    await Task.yield()
    focusCoordinator.focus(.editor)
}
```

## 真实原因

### 1. 当前焦点请求是“状态”，不是“命令”

`focusCoordinator.focus(.editor)` 只是把 `current` 设置为 `.editor`。如果当前状态已经是 `.editor`，这次调用对 SwiftUI 来说可能没有形成新的变化。

但“用户按 Return 进入编辑器”不是一个静态状态，它是一次明确命令。即使当前逻辑焦点已经是 `.editor`，也仍然应该再次尝试让当前真实的 `NSTextView` 成为 first responder。

当前 `NoteEditor` 只监听：

```swift
focusRequest == true && lastFocusRequest == false
```

这意味着只有 `false -> true` 的边沿会触发 `bringFocus()`。如果状态已经是 true，后续 Return 不会产生新的聚焦动作。

### 2. SwiftUI 焦点状态和 AppKit first responder 不是同一个东西

`focusCoordinator.current = .editor` 只是应用层意图。真正能输入文本的是 AppKit 的 `NSTextView` first responder。

因此系统里实际存在两层焦点：

- 逻辑焦点：`FocusCoordinator.current`
- 真实输入焦点：`NSWindow.firstResponder`

当前实现把二者绑定得过于隐式：逻辑焦点变化后，由 `NoteEditor.updateNSView` 在某个时机尝试执行 `makeFirstResponder`。当编辑器还在换载、窗口尚不可用，或请求没有形成新边沿时，真实输入焦点就会丢失。

### 3. 标题命中更容易失败，是因为标题命中会改变结果排序和选中笔记

搜索逻辑会同时匹配标题、正文和标签，并且标题命中通常优先排序。结果是：

- 搜索正文时，当前选中笔记更可能仍在结果中，编辑器已经挂载，`makeFirstResponder` 容易成功。
- 搜索标题时，结果排序更容易变化，当前选中笔记可能不再是第一个结果，编辑器需要切换到另一篇笔记。

而 `searchBarReturn` 当前只在 `selectedNoteID == nil` 时选择第一条结果。如果当前选中笔记不为空但不属于当前搜索结果，Return 仍可能对旧编辑器或未就绪编辑器发出焦点请求。

这就解释了“正文命中有效、标题命中失效”的差异：正文命中往往没有触发编辑器换载；标题命中更容易触发换载或结果重排，焦点请求和编辑器就绪时机错开。

### 4. `Task.yield()` 是猜时机，不是可靠协议

当前 `searchBarReturn` 里用 `Task.yield()` 试图等一帧后再聚焦：

```swift
await Task.yield()
focusCoordinator.focus(.editor)
```

这个做法只能缓解部分场景，不能保证：

- 新选中笔记已经生效。
- `EditorColumn` 已经切到新 note。
- `NoteEditor` 已经完成 `loadNote`。
- `NSTextView.window` 已经可用。

所以它会呈现“偶尔有效”的现象。

## nvALT 可借鉴的核心

nvALT 值得借鉴的不是某个快捷键本身，而是焦点哲学：

1. 搜索框是驾驶舱。
   用户从搜索框发起大多数动作，搜索、选择、创建、进入编辑是一条连续路径。

2. Return 是语义命令。
   Return 不是“把焦点状态设为 editor”，而是“打开当前搜索结果并进入编辑”。

3. 结果选择和编辑焦点必须是原子体验。
   用户按下 Return 后，系统应当先确定目标笔记，再确保目标编辑器可输入。

4. Esc / Return / 方向键构成清晰的焦点语法。
   - Return：进入当前结果或创建笔记并编辑。
   - Esc：回到搜索入口，最好支持选中搜索词。
   - Down：进入结果列表。
   - Tab / Shift+Tab：区域级循环导航。

5. 焦点恢复应该有记忆。
   模态浮层、命令面板、标签编辑等临时状态关闭后，应恢复到进入前的有效工作区，而不是只恢复一个枚举值。

## 改造原则

### 原则一：把焦点请求建模为事件

`FocusCoordinator.current` 仍然保留，用来表示当前逻辑焦点区。但进入编辑器必须增加一次性请求令牌：

```swift
public var editorFocusRequestID: Int = 0

public func requestEditorFocus() {
    current = .editor
    editorFocusRequestID &+= 1
}
```

这样每一次 Return、命令面板“聚焦编辑器”、新建笔记后进入编辑器，都会产生新的请求，即使 `current` 已经是 `.editor`。

### 原则二：搜索 Return 应先确定目标笔记

`searchBarReturn` 应将当前搜索结果作为目标集合：

```swift
let notes = filteredNotes
if coordinator.selectedNoteID == nil ||
   !notes.contains(where: { $0.id == coordinator.selectedNoteID }) {
    coordinator.selectedNoteID = notes.first?.id
}
focusCoordinator.requestEditorFocus()
```

这解决标题命中时“结果已变但选中项仍是旧值”的问题。

### 原则三：编辑器根据请求令牌聚焦，而不是布尔边沿

`EditorColumn` 应把 `editorFocusRequestID` 传入 `NoteEditor`：

```swift
focusRequestID: focusCoordinator.editorFocusRequestID
```

`NoteEditor` 应记录上一次处理过的请求 ID：

```swift
if focusRequestID != context.coordinator.lastFocusRequestID {
    context.coordinator.lastFocusRequestID = focusRequestID
    context.coordinator.bringFocus()
}
```

这使焦点请求成为幂等但可重复的命令流。

### 原则四：编辑器就绪后再完成真实聚焦

`bringFocus()` 不应该只赌一次 `Task.yield()`。更可靠的方式是短暂重试，直到 `textView.window` 可用：

```swift
Task { @MainActor in
    for _ in 0..<3 {
        await Task.yield()
        guard let window = textView.window else { continue }
        if window.firstResponder != textView {
            window.makeFirstResponder(textView)
        }
        return
    }
}
```

后续如果要进一步提高确定性，可以让 `NoteEditor` 在完成 `loadNote` 后主动确认 pending focus request。

## 建议实现步骤

### 第一步：引入编辑器焦点请求令牌

修改 `FocusCoordinator`：

- 新增 `editorFocusRequestID`。
- 新增 `requestEditorFocus()`。
- 将 `returnInList()` 内部改为调用 `requestEditorFocus()`，再发送 `returnInListSubject`。

影响范围高，因为 `FocusCoordinator` 是全局焦点核心。修改前必须运行 GitNexus impact analysis。

### 第二步：修正搜索 Return 的目标笔记选择

修改 `NoteListColumn.searchBarReturn`：

- 如果搜索结果为空且查询不为空，继续创建新笔记。
- 如果搜索结果不为空，确保 `selectedNoteID` 属于当前 filtered results。
- 然后调用 `focusCoordinator.requestEditorFocus()`。
- 移除 `Task.yield()` 作为主要聚焦机制。

这一步直接修复“标题命中导致选中项和编辑器目标错位”的问题。

### 第三步：让编辑器消费请求令牌

修改 `EditorColumn.editorView` 和 `NoteEditor`：

- `EditorColumn` 传入 `focusRequestID`。
- `NoteEditor.Coordinator` 保存 `lastFocusRequestID`。
- `updateNSView` 在请求 ID 变化时调用 `bringFocus()`。
- `bringFocus()` 增加窗口可用性重试。

这一步修复“逻辑状态已经是 editor 时再次 Return 不触发聚焦”的问题。

### 第四步：统一所有进入编辑器的入口

以下入口都应逐步从 `focus(.editor)` 迁移到 `requestEditorFocus()`：

- 搜索框 Return。
- 列表 Return。
- 新建笔记。
- 用搜索词新建笔记。
- URL 新建笔记。
- 命令面板中的“聚焦编辑器”。
- 菜单或快捷键中的“聚焦编辑器”。

统一入口后，项目中“进入编辑器”只有一个语义命令，后续维护会简单很多。

## 回归测试清单

### 搜索到正文

1. 搜索一个只在正文里出现的词。
2. 按 Return。
3. 期望：焦点进入正文编辑器，可以立即输入。

### 搜索到标题

1. 搜索一个只在标题里出现的词。
2. 确认结果列表发生变化或排序变化。
3. 按 Return。
4. 期望：选中第一条匹配结果，焦点进入该笔记正文编辑器，可以立即输入。

### 当前逻辑焦点已是 editor

1. 让 `FocusCoordinator.current` 已经处于 `.editor`。
2. 点击或快捷键回到搜索框输入新查询。
3. 按 Return。
4. 期望：即使 `current` 之前已经是 `.editor`，仍然产生新的编辑器聚焦请求。

### 新建笔记

1. 输入不存在的搜索词。
2. 按 Return。
3. 期望：创建新笔记，标题为搜索词，焦点进入正文编辑器。

### 列表 Return

1. 焦点位于笔记列表。
2. 按 Return。
3. 期望：焦点进入编辑器，光标移动到正文末尾。

### 模态恢复

1. 从编辑器打开命令面板或其他浮层。
2. 关闭浮层。
3. 期望：恢复到进入浮层前的真实输入位置。

## 后续架构方向

中期可以把 `FocusCoordinator` 从“枚举状态管理器”升级为“焦点仲裁器”：

```swift
enterSearch(selectAll: Bool)
enterResults(selectionPolicy: SelectionPolicy)
enterEditor(noteID: UUID?, placement: CursorPlacement)
restoreAfterModal()
```

这里的重点是语义化：

- `enterSearch` 表示回到搜索入口。
- `enterResults` 表示浏览结果。
- `enterEditor` 表示进入某篇笔记的可编辑正文。
- `restoreAfterModal` 表示从临时界面恢复工作状态。

最终目标不是让某个枚举值正确，而是让用户按键后的真实输入位置正确。这一点也是 NV5 能否接近 nvALT 手感的关键。
