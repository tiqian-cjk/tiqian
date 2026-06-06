# 多 Agent 协作约定

本文记录「提椠」（Tiqian）在多 agent 协作下的工作方式。它不是项目治理章程，而是为了让不同 agent、人类维护者和后续贡献者能在同一套长期约束下推进项目。

## 基本判断

提椠不是一个适合“临时补丁式推进”的项目。它的难点不在于某个单点算法，而在于字体 fallback、度量、标点空间、断行、避头尾、两端对齐、平台绘制之间存在强耦合。

因此，多 agent 协作的目标不是把任务拆得越碎越好，而是让每个 agent 都在同一个模型里工作：

```text
功能可以窄，模型必须真。
```

任何 agent 都可以做一个小切片，但这个切片必须沿着真实 pipeline 走，不应制造后续必然推倒重来的假实现。

## 协作原则

### 1. 先维护模型，再扩展功能

提椠的核心资产是模型，不是某个早期 demo。

优先保护这些概念：

- Cluster
- GlyphRun
- FontFallback
- LayoutFontMetrics
- PunctuationAtom
- Glue
- BreakCandidate
- RepairOption
- LineSolution
- LayoutResult

如果一个实现绕开这些概念，直接在 UI 或平台层里做特殊处理，它通常应该被视为技术债。

### 2. 做最小可验证切片，不做最小主义补丁

可以只支持少数字符、少数标点、少数 profile。

不可以为了快速显示效果而把规则写死在渲染层、Compose 层或 Android View 层。

合理的早期实现：

```text
只支持横排。
只支持中文逗号、句号、省略号、破折号。
只支持一种 CJK 字体和一种 Latin 字体。
但仍然走 fallback -> shaping -> metrics -> punctuation atom -> glue -> line layout -> render。
```

不合理的早期实现：

```text
if (char == '，') width -= 0.5em
if (char == '…') forceSomeFont()
if (lineEndBad) moveCharBack()
```

### 3. 平台适配不得泄漏到核心规则

Android、Skia、Compose、Desktop、iOS 可以提供：

- 字体加载。
- shaping。
- glyph metrics。
- glyph drawing。
- platform font fallback 查询。
- input constraints。
- rendering surface。

它们不应该决定：

- CLREQ profile。
- 中文标点 fallback 优先级。
- 标点 glue。
- 避头尾修复策略。
- 两端对齐分配顺序。
- 段落优化评分。

平台差异应该进入 adapter 和 capability report，而不是进入核心规则。

### 4. 所有 heuristic 都必须命名

排版中会有很多启发式策略。启发式不是问题；无名启发式才是问题。

例如：

```text
CenteredCjkVisual
PreferCjkForAmbiguousPunctuation
LineEndHalfWidthPunctuation
LookaheadLineOptimization
PunctuationGlueFirstJustification
```

不接受：

```text
// looks better
x -= 0.5f
```

每个 heuristic 都应该能回答：

- 它解决什么问题。
- 它属于哪个 profile / policy。
- 它是否可关闭。
- 它的测试语料是什么。
- 它是否会影响竖排或 JLREQ。

### 5. LayoutResult 必须可解释

提椠的调试对象不是最终截图，而是 layout decision。

LayoutResult 应逐步具备解释能力：

- 每个 cluster 使用的字体。
- 每个 glyph run 的原始 metrics。
- 每个 line box 的排版 metrics。
- 每个标点的 ink / body / glue。
- 每个断点的候选和禁则原因。
- 每行采用的 repair option。
- 每个 glue 的压缩或扩张量。
- 每行 natural width、adjusted width、visual width。

如果一个 agent 做出的改动无法解释这些信息，后续 agent 很难继续验证它。

## 推荐角色分工

### 规划型 agent

适合负责：

- 长期架构。
- 模块边界。
- profile 体系。
- 规则表设计。
- 竖排 / JLREQ 的未来兼容性。
- 文档统一。

产物应该是：

- 设计文档。
- ADR。
- milestone。
- module map。
- risk register。

规划型 agent 不应只给抽象愿景，也要指出哪些早期实现会堵死未来。

### 实现型 agent

适合负责：

- 搭建模块骨架。
- 写 interface 和 data class。
- 实现小切片。
- 建立 fixture。
- 建立 playground。
- 跑测试和截图验证。

产物应该是：

- 可编译代码。
- 小而完整的 pipeline。
- fixture 和 golden。
- 调试输出。
- 明确的 TODO 和 limitation。

实现型 agent 不应为了跑通 demo 绕开核心模型。

### 审查型 agent

适合负责：

- 找模型泄漏。
- 找平台耦合。
- 找不可解释的 heuristic。
- 找测试缺口。
- 找与 CLREQ / JLREQ / OpenType 语义冲突的地方。

