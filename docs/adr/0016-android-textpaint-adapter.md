# ADR 0016: Android 平台 run 重放与受控 native 字体后端

- Status: Accepted
- Date: 2026-06-10
- Amendment 2026-06-25：实际应用 dogfood 暴露出 Android renderer 仍会在
  draw 阶段重新让平台理解文本，可能与 measure 阶段得到的 CJK glyph 形态
  不完全一致。renderer 不得根据 `PunctuationDecisionInfo` 做 dash 专用缩放；
  后续 slice 已让 Android backend 形状与绘制同源（shape once, draw the
  positioned glyphs）。前端不负责做标点几何修正。
- Amendment 2026-08-05：API 31 的 `TextRunShaper` / `Canvas.drawGlyphs` 不能继续作为
  Android 正确性的最低边界。Compose artifact、native backend 与验证 app 的 minSdk 改为 23；
  新增 HarfBuzz + FreeType 同源后端，API 31 adapter 只保留为经过几何对照的可选 oracle / 优化。
- Amendment 2026-08-05（二）：OEM 证据推翻了“可从 `SystemFonts` 枚举恢复系统默认 family”的
  假设。catalog 改为有序 family fallback、保留各可变参数的实际取值并带单调 revision；枚举路径明确降为
  approximate，Compose 以 revision 使 shaping、metrics 与 layout cache 一起失效。
- Amendment 2026-08-05（三）：API 31+ 默认路径对每个实际 shaping 请求调用平台
  `TextRunShaper`，读回具体 file / TTC index / variation axes，再由 native 后端重放该实例；
  API 23–30 则读取 `fonts.xml` 的有序声明并明确报告无法观察 Minikin 最终运行时选择。语言兼容
  必须保留 `lang="zh"` 的补充字库，例如 MiSans 主字库之后的 `MiSansL3.otf`。
- Amendment 2026-08-06：字体源与 face 实例分离。系统文件按内容身份只读 `mmap` 一次，宿主
  `ByteArray` / asset 只保留一份 direct buffer；TTC index 与 variation axes 只建立共享该源的
  FreeType / HarfBuzz face。native 统计分别报告活跃源数、源覆盖字节和 face 数，避免再用进程 RSS
  猜测是否因多个可变参数取值各复制了整份字体。
- Amendment 2026-08-06（二）：API 35+ 的 `PositionedGlyphs.getFakeItalic()` 是平台选择结果，
  不能作为 fatal capability issue。oracle 保留平台决定并把合成斜体写入 replay face identity；
  native outline 依 Android `TextPaint` 的 `textSkewX=-0.25` 规则绕基线斜切，ink bounds 使用同一
  变换。平台报告 `getFakeBold()` 时不猜 FreeType 加粗量，保留同一个 Android `Font` 与
  HarfBuzz glyph id，并用 `Canvas.drawGlyphs` + `Paint.fakeBoldText` 重放。是否合成仍由平台决定，
  提椠不按文字、字体或厂商自行触发。
- Amendment 2026-08-06（三）：`CjkPunctuation` 已是核心根据段落语境作出的字体角色决定。
  Android oracle 不得再用孤立的弯引号或破折号探测字体，否则同时覆盖这些码位的西文主字体会
  覆盖核心决定。`CjkPunctuationHanFaceAnchor` 使用与 `CjkText` 相同的汉字探针选定具体中文
  face，再由该 face 对原标点执行 HarfBuzz shaping；引号与破折号的字体归属因此不会取决于它们
  脱离上下文时的系统默认归属。
- Amendment 2026-08-12：首次 Maven 发布前按 [ADR 0048](0048-suite-maven-and-package-namespaces.md)
  把 Android native 后端明确命名为 `:shaping:android-native-font`、
  `org.tiqian:tiqian-shaping-android-native-font` 与
  `org.tiqian.shaping.android.nativefont`；只改变模块和公共包身份，不改变本 ADR 的后端接口。
