# 提椠 Roadmap

把 [cjk-layout-engine-design.md](cjk-layout-engine-design.md) 的 M1–M5 和 [multi-agent-collaboration.md](multi-agent-collaboration.md) 的 Slice 0–4 合并成一张可执行表。状态字段在每次产出对应 PR 时更新：

- `done` — 已合入 main 且有 fixture + 测试覆盖。
- `wip` — 有 commit 但还没满足验收清单。
- `todo` — 还没开始。

中文排版思维约束见 [research/kongque-notes.md](research/kongque-notes.md) 与 [adr/0007-grid-first-explainable-cjk-typography.md](adr/0007-grid-first-explainable-cjk-typography.md)。

「当前位置」一行用来让任何 agent / 维护者一眼知道下一步该做什么。

## 当前位置

```text
Last completed: Slice 9 (示亡号：黑框分段几何 + 整体避拆，ADR 0018)
Up next:        新 slice 规划：候选有行尾悬挂 opt-in (ADR 0006)、WordSpace (Latin 分词)、Android composable 渲染、竖排预研；更远期：行尾悬挂 opt-in、WordSpace、Android composable 渲染、竖排预研
```

## Slice / Milestone 对照表

| Slice | Milestone | 目标（一句话） | 验收 fixture | 验收命令 | 状态 |
|------|-----------|----------------|--------------|----------|------|
| 0 | — | 项目骨架、core data model、空 layout pipeline、playground 占位 | `tiqian-test` 现有 fixture | `./gradlew build` + `./gradlew :tiqian-playground:runPlayground` | done |
| 1 | M1 | 字体 fallback 可解释（CJK 标点优先 CJK；省略号/破折号不被 Latin 接管；Latin word 仍走 Latin） | `中文……English——中文。` | `./gradlew :tiqian-layout:jvmTest` + 检查 dump `font:*` 行 | done |
| 2 | M1 | RawFontMetrics ↔ LayoutFontMetrics 分离；`CenteredCjkVisual` policy 默认开启 | 任意含汉字 fixture | `./gradlew :tiqian-font:jvmTest`；dump `metrics:*` 行显示 `raw(...)->layout(...)` | done |
| 3 | M2 | PunctuationAtom（ink/body/leadingGlue/trailingGlue）；行尾标点自然半宽；连续标点挤压；引号 / 括号成对感知 | `中文，中文。` `他说：“你好，世界。”` `中文……中文。` `中文(English)中文` | dump `punct:*` / `spacing:*` / `geom:*` 行；`QuotePairAnalyzerTest` `BracketPairAnalyzerTest` | wip (`PunctuationAtomBuilder` / spacing compression / quote pair / bracket pair / `LineEdgeGlueTrim` / `PunctuationGeometryLedger` / AWT shaped `inkBounds` 校准都 done；剩余平台 adapter 对照与 ink box 可视化) |
| 3.5 | — | Explainability hardening：结构化 decision 类型替代 stringly dump；SpacingPlan 替代 advance mutation；classifier 接 profile；可重复标点进 clreq 表；role override 进 dump | 现有所有 fixture 不变 | 所有现有测试绿；`LayoutResult` 暴露结构化 `clusterDecisions / spacingPlan` 字段 | done |
| 4 | M3 | BreakCandidate / RepairOption；`PushIn` `CarryPrevious`；greedy + lookahead；`Hang` 仅保留 profile opt-in 路径 | `kinsoku-carry-previous` `kinsoku-push-in` `lookahead-future-push-in` `lookahead-avoids-repair` | `./gradlew :tiqian-layout:jvmTest` + `./gradlew :tiqian-playground:runPlayground`；dump `line:*` 行，多行非单 placeholder | done (`PushIn` / `CarryPrevious` / `LeaveRagged` 有结构化 chosen repair + candidates；PushIn 支持全行 capacity 聚合与 zero-shrink merge；CarryPrevious 会验证 carried line 不超宽；lookahead 默认 window 2（`LookaheadWindowProbe` 实测 w3 无增益）；Hang 推到后续 opt-in slice) |
| 5 | M4 | 两端对齐：基于 glue 的 AdjustmentOpportunity；优先级 `PunctuationGlue → CjkLatinSpace → WordSpace → CjkInterChar` | 中文正文段落 + 中西混排 fixture | dump 每行 `adjustedWidth` ≈ `maxWidth`；新 golden | done (`Justifier` + `JustificationDecisionInfo`；`textAlign=Justify` 触发；最后一行 skip；priority chain 完整；`GlueSideAwareJustification`：collapse 不可逆、扩展只在 glue 侧、括号内侧免疫，见 ADR 0004 amendment；WordSpace 待 shaping 分词后启用) |
| 6 | M5 | API 固化；`tiqian-shaping-android` / `tiqian-shaping-skia` 真 adapter；golden test + benchmark | 平台 fixture + screenshot golden | 各平台模块 build + screenshot 测试 | done (6a: shaping contract + `ExplainableStubTextShaper`；6b: `tiqian-shaping-jvm`/`tiqian-shaping-skia`/`tiqian-shaping-android` 三平台 adapter + AWT↔Skia 对照 golden + Android instrumentation 对照 + `LocaleTaggedShaping` + `FontHaltDerivedBody` + `HanContextShaping` + playground skia 光栅化；验收: `LayoutDumpGoldenTest` 结构化 dump golden（`TIQIAN_UPDATE_GOLDEN=1` 再生成）+ `LayoutBenchmarkProbe` 吞吐基线 + 包名/geometry source 固化（`ink.duo3.tiqian.*`、`ProfileDerived*`）；ADR 0008/0013/0014/0015/0016；`chws` 明确不启用) |
| 7 | — | Compose Desktop 前端真渲染：`TiqianParagraph` composable 消费 `LayoutResult`，Skia TextBlob 绘制与 engine 度量同源，前端零排版决策 | 现有 fixture 文本 + 离屏渲染 PNG | `./gradlew :tiqian-compose:jvmTest`（ImageComposeScene 离屏渲染）+ `runComposeDemo` | done (`TiqianParagraph` + `rememberTiqianTextMeasurer` 默认 Skia shaper/lookahead；渲染走 `tiqian-shaping-skia` 共享 `shapeTextBlob`/`SkiaSystemTypefaces`；离屏 PNG 验收 + demo 窗口人工确认；根构建统一 jvmToolchain(25)；ADR 0017) |
| 8 | — | Inline decoration span 模型 + 着重号：`LayoutInput` 接受区间标注，layout 产出逐字 dot 几何决策，渲染层照画 | `emphasis-marks` fixture（跨行、含标点） | dump `deco:*` 行；playground/compose 渲染目检 + golden | done (`DecorationSpan`/`DecorationKind.Emphasis` 输入；`EmphasisDotOnHanText` 逐字决策，标点跳过有 CLREQ 原文 reason；anchor=baseline+0.35em 紧贴字底；U+2022 glyph 渲染 ink-center 对位（skia/compose），AWT raster 圆形近似；golden + 单测；ADR 0018) |
| 9 | — | 示亡号：span 区间的黑框几何（按行分段），断行策略明确（整体避拆 or 分段开口） | `mourning-frame` fixture | dump `decobox:*` 行；渲染目检 + golden | done (`DecorationKind.Mourning`；`MourningSpanKeptUnbroken` 进 breaker `unbreakableRanges`，超宽 fallback 分段 openStart/End；CarryPrevious 防拆 guard；框竖直边用 raw ink metrics（layout em box 会切字形）；golden + 单测；ADR 0018) |

Slice 4 的 `done` 范围是当前默认 kinsoku repair：`PushIn` / `CarryPrevious` / `LeaveRagged` 均可解释，`LineDecisionInfo` 暴露 chosen repair 与 candidate repairs。lookahead window 2~3 属于后续优化，不再阻塞当前 Slice 4 的模型收口。

「Slice 3 wip 收尾」的具体待办在 [adr/0004-punctuation-additive-glue-model.md](adr/0004-punctuation-additive-glue-model.md) 的 Follow-up 段。

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
