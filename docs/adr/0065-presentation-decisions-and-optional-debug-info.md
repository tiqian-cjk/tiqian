# ADR 0065: 呈现决策记录与可选调试信息

- Status: Accepted
- Date: 2026-11-27
- Amends: [ADR 0005](0005-structured-layout-decisions.md)（结构化决策的读取位置）、AGENTS.md「实现约束」第 3 条

## Context

ADR 0005 把 `LayoutDebugInfo` 的决策改为结构化类型，供 playground、benchmark 与调试工具读取。之后，
渲染与查询代码也开始从 `LayoutResult.debug` 读取其中的列表。2026-11-27 在仓库中检索 `.debug.`
（排除测试）得到下列读取方：

| 读取方 | 读取的字段 |
|---|---|
| `platforms/apple/frontend/Sources/Tiqian/CoreTextLayoutRenderer.swift` | `fontDecisions`、`rubyDecisions`、`bopomofoDecisions`、`decorationDecisions`、`decorationSegments` |
| `platforms/android/rendering/.../AndroidParagraphRenderer.kt`、`platforms/compose/compose/.../SkiaLayoutRenderer.kt` | `rubyDecisions`、`bopomofoDecisions`、`decorationDecisions`、`decorationSegments` |
| `platforms/android/view/.../CjkTextView.kt`、`platforms/compose/compose/.../CjkTextLayoutNode.kt` | `lineSpacingDecision` |
| `engine-haxe/src/org/tiqian/layout/PlanLowering.hx`、`PreparedParagraph.hx` | `fontDecisions`、`shapingDecisions`、`punctuationDecisions`、`rubyDecisions`、`bopomofoDecisions`、`decorationDecisions`、`decorationSegments`、`zeroWidthBreakDecisions` |
| `engine-haxe/src/org/tiqian/core/LayoutQueries.hx`、`RichTextLayoutQueries.hx` | `geometryDecisions`、`metricDecisions`、`rubyDecisions`、`bopomofoDecisions`、`autoSpaceDecisions` |
| `engine-haxe/src/org/tiqian/core/LayoutPaintBounds.hx` | `rubyDecisions`、`decorationDecisions` |
| `engine-haxe/src/org/tiqian/core/LayoutResultReplayIndex.hx` | `fontDecisions` |

渲染依赖调试记录，所以每次排版都必须生成 `LayoutDebugInfo` 的全部字段。在 Apple 前端的 release 构建上，用
`sample` 对同一引擎在 20 到 40 栏之间反复重排 10 秒（`engine.layout` 共 6791 个样本），
`LayoutDebugAssembly.buildLayoutDebugInfo` 占 260 个样本，`LayoutDebugInfo` 的释放占 174 个样本，
两项合计约占排版耗时的 6.4%。这两项生成的是行决策、修复候选、两端对齐分配、标点间距等只供解释与
转储使用的记录。

## Decision

1. `LayoutPresentationDecisions`：`org.tiqian.core.LayoutPresentationDecisions` 保存呈现代码读取的
   12 项决策：`metricDecisions`、`geometryDecisions`、`autoSpaceDecisions`、`rubyDecisions`、
   `bopomofoDecisions`、`fontDecisions`、`shapingDecisions`、`punctuationDecisions`、
   `decorationDecisions`、`decorationSegments`、`zeroWidthBreakDecisions`、`lineSpacingDecision`。
   `LayoutResult.presentation` 在每次排版时都携带这些记录。
2. 呈现代码只读 `LayoutResult.presentation`。上表中的读取方全部改为读取该字段；读取 `LayoutResult.debug`
   的代码只剩转储（`LayoutDumpFormat`）、测试与 `tools/engine-probes` 中的诊断探针。
3. `LayoutDebugInfo` 的字段与顺序不变，仍包含上述 12 项。引擎同时生成两份记录时，两者引用同一批列表，
   转储与黄金数据的内容不变。
4. `recordsDebugInfo`：`ExplainableStubParagraphLayoutEngine` 的构造参数 `recordsDebugInfo` 默认为
   true。为 false 时，引擎不调用 `LayoutDebugAssembly.buildLayoutDebugInfo`，`LayoutResult.debug`
   为 `LayoutDebugInfo.Default`，其余字段与 true 时相同。测试、转储、排版报告与诊断探针使用默认值；
   Apple 前端（`AppleParagraphEngines`）默认传入 false，并提供参数打开。
5. AGENTS.md「实现约束」第 3 条改为：新的决策数据同步记录至调试信息与转储输出；呈现层需要的决策
   放入 `LayoutResult.presentation`，呈现层不读取 `LayoutResult.debug`，也不维护独立的排版数据副本。

## Consequences

- Apple 前端的重排不再生成解释记录。同一采样条件下，可省去的耗时上限约为 6.4%。
- 新增一项呈现代码需要读取的决策时，需要同时加入 `LayoutPresentationDecisions` 与 `LayoutDebugInfo`，
  并在 `LayoutDebugAssembly.buildPresentationDecisions` 中填写。
- Android、Compose 与 Web 前端仍使用默认值 true，行为与之前相同；它们改用 false 时只需修改引擎构造参数。
- `LayoutDebugStageInput` 改名为 `LayoutRecordStageInput`，因为它同时为两份记录提供输入。

## Alternatives

1. 保留现状：渲染与查询继续读取 `LayoutResult.debug`，每次排版都生成完整调试记录。上表的读取方不变，
   Apple 前端重排的 6.4% 耗时保留。
2. 只拆分读取位置、不提供开关：呈现代码改读 `LayoutResult.presentation`，但引擎仍每次生成
   `LayoutDebugInfo`。依赖关系得到拆分，耗时不变。
3. 延迟生成调试记录：`LayoutResult.debug` 在第一次读取时才构造。`LayoutResult` 需要持有
   `LayoutRecordStageInput` 引用的全部阶段数据（行候选、修复候选、两端对齐计划等），直到调试记录生成；
   `LayoutResult` 是 `@:dataClass` 记录，boring 为它生成只读字段、按字段比较与打印，读取字段时构造值
   需要在每个目标的生成代码中加入访问器。
