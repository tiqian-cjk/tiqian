# 提椠当前架构

本文说明提椠当前的 pipeline、模块边界与平台接入方式。正在推进的工作见
[roadmap](roadmap.md)，具体取舍及其演变见 [ADR 索引](adr/README.md)。

## 范围

提椠是面向中文正文的 CJK 段落布局引擎，目前完成的是简体中文横排。它在平台字体能力或
受控字体字节后端之上统一处理：

- 字体角色与 fallback；
- 中文字体度量与混排 baseline；
- 标点 body、墨迹与可调整空间；
- 断行、避头尾与行尾修复；
- 行内挤压、拉伸、邻行均摊与两端对齐；
- 段首缩进、列表、富文本、行间线、拼音与注音；
- 源文本范围、复制与搜索保真，以及宿主无障碍语义的保留。

竖排、JLREQ、KLREQ、分页、多栏、编辑器与完整 CSS Text 兼容不属于当前实现范围。

## Pipeline

```text
宿主文本 / AnnotatedString / DOM
  -> 前端 lowering（保留 source range 与宿主语义）
  -> TiqianTextContent + style + annotations + inline geometry
  -> 字体角色与 fallback
  -> 平台或 replayable-font shaping adapter
  -> 字体度量归一化
  -> 标点 atom / glue / inline geometry ledger
  -> break candidates + mandatory breaks + unbreakable ranges
  -> line breaking + kinsoku repair
  -> compression / justification / neighbor adjustment
  -> LayoutResult + structured debug decisions
  -> Compose / DOM / Android / Core Text renderer
```

`ExplainableStubParagraphLayoutEngine` 保留了早期名称，但当前实现已经走完整真实 pipeline。
stub 只作为没有平台字体系统时的确定性测试 adapter 存在，不是默认布局模型。

## 输入与输出

布局核心消费平台无关的输入：

- `TiqianTextContent` 保存 source text、样式 span，以及由宿主语义投影的具名断行策略 span；
- `TextStyle` 与 `ParagraphStyle` 保存样式和段落策略，`LayoutProfileId` 选择由
  profile resolver 提供的中文排版规则；
- `DecorationSpan`、`RubySpan`（含 Bopomofo kind）、`InlineBoxSpan`、`InlineObjectSpan`
  等结构表达行内语义和宿主几何；独立 `InlineBoxSpan` 的 Narrow 外边界统一进入
  autospace，不由 inline code、链接等角色分别补 margin；
- `LayoutConstraints` 提供版心宽高与行数限制。

输出 `LayoutResult` 包含：

- source range 连续可追踪的 `Cluster`；
- 可由平台前端重放的 `GlyphRun` 与 glyph placement；
- `LineBox`、最终 advance、visual width、缩进与 baseline；
- 行间注、装饰、富文本和 inline object 的几何；
- 字体选择、标点空间、断行候选、修复方案、行调整与降级原因等结构化 decision。

前端只能消费这些结果，不得另建一套断行或标点规则。

中西自动间距不复用字体角色。`core` 固定 Unicode Proposed Draft UTR #59
`East_Asian_Spacing` 的官方数据修订，按 source grapheme 边界把 shaping cluster 的首尾解析为
Wide / Narrow / Other（Conditional 在中文语言上下文解析为 Narrow）；`layout` 只在 W↔N
边界应用 profile 的 gap、换行成本与拉伸账目。字体 fallback、shaping face 与间距分类因此不会因
Greek、Cyrillic 等非 Latin 字母互相绑死。该 UTR 仍是 work in progress，升级数据必须显式更新
修订、校验和、fixture 与 golden，不能静默跟随网络最新版。

断行也不复用字体角色充当规则真值。`linebreak` 固定 Unicode 17.0.0 `LineBreak.txt` 中布局实际
消费的标点类别；`layout` 的 `Uax14WesternPunctuationBoundary` 为非 CJK 开闭符号、点号与已解析
引号提供 UAX #14 基础 no-break 边界，CLREQ profile 再对 `CjkPunctuation` 做 None / Basic / GB /
Strict tailoring。当前只承诺 ADR 0026 amendment 列出的标点子集、mandatory break 与 U+200B，
不把 `SimpleCharacterLineBreakAnalyzer` 冒充完整 Unicode Line Breaking Algorithm。

