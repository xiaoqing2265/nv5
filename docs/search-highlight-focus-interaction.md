# 检索、高亮、焦点三者的交互关系研究

## 问题背景

用户观察到：
1. 搜索"生命"时，有时高亮显示，有时不显示
2. 搜索"生"时，反而能高亮显示
3. 焦点转移有时失败，尤其是标题命中的场景

**假设**：这三个系统之间存在时序依赖和状态耦合。

---

## 系统架构

### 1. 检索系统（Search）

**入口**：`NoteStore.search(query:)`

**流程**：
```
用户输入 query
  ↓
coordinator.query 变化
  ↓
filteredNotes 重新计算（computed property）
  ↓
NoteStore.search(query) 执行
  ↓
内存遍历 + String.range(of:) 匹配
  ↓
返回匹配结果（标题命中优先排序）
```

**关键点**：
- 搜索是**同步**的（在 `filteredNotes` 的 getter 中执行）
- 结果包含"标题命中"和"正文命中"，但不区分
- 排序规则：标题命中 > 修改时间

### 2. 高亮系统（Highlight）

**入口**：`NoteEditor.Coordinator.applyHighlight(query:)`

**流程**：
```
updateNSView 被调用
  ↓
applyHighlight(query: highlightQuery) 执行
  ↓
检查缓存：query == lastHighlightQuery?
  ├─ 是 → 直接返回（跳过高亮）
  └─ 否 → 继续
  ↓
遍历 textStorage.string，查找所有匹配
  ↓
layoutManager.addTemporaryAttribute(.backgroundColor, ...)
```

**关键点**：
- 高亮是**异步**的（在 `updateNSView` 中调用，但 `loadNote` 在 `DispatchQueue.main.async` 中）
- 只高亮**正文**，不高亮标题
- 有缓存机制（`lastHighlightQuery`）

### 3. 焦点系统（Focus）

**入口**：`MainWindowController.shared.focusEditor()`

**流程**：
```
NVSearchBar.control(_:textView:doCommandBy:) 捕获 Return
  ↓
onSubmit() → searchBarReturn()
  ↓
MainWindowController.shared.requestFocusAfterLoad()
  ↓
MainWindowController.shared.focusEditor()
  ↓
window.makeFirstResponder(textView)
```

**关键点**：
- 焦点转移是**同步**的（直接调用 AppKit API）
- 但如果笔记切换，`loadNote` 会调用 `makeFirstResponder(nil)` 清空焦点
- `pendingFocusAfterLoad` 机制在 `loadNote` 完成后重新聚焦

---

## 时序分析：搜索 → Return 的完整流程

### 场景 A：搜索"生命"，标题命中（正文不含）

```
T0: 用户输入"生命"
  ├─ coordinator.query = "生命"
  ├─ filteredNotes 重新计算
  │  └─ NoteStore.search("生命") 返回 [笔记A（标题含）, 笔记B（正文含）]
  └─ 列表显示笔记A（标题命中优先）

T1: 用户按 Return
  ├─ NVSearchBar.control 捕获
  ├─ searchBarReturn() 执行
  │  ├─ selectedNoteID = 笔记A.id
  │  └─ focusCoordinator.focus(.editor)
  ├─ MainWindowController.shared.requestFocusAfterLoad()
  │  └─ pendingFocusAfterLoad = true
  └─ MainWindowController.shared.focusEditor()
     └─ window.makeFirstResponder(textView) ← 可能成功（如果 textView 已存在）

T2: SwiftUI 重渲染（selectedNoteID 变化）
  └─ NoteEditor.updateNSView 被调用
     ├─ currentNoteID != noteID → 进入笔记切换分支
     ├─ makeFirstResponder(nil) ← 清空焦点！
     ├─ DispatchQueue.main.async { loadNote(笔记A) } ← 调度
     └─ applyHighlight(query: "生命") ← 在旧内容上执行
        └─ lastHighlightQuery = "生命"

T3: loadNote(笔记A) 执行
  ├─ textStorage.setAttributedString(笔记A的内容)
  ├─ lastHighlightQuery = "" ← 重置缓存（修复后）
  └─ applyHighlight(query: "生命") ← 重新应用（修复后）
     ├─ 在笔记A的正文中搜索"生命"
     └─ 未找到 → 无高亮 ✓（符合预期）

T4: 焦点重新聚焦
  └─ if pendingFocusAfterLoad { focusEditor() }
     └─ window.makeFirstResponder(textView) ✓
```

