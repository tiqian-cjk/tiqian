# ADR 0047: Core Text 渲染前端

- Status: Accepted
- Date: 2026-08-08
- Refines: 与 [0017](0017-compose-desktop-renderer.md) / [0035](0035-android-compose-gallery.md) / [0039](0039-web-rendering-path.md) 并列(前端);消费 [ADR 0046](0046-core-text-shaping-adapter.md)

## Context

[ADR 0046](0046-core-text-shaping-adapter.md) 让 Apple 能产出 `LayoutResult`,但还需要一个前端把它画出来,对标 Compose([0017](0017-compose-desktop-renderer.md)/[0035](0035-android-compose-gallery.md))与 Web([0039](0039-web-rendering-path.md))。按 contributing.md 与 [ADR 0001](0001-core-pipeline-and-platform-boundary.md) 的边界,前端只**呈现 `LayoutResult`**,不实现标点挤压 / 避头尾 / 两端对齐等排版规则。

## Decision

`CoreTextRenderingFrontend`:新增 `:frontend:apple:coretext-render`(`macosArm64`、`iosArm64`、`iosSimulatorArm64`)；
其 Kotlin renderer 包为 `org.tiqian.apple.coretext`，与 `org.tiqian.shaping.coretext` 分开。

- **`CoreTextLayoutRenderer`**:用 `CTFontDrawGlyphs` 画 `LayoutResult`,按字形 id 重放,pen 按 `Cluster.advance` 步进,`clusters` 与 `glyphRuns` 平行对应(逐 cluster index 取对应 run),做法与 `SkiaLayoutRenderer` 相同。坐标:`LayoutResult` 为左上原点 / y 向下,`CGContext` 为左下 / y 向上,故 `layoutY → canvasHeight - layoutY`,用默认 text matrix 让字形正立(无需翻转上下文)。
- **`AppleParagraphBackend`**:把引擎接到 `CoreTextShaper` + `CoreTextFontMetricsResolver` + `LookaheadLineBreaker`,其余接入点(clreq profile / justifier / hyphenator / role classifier / fallback)用引擎默认,对标 `DesktopParagraphBackend` 的最小构造。
- **`frontend/apple` umbrella**：生产 Swift facade、XCFramework 打包、Swift Package 与原生 view
  共同属于 Apple frontend，不属于 demo。内部 renderer 收在 `frontend/apple/coretext-render`；原生
  `AttributedString` authoring 把组合的 font/color/ruby/decoration 属性独立 lowering 到同一 source
  range；demo 只消费这个包并提供样例内容。
- **Swift API 命名**：公共 API 使用 `CJKText`、`CJKBlock`、`CJKAttributes` 等领域名称，不给每个
  类型重复加 `Tiqian` 前缀；品牌名保留在 `TiqianUI` 模块与包内 `Tiqian.xcframework` artifact。
- **最低系统版本**：原生 Swift `AttributedString` 是 authoring 接口，因此 Swift Package 的自然
  下限为 iOS 15。iOS 12 需要另一套 `NSAttributedString`/纯文本 authoring 与 pre-iOS 13 selection
  交互，不作为同一 API 的条件分支伪装支持。
- **原生 view 接入层**：`CJKTextView` 在 macOS 直接暴露 `NSScrollView + NSView`，在 iOS 直接暴露
  `UIScrollView + UIView`；SwiftUI `CJKText` 只包装该原生 view。两端只负责 viewport 生命周期、滚动、动态系统颜色、坐标换算和
  accessibility source text；宽度变化复用同一 `DocBuilder`，不引入 TextKit 或第二份排版结果。
- **原生 selection 接入点**：`frontend/apple` 将 document 全局 UTF-16 source offset 映射到每个
  placed block 的核心 hit-test / caret / selection box。iOS 以只读 `UITextInput` 接入
  `UITextInteraction(.nonEditable)`，macOS 使用 responder action、`NSPasteboard` 与鼠标事件；平台层
  只持有选区状态，矩形始终来自 `LayoutResult`。语义选词复用简体中文 `NLTokenizer`，无法得到词时
  回退到核心的 interaction-unit 选择；tokenizer 不产生第二份字符几何。
- **原生 link 接入点**：Swift `AttributedString.link` lowering 为带目标的精确 source range。下划线与
  命中矩形只消费 `LayoutResult` 的 glyph/source 几何；SwiftUI 通过环境 `OpenURLAction` 导航，
  AppKit/UIKit 暴露 `onOpenURL` 并在未接管时调用平台 URL opener。点击和拖选分离，拖动不导航。
