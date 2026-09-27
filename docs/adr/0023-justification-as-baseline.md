# ADR 0023: 双齐为基线，对齐自由度只在末行

- Status: Accepted
- Date: 2026-06-13

## Context

CLREQ 原文（用户核对）：

> 「与西文排版不同，中文排版特别是书籍正文排版极少使用左齐右不齐，
> 原则上应该进行两端对齐。西文排版两端对齐（justification）时，主要是
> 调整单词之间的间隙（词距），而中文排版在两端对齐时，能调整的地方更多，
> 具体如下所述。」

行长调整程序的措辞同样以满行为前提（「前行多出来的空间**需**按照优先
顺序拉伸」，没有「留着不管」的分支）。汉字等宽、字距均匀的网格本性
决定了中文正文不存在西文式 ragged-right 惯例。

而引擎此前的 `TextAlign { Start, End, Center, Justify }` 是 CSS 形状的
枚举：默认 `Start`（ragged），`End`/`Center` 渲染层从未实现，Justify
要显式开启，ADR 0021 已记过这个不一致。

## Decision

### 删除 `TextAlign`：双齐是行为，不属于选项

非末行**永远**走 justify 链（挤压/拉伸已使行长一致），不再有开关。
对齐的唯一自由度交给末行：

```kotlin
enum class LastLineAlignment { Start, Center, End }   // 默认 Start
```

- `Start`（默认）：CLREQ 横排末行齐行首。
- `Center` / `End`：标题居中、落款齐右、引文出处等特殊用法。

### 末行定位经 `LineBox.indent` 实现

Center/End 表达为末行的额外起点偏移（在该行可用行宽内计算，与段首
缩进叠加）。`indent` 的语义不变（inline 方向起点偏移），三个渲染器与
decoration 几何不变。

### 单行段落即末行

justify 跳过末行的既有规则保证：短标签、标题永远不被拉伸；同时
`Center`/`End` 对单行段落直接给出居中/齐右标题，CLREQ 提到的特殊
场合无需额外机制。

## Consequences

- `ParagraphStyle` 失去 `textAlign`；fixture/测试/demo 的显式 Justify
  全部删除（默认即是）。
- 原先未开 Justify 的多行 fixture（kinsoku 系列、greedy-multi-line 等）
  golden 变为对齐形态，非末行 `visual ≈ maxWidth`。极窄调试 fixture 的
  大份额拉伸（+8/+16px per boundary）是双齐在非常规行宽下的诚实结果。
- 示亡号框几何跟随对齐后的字位（框贴字面，行末 justify delta 在框外）。
- 多行 ragged（诗歌等特定场合）不在第一阶段；将来若需要，是新的段落设置
  选项，不再恢复 `TextAlign.Start`。

### Amendment (2026-07-10): WesternDominantLineNaturalSpacing

「非末行永远走 justify 链」不等于每个视觉行都必须进入中文末档均分字距。
当前视觉行没有 `FontRole.CjkText` 时，它是西文主导排版：西文词距仍按第一档
拉伸，中西间距若存在仍按第二档处理，但不能仅因中文括号、顿号等标点进入
`CjkInterChar`。各有上限的西文资源耗尽后允许保留 ragged deficit，并以
`WesternDominantLineNaturalSpacing` 写入 debug。含汉字正文的混排行不变，
仍以中文双齐为基线。

### Amendment (2026-07-28): 混排行的最终均分包含已优先拉伸的间距

混排行先按顺序拉西文词距和中西间距；仍有余量时，最后一次统一加宽同时落在
汉字间距、词距和中西间距上。前两类不是从最终均分中排除的特殊位置。一个 source
空格只算一个间距；CLREQ 禁止拉伸的符号组合内部和连接号、分隔号两侧仍排除。

行内对象默认保持固定。对象提供方只有在知道边界可调整时，才可把该边界加入最后
一次统一加宽；也可把对象宽度内已经量出的尾部空白作为第八档压缩资源，在七档正文
挤压都用完后再移除。该规则只改变边界空白，不横向缩放对象内容；图片和普通组件不
自动参与。

公式不能只用一个“可拉伸”布尔值概括。公式渲染器从自己的 AST 与实测布局中标出
三类有上限的空白，Tiqian 在西文词距和中西间距之后依次使用：逗号等标点后的空白、
关系符号两侧的空白、二元运算符两侧的空白。每个位置最多再增加其原有的实测数学
空白；一类资源用完才进入下一类。三类优先资源都耗尽后，它们仍和已开放的词距、
中西间距及汉字间距一起参加最终统一字距。这个顺序是公式提供方仿照 CLREQ 分档模型
定义的公式策略，不声称 CLREQ 本身规定了数学公式的上述次序。

调宽边界与断行边界是两条独立规则。逗号后、关系符或运算符之前的边界可以只供调宽而
明确禁止断行；公式原本允许的主基线关系符、二元运算符之后仍可断行，使符号留在上一行。
不断行时后侧数学空白照常存在；命中断点时，该实测空白作为行尾可丢弃 glue 移除，下一片段
不带前导空白。这样既保持 TeX/KaTeX 的断行方向，也不会在两个行端留下空洞。提供方不能为了
暴露空白而给段落断行器凭空增加断点。

### Amendment (2026-08-15): ExplicitEmergencyGraphemeTracking

`WesternDominantLineNaturalSpacing` 继续是默认：大段普通西文在词距上限耗尽后可以右侧参差，
不得为了双齐自动拉开字母间距。唯一窄例外是 upstream 已给出结构化资格的技术/non-lexical
range（见 ADR 0029 amendment）。非末行先完整运行源码技术空格、普通西文词距、中西间距、
公式/inline object 资源以及中文 `CjkInterChar`；仍有 residual 时，才把它平均分配到该资格
range 内、当前行实际存在的 source-grapheme cluster 边界。普通数字/符号 cohesion 可以继续关闭
断点，但不能把 tracking 集中到 token 内少数未关闭的字母间距；源码空格和 opaque inline object
边界不进入这组机会。

该末档名为 `ExplicitEmergencyGraphemeTracking`，allocation kind 为
`EmergencyGraphemeTracking`。资格 range 与原因写入 `emergencyTrackingEligibilityDecisions`，
逐 boundary 的实际分配继续写入 `JustificationDecisionInfo`。技术 inline 位于行中时不会冻结或
删除正文机会；纯链接/hash 行则可以用这项补足手段精确填满版心。末行和 mandatory-break 行仍不调宽。
