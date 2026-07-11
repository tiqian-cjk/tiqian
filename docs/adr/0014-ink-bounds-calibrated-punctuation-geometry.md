# ADR 0014: 标点 glue 方向由 profile 决定，ink bounds 约束压缩安全

- Status: Accepted (amended 2026-06-10, 2026-07-11)
- Date: 2026-06-07

## Context

ADR 0004 定了标点空间的加法模型：标点不是 `1em` 字符再做减法，而是
`ink + body + leadingGlue + trailingGlue`。

ADR 0013 接入 `AwtTextShaper` 后，`Glyph.bounds` 已经能提供真实 glyph visual bounds。
初版实现（已废弃）用 ink center 按比例分配 glue，并允许 ink width 撑大 body。
这等于把排版决策交给了字形的物理位置，违背了 CLREQ 对标点半宽的规定。

实际上，加法模型的基础量（名义半宽 body）应由 OpenType `halt` 等字体预设直接提供；
glue 方向不能由 ink center 猜。但 renderer 若仍绘制默认 glyph，压缩后的 body 也必须
容得下它的真实 ink；否则名义半宽会变成相邻字符重叠。2026-07-11 amendment 将这条
安全下限补进模型。

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

### Body 的规范目标为半宽

`bodyWidth = policyBodyWidth = defaultBodyEm * em`，不再做
基于 ink center 的任意扩展。这是 CLREQ 对半宽标点的规范目标；若默认 glyph 的实际
ink 无法装入目标 body，见 `InkContainmentBodyFloor` amendment。

### Ink bounds 不决定 glue 方向

`PunctuationAtom` 保留 `inkBounds`、`inkWidth`、`inkCenter` 字段；它们不参与
profile glue **方向**的决策。原始用途分两类：

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

`source` 字段还是字符串。（2026-06-10 更新：代码中的 `ClassDerivedWith*` 已
rename 为 `ProfileDerivedWith*`，与本节命名一致；另有 `FontHaltDerived*`
两档，见下方 amendment。）

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

### Amendment (2026-06-10): FontHaltDerivedBody 落地

`halt` 已经由 Skiko 路径接入（`FontHaltMeasurement`，ADR 0015）：shaper 对
CjkPunctuation cluster 额外跑一次 `halt=1` 的 feature-tagged pass，把测得的
alternate advance 与 placement 暴露为 `Glyph.haltAdvance` / `haltPlacementX`。
实测 Source Han Sans CN @16px：

| 类别 | halt advance | placement | 含义 |
|---|---|---|---|
| `。，、）」：！` | 8.0 | 0 | trailing 侧削半 |
| `（「《` | 8.0 | -8.0 | leading 侧削半 |
| `·` | 8.0 | -4.0 | 两侧各削 4（居中） |
| `— 中` | 16.0（无变体） | — | 不受影响 |

字体经 `halt` 独立证实了本 ADR 的 profile glue 方向表。消费规则：

- **body 来自字体**：`PunctuationAtomBuilder` 在 `haltAdvance < advance` 时用
  它替换 policy `0.5em` body（`FontHaltDerivedBody`）；glue 方向仍由 profile
  决定。
- **`HaltPlacementProfileCrossCheck`**：placement 推导出字体的削边侧
  （leading / trailing / both），与 profile glue 侧不一致时在
  `PunctuationAtom.haltValidation` / `PunctuationDecisionInfo.haltValidation`
  记 warning（如 `halt-trims-trailing-but-profile-glue-both`，Traditional
  profile 配大陆设计字体时触发）；几何决策不变，dump `punct:*` 行带
  `haltWarn=`。
- **feature 不参与渲染几何**：排版用的 cluster advance 仍来自无 feature 的
  shaping pass，空白的削减由 glue 模型显式执行——`halt` 只是度量入口。
- **`chws` 不启用**：相邻标点挤压是 engine 的具名决策
  （`CollapseAdjacentPunctuationInnerGlue`），交给字体做会双重压缩且不可解释。
- geometry source 新增 `FontHaltDerived` / `FontHaltDerivedWithInkDiagnostics`，
  AWT / stub 路径无 halt 能力，自然降级到 `ClassDerived*`（跨引擎分歧已记录）。

### Amendment (2026-07-11): 上下文中文引号的 underwidth glyph

真实 Web 字体暴露出“CJK role 已判对，但 glyph 仍是西文比例宽度”的独立情况。
以 MiSans VF 为例，U+201C/U+201D 有 cmap 覆盖，却只有约 `0.378em` advance；
`locl` / `fwid` 在该字体上都不产生一字宽引号。仅把 quote pair 分类成
`CjkPunctuation` 并不能自动得到中文占位，反而会让标点 atom 缩成字体给出的窄宽。

