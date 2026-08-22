# ADR 0039: Web 渲染路径 —— 引擎持有行布局,DOM 只画预断行

- Status: Accepted + Implemented (Slice 34-35; 2026-07-11 host integration amendments;
  2026-07-13 canonical prepared CSS + ancestor transform amendments;
  2026-07-14 Web native-list + first-paint + strong opt-in amendments;
  2026-07-15 Kotlin/JS-only runtime + semantic snapshot amendment;
  2026-07-16 server shaping replay + mixed snapshot/runtime amendment;
  2026-07-18 direct SSR / navigation transport + progressive proof amendment;
  2026-08-20 native precompute migration pointer, see ADR 0050)
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

2026-08-20 追记：[ADR 0050](0050-native-precompute-rust-bindings.md) 把 Node precompute 迁往
Kotlin/Native 静态库加 Rust 绑定，HarfBuzz 改为原生依赖，precompute 迁入独立的
`@tiqian/precompute` 包。本节的 WASM 依赖描述适用于迁移完成前的发布。浏览器路径不受影响。

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

浏览器复核采用 `ExactFaceGroupContractValidation`：同一 family / weight / style / stretch 的 probe
先合并为一个 face group，CSS face descriptor 与 `unicode-range` 覆盖只按 group 校验一次；组内每个
probe 仍分别校验 feature signature 与可见 advance，不能用分组省略逐项几何证据。覆盖判断以已经
排序的构建期码点集合和 CSS range 做区间相交，禁止为文章中的每个 shaping probe 重扫整张覆盖表。
这既保持 exact 契约不变，也避免 JIT 被禁用时把文章级验证放大成重复的主线程长任务。
首次证明本身协作让出主线程，并在每个 face group / probe batch 之间检查 lifecycle generation；它不会
等待用户停止滚动才开始，也不会让已过期导航继续完成证明。需要把 client template 接管进 live DOM
的路径采用约 8ms budget；`server-dom-v1` 已经把精确 SSR DOM 作为可读正文交付，不存在等待 takeover
的理由，因此 `DirectSsrBackgroundProof` 采用更短的约 4ms budget，并在 animation frame 之后以
background task 继续验证，避免 Edge 关闭 JIT 时证明 continuation 与滚轮帧争抢。异步字体 session
建立后的复核只比较 manifest identity 与相关 `@font-face` 原始 descriptor signature，不重复执行
已经通过的整组 Canvas probe。session cache identity 使用 manifest 中 public URL 解析后的字体 URL
集合，而不是会随同站路由变化的 `document.baseURI`。

`LayoutSnapshotContract` 与 `ExactFontReplayContract` 是两个所有权不同的证明。前者由 snapshot
adoption 校验候选集合、source / semantic digest、宿主 typography、有效宽度和 prepared DOM 几何；
后者只校验 manifest/revision、CSS face/source/coverage、浏览器 advance probe 与异步前后的 manifest
identity。宽度 miss 或 mixed completion 进入 runtime 时只能复核后者，不能为了建立 shaping session
再次遍历整篇的 snapshot source 与 layout-only typography。runtime replay lookup 继续以完整的实时
`ShapingInput` 为 key，因此拆分验证不放宽错误内容消费服务器证据的边界。低层同步 API 可以显式
选择浏览器度量 fallback；custom element 的 exact-session 路径则只接管已有 Worker plan 的段落，
replay miss 或不可序列化的 inline contract 保留原生 DOM 并报告 `ExactLayoutWorkerPlanUnavailable`，
不能偷偷回到导航线程执行 Kotlin/JS。

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
若调用方只传入 `status=conforming` 却没有建立可消费该证据的 exact session，Canvas 路径报告
`ConformingCjkDashRequiresExactFontSession`；不能把这类状态自相矛盾地归入“没有合格字形”。

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

因此 `styles.css` 是 DOM replay 的显式 capability，不是可选外观。npm command API 与 custom
element 必须等它加载完成后才接管；直接调用 Kotlin runtime 的宿主必须先加载同一文件，缺失时低层
API 报告 `MissingSharedRuntimeStyles` 并保留 source DOM。构建期 prepared DOM 在 JavaScript 启动前
已经可见，`renderSnapshotBundle().initialStyle` 必须内含同一份共享规则，不能只输出动态 value CSS。

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

