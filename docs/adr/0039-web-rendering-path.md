# ADR 0039: Web 渲染路径 —— 引擎持有行布局,DOM 只画预断行

- Status: Accepted + Implemented (Slice 34-35; 2026-07-11 host integration amendments;
  2026-07-13 canonical prepared CSS + ancestor transform amendments;
  2026-07-14 Web native-list + first-paint + strong opt-in amendments;
  2026-07-15 Kotlin/JS-only runtime + semantic snapshot amendment;
  2026-07-16 server shaping replay + mixed snapshot/runtime amendment)
- Date: 2026-07-07
- Relates: [ADR 0008](0008-shaping-adapter-contract.md)(shaping adapter 契约)、
  [ADR 0014](0014-ink-bounds-calibrated-punctuation-geometry.md)(`halt` = 度量入口非渲染依赖)、
  [ADR 0031](0031-line-adjustment-direction.md) + [ADR 0038](0038-neighbor-amortized-adjustment.md)(推入推出 / 邻行均摊)、
  [ADR 0037](0037-source-faithful-plain-text.md)(源忠实)

## Context

第二阶段要给提椠加 web 前端。一个诱人的误判是「web 没有 Compose 那些平台能力缺口
(ink skip / 度量补足),所以只要用字体的 `halt` 渲染标点、往里插空、让浏览器换行就行」。
逐条证伪:

1. **提椠在任何平台都不是「用 `halt` 渲染」的**。ADR 0014 已定:排版 advance 来自
   前端可重放的 shaping pass（普通 CJK 标点不启用 `halt`；ADR 0040 exact path 可为 Latin
   quote segment 携带显式 feature）,空白削减由 glue 模型显式执行,`halt` 只是度量入口 + 交叉
   校验；body 以 policy 0.5em 为规范目标，真实 ink 装不下时由 ADR 0014 的
   `InkContainmentBodyFloor` 只抬到最小安全宽度。AWT 桌面 adapter 完全没有 `halt` 能力，
   仍可走明确的 policy fallback。
   所以「字体没有 `halt`」在 web 上不构成结构性损失——降级路径本就在跑。
2. **把断行交给浏览器会丢掉推入推出**。`line-break: strict` 只做一种粗暴避头尾:把犯忌
   字**永远推出**到下一行,没有方向偏好、没有压缩预算、没有 ADR 0038 的邻行均摊,也不可
   解释。这恰恰是引擎最不可让渡的部分。委托浏览器折行 = 丢掉皇冠。
3. **canvas 渲染对正文是错的**。提椠面向中文**正文**,canvas 丢失文本选择、无障碍、复制、
   原生 reflow,还要自管 devicePixelRatio 与重绘。canvas 只适合整块图形。

结论:web 既不能把排版决策让给浏览器(违背「模型必须真」),也不能用 canvas 换取控制权
(丢正文该有的文本语义)。

## Decision

Web = **第四个平台 adapter + 引擎完整行布局 + DOM 画预断行的文本节点**。

### `KotlinJsOnlyWebRuntime` —— 发布链不再保留 WebAssembly 后端

浏览器与 Node 预计算入口都发布为 Kotlin/JS。2026-07-15 在同一台 Edge、开启“增强的安全性”后，
用同一真实 pipeline 对 24 段正文做三轮 A/B：Kotlin/JS 每轮 299.1 / 308.9 / 307.6 ms，
中位数 307.6 ms；Kotlin/Wasm 每轮 682.4 / 683.2 / 683.3 ms，中位数 683.2 ms。JS 用时约为
Wasm 的 45%，而两端的 24 段、72 行及 line width 输出一致。

因此不在运行期猜测浏览器安全模式，也不维护双 backend 或失败后切换。引擎链只保留 `js` target，
浏览器发布单一 production bundle，Node 预计算发布 ESM modules；npm 的生成 runtime 目录不得包含
Kotlin `.wasm`，构建也不再下载 Binaryen。这个决定只替换编译与分发后端，不改变本 ADR 的 shaping、
断行、DOM、复制、snapshot 或宿主回退契约。

2026-07-16 的 Edge 增强安全性复查发现，原先的 browser exact-font / 破折号预检仍会懒加载
`harfbuzzjs` 与 WOFF2 decompressor，导致含破折号或 snapshot miss 的页面重新受到 WASM 限速。
因此浏览器发布链现在端到端不再加载 WebAssembly：HarfBuzz 只在 Node 构建期解析站点明确发布的
字体，并把当前 pipeline 实际请求过的 segment shaping 与 font metrics 归一化成字号无关回放表。
浏览器只用纯 JS 按实时字号缩放这份证据，再把结果送入同一个 Kotlin/JS layout core；来源 URL、
source hash、CSSOM face contract、FontFaceSet 与可见 DOM advance 仍现场校验。没有服务器回放证据时，
普通正文继续走 Canvas；要求 exact glyph 的破折号段落具名保留原生 DOM，不能静默猜测。

Node precompute 的依赖树仍包含 HarfBuzz WASM，但它不进入或运行于浏览器。Kotlin 的 `@JsFun` 目前
仍使用名为 `ExperimentalWasmJsInterop` 的编译器 opt-in；该注解名称不是 WebAssembly target 或
运行时依赖。

### `OffscreenMeasureTextShaping` —— 度量而非渲染

