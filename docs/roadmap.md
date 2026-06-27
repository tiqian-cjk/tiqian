# 提椠 Roadmap

把 [cjk-layout-engine-design.md](cjk-layout-engine-design.md) 的 M1–M5 和 [multi-agent-collaboration.md](multi-agent-collaboration.md) 的 Slice 0–4 合并成一张可执行表。状态字段在每次产出对应 PR 时更新：

- `done` — 已合入 main 且有 fixture + 测试覆盖。
- `wip` — 有 commit 但还没满足验收清单。
- `todo` — 还没开始。

中文排版思维约束见 [research/kongque-notes.md](research/kongque-notes.md) 与 [adr/0007-grid-first-explainable-cjk-typography.md](adr/0007-grid-first-explainable-cjk-typography.md)。禁则档/悬挂随行长的实测见 [research/kinsoku-hanging-line-width-experiment.md](research/kinsoku-hanging-line-width-experiment.md)。

「当前位置」一行用来让任何 agent / 维护者一眼知道下一步该做什么。

## 当前位置

```text
Last completed: **Android backend shape-once/draw-positioned-glyphs**（2026-06-25，Slice 28）。真实应用 dogfood 暴露出 Android measure/draw 仍可能二次 shaping 分叉：`Glyph` 增加 glyph origin 与 opaque platform font key；Android shaper 保存 `PositionedGlyphs` 的 id/x/y/Font；Android renderer 在 API 31+ 优先用 `Canvas.drawGlyphs` 重放 `LayoutResult.glyphRuns`，不再靠字符串绘制碰运气；同一设备 repro pin 住破折号 glyph placement 与 Font key。Android backend 当前能力边界就是 API 31+；若未来支持 API 30-，另起低版本 backend slice。
之前:          **Compose migration contract hardening**（2026-06-25，Slice 27）。真实应用 dogfood 暴露出“compatibility report 被误读成回退开关”和“Android renderer 用 dash scaling 掩盖 backend 不同源”的方向问题：`cjkTextCompatibility` 改为 capability issue report；`CjkParagraph` 把 source `AnnotatedString` 暴露给 Compose semantics；`LayoutResult` 新增 line/offset/box/range/position 查询，Skia/Android renderer 共用同一 positioned-cluster 几何；撤销 Android dash renderer scaling。
之前:          **Compose Text interop**（2026-06-24，ADR 0036，2026-06-25 修订）。真实应用迁移入口改为 `AnnotatedString + androidx.compose.ui.text.TextStyle`：`CjkParagraph`/`CjkText`/`ParagraphMeasurer.measure` 增加 Compose `style` overload，`TextStyle.toCjkTextStyle()` 负责降到窄而诚实的引擎样式；新增 `AnnotatedString.cjkTextCompatibility(style)`，把链接、inline placeholder、未知 annotation、背景/下划线/阴影/字距、非 generic font family、Compose 段落控制等无法保真的能力输出为结构化 capability issue。结论：应用接入点必须在富文本 renderer 已生成 Compose 段落模型之后，而不是 Markdown AST/HTML 层重建 reduced `AnnotatedString`；compatibility report 是提椠缺口清单，不是库内回退到 Compose Text 的开关。
之前:          **Android Compose gallery**（2026-06-22，ADR 0035）。`tiqian-compose` 从 Desktop/JVM-only 升为 Android + JVM：公共 Compose API 下沉到 `commonMain`，平台 actual 分别提供默认 measurer 与 renderer；Android 端走 `AndroidPaintTextShaper` + `AndroidFontMetricsResolver` + `Canvas.drawTextRun`（Han context 与 shaper 同源），上游 core/font/shaping-api/linebreak/clreq/layout 补 Android-KMP variant，gallery 入口独立为 `tiqian-gallery-android` app（富文本 + 列表 + 拼音/注音 + 行间线 + ic 缩进）。AGP 9 采用官方 `com.android.kotlin.multiplatform.library`，Android app 与 KMP library 分模块。Android 默认西文断词走 `AndroidLineBreakerHyphenator`：用公开 `LineBreaker` 作平台 oracle，既能探测实际触发 end-hyphen edit 的词内 offset，也通过 `LineWidthHyphenator` 接收 layout 宽度给出平台偏好的单个断点；它不承诺枚举全部断点，也不承诺 TeX/golden 稳定。
之前:          **Compose API 收口**（2026-06-21，两轮 Codex 评审）。作者面定形：**`CjkTextStyle`**（Compose 原生 `.sp`/`Color`/`FontFamily`，composable 边界用 `LocalDensity` 降成引擎 px——不再手乘 density；窄而诚实，不复用 Compose 30 字段 TextStyle）；富文本进**多段/列表**（`CjkBlock.Paragraph`/`List` 承载 `AnnotatedString`，`String` 留便捷）；出口 `onTextLayout`(段) + `onParagraphLayout`(文档逐段/项) + `measure(AnnotatedString)`(预排版)；wire-protocol（tag/extractor）转 `internal`、builder（`emphasis`/`ruby`/`bopomofo`/`properNoun`/`mourning`/`bookTitle`）public 去前缀；`ColorSpan` 进 core、`compose.runtime`/`ui` 改 `api`、`clipToBounds`（高度约束=绘制一致）、`measurer` 独占 profile 源、`.sp` 经 density 正确转 px、命名收口 `CjkParagraph`/`CjkText`。**未做（引擎阶段过早）**：a11y semantics、baseline alignment line
之前:          **注音 ruby**（2026-06-20，ADR 0033）+ **字身框度量 BASE ideo/idtp**（ADR 0002 amend）+ **`ic` 字身框单位**（2026-06-21，ADR 0034）。`ic` = W3C CSS 表意字身 advance，提椠用 BASE ideo/idtp 解析；`ParagraphStyle.firstLineIndent/blockIndent`、`CjkBlock.List.indent`、`ParagraphIndent`、`Float.ic/Int.ic` 全改用 `Ic`（段级锚段落 fontSize；数值同旧 em，零 golden 漂移）。内部 CLREQ/ruby em 常量暂留 Float（概念上 ic，待行内锚点收口）
之前:          富文本 per-span 样式（2026-06-19）——ADR 0030 **A 档颜色** + **B 档 字号/字重/斜体**：`TiqianTextContent.spans`（拍平成无重叠、整解析的 `TextSpan`，字号/字重/斜体/颜色可叠加）进引擎，span 边界切 cluster，per-segment shaping（按 `FontStyle(weight, slant)` 选真粗体/斜体 typeface，advance 真）+ per-cluster 度量；renderer 同样按 per-cluster `FontStyle`+字号取 styled typeface 绘制。混排 em 按「空白归属者字号」（中西间距=汉字、标点=标点、grid/缩进=段落，边角取小）。粗/斜共用纵向度量 → 行高不变。v1 限定：行高取整段 max、边界 em 仍段落基准、基线共享。无 span 时逐字节同旧 golden（默认 `(400,upright)`==`FontStyle.NORMAL`）
Last（同日）:    **行调整方向**（ADR 0031）落地：CLREQ §6.2.2「先挤进/后推出」+「先挤压/后拉伸」。`Justifier.compress`（压缩档序分配器）+ `LineAdjustmentStrategy{Auto/PushInFirst/PushOutFirst/PushOutOnly}`（默认 Auto，`compressBias`=2）+ `applyFillPushIn`（复用 `tryPushIn`，避头尾 PushIn 的兄弟 pass）：短行不再一律拉伸，越界字「挤一挤放得下」且压缩偏差更小（bias 加权）时推入压缩。选择性非全行（避开 ADR 0022 否决的 floor 填行）；守 unbreakable/forbidden/已修复行。golden 重生成（dump 区分 `LineAdjustmentPushIn` vs `ForbiddenAtLineStart`）
之前（同日）:   **列表**（CLREQ §6.2.1.1 凸排）：`CjkBlock.List` + `ListMarker`（`1.`/`一、`/`①`/`•`），标记左对齐顶格、正文固定列缩进续行对齐（Compose 双列，引擎零改动），列宽默认 1 字、自动按最宽标记升整字数（`10.`→2 字）、`indent` 可覆盖
行间注 第一刀: **拼音 ruby**（ADR 0032）落地——`RubySpan(baseRange, text, fontFamilies)` 进 `LayoutInput.rubySpans`；注文居中基字上方、注文专用字体、行高均匀预留带、基文不可拆。**避让**（CLREQ §罗马拼音）：相邻注文留「一个注文词空格」(≈0.25×注文字号)，注文宽实测、只在不够时补最小字距（结构性 advance，断行前注入）、够了悬出不撑；注文字号 0.5em（CLREQ 振假名 1/2 惯例）；垂直摆位让降部越过字身顶。作者面 `cjkRuby("北京","Běijīng"[, fontFamily])`（注文不进源）。无 ruby 时零漂移。**第二刀 注音**（右侧竖排 ㄅㄆㄇ+调号+半字预留）= 下一个 ADR。
富文本完结:    color / 字号 / 字重 / 斜体 / 双语强调 / **字体 family**（generic，role-aware；自定义字体待接）/ 列表——全部落地（ADR 0030）。剩：列表续档；per-cluster 度量随族/字重变（行高）。
Up next:        Android 真机/模拟器截图验收与性能观测；把 Android gallery 中发现的字体/metrics/LineBreaker 差异回写为 fixture 或 capability report。第二阶段（竖排 / web）等模型冻结、考虑 Rust core 后再起；西文连字零散后续：整段最优连字、数据断词器可插拔化
```

