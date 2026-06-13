# ADR 0021: 段首缩进

- Status: Accepted
- Date: 2026-06-12

## Context

CLREQ：「段首缩排以两个汉字的空间为标准。若遇到杂志等多栏排版……时有改用
缩排一字」；「若首行行首出现开始夹注符号，可以缩减该符号始侧二分之一个
汉字大小的空白」。此前段落级特性完全缺失（gap audit 缺口 5）。

## Decision

### `ParagraphStyle.firstLineIndentEm` = 显式覆盖，默认随行长自适应

缩进是段落样式而非 CLREQ profile 规则——量纲用 em，跟随字号。
`firstLineIndentEm` 现为**显式覆盖**（`Float?`，含 0 关闭）；默认 `null`，
由 `firstLineIndentPolicy`（[MeasureAdaptiveFirstLineIndent]）按行长决定。
手调几何的 fixture 与单测显式 pin 0（缩进不是它们要验证的变量）。

### `MeasureAdaptiveFirstLineIndent`：窄行缩一字（2026-06-13 amendment）

CLREQ 标准两字宽是宽行正文的取值；窄栏（多栏杂志、手机正文）里 2 字缩进
占行比过重，CLREQ 也记多栏「时有改用缩排一字」。故默认改为**随行长自适应**：
`measure < shortBelowEm 字` 缩 `shortEm`（默认 1）字，否则 `longEm`（默认 2）
字。`resolveEm(measureEm)` 在引擎里以**量化后的版心**（measure/fontSize）
为输入，与 grid（ADR 0028）/kinsoku 同源。

**阈值默认 14 字，与 `MeasureAdaptiveKinsoku` 的悬挂阈值同值但独立**——两者
回答不同问题（悬挂：整字下移是否过松；缩进：2 字是否过重），按用户拍板
取同一默认值但各自一个 knob，可分别调；且本策略**不依赖悬挂信号**，在
`KinsokuMode.Fixed` 下照常生效（与悬挂解耦，避免 Fixed 模式下失去自适应）。

显式 `firstLineIndentEm` 任意非 null 值都覆盖自适应（含窄行强行 2 字、宽行
强行 0）。决策入 dump：`FirstLineIndentDecisionInfo`
（source=Explicit/MeasureAdaptiveFirstLineIndent + measure/threshold/resolved），
golden 与 playground 在 source 非 Explicit 时打印 `firstindent N字 measure=…
threshold=… …`。`adaptive-short-line-indent` fixture 端到端印证（10 字→1 字）。

### 缩进 = 首行可用行宽收窄 + 渲染起点偏移

- breaker 端：起始于 cluster 0 的行（含 lookahead 评分、PushIn 合并行）
  可用行宽为 `maxWidth - firstLineIndent`，其余行不变（`lineLimit`）。
- justify 端：首行的对齐目标同样是收窄后的行宽。
- 结果端：`LineBox.indent` 暴露行首 inline 轴起点偏移；宽度字段不含
  缩进，`LayoutResult.size.width` 取 `max(indent + visualWidth)`。
  渲染层（compose / playground raster / HTML）只做 `x = line.indent`
  起步，不参与任何决策。decoration（着重号锚点、示亡号框）几何在
  engine 端已含偏移。

### 首行开括号「缩减半宽」不需要实现

加法模型下开括号 = leading glue (0.5em 空白) + body；行首 leading glue
在任何行首都被 `consumeLineEdgeGlue` 削掉（ADR 0010），段落首行不例外。
缩进 2em 后紧跟已削前空白的开括号，字面前视觉空白恰为 2em——CLREQ 的
「可以缩减」是模型的自然推论（`indent-opening-quote` golden 印证）。
CLREQ 原文是「可以」；我们的行首 trim 无条件，取严格侧，与行末
`ForceHalfWidth` 默认一致。若将来需要「首行开括号保留全宽」的宽松
风格再加开关，现在不预留。

### 竖排时它该怎么改

`LineBox.indent` 语义是「inline 轴起点偏移」，竖排即首列顶端的
block-start inset，字段无需改；数值仍是 2em。

## Consequences

- `first-line-indent` / `indent-opening-quote` fixture + golden；
  `real-paragraph-1` 改为带标准缩进的真实正文形态。
- dump：line 行新增 `indent=` 字段（仅非零时输出）。
- compose demo 与 playground 默认呈现缩进段落。
- `ParagraphStyle` 既有默认值的不一致暴露出来：`textAlign` 默认 Start
  而中文正文应 Justify。是否把 Justify 设为默认留待单独讨论，本 ADR
  不顺手改。
