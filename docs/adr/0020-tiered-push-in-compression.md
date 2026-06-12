# ADR 0020: 挤压分层与调整风格开关

- Status: Accepted
- Date: 2026-06-12

## Context

CLREQ 给出了明确的挤压处理优先顺序：①行末标点固定半宽 →②西文词距挤至
1/4 em →③间隔号两侧等量挤压 →④行内句问叹挤至半宽（部分风格禁止）。
另有「在一些排版风格中，中西间距不允许被挤压」的风格分歧，以及行末标点
「严格风格」（强制半宽）与「宽松风格」（允许全宽）之分。

此前 PushIn 把全行标点 trailing glue 按比例摊（gap audit 缺口 4）：没有
分层、没有间隔号双侧等量、词距与中西间距完全不参与，风格分歧也无开关。

## Decision

### 分层挤压模型（`ShrinkOpportunity`）

PushIn 的输入从 `pushInCapacities: Map<Int, Float>` 换成
`List<ShrinkOpportunity>`，每条带 `tier`、`capacity`、`channel`：

| tier | 资源 | channel | 依据 |
|---|---|---|---|
| 1 | 行末标点削半（offender 晋升，见下） | TrailingGlue | CLREQ ① |
| 2 | 西文词距 → 最小 1/4 em | RawAdvance | CLREQ ② |
| 3 | 间隔号 / 中点两侧等量 → 0 | LeadingAndTrailingGlue | CLREQ ③ |
| 4 | 行内句问叹 → 半宽 | TrailingGlue | CLREQ ④ |
| 5 | 中西间距（space 派生 gap cluster） | RawAdvance | CLREQ 风格项 |
| 6 | 其余标点 trailing glue（顿逗引括等） | TrailingGlue | 项目扩展 |

分配规则：**严格按 tier 耗尽**（低 tier 用完才动高 tier），同 tier 内按
capacity 比例分摊。`LeadingAndTrailingGlue` 渠道两侧各扣一半（等量）；
`RawAdvance` 渠道直接削 cluster advance（`withRawEdgeTrims`）。

tier 6 是有意的项目扩展：CLREQ 的挤压清单不含顿号逗号等的可调空间，但
加法 glue 模型（ADR 0004）天然提供这部分容量，作为最后档参与可避免
不必要的 CarryPrevious。排在所有 CLREQ 档之后，不改变规范行为的相对序。

### Offender 晋升（行末削半的实现形态）

「行末标点固定半宽」不是一条独立扫描——当 PushIn 把 offender 挤进上一行
时，offender 即将成为行末，其 trailing glue 晋升为 tier 1 优先消耗。
非 PushIn 的自然行末半宽仍由 `consumeLineEdgeGlue` 在行级统一执行。

### `lineEndOnly` 语义

`allowInlineStopCompression = false` 时，句问叹的机会标记
`lineEndOnly = true`：仅当该 cluster 就是 offender（将成为行末）才可用，
行内保持全宽。这样「行末削半永远允许」与「行内压缩可禁」互不干扰。

### 调整风格开关（`AdjustmentStylePolicy`）

挂在 `ClreqProfile.adjustment` 上，默认值取 CLREQ 推荐 / 大陆主流实践：

- `lineEndPunctuation`: `ForceHalfWidth`（默认，严格风格）/
  `AllowFullWidth`（宽松风格，opt-in）。控制 `consumeLineEdgeGlue` 是否
  对行末标点做削半。
- `allowInlineStopCompression = true`：行内句问叹是否参与 tier 4。
- `allowSinoWesternGapAdjustment = true`：中西间距是否参与 tier 5 挤压
  与 justify 拉伸（同一开关同时门控两侧，CLREQ 风格项原文即如此）。

### 暂不做

- **Insert 模式 gap 的挤压**：无空格边界的 1/4 em gap 计入词 cluster
  advance、由渲染层按 decision 偏移（ADR 0019），削它需要渲染层联动
  可变 gap，收益小（gap 仅 1/4 em）。tier 5 当前只覆盖 space 派生的
  gap cluster。
- 词距挤压档与拉伸档的「同时、同等量」已分别满足（同 tier 比例分摊 /
  justify WordSpace 档均摊）。

### Amendment (2026-06-13): 对齐 CLREQ 七档原序，「项目扩展档」撤销

第六节原文入库（[research/clreq-section-6-line-and-paragraph.md](../research/clreq-section-6-line-and-paragraph.md)
「挤压处理的优先顺序」）后逐字对照，发现本 ADR 最初的六档表偏离原文：
CLREQ 实际列了**七档**，其中两档被我们误判为「CLREQ 未列的项目扩展」，
且句问叹与中西间距的相对位置记反了。修正后的档序：

| tier | 资源 | channel | CLREQ |
|---|---|---|---|
| 1 | 行末标点削半（offender 晋升） | TrailingGlue | ① |
| 2 | 西文词距 → 1/4em | RawAdvance | ② |
| 3 | 间隔号双侧等量 → 0 | LeadingAndTrailingGlue | ③ |
| 4 | 夹注符号外侧：开括号/开引号**前侧**、闭括号/闭引号后侧 | LeadingGlue / TrailingGlue | ④ |
| 5 | 行内逗、顿、分号（冒号等未尽列者同档兜底） | TrailingGlue | ⑤ |
| 6 | 中西间距 → **最小 1/8em**（原实现压到 0；风格开关可禁） | RawAdvance | ⑥ |
| 7 | 行内句问叹（风格开关可禁，`lineEndOnly` 语义不变） | TrailingGlue | ⑦ |

- 新增 `ShrinkChannel.LeadingGlue`：开夹注前侧的消费；渲染层的
  leading-consumed 左移（ADR 0017 amendment）天然覆盖。
- 「tier 6 项目扩展」的说法撤销——CLREQ 几乎列全了所有标点 glue，
  真正的项目兜底只剩未尽列的点号（如冒号），归入第 5 档。
- 拉伸侧同步补 CLREQ 限制：`AvoidStretchAroundConnectors`——均匀拉大
  字距不触碰连接号/分隔号（Connector/Solidus）前后的边界；「禁止拉伸
  符号分离禁则字间」中已建模的部分（两字宽标点为单 cluster）天然满足，
  数字+单位等未建模项随该特性落地时一并处理。
- 行为测试：夹注外侧先于行内逗号被压、gap 1/8em floor 触发 Carry、
  连接号边界不拉伸。

## Consequences

- PushIn 取压缩的顺序对齐 CLREQ：词距先于行内标点 glue 被消耗（见
  `latin-word-wrap` golden：行末 `。` 削半 → 两处词距各取 4px →
  行内 `，` 保持全宽）。
- 每条 `PushInAllocation` 带 channel，dump 可见各档实际扣量。
- 三个风格开关均有行为测试（loose 行末 / 行内压缩禁用 / 中西间距禁用）。
- ledger 旧接口 `pushInCapacities()` 已随本次改动移除。