Web API 显式传入 `fontSize` 时，它不是只供 layout 测量的隐藏参数：runtime 必须先把该字号投影到
source paragraph，再采样所有 descendant computed style，并在增强存续期间保持同一宿主字号；destroy
按原 priority 恢复。否则基准 run 按 option 测量、继承字号的链接按宿主旧值绘制，会形成两个坐标系。
未传 `fontSize` 时仍以宿主 computed style 为单一来源。

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
吞掉这些结构宽度。2026-08-14 起同一 span 还携带通用 outer-spacing contract：独立 inline box
默认以 Narrow 首尾边界进入 `InlineBoxOuterAutoSpace`，不再按 code、pill 或宿主标签逐项补间距；
纯测量 wrapper 可选择 `Source`。相对定位/普通长度 `vertical-align` 从 computed style 读取为显式 baseline shift；
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
runtime。custom element 的 connected / disconnected 生命周期负责 enhance / detach；仍在 document 中的
重排才走 source restore / destroy。detach 只取消任务并释放 document-scoped style，source backing 由
weak state 保留到同一节点重连或随节点回收，不能为了即将被路由器丢弃的旧文章同步重建整篇 DOM。
因此 Astro / Swup 等宿主不需要理解 Tiqian 内部状态或猜构建产物 hash。发布 allowlist 必须包含
Gradle 生成的 `runtime/tiqian-web.js`；仓库内 build helper 不是安装后可执行的 CLI，不能以一个
依赖仓库 `gradlew` 的伪 `bin` 入口发布。

`ReversibleDisabledEnhancement` 把 `<tiqian-prose disabled>` 定义为原生 Boolean attribute 生命周期，
而不是 CSS 可见性或宿主 DOM 重建约定。初始存在时保留 semantic source，不采用 snapshot、不加载
runtime、不建立字体或几何 observer；运行中增加时取消所有代际化任务、恢复 snapshot/runtime source、
释放 exact-font session 与 document-scoped 状态。移除属性后从同一 semantic source 重新进入完整连接
生命周期，并可复用仍已注册的 snapshot。URL、localStorage、rollout 等偏好来源属于宿主，只能把最终
状态投影到 `disabled`；通用 element 不读取或持久化宿主策略。SSR 已经传输的 inert snapshot 不因
客户端关闭而从 HTML 消失。

嵌套 root 以最近的 descendant root 为所有权边界：外层 `enhance()` 不得再次 lower 内层 root 的
段落，`enhanceAll()` 则让每个 root 各自接管直接作用域。这样局部 widget 与整篇正文可以同时使用
Tiqian，而不会产生双重渲染或相互 destroy。

### `ProgressiveParagraphEnhancement` —— SSR 先可用，视口优先逐段接管

Kotlin/JS runtime 内部的 `TiqianWeb.enhance()` 在 runtime 已安装后同步完成一个 root；ESM package 的
`enhance()` 返回 Promise，因为它必须先等待 runtime、stylesheet 与按需字体能力准备。custom element
默认走 `enhanceProgressively()`。
exact-session 候选先按与 viewport 的距离排序；主线程只 lower DOM 并序列化 immutable layout input，
Lookahead layout 在 module Worker 中消费服务端 replay。Worker 全部准备期间 source DOM 保持可读；
generation 变化立即废弃旧导航的请求与 plan。随后主线程在约 8ms 的 animation-frame budget 内分批
提交 prepared DOM，每段在同一 callback 内原子替换自己的 children；尚未轮到的段落继续显示响应式
SSR DOM。调度不会等待滚轮、触摸或 scroll 的“安静窗口”——计算不占主线程，commit 自身受 slice
budget 约束，输入只与普通 frame 调度竞争。Worker 不可用、replay 缺项或 prepared DOM 复核失败时，
custom element 保留该段 native source；禁止以同步 Kotlin/JS 或 browser-metric relayout 作为隐形兜底。
root 级 exact font family、宿主字号、行高与 content width 在接管前已经统一，因此中间帧可以混合
native / Tiqian 段落，但不能出现字体、行高或版心参差。断开 root 会取消待执行 callback，却不改写
已经脱离 document 的 DOM；同一节点重连时才从 weak backing 精确还原。完成事件同时报告总耗时与
最大单 slice 耗时，避免只看 bundle 下载大小而忽略主线程任务。