web 的 shaping adapter(ADR 0008 的第四个实现)用**离屏 canvas** `measureText` 取 advance、
`TextMetrics.actualBoundingBox*` 取 ink bounds。它消费宿主元素的 computed font family / size /
weight / slant；若字体栈首项对可见字形给出零或非有限 advance，则按同一 CSS 栈的后缀继续探测，
并把 requested / actual canvas font 与命中的栈序号写入 shaping decision。canvas 不上屏，
与 AWT / Skia / Android 三个 adapter 同契约。Canvas 目前不能可靠提供 `halt` / `locl`，
因此二者是具名平台降级，不伪装成已经接入。

Canvas 2D 同样不能可靠报告“首选 face 缺字但 CSS fallback 画成功”：此时 advance
仍为正，不能靠零宽探针识别。layout 因此对有规范目标几何的替换继续执行平台无关
交叉校验；例如 U+2E3A 必须通过 ADR 0003 的 `DashSubstitutionTwoEmInkCoverage`，
否则回滚 source `——`。这条校验不解析宿主生成的 font-family hash。

“可见字形”是该保护的必要前提。ADR 0037 的 U+200B 在 layout 层先降为
`ZeroWidthSpaceSoftBreakNoShape`，不会进入 Canvas；`measureText(U+200B) == 0` 是正确语义，不能
触发 `InvalidWebShapingAdvance`。`font-size:0` 等可见内容零宽仍继续具名回退。

### `HarfBuzzVerifiedCjkDash` —— 破折号必须拿真实 face / glyph 证明

Canvas 的正 advance 和墨迹宽度只能证明“浏览器最后画出了某个东西”，不能证明它来自
正文 CJK face，也不能给出 glyph id、`locl` 是否替换或 fallback 落到哪张字体。因此 Web
端的中文两字破折号不再把 Canvas 几何当合格证据；普通正文仍走
`OffscreenMeasureTextShaping`，破折号 exact evidence 只在构建期 HarfBuzz session 中生成。

`CssomFontSourceResolution` 的 source / family / weight / style / `unicode-range` 契约由构建端明确
输入并写入 snapshot manifest；浏览器再从当前 computed style 与 CSSOM 逐项复核，不能在库中猜
构建器生成的 family hash。WOFF2 只在 Node 还原为 SFNT 并交给 HarfBuzz；HarfBuzz 明确使用
`script=Hani`、`language=zh-Hans` 和当前 `wght` variation，产出 glyph id / placement / advance /
ink bounds，随后进入 `ServerShapingReplayTable`。

候选顺序是同一个 CSS family 中的 `U+2E3A`，然后 `U+2014 × 2`，再进入 CSS CJK stack 的
下一个可验证 family。合格契约不是“glyph id 必须与西文不同”：默认 glyph 本来就可能符合
中文排版。它要求总 advance 约 `2ic`、墨迹至少覆盖目标的 85%、水平居中、与同 face “一”字
视觉中线相差不超过具名容差；成对 U+2014 还要求各自约 `1ic` 且接缝无正空隙。默认 shaping 与
显式 `locl=0` 对拍：确有替换才记 `LocalizedVariant`，否则记
`DefaultCjkConforming`。最终策略写成 `TwoEmDash` 或 `PairedEmDash`，连同 exact face、glyph ids、
script/language、advance、ink center、seam 与 feature evidence 进入 shaping decision。

浏览器 exact session 同步消费服务器回放表；没有 manifest、回放 key 缺失、source contract 不可
验证或所有候选不合格时返回 `NoConformingCjkDashGlyph`，该段保留原生 DOM，不能退回 Canvas 后
宣称“中文变体已确认”。DOM 正文仍不能按 glyph id 重放，否则会损失选择/无障碍；它把该 run 固定
到 manifest 证明的 exact family 并设置 `lang=zh-Hans`，随后以可见 Range 宽度与服务器 HarfBuzz
advance 交叉验证。不一致报告 `DomDashFaceGeometryMismatch` 并撤回增强。这是
`ExactGlyphReplayUnavailableOnDom` 的诚实边界，而不是让 DOM 重新决定候选。

### `EngineOwnedLineBreaking` —— 断行留在引擎

引擎持有整套行布局:断行 + 推入推出(ADR 0031)+ 邻行均摊(ADR 0038)+ justify。**浏览器
不参与任何断行决策**。这是本 ADR 的核心红线。

### `WebNativeTwoIcListIndent` —— Web 列表固定缩进两字并保留原生 marker

Web 列表不复刻 Compose 的自动 marker gutter。公开静态样式表让每层 `ol/ul` 的正文列固定缩进
`2ic`，保留浏览器原生 `::marker`、`start` / `value`、列表语义和选区；footnotes 宿主列表不覆盖。
`li` 正文仍可进入 Tiqian 段落 pipeline，但显式使用零段首缩进，续行服从列表内容盒中的同一
行长网格。Web 不再生成 marker span / pseudo，也不在首轮为 marker 启动 shaping 或改变列表几何。

该取舍有意与 Compose 的自动升整字 marker 列分开：Web 目标是接近浏览器原生的稳定两字缩进，
并让 CSS 在 runtime 前已经给出最终列表几何。构建期 snapshot 缓存可证明的 `<p>` / leaf `<li>`；
未预排正文继续保留 semantic source，再由 runtime 按视口优先逐段补齐，不能因为一个 runtime-only
candidate 丢弃同 root 内其余已验证快照。marker 与两字缩进始终由同一份静态 Web CSS 持有。复杂 item 不能
完整 lower 时保留其原生内容，不影响同列表 marker。

