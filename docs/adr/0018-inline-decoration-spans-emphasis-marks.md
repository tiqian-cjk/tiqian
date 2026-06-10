# ADR 0018: Inline decoration span 模型与着重号

- Status: Accepted
- Date: 2026-06-11

## Context

着重号（CLREQ 3.6 强调）与示亡号是简体横排的真实需求（教材、名单/讣告），
两者都需要一个目前不存在的输入通道：**对 source text 区间的标注**。这是
`LayoutInput` 第一次出现 span 概念，值得单独定模型。

CLREQ 对着重号的规定：

- 形态为「圆形中黑点，可以为 U+25CF BLACK CIRCLE 或 U+2022 BULLET」；
  横排标注于文字**底端**。
- 点号/引号/括号/书名号等标点「底端或顶端通常不再添加着重号」。

## Decision

### Span 输入

`LayoutInput.decorations: List<DecorationSpan>`，`DecorationSpan(range, kind)`
以 **source range** 标注（display 替换不影响 span 语义）。第一阶段
`DecorationKind` 只有 `Emphasis`；`Mourning`（示亡号）随 Slice 9 加入。

### 着重号是逐字几何决策

Layout 在行/cluster 几何定稿后解析 span，产出
`DecorationDecisionInfo(clusterRange, kind, applied, reason, anchorX, anchorY)`：

- **加点对象**：`CjkText` role 的 cluster → applied（`EmphasisDotOnHanText`）；
  `CjkPunctuation` → skip（`clreq-no-dot-on-punctuation`，CLREQ 原文）；
  Latin/其它 → skip（`no-dot-on-non-han`，西文强调走斜体不在本期）。
- **anchor 语义**：dot 墨迹中心应落到的画布坐标。
  `anchorX` = cluster 字形中心（最终行内 x + 去掉 justify delta 的字形
  advance 的一半）；`anchorY` = `line.baseline + 0.35em`。下沉量**相对
  baseline 而非 em box 底**：`CenteredCjkVisual` 的 em box descent 是人为的
  0.5em，而汉字真实墨迹只到 baseline 下 ≈0.1em——按 em box 下沉会把点压进
  下一行墨迹。0.35em 让点紧贴字底（@16px 约 2px 间隙），lineHeight 1.0 也
  不与下一行冲突。CLREQ 未规定间距，取值进常量便于 profile 化。
- **渲染**：画 U+2022（CJK 字体 glyph，`LocaleTaggedShaping` 同源路径），
  量出 ink bounds 后把墨迹中心对齐 anchor——字形差异由渲染层吸收，引擎
  决策与字体解耦。AWT 调试 raster 以等效实心圆近似（非真值渲染路径）。

### 不改 line metrics

着重号**不参与** line height / 断行 / justification。由于 anchor 紧贴字底
（baseline + 0.35em，仍在 CenteredCjkVisual 的 0.5em descent 带内），默认
行高即可容纳；更宽的 lineHeight 只是让版面更松，不是正确性前提。

### 示亡号预定（Slice 9）

黑框按行分段描边；断行策略为**整体避拆**（进现有 repair 体系），span
超过一行宽时 fallback 为跨行分段。细节随实现补充本 ADR 或新开。

## Consequences

- `LayoutResult` 新增 `decorationDecisions`；dump 增 `deco:*` 行；
  golden 覆盖（fixture 含跨行、含标点的着重号区间）。
- span 模型为示亡号、未来的下划线/波浪线等装饰直接复用。
- 竖排时 anchor 语义需换轴（顶端/右侧），`anchorX/Y` 字段名保持中性。