`WorkerCandidateSetMatchesCommitSet` 要求 Worker 准备集合与随后 Kotlin runtime 实际访问的集合相同：
mixed snapshot completion 传入明确的 unkeyed selector，只准备该子集；完整 width / typography fallback
没有显式 selector 时则使用 `p, li`，与 runtime 默认段落集合一致。snapshot manifest selector 只描述
keyed 构建产物，不能在完整 fallback 中复用，否则未 keyed 的上标、富文本等可支持段落会永久缺少
Worker plan，并被误报为不可接管。

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
cluster advance、locl 字形、基础 autospace、标点原子与几何账本等宽度无关量由引擎内部的
`WidthIndependentAnnotationCache`（默认 `LruWidthIndependentAnnotationCache`）缓存，resize 时
重排跳过 font resolution、shaping、autospace 与 punctuation atomization 阶段，直接基于已注记数据
进行字格量化、断行与 justify。结合 Web 端全局 `WebCanvasTextShaper` 测量缓存，保证了跨端跟手响应。

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

client template 的 source / digest / typography / 字体证据在 commit 前复核两次。随后
`ProgressiveSnapshotCommitProof` 先发布 provisional snapshot owner，每段 prepared DOM 写入后立即完成
该段 live geometry proof，再协作让出主线程并处理下一段；禁止整篇 commit 后才触发一次 full-tree
layout flush。任一段失败、resize、导航或新一代 adoption 都只在 owner 仍属于该作业时恢复整批 source，
不会留下半接管 DOM，也不会让旧作业拆掉更新作业已经安装的内容。直接 SSR 不替换正文，但同样分片
捕获 immutable semantic backing，并只在整批捕获完成后原子发布缓存。

prepared semantic inline 若采用与段落不同的 exact face（例如有明确等宽字体的 inline code），使用
`ExactInlineRenderFontProjection`：构建期 text span 同时生成 artifact-owned render-family projection，
稀疏 geometry run 以 package value style 重放该别名，宿主 `<code>` / `<sup>` 元素及其盒模型不变。
`BuildFontFace.sourceFamilies` 明确把宿主 CSS alias 映射到 package-owned render family，不能假定 CSS
family 必然等于 OpenType name table。几何校验以 `InlineVerticalStyleGroupConsistency` 比较同一
font/size/weight/vertical-align 组的 fragment top；较小 code、上标与已建模 baseline shift 属于不同组，
但仍由共同的 line marker、baseline sentinel、segment advance 与 paragraph height 约束。

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

## Amendment (2026-08-14): semantic technical-break parity

Browser runtime lowerer 将 `<a>` 与 `<code>` 的投影 range 统一送入核心
`LineBreakSpan(ProgressiveTechnical)`；exact-font Worker request、缓存 key 与 Kotlin/JS precompute ABI
必须序列化同一字段。构建期 precompute 直接从已规范化的 semantic spans 派生该字段。浏览器仍只
重放核心给出的 cluster、断点和 spacing，不启用 `word-break`、`overflow-wrap` 或 `hyphens:auto`
作为第二份布局真值。

## Amendment (2026-08-14): native inline-code continuation decoration

Web 不为逐角 1 px / 3 px 圆角拆分一个跨行 `<code>`。源元素继续以一个
`ContinuousSemanticFlow` 节点跨过核心插入的软换行，并保留宿主的 computed
`box-decoration-break`；默认 `slice` 因而在延续侧形成方角，真实首尾仍由宿主的圆角样式决定。
这与 Compose 的 1 dp 延续圆角不是像素同形，而是 Web 保留 hover/focus、伪元素、border、padding
和动态 CSS 的明确平台取舍。`clone` 在窄行需要复制盒模型，仍按既有 capability 契约回退原生，
不能用多份伪语义元素冒充支持。

## Amendment (2026-08-18): atomic commit, same-grid retarget, per-slice stale guard

Firefox profile（拖动 width-slider，25 个 `<tiqian-prose>`）显示：每次 relayout 的逐节点
`removeChild` / `appendChild` 让每段产生约 44 条 mutation 记录，每条记录附带一次 Firefox
a11y 树同步与父进程 IPC；快速拖动下累计为内容进程 94k marker、270–550 MB/s 分配流失与
365ms eventDelay 峰值。本修订调整三处提交与守卫的粒度：