## Slice / Milestone 对照表

| Slice | Milestone | 目标（一句话） | 验收 fixture | 验收命令 | 状态 |
|------|-----------|----------------|--------------|----------|------|
| 0 | — | 项目骨架、core data model、空 layout pipeline、playground 占位 | `tiqian-test` 现有 fixture | `./gradlew build` + `./gradlew :tiqian-playground:runPlayground` | done |
| 1 | M1 | 字体 fallback 可解释（CJK 标点优先 CJK；省略号/破折号不被 Latin 接管；Latin word 仍走 Latin） | `中文……English——中文。` | `./gradlew :tiqian-layout:jvmTest` + 检查 dump `font:*` 行 | done |
| 2 | M1 | RawFontMetrics ↔ LayoutFontMetrics 分离；`CenteredCjkVisual` policy 默认开启 | 任意含汉字 fixture | `./gradlew :tiqian-font:jvmTest`；dump `metrics:*` 行显示 `raw(...)->layout(...)` | done |
| 3 | M2 | PunctuationAtom（ink/body/leadingGlue/trailingGlue）；行尾标点自然半宽；连续标点挤压；引号 / 括号成对感知 | `中文，中文。` `他说：“你好，世界。”` `中文……中文。` `中文(English)中文` | dump `punct:*` / `spacing:*` / `geom:*` 行；`QuotePairAnalyzerTest`；`AwtSkiaShapingComparisonTest` | done (`PunctuationAtomBuilder` / spacing compression / `QuotePairAnalyzer` / `LineEdgeGlueTrim` / `PunctuationGeometryLedger` / AWT shaped `inkBounds` 校准 + `halt` body 全 done；括号成对感知由分类承担——ASCII 括号→Latin、全宽（）→Opening/Closing，无需独立 analyzer，见 ADR 0004 Follow-up 段；平台 adapter 对照 = `AwtSkiaShapingComparisonTest`（逐标点 advance + ink box 侧）；ink box 可视化在 playground HTML 报告) |
| 3.5 | — | Explainability hardening：结构化 decision 类型替代 stringly dump；SpacingPlan 替代 advance mutation；classifier 接 profile；可重复标点进 clreq 表；role override 进 dump | 现有所有 fixture 不变 | 所有现有测试绿；`LayoutResult` 暴露结构化 `clusterDecisions / spacingPlan` 字段 | done |
| 4 | M3 | BreakCandidate / RepairOption；`PushIn` `CarryPrevious`；greedy + lookahead；`Hang` 仅保留 profile opt-in 路径 | `kinsoku-carry-previous` `kinsoku-push-in` `lookahead-future-push-in` `lookahead-avoids-repair` | `./gradlew :tiqian-layout:jvmTest` + `./gradlew :tiqian-playground:runPlayground`；dump `line:*` 行，多行非单 placeholder | done (`PushIn` / `CarryPrevious` / `LeaveRagged` 有结构化 chosen repair + candidates；PushIn 支持全行 capacity 聚合与 zero-shrink merge；CarryPrevious 会验证 carried line 不超宽；lookahead 默认 window 2（`LookaheadWindowProbe` 实测 w3 无增益）；Hang 推到后续 opt-in slice) |
| 5 | M4 | 两端对齐：基于 glue 的 AdjustmentOpportunity；优先级 `PunctuationGlue → CjkLatinSpace → WordSpace → CjkInterChar` | 中文正文段落 + 中西混排 fixture | dump 每行 `adjustedWidth` ≈ `maxWidth`；新 golden | done (`Justifier` + `JustificationDecisionInfo`；`textAlign=Justify` 触发；最后一行 skip；priority chain 完整；`GlueSideAwareJustification`：collapse 不可逆、扩展只在 glue 侧、括号内侧免疫，见 ADR 0004 amendment；WordSpace 待 shaping 分词后启用) |
| 6 | M5 | API 固化；`tiqian-shaping-android` / `tiqian-shaping-skia` 真 adapter；golden test + benchmark | 平台 fixture + screenshot golden | 各平台模块 build + screenshot 测试 | done (6a: shaping contract + `ExplainableStubTextShaper`；6b: `tiqian-shaping-jvm`/`tiqian-shaping-skia`/`tiqian-shaping-android` 三平台 adapter + AWT↔Skia 对照 golden + Android instrumentation 对照 + `LocaleTaggedShaping` + `FontHaltDerivedBody` + `HanContextShaping` + playground skia 光栅化；验收: `LayoutDumpGoldenTest` 结构化 dump golden（`TIQIAN_UPDATE_GOLDEN=1` 再生成）+ `LayoutBenchmarkProbe` 吞吐基线 + 包名/geometry source 固化（`org.tiqian.*`、`ProfileDerived*`）；ADR 0008/0013/0014/0015/0016；`chws` 明确不启用) |
| 7 | — | Compose Desktop 前端真渲染：`CjkParagraph` composable 消费 `LayoutResult`，Skia TextBlob 绘制与 engine 度量同源，前端零排版决策 | 现有 fixture 文本 + 离屏渲染 PNG | `./gradlew :tiqian-compose:jvmTest`（ImageComposeScene 离屏渲染）+ `runComposeDemo` | done (`CjkParagraph` + `rememberParagraphMeasurer` 默认 Skia shaper/lookahead；渲染走 `tiqian-shaping-skia` 共享 `shapeTextBlob`/`SkiaSystemTypefaces`；离屏 PNG 验收 + demo 窗口人工确认；根构建统一 jvmToolchain(25)；ADR 0017) |
| 8 | — | Inline decoration span 模型 + 着重号：`LayoutInput` 接受区间标注，layout 产出逐字 dot 几何决策，渲染层照画 | `emphasis-marks` fixture（跨行、含标点） | dump `deco:*` 行；playground/compose 渲染目检 + golden | done (`DecorationSpan`/`DecorationKind.Emphasis` 输入；`EmphasisDotOnHanText` 逐字决策，标点跳过有 CLREQ 原文 reason；anchor=baseline+0.35em 紧贴字底；U+2022 glyph 渲染 ink-center 对位（skia/compose），AWT raster 圆形近似；golden + 单测；ADR 0018) |
| 9 | — | 示亡号：span 区间的黑框几何（按行分段），断行策略明确（整体避拆 or 分段开口） | `mourning-frame` fixture | dump `decobox:*` 行；渲染目检 + golden | done (`DecorationKind.Mourning`；`MourningSpanKeptUnbroken` 进 breaker `unbreakableRanges`，超宽 fallback 分段 openStart/End；CarryPrevious 防拆 guard；框竖直边用 raw ink metrics（layout em box 会切字形）；golden + 单测；ADR 0018) |
| 10 | — | 中西混排间距补全：无空格边界插入 1/4em（CLREQ 原文），Insert 为默认 mode | `justify-mixed-paragraph` `ascii-brackets-in-cjk` fixture | dump `autospace` 行 reduction 为负；golden + 渲染目检 | done (`TextAutoSpaceInsert`；decision mode 记实际动作；行边 trim 复用；ADR 0009 amendment) |
| 11 | — | justify 拉伸对齐 CLREQ：去标点优先档，标点 glue 侧并入均匀 CjkInterChar | `real-paragraph-1` golden 中 justify 全为均匀份额 | golden diff review | done (拉伸链 WordSpace→CjkLatinSpace→CjkInterChar；collapse 不可逆与实心侧禁令保留；ADR 0004 amendment、design doc 取舍废止) |
| 12 | — | Latin 分词：词/空格独立 cluster，长西文按词换行，词空格参与 justify，行边空格塌缩 | `latin-word-wrap` fixture | golden + 渲染目检；`longLatinSentenceWrapsAtWordBoundaries` 等单测 | done (`LatinWordSegmentation` shaping 输入层分段；空格三种身份：中西 gap/词空格/行边塌缩；WordSpace 档启用；ADR 0019) |
| 13 | — | 挤压分层对齐 CLREQ：六档 `ShrinkOpportunity`（行末削半→词距→间隔号双侧→行内句问叹→中西间距→其余 glue），`AdjustmentStylePolicy` 三开关 | `latin-word-wrap` golden（词距先于行内 `，` 被压）+ 三开关单测 | golden diff review；`PushInLineWideCapacityTest` tier 顺序断言 | done (严格 tier 耗尽 + 同档比例分摊；offender trailing glue 晋升 tier 1；`lineEndOnly` 隔离行末削半与行内压缩；行末强制半宽默认、宽松风格 opt-in；ADR 0020) |
| 14 | — | 段首缩进：`firstLineIndentEm` 默认两字宽，首行行宽收窄 + `LineBox.indent` 渲染偏移，首行开括号半宽缩减由既有行首 glue trim 自然组合 | `first-line-indent` `indent-opening-quote` fixture；`real-paragraph-1` 带缩进 | golden + 单测 + playground 目检 | done (breaker/justify/decoration 全链路 indent 感知；fixture/单测 pin 0 隔离；ADR 0021) |
| 15 | — | 双齐为基线：删 `TextAlign`，非末行恒走 justify 链；`lastLineAlignment` Start/Center/End 经 `LineBox.indent` 控末行 | 全部多行 fixture（非末行 visual≈maxWidth）；`lastLineAlignmentPositionsTheLastLineViaIndent` 单测 | golden diff review + playground 目检 | done (单行段落即末行，标题/标签不被拉伸；渲染层零改动；ADR 0023) |
| 16 | — | 行间线：`ProperNoun`/`BookTitle` decoration，一项一线、贴字 +0.18em、随 justify 延长、相邻侧回缩 1/16em，直线/波浪线渲染 | `interlinear-lines` fixture（含相邻专名） | golden + 几何单测 + playground 目检 | done (segment 几何复用示亡号通道；`AdjacentInterlinearLineShortening`；行距 floor 自动生效；ADR 0024) |
| 17 | — | 行尾点号悬挂 opt-in：`AdjustmentStylePolicy.hangingPunctuation`（默认关，顿逗句），kinsoku 链 PushIn→Hang→Carry→Ragged，悬挂标点出版心、内容满排 | `hangingPunctuationFillsLineToMeasureAndOverflowsVisual` 等单测 | `./gradlew :tiqian-layout:jvmTest` | done (`LineEndHangingPunctuation`；measure-fill 排除悬挂、visualWidth 溢出；行尾只挂一个；渲染零改动；ADR 0006 amendment) |
| 18 | — | 按行长自适应禁则档 + 悬挂：`KinsokuMode.MeasureAdaptive` 默认（<14 字悬挂 / >24 GB / >32 严格），决策入 dump；阈值由 Wikipedia/文学体语料实测标定 | golden `kinsoku` 决策行；`measureAdaptiveResolvesPerLineWidth` 单测；`KinsokuHangingExperimentProbe` | golden diff + `:tiqian-clreq:jvmTest` | done (合并 `kinsokuLevel`/`hangingPunctuation` 为 `kinsokuMode`；repair fixture pin Fixed；ADR 0025) |
| 19 | — | 行长字号整数倍量化：`LineLengthGridQuantization` 向下取整 maxWidth 到 N×fontSize 版心，`GridBodyAlignment` 用余量按末行对齐在容器内摆放正文，默认开、可 `LineLengthGrid(enabled=false)` 旁路 | `lineLengthGridFloorsMeasure…` / `…CanBeBypassed` 单测；非整数倍 fixture golden | golden diff review + playground 目检 | done (默认开=响应式常态；纯汉字行落格后 justify 余量归零；决策入 dump；ADR 0028) |
| 20 | — | 段首缩进随行长自适应（`MeasureAdaptiveFirstLineIndent`）：窄行<14 字缩 1 字、宽行 2 字，阈值独立于悬挂、`Fixed` 下仍生效；`firstLineIndentEm` 改 `Float?` 显式覆盖 | `firstLineIndentAdaptsToMeasure…` 单测；`adaptive-short-line-indent` fixture golden | golden diff + playground 目检 | done (ADR 0021 amendment；决策入 dump) |
| 21 | — | 中西混排西文音节连字：`tiqian-linebreak` `Hyphenator`/`LiangHyphenator` + 内置 en-US TeX 模式；引擎 `LineEndHangingHyphen` 拆音节 cluster、行尾悬挂连字符（不占版心）；`LatinForcedHyphenBreak` 超宽片段补连字符硬断（前二后三）；**默认启用**（`defaultHyphenator()` expect/actual，JVM=en-US） | `LiangHyphenatorTest`/`EnglishHyphenationTest`/`HyphenationLayoutTest`；`western-hyphenation` / `latin-hard-break` fixture golden | golden + `:tiqian-linebreak:jvmTest` + playground 目检 | done (确定性测试 pin `NoHyphenator` ⇒ 既有 golden 零漂移；源文本不动；ADR 0029) |
| 22 | — | §6.2.1 段落调整：`ParagraphStyle.blockIndentEm`（整段缩进，`firstLineIndentEm` 相对叠加、可负）覆盖 段首缩进/不缩/凸排/段落缩排；Compose `CjkText` 块/节文档模型（`CjkBlock.Paragraph(indent)`/`Section`，空行=节，每段独立 `ParagraphIndent`，跨段行距一致） | `blockIndentInsetsEveryLine`/`hangingIndentFlushesFirstLineAndInsetsRest` 单测；`CjkTextRenderTest`（凸排+段落缩排+节 同屏 PNG） | `:tiqian-layout:jvmTest` + `:tiqian-compose:jvmTest` + PNG 目检 | done (breaker 零改动——喂正文宽+相对首行缩进，`block=0` golden 零漂移；唯凸排「人名不足三字补空白」niche 未做) |
| 23 | — | 富文本 per-span 样式（ADR 0030）：**A 档颜色**（`SpanStyle.color` 纯渲染、零引擎）+ **B 档 字号/字重/斜体**（`SpanStyle.fontSize/fontWeight/fontStyle`：`TiqianTextContent.spans`〔Compose 侧拍平成无重叠整解析 `TextSpan`，四样可叠加〕进引擎，span 边界切 cluster，per-segment shaping〔`FontStyle(weight,slant)` 选真粗/斜 typeface，advance 真〕+ per-cluster 度量，renderer 同样按 per-cluster `FontStyle`+字号取 styled typeface；`.em` 相对段落基准）；混排 em 按归属者字号 | `colorSpansExtractedFromSpanStyle`/`spanColorsPaintTheirClusters`/`sizedSpanScalesAdvanceAndLineHeight`/`boldSpanWidensLatinWord` | `:tiqian-compose:jvmTest` + 全量 golden 零漂移 + PNG 目检（粗/斜/大/色叠加） | done (无 span 时逐字节同旧 golden〔默认 `(400,upright)`==`FontStyle.NORMAL`〕；粗/斜共用纵向度量→行高不变；v1 限定：行高整段 max、边界 em 段落基准、基线共享；字体 family 续档) |
| 24 | — | 凸排列表（CLREQ §6.2.1.1）：`CjkBlock.List(items, marker, indent?, start)` + `ListMarker`（`Decimal 1.`/`CjkNumber 一、`/`Circled ①`/`Bullet •`）。标记左对齐顶格于固定宽「标记列」，正文整列缩进、续行同列对齐（Compose 双列 gutter `Box`+正文 `Row.weight`，引擎零改动）；列宽默认 1 字、自动按最宽标记升最小整字数（`10.`→2 字，`autoListGutterEm` 实测裸宽非数位），`indent` 覆盖；marker/正文零段首缩进 | `markersFormatPerKind`/`gutterDefaultsToOneZiAndBumpsForTwoDigits`/`explicitIndentOverridesAuto` | `:tiqian-compose:jvmTest` + 全量 golden 零漂移 + PNG 目检（续行对齐 + `10.` 升列） | done (纯 `CjkText` 组合糖，引擎零改动；嵌套/富文本项续档) |
| 25 | — | Android Compose gallery：`tiqian-compose` 提供 Android target，公共 Compose API 进入 `commonMain`，Android backend 走 `TextPaint`/`Canvas.drawTextRun` 与 `AndroidPaintTextShaper` 同源；独立 app gallery 展示富文本/列表/ruby/注音/ic | `tiqian-gallery-android` debug app | `:tiqian-compose:compileAndroidMain` + `:tiqian-gallery-android:assembleDebug` + `:tiqian-compose:jvmTest` | done (ADR 0035；Android 默认断词走 `AndroidLineBreakerHyphenator` + `LineWidthHyphenator`，平台 oracle，不枚举全部断点) |
| 26 | — | Compose Text interop：从真实应用的 `AnnotatedString + androidx.compose.ui.text.TextStyle` 迁移到 Tiqian，不在 Markdown AST/HTML 层重建富文本；新增 Compose `style` overload、`TextStyle.toCjkTextStyle()`、`AnnotatedString.cjkTextCompatibility(style)` 结构化 capability issue | `CjkTextCompatibilityTest`（支持子集无 issue；链接/inline placeholder/未知 annotation/背景/字距/段落控制触发 capability issue） | `:tiqian-compose:jvmTest --tests 'org.tiqian.compose.CjkTextCompatibilityTest'` | done (ADR 0036；窄 `CjkTextStyle` 继续作为作者面，Compose interop 作为迁移面；report 不驱动库内回退) |
| 27 | — | Compose 迁移契约止偏：`cjkTextCompatibility` 明确为 capability report 而非 host-renderer 路由；`CjkParagraph` 暴露 source `AnnotatedString` 到 semantics；`LayoutResult` 提供 line/offset/box/range/position 查询，Skia/Android renderer 共享同一 positioned-cluster 几何；撤销 Android dash renderer scaling | `LayoutQueriesTest` + `CjkTextCompatibilityTest` | `:tiqian-core:jvmTest` + `:tiqian-compose:jvmTest` + `:tiqian-compose:compileAndroidMain` | done (2026-06-25；暴露出的 Android backend 同源绘制缺口已由 Slice 28 接上) |
| 28 | — | Android backend 同源绘制：`Glyph` 承载 glyph origin 与 opaque platform font key；Android shaper 保存 `PositionedGlyphs` 的 id/x/y/Font；Android renderer 在 API 31+ 用 `Canvas.drawGlyphs` 重放 `LayoutResult.glyphRuns`，避免 draw 阶段二次 shaping 分叉 | `AndroidDashPunctuationReproTest.androidLayoutKeepsGlyphFontAndPlacementForDashRendering` | `:tiqian-compose:compileAndroidMain` + `:tiqian-shaping-android:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.tiqian.shaping.android.AndroidDashPunctuationReproTest` | done (2026-06-25；当前 Android backend 诚实声明 API 31+；API 30- 不属于本次 dogfood 目标，未来如需支持另起 backend slice) |

