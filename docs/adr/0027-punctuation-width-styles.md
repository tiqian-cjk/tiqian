# ADR 0027: 标点宽度风格——开明式 + GB 固定半宽

- Status: Accepted
- Date: 2026-06-13

## Context

加法模型（ADR 0004）下，标点 = 字面 body + 可调空隙 glue，默认占宽
由 `ClreqPunctuationPolicies` 的 `defaultAdvanceEm` 给出（多数 1em）。
两类 CLREQ 记录的并存宽度风格此前没有载体：

- **开明式标点**（开明书店式，CLREQ issue #572：「句中点号、夹注号半字，
  句末点号（除行末外）一字」）：句中点号（逗号、顿号、分号、冒号）与
  夹注/括号/引号占**半字**，句末点号（句号、问号、感叹号）占**一字**。
- **GB 式固定半宽**（CLREQ「不可调整的标点……GB 式半字连接号、间隔号、
  分隔号，固定半个字宽」）：连接号、间隔号、分隔号固定半字、**不可调整**。

## Decision

落为 profile 级 `ClreqProfile.punctuationWidth: PunctuationWidthPolicy`：

```kotlin
data class PunctuationWidthPolicy(
    val interior: InteriorPunctuationStyle = FullWidth,   // 全身式 / Kaiming
    val gbFixedSeparators: Boolean = false,               // 连接/间隔/分隔 固定半宽
)
```

机制——**强制半字 = 占宽压到 0.5em**。在加法模型里，advance 压到 body
（0.5em）即 glue 归零，于是该标点既半宽**又不可调**（无 glue → 不进
PushIn 挤压档、也不进 justify 拉伸），一举两得。`PunctuationAtomBuilder`
在算出 advance 后，对命中的类别覆盖为 0.5em：

- **开明式**：`Opening`/`Closing`（夹注/括号/引号）+ `PauseOrStop` 中非
  句末者（逗号、顿号、分号、冒号）→ 半字；句末点号（。！？．）保持原占
  宽（行中一字，行末仍由行末削半处理）。
- **GB 固定半宽**：`Connector`/`MiddleDot`/`Interpunct`/`Solidus` → 半字。

覆盖发生在 shaped advance 之后——开明式/GB 是排版风格决策，强制占宽，
不取字体的全宽 glyph advance（glyph 仍画在字面侧，trailing 空白让给版心）。

`forcedHalfWidth(char, policy)` 在 `ClreqPunctuationPolicies` 里，与
分类同源；判定句末点号用 `SentenceEndStops = {。！？．}`。

默认 `FullWidth` + `gbFixedSeparators=false` = 既有行为，golden 零漂移。

## Consequences

- 两风格为 opt-in profile 选项，默认不变；单测覆盖（开明式 逗号/括号
  半字、句号留全字；GB 间隔号 0.5em 且 glue 0 不可调），与 ADR 0020
  三开关同属「knob → 单测，不进 golden fixture」的先例。
- 半字标点在 justify 下仍可获均匀字距份额——增量落在 trailing（标点后的
  字距），字面保持半宽，符合开明式「字面半字、字距照拉」。
- 未做：开明式「夹注号」严格只指括号，本实现把成对引号也并入半字
  （成对标点开明式通常同样半排）——如需区分再加 profile 细分。
  连接号默认占宽（非 GB 时）的全宽/半宽（CLREQ 短横线 0.5em vs 浪纹线
  1em）未按字细分，留作后续。
