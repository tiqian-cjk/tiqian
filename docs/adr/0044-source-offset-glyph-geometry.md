# ADR 0044: 选区/caret/装饰几何按 glyph 边界映射源偏移

- Status: Accepted
- Date: 2026-08-07
- Refines: [ADR 0011](0011-punctuation-geometry-ledger.md) 与 [ADR 0014](0014-ink-bounds-calibrated-punctuation-geometry.md)
  的标点几何 ledger（本 ADR 实现它们注释里预告的 glyph 边界 source mapping，并与标点 glue trim 互补）

## Context

几何查询层：core 的 `getCursorRect` / `getOffsetForPosition` / `getBoundingBoxes` /
`positionedRichTextSegments`，以及 compose 侧复制的 `LayoutResultReplayIndex`：把「源偏移 ↔ x」映射
实现为对 cluster **占位盒**（`left..right == x..x+advance`）的线性比例分。而多字符 cluster（拉丁词按整词
成一个 cluster，`advance` 是词宽）内部的每个字母宽度并不相等，线性均摊拿不到实际字母边界；
`SourceRangeLinearClusterSplit` / `ClusterAdvanceLinearHitTest` 的注释已写明这是「等待按 glyph 边界的
source mapping 实现」之前的占位。

后果：拉丁词内部 caret/选区端点落在线性估计位而非实际字母边界（真机上"选区拿不到西文实际字母宽度"）。
同一套逻辑在 core 与 compose 各存一份，互相发散的风险一直存在。

## Decision

`GlyphBoundarySourceMapping`：`PositionedCluster` 新增 `sourceStops`：每个源偏移边界的 x 位置，
`range.length + 1` 项，由 `positionedClusters` builder 计算：

- **两端总是占位盒边** `left` / `right`。这样行末被压成半角的全角标点，其字形 advance 仍是整个字身框，
  比压缩后的 cluster 占位盒宽，加上两端对齐拉伸，都不会让端点冲出可见行宽。
- **内部项取 shaped glyph 原点**（`drawX + glyph.x`），于是比例字体拉丁词内部的 caret/选区端点落在实际
  字母边界，不按线性估计。
- 仅当该 run 一个源单位对应一个 glyph 时生成；连字/复杂 run 为 null，调用方回退到占位盒线性插值。

`xForOffset` / `offsetForX` / `sliceRect` 改为消费 `sourceStops`；core 是唯一真值源，compose 的 replay
index 读同一份 `sourceStops`，不再是发散的第二实现。选区高亮为每行 caret-to-caret 连续填充。ruby base 的
框经 `withRubySelectionGeometry` 重分配后，`sourceStops` 置空（在重分配框上线性）。

**2026-08-08 amendment — 富文本背景不是选区框。** `SpanStyle.background` 仍从同一份
`positionedRichTextSegments` 起步，但生成独立的逐行 paint segment：一个视觉行内从首个标记内容边
连续覆盖到末个标记内容边，保留区间内部的字距、中西间距、词距和标点间距；只剥掉区间外侧的
autospace、justification 与标点 glue。竖直边使用标记文字的 typographic face，不再复用包含行间距的
完整 `LineBox`。选择、链接命中与无障碍仍使用稳定占位盒，二者不能再次合并。

**标点 glue 与本映射互补，不合并**：占位盒含标点 glue；ADR 0011/0014 的
`RichTextDecorationPunctuationGlueTrim` 保留，负责剥掉装饰外缘的标点 glue。`sourceStops` 只让端点/内部
的位置正确，两端仍是占位盒，压缩标点由 trim 收边。

## Consequences

- 拉丁词内部 caret/选区端点落到实际字母边界；跨行装饰不再因端点几何错误在压缩标点处凸出。
- 一份真值：core 与 compose 走同一 `sourceStops`。
- glyph-less / 连字 / 降级 cluster 回退占位盒线性（与旧行为一致），不引入新的崩溃面。
- `LayoutDumpGoldenTest` 不变：golden 记布局决策，不含选区/caret 查询几何。

## Alternatives considered

- **glyph advance 盒作为 ink span（`inkLeft/inkRight = drawX .. drawX + glyph.advance`），端点直接用它。**
  否决并已回退：行末全角标点压半角时，字形 advance 是整字身框（如 24px）而 cluster 占位盒是半角（12px），
  端点冲到字身框右缘，跨行下划线凭空多出一截（真机复现）。且它对拉丁词内部精度毫无帮助：整词一个 cluster，
  仍是在一个盒上线性。实际的分歧在 cluster **内部**，只能靠逐 glyph 边界解决。
- **让映射也扣除标点 glue、删掉 trim。** 否决：标点 glue 不在 glyph 里（字形填满字身框），删 trim 会让标点
  装饰重新吃 glue。
- **用记录的 glue 量算端点（不看 glyph）。** 否决：glyph 原点是直接证据，且能自然排除两端对齐拉伸。

## Verification

- `:core:jvmTest`、`:frontend:compose:jvmTest`（新增 `underlineDoesNotOvershootCompressedLineEndPunctuation`、
  `caretInsideProportionalLatinWordFollowsGlyphAdvances`，以及 `CjkSelectionTest`、链接命中测试）、
  `:layout:jvmTest --tests LayoutDumpGoldenTest` 全部通过。
- 真机确认（zhplus++）：跨行下划线不再在压缩标点处凸出；拉丁词内选区落在字母边界。
