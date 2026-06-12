# ADR 0004: 标点空间的加法 glue 模型

- Status: Accepted
- Date: 2026-06-06

## Context

中文标点传统实现常用「减法模型」：把全角标点视为 1em 的 glyph，行尾再削掉一半、连续标点之间再削掉重叠。结果是规则散落、连续标点之间会出现 1em 空洞、justification 难以参与、调试无法解释。

更根本的问题：标点不是一个固定宽度的字符，而是 `ink + 周围空间`。空间是可调整的资源，应该被显式建模。

## Decision

每个标点显示为一个 `PunctuationAtom`，模型为加法：

```text
PunctuationAtom
  glyph
  advance          // 当前实际宽度
  inkBounds        // 真实墨迹
  bodyWidth        // 不可压缩的部分
  leadingGlue      // 前置可调空间 (natural / min / max)
  trailingGlue     // 后置可调空间 (natural / min / max)
  anchor           // line-start / line-end / mid / pair
  lineStartPolicy
  lineEndPolicy
  pairRules
```

由 `PunctuationAtomBuilder` 建出原子；`PunctuationSpacingCompressor` 负责 adjacent compression；`QuotePairAnalyzer` 负责引号成对感知，使开/闭引号的 glue 决策一致。

下游 justification 看到的是 `AdjustmentOpportunity`，优先级固定为：

```text
PunctuationGlue -> CjkLatinSpace -> WordSpace -> CjkInterChar
```

所有原子决策都进 `LayoutDebugInfo.punctuationDecisions` / `punctuationSpacingDecisions`，dump 中可逐条看到 `body / leading / trailing / anchor / reduction / reason`。

### Amendment (2026-06-10): PunctuationGlue 档的语义澄清

初版 Justifier 把 `PunctuationGlue` 实现为「把 `PunctuationSpacingCompressor`
压掉的量还回去」。这是错的：相邻标点收缩（`」。` `，「` → body 贴紧）是 CLREQ
的**硬规则**，不是弹性资源——两端对齐的行里 `」。` 被重新拉开，视觉上立即穿帮。

修正后的语义（`GlueSideAwareJustification`）：

- `PunctuationGlue` 档 = 在标点 atom 的 **glue 侧** 上做受限扩展
  （`。，、` 之后、`（「` 之前；anchor 的实心侧永不扩展，括号内侧因此天然免疫）。
- 被 spacing plan 收缩过的相邻标点边界**排除在外**，collapse 不可逆。
- 扩展 cap 取 `0.125em`（inter-char cap 的一半）：标点空白本来就有 0.5em，
  叠加 0.25em 会在视觉上形成「空了一格」的洞。
- `CjkInterChar` 档只在 **汉字 ↔ 汉字** 边界开口；标点相邻边界归
  `PunctuationGlue` 档管，避免同一空隙吃两份配额。
- `CjkLatinSpace` 档只在 ideograph ↔ alpha 边界开口（与 ADR 0009 autospace
  同一边界判定），且边界已有作者键入的 U+0020 时让位给未来的 `WordSpace` 档。

### Amendment (2026-06-11): 拉伸档对齐 CLREQ，标点空隙退出优先序

CLREQ 拉伸顺序（西文词距 → 中西间距 → 平均拉大字距）**不含**标点空隙档——
标点调整空间只参与挤压。上一条 amendment 引入的 tier-1
`PunctuationGlueFirstJustification`（标点 glue 侧优先扩 0.125em）随之删除：

- 拉伸链变为 `WordSpace → CjkLatinSpace → CjkInterChar`；
- 标点 glue 侧边界并入 `CjkInterChar`，与汉字边界**同 cap、同份额**
  （均匀加，无优先无额外）；
- `GlueSideAwareJustification` 的实心侧禁令与 collapse 不可逆原则不变；
- 已折叠/已削减的标点空白永不在拉伸中复原（用户原则 + CLREQ 一致）。

### Amendment (2026-06-12): CjkInterChar 限定双侧 CJK，末档去 cap

Review 发现两处与 CLREQ 的残余出入：

- **`CjkOnlyInterCharBoundary`**：CjkInterChar 准入原为「任一侧 CJK 且非
  汉字↔西文」，导致中文标点↔西文边界（`：The`、`dog（`）也按份额拉开——
  违反「中文标点与西文之间不加间距」（autospace 一侧遵守、justify 一侧
  违反的自相矛盾）。改为**两侧都必须是 CJK**（汉字或中文标点），该条件
  自然覆盖原来的 ideograph↔alpha 排除。
- **末档无上限**：CLREQ 的「平均拉大字距」是无上界的最后手段；原实现
  每边界 cap 0.25em，全部饱和后 deficit 剩余、两端对齐的行停在右边距
  之前——视觉上与「行尾空格未削」无法区分。改为均匀无 cap 兜底，对齐
  行必然填满。cap 以下行为不变（等容量比例分摊本就等于均摊）。

## Consequences

- 行尾标点「自然半宽」不是硬编码 `-= 0.5em`，而是 `lineEndPolicy + trailingGlue.min`。
- 连续标点之间不再出现 1em 空洞：相邻 atom 的 trailing/leading glue 通过 compression 合并。
- justification 参与时，glue 是天然资源，不需要拉开汉字间距即可吸收宽度差。
- 行首悬挂、连续标点挤压、引号上下文这类策略都可以拆成具名 heuristic，而不是 if-chain。

## Alternatives considered

- **减法模型 + 大量特例 if。** 否决：项目想避免的反例。
- **完全依赖 OpenType `chws / palt / halt`。** 部分接受：作为输入之一进入 `PunctuationAtomBuilder`，但字体支持不一致，不能作为唯一来源。
- **每个标点固定写一个宽度表。** 否决：失去 ink-aware 与 pair-aware 能力，且不利于竖排。

## Follow-up (Slice 3 收尾)

- `inkBounds` 当前来自占位实现；接入真实 shaping 后用 glyph ink box 校正。
- `pairRules` 当前仅 `QuotePairAnalyzer` 覆盖共用码点的弯引号（U+2018–201D）。ASCII `(` `)` `[` `]` `{` `}` 不属于共用码点（中文有独立的 fullwidth `（）「」『』`），直接在 `CjkFontRoleClassifier.isAsciiLatinPunctuation` 里分类为 Latin 即可，不需要 pair 推断。
- `anchor = line-end / line-start` 在引擎实现 Slice 4 (kinsoku) 后才真正被使用；当前 dump 已暴露，先做记账。
- 引号在嵌套场景（`他说：“你好‘世界’。”`) 的 pair 优先级需要 fixture。

## 跨 ADR

- 与 [ADR 0003](0003-prefer-clreq-recommended-codepoints.md) 协作：display 替换在前，atom 构造在替换后。
- 与 Slice 4/5（断行、justification）协作：atom 是 break candidate 和 adjustment opportunity 的数据来源。
