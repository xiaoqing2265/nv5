# NV5 - 全键盘笔记应用

NV5 是一个为键盘而生的 macOS 笔记应用，设计灵感来自 [nvALT](http://brettterpstra.com/projects/nvalt/) 和 [Notational Velocity](http://notational.net/)。它继承了这些应用的核心交互理念：搜索框即新建框、即时全文过滤、纯键盘驱动。

## ✨ 核心特性

- **全键盘优先** - 所有操作都可以通过键盘完成，无需触碰鼠标
- **即时搜索** - 输入时实时过滤笔记，支持全文搜索
- **WebDAV 同步** - 支持自建、Nextcloud、坚果云等 WebDAV 服务
- **现代 Swift** - 使用 Swift 6 严格并发、SwiftUI 最新 API
- **快速响应** - 基于 SQLite + GRDB，性能优异
- **隐私优先** - 支持字段级加密，数据完全掌握在自己手中

## 🚀 快速开始

### 系统要求
- macOS 14 Sonoma 或更新版本
- Apple Silicon 或 Intel Mac

### 安装
从 [Releases](https://github.com/xiaoqing2265/nv5/releases) 页面下载最新版本。

### 首次使用
1. 启动应用
2. 按 `⌘N` 创建第一篇笔记
3. 按 `⌘/` 查看所有快捷键

## ⌨️ 核心快捷键

### 笔记操作
| 快捷键 | 功能 |
|--------|------|
| ⌘N | 新建笔记 |
| ⌘⌫ | 删除笔记 |
| ⌘⇧A | 归档/取消归档 |
| ⌘⇧T | 编辑标签 |

### 导航
| 快捷键 | 功能 |
|--------|------|
| ⌘L | 聚焦搜索栏 |
| ⌘1-3 | 切换焦点区 |
| Tab/⇧Tab | 循环切换焦点 |
| ⌘[ / ⌘] | 导航历史前进/后退 |

### 编辑
| 快捷键 | 功能 |
|--------|------|
| ⌘⌃F | 全屏编辑 |
| ⌥⌘← / ⌥⌘→ | 上一篇/下一篇笔记 |

### 其他
| 快捷键 | 功能 |
|--------|------|
| ⌘⇧P | 打开命令面板 |
| ⌘/ | 快捷键速查表 |

完整的快捷键列表请查看 [docs/keyboard.md](docs/keyboard.md)。

## 📚 文档

- [架构设计](docs/architecture.md) - 了解 NV5 的设计原理和架构
- [快捷键指南](docs/keyboard.md) - 完整的快捷键参考
- [实施方案](上.md) - 详细的项目实施方案

## 🏗️ 项目结构

```
NV5/
├── App/                    # 主应用代码
│   ├── Commands/          # 命令系统
│   ├── Views/             # SwiftUI 视图
│   ├── Focus/             # 焦点管理
│   ├── Accessibility/     # 辅助功能
│   └── ...
├── Packages/              # Swift Package
│   ├── NVModel/          # 数据模型
│   ├── NVStore/          # 数据持久化
│   ├── NVSync/           # WebDAV 同步
│   ├── NVCrypto/         # 加密功能
│   └── NVKit/            # UI 组件库
├── Tests/                 # 单元测试
├── docs/                  # 文档
└── ...
```

## 🔧 开发

### 环境要求
- Xcode 16+
- Swift 6
- macOS 14+

### 构建
```bash
xcodebuild build -scheme NV5App -configuration Debug
```

### 运行测试
```bash
xcodebuild test -scheme NV5App
```

## 📦 依赖

- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite 数据库
- [Sparkle](https://github.com/sparkle-project/Sparkle) - 自动更新
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - 快捷键管理

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- 灵感来自 [nvALT](http://brettterpstra.com/projects/nvalt/) 和 [Notational Velocity](http://notational.net/)
- 感谢所有贡献者和用户的支持

## 📞 联系方式

- GitHub Issues - 报告 Bug 或提出功能建议
- GitHub Discussions - 讨论和交流

---

**NV5** - 为键盘而生的笔记应用 ⌨️
