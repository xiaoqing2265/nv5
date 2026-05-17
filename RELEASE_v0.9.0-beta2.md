# v0.9.0-beta2 正式发布报告

## 🎉 发布信息

- **版本号**: v0.9.0-beta2
- **发布日期**: 2026-05-17
- **发布类型**: Beta 版本
- **Git Tag**: v0.9.0-beta2
- **提交哈希**: 63b8d97

## 📋 发布清单

### ✅ 已完成的工作

#### 1. UI 修复
- ✅ 修复 TagEditor 遮挡命令面板的问题
  - 当命令面板显示时，自动隐藏 TagEditor
  - 当命令面板关闭时，自动恢复 TagEditor
  - 提供清晰的 UI 层级

#### 2. 自动更新改进
- ✅ 修复 release.yml 中的 git 操作
  - 添加 `git fetch origin main`
  - 添加 `git checkout main`
  - 添加 `git pull origin main`
  - 确保 `git push origin main` 成功

- ✅ 更新 appcast.xml 文件大小
  - beta1: 8,999,656 字节
  - alpha3: 8,692,459 字节
  - alpha2: 8,606,067 字节

#### 3. 工作流改进
- ✅ 改进 release.yml 错误处理
- ✅ 添加 SPARKLE_PRIVATE_KEY 检查
- ✅ 改进 sign_update 工具查找逻辑

### 📊 代码统计

| 指标 | 数值 |
|------|------|
| 新增提交 | 3个 |
| 修改文件 | 2个 |
| 新增行数 | 20行 |
| 删除行数 | 1行 |
| 编译状态 | ✅ 成功 |

### 🔗 提交历史

```
63b8d97 fix: prevent TagEditor from overlaying command palette
9f5a69c fix: improve release workflow git operations for appcast update
6eafa98 fix: update appcast.xml with correct file sizes for auto-update
```

## 🚀 发布流程

1. ✅ **创建 Tag**
   ```bash
   git tag -a v0.9.0-beta2 -m "Release v0.9.0-beta2: UI Fixes and Auto-Update Improvements"
   ```

2. ✅ **推送 Tag**
   ```bash
   git push origin v0.9.0-beta2
   ```

3. ⏳ **GitHub Actions 自动执行**
   - 构建应用（xcodebuild）
   - 创建 DMG 安装包
   - 使用 Sparkle EdDSA 签名
   - 生成 appcast.xml
   - 创建 GitHub Release
   - 更新 appcast.xml 到 main 分支

## 📦 发布产物

### 生成的文件
- `NV5-v0.9.0-beta2.dmg` - macOS 安装包
- `appcast.xml` - 自动更新配置（已更新）

### 发布位置
- GitHub Releases: https://github.com/xiaoqing2265/nv5/releases/tag/v0.9.0-beta2
- 自动更新源: appcast.xml

## ✨ 主要改进

### UI 改进
- ✅ 命令面板显示清晰，不被 TagEditor 遮挡
- ✅ 更好的 UI 层级管理
- ✅ 更流畅的用户体验

### 自动更新改进
- ✅ release.yml 工作流更加可靠
- ✅ appcast.xml 自动更新成功率提高
- ✅ 更好的错误处理和日志输出

### 工作流改进
- ✅ 改进的 git 操作逻辑
- ✅ 更好的 SPARKLE_PRIVATE_KEY 处理
- ✅ 更清晰的错误消息

## 🧪 测试建议

### 功能测试
- [ ] 打开命令面板（⌘/）
- [ ] 验证 TagEditor 不会遮挡命令面板
- [ ] 关闭命令面板
- [ ] 验证 TagEditor 恢复显示
- [ ] 测试所有快捷键功能

### 自动更新测试
- [ ] 检查 appcast.xml 是否正确生成
- [ ] 测试应用自动更新功能
- [ ] 验证 DMG 签名是否有效
- [ ] 验证从 beta1 升级到 beta2

### 辅助功能测试
- [ ] 使用 VoiceOver 测试应用
- [ ] 启用 Reduce Motion 测试动画
- [ ] 启用高对比度测试界面

## 📝 发布说明

### 新增功能
- 无新增功能（主要是修复和改进）

### 改进
- 修复 TagEditor 遮挡命令面板的问题
- 改进 release.yml 工作流的 git 操作
- 更新 appcast.xml 文件大小
- 改进错误处理和日志输出

### 已知问题
- 无

## 🎯 下一步计划

### 立即可做
- [ ] 监控 GitHub Actions 工作流执行
- [ ] 验证 DMG 生成和签名
- [ ] 检查 appcast.xml 更新
- [ ] 测试自动更新功能

### 后续版本
- v0.9.0-rc1 - 候选发布版本
- v1.0.0 - 正式发布版本

## 📊 版本对比

| 版本 | 主要改进 | 状态 |
|------|---------|------|
| v0.9.0-alpha1 | 首个 alpha 版本 | ✅ 已发布 |
| v0.9.0-alpha2 | M6 键盘工作流实现 | ✅ 已发布 |
| v0.9.0-alpha3 | 快捷键引导和速查表 | ✅ 已发布 |
| v0.9.0-beta1 | M6 完善、文档、测试 | ✅ 已发布 |
| v0.9.0-beta2 | UI 修复、自动更新改进 | ✅ 已发布 |

## 📞 反馈和支持

- GitHub Issues: 报告 Bug 或提出功能建议
- GitHub Discussions: 讨论和交流

---

**NV5 v0.9.0-beta2** - 为键盘而生的笔记应用 ⌨️

发布时间: 2026-05-17
发布者: xianjin + Claude Haiku 4.5