1. **`AtomicParagraphDomSwap`**：renderer 先把全部行盒构建进 `DocumentFragment`，再对宿主
   段落执行一次 `replaceChildren`。构建期间不读布局量，几何全部来自 `LayoutResult`，
   所以交换是纯 DOM 写。每段 mutation 记录从约 44 条降到 2 条，并且消灭「旧行盒已拆、
   新行盒未接」的裸 DOM 闪变窗口。异常路径的 rollback 仍逐节点恢复；该路径执行频率低，
   不计入 mutation 预算。
2. **`SameGridRetargetWithoutRestart`**：`LineLengthGridResponsiveInvalidation` 的同字格
   零作业语义延伸到在途 job。responsive relayout dispatch 使用 `captureSignatures:false`，
   捕获到的签名为空，原来的比较逻辑因此会在每次宽度事件时取消在途 job。现改为与最近一次
   完成提交的量化 measure 比较：宽度仍在同一字格时任务继续跑完，未变化段落由
   `ParagraphLayoutPreparation.Unchanged` 零成本跳过；宽度跨入新字格时才取消任务，
   并按最新宽度重启。
3. **`StaleMeasureGuardPerSlice`**：555a956 删除了逐段宽度守卫，因为该守卫在每段提交后
   读一次布局，读与写交错，是 profile 中 910 次同步 reflow 的直接来源；删除后 `job.stale`
   只在收尾求值，任务中途跨格时过期段落按旧宽度提交，违反「即便只落后一个字格也不得
   提交」。本修订把守卫放回 **slice 头部**：每个 animation-frame slice 开始时求值一次
   `job.stale()`，root 量化 measure 与 job 目标 drift ≥0.5px 即判定过期，跳过本 slice
   剩余 item 并按 stale 收尾，由 element.js 以最新宽度派发后续 job。读取频率从每段一次降为
   每 slice 一次，并且发生在两批 DOM 写之间，不再与写交错。同步首片提交时使用的宽度就是
   当时的实时宽度，符合 `ParagraphCurrentMeasureCommit`；首片之后的漂移由逐 slice 守卫拦截。

## Amendment (2026-08-18): offscreen debounce with visibility wake and kill

coordinator 原先对离屏元素只做降优先级，快速拖动时视口外的段落仍每帧消耗 8ms 预算。
`OffscreenDebounceGate` 改为：离屏元素的请求不立即执行，先挂起等 200ms；等待期间该
元素再来新请求就重新计满 200ms。这样快速拖动时视口外的区块不会跟着每次宽度变化重排，
只在宽度稳定后执行一次。挂起到期后任务照常进入每帧循环；元素回到视口时立即执行；
`cancelFrame` 与 `unregister` 会同步清掉该元素还在挂起的任务。在屏元素的请求不受
影响，照常执行。

挂起队列初版按元素只保存一个待办任务，后来的请求会覆盖先前的。页面初次排版期间的
一次视口变化会让视口外的区块被 IntersectionObserver 判为离屏，这些区块刚排入的初次
排版请求因此被挂起。紧接着 ResizeObserver 报告宽度变化，每个区块又请求一次响应式
提交，新请求把初次排版请求从挂起队列里覆盖掉。顶替它的提交任务运行时发现区块尚未
排过版，按设计直接返回；初次排版请求已经不存在，这些区块从此不再有任何排版。修正
（`OffscreenRequestQueue`）：挂起队列按元素持有一组待办任务，以回调为 key。到期、
回到视口、取消三种操作都只影响组内对应的单个任务，同一区块的多个请求互不覆盖。

`OffscreenLayoutWorkKill`：IntersectionObserver 观察到可见→离屏且元素 busy 时，复用
`tiqian:cancel-layout-work` 通道停止在飞 slice。取消操作不会回滚 DOM，已经提交的可见
成果保持不变。元素从离屏回到可见时，既有的 pending-responsive 分支会立即拉起其挂起的
工作，与挂起队列的立即执行一起完成唤醒。两处逻辑集中在 coordinator 与
IntersectionObserver 转换分支中，没有散落各处的独立计时器。

