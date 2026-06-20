# ADR 0032: 行间注（拼音/注音 ruby）——分两刀，拼音先

- Status: Accepted
- Date: 2026-06-20

## Context

CLREQ §行间注（5.x）：基文旁的小字号标音/释义。两套标音系统几何差异很大：

| | 拼音（罗马） | 注音（ㄅㄆㄇ） |
|---|---|---|
| 位置（横排） | 基字**上方** | 基字**右侧** |
| 字符 | 拉丁、非等宽、宽窄不一 | 等宽、每音 ≤3 符 + 调号 |
| 占位 | 上方宽 ≤ 基字 → 吃**行高** | 右侧占**半字号** → 吃**字宽** + 纵横对齐均匀预留 |
| 地区 | 大陆/简体横排 | 台湾/繁体 |

拼音=上方，正合本引擎（Simplified-horizontal）；注音=右侧，牵动 advance/纵横对齐，是竖排前哨。

## Decision

**分两刀，本 ADR 落地第一刀（拼音 ruby，上方）。** 注音（右侧竖排 ㄅㄆㄇ + 调号 + 半字预留）
留作第二刀，单独 ADR（它改 advance 模型）。

### 第一刀 · 拼音（上方）模型

- **`RubySpan(baseRange, text, fontFamilies)`**（core），随 `LayoutInput.rubySpans` 进引擎。
  与 `DecorationSpan` 不同：ruby **吃度量**（行高）+ **吃断行**（基文不可拆），不是纯渲染。
- **注文专用字体**（per-span `fontFamilies`）：注文本就该独立于正文——注音需含 ㄅㄆㄇ
  字形的字体，拼音/释义各取所需，且「拼注音共同标注」一字两注可各用其字体。经共享
  `SkiaSystemTypefaces.typeface` 解析（空 = 默认 Latin 面）。作者面 `cjkRuby(base, ruby,
  fontFamily)`（注解项内 `font‹US›reading` 编码）。
- **注文字号** = `RUBY_FONT_EM`（0.5em）。CLREQ §罗马拼音:「注文与基文的字号关系并无定数，
  但受**振假名**排版习惯影响，注文常使用基文 **1/2** 字号」——0.5em 即此约定俗成，留作默认可调。
- **行高**：有 ruby 时**每行**预留注文带（`ascent += RUBY_BAND_EM`）。CLREQ「行距不随标注与否变」
  → **均匀**预留（非逐行差异）。**垂直摆位**：注文基线 `RUBY_BASELINE_DROP_EM`（1.12em）必须让
  注文**降部**（g/j/p/y）越过基字字面顶（0.88em）留出空当——否则降部蹭字（实测修正）。
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
  fontSize)`——注文水平**居中于基字范围**，基线落在注文带内。renderer 走 `shapeTextBlob` 画
  注文（与正文同一 locl 路径）。
- **作者面**：`cjkRuby("北京", "Běijīng")`（AnnotatedString 注解，注文是注解值、基文是包裹文本），
  `cjkRubySpans()` 抽取。源文本只含基文（拼音不进源，复制/搜索保真）。

## Consequences

- 引擎改动：行高 band + geometry decision + 基文进 unbreakable + **避让结构性 advance**（注文宽
  驱动的字距下限）。无 ruby 时 `rubySpreadByCluster` 空、band 0 → **零 golden 漂移**。
- 注文可解释：`RubyDecisionInfo` 入 dump（基文、注文、居中 x、字号）。
- 第二刀（注音）会改 advance（右侧半字预留）+ 引入竖直堆叠/调号，单独立 ADR。

## Alternatives considered

- **拼音也做避让（撑开基字）先行**：否决——避让动 advance/断行，v1 先用悬挂把基础设施跑通，
  避让作增量。
- **ruby 当 DecorationSpan**：否决——decoration 是纯渲染（不吃度量/断行），ruby 两者都吃。