### `ExplicitBreakSemanticFlow` —— DOM 画预断行，但不切断语义树

原 `<p>` 自身就是唯一 inline formatting flow，不再插入会破坏 `p > a` / `p > code` 等宿主
selector 的中间 wrapper。引擎行边界落成无源字符的显式 `<br>`，每行开头
放一个零宽 `LineMetricStrut` 固定该行的引擎高度与 baseline。`white-space: pre` + 禁用浏览器
owned wrapping 保证浏览器不会二次断行。这样一个源 `<a>` / `<strong>` / 自定义 inline 可以
跨多个引擎行保持为**同一个 DOM 元素**，浏览器原生负责它的多行伪类、装饰、点击与无障碍语义。

行内仍是按连续几何合并的稀疏 run：推入压缩、推出留下的空、autospace、justify 落成
`letter-spacing`；多字 Latin run 的正 gap 只放到最后一个 grapheme 的 `letter-spacing`，避免
把字内拆成 tracking，也避免 `padding-right` 不进入原生选区与继承 underline 所造成的断口；
负 gap 用 `margin-right` 形成重叠。末 cluster 的 body 压缩也必须显式落成 spacing，不能依赖
裁掉行盒外侧来“碰巧”得到半宽。节点数 ≈ 行数 + 稀疏语义 span，不是每字一个 span。

比例宽标点进入更宽的 profile 盒时，layout 通过 `Cluster.glyphInlineShift` 把 glyph
origin 放到开/闭/对称 body 的正确侧；DOM 仍按相邻 `drawX` 差值落 spacing，不识别
具体码点。这样中文上下文弯引号可以占一字并保持宿主字形，英文 quote pair 仍是
原生比例宽度。

`LineMetricStrut` 的 `data-tq-line-width` 表示 layout advance，不是 ink clip。
`VisibleInkOutsideAdvance` 要求整段 flow 保持 overflow visible：字体 ink、斜体外伸和宿主链接
装饰可以超出 advance；禁止用 `overflow-x: clip` 修齐选择边缘。

`HostCssIsolationForEngineGeometry` 只隔离引擎生成的 geometry / annotation 节点：这些节点先以
`all: unset !important` 清掉宿主对通用 `span` / `svg` 的盒模型，再写回引擎拥有的尺寸与
位置。对 canonical plain prepared DOM 与 runtime DOM，这些不变的 reset / display /
white-space 声明由发布包 `styles.css` 中的受限 selector 统一持有；节点 inline style 只写每行不同的
`--tq-line-height`、`--tq-line-baseline-offset`、可选 `--tq-line-flow-start` 等动态参数。这是
`SharedLineMetricStrutCss`：它缩短 SSR 与 runtime HTML，但不把几何真值移到 CSS；CSS 只重放
plan 明确给出的参数。富语义 runtime renderer 的 invariant `all: unset` 也由
`SharedRuntimeGeometryCss` 持有，inline-important 只保留实际变化的 spacing / decoration 数值；否则
Chromium 会把 CSSOM 中的 `all` 展开成数百条重复 inline 声明。

source semantic clone 不做这种 reset，继续让宿主 selector、伪类与 transition 生效。flow 所需的
white-space / wrapping longhand 由 `[data-tq-rendered]` 与 `[data-tq-source-semantic]` 的共享规则持有，
不再写进每个段落或 clone 的 style attribute。destroy 恢复 `data-tq-rendered` 并移除 clone 后，规则
自然失效，宿主运行期的 inline style 不需要 Tiqian 逐项回滚。

### `HostOwnedLightDom` —— 原节点与宿主 CSS 仍是事实来源

客户端增强保留 SSR 生成的原 `<p>`，只暂存并替换它的 inline children；`<p>` 本身继续持有
宿主 class、继承、CSS selector、Pagefind / a11y 语义。顶层 source semantic 仍是 `<p>` 的直接
子节点，链接、`code`、`strong`、`em` 等元素各自
只浅克隆一次，原有 href / class / data attribute 与宿主 CSS 继续生效；Tiqian 不定义链接颜色、
字体或动画。宿主语义节点的水平盒模型若净 advance 为零（例如链接
`padding: 4px; margin: -4px`），可以保留；Tiqian 的 autospace / justify 必须在捕获到的宿主
padding / margin 上做增量叠加，不能覆盖原值。`InlineBoxBoundaryAdvance` 已支持这些非零边界；
只有 `box-decoration-break: clone` 真正跨行、状态对象不能静态复制或几何不可测时，才报告具名
capability issue 并完整保留原生段落。

`ContinuousSemanticFlow` 要求整段 source semantic path 只克隆一次：同一个 `<a>` 即使内部因
autospace / justification 分成多个 geometry run、并跨越多个 `<br>`，也必须保持一个宿主 `<a>`，
由无语义子 span 承载各段 spacing。否则链接的 hover/underline、焦点与 accessibility tree 都会
被物理拆开。语义 path 的行边界判定来自 source range 是否**严格跨过**该 offset，不能依赖下一行
第一个可见 cluster；否则 `<a>甲<br><br>乙</a>` 的空白强制行会再次把链接切成两个节点。软换行
`<br>` 没有 source text，不进入复制结果。