挂起是否到期取决于**每个元素自身的宽度**是否稳定。快速拖动中，某个离屏 root 的宽度
可能因视口宽度封顶或列宽上限而提前稳定，其 ResizeObserver 不再交付变化；200ms 等待
从最后一次真实宽度变化起算，期满后该元素完成一次最终布局。同一手势里宽度仍在变化的
元素继续等待。drag 测试的违规判据是：某次离屏 relayout 完成时，距该元素最后一次宽度
变化不足 180ms。

## Amendment (2026-08-18): fractional fragment-aware content measure

555a956 把 `elementContentWidth` 改为 `clientWidth` 快路径时引入三个回归：整数舍入带来
最多 `0.5px` 的误差，小数宽度上跨字格边界的变化可能被吞掉，违反
`LineLengthGridResponsiveInvalidation` 的小数语义；stylesheet 声明的 padding（如
`li { padding-inline-start }`）对 inline style 探针不可见；`getBoundingClientRect()` 在
CSS 多列容器上取所有 fragment 的水平并集。现恢复 fragment-aware 实现：取
`getClientRects()` 中最宽的 live fragment 作为单一 fragmentainer 的 border-box，减去
computed padding 与 border。`elementFragmentBorderBoxInlineSize` 仍为 plain gBCR，仅用于
≥0.5px 的粗粒度 drift 检测，整数级舍入误差在该容差下无影响；该函数注释与实现的不一致
是历史遗留。

## Amendment (2026-08-18): coordinator-owned polled scheduling

前两处修订落地后，快速拖动仍暴露三层缺陷：stale 收尾会把已提交段落整批回滚成
   native，造成裸 DOM 闪变；离屏挂起会在宽度仍在移动时到期；被取消任务夹带的
   bare 段落无人补齐。
三层缺陷同出一源：调度权分裂。Kotlin job 自排 animation frame，element.js coordinator
又按自己的节奏派发，两边对「同一帧内谁先谁后、宽度何时算稳定」各有一份判断。
本修订把调度权收归 coordinator。

1. **`WorkerPolledScheduling`**：custom element 在派发 progressive job 前 attach root，
   job 的每个 slice 都由 coordinator 授予。coordinator 每帧轮询：读每个 root 的
   job generation（第几代 job，每次派发新 job 递增）与三层 pending 计数，按 tier
   授予一个有界 slice，再用共享 IntersectionObserver 把段落可见性换算成 tier 写回
   job。授予的单位是一张凭证：一个 controller 对象，只发给一个收件人（已实施形态见
   「调度架构弱点留档」第 2 条）；其余参数与返回值都是 primitive。`ParagraphTierGating` 把段落分为在视口、近视口、
   远三层；`TierOrderedGrants` 让所有可见 root 先排干 tier 1，再 tier 2 与 tier 3；
   视口内正文优先。`OffscreenWorkerDebounce` 让离屏 root 拿排版凭证前也等满同样的
   200ms。coordinated job 的第一个 slice 同样来自第一张凭证，可以与 dispatch 任务落在
   同一帧，共用同一帧预算。
2. **`RunToCompletionWithoutCoordinator`**：standalone rAF 自调度路径整体删除。无
   coordinator 的 root 一口气同步跑完，低层 API 直调与测试直接驱动都走这条路；detach
   发生时，仍有剩余 item 的 job 同样同步跑完再返回。正常部署中 coordinator 必然存在；
   保留第二套调度只制造时序 bug。
3. **`StaleFinishKeepsCommittedParagraphs`**：job 以 stale 收尾时不回滚已提交段落。
   逐 item 提交守卫已保证每个落地的段落与当时的实时量化 measure 一致；把整批回滚到
   native 只会在跨帧、跨宽度变化的 job 上制造闪变。stale 事件仍照常派发，element.js 以
   最新宽度派发一次后续 job。
4. **`StrandedEnhanceResume`**：relayout job 的工作集并入「候选集合中存在、state 中没有」
   的 bare 段落，bare 走实时宽度路径、rendered 走快照准备路径，同一 job 内混合推进。
   任务取消后段落不会永久遗漏。
5. **`OffscreenTrailingWidthCheck`**：ResizeObserver 的交付挂在 animation frame 边界；
   coordinator 无任务时帧循环停摆，宽度变化停止送达，离屏 200ms 挂起可能在宽度仍在移动时
   到期。放行 commit 前同步读一次实际宽度，确认宽度确已静止；仍在移动则刷新基线并重新
   进入挂起等待。
