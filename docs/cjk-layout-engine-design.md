# 中文排版引擎设计备忘录

本文记录「提椠」（Tiqian）中文排版引擎的初步设计方向。它不是最终 API 文档，而是项目早期的取舍、核心模型和实现路线图。

## 目标

提椠的第一阶段目标不是实现一个完整浏览器级文本系统，而是实现一个面向中文正文的 CJK paragraph layout engine。

第一版重点支持：

- 中文横排。
- 静态或半静态段落。
- CLREQ 横排核心需求。
- Compose Multiplatform 前端。
- Android View 前端。
- 比 Android / Compose 默认中文排版更自然的字体 fallback、行高、标点空间和断行策略。

第一版暂不支持：

- 竖排。
- JLREQ。
- ruby / 注音 / 纵中横。
- 分页、多栏、脚注。
- 编辑器、IME、复杂 selection。
- 完整 CSS Text 兼容。

项目的价值不应该只是“多几个中文断行规则”，而是建立一套可观察、可调试、可扩展的 CJK 排版物理模型。

## 核心取舍

不要从 shaping 开始重造文本系统。字符到 glyph、cluster、advance、position 的转换应该尽量复用平台能力，例如 Android text stack、Skia、HarfBuzz、Skiko 等。

提椠需要自己掌握的是 shaping 之后、绘制之前的这些层：

- 字体 fallback 的候选顺序。
- 中文排版用字体度量。
- 标点墨迹与标点空间。
- CLREQ 断行和避头尾修复。
- 行内空间调整和两端对齐。
- 段落级审美优化。

换句话说：

```text
Text + Style + Locale + LayoutProfile
  -> font selection
  -> shaping
  -> CJK metric normalization
  -> punctuation atom / glue model
  -> break candidates
  -> line repair and optimization
  -> justification
  -> layout result
  -> renderer
```

## 字体 fallback

普通平台 fallback 的问题是它通常只关心“哪个字体有 glyph”，而不关心这个 glyph 在当前排版语境里是否合适。中文正文里，破折号、省略号、引号、括号、间隔号等符号如果被西文字体接管，会造成明显问题：

- 破折号中间断开。
- 省略号不采用中文标点的垂直居中形态，或与 CJK 标点风格不一致。
- 标点宽度、灰度、baseline 与中文正文不一致。
- 连续标点空间失控。

注意：中文省略号的合理行为是垂直居中。提椠不应把省略号人为压低；这里要解决的是 fallback 与字体形态选择错误，而不是把中文省略号从中部移到底部。

因此 fallback resolver 需要脚本、语言和标点角色感知。

建议的默认策略：

```text
Han / Kana / Hangul       -> CJK 主字体
CJK 标点                  -> CJK 主字体优先
U+2014 / U+2026 等通用符号 -> CJK 标点字体优先
Latin word                -> Latin 字体优先
Emoji / symbol            -> 专门 fallback
```

这意味着 fallback 不能简单委托给平台。平台可以提供实际 glyph 与 shaping 能力，但提椠应该决定候选字体顺序。

需要保留调试能力：

- 每个 cluster 最终使用的字体。
- fallback 命中原因。
- 是否因为 profile 改写了字体选择。
- 标点是否被 CJK 字体接管。

## 字体度量

中文排版不能直接使用 raw font metrics。以思源黑体等字体为例，字体上方常常为了音调符号、附加符号或跨语言兼容留下较大空间。如果直接使用平台 raw ascent / descent / top / bottom，汉字在视觉上会长期偏下。

需要区分两类度量：

```text
RawFontMetrics
  来自字体或平台 API 的原始事实。

LayoutFontMetrics
  提椠用于排版的度量。
```

这部分应参考 Apple / Web / OpenType 的共同模型：不同文字系统有不同 baseline class，CJK 不应只靠 Roman baseline 和 raw top/bottom 排版。

提椠需要显式建模：