**结果**：
- ✓ 焦点进入编辑器
- ✓ 正文无高亮（因为"生命"只在标题中）
- ✓ 用户体验一致

### 场景 B：搜索"生命"，正文命中

```
T0: 用户输入"生命"
  └─ filteredNotes 返回 [笔记B（正文含）, ...]

T1: 用户按 Return
  └─ selectedNoteID = 笔记B.id

T2: SwiftUI 重渲染
  └─ NoteEditor.updateNSView
     └─ DispatchQueue.main.async { loadNote(笔记B) }

T3: loadNote(笔记B) 执行
  ├─ textStorage.setAttributedString(笔记B的内容)
  ├─ lastHighlightQuery = ""
  └─ applyHighlight(query: "生命")
     ├─ 在笔记B的正文中搜索"生命"
     └─ 找到 → 高亮显示 ✓

T4: 焦点重新聚焦
  └─ focusEditor() ✓
```

**结果**：
- ✓ 焦点进入编辑器
- ✓ 正文高亮"生命"
- ✓ 用户体验一致

### 场景 C：搜索"生"，部分匹配

```
T0: 用户输入"生"
  └─ filteredNotes 返回所有包含"生"的笔记
     （可能在标题、正文、标签中）

T1: 用户按 Return
  └─ selectedNoteID = 第一条笔记.id

T2-T4: 同上

T3: applyHighlight(query: "生")
  ├─ 在正文中搜索"生"
  └─ 找到所有包含"生"的位置（包括"生命"中的"生"）
     └─ 高亮显示 ✓
```

**结果**：
- ✓ 焦点进入编辑器
- ✓ 正文高亮所有"生"（包括"生命"中的"生"）
- ✓ 用户体验一致

---

## 潜在的交互问题

### 问题 1：高亮和焦点的时序竞态

**场景**：笔记切换时，高亮和焦点都需要在 `loadNote` 完成后执行。

**当前实现**：
```swift
DispatchQueue.main.async {
    loadNote(...)
    applyHighlight(query: highlightQuery)  // ← 高亮
    if pendingFocusAfterLoad {
        focusEditor()  // ← 焦点
    }
}
```

**问题**：`applyHighlight` 和 `focusEditor` 的顺序是否会影响结果？

**测试**：
- [ ] 高亮 → 焦点（当前顺序）
- [ ] 焦点 → 高亮（反向顺序）
- [ ] 观察是否有差异

### 问题 2：搜索结果排序和用户期望不一致

**场景**：用户搜索"生命"，期望看到正文中有"生命"的笔记，但第一条结果是标题命中（正文不含）。

**当前实现**：
```swift
// NoteStore.swift:195-204
return matched.sorted { lhs, rhs in
    let lhsTitleHit = tokens.allSatisfy {
        lhs.title.range(of: $0, options: .caseInsensitive) != nil
    }
    let rhsTitleHit = tokens.allSatisfy {
        rhs.title.range(of: $0, options: .caseInsensitive) != nil
    }
    if lhsTitleHit != rhsTitleHit { return lhsTitleHit }  // 标题命中优先
    return lhs.modifiedAt > rhs.modifiedAt
}
```

**问题**：标题命中优先是否合理？

**可能的改进**：
- 选项 A：标题命中和正文命中分组显示
- 选项 B：标题+正文都命中 > 标题命中 > 正文命中
- 选项 C：根据匹配位置（开头 vs 中间）排序

