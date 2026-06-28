# ADR 0037: Source-faithful plain text, mandatory breaks, and the CjkText entry

- Status: Accepted
- Date: 2026-06-28

## Context

提椠的目标之一是**以最少的代价替代 Compose `Text`**。但绝大多数纯文本来源（论坛、知乎、聊天、Markdown 源、纯文本社区）不会预先分好 `<p>`，只给 `\n`。当前 `CjkParagraph` 只接受「已分好的一段」，而引擎对 `\n` 没有任何处理：它分类成 `FontRole.Unknown`、被当字形 shape（出豆腐），`LookaheadLineBreaker` 也不认强制断行。

围绕「`\n` 是什么」出现过定义混乱：一种说法是「`\n` 是段内强制换行、连续多个 `\n` 才成段」（Markdown/HTML 约定）。这对中文纯文本是错的——作者**敲一次回车 = 一个块**，把单 `\n` 当段内软换行会把整篇塌成一两个巨段。

## Decision

### 1. `\n` = 硬断行；纯文本忠实呈现

把「source 不可改写」从**码点**延伸到**结构**：纯文本路径**所见即所得**。

- UAX#14 强制断行类 = 硬断行：`LF`(U+000A)、`VT`(U+000B)、`FF`(U+000C)、`CR`(U+000D)、`CRLF`、`NEL`(U+0085)、`LS`(U+2028)、`PS`(U+2029)。
- **连续强制断 = 空行，原样保留**（N 个空行显示 N 个空行，不折叠）。
- 控制符**不参与 shaping**（零宽、不出豆腐），由断点消费。
- 长行照常按宽度自动回绕（CJK 断行），续行齐头。
- **默认无首行缩进**：作者没缩进就不缩进。首行缩进/段间距是 `ParagraphStyle` 的 opt-in，给正式排版用，不是纯文本默认。

段内**强制换行**(`<br>` 那种「不分块只换行」)是另一回事、且在中文正文罕见，本 ADR 不为它引入独立概念——`\n` 一律按硬断行处理。

### 2. Compose 入口：`CjkText`

- `CjkText(String)` / `CjkText(AnnotatedString)` = 默认文本控件，按 §1 忠实呈现，是 Compose `Text` 的 drop-in。
- `CjkText(blocks: List<CjkBlock>)` 重载 = 结构化文档（段落/列表/章节，首行缩进/段间距经 `ParagraphStyle`）。
- **删除 `CjkParagraph`**：命名坏（与 Compose 底层 `androidx.compose.ui.text.Paragraph` 撞概念，且「Paragraph」暗示单段）。
- `Cjk` 前缀保留：scope 是完整 CJK（README roadmap 含 JLREQ/KLREQ），`ClreqProfile` 将与未来 `JlreqProfile`/`KlreqProfile` 并列。

## Implementation

引擎级（干净模块 `tiqian-linebreak` + `tiqian-layout`，不依赖 compose）：

1. `tiqian-linebreak`：识别强制断行类码点（含 `CRLF` 合一），产出 `BreakKind.Required` 断点。
2. 引擎 cluster 构建：强制断行符成独立零宽 cluster，标记「其后强制断 + 不 shape」。
3. `LookaheadLineBreaker`：接受强制断点集，在其处硬断（贪心/lookahead 不得跨越或填过）；只含强制断 cluster 的行 = 空行（零宽内容、一个行高）。
4. 默认 `firstLineIndent = 0`（纯文本路径）。
5. golden + 新 fixture：单 `\n`、多空行、首尾空行、`CRLF`、长行回绕齐头。

Compose 入口用 `CjkText` 直接接线；public `CjkParagraph` 不保留兼容别名。Compose
模块内部可以保留一个私有/`internal` layout node，但它不是作者 API。

## Alternatives considered

- **`\n\n` 才成段（Markdown）**：与中文写作相悖，会塌成巨段。否。
- **`CjkDocumentText` 严格文档子类型**（前空两格等）：多余——首行缩进/段间距是 `ParagraphStyle` 参数，不是新类型。否。
- **在 compose 层把 `\n` 切成多段、各自布局**：最省事，但碎掉单一 `LayoutResult`（跨段选择/无障碍/行栅格断裂），且要改 compose WIP 文件。引擎级是单一结果、可查询（见 ADR 0036 的 offset/line/box 查询），且落在干净模块。否（v1 即走引擎级）。
- **预发布期保留 `@Deprecated` 兼容别名**：库连测试版都算不上，不背历史包袱。否。
