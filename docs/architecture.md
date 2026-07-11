# 提椠当前架构

本文说明提椠当前的 pipeline、模块边界与平台接入方式。正在推进的工作见
[roadmap](roadmap.md)，具体取舍及其演变见 [ADR 索引](adr/README.md)。

## 范围

提椠是面向中文正文的 CJK 段落布局引擎，目前完成的是简体中文横排。它不重新实现
平台已经具备的字体加载、glyph shaping 与绘制，而是在这些能力之上统一处理：

- 字体角色与 fallback；
- 中文字体度量与混排 baseline；
- 标点 body、墨迹与可调整空间；
- 断行、避头尾与行尾修复；
- 行内挤压、拉伸、邻行均摊与两端对齐；
- 段首缩进、列表、富文本、行间线、拼音与注音；
- 源文本范围、复制与搜索保真，以及宿主无障碍语义的保留。

竖排、JLREQ、KLREQ、分页、多栏、编辑器与完整 CSS Text 兼容不属于当前实现范围。

## Pipeline

```text
宿主文本 / AnnotatedString / DOM
  -> 前端 lowering（保留 source range 与宿主语义）
  -> TiqianTextContent + style + annotations + inline geometry
  -> 字体角色与 fallback
  -> 平台 shaping adapter
  -> 字体度量归一化
  -> 标点 atom / glue / inline geometry ledger
  -> break candidates + mandatory breaks + unbreakable ranges
  -> line breaking + kinsoku repair
  -> compression / justification / neighbor adjustment
  -> LayoutResult + structured debug decisions
  -> Compose / DOM / Android renderer
```

`ExplainableStubParagraphLayoutEngine` 保留了早期名称，但当前实现已经走完整真实 pipeline。
stub 只作为没有平台字体系统时的确定性测试 adapter 存在，不是默认布局模型。

## 输入与输出

布局核心消费平台无关的输入：

- `TiqianTextContent` 保存 source text 与样式 span；
- `TextStyle` 与 `ParagraphStyle` 保存样式和段落策略，`LayoutProfileId` 选择由
  profile resolver 提供的中文排版规则；
- `DecorationSpan`、`RubySpan`（含 Bopomofo kind）、`InlineBoxSpan`、`InlineObjectSpan`
  等结构表达行内语义和宿主几何；
- `LayoutConstraints` 提供版心宽高与行数限制。

输出 `LayoutResult` 包含：

- source range 连续可追踪的 `Cluster`；
- 可由平台前端重放的 `GlyphRun` 与 glyph placement；
- `LineBox`、最终 advance、visual width、缩进与 baseline；
- 行间注、装饰、富文本和 inline object 的几何；
- 字体选择、标点空间、断行候选、修复方案、行调整与降级原因等结构化 decision。

前端只能消费这些结果，不得另建一套断行或标点规则。

## 字体与 shaping

`tiqian-font` 先根据文字角色、locale、宿主字体偏好与标点策略决定候选字体。
`tiqian-shaping-api` 的平台实现随后只负责把已确定的 source/display text 与字体请求变成
cluster、glyph、advance 和 ink bounds。

当前平台实现包括：

- `tiqian-shaping-jvm`：AWT 字体与 glyph vector；
- `tiqian-shaping-skia`：Skia / Skiko，供 Compose Desktop 与 JVM 渲染；
- `tiqian-shaping-android`：Android `TextPaint` / platform glyph data；
- `tiqian-shaping-web`：浏览器离屏 Canvas 度量，并按需要使用可验证字体证据。

平台 adapter 不决定 CLREQ 码点替换、标点宽度、避头尾或两端对齐。它无法提供某项证据时，
必须输出具名降级原因，而不是在 renderer 中猜补偿值。

## 排版核心

`tiqian-layout` 把 shaping 结果与中文排版规则组合成最终段落：

1. `ScriptAwareFontMetricsNormalizer` 把平台 raw metrics 转成用于 CJK 与 Latin 混排的
   layout metrics。
