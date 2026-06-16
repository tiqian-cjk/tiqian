# ADR 0030: 富文本 per-span 样式（render-only 先行，layout-affecting 分档）

- Status: Accepted
- Date: 2026-06-17

## Context

`TiqianTextContent.spans: List<TextSpan(range, TextStyle)>` 早就在 core 模型里，但引擎
完全没读它——`fontSize`/`fontFamilies`/`locale` 全取自单一 `input.textStyle`，一个
`fontSize` 驱动 shaping、度量、标点 glue、中西间距、缩进、整数行长、justify 上限。
要支持富文本（颜色、加粗、斜体、字号、字体）就得让这些**按 span 走**。

Compose 侧作者面用 `AnnotatedString`（ADR 0030 的 `CjkParagraph(AnnotatedString)`），
其 `SpanStyle` 映到本模型：layout 相关的 → 引擎，render 相关的 → renderer。

## Decision

按「改不改 advance / 度量」把 span 样式分两档：

**A. Render-only（不改版面）——先做。**
- **颜色**：只改 paint，不动 advance/度量/glue。引擎布局**一字不变**，renderer 按 span
  逐 cluster 上色。从 `AnnotatedString.spanStyles` 抽 `SpanStyle.color` →
  `drawTiqianGlyphs` 的 per-cluster 颜色查表（color→Paint 缓存）。
- 不走「合成加粗/斜体」：synthetic bold/oblique 会改墨宽却不改 advance，导致版面与绘制
  对不上——加粗/斜体一律归 B 档走真字体。

**B. Layout-affecting（改 advance/度量）——后续增量，需先定混排 em 规则。**
- **字号、字体、字重、斜体**：每个 cluster 按其 span 的 font 真正 shape（advance 真）、
  取真度量。涉及的 em 基准要分清：
  - 行高 = 行内各 cluster 度量的 `max`（已是 maxOf，喂入 per-cluster 度量即可）；
  - 标点 glue、着重号几何 = **标点/被注字自己的字号**；
  - 中西间距 = 边界 CJK 的字号；
  - 段首缩进、整数行长 grid = **段落基准字号**（不随 span 变，否则字格会抖）；
  - 混排字号的基线对齐规则（CLREQ §文本的间距调整）单独定。
- **双语强调**（汉字着重号 + 西文斜体）= B 档的自然产物：一个 emphasis span 里西文部分
  套 `Italic`。是否由 `Emphasis` 装饰**自动**给范围内西文 cluster 加斜体，作为 B 档的一个
  policy 定。
- **列表**（左对齐标记 + 固定列正文）= 段落缩排（已有）+ 标记层，随 B 档一并做。

## Consequences

- 颜色立即可用，且**零引擎风险**（布局不变、golden 不动）。
- B 档是真正的大头：per-cluster style 贯穿 fallback→shaping→metrics，且每条 em 决策都要
  指明「用谁的字号」。分档让 A 先落地、B 带着混排 em 规则单独推进。
- 源文本不改写：`AnnotatedString.text` 即源；span 只附着样式。

## Alternatives considered

- **一步到位做全部样式**：否决——layout-affecting 的混排 em 歧义没定就动 shaping，必然返工。
- **render-only 合成加粗/斜体**：否决——改墨不改 advance，版面与绘制错位，且质量差。
