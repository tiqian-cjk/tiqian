# ADR 0030: 富文本 per-span 样式（render-only 先行，layout-affecting 分档）

- Status: Accepted
- Date: 2026-06-17
- Amendment 2026-06-21：`ColorSpan(start, end, argb)` 移入 `tiqian-core`（与 `DecorationSpan`
  并列的 render-only span），不再住 `tiqian-shaping-skia`——前端公开签名遂不泄漏 Skia 类型。
- Amendment 2026-07-07：`TextStyle.baselineShift` 成为 B 档 layout-affecting span
  样式，用于 Compose `SpanStyle.baselineShift` / 参考文献角标等显式上标/下标位移。

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

**B. Layout-affecting（改 advance/度量）——混排 em 规则已定（2026-06-17）；字号已落地（2026-06-19）。**
- **字号**（✅ 已落地）：sized span 内每个 cluster 按 span 字号真正 shape（advance 真）+
  取真度量。实现：`TiqianTextContent.spans` 进引擎，span 边界强制切 cluster
  （`clusterRanges` 不再吞掉 Latin 词 / 合并标点内的尺寸变化），`shapeSegment` 用
  per-segment style、`FontMetricsRequest` 用 per-cluster 字号；renderer 按 `FontSizeSpan`
  逐 cluster 取同尺寸 `Font` 绘制。Compose 作者面：`SpanStyle(fontSize = 1.8.em)`
  （`.em` 相对段落基准，`.sp`/数值当引擎 px）。无 span 时全路径与旧 golden 逐字节一致。
  - **v1 限定**：① 行高取**整段** cluster 度量的 max（一处放大 → 全段行距升高），**逐行**
    行高是后续；② 边界 em 决策（中西间距、标点 glue）仍按**段落基准**，per-owner 细化是
    后续；③ 因此 sized span **内含标点**时该标点 body/glue 仍是基准尺寸（少见，已知毛边）；
    ④ 混排**基线对齐**沿用共享基线（ideographic/alphabetic），CLREQ 基线规则单独定。
- **字重、斜体**（✅ 已落地 2026-06-19）：`TextStyle` 加 `fontWeight`/`italic`，shaper 按
  `FontStyle(weight, slant)` 选**真**粗体/斜体 typeface → SHAPED advance 是真的（粗体更宽、
  非合成）；renderer 同样按 per-cluster `FontStyle` 取 styled typeface 绘制。**度量不变**：
  同一字族粗/斜共用纵向度量，行高不随字重/斜体变（正确）。CJK 多无斜体，`matchFamilyStyle`
  退最近的正立体（不合成倾斜）——与「斜体只对西文有意义」一致。span 样式在 Compose 侧
  **拍平**成无重叠、整解析的 `TextSpan`（base + 覆盖），故字号/字重/斜体/颜色可任意叠加。
  默认 `(400, upright)` == `FontStyle.NORMAL` → 无 span 时 typeface 不变（golden 零漂移）。
- **字体（family）**（✅ 已落地 2026-06-19）：`SpanStyle.fontFamily`（`GenericFontFamily`
  Serif/SansSerif/Monospace）→ token 名进 `TextStyle.fontFamilies`。`SkiaSystemTypefaces.typeface
  (isLatin, family, style)` 一个**共享**解析器：generic 按 role 映射候选（衬线 CJK→宋/明体、
  Latin→Times；等宽 Latin→Menlo…；CJK 多全宽退回 sans）；具名族先试再退回系统默认。shaper
  （advance）与 renderer（glyph）走同一解析器 → 不漂。**限制**：自定义 `FontListFontFamily`
  （加载字体文件，无可移植族名）暂不接；per-cluster **度量**仍用默认字（行高基本不随族变），
  与字重/斜体同一档的取舍。
- **显式 baseline shift**（✅ 已落地 2026-07-07，`ExplicitBaselineShiftSpan`）：`TextStyle`
  增加 `baselineShift`（px，+down），Compose `SpanStyle.baselineShift` 的 multiplier
  按 span 最终字号解析并翻转成 Tiqian 坐标。它不改变字体 fallback、标点 glue、禁则或
  Roman/CJK baseline 分类，只在最终 cluster baseline 上**叠加**作者样式位移；因此参考文献
  `[1]` 这类西文/数字角标仍保持共享 Roman baseline，只是被显式上移。
