# ADR 0003: PreferClreqRecommendedCodepoints（仅 display，不改 source）

- Status: Accepted
- Date: 2026-06-06

## Context

CLREQ 推荐若干标点的「更合适显示码点」，但用户实际输入往往是历史/输入法兼容写法：

```text
source "……"  vs  CLREQ 推荐 "⋯⋯"
source "——"  vs  CLREQ 推荐 "⸺"
source "・" "‧" "•" 等  vs  间隔号 "·"
```

如果替换 source text，会破坏复制粘贴、搜索、range mapping、IME 期望。如果完全不替换，又会受限于用户字体里某些码点的不良 glyph（例如 `……` 的六点在某些字体里不居中、`——` 中间断开）。

## Decision

引入 profile-driven 策略 `PreferClreqRecommendedCodepoints`，**只影响 layout cluster 的 `displayText`**，不影响 source。三个不变量：

1. source range 保持原样：复制、搜索、selection、hit-test 全部基于 source。
2. display 替换只在 layout 内部生效，dump 中通过 `font:start-end:source->display:role:...:reason` 显示。
3. 替换决策受 profile 控制；提供 `PreserveInput` profile 关闭所有替换。

第一批默认替换见 [clreq-punctuation-audit.md](../clreq-punctuation-audit.md)：

```text
"……" -> "⋯⋯"
"——" -> "⸺"
"・" "‧" "•" -> "·"
```

「只分类不替换」的字符（连接号 ~ – —、分隔号 / ／、句号变体 ．、双叹号 ‼、双问号 ⁇）只在 fallback 上倾向 CJK 字体，不改 code point。

## Consequences

- `ClreqPunctuationGlyphSubstitutor` 是替换的唯一入口；任何地方都不允许直接改写 `Cluster.text`。
- display 替换后仍可能改变 advance（例如 `——` → `⸺` 由两字符变为一字符）；`ClreqPunctuationAdvancePolicy` 负责换算 em advance，避免视觉宽度突变。
- profile 是替换决策的载体；区域差异（Mainland vs Traditional 的 `/` 与 `／`）落到 region profile，而不是 `if` 判断。
- 测试必须同时验证 source 和 display：source 是稳定 contract，display 是排版结果。

## Alternatives considered

- **直接改写 source。** 否决：复制/搜索行为破坏，对编辑器、辅助技术不友好。
- **完全不替换，要求用户输入「正确」码点。** 否决：把负担转嫁给用户，且不解决字体 fallback 问题。
- **依赖字体的 OpenType 特性自动选 glyph。** 部分接受：`chws / vchw / halt / palt` 仍然是输入之一，但不能假设所有字体都实现可靠。

## Amendment (2026-06-10): SubstitutionRollbackOnMissingGlyph

替换只有在 resolved font 真正覆盖目标码点时才成立。实测 `⸺` U+2E3A 在
PingFang SC / Hiragino Sans GB / Heiti SC 中都没有 glyph（.notdef 豆腐块），
只有 Source Han Sans 有。引擎因此增加回滚：shaper 通过
`ShapingDecisionInfo.missingGlyphs` 报告 .notdef 数量，替换 cluster 出现
missing glyph 时用 source text 重新 shaping，并在
`FontDecisionInfo.substitutionReason` 追加 `:SubstitutionRollbackOnMissingGlyph`。
source range / 复制 / 搜索语义不变（本来就以 source text 为准）。

## Follow-up

- Mainland / Traditional region profile 下 `/` ↔ `／` 的偏好。
- `！！！` `？？？` 等连续叹问号的二字宽压缩策略。
- 竖排时破折号、省略号、连接号的方向变化。
