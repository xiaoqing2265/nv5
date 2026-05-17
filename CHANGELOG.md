# 更新日志

所有值得注意的项目更改都将记录在此文件中。

## [0.9.0-beta1] - 2026-05-17

### 🎉 新增

#### M6 键盘工作流完善
- ✨ 添加了 CommandHistoryStore 和 NavigationHistory 的单元测试（18 个测试用例）
- 📚 创建了完整的架构设计文档 (`docs/architecture.md`)
- 📚 创建了完整的快捷键指南 (`docs/keyboard.md`)
- ♿ 实现了 Reduce Motion 和高对比度的辅助功能支持
- ⌨️ 添加了缺失的快捷键命令：
  - `⌥⌘←` - 上一篇笔记 (PreviousNoteCommand)
  - `⌥⌘→` - 下一篇笔记 (NextNoteCommand)
  - `⌘A` - 全选 (SelectAllCommand)

#### 快捷键增强
- 添加了 7 个新的快捷键配置：
  - `navPreviousNote` - ⌥⌘←
  - `navNextNote` - ⌥⌘→
  - `listHome` - Home
  - `listEnd` - End
  - `listPageUp` - Page Up
  - `listPageDown` - Page Down
  - `listSelectAll` - ⌘A

#### 辅助功能
- 创建了 AccessibilitySettings 类来监听系统辅助功能设置
- 添加了 ViewExtensions 提供焦点环视觉指示器和高对比度支持

### 📝 文档
- 添加了 README.md - 项目介绍和快速开始指南
- 添加了 CHANGELOG.md - 更新日志
- 添加了 M6_COMPLETION_REPORT.md - 完善工作总结报告

### 🔧 改进
- 改进了 CommandPaletteView 的辅助功能支持
- 优化了快捷键配置的组织结构

### ✅ 完成标准
- ✅ 所有 9 个 M6 任务（K1-K9）已完成
- ✅ 单元测试覆盖率 ≥ 80%
- ✅ 完整的快捷键文档
- ✅ 首次启动引导已实现
- ✅ Cheat Sheet 已实现
- ✅ VoiceOver 支持已实现
- ✅ 项目编译成功，无错误

---

## [0.9.0-alpha2] - 2026-05-16

### 🎉 新增
- ✨ 添加了键盘快捷键引导面板 (KeyboardGuideView)
- ✨ 添加了快捷键速查表 (CheatSheetView)
- ✨ 添加了帮助命令（反馈、崩溃日志导出）

### 🔧 改进
- 改进了命令面板的用户体验
- 优化了快捷键的可发现性

---

## [0.9.0-alpha1] - 2026-05-15

### 🎉 新增
- ✨ 实现了 M6 键盘工作流的核心功能（K1/K2/K3）
- ✨ 添加了 TagEditor 标签编辑器浮层
- ✨ 实现了持久化搜索历史
- ✨ 改进了焦点管理

### 🔧 改进
- 改进了命令面板的搜索功能
- 优化了焦点导航的流畅性

### 🐛 修复
- 修复了 M6 功能的编译错误
- 修复了 Swift 6 严格并发错误

---

## [0.8.0] - 2026-05-10

### 🎉 新增
- ✨ 实现了 Sparkle 自动更新集成
- ✨ 改进了应用窗口管理

### 🔧 改进
- 改进了应用启动性能
- 优化了内存使用

---

## 版本说明

### 版本号规则
- **主版本号** - 重大功能更新或架构变更
- **次版本号** - 新增功能或重要改进
- **修订号** - Bug 修复或小的改进
- **预发布标签** - alpha（内部测试）、beta（公开测试）、rc（候选发布）

### 发布计划
- **0.9.0-beta1** - 当前版本，M6 完善工作完成
- **0.9.0-rc1** - 计划中，内测反馈修复
- **1.0.0** - 正式发布版本

---

## 贡献者

感谢所有为 NV5 做出贡献的人！

---

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件
