# ADR 0040：构建期 Web 字体证据与最大版心快照

- Status: Accepted
- Date: 2026-07-11
- Amended: 2026-07-14（SSR / browser runtime 共用 exact-font session、render-font family contract
  与 canonical DOM plan；role-aware 弯引号 shaping、shared prepared CSS、compact transport、
  first-paint bundle 与 client-navigation registration）；2026-07-15（browser 与 Node runtime
  迁移为纯 Kotlin/JS，删除 WebAssembly target 与发布产物；受控语义 inline 进入 snapshot；响应式
  SSR 始终保留 native source，prepared DOM 只在 live validation 后原子采用；建模宿主
  `font-variant-numeric: lining-nums` 的 `lnum` shaping / draw contract）；2026-07-16（浏览器
  exact-font backend 改为服务器 shaping / metrics 回放，浏览器不再加载
  HarfBuzz / WOFF2 WebAssembly，并允许已验证 keyed snapshot 与 unkeyed runtime completion 共存）；
  2026-07-18（默认字体所有权改为 host-compatible：构建端直接读取宿主 `@font-face` 样式表，浏览器
  不再下载字体字节或生成 render-family alias；响应式 SSR 始终保留 semantic source；采用与计数验证
  改为可中断的渐进证明）
- Amends: [ADR 0039 Web 渲染路径与真实站点接入](0039-web-rendering-path.md)

## Context

ADR 0039 的 Web 路径在客户端读取 computed typography，用 Canvas 度量，再由同一条 Tiqian
pipeline 断行并生成可选择的 DOM。这个路径在任意宿主 CSS、任意容器宽度下都能诚实回退，
但正文站点通常同时满足两个更强的条件：字体文件随站点发布，桌面正文长期停在同一个最大版心。
此时每次导航都重新下载 Kotlin/JS runtime、重新度量同一批字形并重跑最大宽度布局，是可以避免的工作。

构建期不能为此启动 Headless Chromium。浏览器的系统字体、fallback、CSSOM 与运行机器相关，
产出的结果无法证明来自站点实际发布的字体字节；同时它会把前端 renderer 变成另一份布局事实来源。
服务端需要的不是截图，而是可重复的字体证据与 `LayoutResult` 派生物。

另一个边界必须明确：HarfBuzz 能执行 `liga`、`calt`、`locl` 等 GSUB/GPOS lookup，但当前 core
在 shaping 前仍会把普通 CJK 按码点分段，Latin 的候选断词也可能重新分段 shaping。因此本切片
只能复现**当前 segment 语义**，不能借构建期 HarfBuzz 宣称已经具备完整的跨 run 上下文 shaping。

## Decision

### `ServerShapingReplaySession`：Node 持有 exact HarfBuzz，browser 回放其结果

独立 Node Kotlin/JS 入口读取明确声明的 WOFF2 / SFNT；HarfBuzz backend 负责把 WOFF2 还原为
SFNT、计算 source 与 SFNT SHA-256、选择 face / unicode-range / variation，并建立只读 session。
Kotlin/JS 继续调用 `ParagraphLayoutEngine`，不复制断行、标点 glue、推入推出或 justify 规则。

构建 session 对本 root 实际发生的每个 `ShapingInput` 与 `FontMetricsRequest` 同时记录输入签名和
HarfBuzz / OpenType 结果。glyph advance、placement、ink bounds 与纵向 metrics 除以请求字号后进入
`ServerShapingReplayTable`；`opsz` 等非线性轴本来就不在能力域内，因此同一 weight/style 实例可在
响应式字号下线性重放。多个段落的相同记录在 snapshot manifest 中去重；传输层再把重复的 family、
segment、feature 与 metrics key 收进一张共享字符串表，浏览器在校验索引边界后展开为同一 canonical
replay model，不让 exact evidence 随文章段落数重复膨胀。不同字号除回 em 后产生的 IEEE-754 尾差先
按固定精度 canonicalize；同一 replay key 的结果随后必须完全一致，否则构建以
`SnapshotFontReplay*Conflict` 失败，不能把浏览器必然拒绝的重复 key 发出去。

