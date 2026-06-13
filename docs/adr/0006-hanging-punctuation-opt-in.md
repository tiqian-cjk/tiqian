# ADR 0006: 标点悬挂为可选项，PushIn / CarryPrevious 才是默认避头尾

- Status: Accepted
- Date: 2026-06-06

## Context

Slice 4 引入了 kinsoku 修复（CarryPrevious + LeaveRagged 已实现，PushIn / Hang 推后到 Slice 4b 收尾）。在排版规范层面，必须先回答一个前置问题：当一行结尾遇到避头尾冲突时，「悬挂（Hang）」是不是默认应当考虑的修复方式？

参考资料：

- [The Type — 中文排版的最大迷思：标点悬挂](https://www.thetype.com/2017/11/13290/)
- JIS 4051:2004《日本语文书的排版方法》及其解说
- W3C JLREQ 2.5.1「超出版心的例子」c 部分

### 文章和规范的核心论点

1. **避头尾的两个基本操作是 PushIn 与 CarryPrevious**。
   - 推入（PushIn）：通过挤压行内空间把避头标点拉回当前行行尾。
   - 推出（CarryPrevious）：把行尾最后一个字与避头标点一起推到下一行。
   - 悬挂（Hang）是这两者之上的可选补充，不是第三个对等选项。
2. **JIS 4051:2004 经过讨论后明确不把悬挂写入正文**。日方专家组观点：
   - 「悬挂可能是活字排版里为了减轻调整工作而采用的一种方法」（即「偷懒论」）。
   - 西文排版原则上不悬挂，日西混排时悬挂会失衡。
3. **W3C JLREQ 保留悬挂为「减轻字距调整」的一种手段**，并且 **限于句号、逗号类**。
4. **悬挂必须建立在「行尾标点策略（半角 vs 全角）」的前提上**。如果采用「严格风格＋行尾半角」，行尾本来就齐，悬挂反而会引入新的视觉抖动。
5. **悬挂受版面条件制约**：栏间距过窄、有栏线、段落装饰、分栏紧凑的报刊版面都不适合悬挂。
6. **悬挂应在通篇内保持统一**，不应作为「兜底」启发式临时开关。

文章额外印证了 Slice 5 已采用的 justification 优先链：「为了保持中文网格的稿纸模式，更多情况应该是先『动标点』」——即 `PunctuationGlue` 排在 priority 0 是正确的。

对当前阶段最重要的结论是：Slice 4b 应实现 **PushIn via punctuation glue**，而不是把 Hang 一并做进默认 repair。文章反复指出，强制悬挂可能在已经行尾半宽或已经可挤压标点的情况下制造新的行尾摆动，并可能让整行字距被重新均摊，破坏密排和字格。

## Decision

提椠把标点悬挂定为 **profile 显式可选项**，默认关闭：

```kotlin
enum class HangingPunctuationPolicy {
    Disabled,                  // 默认：严格行尾半角语义，不做悬挂
    EnabledForPauseStop,       // 仅 。 ，    （JIS 4051 / InDesign 默认）
    EnabledForExtendedCjk,     // 追加 ！？： 与弯引号（中国大陆习惯）
}

data class ClreqProfile(
    ...
    val hangingPunctuation: HangingPunctuationPolicy = HangingPunctuationPolicy.Disabled,
)
```

具体含义：

1. **默认 pipeline 永远不主动选择 Hang**。`KinsokuRule` / `LineBreaker` / `Justifier` 都不允许把 Hang 作为兜底 repair。
2. **Hang 仅当 profile 显式开启** 才进入候选集，且必须限制在 `policy.allowList` 内。
3. **PushIn 与 CarryPrevious 是默认 kinsoku 两件套**。后续 Slice 4b 收尾时，PushIn 用 Slice 5 的 `SpacingPlan + Justifier` 反向账本：当 deficit 容量充足时直接收紧 trailing glue 让避头标点回到行尾；不够时退回 CarryPrevious。
4. **Hang 不与 Justification 自动叠加**：当 `hangingPunctuation != Disabled` 时，justifier 必须知道 hang 已经吸收了行尾几何，避免重复填补 deficit。
5. **`ClreqStrictness.Strict` 隐含「行尾半角」**：严格模式下，行尾标点本身已经齐整，悬挂收益接近零；profile 在严格模式下默认 `Disabled` 是自然结果，不再单独提示。

## Consequences

- 默认 fixture / playground 输出不会因为 hang 而出现「行尾标点突出版心」的现象，这是有意为之，不是 bug。
- 任何想测试 hang 的 fixture / 测试 / 演示，必须显式构造 `ClreqProfile.copy(hangingPunctuation = ...)`。
- 当 Slice 4b 实现 PushIn 时，重点在「glue 反借」的算法实现，不需要再为 Hang 留兜底逻辑路径。
- roadmap 中凡是写 `PushIn / Hang` 的地方，应拆开：PushIn 是当前默认 kinsoku 收尾；Hang 是后续 profile opt-in 能力。
- 文档层面：roadmap、ADR 0004 「Slice 3 收尾」段、ParagraphLayoutEngine 注释里所有提到 `Hang` 的位置都需要标注「opt-in via profile」。

## Amendment (2026-06-13): Hang 落地实现（Slice 17）

ADR 立场（默认关、opt-in、限点号、不与 justify 双账）落为实现：

- 开关挂在 `AdjustmentStylePolicy.hangingPunctuation`：`Disabled`（默认）
  / `PauseStops`（顿、逗、句——CLREQ「适合行尾悬挂的标点符号有顿号、
  逗号及句号」）。**（后经 ADR 0025 合并入 `ClreqProfile.kinsokuMode`：
  `Fixed(level, hanging)` 或 `MeasureAdaptive`——本段描述 Slice 17 当时
  的字段。）** 本 ADR 早先草拟的 `HangingPunctuationPolicy`
  三档枚举收敛为两档；简体扩展范围（其余标点也可悬挂）留作后续档位。
- **`LineEndHangingPunctuation`** 进 kinsoku 修复链，顺序
  **PushIn → Hang → CarryPrevious → LeaveRagged**：先挤进（最不扰动，
  全留版心内），挤不下才悬挂（避免 CarryPrevious 拉走整字造成的大幅
  字距重摊——thetype 与窄行宽场景的核心收益），penalty 5（介于
  PushIn 2 与 Carry 10）。lookahead 评分用同一链，保持一致。
- **不与 justify 双账**（ADR 决策④）：悬挂 cluster 从行的 measure-fill
  宽度中**排除**——justify 把内容填满到 `maxWidth`，悬挂标点坐落版心
  外（`LineBox.adjustedWidth == maxWidth`，`visualWidth > maxWidth`）。
  渲染层零改动：cluster 仍在行 range 内、按 advance 照画，自然落到
  版心外。
- **行尾只悬挂一个**：链上从不在已悬挂的行再叠悬挂（`hangingClusterIndex
  != null` 守卫）。
- 行尾标点削半（`consumeLineEdgeGlue`）对悬挂标点照常生效——悬挂的是
  半宽点号，与「严格风格行尾半宽」前提（ADR 决策⑤）一致。

未做：简体扩展悬挂范围、连续标点（第二个及其后）的悬挂、grid 对齐下
与悬挂配合的禁则（CLREQ 纵横对齐节，竖排预研时一并）。

## Alternatives considered

- **默认开启句号、逗号悬挂（参照 InDesign 默认）**。否决：项目目标是把规则写进 profile + ADR，而不是「跟随主流工具默认」。允许用户选这个语义，但不替用户决定。
- **完全不实现 Hang**。否决：Hang 是合法的可选风格，仍有真实场景（窄栏、密排、稿纸式版心）需要。保留实现路径，关掉默认。
- **把 hang 决策塞进 `KinsokuRule`**。否决：`KinsokuRule` 当前是「这个字符是否禁止处于行首/行尾」的事实查询，hang 是版面 / 风格决策，混在一起会让 ADR 0001 的「模型必须真」失血。Hang 由 profile + 一个未来的 `HangingResolver`（与 Justifier 同层）负责。

## Follow-up

- Slice 4b 收尾时实现 PushIn（不实现 Hang）。
- Slice 4b 收尾的 ADR 应说明 PushIn 如何借用 Slice 5 的 `SpacingPlan` 容量。
- Hang 的真实实现单列后续 ADR（待办），包含：白名单字符集、与 justifier 的协调、与 line-end 半角的关系、关闭行尾对齐 (`textAlign != Justify`) 时的语义。

## 当前 PushIn 实现的已知简化

Slice 4b 收尾 (`feat: add punctuation glue push-in repair`, `feat: structure line repair decisions`) 已经把 PushIn 接进默认 kinsoku 修复链。落地实现有两处**已知**的简化，不影响正确性但需要后续 ADR 跟进：

1. **Capacity 与 spacing compression 的潜在双账。** `pushInCapacities` 来自 `atom.trailingGlue.natural - atom.trailingGlue.min`（[ParagraphLayoutEngine.kt:477](../../tiqian-layout/src/commonMain/kotlin/org/tiqian/text/layout/ParagraphLayoutEngine.kt) 的 `pushInCapacities()`），目前 `PunctuationAtomBuilder` 给所有标点的 `leadingGlue.min = trailingGlue.min = 0`，所以 capacity 等于完整 sideGlue。但 `PunctuationSpacingCompressor` 已经因为相邻标点把某条 trailing glue 用掉一部分时，PushIn 再借同一条 trailing glue 就会算两次。当前 fixture 不触发这个组合（相邻挤压发生在行内，PushIn 发生在跨行），但语义上是漏洞。
   - 修复方向：从 `SpacingPlan` 反推「已消费的 glue 量」，得 `effectiveTrailingGlueCapacity = (natural - min) - consumedBySpacingPlan`。
   - 或者在 `PunctuationAtomBuilder` 出 atom 时按 profile 设 `min > 0`，把强制保留量直接体现在 capacity 上。
2. **PushIn 只挤 offender 自己的 trailing glue。** 孔雀文章里「通过挤压」其实是「在本行多处选取四分空」分摊调整。当前实现只查 `pushInCapacities[offenderIndex]`，不会去借同行其它标点的 leading/trailing 空间。这意味着当 offender 本身是非标点 cluster（理论上现在不会发生，因为只有 punctuation 才会触发 forbiddenAtLineStart），或单条 trailing glue 不够而多条合计够时，PushIn 会被错误拒绝，退回 CarryPrevious。
   - 修复方向：让 `pushInCapacities` 输出整行可挤压资源的总和，并在 `tryPushIn` 内部按优先级（offender 自身 → 同行其它点号 trailing → leading）分配。

两者都不影响当前 fixture 与测试的结果，但应作为 ADR 0006 / 0007 的 follow-up 在 Slice 6（shaping adapter）之后处理——因为真实 ink bounds 进来后 `atom.trailingGlue` 的 `min` / `max` 才有实际可调依据，单凭 stub 现在没法做出合理的容量上限。
