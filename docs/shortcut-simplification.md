# 快捷键系统简化方案

## 问题根因

NV5 当前使用 `KeyboardShortcuts` 库通过 `NSEvent.addLocalMonitorForEvents(matching: .keyUp)`
注册全局事件监听器。这与 nvALT 的设计哲学完全相反：

| | nvALT | NV5 现状 |
|---|---|---|
| 快捷键机制 | macOS 菜单系统（响应链） | `KeyboardShortcuts.onKeyUp` 全局监听 |
| 触发时机 | `keyDown`（响应链） | `keyUp`（全局监听，晚于响应链） |
| 焦点感知 | 自动（菜单项禁用时快捷键失效） | 无感知（任何状态下都触发） |
| 可维护性 | 系统保证，无竞争 | 手动管理，存在时序竞争 |

**直接后果**：Return 键在搜索框触发后，焦点已经通过响应链（`keyDown`）转移到编辑器，
但 `keyUp` 阶段的全局监听器仍在运行，任何一个 handler 改变焦点状态都会导致回车失效。

---

## 现状梳理

### 需要删除的内容

**`AppCoordinator.registerCommandShortcuts`**（138 行）

整个方法通过 `KeyboardShortcuts.onKeyUp` 注册了 22 个全局快捷键监听器，全部需要删除：

```
noteNew / noteNewFromSearch / noteDelete / noteArchiveToggle / noteLabelAdd
noteCopyMarkdown / noteCopyRichText / noteCopyPlainText / noteExport / noteShare
navSearch / navSidebar / navList / navEditor / navToggleSidebar
navBackToPrevious / navBack / navForward
viewToggleFullScreenEditor / appCommandPalette / appPreferencesShortcuts
helpFeedback / helpExportCrashLog / navFocusLabels
```

**`KeyboardShortcutsConfig.swift`**（45 行）

除 `.activateNV5` 外全部删除。`.activateNV5` 是唯一合理使用全局监听的场景
（从任意 app 唤起 NV5），其余都应走菜单系统。

**`MenuShortcutLabel.swift`**

专为 `KeyboardShortcuts` 设计的显示组件，菜单系统接管后由系统自动显示快捷键，无需此组件。

**`ShortcutsSettingsView.swift` + `SettingsCategory.shortcuts`**

快捷键设置面板依赖 `KeyboardShortcuts.Recorder`，快捷键改为硬编码后此面板无意义，
连同 `SettingsView.swift` 中的 `.shortcuts` 分类一并删除。

**`CommandPaletteView.shortcutBinding`**

```swift
private func shortcutBinding(for commandID: String) -> String? {
    let name = KeyboardShortcuts.Name(commandID)  // 删除
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
    return shortcut.description
}
```

命令面板中的快捷键显示逻辑，删除后命令行只显示命令名称，不显示快捷键。

---

### 需要新增的内容

**`NV5App.swift` — 重写 `.commands` 块**

用 SwiftUI 原生 `.keyboardShortcut()` 替代全局监听器。
菜单系统的优势：快捷键只在 app 激活时有效，菜单项禁用时快捷键自动失效，
系统自动在菜单中显示快捷键，无需手动维护。

新菜单结构：

```
File（替换系统默认）
  新建笔记          ⌘N
  从搜索新建        ⌘⇧N

笔记（新增）
  删除笔记          ⌘⌫
  切换归档          ⌘⇧A
  ──────────────
  复制为 Markdown   ⌘⇧C
  复制为富文本      ⌘⇧R
  复制为纯文本      ⌘⇧P   ← 原为 ⌘⇧T，修复与「添加标签」的冲突
  ──────────────
  导出到文件        ⌘⇧E
  分享...
  导出选项...

导航（重写）
  聚焦搜索栏        ⌘L
  聚焦笔记列表      ⌘2
  聚焦编辑器        ⌘3
  聚焦侧栏          ⌘1
  ──────────────
  后退              ⌘[
  前进              ⌘]
  返回上一条        ⌘'
  ──────────────
  切换侧栏          ⌘B
  全屏编辑器        ⌘⌃F

命令（保留）
  打开命令面板      ⌘⇧B
```

