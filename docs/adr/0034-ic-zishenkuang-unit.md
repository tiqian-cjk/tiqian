# ADR 0034: `ic` 字身框单位（CJK 原生长度单位）

- Status: Accepted
- Date: 2026-06-21
- 关联：[ADR 0002](0002-script-aware-font-metrics.md)（字身框度量 = BASE ideo/idtp）、[ADR 0028](0028-integer-line-length-grid.md)（行长整字网格）、[ADR 0030](0030-rich-text-spans.md)（混排取 per-gap-owner 字号）

## Context

CJK 排版以「字」为天然单位：行长「40 字」、缩进「2 字」、相邻拼音「1/4 字」——CLREQ 通篇如此。但当前作者面 / `ParagraphStyle` 把这些表达成裸 `Float`：

- `firstLineIndentEm` / `blockIndentEm`（core，px = `值 × fontSize`）；
- `CjkBlock.List.indent`（字数 `Float?`）；
- 行长走整字网格（[ADR 0028](0028-integer-line-length-grid.md)）；
- Compose 面 `textStyle.fontSize` 是裸 px（调用者自乘 density）。

三个新压力把「需要一个正式单位」推到台面：

1. **字身框已被正式度量**（[ADR 0002](0002-script-aware-font-metrics.md)：BASE `ideo/idtp`，缺则 sTypo）——「一个字」不再是模糊的 em，而是字体声明的字身进格。
2. **混排存在**（[ADR 0030](0030-rich-text-spans.md)）——「2 em」在行内变号处歧义（谁的 em？）；需要一个**锚点明确**的单位。
3. **Compose 外壳缺 CJK 习惯单位**——裸 `Float` px 不符合直觉，也不该让每个调用点自己换算 density。

## Decision

引入 **`ic`** 作为提椠的 CJK 原生长度单位。

**名分**：`ic` 直接采用 W3C CSS Values L4 的 `ic` 单位——定义为「表意字身的 advance（CSS 用 '水' U+6C34 字形的 advance 量）」，即**字身框宽**。国际标准、两字母、做 web/排版者皆识。CSS 用探测 水 字定义它；**我们用字体声明的字身框（[ADR 0002](0002-script-aware-font-metrics.md) 的 ideo/idtp）解析它——同一单位，来源更稳**。

```kotlin
// core
@JvmInline value class Ic(val count: Float)        // N 个字身框
fun Ic.toPx(emPx: Float): Float = count * emPx      // emPx = 解析上下文的字身框进格

// frontend/compose（作者面）
val Float.ic: Ic get() = Ic(this)                   // 2f.ic / 0.25f.ic
val Int.ic: Ic get() = Ic(toFloat())                // 40.ic / 2.ic
```

### 锚点规则（解析成 px 时锚到谁的字身框）

与 [ADR 0030](0030-rich-text-spans.md) 的「per-gap-owner」一致：

- **段级**（行长、段首/段落缩进、节距、列表标记列宽）→ 锚**段落基准 CJK 字身框**（= 段落 `fontSize`，不随行内变号）。
- **行内**（相邻 cluster 间距、ruby 间距/字号）→ 锚**该 gap owner 的字身框**。

`ic` 本身只是个计数（与上下文无关）；px 在使用点按上述字体上下文解析。横排全宽 CJK 的字身框宽 = 1em = `fontSize`，故 `Ic(n).toPx(fontSize) = n × fontSize`——**数值同旧 em，零行为变化**；价值在语义 + 类型安全 + 锚点明确 + Compose 习惯单位。

### 适用范围

- **用 `ic`**：行长、段首/段落/凸排缩进、节距、列表标记列宽、行内间距、ruby 字号/间距——凡是作者会用「N 字」想的量。
- **不用 `ic`**：
  - `fontSize` —— 它*定义*了一个字身框，自身不能再以字身框计；保持 px（Compose 面 `sp`/`TextUnit` 是单独的 density 议题）。
  - 比率/无量纲值（行高倍数等）。

### 落地分期（控制 blast radius）

- **本期(作者面)**：`ParagraphStyle` 的缩进、`CjkBlock.List.indent`、Compose `Float.ic` 扩展改用 `Ic`；段级锚段落 `fontSize`。
- **暂不动(内部已是正确 em 倍数,纯类型化收益、golden 风险高)**：CLREQ profile 内部常量（`gapEm`、kinsoku 阈值 `shortBelowEm/hangBelowEm/...`、标点 `defaultBodyEm/defaultAdvanceEm`）、ruby 渲染常量（`RUBY_*_EM`）。它们**概念上是 `ic`**，但保持 `Float` 内部值;待行内锚点(per-owner)整体收口时再议。

## Mechanism

- `Ic` + `toPx` 落 `core`（平台无关）。
- `ParagraphStyle.blockIndentEm: Float` → `blockIndent: Ic`；`firstLineIndentEm: Float?` → `firstLineIndent: Ic?`。引擎缩进解析处 `… × fontSize` 换成 `….toPx(fontSize)`。
- `CjkBlock.List.indent: Float?` → `Ic?`；`ParagraphIndent` 的 `em: Float` → `Ic`。
- Compose 扩展 `Float.ic`/`Int.ic` 在 `frontend/compose`。
- Dump/Decision 字段（`measureEm`/`resolvedEm` 等）维持 `Float`（报告用，非作者输入）。

## Consequences

- 作者面读作 `firstLineIndent = 2.ic`、`List(indent = 3.ic)`、(后续) 行长 `40.ic`——CJK 原生且挂国际标准。
- 零 golden 漂移（全宽 CJK 下 `ic` 数值 = 旧 em）。
- 为「Compose-idiomatic 单位」(Codex #5) 给出 CJK 原生答案，胜过照抄 `sp`。
- 内部常量暂留 `Float`，是已知、有界的不一致；行内锚点收口时清。
- 竖排前哨：竖排时字身框「进格」是字高方向；`Ic` 计数不变，`toPx` 换竖向字身框即可——锚点规则已留好竖排口。
