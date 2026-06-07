# ADR 0012: CarryPrevious 必须验证 carried line 不超宽

- Status: Accepted
- Date: 2026-06-07

## Context

`CarryPrevious` 的语义是把上一行最后一个 cluster 带到当前行，与禁止行首的标点一起放在当前行开头。它是 PushIn 容量不足时的默认避头尾退路。

真实段落 fixture 暴露了一个漏洞：`applyKinsokuRepairs` 只检查上一行是否还能让出一个 cluster，没有检查 carried 后的当前行是否超过 `maxWidth`。结果 `real-paragraph-1` greedy 输出曾出现：

```text
line[6] adjusted=336.0 maxWidth=320 repair=CarryPrevious
```

这不是可接受的 repair。它只是把「行首标点」问题换成了更隐蔽的「当前行超版心」问题，而且 debug 还把它标成 accepted `CarryPrevious`。

## Decision

`CarryPrevious` 进入候选后必须重建 carried current line，并验证：

```text
carriedCurrent.adjustedWidth <= maxWidth
```

若不满足：

1. `CarryPrevious` candidate 标记为 `accepted = false`。
2. `rejectionReason = "carry-overflows"`。
3. 记录 `carriedClusterIndex`，方便 debug 知道哪个 cluster 会造成 overflow。
4. 当前冲突退回 `LeaveRagged`，reason 为 `ForbiddenAtLineStart:<char>:carry-overflows`。

保留原 current line，不移动上一行 cluster。这样输出中仍能看到行首禁则问题，但不会伪装成成功修复，也不会制造 over-budget line。

## Consequences

- `CarryPrevious` 不再保证“只要上一行可让一个 cluster 就接受”；它必须同时满足 current line 不超宽。
- Playground / debug 能看到 rejected candidate：

```text
candidate CarryPrevious rejected:carry-overflows carried 82
```

- `real-paragraph-1` greedy 的原 over-budget line 从 `CarryPrevious adjusted=336` 变成 `LeaveRagged adjusted=320`。
- 这不代表 `LeaveRagged` 是理想排版，只是当前默认修复链里比 over-budget CarryPrevious 更诚实。后续可以继续做更强的 repair resolver，例如重新分配同行多处 glue、扩大 lookahead window、或在 profile opt-in 下考虑 Hang。

## Alternatives considered

- **继续接受 CarryPrevious，但给 line 加 over-budget warning。** 否决。warning 不能改变 drawable geometry，仍会让 renderer 输出超宽行。
- **CarryPrevious 超宽后再尝试 PushIn 当前行其它 glue。** 暂缓。这是更好的长期方向，但当前 PushIn capacity 仍只建模 offender trailing glue；多 glue 分配应单独扩展 repair resolver。
- **强行把 carried line 截断再断一行。** 否决。那会在 repair pass 中改变 line count 和后续所有 line ranges，当前 greedy/lookahead 架构还没有稳定的 recursive repair 模型。