Compose 的 `CjkInlineObject` 是 `InlineObjectSpan` 的呈现边界：宿主先提供对象的 advance、
ascent 与 descent，核心据此断行并形成真实行盒，Compose 前端再把 composable 放到
`LayoutResult` 的最终 baseline 上。`PlaceholderVerticalAlign` 不参与这条路径，也不能成为
公式或其他基线敏感对象的布局真值。对象边界默认固定。提供方可以报告边界的实测自然空白
和绝对目标宽度，开放有上限的优先拉伸；公式把三类空白都先补到 0.5em，依次处理标点后、
关系符两侧、二元运算符两侧，再与已开放的词距、
中西间距和普通字间距一起参加最终统一拉伸。这个公式次序是对象提供方仿照 CLREQ 分档模型
给出的具名策略，不是前端猜测的视觉偏移，也不是 CLREQ 对数学公式的直接规定。

边界是否参加调宽与是否允许断行相互独立：只为移动后续公式片段而暴露的边界必须明确关闭
断行，公式原本的主基线断点才交给 line breaker。断点命中时，运算符留在上一行，但它后侧
实测数学空白作为 `InlineObjectLineEndDiscardableGlue` 丢弃；不断行时仍保留该自然空白，下一片段
本身不携带前导空白，因此两侧行端都不会出现空洞。提供方也可以开放对象宽度内已经量出的尾部
空白作为第八档压缩资源。压缩不会改变对象字形，且发生在七档正文挤压之后。避头尾仍由核心
决定：紧跟行内对象的中文禁则符号和 ASCII 点号把对象视为可见前项，不得留在下一行开头。
若 Markdown 在公式与该点号之间保留了源码空格，核心只把空格的布局宽度折叠为零，复制、搜索
与无障碍仍保留原文；避头尾跨过这段零宽分隔应用，并关闭公式到点号之间的全部拉伸边界。

行内对象的 ascent / descent 是相对正文 baseline 的可见边界，不是要求对象必须塞进本行各自的
上下半 leading。`InlineObjectInterlineCollision` 先让对象使用相邻两行基文字面之间已有的行间空间，
但必须保留 `ParagraphStyle.inlineObjectMinimumClearanceEm` 指定的可见内容净空（默认 0.1em，可显式
关闭）。能够容纳时只在安全范围内移动两行 `LineBox` 的共享边界，baseline 距离不变。只有“前一行
下伸 + 后一行上伸 + 最小净空”超过既有行间空间时，才把实际不足加入两条 baseline 之间；段首上溢
和段末下溢只扩充段落外边界。该决策进入 `InlineObjectLineHeightDecisionInfo` 与 layout dump。

## 字体与 shaping

`font` 先根据文字角色、locale、宿主字体偏好与标点策略决定候选字体。
`shaping/api` 的平台实现随后只负责把已确定的 source/display text 与字体请求变成
cluster、glyph、advance 和 ink bounds。可重放后端还用稳定 `FontFaceId` 把这些几何绑定到
同一份字体字节，供 renderer 取回 outline；`LayoutResult` 仍是唯一几何真值。

当前平台实现包括：

- `shaping/jvm`：AWT 字体与 glyph vector；
- `shaping/skia`：Skia / Skiko，供 Compose Desktop 与 JVM 渲染；
- `shaping/android-native-font`：宿主可显式选择的 Android API 23+ HarfBuzz / FreeType
  受控字体后端，从同一字体字节完成
  shaping、metrics、ink 与 outline replay；文件字体按内容身份只读映射一次，`ByteArray` / asset
  转为一份共享 direct buffer，TTC index 与可变轴组合只创建轻量 face 实例，不复制整份字体。
  字体身份包含源内容、TTC index 与有效轴坐标；每个 role 使用有序 family fallback，组内先匹配
  regular / bold / italic。catalog revision 变化会让 Compose 同时重建 shaping、metrics 和 layout
  cache，旧 face 只为旧 `LayoutResult` 保留；
