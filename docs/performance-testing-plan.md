# NV5 性能测试开发计划

本文档用于指导 NV5 进入性能测试开发阶段。目标不是一次性完成所有压测，而是先建立可重复的性能基线，覆盖近期审计中确认的卡顿热点，并让后续优化可以被量化验证。

## 背景

近期性能审计确认了以下高风险路径：

- 搜索输入会触发全文扫描，历史实现还存在缓存失效 Bug。
- 编辑器自动保存热路径曾包含全文装饰、`NSDataDetector` 链接检测和 RTFD 序列化。
- `NoteStore` 数据库观察使用 `fetchAll` 替换整个 notes 数组。
- 同步流程曾在一次 sync 中多次全量读取本地笔记。
- 高亮搜索会在主线程对整篇文档做全文扫描。

这些问题已经有一批低风险修复，但项目仍缺少性能回归测试。后续任何搜索、编辑器、同步、数据库观察相关改动，都应该能通过性能测试看到趋势。

## 前置工作

### 修复 App 测试目标可见性

当前 `xcodebuild test -scheme NV5App` 会在 `NV5AppTests` 编译阶段失败，测试目标无法访问 `CommandRegistry`、`CommandContext`、`CommandCategory`、`AppCommand`、`AppCoordinator` 等 App 内部类型。

在引入 App 层性能测试前，需要先解决以下任一方案：

1. 将命令、编辑器辅助逻辑、过滤逻辑等可测试代码拆到 framework target。
2. 调整 App 目标中相关类型的访问级别和 testable import 配置。
3. 新建独立性能测试 target，只依赖可测试 framework，AppKit/SwiftUI 集成测试另行处理。

验收标准：

- `xcodebuild test -scheme NV5App` 至少能编译通过测试 target。
- 性能测试可以在本地稳定执行，不依赖真实 WebDAV 服务或用户数据。

## 测试分层

### 1. 单元性能测试

适合放在现有 XCTest 中，执行快，可进入 CI。

覆盖对象：

- `NoteStore.search`
- `TextDecoratorPipeline.runInteractive`
- `TextDecoratorPipeline.runAll`
- 同步本地快照复用逻辑
- 纯函数化后的列表过滤逻辑

指标：

- `XCTClockMetric`
- `XCTMemoryMetric`
- 结果正确性断言
- 调用次数断言

### 2. 集成性能测试

适合本地或 nightly，不一定每次提交都跑。

覆盖对象：

- 编辑器自动保存节流策略
- 数据库观察触发频率
- 同步流程在大量本地/远端笔记下的协调耗时

指标：

- commit 次数
- rich commit 次数
- observation update 次数
- mock WebDAV 请求次数
- wall time 和内存变化

### 3. 手动性能剖析

用于长文档、真实 UI、滚动、输入响应等 XCTest 不稳定覆盖的场景。

工具：

- Instruments Time Profiler
- Allocations
- SwiftUI Body / View Update 相关模板
- Main Thread Checker

建议在每次大型编辑器或搜索架构改动后执行。

## 推荐新增测试模块

### P0：NoteStoreSearchPerformanceTests

目的：建立全文搜索性能与正确性基线。

建议位置：

- `Tests/CommandsTests/NoteStoreSearchPerformanceTests.swift`
- 若拆 target，则放入 `Tests/PerformanceTests/NoteStoreSearchPerformanceTests.swift`

数据集：

- 1,000 篇笔记：日常规模。
- 5,000 篇笔记：重度用户规模。
- 10,000 篇笔记：压力规模，可标记为 nightly。
- 每篇笔记包含 title、body、labels。
- body 建议混合短文、2KB 正文、10KB 正文。

测试场景：

- 空 query 返回全部笔记。
- 标题命中。
- 正文命中。
- 多 token 搜索。
- 无命中搜索。
- 增量搜索：`"s" -> "sw" -> "swift"`。
- 更新 title/body 后缓存失效，搜索结果必须正确。

验收标准：

- 结果正确，不允许缓存返回陈旧结果。
- 1,000 篇数据的常见 query 应保持在可交互范围内。
- 性能指标先记录 baseline，不在第一版设置过严阈值。

示例骨架：

