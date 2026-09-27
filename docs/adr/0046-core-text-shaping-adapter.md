# ADR 0046: Core Text shaping 与度量适配器

- Status: Accepted
- Date: 2026-08-08
- Refines: [ADR 0008](0008-shaping-adapter-contract.md)（Shaping adapter contract）；与 [0013](0013-jvm-awt-shaping-adapter.md) / [0015](0015-skiko-shaping-adapter-cross-check.md) / [0016](0016-android-textpaint-adapter.md) 并列

## Context

[ADR 0045](0045-apple-kotlin-native-target.md) 让组合核心跑上 Apple,但引擎要产出实际 `LayoutResult`,还需要平台的 `TextShaper`(整形)与 `FontMetricsResolver`(字体度量),即 ADR 0008 的适配器接口。JVM 有 AWT([0013](0013-jvm-awt-shaping-adapter.md))与 Skia([0015](0015-skiko-shaping-adapter-cross-check.md)),Android 有 TextPaint/native([0016](0016-android-textpaint-adapter.md));Apple 缺一个对等适配器。

## Decision

`CoreTextShapingAdapter`:新增 `:shaping:coretext`(`macosArm64`、`iosArm64`、`iosSimulatorArm64`),用 Kotlin/Native **内置的 `platform.CoreText` / `platform.CoreFoundation` 绑定**,无需自定义 cinterop def。

- **`CoreTextShaper`**:以 `CFAttributedString` + `CTLineCreateWithAttributedString` 整形,遍历 `CTRun` 用 `CTRunGetGlyphs` / `CTRunGetPositions` 抽取字形,产出**一个 cluster + 一个 glyph run**(做法与 AWT/Skia 适配器相同:消费 layout 决定的 `displayText`,不做 fallback / CLREQ 替换 / 标点决策)。ink bounds 用 `CTFontGetBoundingRectsForGlyphs`,并把 CG(+y 向上,基线相对)转成核心约定(+y 向下、基线上方为负)。逐字形 advance 由相邻 position 差分,末字形取 `CTLineGetTypographicBounds` 的总宽,与 Skia 适配器一致。
- **`CoreTextFontMetricsResolver`**:`CTFontGetAscent/Descent/Leading`(hhea 盒)+ 读 `OS/2` `sTypoAscender/Descender`(`CTFontCopyTable`)得到 CJK **字身框**,对标 `SkiaFontMetricsResolver` 与 [ADR 0002](0002-script-aware-font-metrics.md) amendment。
- **测绘同源**(contributing.md 约束 / [ADR 0016](0016-android-textpaint-adapter.md) 指导原则):整形与绘制使用**同一个 `CTFont`**,前端按同一字形 id 重放。
- **语言与 feature 同源**：paragraph locale 写入 `kCTLanguageAttributeName`；`tag` / `tag=value`
  形式的 OpenType feature 通过 Core Text font descriptor 写入同一条缓存 `CTLine`，renderer 复用
  `GlyphRun` 中实际施加的 feature。无效或 Core Text 无法实例化的请求记录
  `CoreTextOpenTypeFeatureUnavailable` 后才显式退回无 feature shaping。
- 新增 `ShapingSource.CoreText`。默认 face:`PingFang SC`(CJK)/ `Helvetica Neue`(Latin)。

## Consequences

- Apple 上有实际的 shaping 与字体度量;引擎的 CLREQ 规则(避头尾、标点挤压、两端对齐、注音)以**实际 Core Text 测量**驱动、端到端生效。
- 代价(诚实记录):`halt`(标点半角实测,ADR 0014 follow-up)仍暂缓；第一版未做逐
  cluster 的多 face policy（Core Text 可在 run 内产生平台 fallback face，但 fallback 选择仍不成为核心
  可解释 decision）。

## Alternatives considered

- **在 Native 上接 HarfBuzz + FreeType。** 否决:Core Text 是 Apple 的平台原生文本栈,符合 [ADR 0016](0016-android-textpaint-adapter.md)「尽量复用平台已有能力」的指导原则,且免去第三方依赖与字体加载重实现。
- **自定义 cinterop def(手写头文件绑定)。** 不必要:Kotlin/Native 内置的 `platform.CoreText` 绑定已覆盖所需 API。

## Verification

- `:shaping:coretext:macosArm64Test` 在实际系统字体上覆盖中/西文 shaping、advance、ink bounds、
  `OS/2` sTypo 字身框、locale，以及 `liga=1` / `liga=0` 的实际 glyph 差异；无效 feature 断言具名
  capability issue。相同测试源也在 `iosSimulatorArm64Test` 执行。
- 关于 **golden**:`LayoutDumpGoldenTest` **有意**使用确定性 stub shaper(平台字体会让 golden 机器相关),因此平台适配器**不建机器精确 golden**,这与 [0013](0013-jvm-awt-shaping-adapter.md) / [0015](0015-skiko-shaping-adapter-cross-check.md) 一致(0015 亦记录了 AWT↔Skia 的合理分叉,用结构断言 + 交叉一致而非逐值 golden)。上游 stub golden 套件仍然全部通过,证明引擎未被本适配器改动。
