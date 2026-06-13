# ADR 0025: 按行长自适应的禁则档 + 悬挂默认

- Status: Accepted
- Date: 2026-06-13

## Context

CLREQ 行首行尾禁则分四档（[ADR 0020 amendment] 的 `KinsokuLevel`：不处理 /
基本处理 / GB 法 / 严格处理），行尾悬挂是 opt-in（ADR 0006）。这两者此前
是 profile 上的固定值，需要调用方手动选。

`KinsokuHangingExperimentProbe` 在两份语料上做了实测（行长以字数计、
确定性 stub shaper）：

- **zh.wikipedia 正文 80k 字**（破折号/省略号仅 0.03%/0.004%）；
- **破折号/省略号注入至 ~1% 的文学体 50k 字**。

指标：每行两端对齐拉开的最宽单个汉字字距（max CjkInterChar，em）的
mean/p95，加 LeaveRagged / CarryPrevious / Hang 频次（每千行）。结论：

1. **舒适下限 ≈ 14 字**：再窄，p95 字距 > 1/4 em 且开始出现无法修复的行
   （ragged）。
2. **GB ↔ 严格 在百科体几乎无差**（破折号太罕见）；在文学体严格更贵——
   平均字距 +5%、CarryPrevious +2~3/千行，且这代价**延续到宽行**（28 字
   仍有），因为 2em 破折号落行首既挤不进也削不了，只能 carry。但宽行下
   字距已极小（p95 < 0.1em），这点代价可忽略。
3. **悬挂的收益集中在窄行（≤ ~12–16 字）**：把无法修复的行清零、把整字
   推出（CarryPrevious）腰斩；典型行的平均字距几乎不变——收益在尾部。
   ≥24 字每千行触发 < 1.5 次，40 字几乎不触发。

## Decision

把禁则档 + 悬挂合并为 `ClreqProfile.kinsokuMode: KinsokuMode`，默认
`MeasureAdaptive`，按行长（`maxWidth / fontSize`，单位字）解析：

| 行长 | 档 | 悬挂 |
|---|---|---|
| < 14 字 | 基本处理 | **开**（顿逗句） |
| 14–24 字 | 基本处理 | 关 |
| > 24 字 | GB 法 | 关 |
| > 32 字 | 严格处理 | 关 |

- **< 14 → 悬挂**：直接对应实验结论（窄行悬挂收益最明显）。
- **> 24 GB、> 32 严格**：是「宽行能负担更严禁则」的取舍——实验证明的是
  更严档在宽行**变便宜**，而非变更好（严格唯一效果是禁破折号/省略号居
  行首，纯审美）。默认升档无害且符合「宽行从严」的常规品味。
- `KinsokuMode.Fixed(level, hanging)` 固定一档，供需要确定行为者（含
  仓库内 repair-mechanism 测试 fixture）。
- 解析结果记入 `LayoutDebugInfo.kinsokuDecision`，dump 增 `kinsoku` 行
  （measure / level / hang / reason），满足「新增决策即新增 dump」。

CLREQ 主张「一份文档内禁则级别应统一」；自适应是面向响应式 / 移动端
重排（measure 随容器变）的现代扩展，并非违背——同一容器宽度下全段一致。

## Consequences

- 默认行为改变：无 profile override 时，窄版心（< 14 字，如手机正文）
  自动启用悬挂，宽版心自动升档。golden 仅新增 `kinsoku` 决策行，无断行
  变化——证明悬挂是尾部效应（仅 PushIn 失败时才触发）。
- repair-mechanism 微 fixture 与单测 pin `Fixed(Basic)`（`pinBasicNoHang`），
  与 pin `firstLineIndentEm = 0` 同理，避免自适应掩盖被测的具体修复。
- 合并清理：删除从未接线的旧 `HangingPunctuationPolicy` 预留枚举与
  `AdjustmentStylePolicy.hangingPunctuation`、`ClreqProfile.kinsokuLevel`
  两个独立字段，统一到 `kinsokuMode`。
- 阈值（14 / 24 / 32 字）是 `MeasureAdaptive` 的可调字段；语料换代或加入
  竖排后用 `KinsokuHangingExperimentProbe` 重新标定。