- Amendment 2026-08-13：Compose Android 默认后端改为公开平台 run 接口，
  `frontend/compose` 不再传递依赖 `android-native-font`。API 31+ 仍从
  `TextRunShaper` 保留 glyph id、placement 与 `Font`，并用 `Canvas.drawGlyphs`
  重放；API 23–30 改由 `LegacyPlatformRunReplay` 使测量和绘制共用同一
  `TextPaint`、typeface、locale、OpenType feature 和上下文文本。旧系统没有
  逐 glyph 的字体读回 API，因此该路径不声称观察到 Minikin 的物理 face。
  native 模块仍保留为宿主显式选择的受控字体后端，不再是 Compose
  artifact 的默认体积与启动成本。
- Amendment 2026-08-27：华为 HarmonyOS 4.2（API 31）主题字体证据包证明
  `SystemAndroidFontProbe` 的固定文件锚定会绕过 OEM 用户主题字体：平台默认链对
  中西文都返回 `/data/skin/fonts/DroidSansChinese.ttf`，而硬编码的
  `NotoSansCJK-Regular.ttc` 在该机存在并抢走全部 CJK role，造成「西文吃到主题
  字体、中文永远 stock」。API 31+ 的 CJK 锚定改为 `PlatformDefaultHanFaceReadback`：
  按请求的 (weight, italic) 用样式化默认 typeface + `zh-Hans` locale shape 一个汉字，
  读回平台实际选中的 `Font`（可变字体按字重参数选定的实例随之保留，平台自身假粗体时读回
  常规实例、由外层 `Typeface.create` 补假粗体），经 `Typeface.CustomFallbackBuilder`
  （系统链在其他路径都不能用时作为最终手段）作为锚定面，结果按键缓存；固定文件路径降为读回失败时的最终手段与
  API 26–30 的既有路径。单次 400 探测曾把可变字体设备的全部字重锚死在常规实例上，
  中间字重静默落回 400、粗体只剩假粗体，故探测必须携带请求样式。标点归面与
  `LatinVsCjkFaceSelection` 的角色模型不变，改变的只是锚定证据来源。
- Amendment 2026-09-06：Android 共享 renderer（`platforms/android/rendering`，Compose 与 View 前端共用）
  新增宿主字形回放钩子 `HostGlyphReplay`
  （`org.tiqian.shaping.android.AndroidGlyphReplay` 与 `AndroidGlyphReplayRegistry`）。
  注册表可挂多个回放，按 render font key 的归属（`ownsFont`）选择；renderer 先查平台
  `AndroidPositionedGlyphFontRegistry`，查不到的 key 才问回放，答案按 key 缓存在段落 draw cache
  里。API 31+ 优先取回放给出的平台 `Font` 走 `Canvas.drawGlyphs`，该 `Font` 连同平台选它时的
  假粗与斜切一起交回（`AndroidReplayPlatformFont`），renderer 画前设进 paint；否则按
  `LayoutResult` 的 glyph id 与 placement 绘制 outline。API 23–30 的 `NaturalRunCoalescedDraw`
  计划把这类 cluster 记为独立的 outline 命令，不参与合并；连字符 glyph 走同一路径。
  `paint.textSkewX` 不为零时 renderer 以基线为轴对 canvas 做同样的斜切，回放报告 face 已是
  真斜体或已自行斜切（`providesItalic`）时不再加。native 后端在 `install()` 与默认目录
  装载时注册 `AndroidNativeGlyphReplay`，宿主不再自己绘制。此前 native shaping 产出的 glyph
  在 Compose 里会退回平台字符串绘制，测量与绘制不同源。
- Amendment 2026-09-06（二）：`AndroidFontFaceSpec.opticalSize` 声明 `OpticalSizeFollowsFontSize`：
  该 face 的 `opsz` 轴按每次请求取 `fontSize × pointsPerPixel`，夹在字体声明的轴范围内并量化到
  整数（`opsz` 是以磅计的设计尺寸，整数档之间看不出差别）。实例与声明 face 共享源、TTC index
  与其他轴，只多出一个 FreeType / HarfBuzz face，按整数值缓存在该 face 上；metrics、shaping 与
  outline 回放取同一实例，`FontFaceId` 带上实际 `opsz`；无覆盖退化的段不建实例。字体没有
  `opsz` 轴时报告 `OpticalSizeAxisUnavailable` 并沿用声明实例。像素到 opsz 的换算比例由宿主
  给出，后端不猜屏幕密度。