`ComputedInlineFormattingContextLowering` 不再用 `a/code/strong/em` 标签白名单猜宿主能力：只要节点
是纯文本 `display:inline|contents` formatting context，lowerer 就递归保留其原标签、属性与 computed
字体样式。因此 `span/del/mark/small/sup` 与站点自定义 inline element 不需要 Tiqian 逐标签认识。

`MeasurableOpaqueInlineObject` 处理内容不应由 Tiqian lower、但外部几何可以稳定测量的独立 inline
formatting context。lowerer 在 source projection 中放一个结构性的 U+FFFC，并以 `InlineObjectSpan`
把 margin-box advance、相对宿主 baseline 的 ascent / descent 送入 core；对象不经过字体 shaping，作为
不可拆 cluster 参与断行，其上下界参与所在行的真实高度。DOM renderer 再按 source range 深克隆原
宿主节点，所以 `img`、裸 SVG 与普通自定义 `inline-block` 由同一 formatting-context 能力覆盖，而非
标签白名单。U+FFFC 不进入可见 DOM，也不进入复制结果。

默认只接受几何稳定、非交互且可安全克隆的对象；带表单状态、焦点/编辑状态、canvas 或内联事件处理器的
对象报告 `UnsupportedStatefulInlineObject`，整段保留原生。自定义元素默认同样回退，宿主可用
`data-tiqian-static-inline-object` 明确声明其 DOM 可作为静态绘制内容复制。对象加载后自行改变几何的
监听尚未接入，命名为 `OpaqueInlineObjectGeometryInvalidation`，不得把初次测量伪装成永久有效缓存。

`CjkStrongAsEmphasisMark` 是显式 opt-in 的 HTML 语义映射。默认情况下 `<strong>` 完整保留宿主
粗体语义；Markdown 的 `strong` 只表达重要性，不能据此推断作者想要中文着重号。只有调用方设置
Web API 的 `strongAsEmphasisMarks: true`，或在 `<tiqian-prose>` 上添加
`strong-as-emphasis-marks` boolean attribute 时，`<strong>` 内被同一
`FontRoleClassifier` 判为 `CjkText` / `CjkPunctuation` 的 grapheme 才降为
`DecorationKind.Emphasis`，并把这些 grapheme 的字重恢复到进入 `<strong>` 前的父级字重；汉字由
既有 `EmphasisDotOnHanText` 逐字加点，中文标点按 CLREQ 跳过。西文、数字、emoji 不进入该
decoration，继续使用宿主 `<strong>` 的真实粗体，不能被 `BilingualEmphasisWesternItalic` 误改成
斜体。DOM 仍浅克隆原 `<strong>` 以保留 class / color / transition 等宿主声明；只在 geometry leaf
上覆盖引擎实际 shaping 的字重。着重号继续画引擎给出的 SVG 几何，不使用浏览器
`text-emphasis` 再排一遍。Web API 用 `emphasisDotGapEm` 把 ADR 0018 的
字面净空传入 layout；`<tiqian-prose>` 对应 `emphasis-dot-gap-em` attribute。
两者都不从宿主 `line-height` 推导距离。

最大版心 snapshot 可以保留普通 `<strong>` 的宿主语义，但不能假装已经执行了 opt-in 的
strong-to-emphasis 映射。root 显式开启转换且实际包含 `<strong>` 时，
`OptInStrongSnapshotExclusion` 跳过 snapshot adoption 并进入 browser runtime；默认粗体路径仍可
采用语义快照，不能让一个默认关闭的策略损失首帧能力。

`InlineBoxBoundaryAdvance` 把宿主 inline 的真实边界几何作为 layout input，而不是渲染后补偿：DOM
在原生 source 仍连接时测得 inline-start/end 的 padding、border、margin 与 `::before/::after` 占宽，
降为平台无关 `InlineBoxSpan`；core 把边界 advance 加进断行，并用 `Cluster.leadingLayoutAdvance` 区分
盒子起点与 glyph origin。这样 inline code、spoiler pill、脚注伪元素都由同一模型计宽，标点压缩也不得
吞掉这些结构宽度。相对定位/普通长度 `vertical-align` 从 computed style 读取为显式 baseline shift；
只有无法解析的关键字才使用临时 baseline probe。

browser runtime 只有在调用方显式提供 `monospaceFontFamily` contract，或 computed family 对应一个
已经加载的 CSS `FontFace` 时才接管 `<code>`；仅有 generic / system fallback 时以
`InlineCodeFontFaceUnavailable` 整段保留 native，不能用不确定的 fallback advance 参与断行。

连续语义元素把跨行盒模型重新交还浏览器：padding、border、`::before/::after`、source `id` 与
`box-decoration-break` 都只存在于一个真实元素上，不再需要 continuation clone、open-edge attribute
或 hover/focus 状态桥。已有 `:hover` / `:focus` selector 与 transition 直接生效，宿主无需为 Tiqian
额外声明一套 attribute selector。

`HostPunctuationPolyfillExclusion` 要求宿主在启用 Tiqian 的 light DOM 上移除会直接改写标点
advance 的浏览器侧字体 polyfill，同时保留真正的正文 face / size / weight / slant / line-height。
例如 neo-blog 的 `CP` 字体已经把部分右标点做成半字宽，而 Canvas 2D 对 CSS fallback 栈的
度量仍可能落到后继正文 face 的全字宽；随后 Tiqian 再按引擎几何减去半字，DOM 中该标点就会
被压成 `0px`。这不是 kerning，也不能靠拆 span 修复。宿主应从源码级 typography token 派生
一个仅移除 `CP` 的 layout-neutral 栈，在 `<tiqian-prose>:defined` 后生效；no-JS 原文仍保留
原有 polyfill，增强路径则由 Tiqian 独占标点 advance。