```text
BaselineClass.Roman
BaselineClass.IdeographicCentered
BaselineClass.IdeographicLow
BaselineClass.Math

MetricBox.RawFontBox
MetricBox.IdeographicEmBox
MetricBox.IdeographicCharacterFace
MetricBox.SampledInkBox

FontMetricSource.RawTables
FontMetricSource.OpenTypeBase
FontMetricSource.GlyphSampling
FontMetricSource.ManualOverride
FontMetricSource.SynthesizedIdeographicBox
```

默认中文正文策略为：

```text
CJK text / CJK punctuation
  -> BaselineClass.IdeographicCentered
  -> MetricBox.IdeographicEmBox

Latin text
  -> BaselineClass.Roman
  -> MetricBox.RawFontBox
```

这意味着，即使一个 CJK 字体 raw metrics 因兼容附加符号而提供过高 ascent，提椠也应先把它视为 raw input，再通过 normalized layout metrics 生成 line box。最终 layout result 必须能解释：

```text
raw ascent/descent/source
  -> layout ascent/descent
  -> baseline class
  -> metric box
  -> normalizer reason
```

建议提供这些策略：

```text
FontMetricsPolicy.Raw
FontMetricsPolicy.IdeographicBox
FontMetricsPolicy.GlyphBoundsSampled
FontMetricsPolicy.ManualOverride

BaselinePolicy.Alphabetic
BaselinePolicy.Ideographic
BaselinePolicy.CenteredCjkVisual
```

中文正文默认应该倾向：

```text
CenteredCjkVisual + IdeographicBox
```

第一版可以通过代表汉字采样估算 CJK 视觉盒，例如：

```text
一 中 国 口 日 言 語
```

后续再加入字体特性、OS/平台专用 metric override、用户 profile override。

## 标点空间模型

标点处理应采用“加法模型”，而不是传统的“全角标点先占 1em，然后到处削空”的减法模型。

也就是说，标点不应该被简单视为一个 1em 字符，而应建模为：

```text
punctuation = ink + leadingGlue + trailingGlue
```

核心结构可以是：

```text
PunctuationAtom
  glyph
  advance
  inkBounds
  bodyWidth
  leadingGlue
  trailingGlue
  anchor
  lineStartPolicy
  lineEndPolicy
  pairRules
```

这样可以自然表达：

- 行尾标点半宽。
- 行首标点去除前置空白。
- 连续标点挤压。
- 引号和括号的上下文空间。
- 破折号、省略号的特殊宽度和 fallback。
- 两端对齐时优先调整标点空间。

OpenType 特性可以作为输入之一：

```text
chws / vchw  上下文约物间距
halt         半宽替代形
palt         比例替代宽度
```

省略号和破折号需要区分 source text 与 display glyph sequence。提椠不应改写用户输入、复制文本、搜索文本或 range mapping，但 layout cluster 可以根据 profile 选择更符合 CLREQ 的显示码点。

默认策略为 `PreferClreqRecommendedCodepoints`：

```text
source "……"  -> display "⋯⋯"  // U+22EF U+22EF
source "——"  -> display "⸺"    // U+2E3A
```

同时仍然要求这些 display glyph 使用中文标点字体优先显示，并保持中文排版语义：

- 省略号六点居中。
- 破折号占两个汉字宽度，中间不断开。
- source range 保持不变。
- 必要时可通过 `PreserveInput` profile 保留输入码点作为显示码点。

但为了普适性，不能假设所有字体都提供可靠特性。需要一套 fallback 测量方案：

```text
用户或字体 profile override
  -> OpenType feature
  -> glyph ink bounds
  -> Unicode punctuation class heuristic
```

注意：ink bounds 也不是绝对真理。它会受到字体设计、hinting、variable font axis、fallback glyph 和 overshoot 的影响。所以测量结果应被缓存、可调试、可覆盖。

## 断行、避头尾与修复

标点避头尾不是单纯的 line break rule，而是：

```text
line break
  + punctuation repair
  + paragraph aesthetics optimization
```

遇到不理想断点时，至少存在这些修复方案：

