# ADR 0013: 先用 JVM AWT adapter 打通真实 advance 可视化

- Status: Accepted
- Date: 2026-06-07

## Context

Slice 6a 已经把 `TextShaper` contract 接进 layout pipeline，但默认仍是
`ExplainableStubTextShaper`：Latin run 按 `1em × codepoint` 计宽，标点也没有真实
glyph bounds。继续在这个假宽度上调 line break、autospace、glue 和 justification，
会让规则越来越像“在 stub 世界里正确”。

完整 Skia/HarfBuzz/Android shaping adapter 成本更高，而且需要平台绘制链配合。当前更需要的是：

1. playground 里能马上看到真实 advance 对断行和 glue 的影响；
2. 保留 stub 作为 deterministic 对照；
3. 不让 adapter 接管 CLREQ 替换、fallback、标点 atom 或避头尾规则。

## Decision

新增 `tiqian-shaping-jvm`，提供 `AwtTextShaper`：

- 使用 JVM `Font.layoutGlyphVector` 和 `FontRenderContext` 测量 display text。
- 输入仍然消费 layout/profile 已经决定好的 `displayText`，不改 source text。
- 输出一个覆盖输入 `FontDecision.range` 的 cluster、一个 glyph run、每个 glyph 的 advance 与 visual bounds。
- `ShapingDecisionInfo.source = JvmAwt`，reason 写入实际 AWT family / font name。
- playground 默认使用 `jvm-awt`，并保留 `TIQIAN_PLAYGROUND_SHAPER=stub` 对照路径。

`AwtTextShaper` 只是 JVM real-measurement adapter，不是最终跨平台 shaping 答案。

## Consequences

- real-text fixture 中 Latin advance、line deficit、break point、justification allocation 会开始暴露真实变化。
- 真实 glyph bounds 已进入 `Glyph.bounds`，下一步可以把 punctuation atom 的 `bodyWidth` / glue 校正接到这些 bounds 上。
- AWT 的字体 fallback 与平台 Skia/Android 不完全相同，因此不能把 AWT 输出当最终 golden；它是 playground 观察入口和 contract proof。
- Android TextPaint / Skia adapter 仍然留在 Slice 6 后续。

## Follow-up

- 让 `PunctuationAtomBuilder` 接收 shaped glyph bounds，替代 policy-derived `bodyWidth`。
- 在 playground metadata 中展示 glyph bounds / ink box，而不只是 run advance。
- 增加 platform-specific adapter：`tiqian-shaping-android` 和 Skia/Skiko adapter。
- 为真实 shaper 输出建立专门 golden，避免复用 stub golden。