```swift
func testSearchBodyMatchPerformance_1000Notes() throws {
    let notes = makeNotes(count: 1_000, bodySize: .medium)
    try await insertNotes(notes)

    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        _ = store.search(query: "needle")
    }
}
```

### P1：TextDecoratorPipelinePerformanceTests

目的：验证交互装饰管线不会重新引入高成本链接检测。

建议位置：

- 如果 AppKit 代码仍在 App target：先修 App test 可见性。
- 更推荐将 `TextDecoratorPipeline` 移到可测试模块后放入独立测试 target。

数据集：

- 10KB 普通文本。
- 100KB 混合文本。
- 1MB 长文档，nightly。
- URL-heavy 文档。
- wiki link-heavy 文档。
- heading + done tag 混合文档。

测试场景：

- `runInteractive` 处理普通文档。
- `runInteractive` 处理 URL-heavy 文档。
- `runAll` 处理 URL-heavy 文档。
- 对比 `runInteractive` 与 `runAll` 的耗时差异。

验收标准：

- `runInteractive` 不应调用 `NSDataDetector`。
- URL-heavy 文档中 `runInteractive` 应明显快于 `runAll`。
- 交互管线保持主线程可接受耗时。

示例骨架：

```swift
func testInteractiveDecoratorSkipsLinkDetection() {
    let storage = NSTextStorage(string: makeURLHeavyText(size: 100_000))

    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        TextDecoratorPipeline.runInteractive(on: storage)
    }
}
```

### P1：NoteEditorAutosaveTests

目的：防止编辑器自动保存再次把 RTFD 序列化和链接检测放回 300ms 热路径。

建议方式：

- 优先把 autosave 策略抽成小型 coordinator 或 scheduler，使其不依赖完整 `NSTextView`。
- 若直接测 `NoteEditor.Coordinator`，需要修 App test 可见性并处理 AppKit 主线程要求。

测试场景：

- 连续输入 20 次，只触发有限次数 text commit。
- 300ms 后执行轻量 text commit。
- 300ms text commit 不写 `bodyAttributes`。
- 5 秒 idle 后执行 rich commit。
- 失焦、切换笔记、应用 resign active 时执行 rich commit。
- 切换笔记前 pending rich commit 不丢失。

验收标准：

- text commit 和 rich commit 次数符合预期。
- rich commit 不在 300ms 自动保存路径中发生。
- `bodyAttributes` 不因轻量保存被清空。

建议指标：

- text commit count。
- rich commit count。
- commit 延迟。
- RTFD 序列化次数。

### P2：SyncCoordinatorSnapshotTests

目的：保证一次同步只读取一次本地全量快照，并复用于下载、上传、协调阶段。

建议位置：

- `Packages/NVSync/Tests/SyncCoordinatorSnapshotTests.swift`

测试方式：

- 使用 mock WebDAV client。
- 使用临时 SQLite 数据库。
- 通过 spy 或 instrumentation 统计本地全量读取次数。
- 如果 `fetchAllLocal` 当前是 private，不便直接 spy，可以先通过日志/计数抽象一个 local snapshot provider。

测试场景：

- 远端空，本地有 dirty new notes。
- 远端有新 notes，本地为空。
- 本地和远端都有既有 notes。
- 有 tombstones。
- 有 conflict。

验收标准：

- 一次 `sync()` 中本地快照读取次数为 1。
- WebDAV 请求次数符合预期。
- 同步结果正确。

### P2：NoteListFilterPerformanceTests

目的：防止 `filteredNotes` 回到 SwiftUI 计算属性重复扫全文。

前置建议：

- 将列表过滤抽成纯函数或小型服务，例如 `NoteListFilter`。
- View 只负责 debounce 和状态更新。

测试场景：

- all / archived / label 三种筛选。
- query 为空。
- query 非空。
- 快速 query 变化只消费最后一次过滤结果。
- 同一键盘导航事件不重复计算过滤。

验收标准：

- 过滤结果正确。
- 计算次数可观测。
- 频繁输入时可取消旧任务。

### P3：DatabaseObservationPerformanceTests

目的：量化数据库观察器 `fetchAll` 和 SwiftUI 数组替换带来的压力，为后续 NoteSummary 架构提供 baseline。

测试场景：

- 1,000 / 5,000 notes。
- 连续编辑同一篇 note 50 次。
- 批量导入 notes。
- 归档/取消归档。
- 删除/恢复同步清理。