```text
PushIn
  压缩当前行可压缩空间，把标点推入本行。

Hang
  允许标点视觉上悬挂到行尾之外，逻辑仍属于本行。

CarryPrevious
  把标点和前一个字一起带到下一行。

LeaveRagged
  保持参差，避免过度修复。
```

每个断点都应生成候选方案，而不是用硬编码规则直接决定。

建议的数据结构：

```text
BreakCandidate
  index
  naturalWidth
  compressedWidth
  expandedWidth
  forbiddenReason
  repairOptions

LineCandidate
  startIndex
  endIndex
  naturalWidth
  visualEnd
  repairPlan

LineSolution
  lines
  totalBadness
```

评分因素可以包括：

```text
raggednessPenalty
compressionPenalty
expansionPenalty
hangingPenalty
kinsokuPenalty
carryPenalty
punctuationPenalty
profilePenalty
```

第一版可以使用 greedy + lookahead，不必一开始实现完整段落 DP。但 API 应该允许替换策略：

```text
LineOptimizationStrategy.Greedy
LineOptimizationStrategy.Lookahead(window = 2 or 3)
LineOptimizationStrategy.ParagraphDynamicProgramming
```

## 两端对齐

两端对齐应基于 glue 系统，而不是平均拉开所有汉字。

统一的调整机会可以是：

```text
AdjustmentOpportunity
  type
  min
  natural
  max
  priority
  penalty
```

默认调整优先级：

```text
PunctuationGlue
  -> CjkLatinSpace
  -> WordSpace
  -> CjkInterChar
```

中文正文中，粗暴拉开所有汉字会很快显得廉价。提椠应优先利用标点 glue、中西文间距和西文词距，最后才轻微调整汉字间距。

## 模块结构

建议模块：

```text
tiqian-text-core
  TextContent / Span / ParagraphStyle / TypographyStyle
  Cluster / TextRun / GlyphRun / LineBox
  LayoutInput / LayoutResult

tiqian-linebreak
  Unicode UAX #14 adapter
  ICU / platform BreakIterator adapter
  custom rule pipeline

tiqian-clreq
  CLREQ 横排规则
  strictness profile
  punctuation class table
  punctuation glue table
  line-start / line-end policies

tiqian-font
  FontResolver
  FallbackResolver
  FontMetricsPolicy
  PunctuationFontPolicy

tiqian-shaping-api
  TextShaper
  GlyphRun
  ClusterMetrics

tiqian-shaping-android
  Android TextPaint / MeasuredText / Canvas integration

tiqian-shaping-skia
  Skiko / Skia integration

tiqian-layout
  ParagraphLayoutEngine
  PunctuationAtomBuilder
  GluePlanner
  LineOptimizer
  Justifier
  HitTester

tiqian-compose
  TiqianText
  rememberTiqianTextLayout
  Compose Canvas renderer

tiqian-view
  TiqianTextView
  Android View renderer

tiqian-test
  fixtures
  golden layout snapshots
  screenshot renderer

tiqian-samples
  Android sample
  Compose desktop sample
  playground
```

## Compose 和 Android View

Compose 和 View 都应是外壳。排版决策必须在 core engine 内完成。

前端负责：

- 接收 constraints。
- 调用 core layout。
- 绘制 glyph runs。
- 提供 hit test / selection geometry。
- 暴露调试 overlay。

前端不负责：

- 字体 fallback 策略。
- 标点空间计算。
- 断行修复。
- 两端对齐。
- 段落优化。

建议 API 方向：

```kotlin
TiqianText(
    text = annotatedString,
    style = style,
    profile = ClreqProfile.MainlandHorizontal,
    lineBreak = ClreqLineBreak.Strict,
    textAlign = TextAlign.Justify,
)
```

底层 layout API 应独立于 Compose：

```kotlin
val result = paragraphEngine.layout(
    input = LayoutInput(
        text = text,
        style = style,
        constraints = constraints,
        profile = ClreqProfile.MainlandHorizontal,
    )
)
```

