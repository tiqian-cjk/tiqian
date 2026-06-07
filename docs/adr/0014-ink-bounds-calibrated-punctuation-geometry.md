# ADR 0014: 标点 glue 方向由类别决定，ink bounds 仅作诊断

- Status: Accepted (amended 2026-06-07)
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

### Glue 方向由标点类别决定

命名启发式：`ClassDerivedGlueDirection`。

- **开标点**（`「（《〈『` 等 `Opening`）：body 靠 trailing，glue 全部在 leading。
- **闭标点 / 停顿**（`」）。，、；：！？` 等 `Closing` / `PauseOrStop`）：body 靠 leading，glue 全部在 trailing。
- **对称标点**（`·、⸺、……` 等 `MiddleDot` / `Dash` / `Ellipsis`）：glue 对称分配两侧。

这保证了行尾闭标点 trim trailing glue 即变半宽，行首开标点 trim leading glue
即变半宽，不依赖字形物理位置。

### Body 始终为半宽

`bodyWidth = policyBodyWidth = defaultBodyEm * em`，不再做
`max(policyBody, inkWidth)` 扩展。这是 CLREQ 对半宽标点的核心语义。

### Ink bounds 仅作诊断

`PunctuationAtom` 仍保留 `inkBounds`、`inkWidth`、`inkCenter` 字段，但它们
**不参与** glue 分配或 body 计算。这些字段用于：

1. Playground dump / HTML 报告中可视化墨迹位置。
2. 未来验证 `halt` 输出与 ink 是否一致。
3. 作为将来 hanging punctuation 悬挂量计算的输入（ADR 0006 推后）。

### Geometry source 命名

- `ClassDerivedWithInkDiagnostics` — 有 shaped advance 且有 ink bounds（诊断可用）。
- `ClassDerivedWithShapedAdvance` — 有 shaped advance，无 ink bounds。
- `PolicyDerived` — 无 shaping 信息，纯 policy。

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