- Amendment 2026-09-06（三）：`AndroidFontSource.asset` 对未压缩存放的 asset 改为
  `UncompressedAssetRegionMapping`：按 `AssetFileDescriptor` 的偏移与长度只读 mmap APK 文件区间，
  不再复制进 direct buffer；压缩存放的 asset 仍走复制。宿主目录里没有任何 family 覆盖请求文本时，
  `NoCoveringFacePlatformDegrade` 沿用多 face 退化的同一条路：该段由平台文字栈用 renderer 字符串
  绘制所用的同一 typeface 测量并绘制（测量走 `platforms/android/shaping` 里与 renderer 共用的
  `platformRunAdvance`），链尾 family 只提供行高度量，decision 记录 `AndroidPaint` 来源、该
  reason 与 capability issue `NoCoveringFaceStringDraw`；此前这种情况直接抛
  `MissingControlledFontFace`，一个 emoji 就会让整段布局失败。未安装目录时的报错不变。
- Amendment 2026-09-07：平台路径补上宿主字体入口 `HostTypefaceResolver`。
  `AndroidTypefaceResolverRegistry` 持有一个进程内共用的 `AndroidTypefaceResolver`，默认仍是
  `SystemAndroidTypefaceResolver`；`createAndroidTextShaper`、`AndroidFontMetricsResolver`、两个平台
  shaper 的默认参数、共享 renderer
  `AndroidParagraphRenderer` 与 `AndroidParagraphMeasurer`（含 measurement session）的默认 typeface，以及
  native 后端的退化测量都从它取值，测量与绘制共用同一实例；显式传入的解析器仍优先。宿主用自带文件造 `Typeface`（含 `fontVariationSettings`）时在第一个 `CjkText`
  之前安装。它只解决「用什么字体」：API 29 以下拼不出自定义回退链、API 28 以下没有连续字重、
  平台不按字号设 `opsz`、API 31 以下没有逐 glyph 字体读回，这些仍是平台文字栈的边界，宿主受控
  字体的完整能力仍在 native 后端。
- Amendment 2026-09-08：`StyleMatchedFaceCoverage`。2026-08-05 修订写的「只有该 family 不覆盖
  文本时才进入下一 family」没有说明按哪张面判断，实现选了「family 内任一面覆盖即不换 family」，
  再在剩下的面里按样式就近挑。这隐含同一 family 各面字集相同的前提；这是系统字体打包的习惯，
  不是排版事实。中文正文的样式分派常跨字体（正文一款字体只有一个字重、斜体换楷体、粗体换另一
  款字体），CSS `@font-face` 也允许把不同来源的文件声明进同一 family。舒页把 U 明（正体 400 档）、
  FandolKai（斜体）与思源宋 wght 700（粗体）声明进同一正文 family，回退 family 是思源宋 wght 250；
  U 明没有「婳」时实现剔除 U 明后留在正文 family 内，常规正文被画成 700，回退 family 永远走不到。
  自此改为 CSS Fonts Level 4 §5.2 的次序：family 内先按斜体、再按字重挑出一张面（字重按该节
  规定的搜索方向，不再取绝对差最小：目标在 400 到 500 之间先向上到 500、再向下、再向上；小于
  400 先向下再向上；大于 500 先向上再向下），只检查这张面是否覆盖请求文本，不覆盖就换下一
  family，不考虑同 family 其他面；整条链都不覆盖时沿用 `NoCoveringFacePlatformDegrade`。样式缺失
  仍只合成、不换 family；`preferredFamilies` 筛选、`exactFamily` / `exactStyle` 与 capability issue
  不变。同 family 各面字集相同时结果与此前一致。否决的替代：维持覆盖优先并要求宿主声明伴随面
  （把实现前提转嫁给每个宿主）；照 Minikin 用 family 默认样式那张面的字集代表整个 family（缺字
  判断取决于哪张面算默认，与 CSS 不同）。
