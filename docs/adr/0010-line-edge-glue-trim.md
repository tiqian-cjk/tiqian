# ADR 0010: LineEdgeGlueTrim 收口 ADR 0004 的加法模型

- Status: Accepted
- Date: 2026-06-06

## Context

[ADR 0004](0004-punctuation-additive-glue-model.md) 写的是「punctuation = body + leadingGlue + trailingGlue」，承诺把标点的几何拆成 ink 与可调空隙，让行内调整、相邻挤压、断行修复、两端对齐这些下游决策都从同一份 glue 资源消费。

实际落地走样了：

| 消费者 | 是否真的把 atom 当几何来源 | 备注 |
|---|---|---|
| `Cluster.advance` 本身 | 否 | `ExplainableStubTextShaper` 直接给 `fontSize × codepointCount × advanceEm`，永远 1em；atom 是平行存在的描述卡 |
| `PunctuationSpacingCompressor` | 是（atom-atom 内 glue） | 但只看 inner，不看 edge |
| `pushInCapacities` / PushIn | 是（atom trailing glue） | |
| `Justifier.PunctuationTrailing` | 是（atom trailing glue） | |
| **行尾半宽 / 行首半宽** | **否** | atom 说尾部 4px 可消耗，但没人在 line 边缘真的去消耗 |

