# ADR 0008: Shaping adapter 只负责字体成形与 glyph 几何

## Status

Accepted.

> [!NOTE]
> 本 ADR 中“当前 JVM 使用 stub、Android / Skia 后续接入”是建立 contract 时的实施状态。
> AWT、Skia、Android 与 Web adapter 现均已接入；`ExplainableStubTextShaper` 只保留为确定性
> 测试实现。见 [ADR 0013–0016](README.md#平台-shaping-与绘制)、
> [ADR 0039](0039-web-rendering-path.md) 与 [architecture.md](../architecture.md)。

## Context

Slice 6 开始前，`tiqian-shaping-api` 只有极薄的 `TextShaper` 接口，layout 仍直接构造 `Cluster` 和 nominal advance。这会让 pipeline 看起来已经有 shaping 模块，但实际上排版核心没有经过 shaping boundary，也无法在 playground / tests 中解释 shaping 来源。

同时，提椠必须避免另一个方向的错误：把 CLREQ 替换、字体 fallback、标点 glue、避头尾或两端对齐决策塞进平台 shaper。Android / Skia / HarfBuzz adapter 应是可替换的 glyph geometry provider，而不是排版规则拥有者。

## Decision

`TextShaper` 的契约如下：

1. `ShapingInput` 接收 source `text` / `range`、`TextStyle`、已完成的 `FontDecision`，以及 layout/profile 已决定好的 `displayText`。
2. `TextShaper` 返回 `Cluster`、`GlyphRun` 和结构化 `ShapingDecisionInfo`。
3. `TextShaper` 可以把一个 font decision range 拆成多个 cluster，但必须连续覆盖该 range。
4. `TextShaper` 不决定字体 fallback、CLREQ 码点替换、标点 atom/glue、kinsoku repair 或 justification。
5. 当前 JVM 使用 `ExplainableStubTextShaper`：它按 source/display code point 数生成 deterministic nominal advance，并把 source/display/font/source/reason 写入 debug。它是 pipeline 占位，不是假装真实 shaping。

## Consequences

- `ExplainableStubParagraphLayoutEngine` 的 pipeline 从 `fontDecisions -> direct Cluster` 推进到 `fontDecisions -> TextShaper -> Cluster/GlyphRun`。
- Playground metadata 必须显示 shaping decisions，以便确认每个 display cluster 的来源、advance 和 shaper source。
- Android / Skia adapter 后续可以逐步替换 stub，只要遵守 coverage contract。
- 真实 adapter 接入前，`ExplainableStubTextShaper` 仍不负责测量真实 glyph ink bounds；`PunctuationAtomBuilder` 继续使用当前 policy-derived body/glue，后续再用真实 glyph bounds 改进。

## Alternatives considered

- **继续在 layout 内直接构造 Cluster。** 否决。模块边界会停留在名义状态，后续真实 shaping 接入时会被迫大改 layout。
- **让 shaper 自己做 CLREQ punctuation substitution。** 否决。source/display 替换属于 profile 决策，shaper 只消费已经决定的 display text。
- **第一步直接接 Android / Skia 真实 shaper。** 否决。当前目标是先固化可解释 contract 和 golden path；平台 adapter 需要在 contract 稳定后接入。

## Follow-up

- 为 `tiqian-shaping-android` / `tiqian-shaping-skia` 单列模块和 adapter。
- 增加 golden fixture，固定 source/display/glyph advance/debug decision。
- 将真实 glyph ink bounds 接入 `PunctuationAtomBuilder`，替代当前 policy-derived body width。