审查输出应 findings first，优先指出会导致后续推倒重来的问题。

### 研究型 agent

适合负责：

- CLREQ / JLREQ 条款整理。
- OpenType feature 调研。
- 平台字体栈调研。
- Skia / Android / Compose text behavior 调研。
- Web / Apple / Android 对比。

研究输出必须区分：

- 规范明确要求。
- 平台实际行为。
- 字体特定行为。
- agent 推断。

## 交接格式

每次较大交接应包含：

```text
Current objective
  当前目标是什么。

What changed
  改了哪些文件和概念。

Verified
  实际跑过什么命令、看过什么输出。

Known limitations
  哪些只是占位、哪些尚未实现。

Open decisions
  需要人类或下一个 agent 决定什么。

Do not break
  哪些约束后续不能破坏。

Suggested next slice
  下一个最小可验证切片。
```

如果涉及排版行为，还应补充：

```text
Test text
Width / constraints
Font profile
Expected line decisions
Observed line decisions
Screenshots or layout dump
```

## 决策记录

重要取舍应该写 ADR，而不是只留在聊天里。

推荐路径：

```text
docs/adr/0001-core-pipeline.md
docs/adr/0002-font-fallback-policy.md
docs/adr/0003-punctuation-glue-model.md
docs/adr/0004-line-repair-strategy.md
```

ADR 应包含：

- Context
- Decision
- Consequences
- Alternatives considered
- Follow-up questions

## 禁止的协作模式

### 1. Demo 先行但不补模型

可以做 demo，但 demo 不能成为唯一事实来源。

如果 demo 里出现一个规则，它必须最终回到 core policy、fixture 或 ADR 中。

### 2. 平台层私自修正排版

例如 Compose renderer 发现行尾标点不好看，于是在绘制时移动 glyph。这种修正会让 Android View、Skia 和测试全部失去一致性。

正确位置应该是 layout / punctuation / justification 层。

### 3. 规则散落在条件判断里

单点条件可以作为临时实验，但不能作为合并后的结构。

规则应尽量表驱动、profile 驱动、policy 驱动。

### 4. 用截图替代 layout dump

截图重要，但截图不是全部。排版引擎必须能解释为什么这样排。

### 5. 过早承诺竖排和 JLREQ

横排模型必须为竖排和 JLREQ 留接口，但第一阶段不应该假装已经解决它们。

## 早期推荐推进顺序

### Slice 0: 项目骨架

目标：

- 建立 Gradle / KMP 模块。
- 建立 core data model。
- 建立空 layout pipeline。
- 建立 fixture 目录。
- 建立 playground 占位。

验收：

- 项目可编译。
- core API 不依赖 Compose 或 Android View。
- 文档中提到的核心概念都有对应类型或 TODO。

### Slice 1: 字体 fallback 可解释

目标：

- CJK 标点优先走 CJK 字体。
- Latin word 可走 Latin 字体。
- 省略号和破折号不被错误 fallback 接管。
- layout dump 能显示 cluster -> font。

验收：

- fixture 覆盖 `中文……English——中文。`
- 输出每个 cluster 的 font decision。
- Android 和 Compose 前端不私自参与 fallback 决策。

### Slice 2: 中文视觉度量

目标：

- 建立 RawFontMetrics 与 LayoutFontMetrics。
- 建立 CenteredCjkVisual policy。
- 思源黑体等字体不因 raw metrics 导致汉字视觉偏下。

验收：

- layout dump 显示 raw metrics 和 layout metrics。
- playground 能显示 baseline 与 line box overlay。

### Slice 3: 标点 atom / glue

目标：

- 建立 PunctuationAtom。
- 支持 ink / body / leadingGlue / trailingGlue。
- 行尾标点可自然半宽。

验收：

- fixture 覆盖 `中文，中文。`、`他说：“你好，世界。”`
- layout dump 显示标点 glue。

### Slice 4: 避头尾修复

目标：

- 建立 BreakCandidate 和 RepairOption。
- 支持 PushIn、Hang、CarryPrevious。
- 先使用 greedy + lookahead。

验收：

- fixture 能在不同 width 下触发不同 repair。
- 每行 repair plan 可解释。

## 给后续 agent 的提醒

如果你要继续这个项目，请先读：

```text
docs/cjk-layout-engine-design.md
docs/multi-agent-collaboration.md
```

然后确认当前工作属于哪一种：

```text
architecture
research
implementation
review
playground
test
```

不要在没有说明角色的情况下同时做架构重写、行为修正和视觉调参。提椠需要长期一致性，短期灵感应该通过文档、fixture 和可解释 layout result 落地。