## 可以借鉴 JetBrains 的部分

可以借鉴：

- Compose text 的分层抽象，例如 ParagraphIntrinsics、Paragraph、MultiParagraph、TextLayoutResult。
- Compose Multiplatform 的模块组织和跨平台适配方式。
- Skiko / Skia 的绘制与测量能力。
- text layout cache 的边界设计。
- golden test 与截图测试思路。

不建议照搬：

- Compose 内部 text implementation。
- Android StaticLayout 的行为。
- 平台默认 fallback。
- Skia Paragraph 的完整 layout 决策。

原因是提椠的核心价值恰恰在平台默认行为之外：CJK fallback、中文视觉度量、标点 glue、避头尾修复和段落级优化。

## 调试实验台

项目早期应优先建立 playground，而不是先做正式 UI 组件。

playground 至少应支持：

- 原生 Compose / Android 排版与提椠排版并排比较。
- 段落宽度 slider。
- 字体选择。
- profile 选择。
- baseline overlay。
- line box overlay。
- glyph bounds overlay。
- ink bounds overlay。
- punctuation glue overlay。
- break candidate overlay。
- 每行 repair plan 展示。
- 每个 cluster 的最终字体展示。

没有调试实验台，很难判断排版结果是正确、变好，还是只是换了一种错误。

## 测试语料

第一批 fixture 应覆盖：

```text
中文，中文。
中文……中文。
中文——中文。
他说：“你好，世界。”
中文 English 中文。
（开头括号）和结尾标点。
这是一个很长的中文段落，用来测试不同宽度下的行尾标点。
```

每个 fixture 应尽量测试：

- 每行断点。
- 每个 cluster 的字体。
- 标点 atom 的 body / glue。
- 每行 natural width / visual width。
- 修复策略。
- baseline。
- screenshot golden。

## 里程碑

### M1: 字体与度量 demo

目标：

- 思源黑体等 CJK 字体视觉居中。
- 破折号、省略号、中文标点不被西文字体接管。
- Latin 仍可使用西文字体。
- layout debug 能显示每个 cluster 的字体。

### M2: 标点 glue demo

目标：

- 行尾标点自然半宽。
- 连续标点不产生 1em 空洞。
- 破折号不断开。
- 省略号保持 CJK 形态。
- 能显示 ink bounds 与 glue。

### M3: 避头尾 demo

目标：

- 支持 PushIn。
- 支持 Hang。
- 支持 CarryPrevious。
- 在不同段落宽度下根据评分选择不同方案。
- 使用 lookahead 2 到 3 行改善局部贪心问题。

### M4: 段落排版 demo

目标：

- 中文正文两端对齐。
- 标点 glue 优先参与调整。
- 中西混排 baseline 稳定。
- 视觉效果明显好于 Android / Compose 默认排版。

### M5: 库化

目标：

- 拆出 core、font、layout、android、compose、skia 等模块。
- 固化公开 API。
- 建立 golden tests。
- 建立 benchmark。

## 后续扩展

竖排不应该作为横排的小补丁加入，而应作为新的 writing mode。

需要额外处理：

- vertical glyph substitution。
- 标点方向与位置。
- tate-chu-yoko。
- ruby。
- 列方向。
- 纵排中的行首行尾规则。

JLREQ 也不应只是 CLREQ 的配置文件。它可以共享 core pipeline、shaping、glue 和 optimizer，但规则 profile 应独立建模。

## 第一原则

最容易失败的方式，是一开始就宣称实现 CLREQ / JLREQ / 竖排 / 编辑器。

更稳的方式是：

```text
先字体
  -> 再度量
  -> 再标点空间
  -> 再断行
  -> 再优化
  -> 最后封装 UI
```

只要第一阶段能证明这四件事，项目就已经有明确价值：

- 汉字 baseline 视觉自然。
- 中文标点 fallback 正确。
- 行尾标点和连续标点空间正确。
- 避头尾策略比系统文本更自然。