- `shaping/android-adapter`：Compose 默认的 Android 公开平台后端。API 31+ 保留
  `TextRunShaper` 返回的 glyph id、placement 与 `Font`；API 23–30 以
  `LegacyPlatformRunReplay` 保证测量与 `drawTextRun` 共用同一 run 契约；
- `shaping/web-adapter`：浏览器离屏 Canvas 度量，并按需要使用可验证字体证据；
- `shaping/coretext`：Apple Core Text shaping、系统字体度量与 glyph ink。语言和显式 OpenType
  feature 进入同一条 `CTLine` 测绘路径；无法施加的 feature 以具名 capability issue 降级，不能
  只把请求原样写进 `GlyphRun`。

平台 adapter 不决定 CLREQ 码点替换、标点宽度、避头尾或两端对齐。它无法提供某项证据时，
必须输出具名降级原因，而不是在 renderer 中猜补偿值。
标点压缩的目标宽度属于 CLREQ policy，但左右削边来自 adapter 提供的逐 glyph `halt`
placement 或 ink bounds：layout 选择能保留原墨迹及框内安全边距的左、居中或右拟合框；
只有缺少字体几何时才使用具名 profile fallback。renderer 不再为标点另行移动 glyph。
中文上下文弯引号会先请求字体 `fwid`；若字体仍给出比例宽 glyph，layout 只把完整比例 glyph
box 放到语义正确的全宽字身一侧，再从该全宽字身计算压缩，不在比例盒内部重排墨迹。
弯引号的中文 / 西文 role 由结构化上下文解析：配对阶段只建立嵌套关系，role 阶段汇总同一外层
左右两侧与完整引文的强脚本文本，混合或无文字证据时服从 `TextStyle.locale`。相邻引文内容不会
泄漏为下一对的外层上下文，renderer 也不重新猜测 role。强文本证据固定使用 Unicode 17.0.0
`Scripts.txt` 的 Script 数据；Common、Inherited 与未分配码点不提供语言证据，也不依赖
Android、JVM 或 JS 自带的 Unicode 表。

## 排版核心

`layout` 把 shaping 结果与中文排版规则组合成最终段落：

1. `ScriptAwareFontMetricsNormalizer` 把平台 raw metrics 转成用于 CJK 与 Latin 混排的
   layout metrics。
2. `PunctuationAtom` 把标点表达为 `ink/body + leadingGlue + trailingGlue`，避免把所有
   标点先假定成 1em 再散落减法补丁。
3. `linebreak` 提供固定 Unicode 数据、已实现的 UAX #14 标点子集、强制换行、西文按词断行与
   连字符断词候选。
4. line breaker 按 `ClreqProfile` 选择断点，并通过 PushIn、Hang、CarryPrevious、
   CarryNext 等具名 repair 处理行首行尾禁则。
5. 行调整在合法断行基础上分配可压缩和可拉伸空间，非末行以中文正文两端对齐为基线。
6. annotation、decoration、inline object 与 rich text geometry 在同一份最终行几何上解析。

每一步都把原因写入 `LayoutResult.debug` 和 layout dump。视觉结果与 decision 不一致时，
应修正 pipeline 或平台证据，不能只在前端移动 glyph。

## 前端

### Compose

`frontend/compose` 是不依赖 Material 的基础前端，提供两类入口：

- 接受 `String` 或 `AnnotatedString` 的 `CjkText` 用于低成本替换 Compose `Text`；
- `CjkText(blocks = ...)` 用于显式的段落、节与列表结构。

`frontend/compose-material3` 是可选的宿主上下文适配层。它以
`org.tiqian.compose.material3.CjkText` 暴露同形的单段入口，读取 Material 3 的
`LocalTextStyle` 与 `LocalContentColor` 后转交基础前端。它不复制 TextStyle lowering、布局、
字体 fallback 或绘制逻辑；未采用 Material 3 的宿主继续直接使用 `frontend/compose`。

