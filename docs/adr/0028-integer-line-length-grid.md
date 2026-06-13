# ADR 0028: 行长字号整数倍量化（grid-first 完整形态）

- Status: Accepted
- Date: 2026-06-13

## Context

ADR 0007 把「字格优先（grid-first）」定为项目排版哲学：中文正文应落在字号
构成的方格上。但此前引擎直接拿 `LayoutConstraints.maxWidth` 当版心——而
响应式 / 实际容器宽度几乎不会恰好是字号的整数倍（200px / 16px = 12.5 字）。
于是每行都靠 justify 的均匀字距把半个字的零头摊掉，正文并不真正落在字格上。

调用方也无法在排版前给出对齐字格的精确行长：容器宽度由布局系统/屏幕决定，
是排版的输入而非输出。所以「凑整」只能由引擎在拿到 maxWidth 之后做。

## Decision

`LineLengthGridQuantization`：引擎把容器宽度**向下取整**到字号的整数倍
（`N×fontSize`，N = ⌊maxWidth/fontSize⌋，至少 1 字）得到版心 `measure`，
所有行布局（禁则档解析、断行、justify、末行对齐）都以 `measure` 为准。
不足一字的余量 `slack = maxWidth − measure ∈ [0, fontSize)` 不进版心，而是
用来在容器内摆放**整块正文**。

`GridBodyAlignment`：整块正文在容器内的横向位置由 `bodyOffset` 给出，按
对齐值在 `slack` 上取 0 / slack÷2 / slack。该对齐**默认跟随**段落的末行
对齐（`ParagraphStyle.lastLineAlignment`，CLREQ 双齐正文唯一的对齐自由度
就是末行），也可在 `LineLengthGrid.bodyAlignment` 独立 override。`bodyOffset`
叠加进每行的 `LineBox.indent`（段首缩进/末行对齐之上），渲染与行间线几何
都照常消费 `indent`，无需改前端。

落为 `ParagraphStyle.lineLengthGrid: LineLengthGrid`：

```kotlin
data class LineLengthGrid(
    val enabled: Boolean = true,                 // 默认开：响应式下只能向下取整
    val bodyAlignment: LastLineAlignment? = null, // null = 跟随末行对齐
)
```

**默认开启**——「我们只能向下取整」是引擎在响应式下的常态，不是可选项；
grid-first 哲学也要求默认对齐字格。`enabled = false` 用于边缘情形：已知
精确像素行长、非中文正文、或调用方自己已对齐字格——此时直接用原始 maxWidth、
不取整、无 body 偏移。

## Consequences

- 容器宽度恰为字号整数倍时（fixture 240/320/…），`slack = 0`、`bodyOffset
  = 0`、`measure = maxWidth`，与旧行为完全一致——这些 golden 零漂移。
- 非整数倍的 fixture（220→208/13字、200→192/12字、100→96/6字、…）版心
  收窄到整字：纯汉字行此时**正好填满字格、justify 余量为 0**，inter-char
  均匀字距消失。这正是 grid-first 想要的——正文落在格上，而不是靠字距凑整。
  golden 已按此重生成。
- 决策可解释：`LineLengthGridDecisionInfo`（container/measure/cells/slack/
  bodyAlignment/bodyOffset/enabled/reason）入 dump，golden 与 playground 在
  `slack > 0` 时打印 `grid container=… measure=…(N字) slack=… body=…@…`。
- 单测里需要**精确像素行长**触发特定 deficit/断点的 justify/kinsoku 用例
  （maxWidth 非字号整数倍），改用 `enabled = false` 旁路——这正是旁路开关
  的用途，保留这些用例的原数；grid 行为另有专门单测覆盖（取整、body 偏移、
  override、旁路）。
- `LayoutResult.size.width` 仍为内容实测宽度 coerce 到容器（含 bodyOffset），
  语义不变。
- 竖排：取整与 body 偏移沿 inline 轴定义；竖排时 inline 轴变为纵向（block
  方向不变），`measure` 取整与 `bodyOffset` 概念照搬到纵向行长即可，未在此
  阶段实现。
