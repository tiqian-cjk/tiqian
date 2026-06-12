# ADR 0022: ShrinkToFit 断行——「先挤进」的一般化（否决）

- Status: **Rejected** (2026-06-12，实现完成后整段回退)
- Date: 2026-06-12

## Context

CLREQ 的挤压处理目前只在避头尾修复里使用：禁则字符落到行首时，PushIn
按六档（ADR 0020）压缩前一行把它收进去。普通断行按自然宽度判定——
cluster 放不下就整体下行，即使差额远小于行内可压缩空间。

触发讨论的场景（compose demo 第二段，左对齐）：破折号是不可拆分的
2em cluster，行剩 1.93em——差 2px 放不下，整体下行，行尾留近两字宽
空白；而行内 `，` `”` 的 glue 容量有 30px。

## Considered design (implemented, then reverted)

cluster 准入从「自然宽度 ≤ 行宽」放宽为「自然宽度 − 行内挤压容量 ≤
行宽」，行收口按 ADR 0020 六档分配压缩，记为 `PushIn`（reason 前缀
`ShrinkToFitLineFill` 区分于 `ForbiddenAtLineStart`）。greedy /
lookahead / 评分路径同一准入；避头尾修复降为兜底。

实现后 golden 显示的全局效果：`real-paragraph-1` 多数行通过标点挤压
多收一个字（每行 shrink 8–20px），拉伸行几乎消失，行多以压缩态填满。

## Decision: rejected

否决理由（用户复审）：**普通两端对齐不应以挤压为常规填充手段。**

- CLREQ 的挤压程序服务于「需要调整时」——避头尾修复、行长微调——
  而不是把每一行都尽量多塞一个字。全面 shrink 准入让行末标点削半、
  行内句读压缩成为**常态**而非例外，版面密度系统性偏紧。
- 「先挤进，后推出」的原文语境是禁则修复链，把它推广为一等断行能力
  是过度引申。
- 动机场景本身（差 2px 的破折号）在两端对齐下并不存在视觉问题——
  剩余空间会被 justify 拉伸吃掉；左对齐下行尾不齐本来就是预期形态。

## Consequences

- 断行准入维持自然宽度判定；挤压只出现在避头尾 PushIn 修复中。
- 实现期间顺带发现并已独立修复的问题不随回退（uniform tracking、
  渲染器 role 包含匹配等，见各自 commit）。
- 若将来要重新评估，需先回答：压缩态填满的版面是否真是目标风格——
  那是一个 AdjustmentStylePolicy 级别的 opt-in，而不是默认行为。