6. **`ClockTierDiscipline`**：帧预算 deadline 读 `performance.now`。rAF 回调参数是帧起点
   时间戳，长帧内回调执行时它早已落后；以它起算预算窗口会让整段拖动中一张凭证都
   发不出去。当时跨边界传的是剩余毫秒数，Kotlin 侧在自己的 `Date.now` 时间线上量测
   耗时，两条时钟不做比较；后续 GrantController 修订改为携带换算到 `Date.now` 域的
   截止时间戳，两条时钟在构造凭证时对齐一次。200ms 级防抖到期时间与时长统计同用
   `Date.now`，毫秒精度足够。

## Amendment (2026-08-18): skip discarded finish reads

2026-08-18 的 Zen profile（快拖，172 次字格穿越）把最大单一可归因项定位到
`fragmentedBorderBoxInlineSize`（gBCR）23.1%、1483ms：每个 relayout job 完成时
`#finishLayoutWorkAndObserve` 对 root 内每段读一次布局签名。审计发现这些读取没有消费者：

1. 宽度移动中的 relayout finish 走 responsive-commit 分支，该分支不存储任何段落 baseline。
2. relayout job 以 `captureSignatures: false` 派发，`#layoutWorkMeasureSignature` 为空串，
   live 签名与空串比较恒为真，`layoutInputsChangedDuringWork` 的判定不需要 live 读数。
3. 比较结果与签名值都被丢弃；每段一次 gBCR 加一次 getComputedStyle 花在 job 刚弄脏的
   DOM 上。commit 任务在宽度移动时本就使用缓存 baseline，拖动全程没有任何路径消费该读数。

**`ResponsiveFinishSkipsDoomedSignatureReads`**：finish 只在两种情况下读段落签名：与
捕获签名比较（enhance 路径，`CapturedMeasureFollowUpCoalescing` 语义不变），或走
unchanged 路径存储 baseline（宽度静止时的收尾一次读完）。宽度移动中的 finish 以缓存
baseline 进入 responsive-commit 分支。finish 无条件的 typography 签名刷新保留，它是
settle 后 commit 比较的基准。

demo CDP burst 基线（1500×6000 视口、12 root 全可见、900ms 逐帧宽度振荡）：段落 gBCR
读取从 610-624 降到 335-419；`drag-responsiveness-metrics` 以 500 为预算固定该行为。
后续 enhance 停摆修复让 burst 内完成次数接近翻倍，绝对预算随机器吞吐漂移，2026-08-18
改为按完成次数归一（每次完成 gBCR ≤ 4、gCS ≤ 24，实测基线 3.0 与 18.2），被固定的
行为仍是 finish 路径的单次成本。

## Amendment (2026-08-18): coordinator 不再预估排版耗时

coordinator 每帧做两件事：跑回调队列里的轻量任务（派发排版作业、提交几何变化）；
给已挂载的区块授予排版切片。每次授予一张凭证（一个 GrantController 对象：收件人、
job generation、换算到 `Date.now` 域的截止时间戳、段数配额），排版循环每排完一段问
一次准入，至少排一段。

初版在此之上还维护一个全页共享的「切片耗时估计」（滑动平均）：授予凭证前先按估计值
预判这次切片会不会超出帧预算，会则不授予；帧预算下限与轻量任务的让路判断也都参考
它。帧级追踪（`__tqFrameTrace`）证实这套预判会失效：冷启动的一个慢切片把估计值抬过
帧预算后，发放凭证的门槛在预算远未耗尽时就一直成立，所有区块一张凭证都拿不到，只剩
「连续两帧毫无产出」的兜底通道，节奏退化成三帧排一段。估计值全页共享，一个慢切片
惩罚所有区块。

决定：删除整个预估层，coordinator 只切分帧和排序。

1. `RefreshAnchoredFrameBudget`：帧预算每帧由实测帧间隔直接算出
   `clamp(帧间隔 × 0.4, 2.5, 6.0)`，不随压力事件调节。帧来得晚，截止时刻不变，
   能装的工作自然变少。
2. `DeadlineGate`：发不发凭证只看真实时间，预算耗尽即停。兜底改成结构性的：一帧里
   轻量任务与凭证发放都毫无产出时仍发放一张，保证再慢的切片也有前向推进。
