# ADR 0019: Latin 分词与西文词距

- Status: Accepted
- Date: 2026-06-11

## Context

Latin run 此前是单 cluster：长西文句无法换行（只能整体溢出），CLREQ 拉伸
第一档「西文词距」无从参与（justify 的 WordSpace 一直 no-op），挤压侧的
词距档（gap audit 缺口 4）也没有载体。

## Decision

### 分段发生在 shaping 输入层（`LatinWordSegmentation`）

`LatinText` font decision 在进 shaper 前按「词 / 空格串」交替切成子 range，
每段独立 shaping——每个词、每串空格成为独立 cluster。其它 role 不分段。
跨空格的 kerning 损失可忽略。选择输入层而非 shaping 输出层切分的原因：
不依赖 glyph→字符的 cluster 映射（我们的 `Glyph` 模型无此信息，且连字会
破坏一一对应）。

### 空格 cluster 的三种身份

- **中西 gap**（CjkText 相邻）：空格串本身就是 sino-western gap，advance
  归一为 `gapEm`（`TextAutoSpaceReplace:space-cluster-to-gap`，decision
  side="gap"）。渲染层无需任何偏移——cluster 宽度即间距。
- **词空格**（两侧都是 Latin 词）：保持原 advance；justify 的 WordSpace 档
  对其拉伸至最终 ≤0.5em（CLREQ 第一档绝对上限，一行内多处同时、同等量）。
  （2026-06-13 订正：stub 把 U+0020 建模为二分空 0.5em，恰在上限、不再
  拉伸；真字体的更窄西文空格才有余量——见 clreq-gap-audit「已知偏离」。）
- **行边空格**：整体塌缩为 0（`LineEdgeWordSpaceCollapse`，CSS 式行边
  空格移除；CLREQ 西文行边无空白同理）。

`TextAutoSpaceInsert`（无空格的直接 CJK↔词边界）保持既有机制：gap 计入
词 cluster advance、渲染层按 side decision 偏移、行边由
`TextAutoSpaceLineEdgeTrim` 削除。

### 断行

词/空格 cluster 边界天然是断行点：行尾落在空格上则塌缩，行首遇空格同样
塌缩。`greedyBreakerKeepsLatinRunAsSingleCluster` 的旧限制（整句溢出）
不复存在；无空格的单个超长词仍不可拆（hyphenation 不在本期）。

## Consequences

- 长西文在中文段落里正确换行；`latin-word-wrap` fixture + golden。
- justify 拉伸三档全部可用：WordSpace → CjkLatinSpace → CjkInterChar。
- 渲染层的 strip 机制（从 cluster 文本中剥离空格再补 gap）失去触发条件
  （词 cluster 不再含空格），保留为死路径，后续清理。
- 词空格成为 Slice 13 挤压分层的载体（min 1/4em，CLREQ 挤压第②档）。