- **混排 em 决策的字号基准 = 该空白的「归属 cluster」的字号**（加性 glue 模型每条空白都有
  归属者）。CLREQ 已为关键决策指定了归属，不是「小的/前一个/段落」的全局选择：
  - **中西间距** = 1/4 **汉字宽**（CLREQ 原文）→ 归属那个**汉字**的字号（西文字号不进式子）；
  - **标点 body（半字）+ glue** = **标点自己**的字号；
  - **着重号几何** = 被注**那个字自己**的字号；
  - **段首缩进 / 整数行长 grid** = **段落基准字号**（结构骨架，绝不随 span 抖）；
  - **CjkInterChar 末档拉伸** = 亏空÷边界数，不吃 em，无字号问题；
  - CLREQ 未指定归属的边角（两个任意不同字号字之间）= **取小的那边**（保守、对称；中文里罕见）。
  - 对回业界：Word「前一个字符」≈ 拖尾 glue 的归属者（局部近似）；InDesign「段落值」= 我们
    的结构档（grid/缩进）；都各对一半，本规则把两半按归属统一了。
- **行高** = 行内各 cluster 度量的 `max`（已是 maxOf，喂入 per-cluster 度量即可）；混排字号的
  **基线对齐**规则（CLREQ §文本的间距调整）单独定。
- **双语强调**（✅ 已落地 2026-06-19，`BilingualEmphasisWesternItalic`）：`Emphasis`(着重号)
  span 内，汉字加点（既有），**西文 run 自动斜体、不加点**。引擎按 role(Latin)∩Emphasis 在
  shaping 时 `italic=true`（advance 真）；renderer 用**同一份** role(`debug.fontDecisions`)+
  decorations 数据取斜体 typeface，二者一致。着重号点几何本就跳过非汉字（`no-dot-on-non-han`）。
  当前**恒开**（无 flag）——要可关需把 policy 透到 renderer，后续。
- **列表**（✅ 已落地 2026-06-19，CLREQ §6.2.1.1 凸排）：`CjkBlock.List(items, marker, indent?, start)`
  + `ListMarker`（`Decimal` `1.` / `CjkNumber` `一、` / `Circled` `①` / `Bullet` `•`）。
  标记**左对齐顶格**于固定宽「标记列」(gutter)，正文整列缩进、续行同列对齐——Compose 侧
  双列（gutter `Box` + 正文 `Row.weight`），**引擎零改动**，正文/标记都走 `CjkParagraph`。
  列宽默认 **1 字**，自动按列表中**最宽标记**升到放得下它的最小整字数（如出现 `10.` → 2 字），
  标记宽**实测**（`autoListGutterEm`，关 grid + 零缩进取裸宽，不靠数位数）；`indent` 非空则覆盖。
  marker/正文都**零段首缩进**（gutter 是唯一缩进）。嵌套/富文本项是后续。
  Web 于 2026-07-14 接入同一模型：简单顶层 `ol/ul` 保留原生容器与 `li`，整组 marker 用当前
  Web shaper 实测，最宽值向上取整到整数 `ic`；gutter 位于正文版心内部，item 可用行长为
  `正文版心 - gutter`，因此续行、响应式网格与普通正文共用同一组字格。marker 是 `aria-hidden`、
  不可选且不进入 DOM `textContent` 的 paint-only pseudo；复制、搜索和无障碍仍只看到原 item。
  任一 item 不能保真时整组恢复原生列表。嵌套、block-rich item、`reversed` 与非 decimal / 常见
  bullet marker 暂不冒充支持。

## Consequences

- 颜色立即可用，且**零引擎风险**（布局不变、golden 不动）。
- B 档是真正的大头：per-cluster style 贯穿 fallback→shaping→metrics，且每条 em 决策都要
  指明「用谁的字号」。分档让 A 先落地、B 带着混排 em 规则单独推进。
- 源文本不改写：`AnnotatedString.text` 即源；span 只附着样式。

## Alternatives considered

- **一步到位做全部样式**：否决——layout-affecting 的混排 em 歧义没定就动 shaping，必然返工。
- **render-only 合成加粗/斜体**：否决——改墨不改 advance，版面与绘制错位，且质量差。