- Amendment 2026-09-08（二）：公开系统字体发现 `AndroidFontCatalog.system(context)`。宿主要提供
  「系统默认字体」时常只想让中文正文跟随系统，拉丁与标点仍用自带字体；此前系统目录的三条发现
  路径都是 internal，宿主只能在整套跟随系统与全部自带之间二选一。新入口按 `defaultCatalog` 的
  同一优先次序返回后端未安装宿主目录时会使用的那份目录，`faceSpecs` 带文件源、TTC index、字重、
  斜体与轴实例，`fallbackChains`、`sourceKind` 与 `declaredIssues` 原样携带；宿主可把这些 face
  spec 与自己的面合成新目录再 `install()`，目录构造时的链校验不变。只做发现，不改变默认路径，
  也不承诺系统主题运行中切换后自动刷新。记录但不在此决定的扩展：`TextStyle.fontFamilies` 从
  筛选链改为样式自带顺序（EPUB 每份文档自带 `font-family` 列表）；`WeightFollowsRequest` 按请求
  字重实例化可变字体，与 `OpticalSizeFollowsFontSize` 同构；样式缺失的显式策略（CSS 没有此项）。
- Amendment 2026-09-08（三）：`PlatformDefaultFamily`。宿主目录的 fallback 链里可以写保留名
  `AndroidFontCatalog.PLATFORM_DEFAULT_FAMILY`（`platform-default`），表示「这一位交给平台自己
  选字」，它不声明 face。API 31+ 在解析时走到这一位就按 2026-08-05（三）的平台读回逐请求问平台，
  平台面覆盖文本即选用，不覆盖则继续下一位；链尾仍是这一位时由平台文字栈退化绘制，读回的面只
  供度量。API 23 到 30 在安装时把这一位展开成 fonts.xml 声明目录里该角色的家族（key 加
  `platform-default:` 前缀，角色只保留宿主链委托的那些角色，系统目录的 capability issue 一并
  带入）。宿主由此可以只自带拉丁或标点字体、中文正文跟随系统，而不必在「整套跟随系统」与
  「全部自带」之间二选一；(二) 的 `system(context)` 保留为发现入口。
- Amendment 2026-09-08（四）：`FakeBoldWhenNoBoldFace` 与 `StrokeSyntheticBold`。宿主目录里按样式
  挑出的面字重比请求低 200 以上、且请求不低于 600 时（Minikin 的假粗体条件），该面以
  `:syntheticBold=stroke` 后缀的 `FontFaceId` 登记为合成粗体面，度量与 shaping 仍用同一
  FreeType / HarfBuzz face，advance 不变；回放时 outline 以 fill 加 stroke 绘制，stroke 宽度取
  Skia 假粗体的比例（9 px 处 1/24 em，36 px 处 1/32 em，之间线性）。decision reason 追加
  `FakeBoldWhenNoBoldFace`。skip-ink 与 ink bounds 用未描边的 outline，偏差在 stroke 半宽以内。
  平台读回的合成粗体（API 31+ `Font` 加 `fakeBoldText`）不变。

## 2026-08-05 决策修订：API 23 native correctness backend

Android API 23+ 的默认正确性路径改为 `shaping/android-native-font`：

- `shaping/api` 定义平台无关的 `FontFaceId`、`ReplayableFontCatalog`、face request / descriptor
  与结构化 `FontBackendCapabilityReport`。`FontFaceId` 由字体字节 SHA-256、TTC index 与可变字体各参数的取值
  稳定导出，
  已产生 `LayoutResult` 的 face 在进程内继续保留，catalog 更新不会让旧布局失去重放资源。
- 宿主通过 `AndroidFontSource.bytes/file/asset` 与 `AndroidFontFaceSpec` 明确声明 family key / alias、
  字重、斜体、各可变参数的有效取值和 fallback role；`AndroidFontCatalog.fallbackChains` 按 role 给出有序
  family 链，regular / bold / italic 在同一 family 内先做样式匹配，只有该 family 不覆盖文本时
  才进入下一 family。HarfBuzz 从这份字节产生 cluster、glyph id、advance、placement、
  `locl` 与调用方要求的 feature；FreeType 从同一 face 取得 raw metrics、ink bounds 和 outline。
  renderer 只按 `LayoutResult` 的 glyph id / origin 重放 outline，不重新断行、重新 shaping 或猜偏移。