发布形态是 ESM package `@tiqian/prose`：`<tiqian-prose>` 使用 light DOM，按需加载优化后的 Kotlin/JS
runtime。custom element 的 connected / disconnected 生命周期负责 enhance / destroy，
因此 Astro / Swup 等宿主不需要理解 Tiqian 内部状态或猜构建产物 hash。发布 allowlist 必须包含
Gradle 生成的 `runtime/tiqian-web.js`；仓库内 build helper 不是安装后可执行的 CLI，不能以一个
依赖仓库 `gradlew` 的伪 `bin` 入口发布。

嵌套 root 以最近的 descendant root 为所有权边界：外层 `enhance()` 不得再次 lower 内层 root 的
段落，`enhanceAll()` 则让每个 root 各自接管直接作用域。这样局部 widget 与整篇正文可以同时使用
Tiqian，而不会产生双重渲染或相互 destroy。

### `ProgressiveParagraphEnhancement` —— SSR 先可用，视口优先逐段接管

Kotlin/JS runtime 内部的 `TiqianWeb.enhance()` 在 runtime 已安装后同步完成一个 root；ESM package 的
`enhance()` 返回 Promise，因为它必须先等待 runtime、stylesheet 与按需字体能力准备。custom element
默认走 `enhanceProgressively()`。
候选段落先按与 viewport 的距离排序，再在约 8ms 的 animation-frame budget 内分批 lower / layout。
每段准备好后在同一 callback 内原子替换自己的 children；尚未轮到的段落继续显示响应式 SSR DOM。
root 级 exact font family、宿主字号、行高与 content width 在接管前已经统一，因此中间帧可以混合
native / Tiqian 段落，但不能出现字体、行高或版心参差。断开 root 会取消待执行 frame，并精确还原
已增强段落。完成事件同时报告总耗时与最大单 slice 耗时，避免只看 bundle 下载大小而忽略主线程任务。

每段接管必须满足 `ParagraphAtomicNativeRollback`：lowering、layout 或 DOM commit 任一阶段失败，都在
callback 返回前恢复该段原 children 与宿主属性，再发布具名 capability issue 并继续其他段落。任何
paint 都不能出现空段或半成品 DOM；具名不支持段落可以保持 native，但不能被永久遗漏且没有解释。

### `HostCascadeReadyGate` + `HostTypographyInvalidation` —— measure 与 paint 同源

light DOM 继承宿主 CSS，因此 custom element 不能把 `connectedCallback` 当成 computed style
已经稳定的信号。初次增强先等 Tiqian stylesheet，再用一个 animation frame 让解析器与宿主
cascade 落定；随后只对正文 computed font descriptor 与实际字符调用 `FontFaceSet.load()`，而不等
`document.fonts.ready` 中无关的图标、代码或 widget 字体。正文字体等待以 3 秒为上限；超时后原生
SSR 继续作为事实来源，不启动可能与 font swap 竞态的测量。对应 load promise 最终 settle、相关
`loadingdone` / `loadingerror` 或宿主字体样式变化时，custom element 从最新一代连接状态重新走完整
gate。构建期 snapshot 自己验证明确声明的 exact face，因此命中候选不重复执行这次通用字体扫描。
否则 Vite/Astro 的模块 CSS 仍可能把正文从浏览器默认 `16px / normal` 改成站点的 `18px / 460`，
canvas 按旧值度量而 DOM 按新值绘制，整行墨迹会超出 `LineBox.visualWidth` 并被宿主容器裁切。

`TranslationOnlyAncestorTransformCompatibility` 只把祖先 computed `matrix()` / `matrix3d()` 中的
纯 x/y 平移视为不改变排版几何：linear 分量保持单位矩阵，perspective 与 z 分量保持为零。它允许
宿主入场动画在终态仍保留 `translateY(0)`，以及只移动整个正文的平移帧；这些状态不改变段内 advance、
content width 或相对 baseline。scale、rotate、skew、perspective、z 平移、独立 `scale` 属性以及
无法解析为 computed matrix 的 transform 继续 fail closed；段落自身的 transform 也不放宽。

连接期间记录正文、source semantic inline clone 与 inline object 的 computed typography / box /
pseudo-content signature，并观察 root 子树的样式属性、祖先属性以及 FontFaceSet `loadingdone`。
签名、宿主样式所有权或真实 font face 变化时，
`HostTypographyInvalidation` 先恢复 SSR inline children，再重新 lower，并继续走分帧增强；只有
容器宽度变化且 typography signature 不变时才复用 lowered source 走普通 relayout。resize
必须先做 signature 比较，因为 media query 可以同时改变字号/行高而不产生任何 class/style
mutation。宿主无需向 Tiqian 重复声明一套字体。