[real-text-fixture-1 观察 #3](../research/real-text-fixture-1.md) 在真实段落上让这个 gap 显形：12 行里每个以 `。` `，` `」` `）` 结尾的行都顶满 1em，行尾视觉虚胖。在短 fixture 上看不出来，所以 Slice 0–6a 一路绿灯地把 atom 系统建好，但「行尾半宽」一直挂在 [ADR 0006](0006-hanging-punctuation-opt-in.md) 的 follow-up 上当成「Slice 4b 收尾时再做」——其实它根本不是新功能，是 ADR 0004 本来就该有的语义。

孔雀计划《中文排版的最大迷思：标点悬挂》明说：**判断悬挂之前必须先做行尾半宽**，否则悬挂只是把不齐换成更不齐。当前模型给 hang 留了 profile opt-in 通道（ADR 0006），却没把作为前提的「严格行尾半角」实现。

## Decision

把 ADR 0004 加法模型的「edge glue 在 line 边缘被消耗」这一基础语义补上，作为 `ParagraphLayoutEngine` 在 lineBreak 之后、justifier 之前的独立步骤：

### 1. GlueBudget：跨步骤共享的 edge glue 账本

```kotlin
data class GlueBudget(
    val leadingNatural: Float,
    val leadingConsumed: Float,
    val trailingNatural: Float,
    val trailingConsumed: Float,
) {
    val leadingRemaining: Float = (leadingNatural - leadingConsumed).coerceAtLeast(0f)
    val trailingRemaining: Float = (trailingNatural - trailingConsumed).coerceAtLeast(0f)
}
```

每个有 atom 的 cluster 维护一份 budget，跨三个消费者：

| 步骤 | 影响字段 | 约定 |
|---|---|---|
| `PunctuationSpacingCompressor` | `leadingConsumed` of right cluster in pair | spacing 缩的是右 cluster 的 leading（reductionTargetRange 指右） |
| `PushIn` repair | `trailingConsumed` of offender cluster | PushIn 消费 offender 的 trailing |
| **`LineEdgeGlueTrim`（本 ADR 新增）** | 行末 cluster 的 `trailingConsumed` 加到饱和；行首 cluster 的 `leadingConsumed` 加到饱和 | 命名 heuristic `LineEndHalfWidthPunctuation` / `LineStartHalfWidthPunctuation` |

约束：`s_leading + ... ≤ leadingNatural`，`s_trailing + ... ≤ trailingNatural`。Edge trim 只能消费 `remaining`，自动避免双账。

### 2. LineEdgeGlueTrim 的应用顺序

```text
naturalClusters
  → applyAutoSpacePolicy            (ADR 0009)
  → applyPunctuationSpacingCompression
  → lineBreaker.breakLines          (可能产生 PushIn)
  → applyPushInShrink               (engine 层)
  → applyLineEdgeGlueTrim           (← 本 ADR 的新步骤)
  → justifier.justify
  → applyJustificationDeltas
  → finalClusters
```

每条 trim 产出结构化 `LineEdgeTrimDecisionInfo`：

```kotlin
data class LineEdgeTrimDecisionInfo(
    val lineRange: TextRange,
    val clusterRange: TextRange,
    val side: String,        // "leading" / "trailing"
    val trimAmount: Float,
    val consumedBefore: Float,
    val naturalGlue: Float,
    val reason: String,      // "LineEndHalfWidthPunctuation" / "LineStartHalfWidthPunctuation"
)
```

进 `LayoutDebugInfo.lineEdgeTrimDecisions`。

### 3. Justifier 的协调

`PunctuationTrailing` priority 不能再从已 trim 的 edge 借空间——edge glue 已经吃光。Justifier 通过同一份 GlueBudget 知道 remaining，自动跳过 zero-remaining 的 atom。无需 justifier 自己改逻辑，只要传 trimmed clusters 进去即可。

### 4. LineBox 几何更新

`LineBox.adjustedWidth` 现在由 trimmed clusters 求和而来（post-trim, pre-justify），不再直接信 `lineCandidate.adjustedWidth`——后者代表 lineBreaker 的视角，没经过 trim。

## Consequences

- **真实文本立刻收紧**：以标点结尾的行省 4px（PauseOrStop / Closing 类）。real-paragraph-1 12 行里至少 5–6 行会显示出差别。
- **测试 baseline 变化**：以下 engine-level 测试断言需要更新，因为它们的预期值是 ADR 0004 没收口前的「1em 顶到底」语义：
  - `appliesAdjacentPunctuationCompressionToDrawableGeometry`：`你好，。` 末尾 `。` 再 trim 4，line.adjustedWidth 60 → 56，stop.advance 12 → 8。
  - `kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation`：line 1 `文。` 末尾 trim 4，adjustedWidth 32 → 28。
  - 其它含标点结尾的可能也会变；统一改。
- **PushIn 测试不变**：PushIn 已经吃满 trailing，trim 拿 0，行为一致。
- **Dash / Ellipsis 不变**：`⸺` `⋯⋯` 的 body 已是 advance（sideGlue = 0），edge glue 自然为 0，trim 拿 0。
- **lineBreaker 视角的 `LineCandidate.adjustedWidth` 不变**：breaker 单元测试断言的是 pre-trim 视角，不动。变的只有 engine emit 的 LineBox.adjustedWidth。
- **观察 #3 关闭**，[real-text-fixture-1](../research/real-text-fixture-1.md) 更新为前后对比。
- **悬挂（Hang）的前置条件就位**。今后 [ADR 0006](0006-hanging-punctuation-opt-in.md) 的 follow-up 真正实现 Hang 时，可以直接基于「严格行尾半角」做差分判断，而不是从零起步。

## Alternatives considered

- **跟 PushIn 合并成同一个「TrailingGlueTrim」概念，按 reason 区分**。否决：PushIn 是 kinsoku 修复决策，要进 RepairOption / repair penalty 体系；LineEdgeTrim 不是修复，是渲染阶段的固定语义。合并会让 RepairOption 列表里挤进非修复条目，污染 line decision 的语义。**两者用同一份 GlueBudget 共享 trailing 库存就够了**，不需要类型上合并。
- **在 `PunctuationAtomBuilder` 出 atom 时就根据 line 位置给不同 advance**。否决：atom 是 cluster 构造前的描述，那时不知道 line 在哪里断。要让 atom 知道 line 位置就得反向依赖 lineBreaker，破坏 pipeline 单向流。
- **作为 Justifier 的第 0 步（强制收缩）**。否决：Justifier 处理 deficit 分配（拉伸），跟 LineEdgeTrim 的「固定收缩」语义不同，混进去会让 justification 的 priority chain 变得难解释。
- **只做 LineEnd 不做 LineStart**。暂时接受：现实正文中以 opening punct（`（` `「` 等）开头的行远少于以 closing/pause/stop 结尾的行；两个同时实现成本不高，一并做了。

## Follow-up

- 后续如果引入 `text-spacing-trim`（CSS Text 4 跟 `text-autospace` 配对的属性，处理 fullwidth 标点在版心边缘的裁剪），可以并入同一份 GlueBudget。
- Hang（[ADR 0006](0006-hanging-punctuation-opt-in.md)）的实现可以基于本 ADR 之后的「严格行尾半角」做增量：当 profile 启用 hang 时，行尾 trim 的 cluster 改为「不 trim、用 visualOverhang 字段悬挂到 maxWidth 之外」。
- `effectiveTrailingGlueCapacity = trailingNatural - trailingConsumed` 这套账本同时回答了 [ADR 0006 follow-up](0006-hanging-punctuation-opt-in.md) 里 PushIn capacity 跟 SpacingCompression 双账的那个 known 简化——同一份 budget 自动协调。
