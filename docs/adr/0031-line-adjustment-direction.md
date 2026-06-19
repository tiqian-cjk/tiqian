# ADR 0031: 行调整方向——偏差最小化下的「推入/推出」取舍

- Status: Accepted
- Date: 2026-06-19
- Supersedes the rejection scope of [ADR 0022](0022-shrink-to-fit-line-breaking.md)

## Context

当前 `Justifier` 只有**拉伸**方向：每个非末行算 `deficit = 行长 − adjustedWidth`，按
§6.2.2.4 档序加空白。压缩只出现在避头尾 PushIn 修复里。普通断行按自然宽判定——
cluster 放不下就整体下行（推出），本行随后被拉伸。

实际使用观察（用户）：**几乎总在拉大字距，即便挤一挤还放得下。** 因为越界字一律推出、
从不推入，本行只能靠拉伸补足。这违背 CLREQ §6.2.2「先挤进、后推出」与「先挤压、后拉伸」。

[ADR 0022] 曾把 cluster 准入一般化为「自然宽 − 行内可压容量 ≤ 行宽」（floor 填行），
**被否决**：「普通两端对齐不应以挤压为常规填充手段」——它让**每一行**都尽量多塞、
行末削半与行内压缩成为**常态**，版面系统性偏紧。本 ADR 必须避开同一个坑。

## Decision

把越界那一字落在本行(推入/压缩)还是下一行(推出/拉伸)做成**方向选择**，判据是
**离自然密排(基线)的偏差最小**，且**压缩比拉伸优先**（不对称权重）：

```
badness(行) = 拉伸量 × Ws + 压缩量 × Wc ，  Ws/Wc = compressBias（默认 2）
```

越界字 `i`：收进来压 `O = N(≤i) − 行长`、代价 `Wc·O`；断开拉 `U = 行长 − N(≤i-1)`、
代价 `Ws·U`。取小者，收进来还须**可行**（`O ≤ 本行可压容量`）。

**与被否决的 0022 的本质区别**（这才是它可被接受的原因）：

- 0022 是「**能压尽压**」——把压缩当一等填充手段，每行都最大化塞字 → 全行偏紧。
- 本 ADR 压缩只是**越界处的方向二选一**，且按偏差加权：
  - **自然宽本就贴行长的行 → 偏差≈0，不动**（绝不会被无故压）；
  - 只有**越界那一字**的归属按「谁偏差小（压缩打折后）」翻一下；
  - `compressBias` 有限（默认 2，非 ∞）→ 压到一定程度就让位给推出，不会塌成紧排。
- 即：压缩出现在「**确实是更小偏差**」的地方，而非「**每一行都尽量塞**」。0022 的否决理由
  （压缩不该是常规填充）在此成立——本模型下绝大多数行仍是自然或拉伸态。

### 四种策略（`LineAdjustmentStrategy`，profile 可选）

方向取舍统一由 `(是否生成推入候选, 有效 bias)` 表达；**档内分配**始终走
§6.2.2.3/§6.2.2.4 tier 顺序（与方向无关）：

- **Auto**（默认）：偏差最小化 + 压缩优先，`bias = lineAdjustmentCompressBias`（默认 2）。
- **PushInFirst**（先推入）：`bias → 大`——压得动就压（CLREQ「先挤进」字面顺序），压不动才推出。
- **PushOutFirst**（先推出）：`bias < 1`——能断就断、拉伸，只有推出明显更差时才回头推入。
- **PushOutOnly**（仅推出）：不生成推入候选——一律断、拉（**= 0022 否决后的现状**，旧 golden 行为）。

## Mechanism

1. `Justifier.compress(surplus, shrinkOpportunities)` —— 压缩方向分配器（§6.2.2.3 档序），
   与 `justify` 对称，吐 `PushInAllocation`，复用现有 channel 应用路径。**已落地**（步骤 ①）。
2. breaker：在越界处增设**推入候选**（`greedyEnd+1…` 至可压容量耗尽），`badness` 改为
   **双向不对称**（拉 `Ws`、压 `Wc=Ws/bias`，压不下→不可行罚），随 lookahead 评分一起选。
3. 引擎 per-line：过满行→`compress` 应用、不足行→`justify`。

## Consequences

- golden **普遍变化**（断行重排）；`TIQIAN_UPDATE_GOLDEN=1` 重生成 + 逐行 review，
  重点看「是否只在越界处压、自然行是否保持不动」（防止重蹈 0022）。
- `PushOutOnly` 完整保留旧行为，可作回退与对照。
- 复用 `tryPushIn`/`distributeShrink`/PushIn channel 应用，不新造压缩几何路径。

## Alternatives considered

- **floor 填行（能压尽压）**：即 [ADR 0022]，已否决——压缩成常态、版面偏紧。
- **纯对称偏差（bias=1）**：可作 `compressBias=1`，但用户要「先挤压」优先，默认 2。
