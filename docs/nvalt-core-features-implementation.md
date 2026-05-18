# nvALT 核心功能实现总结

## 背景

通过深入分析 nvALT 源码（~8000 行 Objective-C），识别出 nvALT 作为生产力工具而非玩具的核心差异。本次实施将这些核心理念移植到 NV5。

---

## 实施的功能

### P0 - 核心体验（必须有）

#### 1. 标题自动补全 ✅

**nvALT 的实现**：
```objc
// NotationController.m:1337-1362
if (noteTitleHasPrefixOfUTF8String(notesBuffer[i], searchString, newLen)) {
    selectedNoteIndex = i;
    // 找到最短的前缀父节点...
}

// AppController.m:1010-1022
NSString *remainingTitle = [titleOfNote(currentNote) substringFromIndex:typingRange.location];
[fieldEditor replaceCharactersInRange:typingRange withString:remainingTitle];
[fieldEditor setSelectedRange:typingRange]; // 补全部分被选中
```

**NV5 的实现**：
- `NoteStore.noteTitlePrefixedBy()`: 查找标题前缀，返回最短匹配
- `NVSearchBar.controlTextDidChange()`: 检测输入（非删除），插入补全，选中补全部分

**用户体验**：
- 输入"生" → 自动补全"生命的意义"（补全部分被选中）
- 继续输入覆盖补全，或按 Return 直接打开
- **不需要精确记住笔记标题，只需开头几个字**

---

#### 2. 列表任意键转发到搜索框 ✅

**nvALT 的实现**：
```objc
// NotesTableView.m:870-877
if ([win firstResponder] == self) {
    [win makeFirstResponder:controlField];
    NSTextView *fieldEditor = (NSTextView*)[controlField currentEditor];
    [fieldEditor keyDown:theEvent];
}
```

**NV5 的实现**：
- `NoteListColumn.onAnyKey()`: 捕获可打印字符
- `MainWindowController.focusSearchField()`: 直接转移焦点
- `.onKeyPress(action:)`: SwiftUI 键盘处理

**用户体验**：
- 在列表中按任意字母/数字/标点 → 立即回到搜索框
- **永远不会"卡"在列表里**
- 键盘流畅，无需手动点击搜索框

---

### P1 - 体验完整性

#### 3. 高亮后光标落在第一个匹配位置 ✅

**nvALT 的实现**：
```objc
// AppController.m:1232-1242
firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString ...];
if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
    noteSelectionRange = firstFoundTermRange;
[textView setAutomaticallySelectedRange:noteSelectionRange];
```

**NV5 的实现**：
- `applyHighlight()` 返回 `NSRange`（第一个匹配位置）
- 笔记切换时：如果没有保存的选区，使用第一个匹配
- query 变化时：跳转到第一个匹配

**用户体验**：
- 搜索"生命" → 编辑器自动跳到正文中第一个"生命"
- **光标落在那里，不只是滚动**
- 不需要手动查找匹配位置

---

#### 4. 应用切换时立即保存 ✅

**nvALT 的实现**：
```objc
// AppController.m:793-796
- (void)applicationWillResignActive:(NSNotification *)aNotification {
    [notationController synchronizeNoteChanges:nil];
}
```

**NV5 的实现**：
- `NoteEditor.Coordinator.setupAppSwitchObserver()`: 监听 `NSApplication.willResignActiveNotification`
- 立即调用 `commitPendingIfNeeded()`

**用户体验**：
- 切换到其他应用 → 当前笔记立即保存
- **不依赖 300ms 防抖定时器**
- 不会因为切换应用太快而丢失内容

---

## 核心设计理念

这四个功能共同实现了 nvALT 的核心哲学：

### 1. 搜索即创建（Search-or-Create）
- 一个入口，无认知负担
- 没有"新建笔记"按钮，没有模态对话框
- 用户意图只有一个：**找到或创建**

### 2. 标题前缀驱动导航
- 不需要精确记住笔记标题
- 只需记住开头几个字
- 自动补全 + 自动选中 = 零摩擦导航

### 3. 键盘优先流
- 任意键回到搜索
- 永不卡住
- 鼠标是可选的，不是必需的

### 4. 高亮驱动选区
- 高亮不是装饰，是导航
- 第一个匹配自动选中
- 光标落在那里，立即可编辑

---

## 技术实现细节

### 代码统计
```
4 files changed, 87 insertions(+), 12 deletions(-)

NoteStore.swift:        +14 行（标题前缀查找）
NVSearchBar.swift:      +25 行（自动补全逻辑）
NoteEditor.swift:       +27 行（光标跳转 + 应用切换保存）
NoteListColumn.swift:   +21 行（键盘转发）
```