- API 31+ 默认路径以 `AndroidPlatformTextRunOracleApi31` 让平台 shape 当前 selection text，读回
  实际 `Font` 的 file / TTC index / variation axes，再把同一实例交给 HarfBuzz / FreeType；结果按
  完整 face request 与实例缓存。它沿用 Android 自己的 OEM、用户主题和 fallback 选择，不从
  文件名反推 family。
- API 23–30 没有逐 glyph font 读回，默认读取单一可读 `fonts.xml` 根文件的声明顺序：具名
  `sans-serif`、与简中兼容的语言 family、其后的中立 fallback 分别进入有序链。`zh-Hans` 请求
  接受 `zh` / `zh-CN` / `zh-SG` / `und-Hani`，因此小米声明为 `lang="zh"` 的 `MiSansL3.otf`
  会保留在主 MiSans 之后；显式 `zh-Hant` 不混入简中链。该路径报告
  `RuntimeFontSelectionUnobservableBelowApi31`；发现多个可读配置根时再报告
  `UnmergedFontConfigOverlays`，不假装复现私有 overlay merge。
- API 29+ 的公开 `SystemFonts` 只在上述声明目录不可用时构造
  `ApproximateAndroidPublicSystemFontsApi29` 诊断目录，并报告 `ApproximateSystemFontSelection`；
  排在更后面的已知系统路径同样具名报告能力缺失项。宿主仍可在第一次 `CjkText` 前安装受控 catalog，
  以覆盖无法从旧系统公开 API 观察的主题或合成字形行为。所有路径都不调用 Android 私有 Minikin API，
  也不静默用另一字体测量或绘制。
- `SystemFonts` 会把同一个可变字体文件和 TTC face 暴露成多组可变参数坐标。catalog 必须按
  `file / source + TTC index + variation axes` 区分实例，并把坐标交给 FreeType 后再建立
  HarfBuzz face；不能按文件合并，也不能把枚举实例改写成猜测的 400 / 700。平台 font override
  在进入 catalog 时必须 lower 成 `AndroidFontFaceSpec.variationAxes` 的有效坐标；无法保真的
  fake style 必须形成 capability issue。approximate 枚举路径只保留 API 实际报告的坐标。这里的
  “实例不可合并”只指 face 状态和稳定身份；底层字体文件必须按 SHA-256 内容身份共享，不能让
  每个可变参数取值各自持有一份完整字节。
- 每次 `TiqianAndroidFontBackend.install()` 产生新的单调 catalog revision，并通知 Compose 重建
  `ParagraphMeasurer`；这同时丢弃旧环境的 shaping、metrics 与段落 cache。已产出的
  `LayoutResult` 仍凭稳定 `FontFaceId` 使用被进程保留的旧 face 重放，两种生命周期不得混为一谈。
- outline replay 将“有效但无 contour”（例如空格）视为成功的无墨迹 glyph；已注册 face 的 glyph
  若不是可重放 outline，则以 `NativeGlyphReplayUnavailable` 明确失败。它不能落到
  `drawTextRun` / `getTextPath`，因为这会破坏测量与绘制同源。
- `frontend/compose` 对外仍只有同一套 `CjkText` / `CjkSelectionContainer`。capability report
  是宿主修复字体输入的诊断，不作为 renderer 路由；API 23–30 不切回 Compose `BasicText` 或旧正文
  renderer。标点 glue、避头尾、断行、justification、rich text、selection、链接命中与语义仍只消费
  `LayoutResult`。
- API 31 `AndroidPaintTextShaper` / `Canvas.drawGlyphs` 保留为同字体几何对照和潜在优化路径，
  不是正确性依赖。其 API 31 类型用版本边界隔离，库本身 minSdk 为 23。

native bridge 目前留在提椠内，但公共边界只依赖 replayable font catalog / face contract；与
`math-compose` 共用的字体加载、shaping、outline 与 cache 待双方桥接稳定后移入共享层，不复制数学布局规则。

## 2026-08-13 决策修订：Compose 默认使用公开平台 run replay

