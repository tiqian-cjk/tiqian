# ADR 0014: 标点压缩几何由字体 `halt` / ink bounds 决定

- Status: Accepted (amended 2026-06-10, 2026-07-11, 2026-08-06, 2026-08-12)
- Date: 2026-06-07

## Context

ADR 0004 定了标点空间的加法模型：标点空间按
`ink + body + leadingGlue + trailingGlue` 相加计算，不从 `1em` 字符做减法。

> 2026-08-06 的修订取代本文早期“profile 决定 glue 方向”以及
> `ProfileAnchoredUnderwidthGlyphShift` / `InkContainmentGlyphShift` 的当前行为。
> 这些旧段落只保留为决策演变记录，当前规格以下方最新 amendment 为准。

ADR 0013 接入 `AwtTextShaper` 后，`Glyph.bounds` 已经能提供实际 glyph visual bounds。
初版实现（已废弃）用 ink center 按比例分配 glue，并允许 ink width 撑大 body。
这等于把排版决策交给了字形的物理位置，违背了 CLREQ 对标点半宽的规定。

加法模型的基础量（名义半宽 body）应由 OpenType `halt` 等字体预设直接提供；
glue 方向不能由 ink center 猜。但 renderer 若仍绘制默认 glyph，压缩后的 body 也必须
容得下它的实际 ink；否则名义半宽会变成相邻字符重叠。2026-07-11 amendment 将这条
安全下限补进模型。

## Decision

### Glue 方向由 profile 决定（三个方向）

命名启发式：`ProfileDerivedGlueDirection`。CLREQ 3.1.3
（Punctuation Position）按 region 给出的 placement 共**三**种：

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
trim 后视觉位置不变，这与铅字时代繁体「正中」习惯一致。

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
   接入实际 shaping 后）发现 ink 偏离 profile 期望位置时，会用 `inkCenter`
   把 glyph 平移到正确侧。这种「字形偏移」是渲染补丁，**不是**排版决策；
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

### Amendment (2026-06-10): FontHaltDerivedBody 实现

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
  shaping pass，空白的削减由 glue 模型显式执行；`halt` 只是度量入口。
- **`chws` 不启用**：相邻标点挤压是 engine 的具名决策
  （`CollapseAdjacentPunctuationInnerGlue`），交给字体做会双重压缩且不可解释。
- geometry source 新增 `FontHaltDerived` / `FontHaltDerivedWithInkDiagnostics`，
  AWT / stub 路径无 halt 能力，自然降级到 `ClassDerived*`（跨引擎分歧已记录）。

### Amendment (2026-07-11): 上下文中文引号的 underwidth glyph

实际 Web 字体暴露出“CJK role 已判对，但 glyph 仍是西文比例宽度”的独立情况。
以 MiSans VF 为例，U+201C/U+201D 有 cmap 覆盖，却只有约 `0.378em` advance；
`locl` / `fwid` 在该字体上都不产生一字宽引号。仅把 quote pair 分类成
`CjkPunctuation` 并不能自动得到中文占位，反而会让标点 atom 缩成字体给出的窄宽。

新增两条具名规则：

- **`UnderwidthPunctuationAdvanceExpansion`**：只有进入 `CjkPunctuation` 几何的
  标点，shaped advance 小于 profile `defaultAdvanceEm` 时，layout advance 补到
  profile 下限；更宽的实际 shaping 仍然有效。英文上下文 quote pair 已由
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

实际 Web dogfood 暴露了相反方向的问题：书名号乙式 `《》` 的默认 glyph ink 可能略宽于
`0.5em`。引擎把名义半字之外的 glue 全部消费后，DOM 仍绘制默认 glyph；负
`letter-spacing` 只缩 advance，不会缩墨迹，结果书名号侵入后一个汉字。

新增 `InkContainmentBodyFloor`。它不从 ink center 推导风格，只按已经确定的
`PunctuationAnchor` 计算“全部 glue 被消费后仍能容纳默认 glyph”的最小 body：

- `Leading`（闭标点）：`floor = ink.right`；
- `Trailing`（开标点）：`floor = glyphAdvance - ink.left`；
- `Center`：取两侧完全压缩时所需 floor 的较大值。

上述 anchored floor 还必须与 `ink.width` 取较大值；任何 placement 都不可能把更宽的
墨迹装进更窄的 body。通常 glyph ink 位于自身 advance 内，body floor 就足够；若斜体或
synthetic slant 让 ink 越出 glyph advance，单纯加宽 body 仍无法修正锚定侧越界。此时具名
`InkContainmentGlyphShift` 把既有 profile placement 限制在最终 body 的可行区间内，shift
与 body floor 一起进入 punctuation / cluster geometry dump。renderer 仍只消费统一的
`PositionedCluster.drawX`，不自行判断码点或墨迹。

最终 `bodyWidth = max(policy/halt body, ink containment floor)`；glue 仍按 profile 放在
leading / trailing / both。普通字体能把墨迹装进半字时结果完全不变；不能时只减少可压缩
glue。开明式/GB 固定半宽同样受此安全下限约束：宁可诚实地多占一点，也不能让 glyph
重叠。缺少 ink bounds 时记录 `MissingInkBoundsFallback`，继续走 policy/halt 目标。