snapshot 未命中并进入 browser Kotlin/JS runtime 时，loader 不再 fetch 字体字节。source / SFNT hash、
face index、descriptor、axis tags、OpenType local names、构建时 `sourceOrder`、HarfBuzz version 与 backend
revision 已属于服务器生成且签名稳定的 replay evidence；浏览器先验证宿主 CSS face inventory、
`FontFaceSet.load()` 与实际 advance probe，再直接从 manifest 建立纯 JS replay session。replay backend 按
实时字号缩放服务器结果，再由既有 `HarfBuzzSessionTextShaper` / `HarfBuzzSessionFontMetricsResolver`
适配给同一个 layout core。因此 miss 后重排仍不换回 Canvas 度量，也不在浏览器启动 HarfBuzz / WOFF2
WASM 或重复下载同一批中文字体分片。
输入 key 缺失、字体证据失效或 live paragraph 超出服务器捕获的受控语义能力域时，具名回到
ADR 0039 的能力边界：低层同步 API 可显式选择普通 browser adapter；custom element 的 exact-session
导航路径保留 native source，不在主线程重新执行 layout。

字体度量从同一个 HarfBuzz face 取得：

- `hhea` 对应的 ascender / descender / line gap 来自 `Font.hExtents()`；
- CJK 字身框每条边优先取 `BASE` 的 `idtp` / `ideo`，缺失时回退 `OS/2`
  `sTypoAscender` / `sTypoDescender`；
- glyph advance、placement 与 ink bounds 来自 HarfBuzz shaping / glyph extents；
- 所有 FUnits 统一按 `fontSize / UPEM` 换成 layout px。

构建端不读取系统字体或 `local()`，未声明 fallback、缺字、synthetic bold/italic、未建模的
`wdth` / `opsz` / 任意 feature 都不是可猜测输入：第一版直接返回具名 capability issue，保留
现有浏览器路径。
第一版也拒绝 font collection / 非零 face index；带 `MVAR` 或 `BASE` VariationIndex 的 variable
font metrics 尚未建模，同样不能把默认实例的静态 table 值当成指定 weight 的度量。

宿主显式声明 `font-variant-numeric: lining-nums` 时，构建 session 把它降为 HarfBuzz `lnum=1`
的段落基准 feature，浏览器按 key 重放该结果；字体 probe 记录实际启用的 `lnum`，live typography 必须仍为
`lining-nums`。这个基准 feature 由段落继承，不进入逐 run 的 prepared DOM feature boundary；弯引号
等 role feature 仍只携带自己的 `pwid,palt`。其余 numeric variant 和任意未建模 feature 继续 fail closed。

### `FontInstanceMetricsKey`：度量缓存必须包含真实实例

`FontMetricsRequest` 的 identity 至少包含 family stack、font size、weight 与 italic。构建端额外以
`sfntSha256 + faceIndex + sorted axes` 作为 `FontInstanceId`。同 family 的 unicode-range 子集只有在
全局 metrics 一致时才可共用一份行高度量；不一致即拒绝预计算，不能把不同实例混进一个 cache key。
为让 fallback stack 的 metrics 与实际 shaping face 同源，请求还携带仅用于 face selection 的 source
text。这个公共 data class 扩展保持 Kotlin 源码默认参数兼容，但会改变 JVM constructor / `copy` ABI；
本仓库仍为 pre-1.0，消费方升级该版本时必须与 Tiqian modules 一起重新编译，不能混用旧二进制。

### `CurrentSegmentShapingSnapshot`：只缓存当前 pipeline 的 shaping 语义

构建端 shaper 对 core 交来的每个 `ShapingInput` 用 HarfBuzz 完整执行该 segment 内的 GSUB/GPOS，
并把 glyph id、advance、offset、ink、missing glyph 与 font instance 写进 evidence。它不扩大 core
给出的上下文范围。完整 contextual shaping 需要另一个 run-first contract：以 font instance / script /
language / direction / features 切连续 run，消费 HarfBuzz cluster 与 unsafe-to-break，并在最终行边界
重新 shaping；这不是本 ADR 的隐含能力。

render plan 也必须保留这些 segment boundary：每个 cell 以原子 inline box 呈现，segment 之间的
adjustment 用 margin 表达，不能为了减少 DOM 再合并成连续 text run。否则浏览器会跨 segment 重新
执行 `liga` / `calt`，形成与构建期 advance 不同的第二份 shaping 结果。

### `RoleAwareCurlyQuoteReplay`：共用码点按 role 选 script / feature