实际 Lite 应用验证表明，把 HarfBuzz / FreeType 与系统字体 catalog 全部传递进
Compose artifact，会把 native ABI 体积、旧设备初始化与字体扫描成本无条件地
交给每个宿主。对于“跟随 Android 当前字体选择”的普通 Compose 正文，
平台本身已经拥有 Minikin 的完整 fallback 与 OEM 策略；提椠需要保住的是测量和
绘制接口同源。运行时不应再复制一遍平台字体系统。

- API 31+ 使用 `AndroidPaintTextShaper`：从 `PositionedGlyphs` 读回 glyph id、
  placement 和每段 `Font`，renderer 按 `LayoutResult` 保留的位置以
  `Canvas.drawGlyphs` 重放。
- API 23–30 使用 `AndroidLegacyTextShaper`。这些版本只公开了上下文
  advance、path 和 `drawTextRun`，没有读回逐 glyph 字体的 API。
  `LegacyPlatformRunReplay` 因此把每个 layout cluster 定义为平台 run：同一
  display text、typeface、locale、OpenType feature 与 Han context 同时进入
  `getRunAdvance` / `getTextPath` 和 `drawTextRun`。其结构化 decision 明确记录
  `LegacyPlatformRunReplay:api23-30`，不伪造 glyph id 或物理 face 身份。
- Han context 只用于 CJK 角色中没有强脚本的共用符号和标点。汉字、
  假名、拉丁字母和数字不再放入合成的 `中…中` 缓冲，避免为不需要
  script 锚点的内容增加测量与绘制差异。该判定由
  `requiresHanShapingContext` 公开共享，数学公式中的宿主文字也使用同一
  接口。
- `shaping/android-native-font` 仍提供精确字体字节、HarfBuzz / FreeType 与
  outline replay，适合宿主明确选择的受控字体环境。它不再由
  `frontend/compose` 自动安装，也不作为跟随系统字体时的默认 fallback。

这次修订取代本 ADR 中“API 23+ native backend 是 Compose 默认正确性边界”
的结论；2026-08-05 的受控字体后端规格与验证证据仍保留，但不再描述
Compose 默认依赖图。

### API 23+ 验证证据

此前构建在 Android emulator 上通过 native instrumentation：API 23、27、30 各 4/4；API 31 与
当时 API 37 各通过 native 4/4 和 platform adapter 16/16。API 31+ 对照测试从同一字体字节比较
glyph id、advance、ink 数量、layout line range 与 visual width。API 23 / 27 / 30 / 31 共享 Demo
均能启动并生成正文截图，覆盖中西混排、破折号/省略号、标点压缩与双齐、装饰线、ruby / 注音、
富文本和链接/选择入口。

有序 family fallback、catalog revision、平台 oracle 与旧系统声明目录完成后，当前工作树在两台
物理设备上各通过 native instrumentation 8/8：小米 Mi 10s（Android 13 / API 33）命中
`AndroidPlatformTextRunOracleApi31`，普通汉字由 `MiSansVF` 实例承担，Ext-B 生僻字由
`MiSansL3.otf` 承担；Galaxy S8+（Android 9 / API 28）命中
`DeclaredAndroidFontConfigApi23To30`，保留 `SECCJK-Regular.ttc#2` 及其后续声明 fallback。

同一 5040 字 debug 真机探针在 Mi 10s 约 1.29 s、Galaxy S8+ 约 4.43 s，均通过 20 s 要求。
此前 Galaxy 的约 85 s 来自 layout 内两处按字体决策反复扫描全文、复杂度按全文长度平方增长的 range join；改为按
source range 单调遍历后，layout golden 未变化。数字只证明当前 debug 真机要求，不等同 release
整机性能或内存结论。

共享字体源改造后，Mi 10s 上普通正文命中 `MiSansVF.ttf wght=310`，粗体命中同一文件的
`wght=360`：native face 数由 2 增至 3，而 source 仍为 2 份、覆盖 39,475,708 字节。该统计证明
新增的可变参数取值没有再映射或复制一份 MiSansVF；它不是 RSS，也不代替后续 release 整机内存验收。

## Context

Slice 6 的平台收尾：AWT（ADR 0013）与 Skiko（ADR 0015）已交叉验证了标点几何，
还差 Android 平台真值。Android 的文本栈（Minikin/HarfBuzz）不暴露 script 控制，
且 typeface 永远带不可关闭的内部 fallback 链，contract 上「单一字体测量」在
Android 只能近似为「该 locale 下的平台文本栈测量」。

