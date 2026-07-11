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
  advance 的一半）；`anchorY` 从该 cluster 的真实字面底边开始，加上
  `ParagraphStyle.emphasisDotGapEm × clusterEm` 的净空和圆点半径。默认净空
  `0.1em`。CLREQ 只规定着重号位于文字底端，没有规定精确距离，因此
  `ExplicitEmphasisDotGap` 把距离保留为显式排版输入；定位仍随真实字体度量、
  span 字号与 baseline shift 变化，不把 baseline 当作字面底边。
- **渲染**：`DecorationDecisionInfo.dotDiameter` 是最终墨迹直径，默认 `0.19em`。
  Web、Compose 与调试前端均在 anchor 画同样大小的实心圆，不得再乘隐藏 scale；
  引擎用于定位的半径与实际墨迹因此完全一致。

### 不改 line metrics

着重号**不参与** line height / 断行 / justification。`lineHeight` 只提供容纳
行间标记的空间，不参与反推 anchor；更宽的 lineHeight 会让版面更松，但不会
暗中移动着重号。空间下限由 `InterlinearMarkLineSpacingFloor` 独立保证。

### 示亡号（Slice 9 落地）

- **整体避拆（`MourningSpanKeptUnbroken`）**：Mourning span 映射为 breaker 的
  `unbreakableRanges`——断点落在 span 内部时移到 span 起点（greedy 与
  lookahead 同规则，lookahead 候选直接排除 span 内断点）。span 比版心还宽
  时放弃避拆，分段并以 `openStart`/`openEnd` 标记续行边（该边不描）。
- **kinsoku 交互**：`CarryPrevious` 若会把 span 的一部分带走则拒绝
  （`carry-would-split-mourning-span`，落 LeaveRagged）；PushIn 的 offender
  恒为标点、不会在姓名 span 内，无需 guard。
- **框几何（`DecorationSegmentInfo`）**：按行一段矩形，**紧贴字面、零边距**。
  水平边贴 cluster 盒（右边去掉 justify delta）；竖直边取常规 CJK 字身框
  `baseline - 0.88em .. baseline + 0.12em`。排除过的方案：layout em box
  （0.5/0.5 人为虚构，会切穿字形）、raw line metrics（含行间空隙，框会
  虚胖）、逐字 ink union（随字形起伏——`一` 会让框塌掉，名单中框高不一致）。
  0.88/0.12 编码标准 CJK 设计字身比例；换用字体上报的 ideographic
  metrics（BASE 表）是 follow-up。框高恰为 1em，默认行高即可容纳，
  更大行距只是版面更松。
- CLREQ 依据：「在人名文字外框描上实心的黑色边线」；断行规则 CLREQ 未规定，
  避拆为本项目决策（名单场景姓名不应跨行）。

### Amendment (2026-06-13): 行距下限与锚点下移（CLREQ 5.6.1.1）

第五节原文入库后复核发现两处缺口：

- **`InterlinearMarkLineSpacingFloor`**：CLREQ 5.6.1.1 要求带行间标点时
  行距（行高 − 字面高）单面装不小于 1/2 字号、双面装不小于 5/8 字号。
  此前引擎没有任何约束——默认行高恰为 1.0em（字面相贴、行距 0），
  fixture 靠手动 lineHeight 兜底，demo 第三段实际处于违例状态。现在：
  段落带行间标记类 decoration 时 auto 行高抬到 floor；显式 lineHeight
  低于 floor 时 clamp（原文是「不应小于」）。决策记入
  `LayoutDebugInfo.lineSpacingDecision`，dump 增 `linespacing` 行。
  - **Amendment (2026-06-21)**：floor 固定取**单面装 1/2 字号**（屏幕真实下限）。
    原 `ParagraphStyle.printingSides` + 双面装 5/8 已删——单/双面是**印刷正反面透印**
    概念，屏幕前端无背面、无法兑现（同竖排/JLREQ「不过早承诺」）。双面 5/8 随打印
    后端连同 ADR 再回。
- **着重号锚点 0.35em → 0.45em**（历史实现，已由 2026-07-11 amendment 取代）：原值点的墨水上缘距字身底仅 0.12em，
  视觉上贴字。下移后点与字面有明确空隙，且在 floor 保证的行距带内
  （点底 +0.56em < 下一行字身顶 +0.62em @1.5em 行高）。

### Amendment (2026-07-10): 显式距离，不跟随行高

旧实现曾把 `0.45em` 中心下沉量提升为显式参数，并删除根据 `lineHeight`
自动移动 anchor 的实验公式。这个修订确立了“行高与着重号距离相互独立”，
但中心相对 baseline 仍没有表达真正的字面间距。

### Amendment (2026-07-11): 字面净空与单一圆点几何

公共参数改为 `ParagraphStyle.emphasisDotGapEm`：它表达字面底边到圆点墨迹上缘
的净空，默认 `0.1em`。引擎用每个 cluster 的 `layoutDescent + baselineShift`
取得字面底边，再加净空与真实半径得到 anchor。原先各前端额外乘 `0.85` 的缩放
删除，`dotDiameter` 成为唯一真值。由此保留距离可调能力，同时不再依赖 baseline、
行高或渲染器私有常量。

## Consequences

- `LayoutResult` 新增 `decorationDecisions`；dump 增 `deco:*` 行；
  golden 覆盖（fixture 含跨行、含标点的着重号区间）。
- span 模型为示亡号、未来的下划线/波浪线等装饰直接复用。
- 竖排时 anchor 语义需换轴（顶端/右侧），`anchorX/Y` 字段名保持中性。