U+2018–U+201D 同时用于中文引号和西文 quote / apostrophe，exact-font shaping 不能只按码点
固定一种字面。`QuotePairAnalyzer` 先按段落上下文决定成对引号的 `FontRole`，同时应用
`LatinInWordApostropheExclusion`：U+2019 两侧都是拉丁单词字符时不消耗外层单引号对。因此
`中‘that’s’中` 的外层引号仍是 CJK punctuation，中间 `that’s` 则保持连续的 Latin run。

`UnmatchedCurlyQuoteDirectionalContext` 补齐不成对但仍有明确语言语境的弯引号：词中撇号
(`that’s`)、尾部所有格 (`James’`)、省略式开头 (`’90s`) 与被截断的 quotation 先看紧邻的
Western 空格和前后有意义的文字 run，再决定 Latin / CJK role。这个规则只增加结构化 role
decision，不补写缺失引号，也不修改 source range；没有任何文字语境时仍保守落到 CJK。

构建端对每个已分段的 `ShapingInput` 使用同一条具名策略，browser replay 以完整输入 key 消费其结果：

- `LatinText` 中包含共用弯引号时使用 `script=Latn` 并启用 `pwid,palt`，以重放西文
  quote / apostrophe 的比例字形；普通 Latin segment 不额外启用这组 feature。
- `CjkText` / `CjkPunctuation` 使用 `script=Hani` 且不启用比例宽 feature；中文引号的
  profile 字身、glue 与 `’，‘` 相邻标点挤压仍完全由 core 决定。

prepared layout wire 为 segment 显式携带 OpenType feature signature；canonical DOM 先以
`font-feature-settings: "halt" 0, "chws" 0, "palt" 0` 锁住普通 CJK 标点的全宽 shaping。这里显式关闭
`palt` 是因为 Firefox 在 IBM Plex Sans SC 真正加载后会让 `font-kerning: normal` 带出比例标点定位；
标点压缩仍只来自 `LayoutResult`。西文弯引号再只接受已知的 `pwid,palt` 映射，以
`font-variant-east-asian: proportional-width` 与同时保留上述关闭项的 `"palt" 1` 重放西文弯引号。
字体 advance probe、snapshot adoption 和 runtime geometry gate 都把该 signature 与普通标点 feature lock 纳入
证据；未知 signature 直接 fail closed。这一决策只统一当前 segment 内的 measure / draw，不宣称
已实现跨 segment 的完整 contextual shaping。

`LayoutResult → PreparedParagraphV1` 的 JSON lowering 位于共享 layout 模块；Node snapshot serializer
与 browser server-replay runtime 再共同调用同一个 `prepared-dom.js` lowering。line marker、稀疏
geometry / feature boundary、hyphen、hard break、`br` 与 sentinel 的节点和属性必须同构，不能继续由 Node JS 与 browser
Kotlin renderer 各维护一份实现。

`NecessaryGeometrySpanOnly` 要求普通连续正文直接序列化为 Text node；只有间距、display substitution、
OpenType feature 或宿主语义确实需要独立边界时才生成 span。单字符与可合并 run 的正负间距优先使用
进入原生选区的 `letter-spacing`，只有多字 run 的负重叠才使用 `margin-right`。因此 prepared SSR 与
runtime 重排都不能为了逐 cluster 记录证据而退回每字一个 `inline-block`，选区必须保持连续。

canonical plain prepared DOM 的静态 reset / display / white-space 声明也是这个共享 lowering contract
的一部分：它们收敛到发布包 `styles.css` 的受限 selector，不再在每个 marker、sentinel、hard
break 或 hyphen 节点上重复。

行高、baseline offset、flow start 与 segment trailing gap 等动态数值采用
`PreparedValueStyleDictionary`：canonical lowering 把相同 declaration 映射成 root 内的短 class，
snapshot transport 只序列化一次 declaration table；采用快照或 browser server-replay runtime 绘制时，
由 `prepared-dom.js` 在 document head 安装一张带 root scope 的样式表。rendered paragraph 不再携带
逐 marker / segment 的 inline style，destroy、原子恢复或退出 exact prepared path 时同步释放作用域。
class、declaration table 与实际 template artifact 都受 render revision / digest / geometry gate 约束；
不能由宿主 CSS 猜测或重建这些数值。

`SharedSnapshotManifestTables` 同样把全页不变的 typography contract 与 font face descriptor 提升到
manifest table。每段只保存 typography ref，以及本段实际使用的 face ref、coverage 与 advance probe；
浏览器解析后再展开为既有 canonical validation shape。这样不改变每段证据，也不再把完整
unicode-range、字体 hash、local names 和 typography 重复写入每个 entry。table reference 越界、
版本冲突或 digest 失配全部 fail closed。

