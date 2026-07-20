# ADR 0016: Android TextPaint adapter 与 Han 上下文 shaping

- Status: Accepted
- Date: 2026-06-10
- Amendment 2026-06-25：真实应用 dogfood 暴露出 Android renderer 仍会在
  draw 阶段重新让平台理解文本，可能与 measure 阶段得到的 CJK glyph 形态
  不完全一致。renderer 不得根据 `PunctuationDecisionInfo` 做 dash 专用缩放；
  后续 slice 已让 Android backend 形状与绘制同源（shape once, draw the
  positioned glyphs），而不是在前端做标点几何修正。

## Context

Slice 6 的平台收尾：AWT（ADR 0013）与 Skiko（ADR 0015）已交叉验证了标点几何，
还差 Android 平台真值。Android 的文本栈（Minikin/HarfBuzz）不暴露 script 控制，
且 typeface 永远带不可关闭的内部 fallback 链——contract 上「单一字体测量」在
Android 只能近似为「该 locale 下的平台文本栈测量」。

## Decision

新增 `shaping/android-adapter`（AGP 9.2.1，minSdk 31，AGP 内建 Kotlin）：

- `AndroidPaintTextShaper`：advance 来自 `Paint.getRunAdvance`，per-glyph
  id/位置/Font 来自 `TextRunShaper.shapeTextRun`（API 31+），ink bounds 来自
  `Paint.getTextBounds`（仅单 glyph cluster）。`Glyph.x/y` 保留 glyph origin，
  `Glyph.renderFontKey` 通过有界的 Android 专用 registry 指回 shaping 阶段的
  `Font`；旧 key 淘汰后 renderer 回到同一上下文字符串绘制路径，不让进程级
  registry 无限持有平台字体对象。
- `LocaleTaggedShaping`：`Paint.textLocale` 取 `TextStyle.locale`。
- `FontHaltMeasurement`：第二次测量用 `fontFeatureSettings = "'halt' on"`，
  产出 `Glyph.haltAdvance` / `haltPlacementX`，feature 不进渲染几何。
- `SystemAndroidFontProbe`：CJK role 显式解析 CJK typeface
  （`NotoSansCJK-Regular.ttc` 取 **ttcIndex 2** = SC face，与 AOSP fonts.xml
  对 zh-Hans 的映射一致）。不显式指定时 Roboto 在 fallback 链首位，会接管
  `—` `…` 等共用码点。

### HanContextShaping（关键决策）

孤立的 `—` 是 script-COMMON 码点，HarfBuzz 对单字符 buffer 解析为 OpenType
DFLT script，而 Noto Sans CJK 的 `locl` 规则注册在 hani/latn/cyrl/… 下
**唯独不含 DFLT**——上下文无关的逐 cluster shaping 会静默拿到西文形破折号
（0.89em）。桌面 adapter 用 `TrivialScriptRunIterator` 强制 `Hani` 解决；
Android 没有公开的 script 控制，且 `getRunAdvance`/`shapeTextRun` 的
context 参数不参与 HB 的 script 推断（buffer 只含 run 本身）。

因此 CJK role 的 cluster 统一放进 `中<cluster>中` buffer 整体 shaping，再按
offset 切回该 cluster 的 glyph 与 advance（pen 原点用 `getRunAdvance` 差分，
不用 glyph x——`halt` 的 placement 位移正是要单独上报的量）。这正是真实
Android 段落里 Minikin 给这些字符的环境，不是 hack。glyph↔字符无法 1:1
对应时（连字）回退到上下文无关 shaping。

### 平台限制（已记录，golden 需容忍）

- `Paint.getTextBounds` 无 context 参数：`locl` 替换后的破折号 ink bounds
  量到的是替换前的 glyph，仅诊断用途受影响。
- typeface fallback 链不可关闭：缺字时由系统兜底而非报 .notdef，
  `missingGlyphs` 改用 `Paint.hasGlyph` 上报。
- 多 glyph cluster 不报 per-glyph ink bounds（走 `MissingInkBoundsFallback`）。

### 设备实测（emulator API 37, Noto Sans CJK 2.004）

instrumentation 测试（`connectedAndroidTest`）复现桌面双引擎的全部不变量：
全宽标点 1em；`halt` body 0.5em 且 placement 方向正确（`。`→0、`（`→-8）；
`locl` 破折号整 em；ink 落在 profile glue 侧的对侧；缺字上报。

真实应用 dogfood 暴露出一类 renderer 层错位：Android measure 与 draw
路径虽然都试图提供 Han context，但 draw 阶段仍以 `Canvas.drawTextRun`
重新 shaping 文本，而不是重放 measure 阶段已经得到的 glyph id/position。
这类问题已经收敛到 Android backend 的同源 shaping/drawing 能力：API 31+
renderer 优先用 `Canvas.drawGlyphs` 按 `LayoutResult.glyphRuns` 里的 glyph
id、origin、Font 绘制；只有缺少平台 Font key 时，才退回同一 renderer 内的
字符串绘制 containment（例如 registry 中过旧的 Font key 已被淘汰）。
`AndroidLayoutRenderer` 不再按标点类型做几何变形。

## Consequences

- 标点几何的「三平台互证」完成：AWT、Skia、Android 在同一字体家族上给出
  一致的 body/glue/方向结论。
- Android 的测量与主文本绘制在 API 31+ 上同源：layout 消费的 glyph id /
  origin / Font 被 renderer 直接重放，避免 draw 阶段再次让平台重新理解文本。
- Android 真机/模拟器是唯一需要外部环境的测试路径，不进默认 `build`；
  按需跑 `:shaping:android-adapter:connectedAndroidTest`。
- `local.properties`（sdk.dir）为本机配置，不入库。

## Alternatives considered

- **接受西文形破折号作为平台差异。** 否决：真实 Android 渲染在 Han 段落里
  就是中文形，上下文无关测量的西文形是测量方法的伪差异，不是平台真值。
- **Typeface.CustomFallbackBuilder 构造带语言属性的字体链。** 否决：构造出的
  字体仍不携带 fonts.xml 的 lang 属性，无法影响 HB 的 script/language 解析。
