# ADR 0011: PunctuationGeometryLedger 作为标点几何事实来源

- Status: Accepted
- Date: 2026-06-07

## Context

ADR 0004 定义了加法标点模型：

```text
punctuation = body + leadingGlue + trailingGlue
```

ADR 0010 又补上了行首 / 行尾 edge glue trim，并引入 `GlueBudget` 避免 spacing、PushIn、line-edge trim 对同一份 glue 双账。

但实现上仍有一层减法壳：`PunctuationSpacingCompressor`、PushIn、`LineEdgeGlueTrim`、justification 分别通过 `cluster.copy(advance = advance +/- x)` 改 cluster 宽度。这样虽然 debug 能解释每次变化，真正的 drawable geometry 仍然是多次 mutation 后的 `Cluster.advance`，而不是 `body + remaining glue` 的统一解析结果。

这会带来三个问题：

1. 新的消费者很容易绕过 glue 账本，继续写 `advance -= 4f`。
2. `Cluster.advance` 同时承担 source shaping advance、layout adjustment 和 render advance，语义混杂。
3. playground 只能看见“减了多少”，看不见某个标点最终还有多少 leading / trailing glue。

## Decision

在 `ParagraphLayoutEngine` 内引入 `PunctuationGeometryLedger`，作为当前阶段的标点几何事实来源。

### 1. Ledger 输入

`PunctuationGeometryLedger.from(...)` 接收：

- `naturalClusters`：shaping / autospace 后的基础 cluster。
- `punctuationAtoms`：`PunctuationAtomBuilder` 产出的 `bodyWidth / leadingGlue / trailingGlue`。
- `spacingPlan`：相邻标点挤压结果。

它为每个包含标点 atom 的 cluster 建立：

```text
PunctuationClusterGeometry
  baseAdvance
  bodyWidth
  leadingGlueNatural
  trailingGlueNatural

GlueBudget
  leadingNatural / leadingConsumed
  trailingNatural / trailingConsumed
```

当前 `bodyWidth` 仍是 policy-derived；真实 shaping 接入后再由 glyph ink bounds / OpenType feature 输出校正。

### 2. 所有调整写 ledger

以下步骤不再各自直接改 `Cluster.advance`：

```text
PunctuationSpacingCompressor -> leadingConsumed of target cluster
PushIn repair                -> trailingConsumed of target cluster
LineEdgeGlueTrim             -> remaining leading/trailing consumed at line edge
Justifier                    -> justificationDelta
```

最终 drawable clusters 只由：

```text
resolveAdvance =
  bodyWidth
  + (leadingGlueNatural - leadingGlueConsumed)
  + (trailingGlueNatural - trailingGlueConsumed)
  + justificationDelta
```

解析得到。

`baseAdvance` 只作为 shaping / autospace 后的输入对照进入 debug；标点 cluster 的 render advance 不再以 `baseAdvance - consumed` 为事实来源。这仍然保留 `Cluster.advance` 作为渲染层可直接消费的宽度，但它是 `PunctuationGeometryLedger.resolveClusters()` 的产物，不是每个阶段私自 mutation 的中间状态。

### 3. Debug 输出

新增 `LayoutDebugInfo.geometryDecisions`：

```text
range / sourceText / displayText
baseAdvance / bodyWidth
leadingGlueNatural / leadingGlueConsumed
trailingGlueNatural / trailingGlueConsumed
justificationDelta / resolvedAdvance
source / reason
```

Playground metadata 显示 `geom` 项，让开发者能看到：

```text
geom 3-4 '。' body=8.0 lead=4.0/4.0 trail=4.0/4.0 justify=+0.0 resolved=8.0
```

## Consequences

- ADR 0004 的加法模型不再只是 atom 描述；至少在 engine 内，标点 drawable advance 来自同一个 ledger。
- ADR 0010 的 line-edge trim 和 ADR 0006 的 PushIn capacity 共用同一份 `GlueBudget`。
- 后续实现标点 + 文字挤压、Hang、真实 glyph ink bounds 时，应扩展 ledger，而不是新增直接 `advance -= ...`。
- 当前 line breaker 接口仍吃 `List<Cluster>`，所以 engine 会在每个阶段调用 `resolveClusters()` 生成 line breaker / justifier 所需视图。后续如果需要更强约束，可以把 line breaker 参数升级为 `ResolvedInlineGeometry`。

## Alternatives considered

- **只保留 ADR 0010 的 GlueBudget，不加 geometry decision。** 否决。没有 resolved geometry debug，仍然很难判断加法模型是否真的参与渲染。
- **马上把 `Cluster.advance` 拆成 sourceAdvance / layoutAdvance / renderAdvance。** 暂缓。这会波及 core、renderer contract 和所有测试；当前先把 engine 内部事实来源收拢，等平台 renderer 接入时再做 public API 拆分。
- **把所有非标点 spacing 也纳入同一个 ledger。** 暂缓。Autospace / CJK-Latin / CJK inter-char glue 也应该 ledger 化，但本 ADR 先收口标点模型，避免范围失控。