canonical plain flow 使用 `line-height: 0` 消除宿主 root strut，让 `LineMetricStrut` 独占每行的
ascent / descent / baseline；否则即使两端 HarfBuzz 结果相同，浏览器仍会用自身字体垂直度量把
`LayoutResult` 的段落高度撑大。marker 同时携带 line top / bottom / baseline 与 paragraph height，
采用 gate 逐行验证 marker、baseline sentinel 和最终 content height，renderer 不再持有第二份纵向真值。

### `MaximumMeasureSnapshotCache`：最大版心结果是严格校验的 cache

构建产物 `PreparedParagraphV1` 包含 schema / engine revision、source digest、source semantic artifact
digest、typography contract、exact font evidence、最大 layout width 与由 `LayoutResult` 降出的
line/run render plan。快照接收纯文本、source-faithful mandatory break，以及可安全序列化的受控
semantic inline；链接、强调等以 source range、标签和行为属性进入 artifact，跨软换行仍只生成一个
语义元素。行内代码只有在宿主显式发布 exact 等宽 font face，并把完整字体 span 与 padding box
contract 同时送入真实 layout input 时才可命中；仅有 `monospace` fallback、缺少任一盒边证据或由
集成层私自补字体时，整段具名退出，保留 native HTML/CSS。事件属性、`javascript:` URL、引擎私有
属性、crossing range、ruby / 注音、
opaque inline object、未知伪元素盒、未知 emoji fallback 与破折号 exact-face 特例仍具名退出快照。
为与 core
当前 classifier 及窄屏 browser fallback 同构，v1 固定 `zh-Hans` 与 line-length grid，只接收 Han、
ASCII / U+00C0–024F Latin 及 Common；Bopomofo、Inherited combining mark 和其他 script 均不命中。

默认 transport 始终让原 SSR `<p>` / `<li>` 作为 no-JS、SEO、Pagefind、复制与恢复的事实来源；prepared
HTML 放在正文之外的 inert `<template data-pagefind-ignore>` 中。初始 HTTP、整页 HTML 导航与 page-data
导航都不得只凭站点配置的 maximum measure 直接把 prepared children 塞进正文，因为服务端无法知道
浏览器是否命中了本地字体，也不知道首帧实际 content width。客户端在 live width、source、typography、
宿主 font face 与 prepared geometry 全部验证后，才逐段采用 keyed candidate set。

`renderSnapshotBundle()` 注入 engine-owned geometry CSS、prepared `inertTemplate` 与 compact
`clientTemplate`；不生成字体 preload，字体 CSS、资源优先级和缓存策略继续由宿主负责。同 root 的
unkeyed candidate 保留 native source，由 runtime 按视口优先逐段原子补齐。任一 keyed candidate miss
都不触碰正文，runtime 从完整 native source 开始接管。不得把数百 KB prepared DOM 塞进 page-data
payload，再让浏览器做一次整篇 takeover。
回到最大版心可重新采用仍在 document 中的 inert artifact，并再次只补齐 unkeyed candidate，不必重新下载或在 page data
复制 prepared DOM。若 resize 在补齐过程中取消 captured job、但 maximum-measure snapshot 仍然有效，
协调层必须恢复并重启 unkeyed candidate；keyed snapshot 的存在本身不代表混合根节点已经完成。

### `HostCompatibleFontOwnership`：提椠不改写宿主字体族

普通集成只提供一份现有字体样式表的本地构建路径与浏览器 URL。Node precompute 解析其中全部
`@font-face`，把相对资源 URL 分别解析到本地字体文件与宿主原公开 URL，并按 CSS source order、
weight、style 与 unicode-range 选择构建 face。几百个 CJK shard 不需要逐项配置，也不会被复制、改名或
重新发布到提椠路由。`faces[]` 只保留为生成式字体系统的低层入口，不能与 stylesheet 入口混用。

prepared DOM 与 runtime canonical DOM 均继承宿主原 `font-family`；提椠不生成 `Tiqian Exact …`
`FontFace`、root-scoped render-family 变量或 package-owned family alias。`renderFontFamilies` 仅记录
replay corpus 覆盖到的宿主 family identity，不能成为 CSS 投影。行内 run 只有在宿主本来就声明了另一
字体且集成层提供了对应 build evidence 时才携带自己的宿主 family；提椠不得私自补字体。