新增两条具名规则：

- **`UnderwidthPunctuationAdvanceExpansion`**：只有进入 `CjkPunctuation` 几何的
  标点，shaped advance 小于 profile `defaultAdvanceEm` 时，layout advance 补到
  profile 下限；更宽的真实 shaping 仍然有效。英文上下文 quote pair 已由
  `QuotePairAnalyzer` 判为 `LatinText`，不会进入该规则。
- **`ProfileAnchoredUnderwidthGlyphShift`**：不拉伸字形。按 profile 的
  `PunctuationAnchor` 把比例 glyph 的 advance box 居中放进不可压 body，再把 body
  放到开引号的 trailing 侧、闭引号的 leading 侧或对称类中央。结果写入
  `Cluster.glyphInlineShift`，所有 renderer 只消费统一 `PositionedCluster.drawX`，
  不在前端重新识别引号。

这不是用 ink bounds 改写 body/glue；body 与 glue 仍完全由 profile / `halt` 决定。
它补的是“字形小于既定 body/advance”时缺失的 glyph origin。行首/行尾消费 glue、
相邻标点压缩和 justification 之后仍复用同一 shift，因此不会另外发明一套 Web 间距。

### Amendment (2026-07-11): `InkContainmentBodyFloor`

真实 Web dogfood 暴露了相反方向的问题：书名号乙式 `《》` 的默认 glyph ink 可能略宽于
`0.5em`。引擎把名义半字之外的 glue 全部消费后，DOM 仍绘制默认 glyph；负
`letter-spacing` 只缩 advance，不会缩墨迹，结果书名号侵入后一个汉字。

新增 `InkContainmentBodyFloor`。它不从 ink center 推导风格，只按已经确定的
`PunctuationAnchor` 计算“全部 glue 被消费后仍能容纳默认 glyph”的最小 body：

- `Leading`（闭标点）：`floor = ink.right`；
- `Trailing`（开标点）：`floor = glyphAdvance - ink.left`；
- `Center`：取两侧完全压缩时所需 floor 的较大值。

上述 anchored floor 还必须与 `ink.width` 取较大值；任何 placement 都不可能把更宽的
墨迹塞进更窄的 body。通常 glyph ink 位于自身 advance 内，body floor 就足够；若斜体或
synthetic slant 让 ink 越出 glyph advance，单纯加宽 body 仍无法修正锚定侧越界。此时具名
`InkContainmentGlyphShift` 把既有 profile placement 限制在最终 body 的可行区间内，shift
与 body floor 一起进入 punctuation / cluster geometry dump。renderer 仍只消费统一的
`PositionedCluster.drawX`，不自行判断码点或墨迹。

最终 `bodyWidth = max(policy/halt body, ink containment floor)`；glue 仍按 profile 放在
leading / trailing / both。普通字体能把墨迹装进半字时结果完全不变；不能时只减少可压缩
glue。开明式/GB 固定半宽同样受此安全下限约束：宁可诚实地多占一点，也不能让 glyph
重叠。缺少 ink bounds 时记录 `MissingInkBoundsFallback`，继续走 policy/halt 目标。

## Consequences

- 标点 body 以半宽为规范目标；真实默认 glyph 装不下时由
  `InkContainmentBodyFloor` 扩到最小安全宽度。glue 方向仍只由 CLREQ profile 决定。
- 行尾闭标点的 trailing glue 为 0.5em（8px @16px），edge trim 吃掉后变半宽——比旧模型（trim 4px）效果更正确。
- 相邻标点压缩量不变（仍是 0.5em → 0.25em），但 reduction target 从右侧标点改为有 glue 的一侧。
- Ink bounds 不改变风格方向，只限制会造成墨迹重叠的压缩容量；决定与 floor 一并进入 dump。
- `halt` 接入后将直接替换 policy advance/body，ink bounds 作为验证手段。
- 比例宽 U+2018..U+201D 在中文上下文中保持源码字形，但占位与开闭锚点符合 profile；
  同码点的英文 quote pair 保持西文比例宽度。

## Follow-up

- OpenType `halt` / `chws` 接入后，替换 policy body/advance 为字体预设值。
- Ink bounds 用于自动验证 `halt` 输出是否合理（如果 ink 不在预期侧则发出警告）。
- Android / Skia adapter 接入后复核同一批标点的 body/glue 差异。