指标：

- active observation update count。
- archived observation update count。
- `notes` 数组替换次数。
- 每次 observation 的 wall time。
- 内存峰值。

验收标准：

- 先记录 baseline。
- 后续引入 `NoteSummary` 后，应证明 observation 数据量和主线程更新时间下降。

## 测试数据生成器

建议新增统一 fixture 工具，避免各测试重复造数据。

建议能力：

- 生成固定 seed 的 notes，保证测试稳定。
- 指定 note count。
- 指定 body size。
- 指定命中 token 分布。
- 指定 label 分布。
- 指定 dirty、archived、deletedLocally、remotePath、etag 状态。

示例 API：

```swift
enum NoteFixtureFactory {
    static func notes(
        count: Int,
        bodySize: BodySize,
        matchingEvery stride: Int = 10,
        token: String = "needle"
    ) -> [Note]
}
```

## 性能指标与阈值策略

第一阶段不要急着写死严格阈值。建议分三步：

1. **Baseline 阶段**：只记录指标，避免因机器差异导致测试不稳定。
2. **Guardrail 阶段**：设置宽松阈值，例如不能比 baseline 慢 2 倍。
3. **CI 阶段**：只把稳定的 1,000 notes 测试纳入每次提交；5,000/10,000 notes 放 nightly 或手动。

建议记录：

- 测试机器。
- Xcode 版本。
- macOS 版本。
- Debug/Release 配置。
- 数据规模。
- 平均耗时。
- p95 耗时。
- 内存峰值。

## 推荐落地顺序

### Phase 1：可测试性与基线

1. 修复 `NV5AppTests` 编译失败。
2. 新增 `NoteFixtureFactory`。
3. 新增 `NoteStoreSearchPerformanceTests`。
4. 新增 `TextDecoratorPipelinePerformanceTests`。

验收：

- `xcodebuild build -scheme NV5App` 通过。
- `xcodebuild test -scheme NV5App` 可以编译并运行相关测试。
- 搜索和装饰管线有第一版 baseline。

### Phase 2：近期修复回归保护

1. 新增 `NoteEditorAutosaveTests`。
2. 新增 `SyncCoordinatorSnapshotTests`。
3. 对搜索缓存失效 Bug 增加功能测试。

验收：

- 300ms 自动保存路径不会执行 rich commit。
- 一次 sync 中本地快照读取保持 1 次。
- 更新 title/body 后搜索结果正确。

### Phase 3：架构优化前后对比

1. 抽出 `NoteListFilter` 并新增性能测试。
2. 新增 `DatabaseObservationPerformanceTests`。
3. 开始评估 `NoteSummary` 和 FTS5 前后对比。

验收：

- 列表过滤计算次数可观测。
- 数据库观察压力有 baseline。
- 大型架构优化能用数据证明收益。

## CI 建议

每次提交运行：

- 构建。
- 功能测试。
- 1,000 notes 搜索性能 smoke test。
- `runInteractive` 100KB 文档性能 smoke test。
- 同步快照读取次数测试。

Nightly 运行：

- 5,000 / 10,000 notes 搜索测试。
- 1MB 文档装饰测试。
- 数据库观察压力测试。
- 同步 5,000 notes 场景。

手动 release 前运行：

- Instruments 输入长文档。
- Instruments 搜索大库。
- WebDAV mock 大同步。
- 真实应用滚动和焦点切换检查。

## 完成定义

性能测试开发第一阶段完成应满足：

- App 测试 target 编译问题已修复。
- 至少 4 个核心测试文件落地：
  - `NoteStoreSearchPerformanceTests`
  - `TextDecoratorPipelinePerformanceTests`
  - `NoteEditorAutosaveTests`
  - `SyncCoordinatorSnapshotTests`
- 搜索、编辑器自动保存、同步快照复用都有回归保护。
- 关键测试数据由统一 fixture 生成。
- 本地文档记录了 baseline 数字和测试机器信息。

## 后续方向

完成基线后，再推进更大的性能架构：

- 列表改为 `NoteSummary`，正文按需加载。
- 搜索迁移到 SQLite FTS5 或专用索引。
- 文本装饰支持 dirty range。
- 同步核心拆成非 MainActor worker。
- 高亮限制可视范围或最大匹配数。