浏览器采用前按每个 evidence face 的实际 coverage 调用 `FontFaceSet.load()`，验证宿主 CSS 的 family、
weight、style、unicode-range、原资源 URL 与 local name contract，并用实际 advance probe 证明当前
选中的 face 与构建布局几何兼容。字体加载失败或 CSSOM 不可验证时保持 semantic source。bundle 不做
preload；长文触达哪些 shard、是否预加载与 `font-display` 取舍都由宿主决定。

响应式 runtime 可以在相同 family / weight / style / feature contract 下复用已验证的服务器回放表，
不要求 live font-size 与 line-height 等于最大版心 snapshot；这两项由 runtime 以宿主当前值重新布局，
但 snapshot adoption 本身仍严格验证构建时的字号与行高。

### `CompatibleLocalFontSource`：允许同一命名字体的本地版本

浏览器端不再一概拒绝 `@font-face src` 中的 `local()`。构建端从 exact face 的 OpenType `name`
table 导出 family、full name、PostScript name 与 typographic family；CSS 中每个 `local()` token 都必须
命中这组名字，同时保留唯一且与 manifest 一致的宿主 URL fallback。family 本身不能自行成为 local
证据，`local("Arial"), url(ExampleCJK.woff2)` 一类声明会 fail closed。

这个 policy 随 host-compatible contract 修订为 `host-compatible-stylesheet-v1`。它有意接受
“同名字体不同版本不一定字节相同”的事实，
不再宣称浏览器一定绘制构建时的 exact bytes。Node 布局计算使用构建输入中的字体字节；browser
runtime 使用服务器 replay 计算布局，snapshot 与 runtime 都由同一宿主 family stack 绘制。这不等于
证明 local outline 与构建字体逐字节相同。
为了把风险限制在视觉
outline / ink 的小差异，采用前后
还必须满足：`font-optical-sizing: none`、face descriptor 与 advance probe；每个原子 segment 的 live
advance、每个预期 `drawX` 前缀位置以及每行 end sentinel 的 pen position 都在固定 CSS-px 容差内。
容差不随整行长度按比例放大；任一 segment、前缀或行末失配都原子恢复 SSR 并进入 browser pipeline。

该策略证明的是预断行所需的水平 advance / placement 兼容，而不是 glyph outline、GSUB 结果或
vertical metrics 的字节等价。相同 advance 下仍可能存在小的 ink 差异，这是本 ADR 接受的兼容性
取舍；需要 exact glyph identity 与 immutable asset identity 的站点需要另行选择显式 exact-URL policy，
不能把本默认策略的 advance 兼容误称为 byte-exact。
采用结果在 root 上暴露 `data-tiqian-snapshot-font-policy="compatible-local|url-only"`；这个标记描述
校验 policy，不声称 CSS Font Loading API 已披露浏览器最终选择了哪一个 `src` token。

快照采用对 manifest 内全部 keyed candidate 是 all-or-nothing，且只在以下证据全部匹配时发生。
显式 `data-tiqian-skip` 的宿主原生段落不参与；未进入 manifest 但仍属于 runtime-eligible 的段落不扩大
快照的声明范围，保留 semantic source 并在采用 keyed 快照后由 runtime 补齐：

验证调度在采用前后按约 8ms budget 协作让出主线程。`ProgressiveSnapshotCommitProof` 先对整批
source / manifest 做无副作用
preflight，再登记 provisional owner；随后每段 commit 后立即完成该段 geometry proof，才进入下一段，
避免一次替换整篇后触发 full-tree layout flush。新导航、resize 或新一代 adoption 只能回滚仍属于该
作业的 provisional owner；取消不会暴露不完整的 DOM owner 或计数。

可观察计数必须反映这两个 owner：采用成功后立即写入 `data-tiqian-snapshot-count`；
`data-tiqian-enhanced-count` 在纯快照路径等于该值，在混合路径的每个 progressive slice 都等于
snapshot count 与当前 runtime count 之和。完成事件同时携带 `snapshotCount`、
`runtimeEnhancedCount` 与总 `enhancedCount`，不能在 runtime 尾部处理中短暂回报 `0` 或只回报
其中一侧。