Compose 前端把 `AnnotatedString` 与 `TextStyle` lowering 成核心输入，并用
`cjkTextCompatibility()` 报告当前无法完整保真的能力。Skia 与 Android renderer 重放
`LayoutResult` 的 glyph 和 annotation geometry，不自行重新排版。
Android API 23+ 默认使用公开平台 run 契约。API 31+ 让平台 shape 当前请求，
保留逐 glyph 位置和具体 `Font`，renderer 以 `Canvas.drawGlyphs` 重放；API 23–30
无法读回物理 face，因此把每个 cluster 作为 `LegacyPlatformRunReplay`，由同一
`TextPaint`、typeface、locale、OpenType feature 与上下文文本完成测量和
`drawTextRun`。该路径跟随 Android 当前的 OEM 字体与 fallback 选择，不伪造平台
未公开的 glyph 级身份。`shaping/android-native-font` 仍可由宿主单独依赖，
为明确字体字节提供受控的 HarfBuzz / FreeType 与 outline replay，但不再传递进
Compose artifact。capability report 不会把正文路由回 Compose Text。
可选的
`CjkSelectionContainer` 把同一份 `LayoutResult` 的 UTF-16 source range、cluster box 与 caret
位置接到鼠标/触摸选择、选区绘制、复制和 selection semantics；短正文跨多个 `CjkText` 的选择
按实际几何顺序组合 source `AnnotatedString`。虚拟正文则提供 `CjkSelectionDocument`：锚点使用
稳定片段 key 与 UTF-16 offset，屏外节点只缺少可见几何而不会丢失选区；全选和复制读取逻辑文档，
不会为此组合或测量全文。Compose Foundation 当前没有面向第三方布局结果的
公开 `Selectable` 适配接口，因此前端用隔离、随版本编译验证的兼容层复用 Foundation 自己的
平台手柄、手势状态机、文本上下文菜单与 Android 文本放大镜；Android 使用系统 `ActionMode`
provider（含宿主菜单扩展和 `PROCESS_TEXT`），Desktop 使用当前 `LocalTextContextMenu` 右键契约。
Compose Android artifact 同时合并 `ACTION_PROCESS_TEXT` / `text/plain` 的 `<queries>` 声明，避免
Android 11+ 包可见性规则把其他应用注册的处理文本动作静默裁掉。
兼容层只把坐标和 selection adjustment 翻译到 `LayoutResult` 查询，不引入第二份
`TextLayoutResult`。同一布局的 positioned cluster、按行查询与
glyph/source lookup 由不可变 replay index 复用；容器缓存节点几何顺序与每节点 range，只有跨过新的
source boundary 才让受影响节点重绘。连续滚动宿主把同一个 `ScrollState` 同时交给容器与
`verticalScroll`；拖动越过 touch slop 后进入视口边缘才启动自动滚动，并在内容移动时用 Tiqian
几何刷新 endpoint；同一位置通知让系统菜单锚点和非拖动手柄跟随祖先裁剪后的可见视口，长按不动
不会自行扩选。source `AnnotatedString`（含 link/URL/TTS annotation）
原样进入 Compose semantics，非空选区再暴露 set-selection/copy action。Compose Android 只有拿到
真实 `TextLayoutResult` 才会提供逐字符屏幕框与行/页遍历，前端不为此伪造第二份排版；编辑器、IME、
TalkBack character-location 能力不属于当前静态正文路径。

### Web

`frontend/web` 发布 ESM 包 `@tiqian/prose` 与 light-DOM `<tiqian-prose>`。服务器输出的
HTML 先保持可读，Kotlin/JS runtime 与字体就绪后按 viewport 距离逐段原子增强。原 `<p>`、链接、代码、强调、自定义
inline 与 CSS 仍由宿主持有；引擎只写入断行和 spacing geometry。

同仓库的 `frontend/web/integrations/sveltekit` 与 `frontend/web/integrations/astro` 分别发布
`@tiqian/sveltekit` 和 `@tiqian/astro`。它们只把框架的 SSR、静态构建、head 资产与客户端导航生命周期
接到 `@tiqian/prose`，不拥有另一份 HTML 投影或排版规则。最低配置的组件输出 semantic SSR，浏览器按
实时 content width 增强；构建字体证据不要求宽度，只有显式 fixed-measure snapshot 需要
`maxWidthPx`。完整边界见 [ADR 0042](adr/0042-framework-web-integrations.md)。