### 问题 3：高亮只在正文，不在标题

**场景**：搜索"生命"，笔记标题是"生命的意义"，但标题不高亮。

**当前实现**：`applyHighlight` 只搜索 `textStorage.string`（正文），不搜索标题。

**问题**：用户可能期望标题也高亮。

**可能的改进**：
- 在 `TitleBar` 中也实现高亮逻辑
- 或者在搜索结果列表中高亮标题

### 问题 4：`handleNotesChange` 的重复焦点请求

**场景**：新建笔记时，GRDB 异步推送触发 `handleNotesChange`，再次调用 `focusCoordinator.focus(.editor)`。

**当前实现**：
```swift
// NoteListColumn.swift:293
focusCoordinator.focus(.editor)
MainWindowController.shared.focusEditor()  // ← 兜底
```

**问题**：这两个焦点请求是否会冲突？

**测试**：
- [ ] 新建笔记 → 观察焦点是否稳定
- [ ] 检查是否有多次 `makeFirstResponder` 调用

---

## 测试计划

### 基础测试

1. **搜索正文命中 → Return**
   - 输入："生命"
   - 笔记：正文含"生命是一场旅程"
   - 预期：焦点进入编辑器，"生命"高亮

2. **搜索标题命中 → Return**
   - 输入："生命"
   - 笔记：标题"生命的意义"，正文不含"生命"
   - 预期：焦点进入编辑器，正文无高亮

3. **搜索部分匹配 → Return**
   - 输入："生"
   - 笔记：正文含"生命"
   - 预期：焦点进入编辑器，"生"高亮（包括"生命"中的"生"）

### 边界测试

4. **快速连续 Return**
   - 输入："生命"
   - 快速按两次 Return
   - 预期：焦点稳定，不闪烁

5. **搜索 → 切换笔记 → Return**
   - 输入："生命"
   - 用鼠标点击列表中的另一条笔记
   - 再按 Return
   - 预期：焦点进入编辑器，高亮正确

6. **搜索 → 修改搜索词 → Return**
   - 输入："生命"
   - 修改为"生"
   - 按 Return
   - 预期：焦点进入编辑器，高亮更新为"生"

7. **新建笔记 → 焦点**
   - 输入："不存在的词"
   - 按 Return（创建新笔记）
   - 预期：焦点进入编辑器，无高亮

### 性能测试

8. **大量笔记场景**
   - 创建 1000 条笔记
   - 搜索常见词（如"的"）
   - 按 Return
   - 预期：响应时间 < 100ms

9. **长正文场景**
   - 创建一条 10000 字的笔记
   - 搜索出现 100 次的词
   - 按 Return
   - 预期：高亮渲染时间 < 200ms

---

## 下一步行动

1. **运行基础测试** — 验证修复是否生效
2. **运行边界测试** — 发现潜在的交互问题
3. **性能测试** — 确保大规模场景下仍然流畅
4. **用户反馈** — 收集真实使用场景中的问题

---

## 已知问题和待改进

- [ ] 高亮只在正文，不在标题
- [ ] 搜索结果排序可能不符合用户期望
- [ ] `handleNotesChange` 的重复焦点请求
- [ ] 高亮和焦点的时序是否最优

---

## 修复历史

### 2024-XX-XX：修复高亮缓存 Bug
- **问题**：笔记切换时，`lastHighlightQuery` 缓存导致高亮不更新
- **修复**：在 `loadNote` 结束时重置 `lastHighlightQuery = ""`，并在 `updateNSView` 的异步块中重新调用 `applyHighlight`
- **影响**：高亮现在在笔记切换后正确更新

### 2024-XX-XX：引入 nvALT 风格焦点架构
- **问题**：SwiftUI 焦点系统的多层异步导致焦点丢失
- **修复**：创建 `MainWindowController` 作为焦点中心，直接调用 `window.makeFirstResponder(textView)`
- **影响**：焦点转移更稳定，时序更可预测