1. schema / engine / render revision、候选段落集合及 canonical snapshot DOM digest 一致；
2. 重新从 live SSR DOM 计算的 source digest 一致；
3. 启用 line-length grid 时，实际 content width 与构建宽度向下折算出的有效行宽一致；例如
   `800px` 与 `808px` 在 `18px` 网格下都得到 `44` 字、`792px` 有效行宽，可以复用同一份
   start-aligned 快照而不改变宿主容器。未启用网格时，原始 content width 仍须相差不超过具名
   亚像素容差；
4. source DOM 与 canonical prepared DOM 的 computed host family stack，以及 size / weight / style /
   line-height / letter-spacing 等 contract 一致；其中 `renderFontFamilies` 只用于确认 replay evidence 覆盖
   到同一宿主 family，不参与 CSS 投影；
   `font-kerning` 必须显式为 `normal`、`font-optical-sizing` 必须为 `none`，行对齐必须保持 start / left；
5. `@font-face` 的原宿主 URL、weight、style、unicode-range 与构建 manifest 一致；默认策略不要求 URL
   名称内容寻址，也不允许提椠为满足该条件另建资源代理；
6. `document.fonts.load()` 成功，且构建期 advance probe 与浏览器 DOM Range 结果一致；
7. clone 后每个显式 geometry / feature run 的实际 advance / `drawX`、每行 sentinel pen 与 core line
   width 都在固定亚像素容差内，且没有发生二次折行；普通 Text node 由整行 pen、字体 probe 与 artifact
   digest 共同覆盖，不为验证凭空增加 span。

第 4 项也包含 `font-variant-*`、language override、word spacing、text indent、text alignment、
writing mode 与 generated pseudo content；第一版没有建模的值一律 miss。第 1 项中的 render digest
由实际 template node / attribute / text 的 canonical tree 计算，minifier、缓存拼接或 DOM 插件改写
快照 artifact 后不能继续沿用 manifest。相同 family / style / weight 下，只要存在覆盖本段实际用字
但 URL、unicode-range 或 local-name evidence 不兼容的另一条 `@font-face`，字体来源就不可证明，
同样 miss。`size-adjust`、metrics override、face feature / variation / language override 与 named
instance 等会改变字形选择或度量的 descriptor 也必须保持默认值。任何 CSSOM stylesheet / nested
rule 若因跨域策略不可读，潜在的同名 face 同样不可排除，因此 exact contract 必须 fail closed。

任一条件不满足时，DOM 保持或原子恢复 SSR source，然后懒加载 browser Kotlin/JS runtime。snapshot-backed 的
paragraph 优先从 manifest 建立上述 shared exact-font session 并重跑相同 layout / DOM plan；session
loader 在字体异步准备前后都重新校验 live source、typography 与 CSS face contract；命令式调用若
覆盖 font family、font size、line height 或非零首行缩进，也不得复用 snapshot exact session。
runtime canonical DOM 生成后再走与 snapshot adoption 相同的 segment、line pen、baseline 与 paragraph
height gate；只有这一步失配，才清除 canonical 标记并在同次调用内回到 ADR 0039 的 browser adapter。
session 证据失效或内容超出能力域时同样走该 adapter。最大宽度且所有 eligible 正文段落都在
candidate set 时仍只安装轻量 copy / restore / observer 逻辑；存在列表或具名 capability miss 时加载
Kotlin/JS runtime，从完整 native source 开始按 viewport 距离逐段原子接管。

`SnapshotFirstInputBeforeRuntimeCompile` 要求 snapshot-ref root 先完成上述 inert snapshot 判断；
不能仅因为存在 unkeyed completion 就在输入关键期预加载 Kotlin/JS runtime。只有 snapshot 结果确认需要
runtime 时才启动 Worker 与 runtime import，使首个滚动/导航手势不与编译竞争。

进入完整 runtime fallback 时，Worker 默认候选集合必须使用 runtime 的 `p, li`，不得继续使用仅描述
keyed snapshot 的 manifest selector；只有 mixed completion 才显式传入 unkeyed selector。否则构建期
没有 keyed 的富文本段落虽然属于 runtime 能力域，也会因为 Worker 没有准备对应 plan 而永久保持 native。

### `SnapshotInvalidationBeforeRebreak`：宽度和 typography 先失效再重排