2. `PunctuationAtom` 把标点表达为 `ink/body + leadingGlue + trailingGlue`，避免把所有
   标点先假定成 1em 再散落减法补丁。
3. `tiqian-linebreak` 提供 UAX #14、强制换行、西文按词断行与连字符断词候选。
4. line breaker 按 `ClreqProfile` 选择断点，并通过 PushIn、Hang、CarryPrevious、
   CarryNext 等具名 repair 处理行首行尾禁则。
5. 行调整在合法断行基础上分配可压缩和可拉伸空间，非末行以中文正文两端对齐为基线。
6. annotation、decoration、inline object 与 rich text geometry 在同一份最终行几何上解析。

每一步都把原因写入 `LayoutResult.debug` 和 layout dump。视觉结果与 decision 不一致时，
应修正 pipeline 或平台证据，不能只在前端移动 glyph。

## 前端

### Compose

`tiqian-compose` 提供两类入口：

- 接受 `String` 或 `AnnotatedString` 的 `CjkText` 用于低成本替换 Compose `Text`；
- `CjkText(blocks = ...)` 用于显式的段落、节与列表结构。

Compose 前端把 `AnnotatedString` 与 `TextStyle` lowering 成核心输入，并用
`cjkTextCompatibility()` 报告当前无法完整保真的能力。Skia 与 Android renderer 重放
`LayoutResult` 的 glyph 和 annotation geometry，不自行重新排版。

### Web

`tiqian-web` 发布本地 ESM 包 `@tiqian/web` 与 light-DOM `<tiqian-prose>`。服务器输出的
HTML 先保持可读，Wasm 与字体准备完成后再逐段增强。原 `<p>`、链接、代码、强调、自定义
inline 与 CSS 仍由宿主持有；引擎只写入断行和 spacing geometry。

不支持或无法稳定测量的段落原子回退为原生 DOM。无 JavaScript、异步加载失败、复制、
Pagefind 和客户端路由都以原始语义 HTML 为基础。详细边界见
[ADR 0039](adr/0039-web-rendering-path.md)。

### Android View

`tiqian-android-view` 目前只保留前端契约，还不是与 Compose / Web 同等完整的可用入口。

## 模块职责

- `tiqian-core`：平台无关的数据结构与 layout contract，不依赖其他提椠模块。
- `tiqian-font`：字体角色、fallback 与字体度量策略。
- `tiqian-shaping-*`：平台 shaping contract 及其实现。
- `tiqian-linebreak`：断行机会、西文断词与相关数据。
- `tiqian-clreq`：中文 profile、标点分类、禁则与空间策略。
- `tiqian-layout`：段落布局、修复、行调整与结构化 decision。
- `tiqian-compose`、`tiqian-web`、`tiqian-android-view`：前端 lowering 与呈现。
- `tiqian-demo`：Desktop / Android 共用的 Compose 示例界面与 Desktop 启动入口。
- `tiqian-demo-android`：只负责 Android 应用打包和启动的薄外壳。
- `tiqian-test` 与 `tiqian-layout` 的报告任务：共享语料、布局诊断和文档样张生成。

## 不变量

跨模块改动应始终保持以下约束：

1. source text 与 source range 不因显示替换或软换行改变；
2. 测量和绘制尽量使用同一字体、glyph 与 placement；
3. 平台层不拥有排版规则；
4. 每个 heuristic 与 capability fallback 都有名称、decision 和测试；
5. renderer 不持有第二份布局真值；
6. 新能力不能以破坏无 JavaScript、复制、搜索或无障碍语义为代价。

## 文档关系

- 本文描述**当前架构**。
- [roadmap](roadmap.md) 描述**当前工作与实施状态**。
- [ADR](adr/README.md) 记录**为什么选择当前方案，以及方案如何修订**。
- [CLREQ gap audit](clreq-gap-audit.md) 与
  [标点码点审计](clreq-punctuation-audit.md) 记录**规范要求与实现证据**。
- [初始设计备忘录](cjk-layout-engine-design.md) 与 `docs/research/` 保留**历史背景和研究快照**。