Web 列表保留原生 marker 与语义，只把列表正文交给 Tiqian 排版。不支持或无法稳定测量的段落原子
回退为原生 DOM；无 JavaScript、异步加载失败、复制、Pagefind 和客户端路由都以原始语义 HTML
为基础。详细边界见 [ADR 0039](adr/0039-web-rendering-path.md)。

构建期 precompute 由 `frontend/web-precompute/rust` 的 Rust 编排承担：从站点明确发布的字体文件建立
HarfBuzz session，并调用同一个 `layout` 生成宽度无关的字体回放证据，以及可选的最大版心预排结果。
引擎的 Kotlin/JS 出口在 `ffi/js` 编译，服务浏览器 exact-font 回退 worker 与 parity oracle；
Kotlin/Native 出口在 `ffi/native`，以引擎级 C ABI 供 Rust 编排调用（ADR 0050）。纯文本与受控语义 inline
共用 source / semantic artifact / typography / font / width 证据；prepared DOM 留在正文之外的 inert
template，SSR 正文始终是可响应的 native semantic backing。浏览器只有在 live width、字体与 artifact
证据全部匹配时才整批采用快照；窄屏等 snapshot miss 使用构建期捕获的字号无关 shaping / metrics
回放表继续运行 Kotlin/JS layout core，浏览器不加载 HarfBuzz / WOFF2 WASM。证据缺失时保留 source，
再回到 Canvas host-font pipeline。完整契约见
[ADR 0040](adr/0040-build-time-web-font-snapshots.md)。

引擎插入的视觉软换行不进入复制或无障碍语义；真实 mandatory break 保留。跨段复制同时提供
block-aware `text/plain` 与去除引擎几何后的宿主语义 `text/html`。

### Android View

`frontend/android-view` 目前只保留前端契约，还不是与 Compose / Web 同等完整的可用入口。

### Apple

`frontend/apple/coretext-render` 在 macOS 与 iOS 上用 Core Text 重放 `LayoutResult`。正文字形沿用 shaping
时的 language、OpenType feature、font 与 glyph 选择；拼音、注音和行间装饰消费核心给出的最终几何。
装饰颜色继承对应 source range，专名号和书名号只依据 `LayoutResult` 已记录的 glyph ink bounds
做避让，renderer 不重新 shaping 来推导布局真值。

`frontend/apple` 是 Apple frontend 的唯一根：Gradle 模块把引擎、内部 Core Text renderer 与窄
Swift-facing authoring/document facade 打成静态 `Tiqian.xcframework`（macOS arm64、iOS device
arm64、iOS simulator arm64），同目录 Swift Package 用原生 `AttributedString` 表达字体、颜色、ruby
、链接与装饰，并将同一 run 上的组合属性 lowering 到同一 source range。正文与注文语言独立 lowering：
注音使用 `zh-TW`，不会覆盖简体横排正文默认的 `zh-Hans`。公共 Swift 类型使用 `CJKText`、
`CJKBlock`、`CJKAttributes` 等领域名称；品牌名只保留在 `TiqianUI` 模块和包内二进制 artifact。
`CJKTextView` 直接提供 `NSScrollView` / `UIScrollView` 原生入口，`CJKText` 只用
`NSViewRepresentable` / `UIViewRepresentable` 包装同一个 view；AppKit/UIKit 只处理 viewport、滚动、动态系统颜色、坐标变换与
无障碍 source text，宽度变化复用已 lowering 的 builder，并按整字栏宽重排。`frontend/apple`
把多 block 的全局 UTF-16 source range 映射到各自 `LayoutResult` 的 hit-test / caret / selection box；
iOS view 实现只读 `UITextInput` 并交给系统 `UITextInteraction(.nonEditable)` 管理手势、手柄与菜单，
macOS view 用标准 responder action、`NSPasteboard` 与 AppKit 鼠标事件完成拖选、双击词选和复制。
Apple 端用简体中文 `NLTokenizer` 把命中 offset 扩成语义词范围，核心仍提供 UTF-16 安全边界与全部
caret/selection 几何；平台 tokenizer 不参与 shaping、断行或字位计算。
原生 `AttributedString.link` lowering 为精确 source range；链接命中区和下划线同样消费
`LayoutResult` 几何。SwiftUI 交给环境 `OpenURLAction`，AppKit/UIKit 原生入口可通过 `onOpenURL`
接管，未接管时使用平台 URL opener；拖动选择不会触发导航。
两端都不经 TextKit 重排文字，也不维护第二份字符几何；编辑器和 IME 仍不属于这条静态正文路径。

