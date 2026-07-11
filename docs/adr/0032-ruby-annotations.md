# ADR 0032: 行间注（拼音/注音 ruby）——分两刀，拼音先

- Status: Accepted
- Date: 2026-06-20

## Context

CLREQ §行间注（5.x）：基文旁的小字号标音/释义。两套标音系统几何差异很大：

| | 拼音（罗马） | 注音（ㄅㄆㄇ） |
|---|---|---|
| 位置（横排） | 基字**上方** | 基字**右侧** |
| 字符 | 拉丁、非等宽、宽窄不一 | 等宽、每音 ≤3 符 + 调号 |
| 占位 | 优先使用基字上方的**行间空间**，不足时才扩充行高 | 右侧占**半字号** → 吃**字宽** + 纵横对齐均匀预留 |
| 地区 | 大陆/简体横排 | 台湾/繁体 |

拼音=上方，正合本引擎（Simplified-horizontal）；注音=右侧，牵动 advance/纵横对齐，是竖排前哨。

## Decision

**分两刀，本 ADR 落地第一刀（拼音 ruby，上方）。** 注音（右侧竖排 ㄅㄆㄇ + 调号 + 半字预留）
留作第二刀，单独 ADR（它改 advance 模型）。

### 第一刀 · 拼音（上方）模型

- **`RubySpan(baseRange, text, fontFamilies)`**（core），随 `LayoutInput.rubySpans` 进引擎。
  与 `DecorationSpan` 不同：ruby 有独立字体度量、避让和**断行约束**（基文不可拆），
  并在既有行间空间不足时参与 line-box 高度计算，不是渲染器自行猜位置的纯装饰。
- **注文专用字体**（per-span `fontFamilies`）：注文本就该独立于正文——注音需含 ㄅㄆㄇ
  字形的字体，拼音/释义各取所需，且「拼注音共同标注」一字两注可各用其字体。经共享
  `SkiaSystemTypefaces.typeface` 解析（空 = 默认 Latin 面）。作者面 `cjkRuby(base, ruby,
  fontFamily)`（注解项内 `font‹US›reading` 编码）。
- **注文字号** = `RUBY_FONT_EM`（0.5em）。CLREQ §罗马拼音:「注文与基文的字号关系并无定数，
  但受**振假名**排版习惯影响，注文常使用基文 **1/2** 字号」——0.5em 即此约定俗成，留作默认可调。
- **条件式行高 + 垂直摆位（Latin 字体度量，不看注文墨迹）**：注文在自己的字体与字号下只
  shape 一次，结果只供横向宽度与避让；纵向始终使用该 Latin 字体原有的 typographic
  ascent / descent，缺少 typographic 度量时才回退字体 ascent / descent。读音内容不参与
  行高判定，因此同一字体下把 `hé` 换成带升部或降部的读音也不会改变行距。
  `RUBY_STACK_GAP_EM` 默认 0，要更松才增加。
  - 注文基线 = `基字字面顶 − clearance − Latin 字体 descent`，同一注文字体使用稳定的
    垂直位置，不随具体字形的墨迹变化；
  - 现有可用空间 = `resolved lineHeight − 基文字面高`，所需空间 =
    `Latin 字体 ascent + descent + clearance`；只有后者更大时才产生差额；
  - `ParagraphStyle.rubyLineHeightMode = PerLine`（默认）只把差额加在含注文的行之前，
    即单行加高；`UniformParagraph` 把同一差额加到整段每一行，保持统一基线间距；
  - 差额为 0 时两种模式都**不改变任何 `LineBox`、基线或段落高度**。注文仍可能越过当前
    line box 的上边界，因为完整行间空间分属相邻两个 line box；前端必须允许这类 paint overflow。
- **宽度 = 避让（CLREQ §罗马拼音）**：「相邻注文的间距不应小于**西文词间空格**的宽度」+「只要
  不侵犯最小间距，**可允许注文伸展到相邻基字上方**」。即:
  - 间距基准 = **一个注文词空格** ≈ `0.25 × 注文字号`（`RUBY_MIN_GAP_EM_OF_RUBY`，**注文尺度**
    不是基字 1/4——纠正过两次的关键）;
  - 判据 `中心距(i,i+1) ≥ (注文宽ᵢ+注文宽ᵢ₊₁)/2 + 词空格`，注文宽**实测**（注文自己的字体）;
  - 左→右一遍，**只在不够时**补最小 trailing 字距（`computeRubySpread`），够了就**悬出**不撑;
  - 撑开是**结构性** advance（`PunctuationGeometryLedger.rubySpreadByCluster`），断行**之前**注入、
    贯穿到最终 geometry → 断行/对齐自然跟上;
  - 注文**居中于基字内容**（`computeRubyDecisions` 用 natural 宽，排除 trailing 撑开量）。
- **断行**：基文 cluster 范围进 `unbreakableRanges`（基文+注文不可拆，CLREQ §注释符号「注释记号
  与被标记文字不能断行」），与示亡号同一机制。分词连写则以词为 `baseRange`。
- **几何**：最终布局后算 `RubyDecisionInfo(baseRange, text, lineIndex, centerX, baselineY,
  fontSize)`——注文水平**居中于基字范围**，基线由注文 descent 与基字字面顶确定。renderer 走 `shapeTextBlob` 画
  注文（与正文同一 locl 路径）。
- **作者面**：`cjkRuby("北京", "Běijīng")`（AnnotatedString 注解，注文是注解值、基文是包裹文本），
  `cjkRubySpans()` 抽取。源文本只含基文（拼音不进源，复制/搜索保真）。

### Amendment (2026-07-11): 先用既有行间空间，差额才加高

原实现只看当前 line box 的上半 leading，把能完整放进相邻两行之间的 0.5em 注文也
当成溢出，导致带注文的行无条件变高。现改为比较完整行距
`lineHeight - 基文字面高` 与注文 Latin 字体的 ascent / descent 占用：能放下时零变化，
放不下时才补差额。具体注文的墨迹不参与判断，避免读音内容改变段落节奏。
补差额有两种明确策略：默认 `PerLine`，以及需要统一基线网格时使用的
`UniformParagraph`。两者都进入 `RubyLineHeightDecisionInfo` 与 layout dump。

## Consequences

- 引擎改动：条件式 line-height deficit + geometry decision + 基文进 unbreakable +
  **避让结构性 advance**（注文宽驱动的字距下限）。默认只加高空间不足且含注文的行；
  需要整段统一时显式选择 `UniformParagraph`。
- 注文可解释：`RubyDecisionInfo` 入 dump（基文、注文、居中 x、字号）。
- 第二刀（注音）会改 advance（右侧半字预留）+ 引入竖直堆叠/调号，单独立 ADR。

## Alternatives considered

- **拼音也做避让（撑开基字）先行**：否决——避让动 advance/断行，v1 先用悬挂把基础设施跑通，
  避让作增量。
- **ruby 当 DecorationSpan**：否决——decoration 不带注文字体度量、条件式行高、避让或断行约束。