- **正文与注文 locale 分离**：原生 `.languageIdentifier` 描述基文 run；`RubyReading` 另带注文
  language，`.bopomofo(...)` 默认为 `zh-TW`。因此注音 fallback/`locl` 使用繁中语言证据，段落仍以
  `zh-Hans` 和 `MainlandHorizontal` 进入现有 pipeline。
- **命名 `coretext-render`(而非 `coretext`)**:与 `:shaping:coretext` 同 leaf 名会在共享 `group` 下产生同一 capability `org.tiqian:coretext`,触发 Gradle 重复能力解析,使依赖回指消费者自身、导致 `compileKotlinMacosArm64` **自环**。不同 leaf 名规避之。命名启发式:`PlatformFrontendDistinctCapability`。

## Consequences

- Apple 端到端管线可以完整运行:**文字 → 整形/度量 → 布局 → 分页 → 画到像素**。
- 渲染器绘制正文字形 + 拼音/注音行间注 + 着重号点 + 专名号/书名号/示亡号线(`drawRuby`/`drawBopomofo`/`drawEmphasisDots`/`drawDecorationSegments`);拼音与注音都按 run 自身字体重整形绘制,避免用新建字体回放回退字体的字形 id(否则错配成乱码);注音用 `vert` 竖排字形:ㄅㄆㄇ 是实际的竖排 run,其笔位取字身框顶端居中(核心记录的 `drawX`/`baselineY` 是给 Skia/Android/Web 的横排基线原点),调号/轻声按核心记录的原点与基线重放,普通声调共用注音字号、不再按 ink bounds 二次缩放。
- 逐 cluster 字体解析走引擎 `debug.fontDecisions` + 共享 `usesLatinFace` 规则；feature 从实际
  `GlyphRun` 回放。装饰继承 source color；书名号波形参数与 Compose 一致，专名号/书名号依据
  `LayoutResult` 已记录的 glyph ink bounds 做 skip-ink，不在 renderer 建立第二份布局真值。
- 代价(诚实记录):底层 `draw` 仍明确接受 **y-up 上下文**；AppKit/UIKit view 在调用边界统一
  处理宿主 y-down 坐标。Apple view 当前是支持 selection/copy 的只读正文，editor / IME 尚未实现。

## Alternatives considered

- **WebKit 渲染 EPUB。** 否决:非原生手感,且无法直接重放 `LayoutResult` 的字形/位置决策(WebKit 会用自己的排版,丢弃引擎决策)。
- **Compose Multiplatform on macOS。** 否决:非原生手感,且已有 Compose 前端([0017](0017-compose-desktop-renderer.md))。

## Verification

`:frontend:apple:coretext-render:macosArm64Test` 与 `iosSimulatorArm64Test`:

- **端到端**:`appleParagraphEngine().layout(中文)` 产出含 clusters / glyphRuns / lines、正尺寸的 `LayoutResult`,窄宽度下正确换行,`shapingDecisions` 的 source 为 `CoreText`。
- **渲染**:`CoreTextLayoutRenderer` 画到离屏 `CGBitmapContext` 后,位图含实际字形墨迹(断言非白像素数)。
- **rich text parity**：组合 source range 不重复文本，装饰继承 span color，行间线从已记录 glyph
  ink 生成避让区间；书名号保持波浪线而非退化为专名号直线，且中心线补偿波幅后不再贴字。
- **iOS view runtime**：在 iPhone simulator 上实例化公共 `CJKTextView`，断言长文产生
  可滚动 content size、Core Text 位图实际出墨、宽度变化降低文档高度且 accessibility value 始终
  保持原 source text；同时验证系统 non-editable text interaction、核心选区矩形、复制 source、
  surrogate 安全边界、原生简体中文分词、链接命中/回调与宽度重排后的选区保持。
- **macOS view runtime**：实例化公共 `CJKTextView`，验证全选/局部选择、核心选区矩形、
  responder menu validation、链接命中/回调、accessibility selection 与宽度重排后的 source offset 保持。
- **CLREQ 合规**(实际 Core Text 测量驱动):避头尾(无一行以行首禁则标点开头)、两端对齐(`justificationDecisions` 触发且非末行填满行宽)、中西文间距(`autoSpaceDecisions`)、标点挤压(标点带可压缩 glue)。