3. 删除切片耗时估计、三处预判消费点、压力反比调节与连续空转帧计数。轻量任务的
   让路只看已耗时间，每帧第一个任务恒执行。

排版循环内部的时间治理不变：每排完一段问一次凭证携带的准入条件，到限即停，至少排
一段，`MAX_PROGRESSIVE_SLICE_MS` 与 `MAX_PROGRESSIVE_ITEMS_PER_SLICE` 仍是无协调
路径的上限。分工固定为：coordinator 决定每帧给排版多少时间、给谁；排版循环决定这段
时间怎么用。

## Amendment (2026-08-18): 调度架构弱点留档

2026-08-18 调度重构（轮询调度、预算层拆除、挂起队列修正）期间的讨论收敛出三个
长期架构弱点。每个弱点写清它在现行实现里的形态、已处理的部分、剩余部分要什么
证据才值得动。

1. **调度者与被调度的工作在同一条线程。** 排版计算、DOM 提交、布局量读取、浏览器
   回流、coordinator 的帧循环全部在主线程。coordinator 用帧预算分时，但分时者自己
   也在被分时的线程里：宿主脚本的长任务会挤掉帧循环，被挤之后 rAF 回调参数（帧
   起点时间戳）在回调真正执行时早已落后，就是这条链的实例（`ClockTierDiscipline`
   已处理时钟一侧）。预算层拆除后 coordinator 不再依赖跨帧历史做预判，帧晚到时
   截止时刻不变、装得下的工作自然变少，这条链上的连锁失效少了一层。剩余部分：
   主线程被宿主长任务占满时排版整体让路，没有机制能抢回时间。根治方向是把排版
   计算挪进真 Worker，请求与结果都是纯数据，`worker-layout.js` 的快照排版已是
   雏形；代价是 Worker 内拿不到 DOM 与计算样式，度量正确性只能靠构建期证据链
   （ADR 0040）。这是独立的 ADR 级决策，本文件不预设结论。

2. **取消与预算的最小作用单位是整个段落。** 排版作业按段落推进：断行、准备、
   DOM 提交对一个段落一次做完，停止检查只在段落之间生效。段落成本方差很大：
   实测短段不足 1ms，首次 enhance 的长段 5 到 20ms，单个超重段落可以吃掉整帧
   预算，帧的截止时间拦不住进行中的那一段。

   「该不该停」的判断当时有两份副本：coordinator 发放凭证前比较 deadline 与
   performance.now，排版循环在每个段落后比较 sliceDeadline 与 Date.now，后者
   的数字来自发放时传入的剩余毫秒。两份副本可能给出不同答案。预算 deadline
   误用 rAF 回调参数（帧起点时间戳）导致凭证长期发不出去的事故就是时钟口径不一致
   的实例，ClockTierDiscipline 修正了时钟选择，副本本身仍待合并。

   讨论收敛的目标形态已于当天实施（GrantController）。停止检查收拢为一个准入判断：
   coordinator 每次发放都构造一张凭证（一个 GrantController 对象）派下去，携带收件人
   root、job generation、换算到 Date.now 域的截止时间戳与段数配额，外加一个
   shouldStop 闭包；闭包只捕获这些数字，不捕获 coordinator 状态。排版循环不认识
   时钟、策略与身份，每个段落边界问一次准入；问题在提交一个段落之后才问，所以
   一张凭证至少提交一段。两份副本就此合并：循环回答问题依据的条款就是凭证携带的
   条款，coordinator 侧的 `DeadlineGate` 只决定是否再发下一张。时间戳换算：每帧
   轮询开头把两个时钟各读一次，得到 offset = Date.now() - performance.now()，帧的
   截止时间加 offset 就换算到 Date.now 的读数上，之后循环内是同一读数上的数值比较；
   两个时钟走速相同的假设与传时长的旧做法共用。配额补截止的盲区：Date.now 截断到
   毫秒，亚毫秒的剩余时间可放行大量廉价段落，配额按段数封顶。job generation 在
   每个 startProgressiveJob 时盖章，凭证携带的 generation 与现行 job 不符时静默
   拒绝，发给已替换 job 的旧凭证不会跑到新 job 上。无 coordinator 的路径（detach
   收尾、未 attach 的同步跑完）在 slice 开头构造本地准入，沿用毫秒与段数上限。
   单线程的事实不变：slice 运行期间收件人的其余状态冻结，循环中途真正推进的量
   只有时间。多个 root 之间的排序、预算切分与前向推进兜底依赖全局页面状态，
   计算留在 coordinator，算出的值随凭证下行，本张凭证的截止与配额就是预算切分的
   产物；全局状态本身不跨线，执行侧零全局知识。

   剩余部分：把检查点下沉进断行循环、让段落做到一半能停且能恢复，仍是替换
   治理模型的 ADR 级变更，只在单段超重场景有收益，demo 规模未观测到失控。
   触发条件：真实页面出现单段超帧的可归因卡顿证据。

