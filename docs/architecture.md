# NV5 架构设计

## 概述

NV5 是一个全键盘优先的笔记应用，采用分层架构设计，确保键盘交互的流畅性和可维护性。

## 架构层次

```
┌─────────────────────────────────────┐
│         UI 层 (SwiftUI Views)       │
├─────────────────────────────────────┤
│    协调层 (Coordinators & Registry) │
├─────────────────────────────────────┤
│      业务逻辑层 (Commands)          │
├─────────────────────────────────────┤
│      数据层 (Store & Models)        │
└─────────────────────────────────────┘
```

## 核心组件

### 1. FocusCoordinator（焦点协调器）

**职责**：管理应用中的焦点状态和焦点区之间的导航。

**关键特性**：
- 维护当前焦点区（searchField, sidebar, noteList, editor）
- 支持 Tab/Shift+Tab 循环导航
- 焦点栈用于模态对话框焦点恢复
- 浮层激活状态管理

**使用场景**：
```swift
// 切换焦点
focusCoordinator.focus(.editor)

// 循环导航
focusCoordinator.focusNext()
focusCoordinator.focusPrevious()

// 模态对话框
focusCoordinator.pushFocus()  // 打开前
focusCoordinator.popFocus()   // 关闭后
```

### 2. CommandRegistry（命令注册表）

**职责**：管理所有可用命令，支持搜索和执行。

**关键特性**：
- 注册和管理应用命令
- 模糊搜索命令
- 条件启用/禁用命令
- 动态生成快捷键列表

**命令结构**：
```swift
protocol AppCommand {
    var id: String { get }
    var title: String { get }
    var category: CommandCategory { get }
    var symbol: String { get }
    
    func isEnabled(in context: CommandContext) -> Bool
    func run(in context: CommandContext) async
}
```

### 3. CommandHistoryStore（命令历史存储）

**职责**：持久化和管理命令执行历史。

**关键特性**：
- 记录命令执行时间和频次
- 按最近使用时间和频次排序
- 支持查询历史
- 自动清理过期数据

**使用场景**：
```swift
// 记录命令执行
historyStore.record("note.new")

// 获取最近命令
let recent = historyStore.recent(limit: 5)

// 获取查询历史
let history = historyStore.queryHistory()
```

### 4. NavigationHistory（导航历史）

**职责**：管理笔记浏览历史，支持前进/后退。

**关键特性**：
- 记录笔记访问顺序
- 支持前进/后退导航
- 自动截断前进历史
- 避免重复记录相同笔记

**使用场景**：
```swift
// 记录访问
navigationHistory.record(noteID)

// 后退
if let previousID = navigationHistory.goBack() {
    coordinator.selectNote(previousID)
}

// 前进
if let nextID = navigationHistory.goForward() {
    coordinator.selectNote(nextID)
}
```

### 5. AppCoordinator（应用协调器）

**职责**：协调应用级别的状态和操作。

**关键特性**：
- 管理选中笔记
- 处理笔记创建/删除/更新
- 管理全屏编辑器状态
- 协调多选状态

## 键盘事件处理

### 三层键盘事件架构

```
┌──────────────────────────────────────┐
│  K1: KeyboardShortcuts (全局)        │
│  - 应用级快捷键                      │
│  - 通过 KeyboardShortcuts 库管理     │
└──────────────────────────────────────┘
           ↓
┌──────────────────────────────────────┐
│  K2: SwiftUI .keyboardShortcut       │
│  - 菜单快捷键                        │
│  - 绑定到菜单项                      │
└──────────────────────────────────────┘
           ↓
┌──────────────────────────────────────┐
│  K3: .onKeyPress (局部)              │
│  - 面板内快捷键                      │
│  - 特定视图的快捷键                  │
└──────────────────────────────────────┘
```

### 快捷键配置

所有快捷键定义在 `KeyboardShortcutsConfig.swift`：

```swift
extension KeyboardShortcuts.Name {
    static let noteNew = Self("note.new", default: .init(.n, modifiers: [.command]))
    static let navBack = Self("navigation.back", default: .init(.leftBracket, modifiers: [.command]))
    // ...
}
```

## 数据流

### 命令执行流程

```
用户按下快捷键
    ↓
KeyboardShortcuts 捕获
    ↓
CommandRegistry 查找命令
    ↓
检查命令是否启用
    ↓
执行命令 (async)
    ↓
更新 UI 状态
    ↓
记录到 CommandHistoryStore
```

### 焦点导航流程

```
用户按下 Tab/Shift+Tab
    ↓
MainView 捕获 .onKeyPress
    ↓
FocusCoordinator.focusNext/Previous()
    ↓
更新 current 焦点区
    ↓
UI 响应焦点变化
    ↓
相应视图获得焦点
```

## 设计原则

### 1. 单一职责
- 每个组件只负责一个明确的功能
- FocusCoordinator 只管理焦点
- CommandRegistry 只管理命令

### 2. 依赖注入
- 通过 @Environment 注入依赖
- 便于测试和替换

### 3. 异步优先
- 所有命令执行都是异步的
- 避免阻塞 UI

### 4. 主线程安全
- 所有状态管理都在 @MainActor 上
- 遵循 Swift 6 严格并发

### 5. 可测试性
- 核心逻辑与 UI 分离
- 易于编写单元测试

## 扩展指南

### 添加新命令

1. 创建 Command 结构体：
```swift
struct MyCommand: AppCommand {
    let id = "category.myCommand"
    let title = "我的命令"
    let category: CommandCategory = .note
    let symbol = "star"
    
    func isEnabled(in context: CommandContext) -> Bool { true }
    
    func run(in context: CommandContext) async {
        // 实现命令逻辑
    }
}
```

2. 注册到 BuiltinCommands：
```swift
enum BuiltinCommands {
    static let all: [AppCommand] = [
        // ...
        MyCommand(),
    ]
}
```

3. 添加快捷键（可选）：
```swift
extension KeyboardShortcuts.Name {
    static let myCommand = Self("category.myCommand", default: .init(.m, modifiers: [.command]))
}
```

### 添加新焦点区

1. 扩展 FocusTarget 枚举
2. 更新 FocusCoordinator 的循环逻辑
3. 在 MainView 中处理新焦点区

## 性能考虑

- CommandRegistry 搜索使用模糊匹配，O(n) 复杂度
- CommandHistoryStore 使用 UserDefaults，自动延迟写入
- NavigationHistory 限制最大 50 条记录
- 所有异步操作都在后台线程执行

## 测试策略

- 单元测试：FocusCoordinator, CommandRegistry, CommandHistoryStore, NavigationHistory
- 集成测试：完整的键盘工作流
- UI 测试：焦点管理和快捷键响应
