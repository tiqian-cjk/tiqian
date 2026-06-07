# ADR 0014: 标点 glue 方向由 profile 决定，ink bounds 仅作辅助

- Status: Accepted (amended twice 2026-06-07)
- Date: 2026-06-07

## Context

ADR 0004 定了标点空间的加法模型：标点不是 `1em` 字符再做减法，而是
`ink + body + leadingGlue + trailingGlue`。

ADR 0013 接入 `AwtTextShaper` 后，`Glyph.bounds` 已经能提供真实 glyph visual bounds。
初版实现（已废弃）用 ink center 按比例分配 glue，并允许 ink width 撑大 body。
这等于把排版决策交给了字形的物理位置，违背了 CLREQ 对标点半宽的规定。

实际上，加法模型的基础量（半宽 body）应由 OpenType `halt` 等字体预设直接提供；
在 `halt` 不可用时，ink bounds 仅用于判断墨迹在哪一侧、辅助确认「削成半宽」
的方向是否正确。Body 始终是半宽（0.5em），不因 ink 扩大。

## Decision

### Glue 方向由 profile 决定（三个方向）

命名启发式：`ProfileDerivedGlueDirection`。CLREQ 3.1.3
（Punctuation Position）按 region 给出**三**种 placement，不是两种：

| Profile | Opening | Closing / PauseOrStop | 对称类 |
|---|---|---|---|
| MainlandSimplified（简体）| `LeadingOnly` (body 靠 trailing) | `TrailingOnly` (body 靠 leading) | `BothSides` |
| Traditional（台湾 / 香港）| `BothSides` | `BothSides`（句号 / 逗号居中央） | `BothSides` |

实现以 `PunctuationGluePlacement` enum + `glueSideFor(class)` 表达，由
`ClreqProfile.gluePlacement` 默认 `forRegion(region)` 拿到，调用方可
override。`PunctuationAtomBuilder.build(..., gluePlacement)` 接收 placement，
不再硬编码 Mainland 风格。

行尾闭标点 trim trailing glue 在 MainlandSimplified 下即变半宽，行首开标点
trim leading glue 即变半宽；Traditional 下两侧都缩、本来就居中，所以行边
trim 后视觉位置不变——这跟铅字时代繁体「正中」习惯一致。

### Body 始终为半宽

`bodyWidth = policyBodyWidth = defaultBodyEm * em`，不再做
`max(policyBody, inkWidth)` 扩展。这是 CLREQ 对半宽标点的核心语义。

### Ink bounds 仅作辅助：诊断 + 低质字体校正

`PunctuationAtom` 保留 `inkBounds`、`inkWidth`、`inkCenter` 字段，但它们
**不参与** body 计算和 glue 分配的决策路径。它们的用途分两类：

1. **诊断 / 验证**：playground dump 中可视化墨迹位置；`halt` 接入后用来
   校验字体输出是否合理；将来 hanging 悬挂量计算（ADR 0006）的输入。
2. **低质字体的渲染层校正**：有些字体（早期微软雅黑、部分方正字体）
   把所有标点 ink 居中，无论 region 应该是什么。**排版决策仍然按 profile**
   （MainlandSimplified 下 `。` 仍然 trailing-only glue）；但渲染层（Slice 6
   接入真实 shaping 后）发现 ink 偏离 profile 期望位置时，会用 `inkCenter`
   把 glyph 平移到正确侧。这种「字形偏移」是渲染补丁，**不是**排版决策——
   `cluster.advance / bodyWidth / leadingGlue / trailingGlue` 都不变。

`halt` 接入后 ink bounds 还能反向校验：如果 `halt` 给出的 advance 跟 ink
中心位置不匹配（比如 `halt` 说半宽但 ink 在 1em 中央），可以记入诊断 warning。

### Geometry source 命名

- `ProfileDerivedWithInkDiagnostics` — profile + shaped advance + ink bounds（诊断可用）。
- `ProfileDerivedWithShapedAdvance` — profile + shaped advance，无 ink bounds。
- `PolicyDerived` — profile + 无 shaping 信息，纯 policy（stub 路径）。

`source` 字段还是字符串，旧的 `ClassDerived*` 名字代码里暂时仍叫
`ClassDerivedWith*`；rename 跟着 `gluePlacement` 接入的 follow-up PR 一起做，
不影响现有结构化 debug 消费。

### 压缩算法修正

`PunctuationSpacingCompressor` 改为 `naturalInnerGlue / 2` 而非
`max(left.trailing, right.leading)`。单侧 glue 模型下旧公式会导致
inner glue = 8 + 0 = 8, max(8, 0) = 8, reduction = 0 的错误。

`consumeSpacingAdjustments` 改为根据 budget 的 remaining capacity 选择消费
trailing 或 leading（不再硬编码只消费 leading）。

### Anchor

`PunctuationAnchor` 现在跟随类别：

- `Opening` → `Trailing`（body 锚定在右侧）
- `Closing` / `PauseOrStop` → `Leading`（body 锚定在左侧）
- 其他 → `Center`

## Consequences

- 标点 body 始终半宽，glue 方向由 CLREQ 规则而非字形物理位置决定。
- 行尾闭标点的 trailing glue 为 0.5em（8px @16px），edge trim 吃掉后变半宽——比旧模型（trim 4px）效果更正确。
- 相邻标点压缩量不变（仍是 0.5em → 0.25em），但 reduction target 从右侧标点改为有 glue 的一侧。
- Ink bounds 的诊断价值保留，但不再影响排版决策，消除了字体差异导致 glue 不稳定的风险。
- `halt` 接入后将直接替换 policy advance/body，ink bounds 作为验证手段。

## Follow-up

- OpenType `halt` / `chws` 接入后，替换 policy body/advance 为字体预设值。
- Ink bounds 用于自动验证 `halt` 输出是否合理（如果 ink 不在预期侧则发出警告）。
- Android / Skia adapter 接入后复核同一批标点的 body/glue 差异。
