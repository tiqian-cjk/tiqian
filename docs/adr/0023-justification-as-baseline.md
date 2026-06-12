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
顺序拉伸」——没有「留着不管」的分支）。汉字等宽、字距均匀的网格本性
决定了中文正文不存在西文式 ragged-right 惯例。

而引擎此前的 `TextAlign { Start, End, Center, Justify }` 是 CSS 形状的
枚举：默认 `Start`（ragged），`End`/`Center` 渲染层从未实现，Justify
要显式开启——ADR 0021 已记过这个不一致。

## Decision

### 删除 `TextAlign`：双齐是行为，不是选项

非末行**永远**走 justify 链（挤压/拉伸已使行长一致），不再有开关。
对齐的唯一自由度交给末行：

```kotlin
enum class LastLineAlignment { Start, Center, End }   // 默认 Start
```

- `Start`（默认）——CLREQ 横排末行齐行首。
- `Center` / `End` —— 标题居中、落款齐右、引文出处等特殊用法。

### 末行定位经 `LineBox.indent` 落地

Center/End 表达为末行的额外起点偏移（在该行可用行宽内计算，与段首
缩进叠加）。`indent` 的语义不变（inline 轴起点偏移），三个渲染器与
decoration 几何零改动。

### 单行段落即末行

justify 跳过末行的既有规则保证：短标签、标题永远不被拉伸；同时
`Center`/`End` 对单行段落直接给出居中/齐右标题——CLREQ 提到的特殊
场合无需额外机制。

## Consequences

- `ParagraphStyle` 失去 `textAlign`；fixture/测试/demo 的显式 Justify
  全部删除（默认即是）。
- 原先未开 Justify 的多行 fixture（kinsoku 系列、greedy-multi-line 等）
  golden 变为对齐形态——非末行 `visual ≈ maxWidth`。极窄调试 fixture 的
  大份额拉伸（+8/+16px per boundary）是双齐在非常规行宽下的诚实结果。
- 示亡号框几何跟随对齐后的字位（框贴字面，行末 justify delta 在框外）。
- 多行 ragged（诗歌等特定场合）不在第一阶段；将来若需要，是新的段落
  级特性而不是恢复 `TextAlign.Start`。
