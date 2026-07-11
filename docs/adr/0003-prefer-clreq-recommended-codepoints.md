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

## Amendment (2026-07): 替换的两道墨迹守门

替换只在「画得出、画得好」时成立,两个具名回退/矫正(dogfood 实测 Pixel 的
Noto CJK:其 `⸺` U+2E3A 与 `——` 连字共用同一个 ≈1.6em 墨迹、靠左放在 2em
advance 里,右侧留 ~0.35em 的洞):

- **`DashSubstitutionInkCoverageRollback`**:字体有 `⸺` 但单字形墨迹宽度
  < 85% × **CLREQ 两字宽目标盒**时回退到源码 `——`(阈值:Pixel Noto ≈80% 回退,
  Source Han ≈94% 保留)。仅在 shaper 报告 ink bounds 时判定;stub/AWT
  无 ink 保持替换(golden 不漂移)。
- **`DashInkCentering`**:无论保留还是回退,破折号 cluster 的 body 恒为
  二字宽(网格);当字形墨迹铺不满 body 时,把字形绘制原点移到墨迹居中
  (`Glyph.x` 偏移),单侧大洞变两侧对称小 bearing。桌面 Skia 渲染器按
  cluster 重排字形、不消费 `Glyph.x`,但满墨迹字体 inset≈0 本就不触发;
  Android 逐字形重放路径消费 `Glyph.x`。

### Amendment (2026-07-11): DashSubstitutionTwoEmInkCoverage

Web dogfood 证明上面的“advance”必须明确为**规范目标 advance**，不能取 shaper
返回的 advance。浏览器遇到首选字体不含 U+2E3A 时，Canvas 2D 不会报告 `.notdef`，
而会从 CSS 栈中画一个完整的一字宽 fallback glyph。该 glyph 的墨迹可以覆盖自身
advance 的 95% 以上，旧分母因此把“一字宽但很完整”的错误形态判成合格。

具名校验 `DashSubstitutionTwoEmInkCoverage` 固定以 `2em × 85%` 为门槛；不合格就
回滚到 source `——`。Web 端随后由 ADR 0039 的 `HarfBuzzVerifiedCjkDash` 从 CSSOM
实际 `@font-face` source 取得 cmap / glyph / ink 证据，确认同一 face 的两个 U+2014
各占一字、连续且居中后才增强；Canvas fallback 不再有资格证明“同一正文 face”。
family 名来自 CSSOM，不猜构建 hash，也不要求宿主重复声明字体。source range、复制和
搜索语义仍不变。