快照被采用后，`ResizeObserver`、字体加载完成和宿主 typography mutation 都重新验证 contract。
有效网格行宽变化、响应式字号变化、字体换源或 probe 变化时，先原子恢复保存的 SSR semantic source；
能力仍匹配时用 shared exact-font session 重排，否则进入现有 `HostTypographyInvalidation` /
`ReflowByRebreak`。已连接 custom element 的 `snapshot-ref` 变化也必须取消旧验证、释放 retained session，
再从新 template 走完整 adoption / fallback lifecycle；不得把旧快照 DOM 当作新的 source 再 lower。

`ResizeObserver` 直接观察 root / paragraph 的 border box，但只比较 inline-size；接管导致的 block-size
变化不会启动第二次响应式作业。确认行内尺寸变化后先断开当前 delivery，再把恢复安排在下一
animation frame 的 leading edge；不能在 observer callback（包括其 microtask）内替换正文，因为正文
高度变化会让宿主自己的 body / scrollbar observer 漏掉同轮 notification 并触发
`ResizeObserver loop completed with undelivered notifications`。viewport / visual viewport resize 则有更早
的 resize signal，仍在该帧 paint 前同步恢复 source。settled / no-op 路径随后重挂观察，不向正文 DOM
插入测量节点，也不改变 source、复制、无障碍或 Pagefind 语义。

复制 handler 从 Kotlin runtime 安装逻辑抽到独立小 JS；零 runtime 快照路径与现有 runtime 共用同一
`data-tq-copy-ignore` / `data-tq-src` 契约，软折行不进入复制，mandatory break 仍保留源码换行。

## Consequences

- 常见桌面最大版心且所有 eligible 段落都可预排时，可以原子采用整组已排好的可选择 DOM，不下载或初始化
  browser runtime；存在 runtime-only 段落时仍采用已验证的 keyed 集合，只为 unkeyed candidate 初始化 runtime。
- snapshot miss 后的 browser Kotlin/JS runtime 与构建快照共用服务器生成的 HarfBuzz/OpenType shaping、
  metrics、`PreparedParagraphV1` 和 DOM lowering，并由相同宿主 family stack 绘制；相同输入下可以比较 DOM digest、
  逐行 geometry 与像素。
- 构建缓存可由 font/source/typography digest 精确失效，度量来源可审计、可复现。
- 同一命名字体的已安装本地版本可复用快照，这是默认 host-compatible policy 的有意取舍；exact-byte
  需求必须另行选择不可变资源与隔离绘制都明确的 policy。
- 宿主只配置一份已有字体样式表；提椠不生成字体 alias、代理 URL 或 preload，也不在浏览器重复下载
  几百个 CJK shard。
- 小屏、响应式排版、系统 fallback 与快照能力域以外的复杂 inline 内容继续使用 ADR 0039 路径；快路径不会降低
  既有能力。
- 发布包新增 Node-only precompute export 与 runtime，浏览器主入口不会静态引入 Node 模块。
- HarfBuzz / WOFF2 WebAssembly 只属于 Node precompute 依赖；浏览器入口、snapshot miss 与破折号
  capability 路径都不再 import 或执行它们。
- snapshot HTML 使用共享 manifest tables 与 root-scoped dynamic-value stylesheet；这只是 transport
  去重，不改变 `PreparedParagraphV1`、原子 segment 边界或几何 gate。
- 本切片不改变 core cluster 边界，因此不会改善现有跨 segment 的 `calt` / `liga` / `locl`；相关
  full-run shaping 必须单独设计并逐平台验证 measure/draw 同源。

## Alternatives considered

- **构建时启动 Headless Chromium**：依赖浏览器与构建机字体状态，无法以 exact font bytes 作为
  可复现证据，且把 DOM renderer 变成布局事实来源。否。
- **只缓存每字 advance、客户端继续断行**：仍需加载整个 layout runtime，也无法复用最大版心的
  推入推出与 justify 结果。可作为以后 `WidthIndependentAnnotationCache` 的数据来源，不是本切片。
- **仅凭站点 maximum measure 把预断行 HTML 当 SSR 正文**：首个 response 不知道实际 viewport，窄屏
  会先 paint 固定宽度 DOM；服务端也不知道客户端是否命中不同版本的 `local()`。否。默认响应式 SSR
  必须保留 native source，浏览器完成 width/font proof 后再采用 inert artifact。
- **构建端直接按完整段落 HarfBuzz shaping**：与当前 browser/core segment 边界不同，会产生第二份
  布局语义。等 run-first shaping contract 完成后再统一迁移。