宽度变化也可能让 capability 本身发生转换，例如 `box-decoration-break: clone` 从单行变成跨行。
`CapabilityTransitionNativeFallback` 要求 relayout 一旦发现当前宽度不能保真，就原子恢复该段 SSR
children 并发布 issue，不能保留旧宽度的 Tiqian DOM；后续宽度变化会重新尝试，使回到单行时可以
恢复增强。ESM 入口的字体/runtime 异步准备另由 `AsyncPreparationCancellation` 代际化：`destroy()`
或更新的 enhance 请求必须使旧 promise 失效，不能在导航后复活已断开的正文。custom element 在首次
接管前收到公开属性变化时也必须重启连接代际；尤其 `strong-as-emphasis-marks` 会改变 snapshot
eligibility，不能让等待字体之前捕获的旧值在等待结束后提交。

`RouterRemovedStylesheetRecovery` 要求每次 root 连接都以当前 document 为事实来源检查
`link[data-tiqian-stylesheet]`，不能把一次已 resolve 的 module-level Promise 当成 stylesheet 永久
存在。Swup Head Plugin 等客户端路由会移除下一页 HTML 中不存在的 runtime asset；若 Tiqian 的
`text-autospace: no-autospace` 随 link 一起消失，返回正文后浏览器会再次插入 1/8em 原生 autospace，
与引擎 spacing 叠加并造成整行错排。link 被移除后，下一次 `ensureTiqianStyles()` 必须新建并等待
真实 stylesheet，而不是复用指向已断开节点的旧 Promise。

渐进增强的 typography signature 以 `tiqian:ready` 完成时为准，而不是首次
dispatch 时为准；逐段分帧接管期间若响应式 CSS 刚好稳定，完成值才是引擎
实际使用的宿主状态。typography / resize observer 在 progressive job 期间必须暂停，并只在
`tiqian:ready` 后重新连接；否则它会把引擎自己写入的 paragraph style 当成宿主变化，反复取消
尚未处理首段的 job。后续每次 full refresh 完成也同步更新该 signature。

### `CssWhiteSpaceCollapseProjection` —— DOM 源码换行不等于强制断行

Web lowerer 的输入是宿主已经生成的 DOM，不是 Markdown 源文件。SSR/HTML 序列化器会在 inline
节点之间以及 `<br>` 之后保留用于格式化源码的换行；在宿主 `white-space: normal` 下，这些 text
node 空白会由浏览器折叠，不能直接作为 UAX mandatory break 送进 layout。否则普通 Markdown
软换行会变成硬换行，`<br>\n` 会变成两个连续硬换行并产生一个宽度为零、却占完整行高的空行。

lowerer 因此先按每个 inline formatting context 的 computed `white-space` 建立源投影：
`normal` / `nowrap` 折叠连续 CSS 空白，`pre-line` 折叠空格但保留 text node segment break，
`pre` / `pre-wrap` / `break-spaces` 保留空白与 segment break，并按 CSS Text 把 CRLF / CR
规范化为单个 LF；只有真实 `<br>` 另记为结构性 mandatory break。
投影同时生成 UTF-16 boundary map，`TextSpan`、decoration、inline box/object 与 source semantic range
必须一起重映射，不能只改字符串再猜 range。复制语义与宿主原生 `innerText` 对拍：HTML 格式化
空白不凭空进入复制，真实 `<br>` 仍复制为一个换行；原 SSR children 在 destroy 后逐节点还原。

同一 computed typography 与容器宽度必须得到同一投影和 line signature。验收包含
`width A → width B → width A` 往返测试，逐项比较行文本、行宽与 hard-break 位置，不能只比较
最终段落高度。

### `EngineOwnedHyphenation` —— 断词也归引擎,不甩给浏览器

拉丁词的断词(ADR 0029:`LineEndHangingHyphen` / `LatinForcedHyphenBreak` /
`ExistingHyphenBreak`)与 CJK 断行同理,**必须由引擎决定,DOM 一律不用 `hyphens: auto`,
也不得把未断的整词交给浏览器去折**。委托浏览器断词会丢两样东西:

1. **连字符拿不到**:引擎的行尾连字符是受控几何——`LineEndHangingHyphen` 把连字符
   预留进版心、放不下才把残余悬挂(ADR 0029)。浏览器 `hyphens: auto` 用自己的词典和
   自己的连字符,不是 CLREQ / 引擎那一个,也不进 justify 计量。
2. **断点两端的字偶间距(kerning)被扔掉**:引擎是把**整词**连同字偶间距一起度量、再在
   词内选断点的;一旦交给浏览器重折,两段被独立重排,断点两侧的 kerning 与两行各自的
   advance 都跟引擎算的对不上,justify 也就错位。

所以 DOM 侧:引擎断的词,行尾连字符由渲染层**显式画出**(引擎已把它算进版心 / 悬挂量),
两行的拉丁 run 用**引擎的 per-cluster advance**(含 kerning),不让浏览器重新 shape。
CSS `hyphens` 恒为 `manual`(即不自动断词)。断词开不开、用哪套词典,是引擎默认
(ADR 0029,当前默认开)的事,与 web 后端无关——web 只负责忠实画出引擎的断词结果。

### `ReflowByRebreak` + `WidthIndependentAnnotationCache` —— resize 只重跑折行

放弃「浏览器免费 reflow」，换成 `ResizeObserver` 驱动引擎重排。目标仍是只重跑折行那一趟：
cluster advance、locl 字形、基础 autospace 等宽度无关量应缓存，再喂给断行 / 推入推出 /
justify。**当前 Slice 34/35 实现仍按段重跑完整 pipeline**；`WidthIndependentAnnotationCache`
是已命名的性能缺口，不能把理想目标写成既成事实。

