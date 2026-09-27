# ADR 0026: 行尾禁则（开括号/分隔号不得居行尾）

- Status: Accepted
- Date: 2026-06-13

## Context

整体 review 发现：`KinsokuRule` 接口有 `forbiddenAtLineStart` 与
`forbiddenAtLineEnd` 两个方法，`ClreqPunctuationPolicies` 也按四档算出
行尾禁则，但 **breaker 全程只消费 `forbiddenAtLineStart`**，行尾禁则
计算了却从未生效。后果：

- 「开引号/开括号不得居行尾」（CLREQ 基本处理档的规则）未实现，行尾
  可能留下一个没有后续文字的 `（` / `“`；
- GB 法 / 严格处理追加的「分隔号不得居行尾」是空操作，它依赖的机制
  不存在（这也使 ADR 0025 的 `>24→GB` 升档此前完全无效）。

无任何 ADR 把行尾禁则记为暂缓，这是实现遗漏。

## Decision

行尾违禁标点用**断点回退**处理，不采用 line-start 的挤进/推出：

- 当贪心断点会让一行**以**行尾违禁标点（开引号括号；GB·严格 的分隔号）
  **结尾**时，断点回退到该标点之前，标点移到下一行行首（开括号在行首
  被允许）。`adjustBreakForLineEnd`，连续多个一并回退，绝不把行清空
  （仅一个违禁标点独占整行的极端情形保留违规，避免死循环）。
- **只缩短当前行、不增长任何行 → 不会引发其他行溢出**。这是相对 line-start
  「推出」的对称操作，但因为方向是向后移、不回拉，不需要 PushIn/shrink
  补足，实现简单且封闭。
- 记为 `RepairOption.CarryNext`（penalty 0，强制且无代价），dump 显示
  `repair=CarryNext(ForbiddenAtLineEnd …)`，offender = 被移走的标点。
- 末行（段尾）不回退，没有下一行可承接，段落以 `（` 结尾是文本问题。
- 禁则集 `forbiddenLineEndClusters` 由 engine 从解析出的 `KinsokuLevel`
  算出（与 `forbiddenLineStartClusters` 并列），随 profile 档变化。

greedy 与 lookahead 两条路径都在**提交断点时**回退并标注，保证 dump
一致（lookahead 不在评分阶段回退：评分是启发式，正确性由提交时回退
保证）。

## Consequences

- 「开括号不得居行尾」（基本处理）实际生效；GB 法的「分隔号不得居行尾」
  从空操作变为实操作，ADR 0025 的 `>24→GB` 升档现在名副其实。
- `line-end-kinsoku` fixture + golden（`CarryNext` 决策行）；breaker 单测
  覆盖回退与「独占整行不回退」边界；engine 单测验证从档解析禁则集。
- `CarryNext` 的 repair 标注在后续 line-start 修复（PushIn/Carry 复用
  同一行）时可能被覆盖：几何已定，标注以更晚者为准，可接受。
- 行尾禁则不参与 lookahead 评分，理论上偶有非最优断点；与既有
  line-start 推出同属启发式，未观测到问题。

## Amendment (2026-08-11): UAX #14 西文标点边界与 CLREQ tailoring 分层

Mi 10s 真机语料暴露出原模型把两件事错误地绑在了一起：弯引号一旦因上下文误判而使用
`LatinText`，不仅字形变成比例宽，`isCjkKinsokuRole()` 也会同时撤掉断行语义，于是闭引号
可以落到下一行行首。ASCII 闭括号此前也只有「内部含 CJK」时才由
`CjkContextAsciiBracketKinsoku` 补规则；纯西文括号反而没有西文本身的边界约束。

修订后分为两层：

- `CjkPunctuation` 继续由 CLREQ 的 `KinsokuLevel`（None / Basic / GB / Strict）tailor；
- 非 CJK 标点由具名 `Uax14WesternPunctuationBoundary` 消费 Unicode 17.0.0
  `LineBreak.txt` 的固定数据，不再以字体面是否为 CJK 作为「有没有断行语义」的开关。

本次只实现与现有分词/CLREQ 策略边界明确的 UAX #14 标点子集，不宣称完整实现 Unicode
Line Breaking Algorithm：

- LB13 / LB15d：`CL` / `CP` 闭符号、`EX` 句末符号与 `IS` 句内符号不得居自动折行行首；
- LB14：`OP` 开符号不得居自动折行行尾；
- LB15a / LB15b / LB19 tailoring：`QuotePairAnalyzer` 已确认成对的弯开引号与闭引号分别绑定
  后文与前文；未配对的 Unicode `Pi` / `Pf` 引号仍保留码点方向，`’90s` / `James’` / 词内
  apostrophe 再按相邻西文解析，方向不明的 ASCII 直引号与装饰引号保护两侧；
- 源文 mandatory break 与 U+200B 的显式断点优先，不跨作者指定边界修复。

`SY`、`BA`、`HY`、`NS`、`IN` 仍由已有 URL/opaque token、连字符和 CJK profile 策略处理，
避免出现第二份断行真值；待接入完整 UAX #14 analyzer 时再统一迁移。数据生成表记录 Unicode
版本、官方 URL 与 SHA-256，跨 JVM / Android / JS / Apple 共用。

这些标准边界同时进入 `forbiddenLineStart/EndClusters` 与 `unbreakableRanges`。后者让 breaker
在枚举断点时就关闭「前字｜闭符号」「开符号｜后字」，可以把后续文字一并重排；只做事后
PushIn/Carry 修补会在局部无解时退成 `LeaveRagged`，仍留下孤立符号。每个非 CJK 约束进入
`ContextualKinsokuDecisionInfo`，dump 可见具体 LB 规则，字体、advance 与标点 glue 均不因此改变。

规范依据：[Unicode UAX #14](https://www.unicode.org/reports/tr14/)；CSS 的 `line-break`
明确以 UAX #14 为起点，再按书写系统与 strictness 做语言 tailoring，见
[CSS Text Level 4 §6.2](https://www.w3.org/TR/css-text-4/#line-break-property)。
