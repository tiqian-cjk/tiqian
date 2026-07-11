# ADR 0024: 行间线——专名号与书名号甲式

- Status: Accepted
- Date: 2026-06-13

## Context

CLREQ 行间标点的处理（第五节摘录已入库）：专名号（下划线）、书名号
甲式（波浪线）合称「行间线」，横排标注于文字下方。规则要点：

- 有几个标注项目就用几条线段，不能从中断开、不能拼接；相邻两个专名
  必须两条线、断开可辨认；
- 长度与所标注文字外框一致；相邻时相邻一侧缩短（≤1/8em），另一侧不变；
- 被标注字距被拉开时，行间线相应延长且不断开；
- 行间标点尽量紧贴所标注汉字一侧；
- 与着重号同现时「先线后点」：线贴字，点在线下。

decoration 通道（ADR 0018）已有 span 输入与按行分段几何（示亡号同型）。

## Decision

- `DecorationKind.ProperNoun` / `BookTitle`：行间线两式。几何复用
  `DecorationSegmentInfo`，线类 `top == bottom == baseline + 0.18em`
  （字身底 +0.12em 下方一线空气，「紧贴所标注汉字」；使用着重号默认
  `0.1em` 字面净空时，点墨水上缘为 `0.12em + 0.1em = +0.22em`，
  先线后点成立，无需额外机制）。
- **一项一线**：每个 span 每行一条线段（跨行自然分段，openStart/End
  仅作 dump 诊断——线没有「开口边」渲染语义）；行内永不拆分。
- **随字距延长**：线段跟随 justify 后的字位（行间线随拉开的字距延长、
  不断开），末 cluster 的 trailing justify delta 在线外（长度与文字
  外框一致）——与示亡号右缘同规则。
- **`AdjacentInterlinearLineShortening`**：同一行内两条行间线相接
  （间距 < 0.01em）时，各自相邻一侧回缩 1/16em（可见间隙 1/8em，单侧
  回缩在 ≤1/8em 上限内），外侧保持文字外框。专名+书名混合相邻同样适用。
- **断行**：不避拆（与示亡号不同——长专名跨行是常态），跨行各段独立。
- **行距**：行间线属行间标点，`InterlinearMarkLineSpacingFloor`
  （ADR 0018 amendment）自动生效。
- 渲染：专名号直线、书名号甲式波浪线（`wavyLinePath` 下沉到
  `tiqian-shaping-skia` 与 `shapeTextBlob` 同位；AWT raster 用折线
  近似）。前端仍零决策——线的位置、长度、缩短全部来自 engine dump。

### Amendment (2026-06-13): 波浪线形态——简体默认圆形，尖形留作 zh-Hant 预留

书名号甲式的波形存在两种并存风格：台湾《重訂標點符號手冊》图示为
**尖**的波浪；U+FE4F（WAVY LOW LINE）在多数字体中为**圆**的波浪。
两者都不是 `MainlandHorizontal` profile 的规范来源——CLREQ 把行间线的
形态明确交给「字体和排版引擎的设计」。拍板：

- **简体 profile 默认圆形**（二次贝塞尔、波长 0.4em、振幅 0.06em）：
  大陆古籍整理本的浪线书名号、大陆字体的 `﹏` 字形、浏览器
  `text-decoration-style: wavy` 均为圆形，符合简体读者的心智模型。
- **尖形是真实的风格差异**，对应《重訂標點符號手冊》——留作将来
  zh-Hant profile 的渲染参数，与「GB 固定半宽标点」同属并存风格预留。
- AWT 调试视图原为折线近似（视觉为尖形），已改为与 Skia 路径同形的
  圆滑波——两个渲染器不得在波形上不一致。

### 暂不做

- 直排（行间线在文字左侧、与着重号构成双面装）——竖排预研时一并处理；
  segment 模型只需换轴。
- 专名号/书名号的语义识别（哪些字是专名）——永远是调用方输入，引擎
  不做 NER。

## Consequences

- `interlinear-lines` fixture + golden（dump `decobox` 行可见相邻缩短
  159/161 与 `linespacing` floor）；几何单测覆盖一项一线、贴字 y、
  相邻侧回缩、外侧不变。
- gap audit 缺口 7 关闭；第一阶段 audit 列出的缺口全部完成。