## 模块职责

- `core`：平台无关的数据结构与 layout contract，不依赖其他提椠模块。
- `font`：字体角色、fallback 与字体度量策略。
- `shaping/*`：平台 shaping / replayable font contract 及其实现；`shaping/android-adapter`
  是 Compose Android 默认的公开平台 run 后端，`shaping/android-native-font` 持有
  宿主可显式选择的共享字体源、受控 face、HarfBuzz / FreeType 与同源
  outline replay。
- `linebreak`：断行机会、西文断词与相关数据。
- `clreq`：中文 profile、标点分类、禁则与空间策略。
- `layout`：段落布局、修复、行调整与结构化 decision。
- `frontend/compose`、`frontend/web`、`frontend/android-view`：前端
  lowering 与呈现。
- `frontend/apple/coretext-render`：Apple 内部 Core Text renderer 与 paragraph backend。
- `frontend/apple`：生产 Swift facade、静态 XCFramework、`AttributedString` authoring 与 Apple
  原生 view package；不拥有示例内容或排版规则。
- `ffi/native`：引擎级 packed C ABI 的 Kotlin/Native 门面；不拥有排版规则。
- `ffi/js`：引擎的 Kotlin/JS 门面（`@JsExport` wire 与 HarfBuzz session 后端）；不拥有排版规则。
- `frontend/web-precompute`：Rust workspace（`tiqian-precompute`、`tiqian-precompute-neon`）与
  `@tiqian/precompute` npm 包；Node exact-font session 与构建期编排；不拥有排版规则。
- `frontend/web/integrations/*`：框架 SSR / build / navigation transport；消费 `@tiqian/prose` 的公共
  HTML prepare 与 snapshot contract，不拥有排版或字体 policy。
- `demo`：Desktop / Android 共用的 Compose 示例界面与 Desktop 启动入口。
- `demo/android`：只负责 Android 应用打包和启动的薄外壳。
- `demo/apple`：一个 Xcode project 内的 macOS / iOS targets，共享 Swift 样例内容并消费
  `frontend/apple`。
- `test-support` 与 `layout` 的报告任务：共享语料、布局诊断和文档样张生成。

首次公开发布的套件统一使用 Maven group `org.tiqian`。提椠 artifact 保留 `tiqian-*`
产品族前缀，其中 Compose 基础前端与 Material 3 适配层分别是 `tiqian-compose` 和
`tiqian-compose-material3`；数学与 Markdown 分别使用 `math-*` 与 `markdown-*`。Markdown 的中立文档模型位于
`org.tiqian.markdown`，Compose renderer 位于 `org.tiqian.markdown.compose`；Android native
字体后端位于 `org.tiqian.shaping.android.nativefont`。完整命名边界见
[ADR 0048](adr/0048-suite-maven-and-package-namespaces.md)。

## 不变量

跨模块改动应始终保持以下约束：

1. source text 与 source range 不因显示替换或软换行改变；
2. 可重放后端的测量和绘制必须使用同一字体、glyph 与 placement；无法同源时显式报告 capability；
3. 平台层不拥有排版规则；
4. 每个 heuristic 与 capability fallback 都有名称、decision 和测试；
5. renderer 不持有第二份布局真值；
6. 新能力不能以破坏无 JavaScript、复制、搜索或无障碍语义为代价。

## 文档关系

- 本文描述**当前架构**。
- [roadmap](roadmap.md) 描述**当前工作与实施状态**。
- [ADR](adr/README.md) 记录**为什么选择当前方案，以及方案如何修订**。
- [CLREQ gap audit](clreq-gap-audit.md) 与
  [标点码点审计](clreq-punctuation-audit.md) 记录**规范要求与实现证据**。
- [初始设计备忘录](cjk-layout-engine-design.md) 与 `docs/research/` 保留**历史背景和研究快照**。
