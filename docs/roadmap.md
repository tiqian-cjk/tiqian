# 提椠 Roadmap

把 [cjk-layout-engine-design.md](cjk-layout-engine-design.md) 的 M1–M5 和 [multi-agent-collaboration.md](multi-agent-collaboration.md) 的 Slice 0–4 合并成一张可执行表。状态字段在每次产出对应 PR 时更新：

- `done` — 已合入 main 且有 fixture + 测试覆盖。
- `wip` — 有 commit 但还没满足验收清单。
- `todo` — 还没开始。

中文排版思维约束见 [research/kongque-notes.md](research/kongque-notes.md) 与 [adr/0007-grid-first-explainable-cjk-typography.md](adr/0007-grid-first-explainable-cjk-typography.md)。

「当前位置」一行用来让任何 agent / 维护者一眼知道下一步该做什么。

## 当前位置

```text
Last completed: Slice 3 wip 续 (bracket pair analyzer), Slice 4 (kinsoku repair + structured repair plan), Slice 5 (justification via glue priority), Slice 6a (shaping contract + stub)
Up next:        Slice 6b (real shaping adapter: Skiko/JVM 或 Android TextPaint，二选一)
```

## Slice / Milestone 对照表

| Slice | Milestone | 目标（一句话） | 验收 fixture | 验收命令 | 状态 |
|------|-----------|----------------|--------------|----------|------|
| 0 | — | 项目骨架、core data model、空 layout pipeline、playground 占位 | `tiqian-test` 现有 fixture | `./gradlew build` + `./gradlew :tiqian-playground:runPlayground` | done |
| 1 | M1 | 字体 fallback 可解释（CJK 标点优先 CJK；省略号/破折号不被 Latin 接管；Latin word 仍走 Latin） | `中文……English——中文。` | `./gradlew :tiqian-layout:jvmTest` + 检查 dump `font:*` 行 | done |
| 2 | M1 | RawFontMetrics ↔ LayoutFontMetrics 分离；`CenteredCjkVisual` policy 默认开启 | 任意含汉字 fixture | `./gradlew :tiqian-font:jvmTest`；dump `metrics:*` 行显示 `raw(...)->layout(...)` | done |
| 3 | M2 | PunctuationAtom（ink/body/leadingGlue/trailingGlue）；行尾标点自然半宽；连续标点挤压；引号 / 括号成对感知 | `中文，中文。` `他说：“你好，世界。”` `中文……中文。` `中文(English)中文` | dump `punct:*` / `spacing:*` / `geom:*` 行；`QuotePairAnalyzerTest` `BracketPairAnalyzerTest` | wip (`PunctuationAtomBuilder` / spacing compression / quote pair / bracket pair / `LineEdgeGlueTrim` / `PunctuationGeometryLedger` 都 done；剩余 `inkBounds` 等 Slice 6 真实 shaping) |
| 3.5 | — | Explainability hardening：结构化 decision 类型替代 stringly dump；SpacingPlan 替代 advance mutation；classifier 接 profile；可重复标点进 clreq 表；role override 进 dump | 现有所有 fixture 不变 | 所有现有测试绿；`LayoutResult` 暴露结构化 `clusterDecisions / spacingPlan` 字段 | done |
| 4 | M3 | BreakCandidate / RepairOption；`PushIn` `CarryPrevious`；greedy + lookahead；`Hang` 仅保留 profile opt-in 路径 | `kinsoku-carry-previous` `kinsoku-push-in` `lookahead-future-push-in` `lookahead-avoids-repair` | `./gradlew :tiqian-layout:jvmTest` + `./gradlew :tiqian-playground:runPlayground`；dump `line:*` 行，多行非单 placeholder | done (`PushIn` / `CarryPrevious` / `LeaveRagged` 有结构化 chosen repair + candidates；CarryPrevious 会验证 carried line 不超宽；lookahead window 1；window 2~3 改列后续 opt-in optimization；Hang 推到后续 opt-in slice) |
| 5 | M4 | 两端对齐：基于 glue 的 AdjustmentOpportunity；优先级 `PunctuationGlue → CjkLatinSpace → WordSpace → CjkInterChar` | 中文正文段落 + 中西混排 fixture | dump 每行 `adjustedWidth` ≈ `maxWidth`；新 golden | done (`Justifier` + `JustificationDecisionInfo`；`textAlign=Justify` 触发；最后一行 skip；priority chain 完整；WordSpace 待 shaping 分词后启用) |
| 6 | M5 | API 固化；`tiqian-shaping-android` / `tiqian-shaping-skia` 真 adapter；golden test + benchmark | 平台 fixture + screenshot golden | 各平台模块 build + screenshot 测试 | wip (6a: shaping contract + `ExplainableStubTextShaper` + debug decisions；ADR 0008；真实 Android / Skia adapter 未接) |

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
