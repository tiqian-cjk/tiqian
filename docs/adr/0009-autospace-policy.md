# ADR 0009: AutoSpacePolicy（按 CSS Text 4 模型处理中西/数字边界与 typed 空格）

- Status: Accepted
- Date: 2026-06-06

## Context

[real-text-fixture-1 观察 #1](../research/real-text-fixture-1.md) 暴露了一个之前没被任何 fixture 触发的问题：用户键入的 U+0020 SPACE 当前在 `CjkFontRoleClassifier` 里依次被所有码点判定漏掉，最终落到 `FontRole.Unknown` → `symbol-fallback` 字体；同时 `FontMetricsNormalizer` 把 Unknown role 当作 raw passthrough，导致段落里**任何**含空格的真实文本——也就是几乎所有正文——`maxAscent` 都被空格 cluster 拉到 14.4 px，line-height 假性扩大。

「修空格」单看是一个 30 行的改动；但它真正问的是 CJK-Latin 边界该怎么处理这件事，已经不只是 classifier 缺一条规则，而是整个项目的「中西文之间到底有没有空隙、谁决定、谁渲染」的语义问题。

参考输入：

- [CSS Text Module Level 4 — `text-autospace`](https://drafts.csswg.org/css-text-4/#text-autospace-property)
- [CSS Text Module Level 4 — `text-spacing-trim`](https://drafts.csswg.org/css-text-4/#text-spacing-trim-property)
- 用户原话：「应该遵循 css 里的 text auto space 的模样，可以按字符集切换并且可以设置为 replace」

CSS Text 4 的心智模型：在 ideograph ↔ alpha、ideograph ↔ numeric 等 script-pair 边界上自动插入一个可配置的「autospace 间隙」（约 1/4 em）；当作者本来就键入了 U+0020 时，autospace 不应该额外加，而应该**替换**（Replace）这个 typed space——否则会变成 1 em（typed）+ 0.25 em（autospace）= 1.25 em 的双层间距。一些工作流（数据回流、可编辑文本）需要 typed space 在 source 里 round-trip，这时改用 Insert 语义。

## Decision

把空格处理从「FontRoleClassifier 漏一类」抬到 profile 级别，按 CSS Text 4 的形态建模：

```kotlin
data class AutoSpacePolicy(
    val cjkLatin: AutoSpaceMode = AutoSpaceMode.Replace,
    val cjkDigit: AutoSpaceMode = AutoSpaceMode.Replace,
    val gapEm: Float = 0.25f,
)

enum class AutoSpaceMode {
    Disabled,
    Replace,
    Insert,    // 暂未实现（需虚拟 cluster 注入）
}

ClreqProfile(..., autoSpace = AutoSpacePolicy.Default)
```

具体语义：

1. **U+0020 SPACE 归类为 `LatinText`**（[`CjkFontRoleClassifier.isAsciiLatinPunctuation`](../../font/src/commonMain/kotlin/org/tiqian/font/FontPolicy.kt) 扩展）。它进入 Latin run，跟相邻 Latin 字符聚合成一个 cluster。
2. **Cluster 阶段后，按 `policy.cjkLatin` 处理边界 typed space**（[`ParagraphLayoutEngine.applyAutoSpacePolicy`](../../layout/src/commonMain/kotlin/org/tiqian/layout/ParagraphLayoutEngine.kt)，命名 heuristic `TextAutoSpaceReplace`）：
   - 一个 Latin cluster 的**前导**空格数 × (1em - gapEm)，从该 cluster 的 advance 减掉，前提是它的左邻 cluster 是 `CjkText` 或 `CjkPunctuation`。
   - **后置**空格数同理，看右邻。
   - Latin 内部空格（如 `Hello world` 的词间）不动——它们不在 CJK 边界上。
3. **每次缩减生成结构化 `AutoSpaceDecisionInfo`** 进 `LayoutDebugInfo.autoSpaceDecisions`，含 `clusterRange / side / boundaryRole / mode / charactersAffected / reductionPerChar / totalReduction / reason`。可解释。
4. **`policy.cjkLatin = Disabled`**：space 保留 1em advance（典型 stub 渲染），不产生 decision 条目。
5. **`policy.cjkLatin = Insert`** 留接口未实现：需要虚拟 cluster 注入（typed space 留 1em，再插入 0.25em autospace），跟当前「cluster 必须连续覆盖 source range」的契约冲突，留 Slice 6+ 配合 shaping adapter 一起处理。
6. **Justifier 的 `CjkLatinSpace` priority**（[ADR 0005 / ADR 0004 priority chain](0004-punctuation-additive-glue-model.md)）保留不变。Replace 模式下 typed space 已经吸收到 gapEm 上限，justifier 只在该 cluster 还有 stretch capacity 时再加（未来 follow-up：让 justifier 知道哪些 Latin cluster 是 autospace-shrunk，以避免双账）。

### Amendment (2026-06-11): Insert 落地并成为默认

CLREQ 原文「原则上，汉字与西文字母、数字间使用不多于四分之一个汉字宽的字距
或空白」不以作者键入空格为前提。`AutoSpaceMode.Insert` 实现为 Replace 的
超集并成为 profile 默认：

- 有 typed space 的边界照旧 `TextAutoSpaceReplace`（n-to-one 归一）；
- 无 typed space 的 ideograph↔alpha 边界增加 `gapEm` 间距
  （`TextAutoSpaceInsert`，decision 记负向 reduction，cluster advance 加宽，
  渲染层按 side decision 画 gap）；
- 行边仍无间距（`TextAutoSpaceLineEdgeTrim` 同样适用于 Insert 边界）；
- decision 的 `mode` 字段记录边界上的实际动作（Replace/Insert），而非
  profile 枚举值。
- justify 的 `CjkLatinSpace` 档自此有了真实基础间距可拉伸：1/4em 起、
  上限 +1/4em（合计 1/2em，恰为 CLREQ 上限）。

## Consequences

- **Line-height 立刻收紧**：空格不再以 Unknown role 进入 `metricDecisions.lineMetrics`，paragraph maxAscent 从 14.4 (Symbol fallback) 回到 12.8 (Latin)。real-paragraph-1 测试段落 12 行总高 268.8 → 249.6。
- **行宽收紧**：每个 CJK ↔ Latin 边界 typed space 从 16px 降到 4px。real-paragraph-1 visual-sum 3656 → 3620 px（14 个空格，部分在边界）。
- **测试断言变化**：`"Hello" world` 现在聚成单个 Latin cluster 而非两个；`keepsTextStartLatinQuotePairInLatinRun` 等基于「空格切 cluster」的测试需要重写以适应新聚合。
- **profile-driven**：CJK / CSS-style / region-specific 工作流可以独立设置 `gapEm`、`cjkLatin`、`cjkDigit` 三档。`Disabled` 模式保留给「CJK 全部按 typed」的怀旧/调试场景。
- **跟 Justifier 的 `CjkLatinSpace` 没有立即冲突**：但需要 follow-up 跟踪——目前 justifier 仍按 0.25em 容量在 CJK-Latin 边界上加 glue；如果该边界 cluster 已被 autospace 处理过，理论上 stretch capacity 应基于「max gap」而非「nominal 1em」。在 stub 状态下数字凑巧合理，真实 shaping 接上后再校准。

## Alternatives considered

- **新建 `FontRole.Space` 作为独立第 8 个 role**。否决：空格在多数排版语境下属于 Latin run（甚至 CJK 内部空格也应进入文本的 Latin 风格），单列 role 会让 cluster aggregation、justifier、metric normalization 三处都要加 case。CSS Text 4 也没把 space 当独立 script，把它当成 Latin run 的一部分加上 autospace 后处理更贴标准。
- **把空格当作 punctuation atom，借用 `PunctuationSpacingCompressor`**。否决：空格不是 ink-bearing punctuation，跟 atom 的 body/ink/glue 模型语义不符。Atom 是「标点字面 + 周围空隙」，space 是「无字面的纯空隙」——结构性分隔符，不是 atom。
- **跟随 Compose / Android 现有 BreakIterator 默认行为**。否决：平台默认要么忽略 CJK 内部空格（Android），要么按 Latin word break 处理（Compose）。两个都不是 CLREQ profile 想要的，且都不暴露 typed space 的 Replace 语义。
- **完全模拟 CSS `text-autospace` 全部子值（normal / no-autospace / ideograph-alpha / ideograph-numeric / punctuation / replace / insert）**。暂缓：本 slice 只落 `cjkLatin` + `cjkDigit` 两个 boundary 和 `Disabled` / `Replace` 两个 mode。`punctuation` 与 fullwidth 标点的边界微调留给 Slice 6（接 ink bounds 后才有可信数据）。

## Follow-up

- `Insert` 模式：等虚拟 cluster 注入或 `ClusterPart` 概念落地后实现。
- Justifier 跟 autospace 的协调：当 Latin cluster 已经被 autospace 缩窄后，`CjkLatinSpace` priority 的 stretch 上限应基于 `(1em - gapEm)` 还原，而不是从 0 累计。当前 stub 数字凑巧 OK，接真实 shaping 时校准。
- 数字边界：`cjkDigit` 已经在 policy 里了但 `applyAutoSpacePolicy` 暂时只看 `cjkLatin`（因为 stub classifier 把 ASCII 数字归 LatinText，跟字母无差别）。等数字有独立 role 或独立 metric class 时再启用。
- `text-spacing-trim`（fullwidth 标点行首/行末/段首边界裁剪）是 CSS Text 4 的姊妹属性，但跟 [ADR 0006 hanging](0006-hanging-punctuation-opt-in.md) / 行尾半宽紧密耦合，单独 ADR 处理。

## Amendment (2026-07): 间距预设 Default (1/8–1/3) / Clreq (1/4–1/2)

CLREQ 要求中西间距四分之一至二分之一字宽,但主流实现(iOS、Chrome 的
`text-autospace`)收敛在 **1/8 字宽**,屏幕观感也确实更好(用户判断)。
CLREQ 自己的注②也记录了「很多排版风格在实际处理上,只允许最大拉伸到
三分之一汉字宽」——1/3 的拉伸上限并不违背原文。

决定:

- `AutoSpacePolicy` 携带**一对**宽度:`gapEm`(基准)+ `stretchMaxEm`
  (justify 拉伸上限,final width)。两个预设:
  - **`AutoSpacePolicy.Default`** = 1/8 基准、1/3 上限(实践收敛值,默认);
  - **`AutoSpacePolicy.Clreq`** = 1/4 基准、1/2 上限(CLREQ 字面)。
- `AdjustmentStylePolicy.sinoWesternStretchMaxEm` **删除**(预发布不留包袱)
  ——拉伸上限随基准一起属于间距策略,移入 `AutoSpacePolicy.stretchMaxEm`;
  `allowSinoWesternGapAdjustment`(是否允许拉伸)留在调整风格里。
- `Justifier` 的 `cjkLatinSpaceBaseEm` 从构造字段改为 `justify()` 必填参数,
  与 `cjkLatinSpaceMaxEm` 一样由引擎从 profile 传入——消灭「同一数字在
  profile 与 Justifier 各存一份」的漂移面。
- 引擎/几何层不再硬编码 `0.25f * fontSize`:每条 `AutoSpaceDecisionInfo`
  记录应用的 `gapPx`,`positionedClusters` 等几何查询读决策值。