## Decision

历史上的第一阶段新增 `shaping/android-adapter`（当时 minSdk 31）：

- `AndroidPaintTextShaper`：advance 来自 `Paint.getRunAdvance`，per-glyph
  id/位置/Font 来自 `TextRunShaper.shapeTextRun`（API 31+），ink bounds 来自
  `Paint.getTextBounds`（仅单 glyph cluster）。`Glyph.x/y` 保留 glyph origin，
  `Glyph.renderFontKey` 通过有界的 Android 专用 registry 指回 shaping 阶段的
  `Font`；旧 key 淘汰后 renderer 回到同一上下文字符串绘制路径，避免整个进程共用的
  registry 无限持有平台字体对象。
- `LocaleTaggedShaping`：`Paint.textLocale` 取 `TextStyle.locale`。
- `FontHaltMeasurement`：第二次测量用 `fontFeatureSettings = "'halt' on"`，
  产出 `Glyph.haltAdvance` / `haltPlacementX`，feature 不进渲染几何。
- `SystemAndroidFontProbe`：CJK role 显式解析 CJK typeface
  （`NotoSansCJK-Regular.ttc` 取 **ttcIndex 2** = SC face，与 AOSP fonts.xml
  对 zh-Hans 的映射一致）。不显式指定时 Roboto 在 fallback 链首位，会接管
  `—` `…` 等共用码点。

### HanContextShaping（历史起点，已由 2026-08-13 amendment 缩小适用范围）

孤立的 `—` 是 script-COMMON 码点，HarfBuzz 对单字符 buffer 解析为 OpenType
DFLT script，而 Noto Sans CJK 的 `locl` 规则注册在 hani/latn/cyrl/… 下
**唯独不含 DFLT**，上下文无关的逐 cluster shaping 会静默拿到西文形破折号
（0.89em）。桌面 adapter 用 `TrivialScriptRunIterator` 强制 `Hani` 解决；
Android 没有公开的 script 控制，且 `getRunAdvance`/`shapeTextRun` 的
context 参数不参与 HB 的 script 推断（buffer 只含 run 本身）。

第一阶段因此把 CJK role 的 cluster 统一放进 `中<cluster>中` buffer 整体 shaping，再按
offset 切回该 cluster 的 glyph 与 advance（pen 原点用 `getRunAdvance` 差分，
不用 glyph x。`halt` 的 placement 位移正是要单独上报的量）。这正是实际
Android 段落里 Minikin 给这些字符的环境。这不是 hack。glyph↔字符无法 1:1
对应时（连字）回退到上下文无关 shaping。

### 平台限制（已记录，golden 需容忍）

- `Paint.getTextBounds` 无 context 参数：`locl` 替换后的破折号 ink bounds
  量到的是替换前的 glyph，仅诊断用途受影响。
- typeface fallback 链不可关闭：缺字时由系统在其他路径都不能用时作为最终手段而非报 .notdef，
  `missingGlyphs` 改用 `Paint.hasGlyph` 上报。
- 多 glyph cluster 不报 per-glyph ink bounds（走 `MissingInkBoundsFallback`）。

### 设备实测（emulator API 37, Noto Sans CJK 2.004）

instrumentation 测试（`connectedAndroidTest`）复现桌面双引擎的全部不变量：
全宽标点 1em；`halt` body 0.5em 且 placement 方向正确（`。`→0、`（`→-8）；
`locl` 破折号整 em；ink 落在 profile glue 侧的对侧；缺字上报。

实际应用 dogfood 暴露出一类 renderer 层错位：Android measure 与 draw
路径虽然都试图提供 Han context，但 draw 阶段仍以 `Canvas.drawTextRun`
重新 shaping 文本，不重放 measure 阶段已经得到的 glyph id/position。
这类问题已经收敛到 Android backend 的同源 shaping/drawing 能力：API 31+
renderer 优先用 `Canvas.drawGlyphs` 按 `LayoutResult.glyphRuns` 里的 glyph
id、origin、Font 绘制；只有缺少平台 Font key 时，才退回同一 renderer 内的
字符串绘制 containment（例如 registry 中过旧的 Font key 已被淘汰）。
`AndroidLayoutRenderer` 不再按标点类型做几何变形。