响应式 invalidation 采用 `LineLengthGridResponsiveInvalidation`：当前 Web 正文只呈现 Start-aligned
body，有效行长按 `floor(contentWidth / fontSize)` 个字格向下取整（不足一格时仍保留实际宽度）。
所以同一字号字格内的像素变化不会改变断行、placement 或 body offset，不应重跑 pipeline；小数字号
仍按 Kotlin `Float` 语义判断，不能用固定 `0.5px` 容差吞掉一次真实跨格。最大版心快照也按相同
有效字格复用；只有未启用字格量化时才严格比较实际 content width。字号、字体、行高等 typography
变化仍必须重新 lower，不能被字格合并。

响应式调度采用 `LeadingSingleFlightGridInvalidation`，不再等连续变化停止 180ms 后才开始工作。原始
宽度变化先折叠为有效字格：同一字格内无论收到多少次 `ResizeObserver` / viewport resize 通知都产生
**零个** layout job；第一次跨格则在下一 animation frame 以当时最新的有效行长启动 job。任意 root
同时最多有一个 responsive job 在途，在途期间继续发生的跨格只更新 latest target，不并发或排队重放
每一个中间宽度。若在途 job 的有效字格已经过期，`NextFrameLatestRetarget` 在下一 animation frame
取消剩余工作，并通过同一个 coordinator 直接改算最新 target；同字格变化不取消，也不设置固定等待。
最大版心 snapshot 的精确宽度边界与 typography signature 仍是独立 invalidation，不能因为有效字格
相同而跳过。

`ResponsiveNativeBacking` 要求跨字格后在最早安全信号内先 destroy 当前固定断行 DOM，恢复整 root 的
semantic source。viewport resize 在浏览器 resize task 内、paint 前同步完成；只有
`ResizeObserver` 才能发现的纯容器变化在下一 animation frame 的 leading edge 完成，避免在 observer
delivery loop 内改变祖先高度。恢复后的 source 会立即按宿主 CSS 响应新宽度，避免旧 Tiqian 行继续
作为下一轮排版的 backing。
随后 `ParagraphAtomicRelayoutCommit` 把 shaping / layout 放在约 8ms budget 的 animation-frame slices
中，按 viewport 距离逐段原子提交。每段开始前读取 live 有效行长；若 root 在作业期间跨格，element 在
下一帧取消剩余工作，destroy 已提交段落并从最新 source 重新开始。低层 `TiqianWeb.relayout()` 在旧
rendered backing 上准备单段 replacement，但 `ParagraphCurrentMeasureCommit` 要求 commit 前的 live
有效行长仍与准备值完全相同；即便只落后一个字格也不得提交。输入最终稳定后必须收敛到最终字格；
不能保留固定宽度溢出，也不能让一次取消永久遗漏尾部段落。

snapshot、runtime 与 native source 之间采用 `AtomicSnapshotNativeTransition`。异步加载 runtime 与字体
时，当前 snapshot / rendered DOM 继续留在 live tree；真正开始 width fallback 前一次恢复完整 native
source，随后由 `ProgressiveParagraphEnhancement` 视口优先逐段接管。snapshot 验证失败、
离开最大版心，以及命名为 `InlineCloneDecorationBreakUnsupported` 的宽度相关 capability retry 都遵守
同一恢复规则：异步资源就绪前保留当前完整 backing；开始 runtime 接管后，每段只在自己的原子 commit
中切换。`InvalidWebShapingAdvance` 等稳定 issue 继续让对应段落保持 native，只重排其他可增强段落。

初始最大版心允许 `MixedSnapshotRuntimeCompletion`：通过全部证据校验的 keyed 段落保留 snapshot DOM，
同 root 内未 keyed 的 runtime-eligible 段落从各自 semantic source 进入 Kotlin pipeline；两类段落的所有权
互不重叠。只有 keyed canonical 段落可以假定 server replay 完整并进入 prepared DOM；unkeyed completion
按 shaping run 混用 exact replay 与 browser fallback，避免普通字符的 replay miss 连带丢失只能由服务端
证明的破折号字形。任何 width / typography invalidation 都先分别恢复 snapshot 与 runtime 持有的 source，
再让 runtime 从完整 native backing 重排，禁止把已排 DOM 当成另一条 pipeline 的输入；若取消后 maximum-
measure snapshot 仍有效，则只重启 unkeyed completion，不能把 keyed snapshot 误当成整根已经完成。

若在途 job 准备期间 typography attribute 或相关 FontFace 发生变化，
`ResponsiveTypographyCommitCancellation` 使旧 typography 结果失去提交资格；新 signature 作为 latest
target 重新 lower。typography 与 width refresh 都先恢复 native backing，再按视口优先逐段接管；root
字体、行高与版心 contract 必须在第一段提交前统一，避免渐进期间出现可见样式参差。

### `CssTextAsCrossCheckNotDependency` —— CSS Text 4 是快路径不是依赖

`text-spacing-trim` / `text-autospace` / `hanging-punctuation` 支持时,可对**与宽度无关的**
标点半宽 / 中西间距走纯 CSS 快路径(零 span);不支持(Safari / Firefox 现状)则落到引擎烘出的
span / thin-space 兜底。引擎标注是**跨浏览器真相来源 + 通用兜底**,CSS 只是 Chromium 上的优化。
契约与 `halt` 同构:有则精修、无则降级。**CSS 一律不碰断行**。开发期可拿引擎几何对拍
`getBoundingClientRect`、dump「浏览器是否同意」,保留可解释性。

