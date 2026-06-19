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

- **`RubySpan(baseRange: TextRange, text: String)`**（core），随 `LayoutInput.rubySpans` 进引擎。
  与 `DecorationSpan` 不同：ruby **吃度量**（行高）+ **吃断行**（基文不可拆），不是纯渲染。
- **注文字号** = `RUBY_FONT_EM`（0.5em，注文 ≤ 基字，CLREQ）。
- **行高**：有 ruby 时**每行**预留注文带（`ascent += rubyBand`，band ≈ 注文字号 + gap）。CLREQ
  「行距不随标注与否变」→ **均匀**预留（非逐行差异），简单且合规；基线随之下移腾出上方。
- **宽度（v1）**：注文比基字宽时**对称悬挂**（overhang）进邻字 ruby 空带——**基字 advance 不变**，
  断行/对齐完全不受 ruby 宽影响。**避让**（撑开基字/加字距）= 后续。
- **断行**：基文 cluster 范围进 `unbreakableRanges`（基文+注文不可拆，CLREQ §注释符号「注释记号
  与被标记文字不能断行」），与示亡号同一机制。分词连写则以词为 `baseRange`。
- **几何**：最终布局后算 `RubyDecisionInfo(baseRange, text, lineIndex, centerX, baselineY,
  fontSize)`——注文水平**居中于基字范围**，基线落在注文带内。renderer 走 `shapeTextBlob` 画
  注文（与正文同一 locl 路径）。
- **作者面**：`cjkRuby("北京", "Běijīng")`（AnnotatedString 注解，注文是注解值、基文是包裹文本），
  `cjkRubySpans()` 抽取。源文本只含基文（拼音不进源，复制/搜索保真）。

## Consequences

- 引擎改动面小：行高 + 一条 geometry decision + 基文进 unbreakable；advance 不动 → 既有 golden
  仅在「有 ruby」的新 fixture 上变，无 ruby 时零漂移。
- 注文可解释：`RubyDecisionInfo` 入 dump（基文、注文、居中 x、字号）。
- 第二刀（注音）会改 advance（右侧半字预留）+ 引入竖直堆叠/调号，单独立 ADR。

## Alternatives considered

- **拼音也做避让（撑开基字）先行**：否决——避让动 advance/断行，v1 先用悬挂把基础设施跑通，
  避让作增量。
- **ruby 当 DecorationSpan**：否决——decoration 是纯渲染（不吃度量/断行），ruby 两者都吃。