## Consequences

- 标点几何的「三平台互证」完成：AWT、Skia、Android 在同一个 family 上给出
  一致的 body/glue/方向结论。
- Android 的测量与主文本绘制在 API 31+ 上同源：layout 消费的 glyph id /
  origin / Font 被 renderer 直接重放，避免 draw 阶段再次让平台重新理解文本。
- Android 真机/模拟器是唯一需要外部环境的测试路径，不进默认 `build`；
  按需跑 `:shaping:android-adapter:connectedAndroidTest`。
- `local.properties`（sdk.dir）为本机配置，不入库。
- 当前 Android Compose artifact 的最低版本为 API 23。默认路径按 2026-08-13
  amendment 使用公开平台 run replay；native backend 是宿主可显式选择的受控字体能力。

## Alternatives considered

- **接受西文形破折号作为平台差异。** 否决：实际 Android 渲染在 Han 段落里
  就是中文形，上下文无关测量的西文形是测量方法造成的差异，不等于平台真值。
- **Typeface.CustomFallbackBuilder 构造带语言属性的字体链。** 否决：构造出的
  字体仍不携带 fonts.xml 的 lang 属性，无法影响 HB 的 script/language 解析。

## Amendment (2026-08-05)：枚举不是渲染真值，平台读回才是

API 29+ 的 catalog 由 `SystemFonts.getAvailableFonts()` 构建，而该 API 返回的是**无序集合，
不带具名 family 归属，也不带 fallback 次序**（`selectGenericSans` 的注释已经记过这一点）。因此
`cjkScore` 只能按 `localeList` 加文件名打分猜哪一个是 CJK 正文字体。

这个猜测在 OEM 设备上会与平台实际解析分叉。典型形态：厂商把自家字体加进具名 `sans-serif`
（西文位），而 `lang="zh-Hans"` 的 fallback 链仍指向 Noto，平台按链渲染，我们按「谁看起来
最像 CJK」打分，两边选出不同的 face，且分叉是静默的。解析 `/system/etc/fonts.xml` 能改善
候选枚举与次序（它带 `lang` 标签，API 21+ 即为该格式，world-readable），但它同样只是**声明**：
厂商主题引擎与运行时换字体不在那份 XML 里。

因此定为：**只有让平台自己 shape 一遍、再读回 `PositionedGlyphs.getFont(i).file`，才算渲染
真值。** `AndroidPositionedGlyphFontRegistry` 已经持有这些 `Font` 对象（当前仅用作 drawGlyphs
的不透明 key），证据一直在，只是没有被读。

原先的 `platformResolvedFacesMatchTheFacesWeSelect` 只在 AOSP API 37 上得到一致，不能把 AOSP
巧合提升成默认目录规则。2026-08-05 的 8 份逐 glyph OEM 样本已经观测到枚举 heuristic 与平台
默认 face 与各可变参数取值的系统性分叉，详见
[`2026-08-05-compose-font-selection-audit.md`](../research/android-font-reports/2026-08-05-compose-font-selection-audit.md)。
该断言已删除，枚举目录改为自报 approximate；API 31+ 默认路径现在直接消费当前请求的平台读回，
不继续修文件名评分。

范围与未决：

- 该取证要求 API 31（逐 glyph 的 `getFont`）。**API 23–30 没有逐 glyph 的 font 读回**，
  只能使用有序 `fonts.xml` 声明或宿主 catalog，并报告运行时选择不可观察；不得声称与平台同源。
- 探针不能复用 glyph 的 `renderFontKey`：Han context 下它按 `NoGlyphReplayInHanContext`
  有意置 null，那是 glyph id 不可重放，不表示字体身份不可用。
- Android 主题或字体设置改变后，平台没有向第三方排版引擎公开整套字体图修订通知；当前 request
  cache 以进程内 catalog revision 为边界。宿主主动安装 catalog 会正确失效，运行中系统主题切换的
  自动侦测仍需单独接口。