一旦进入引擎烘出几何的路径，`EngineOwnedPunctuationSpacing` 要求接管后的 flow 与 shaping
boundary 显式使用 `text-spacing-trim: space-all`。否则支持 `normal` 上下文标点收窄的浏览器会
先压缩一次 `」、「`，DOM renderer 又按 `LayoutResult` 压缩一次，形成双重压缩。纯 CSS 快路径
与引擎几何路径只能二选一，不能同时生效。

### `CopyTransparentSpacingSpans` —— 复制仍守源忠实

行边界是 flow 内的显式 `<br>`，软换行本身不进入复制文本；display substitution run 用
`data-tq-src` 还原源码，
强制换行另带隐藏 source marker，因此 `<br>` 复制为一个换行而自动折行不产生换行。选中 /
复制拿回的是源文本(ADR 0037)。U+200B 自身不画，但作为零宽 source marker 进入同一
`data-tq-src` 通道，复制不能把 `A.\u200B.\u200B.Complete` 静默改成 `A...Complete`。

`AccessibilitySoftWrapExclusion` 要求视觉软换行的 `<br>` 同时带 `aria-hidden="true"` 与
`data-tq-copy-ignore="true"`；它既不是 source newline，也不能被无障碍树读成停顿。只有
`MandatoryBreak` 的 `<br>` 保留可访问的换行语义。动态 runtime DOM 与构建期 canonical DOM 必须
输出同一契约，变更 canonical 属性时同步升级 render revision。

document-level handler 只在 selection 与 `[data-tq-rendered]` 相交时接管；站内其它文本必须继续走
浏览器原生 copy。`SourceFaithfulSemanticClipboard` 对接管的 selection 同时写入两种 payload：

- `text/plain` 按宿主 block 边界加入段间换行，保留真实 `<br>`，删除软折行和仅用于绘制的连字符；
- `text/html` 保留 `p`、`a`、`strong`、`em`、`code` 等宿主语义，同时 unwrap engine geometry、
  删除 `data-tq-*` 与引擎注入的 flow style。

因此跨段复制不能再退化成 `DocumentFragment.textContent`，也不能因为安装 Tiqian 而把所有站内复制
全局降成 plain text。

## Consequences

- 推入推出 / 邻行均摊 / 避头尾在 web 上与 Compose **同源同模型**,不被浏览器策略稀释。
- SSR 正文始终先可见；客户端按视口优先逐段原子接管，宿主 CSS / SEO / Pagefind / no-JS 路径不需要为
  Tiqian 重写一份。
- **真损失**：layout-owned 的 `Cluster.glyphInlineShift` 可由 DOM spacing 忠实表达；
  但 shaper-owned 的逐 glyph `Glyph.x` 校正（例如任意低质字体 ink 微调）仍无法在普通
  文本 DOM 中重放，记为具名降级 `PerGlyphInkShiftUnavailableOnDom`。
- web adapter 的 dump 与 golden 复用现有结构化 dump 通道，普通正文使用
  `OffscreenMeasureTextShaping`；中文两字破折号使用 `HarfBuzzWebFontData`，并携带
  resolved face / script / language / strategy / feature evidence / capability issue。

## Alternatives considered

- **canvas 渲染**:引擎全权、与 Compose 像素一致,但丢文本选择 / 无障碍 / 复制 / 原生 reflow /
  SSR。对正文是错的取舍。否。
- **DOM + CSS Text 4 一把梭(浏览器折行)**:最省事,但排版模型退化成「Chromium 当前版本怎么
  解释 CLREQ」,丢推入推出、跨浏览器不一致、违背「模型必须真」。否。
- **断词交给浏览器(`hyphens: auto`)**:连字符不受控(不是引擎/CLREQ 那一个、不进 justify),
  且断点两端 kerning 与两行 advance 与引擎度量对不上。见 `EngineOwnedHyphenation`。否。
- **DOM 冻结引擎算好的断点 + x 坐标**:resize 后几何全部失效需整体重发,并未保住原生 reflow,
  反而更脆。被 `ReflowByRebreak`(只重跑折行 + 缓存宽度无关量)取代。否。
- **Houdini CSS Layout API**:理论最优——把断行器注册进浏览器布局树,推入推出跑在**原生 reflow
  内部**,引擎拥有算法、浏览器驱动重排。但 Chromium-only、基本弃坑,不能做主路径。仅作渐进
  增强候选,不阻塞主设计。

## Follow-up

- 完成 `WidthIndependentAnnotationCache`，让 resize 从整段 pipeline 收敛为真正的 rebreak。
- 完成 `OpaqueInlineObjectGeometryInvalidation`，让无固有尺寸或运行期改变尺寸的静态 inline object
  触发重新测量，而不是只依赖宿主宽度 / typography invalidation。
- 用真实站点继续扩充 capability issue 语料；unsupported 内容必须留原生，不能扩大 reduced DOM
  lowerer 后静默丢语义。
- 复用现有 golden:web adapter 的逐标点 advance / ink 侧与 AWT / Skia / Android 对照,分歧入
  `haltValidation` 通道。
- 如果未来更换 core 的实现语言，本 ADR 的前端边界仍然成立：
  `OffscreenMeasureTextShaping` 度量后端与 `PreBrokenLineDom` 渲染边界不变。
