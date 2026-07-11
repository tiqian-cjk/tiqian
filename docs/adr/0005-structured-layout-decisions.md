# ADR 0005: 结构化 LayoutDecision 与 SpacingPlan

- Status: Accepted
- Date: 2026-06-06

## Context

Slice 0–3 把 pipeline 形状打通了，但 `ExplainableStubParagraphLayoutEngine` 里积累了几处与 ADR 0001 / 0004 直接冲突的实现细节，在 Slice 4 (kinsoku repair) 接入之前必须清理，否则后续每次改动都要绕过它们：

1. `LayoutDebugInfo` 里所有决策都是手写字符串（`"font:5-6:中:CjkText:src.cjk.body:..."`）。测试只能 `assertContains` 串；外部消费者（playground HTML、benchmark、未来 IDE 工具）拿不到结构化字段。
2. `PunctuationSpacingCompressor` 直接改 `cluster.advance`。ADR 0004 的加法 glue 模型要求 glue 是资源、由 justifier 消费；提前 mutation 会让 Slice 5 (justification) 分不清「自然 advance」与「已压缩 advance」。
3. `isRepeatableCjkPunctuation` 用 `if (cp == 0x2014 || cp == 0x2026 || cp == 0x22EF)`
   写死在引擎里。这违反 [AGENTS.md](../../AGENTS.md) 的具名策略与模块边界约束，且属于
   CLREQ profile 表的内容。
4. `FontRoleClassifier` 不接 profile。Mainland / Traditional region 进来时整套 signature 要改。
5. `QuotePairAnalyzer` 改写 cluster role 后没有进 dump，造成「dump 里看到的 role 与真实推理路径不一致」。

这些单看都小，叠加起来正好打掉项目的核心卖点：可解释、可观察、profile-driven。

## Decision

在 Slice 4 之前插入 Slice 3.5「explainability hardening」，做一次纯结构性重构，不加新功能：

### 1. 结构化 LayoutDecision 类型

在 `tiqian-core` 引入：

```text
FontDecision         (range, sourceText, displayText, role, fontKey, reason, substitutionReason)
MetricDecision       (range, sourceText, request, rawMetrics, layoutMetrics, reason)
PunctuationDecision  (range, char, punctuationClass, advance, body, leadingGlue, trailingGlue, anchor)
SpacingDecision      (range, leftChar, rightChar, naturalInnerGlue, adjustedInnerGlue, reduction, targetRange, reason)
ClusterRoleOverride  (range, originalRole, overriddenRole, source, reason)   // QuotePair 等
```

`LayoutDebugInfo` 的字段从 `List<String>` 改为这些类型的列表；现有的字符串 dump 通过 `toDebugString()` 扩展提供，golden 测试可继续工作。

### 2. SpacingPlan 作为结构化解释，与 cluster 的最终 advance 共存

```text
SpacingPlan
  adjustments: List<GlueAdjustment>     // 每条 = atomRange + leading/trailing delta + reason
  totalReduction: Float
```

实际落地的 pipeline：

```text
naturalClusters (advance = 自然值)
  -> punctuationAtoms
  -> spacingPlan = compressor.compress(atoms)
  -> clusters    = naturalClusters.applyPlan(spacingPlan)   // advance 压缩到最终值
```

`Cluster.advance` 携带压缩后的最终 advance，渲染器可以直接 draw；`line.naturalWidth = sum(naturalClusters.advance)` 记录压缩前总宽，`line.adjustedWidth` 与 `line.visualWidth` 记录压缩后总宽，差额由 `spacingPlan.totalReduction` 解释。`result.debug.spacingDecisions` 用结构化条目暴露每一次 reduction 的 left/right char、targetRange、reason，供 justifier (Slice 5) 在需要时重新分配 glue。

关键差别：`SpacingPlan` 不是「替代」cluster mutation 的唯一来源，而是为这次 mutation **保留结构化解释**——cluster 携带渲染所需的几何，plan 携带「这几何是怎么从自然值压缩来的」。Slice 5 的 justifier 读 plan 即可恢复并重新分配。

### 3. FontRoleClassifier 接 profile

```kotlin
interface FontRoleClassifier {
    fun classify(text: String, range: TextRange, profile: ClreqProfile): FontRole
}
```

默认实现忽略 profile，行为不变。但 signature 落地，避免 Mainland/Traditional region 进来时所有 call site 要改。

### 4. 可重复标点进 clreq 表

新增 `ClreqProfile.repeatablePunctuation: Set<Int>`（命名 heuristic：`CoalesceRepeatablePunctuation`）。引擎从 profile 读取，不再有 `if (cp == 0x2014 || ...)`。

### 5. QuotePair role override 进 dump

`QuotePairAnalyzer.classifyPairs` 产出的每条 override 进入 `LayoutDebugInfo.roleOverrides`，字段含 pair index、原 role、新 role、原因（`QuotePairAwareLatinContext` 等具名 heuristic）。

## Consequences

- LayoutResult 真正可被结构化消费：playground HTML、未来 IDE 调试器、benchmark、screenshot 比对都能拿到字段而不是 grep 字符串。
- Slice 5 (justification) 可以基于 `clusters + spacingPlan` 恢复自然 advance 并重新分配 glue；无需扫源码反推压缩规则。
- profile-driven 规则集中到 clreq 模块；引擎里再出现 `if (cp == ...)` 应在 review 时打回。
- 测试可以从「字符串 contains」迁到「字段断言」，重构成本下降。
- 不影响任何现有 fixture 的行为；这是纯结构重构。

## Alternatives considered

- **不重构，先做 Slice 4。** 否决：kinsoku repair 会读 `atom.anchor` 和 `cluster.advance`，一旦它依赖了 mutated advance，加法 glue 模型再也回不去；string dump 会被更多新决策塞满，越晚改成本越高。
- **只做结构化决策，不动 SpacingPlan。** 否决：mutation 问题独立于 dump 问题，但同样是 Slice 5 的拦路虎，两件一起做比拆两次 PR 简单。
- **同时把 `clusterRanges` 抽成 `ClusterScanner` 抽出 core。** 暂缓：surrogate pair walking 重复确实是技术债，但和这次重构关注点不同，留作单独 ADR。

## Follow-up

- `ClusterScanner` 抽 core（ADR 0006 候选）。
- `inkBounds` 接真实 shaping（Slice 6 范围）。
- 测试从字符串 contains 迁到字段断言（与本 ADR 同 PR 完成）。