Slice 15 的依据（CLREQ 原文）：

> 「与西文排版不同，中文排版特别是书籍正文排版极少使用左齐右不齐，原则上
> 应该进行两端对齐。西文排版两端对齐（justification）时，主要是调整单词
> 之间的间隙（词距），而中文排版在两端对齐时，能调整的地方更多，具体如下
> 所述。」

——双齐不是可选项而是基线，对齐的自由度只在末行（齐左/居中/齐右）。

Slice 4 的 `done` 范围是当前默认 kinsoku repair：`PushIn` / `CarryPrevious` / `LeaveRagged` 均可解释，`LineDecisionInfo` 暴露 chosen repair 与 candidate repairs。lookahead window 2~3 属于后续优化，不再阻塞当前 Slice 4 的模型收口。

Slice 0–22 全部 `done`，第一阶段（CLREQ 简体横排）覆盖收口——gap audit 七缺口 + 自适应默认 + grid-first 整数行长 + 中西混排西文连字 + §6.2.1 段落调整（多段/凸排/段落缩排/节）均落地。本阶段剩下的真实需求只有**注音/ruby**（含 §符号分离禁则·注释符号），单独成 slice、随竖排意愿评估。下一步是在 Compose gallery 上把模型用稳；竖排 / web 属第二阶段（见「不在第一阶段做的」），web 倾向等 Rust core。

## 不在第一阶段做的

明确推到后面，不在 roadmap 主线上：

- 竖排 / JLREQ profile。
- Ruby、注音、纵中横。
- 分页、多栏、脚注。
- 编辑器、IME、复杂 selection。
- 完整 CSS Text 兼容。

这些可以预留接口（写 ADR 记录预留点），但不应该有「半完成」实现。

## 怎么用这张表

- 接到任务先确认它属于哪一行；如果不属于任何一行，先开一条新 slice 或写 ADR。
- PR 描述里引用 slice 行号；合入后把状态改成 `done`，并把「当前位置」往前推一格。
- 一个 slice 跨多个 PR 是正常的——但只有验收 fixture + 测试 + dump 三件都满足才能改 `done`。