### Amendment (2026-08-06): 字体拟合框决定压缩方向，不重定位墨迹

真字体证据否定了“region/profile 可以替字体决定墨迹位于哪一侧”的前提：早期微软雅黑的
逗号、冒号、问号等可以居中，而句号、顿号又位于左下；方正黑体的全角括号也是居中设计。
差异发生在单个 glyph 层面，不能按地区、字体系列或标点类别统一猜测。

当前证据优先级为：

1. **`halt` advance + placement**：`FontHaltFittedBodyCompression` 直接把字体给出的
   placement 还原为 leading/trailing 削边量。因为 renderer 回放默认 glyph，默认 glyph
   的 ink bounds 仍是安全上限；若 `halt` 会削进默认墨迹，则减少对应侧压缩并记录
   `halt-trim-limited-by-default-ink-bounds`。
2. **ink bounds**：没有完整 `halt` placement 时，使用
   `InkBoundsFittedBodyCompression`。设自然 advance 为 `A`、规范目标 body 为 `W`、
   ink 横向范围为 `[L, R]`，分别求能够容纳原墨迹的三个规范框：
   - 左框：`start = 0`，`width = max(W, R)`；
   - 居中框：`width = max(W, A - 2L, 2R - A)`，`start = (A - width) / 2`；
   - 右框：`width = max(W, A - L)`，`start = A - width`。
   三者均限制在自然 advance 内；先选 width 最小者，同宽时选框中心最接近 ink center
   的一项。最终 `leadingGlue = start`，`trailingGlue = A - start - width`。
3. **无字体几何**：只有 shaper 不能提供上述证据时，才走具名
   `ProfileGlueFallbackWithoutFontGeometry`。这不是正常真字体路径。

“容纳原墨迹”也包括保留目标框内部的安全边距。例如左下角句号的墨迹完整落在左侧半字框
时，leading glue 必须为 0，只削右侧框外空白；不能因为左侧仍有少量 sidebearing 就按比例
扣除它。居中括号若完整落在居中半字框，则两侧各削四分之一字。若任何半字框都装不下，
body 只扩到能容纳原墨迹的最小规范框，不通过额外 glyph shift 强行放入。

中文上下文的 U+2018..U+201D 先以 `CjkContextCurlyQuoteFullWidthVariant` 请求字体 `fwid`。
若 shaping 仍返回比例 advance（MiSans VF 4.003 的双引号为 0.382em、单引号为 0.248em，
且 `fwid` 不改变它们），`UnderwidthPunctuationFullWidthBoxPlacement` 才补齐缺失的全宽字身：
开标点把新增空间放在比例 glyph box 之前，闭标点放在之后，居中 convention 均分。
这里移动的是整个字体比例盒，盒内 advance、ink 与安全边距不变；随后 `halt` / ink 压缩
面对的是已经完成的全宽标点，不存在把比例字形一律向尾侧补宽的情况。

标点 builder 不再产生旧的 `ProfileAnchoredUnderwidthGlyphShift`、
`InkContainmentGlyphShift` 或 `ForcedHalfWidthGlyphAnchorShift`。消费 leading glue 时 `drawX`
随已删除的 leading 空白等量变化，这是压缩框的坐标结果，也不是在字体盒内重定位墨迹。

开明式与 GB 固定半宽使用同一字体拟合框，并在断行前把该框外的 glue 标为已消费；因此它们
仍是固定宽度、不给 PushIn 二次借用，同时不需要 renderer 侧位移。

## Consequences

- 标点 body 以半宽为规范目标；实际默认 glyph 装不下时扩到最小字体拟合框。
  glue 方向来自 `halt` placement 或逐 glyph ink bounds，不再由 profile 覆盖真字体几何。
- 行尾闭标点只消费字体证据判定为框外的 trailing glue；没有字体几何时，profile fallback
  才沿用 0.5em（8px @16px）的单侧预算。
- 相邻标点压缩量不变（仍是 0.5em → 0.25em），但 reduction target 从右侧标点改为有 glue 的一侧。
- Ink bounds 同时决定压缩方向和安全容量；选中的框、glue、body 与 halt 限制进入 dump。
- `halt` 同时提供目标 advance 与 placement；只有缺 placement 时才由 ink bounds 补方向。
- 字体拟合框选中 `Center` 时，左右 glue 是一个成对预算。相邻标点压缩、PushIn、
  行首/行尾削减都必须同时等量消费两侧；后续阶段不得再按 `PauseOrStop` 等字符类别
  把它降回单侧预算。左框和右框仍只消费各自实际存在的一侧空白。
- 比例宽 U+2018..U+201D 在中文上下文中先请求字体全宽 variant；缺失时把完整比例 glyph box
  放进语义正确的全宽字身，再由同一压缩模型处理；
  同码点的英文 quote pair 保持西文比例宽度。

## Follow-up

- 收集更多 OEM / 桌面字体的逐 glyph `halt`、advance 与 ink bounds 证据，扩充跨字体 fixture。
- `chws` 仍不直接启用；相邻标点挤压继续由可解释的 glue ledger 负责。
