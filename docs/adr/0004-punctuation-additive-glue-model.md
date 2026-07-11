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
- **末档是均匀 tracking，不做 glue 侧/折叠排除**（同日复审第二轮，
  用户拍板「除西文字母间距外所有都要参与」）：平均拉大字距对**每一个**
  CJK↔CJK 边界同份额加空——标点实心侧（`“|好`、`喝|。`、括号内侧）与
  已折叠的相邻标点对（`。”`）一并参与。被削减/折叠的空白依旧**不优先
  补齐**（consumed 不回退），拿到的只是和大家相同的均匀份额——即此前
  缺口 3 讨论的原意「加空白也是跟其他一样尽量均匀地加」。
  `GlueSideAwareJustification` 的拉伸侧禁令随之退役（它本是配合已删除
  的标点优先档的非对称扩张设计）；压缩侧的 glue 模型不受影响。

### Amendment (2026-06-25): 原子长标号边界不参与 CjkInterChar

知乎正文 dogfood 暴露出另一条边界：破折号 `——` 已按 CLREQ display
substitution 合成 `⸺`，但 justify 末档仍把其右侧边界当普通
`CjkInterChar`，视觉上变成 `—— 不`。这不是 source 空格，也不是字体缺字
回滚，而是两端对齐阶段制造的假空隙。

决议：

- `NoStretchBoundaryClusters` 覆盖 Connector / Solidus / Dash / Ellipsis。
  连接号、分隔号来自 CLREQ 明示限制；破折号、省略号来自项目的原子长标号
  模型。
- 破折号、省略号仍是一个 source-preserving display cluster：source range
  保留原输入，display text 可替换为 CLREQ 推荐码点，但前后边界不作为均匀
  tracking 机会。
- 普通标点（括号内侧、点号前后、标点↔西文）仍按 2026-06-12/16 amendment
  参与末档均匀 tracking；这次限制只针对不可拆长标号，避免把长标号误读成
  “后面多了一个空格”。

### Amendment (2026-07-10): 西文主导视觉行不进入 CjkInterChar

Web 正文 dogfood 在移动行宽暴露出 `Rust（Winio）、Rust（windows-reactor）`
一类技术名称：视觉行内没有汉字正文，只有西文与中文标点；若仅凭中文标点
进入无上限 `CjkInterChar`，括号和顿号两侧会被各拉开约半个字，读起来像
source 中存在空格。

新增具名 fallback `WesternDominantLineNaturalSpacing`：

- 判定范围是**当前视觉行**；没有 `FontRole.CjkText` 时，先照常执行
  `WordSpace` 与 `CjkLatinSpace`，但不进入 `CjkInterChar`。
- 剩余 deficit 可以保留为 ragged，并写入 justification decision 与 line
  notes；这比在西文技术名称内部制造假空格更忠实于 source 与西文排版习惯。
- 只要视觉行含有汉字正文，仍按既有混排规则让普通标点↔西文边界参与末档
  均匀 tracking；本修订不是恢复全局 `CjkOnlyInterCharBoundary`。

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
