# ADR 0008: Shaping adapter 只负责字体成形与 glyph 几何

## Status

Accepted.

> [!NOTE]
> 本 ADR 中“当前 JVM 使用 stub、Android / Skia 后续接入”是建立 contract 时的实施状态。
> AWT、Skia、Android 与 Web adapter 现均已接入；`ExplainableStubTextShaper` 只保留为确定性
> 测试实现。见 [ADR 0013–0016](README.md#平台-shaping-与绘制)、
> [ADR 0039](0039-web-rendering-path.md) 与 [architecture.md](../architecture.md)。

## Context

Slice 6 开始前，`shaping/api` 只有极薄的 `TextShaper` 接口，layout 仍直接构造 `Cluster` 和 nominal advance。这会让 pipeline 呈现出已有 shaping 模块的样子，而排版核心没有经过 shaping boundary，也无法在 playground / tests 中解释 shaping 来源。

同时，提椠必须避免另一个方向的错误：把 CLREQ 替换、字体 fallback、标点 glue、避头尾或两端对齐决策放进平台 shaper。Android / Skia / HarfBuzz adapter 应是可替换的 glyph geometry provider，不拥有排版规则。

## Decision

`TextShaper` 的接口定义如下：

1. `ShapingInput` 接收 source `text` / `range`、`TextStyle`、已完成的 `FontDecision`，以及 layout/profile 已决定好的 `displayText`。
2. `TextShaper` 返回 `Cluster`、`GlyphRun` 和结构化 `ShapingDecisionInfo`。
3. `TextShaper` 可以把一个 font decision range 拆成多个 cluster，但必须连续覆盖该 range。
4. `TextShaper` 不决定字体 fallback、CLREQ 码点替换、标点 atom/glue、kinsoku repair 或 justification。
5. 当前 JVM 使用 `ExplainableStubTextShaper`：它按 source/display code point 数生成 deterministic nominal advance，并把 source/display/font/source/reason 写入 debug。它是 pipeline 占位，不冒充实际 shaping。

## Amendment (2026-08-28): ShapingInputDefinesLayoutCluster

第 3 条由本修订取代：核心在 shaping 输入层建立布局 cluster 边界，平台 adapter 对每个
`ShapingInput` 返回一个连续覆盖 `input.range` 的 `Cluster`。HarfBuzz、SkShaper、Core Text
或平台 API 返回的内部 glyph cluster 只用于 glyph 与 source 的关联、placement 和重放，不能直接
成为断行机会。

断行规则需要更细边界时，核心必须先把 source range 拆成多个 `ShapingInput`。例如 ADR 0029
先按英文音节和硬断候选切分输入，再分别 shaping；因此每个输出 cluster 边界都具有明确的断行
来源。平台因字体、样式或能力边界无法处理一个输入时，应把证据交回核心或走具名 capability
degrade，不能自行增加布局 cluster 边界。

该约束不要求丢弃底层 glyph cluster 信息；它只分离 glyph/source 映射与布局断点。当前
Skia、Android public、Android controlled-font、Core Text、Web Canvas 与 stub adapter 均已遵守。
Rust paragraph demo 曾把 HarfRust 的逐字母 glyph cluster 暴露为布局 cluster，使断行器在
`internationalization` 的非音节边界直接截断；adapter 改为按输入聚合后恢复与上述平台一致。

## Consequences

- `ExplainableStubParagraphLayoutEngine` 的 pipeline 从 `fontDecisions -> direct Cluster` 推进到 `fontDecisions -> TextShaper -> Cluster/GlyphRun`。
- Playground metadata 必须显示 shaping decisions，以便确认每个 display cluster 的来源、advance 和 shaper source。
- Android / Skia adapter 后续可以逐步替换 stub，只要遵守 coverage contract。
- shaping 库的内部 cluster 粒度不再改变可用断行集合；新增 adapter 必须保持按输入划分的布局 cluster。
- 实际 adapter 接入前，`ExplainableStubTextShaper` 仍不负责测量实际 glyph ink bounds；`PunctuationAtomBuilder` 继续使用当前 policy-derived body/glue，后续再用实际 glyph bounds 改进。

## Alternatives considered

- **继续在 layout 内直接构造 Cluster。** 否决。模块边界会停留在名义状态，后续实际 shaping 接入时会被迫大改 layout。
- **让 shaper 自己做 CLREQ punctuation substitution。** 否决。source/display 替换属于 profile 决策，shaper 只消费已经决定的 display text。
- **第一步直接接 Android / Skia 实际 shaper。** 否决。当前目标是先固化可解释 contract 和 golden path；平台 adapter 需要在 contract 稳定后接入。

## Follow-up

- 为 `shaping/android-adapter` / `shaping/skia` 单列模块和 adapter。
- 增加 golden fixture，固定 source/display/glyph advance/debug decision。
- 将实际 glyph ink bounds 接入 `PunctuationAtomBuilder`，替代当前 policy-derived body width。

## Amendment（2026-08-25）：`ExplainableStubParagraphLayoutEngine` 改名裁定

该名字出自 2026-06-06 的 scaffold 提交（1a37d54a，Claude session 写入），早于
本 ADR。本 ADR 把以 Stub 命名的类记录为 pipeline 占位时，该引擎此后已接入实际 shaping、
字体度量与断行，名字中的 Stub 与运行现状不符。2026-08-25 ffi 边界复审
（ADR 0053）裁定：生产路径类名不得保留 Stub，改名
`TiqianParagraphLayoutEngine`，旧名不再并存；`ExplainableStubTextShaper` 等
只服务测试与确定性 fixture 的 stub 命名不在本裁定范围。改名由引擎侧主责者
执行，ffi 边界纠偏队列只记录裁定，不携带该波。