### 关键方法

**NoteStore.swift**
```swift
public func noteTitlePrefixedBy(_ prefix: String) -> String? {
    let matches = notes.filter { note in
        note.title.lowercased().hasPrefix(prefix.lowercased())
    }
    return matches.min(by: { $0.title.count < $1.title.count })?.title
}
```

**NVSearchBar.swift**
```swift
func controlTextDidChange(_ obj: Notification) {
    let newText = field.stringValue
    let oldText = parent.text
    
    // 只在用户输入（不是删除）时触发
    if newText.count > oldText.count, !newText.isEmpty {
        if let matchedTitle = parent.store.noteTitlePrefixedBy(newText) {
            let remaining = String(matchedTitle.dropFirst(cursorPos))
            fieldEditor.insertText(remaining, ...)
            fieldEditor.setSelectedRange(...)  // 选中补全部分
        }
    }
}
```

**NoteListColumn.swift**
```swift
private func onAnyKey(_ event: KeyPress) -> KeyPress.Result {
    guard let char = event.characters.first,
          char.isLetter || char.isNumber || char.isPunctuation else {
        return .ignored
    }
    
    coordinator.query = String(char)
    MainWindowController.shared.focusSearchField()
    return .handled
}
```

**NoteEditor.swift**
```swift
func setupAppSwitchObserver() {
    appSwitchObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willResignActiveNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.commitPendingIfNeeded()
    }
}
```

---

## 与 nvALT 的对比

| 维度 | nvALT | NV5（修复前） | NV5（修复后） |
|---|---|---|---|
| **标题自动补全** | ✅ 有，驱动导航 | ❌ 无 | ✅ 有 |
| **任意键→搜索** | ✅ 有，永不卡住 | ❌ 无 | ✅ 有 |
| **高亮驱动光标** | ✅ 有，跳到第一个匹配 | ⚠️ 部分（只滚动） | ✅ 有 |
| **应用切换保存** | ✅ 立即同步 | ⚠️ 300ms 防抖 | ✅ 立即保存 |
| **增量搜索** | ✅ C 字符串优化 | ❌ 全量扫描 | ❌ 全量扫描（P2） |
| **同步执行** | ✅ 全链路同步 | ❌ 多层异步 | ✅ 已优化 |

---

## 用户体验提升

### 修复前
1. 搜索"生" → 没有任何提示，需要完整输入标题
2. 在列表中按"工" → 没有反应，需要手动点击搜索框
3. 搜索"生命" → 高亮显示，但光标在文档开头，需要手动滚动查找
4. 切换应用 → 可能丢失最后 300ms 内的编辑

### 修复后
1. 搜索"生" → 自动补全"生命的意义"，按 Return 打开
2. 在列表中按"工" → 立即回到搜索框，开始搜索"工"
3. 搜索"生命" → 光标自动跳到第一个"生命"，立即可编辑
4. 切换应用 → 立即保存，不会丢失任何内容

---

## 下一步优化（P2 - 可选）

### 增量搜索
**问题**：当前每次输入都全量扫描所有笔记，大量笔记时可能变慢

**nvALT 的做法**：
```objc
// NotationController.m:1264-1278
if (strncmp(currentFilterStr, searchString, oldLen)) {
    // 新词不是旧词的前缀，重新从所有笔记开始
    [notesListDataSource fillArrayFromArray:allNotes];
} else {
    // 在当前结果中继续搜索（结果集更小）
    filterContext.useCachedPositions = YES;
}
```

**实现难度**：中等（需要重构 `NoteStore.search`）

**优先级**：低（除非用户有大量笔记且感觉到搜索变慢）

---

## 总结

通过实施这四个核心功能，NV5 从"有搜索功能的笔记应用"升级为"以搜索为中心的笔记应用"。

**核心差异**：
- **玩具**：功能齐全，但交互有摩擦，需要思考"我要做什么"
- **生产力工具**：交互流畅，无需思考，手指比大脑快

**nvALT 的成功秘诀**：
1. 消除认知负担（搜索即创建）
2. 消除记忆负担（标题前缀补全）
3. 消除导航负担（任意键回搜索）
4. 消除查找负担（高亮驱动光标）

这些理念现在已经完整移植到 NV5。

---

## 参考资料

- [nvALT 源码分析](./nvalt-lessons-learned.md)
- [搜索/高亮/焦点交互分析](./search-highlight-focus-interaction.md)
- [焦点系统开发记录](./focus-system-development.md)

---

**实施日期**：2026-05-18  
**提交记录**：
- `b78f824` - fix: rewrite search/highlight/focus based on nvALT architecture
- `[current]` - feat: implement nvALT core productivity features (P0/P1)