**`AppCoordinator` — 新增三个方法**

当前 `AppCoordinator` 缺少菜单直接调用所需的方法：

```swift
// 删除当前选中笔记
func deleteCurrentNote() {
    guard let id = selectedNoteID else { return }
    Task { try? await store.softDelete(id: id) }
}

// 切换当前笔记的归档状态
func toggleArchiveCurrentNote() {
    guard let id = selectedNoteID,
          let note = store.notes.first(where: { $0.id == id }) else { return }
    setArchived(id: id, archived: !note.archived)
}

// 跳转到上一条笔记（BackToPrevious 命令的直接调用版）
func switchToPreviousNote() {
    if let prev = navigationCoordinator.previousNote(
        existingIn: store.notes, archived: store.archivedNotes) {
        selectedNoteID = prev
    }
}
```

---

## 修复的已知 Bug

**`⌘⇧T` 快捷键冲突**

```swift
// KeyboardShortcutsConfig.swift 当前状态（两个命令绑定同一快捷键）
static let noteLabelAdd      = Self("note.label.add",      default: .init(.t, modifiers: [.command, .shift]))
static let noteCopyPlainText = Self("note.copy.plainText", default: .init(.t, modifiers: [.command, .shift]))
```

`KeyboardShortcuts` 库遇到冲突时两个 handler 都会触发，行为不可预测。
修复：`noteCopyPlainText` 改为 `⌘⇧P`。

---

## 改动范围

| 文件 | 操作 | 说明 |
|---|---|---|
| `App/Shortcuts/KeyboardShortcutsConfig.swift` | 重写 | 只保留 `.activateNV5` |
| `App/AppCoordinator.swift` | 删除方法 + 新增方法 | 删除 `registerCommandShortcuts`，新增 3 个方法 |
| `App/NV5App.swift` | 重写 `.commands` 块 | 用 `.keyboardShortcut()` 替代全局监听 |
| `App/Views/MenuShortcutLabel.swift` | 删除 | 系统自动显示快捷键 |
| `App/Views/Settings/ShortcutsSettingsView.swift` | 删除 | 快捷键不再可自定义 |
| `App/Views/SettingsView.swift` | 删除 `.shortcuts` 分类 | 对应设置面板已删除 |
| `App/Views/CommandPaletteView.swift` | 删除 `shortcutBinding` | 命令面板不再显示快捷键 |
| `NV5.xcodeproj/project.pbxproj` | 删除文件引用 | 对应删除的两个 Swift 文件 |

**保持不变**：
- `KeyboardShortcuts` 库依赖（仍需用于 `.activateNV5`）
- `BuiltinCommands.swift`（命令面板仍使用）
- 所有 `onKeyPress` 处理（列表导航、Escape 等走响应链，本来就正确）

---

## 预期效果

1. **消除 `keyUp` 竞争**：所有快捷键通过 `keyDown` 响应链处理，与焦点转移不再有时序冲突
2. **修复 `⌘⇧T` 冲突**：两个命令不再绑定同一快捷键
3. **减少代码量**：删除约 200 行快捷键注册代码，删除 2 个文件
4. **行为更可预测**：菜单项禁用时快捷键自动失效（如无选中笔记时删除快捷键不触发）
5. **维护成本降低**：新增命令只需在菜单加一行 `.keyboardShortcut()`，不需要同时维护 `KeyboardShortcutsConfig` 和 `registerCommandShortcuts`

---

## 取舍说明

**失去的功能**：用户无法在设置中自定义快捷键。

这与 nvALT 的设计一致——nvALT 也不支持自定义快捷键。
对于 NV5 这类效率工具，固定的肌肉记忆比可自定义更重要。
如果未来需要自定义，可以通过 macOS 系统偏好设置的「键盘 → 快捷键 → App 快捷键」实现，
无需 app 内部支持。