3. **每条停止路径必须带上重派义务。** 协议要求：任何取消、挂起、掐死排版工作的
   路径，必须能指出谁负责重新唤醒工作；说不出唤醒者的沉默只允许出现在元素断连
   或宿主显式禁用。2026-08-18 逐路径审计的配对：排版变化取消与几何变化取消在
   取消后显式重排一次几何提交；工作进行中收到新几何需求时记下「需要提交」标志，
   收尾路径与回屏分支都会消费它；离屏掐死在回到视口时清除挂起并按标志重排；帧
   任务挂起 200ms 到期由计时器整桶放行；排版凭证的发放挂起有独立的唤醒计时器，到点
   重启帧循环；两种挂起的唤醒都不依赖新输入到达。断连与禁用的沉默有意。曾发生的缺口：
   挂起队列初版按元素只保存一个待办任务，后到请求覆盖先到请求，初次排版请求被
   宽度提交请求覆盖后永久丢失，即 enhance 停摆事故（`OffscreenRequestQueue` 修正，
   见 offscreen debounce 修订）。新增停止路径时按此协议审查。

## Amendment (2026-08-18): 凭证段数按 root 自适应（AdaptiveGrantQuota）

Firefox 隐私模式录得的纯悬停加滚动会话（零拖动输入、零 relayout 派发）暴露了
GrantController 的盲区：我们的 JS 全程 1.17s（主线程 17.8%），LongTask 却有 55 个
共 5.4s（最大 171ms）；28k 次 a11y 移除中 16k 落在 LongTask 窗口内。提交批次的
原生后续（a11y 记账与 style/layout flush）在 JS 归还后同一个任务内结算，凭证的
截止时间只约束 JS 切片时长，约束不了一段凭证放行多少段提交、带出多少原生后续。

治理对象因此从「每帧给多少毫秒」扩到「每张凭证放行多少段」：quota 从常量 8 改为
每 root 自适应。slot 记录当前 quota，起步 2；上一帧有提交的 root 在本帧头部接受
判定，帧距超过节奏 1.5 倍判慢帧，quota 减半（地板 1）；低于节奏 1.1 倍判健康帧，
quota 加一（上限 8，原常量变成上限）。帧距 ≤ 4 或 ≥ 150 不判，标签页挂起间隙
不惩罚任何人。节奏基准沿用 `RefreshAnchoredFrameBudget` 的 EMA：只吸收快帧，
慢帧不污染基准。

信号选帧距而非切片 JS 耗时，因为原生后续的成本不在我们的 JS 栈下，帧距是唯一
覆盖全账的测量，代价是判决晚一帧生效。与上午拆除的切片耗时估计层有三点区别：
作用在凭证段数不在帧预算，慢帧不再关门所有 root 的发放通道；判定按 root 独立，
一个重 root 收敛到小批，无辜邻居每帧加一爬回；信号是帧距含原生后续，旧估计层
只见 JS 耗时。帧距无法按 root 拆分，慢帧判所有上一帧提交者，这是量测粒度的
代价，由每帧加一的恢复速度兜住。

Kotlin 侧不变：quota 是凭证携带的条款，排版循环照读。冷启动 2、逐帧增减、
地板与上限、挂起豁免、按 root 隔离由 `coordinator.test.mjs` 逐帧断言。demo 的
scroll 套件是灾难级护栏：headless Chromium 的原生后续远低于 Gecko 的逐节点 a11y
记账，实测拆掉自适应后帧距仅 16.8 升到 33.4ms，无法在此环境做灵敏度断言，
方向性验证留在 npm 单测。
