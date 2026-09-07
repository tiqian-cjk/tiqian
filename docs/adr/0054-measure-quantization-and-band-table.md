# ADR 0054: 行长计量统一与格数区间表

- Status: Proposed
- Date: 2026-08-22
- Relates: [ADR 0007](0007-line-length-grid-quantization.md)（字格量化）、
  [ADR 0028](0028-line-length-grid-tolerance.md)（宽度容差）、
  [ADR 0040](0040-build-time-web-font-snapshots.md)（构建期快照）、
  [ADR 0041](0041-paragraph-dp-line-breaking.md)（DP 断行）、
  [ADR 0052](0052-precompute-cache-and-batch-renderer.md)（二进制站表）、
  [ADR 0053](0053-web-prose-host-consolidation.md)（宿主收敛）、
  [ADR 0057](0057-vertical-axis-exits-cache.md)（垂直方向与装饰层，自本文件拆出）

## Context

### 快照宽度匹配的现状

manifest entry 记录一个 `maxWidthPx`，运行时 `snapshotEntryWidthMatches`
（precomputed.js:158-168）判定是否采用：`lineLengthGridEnabled` 为真时两边各过一次
`lineLengthGridMeasure = min(width, floor(width / fontSize) × fontSize)`
（lazy-capabilities.js:11-21），差值容差 0.5px；为假时直接比原始像素（±0.5px）。
格开启时 `maxWidthPx` 的信息量是（格数，余数）两个数，plan 身份只依赖格数；存档像素
只是它所在格数区间的代表元。

快照分两层：宽度无关层（`fontReplay.shapes` 逐 glyph 的 advanceEm 与 boundsEm、
metric rows、faces 证据、typography）与宽度相关层（断点与行几何，随宽度变化的是
断行与调整，shaping 与 metrics 不重算）。跨格数区间时运行时用回放证据在 worker
重跑断行（`LAYOUT_REQUEST_FIELDS` 携带 `maxWidthPx`，worker-layout.js:18-32），
prepared-dom 把 plan 渲染成 HTML 字符串后整段 `replaceChildren`。

### 格量化的三份算术、两种精度

引擎侧格数计算是 `floor(containerWidth / fontSize)`
（WidthIndependentAnnotationCache.kt:411），`containerWidth` 与 `fontSize` 是
Kotlin `Float`。`Float` 在 JVM 与 Kotlin/Native 是 IEEE binary32；Kotlin/JS 把
`Float` 编译为 JS number，除法按 binary64 计算（2026-08-22 核对：编译产物
`runtime/tiqian-web.js` 全文无 `fround`，Kotlin/JS 不做逐运算精度模拟）。
构建期快照由 Kotlin/Native 产出（ADR 0050），格数是 binary32 语义；手写 JS 的
`lineLengthGridMeasure` 用 `Math.fround` 把除法压到 binary32 对齐 Native
（`fround` 只对商舍入，操作数本身可表示时才严格对齐）。

由此存在一处未对齐的边界：浏览器内 Kotlin/JS 引擎重排时按 binary64 计算格数，
与 Native 产出的快照在整除边界宽度上可能差一格：采用判定（手写 JS，binary32
语义）正确，随后的重排却按不同格数执行。parity 语料未覆盖边界宽度样本。

### `lineLengthGridEnabled` 的使用范围

两个生产宿主都显式设 `true`（sveltekit 站点 `src/lib/server/tiqian.ts:66`、astro 站点
`src/server/tiqian-engine.ts:33`）；`false` 只出现在 layout 测试中为精确宽度断言
而构造（AsciiPointMarkKinsokuTest.kt:279、DisplayGlyphSubstitutionEngineTest.kt:521、
InlineBoxLayoutTest.kt:23、:64、SpacingAndLineGeometryEngineTest.kt:255）。
normalize.rs:81-84 把未声明视为默认开启。引擎文档（TextModel.kt:505-528）记录的
三个绕过场景（精确像素行长、非中文正文、调用方自对齐）在生产消费范围内没有实例。
2026-08-22 裁定该开关是过度防卫，应删除。

### 标点压缩与行内几何的量值来源

行内容宽不是字号的整数倍：压缩量优先取字体 OpenType `halt` 特性的设计值（每个
标点各自的 em 分数，实测自字体，PunctuationModel.kt:57-62），字体未提供时策略
回退 `min(policyBodyFloor, 0.5 × em)`（:325）；窄行（< 14em）行尾顿号逗号句号
悬挂到行界之外，不占行内格（ClreqProfile.kt:303-321）；拉丁 glyph 的 advance
是任意的 em 分数；两端对齐的拉伸按机会类别分配（词空格、技术空白、中西文边界
各有 em 上限，另有优先顺序与紧急字距，Justifier.kt:63-71、:226、:307），行内
逐空隙增量不相等。因此不存在一个公共固定步长整除全部行内几何量。

### 宿主配置与缓存身份的现状

缓存字节是 `(source, typography, 格数)` 的纯函数；typography 现含 fontSizePx、
lineHeightPx 与 fontFamilies，字号与行高都以 px 绝对值参与身份。宿主配置靠手抄：
sveltekit 站点把 CSS 规则里的数字抄进 `src/lib/server/tiqian.ts`，成为传给
`createPrecomputer` 的三份配置（`.article-entry p` 15.5/30，行高声明在
layout.css:302；`li` 15.5/28，:306；脚注区 13/24，:437）。引擎不读样式表：同一
数字在引擎层与 CSS 层各出现一次，引擎层那份决定快照按什么算，CSS 层那份决定
浏览器实际怎么画，两份事实来源靠人工同步。

手抄的失败模式有现役实例。note 的 1.1em（17.05px）只写在 Note.svelte 的样式表里，
引擎收到的仍是 15.5/30 配置；一致性校验拿 computed 17.05 与记录的 15.5 比对，每次
访问不匹配，该段每次访问都降级为浏览器排版。要按 17.05 出快照需要第四个
precomputer，第四个 context 随之出现。按字号区分 context 因此成为宿主的正确性
前提：漏枚举不报错，在运行时以降级暴露，宿主看到降级才知道漏了。

单位现状分三层：glyph 度量已是 em 分数（advanceEm，用时乘字号）；断点是无单位
整数 source 偏移；行几何、拉伸增量与 y 是 px 绝对值。断行判定的全部横向比较对
字号齐次：计量是 N × fontSize，advance 是 em × fontSize，悬挂阈值是 14em，halt
压缩量是 em，首行缩进是 2em，两端对齐上限是 em；全部同除字号后，判定结构与字号
无关（精确算术下）。

## Decision

### `GridQuantizationUnconditional`：格量化成为唯一行长语义

删除 `LineLengthGrid.enabled`。引擎对一切正文（纯 CJK、混排、纯拉丁）只消费
`floor(width / fontSize) × fontSize`，不再有原始像素计量路径；格数保留下限限制
`coerceAtLeast(1)`（WidthIndependentAnnotationCache.kt:411 既有行为），宽度不足
1em 时格数为 1。拉丁正文的代价至多是断行计量的可用宽度减少 1em 以内（计量
取整，内容不吸附字格、无字距畸变）；换来删除一个配置开关、`snapshotEntryWidthMatches` 的分叉
判据与双套宽度匹配语义。本决定是 ADR 0007 的修订：0007 的 grid-first 语义不变，
其绕过场景不再存在。0053 五表规格的段落标量清单随本决定删除
`gridEnabled`。

迁移边界：manifest schema 升版本，旧 revision 的 manifest 整体拒读
（`expandSnapshotManifest` 对 revision 不符已有 throw 行为，沿用，不做解释性
兼容；`false` entry 属旧 revision，随之不可读）；normalize.rs 删除该字段读取；四处 layout 测试改为 em 对齐宽度（取整不改变
数值）或改写期望值。构建缓存按内容哈希全量重建，静态页的 runtime 与 manifest
同一次构建成对发布，不存在跨版本配对的常态路径；除拒读行为外无兼容工程。

### `SingleGridArithmetic`：格数除法统一为 Double

格数除法的两个操作数（宽度与字号）从入口到除法点全程 `Double`，中途不得经过
`Float` 中转。仅改除法不够：`maxWidthPx` 现状在 Rust 侧是 f32（layout_request.rs:85），
字号同为 f32（layout_request.rs:86，span 粒度 :55），C ABI 按 f32 读入
（LayoutRequestReader.kt:44-45），两个操作数跨 FFI 边界时已截断为 binary32，除法处提升
`Double` 也拿不回丢掉的位。宽度与字号的 wire 字段与 ABI 读取一并升 f64/Double，
Kotlin 侧以 `Double` 进入格数计算；JS 侧本来就是 Double。字号还决定 typography
匹配：两侧都记 f64，比较不再经过 f32 中转。运行时字号来自 CSSOM 序列化字符串
的解析（element.js:1855 `parseFloat(getComputedStyle)`），同一声明值的构建期与
运行时表示不保证逐位相同，typography 判等沿用既有容差（0.01px，
precomputed.js:1060 现状）；容差只作用于采用判定，引入的行长偏差上界为
N × 0.01px（48 格时 0.48px），不超过现行 0.5px 计量容差；格数算术不受容差
影响，仍由两侧 f64 除法导出。容差内的字号差在整除边界可以导出不同格数（构建
15.5 对运行时 15.509，744px 下 48 格对 47 格）：条目按格数索引，此时不命中，
按 miss 走引擎重排与回填，不会取错带。全平台格数相同，
lazy-capabilities.js 的 `Math.fround` 复刻删除，Native 快照与浏览器重排的边界
宽度分歧消除。格数计算只在入口判定；引擎内部布局数学继续使用
`Float`。运行时格数函数与引擎同式：`Double` 下
`coerceAtLeast(1, floor(width / fontSize))`；`lineLengthGridMeasure` 的 `min`
保留为计量字段的浮点守卫（`floor` 结果乘回字号可能越过原宽度），不参与格数
决定；宽度不足 1em 时格数为 1，引擎按 1 × fontSize 计量（此时超过容器宽），
请求的计量字段如实记录容器宽，仅作诊断，不参与断行，也不从格数还原。
格数 1 与 2 在缺省表域之外，走 miss 路径。golden 预期零 diff（语料宽度应为
em 对齐值），实施时验证，并在 parity 语料补边界宽度样本（整除附近 ± 1 ULP 内的
宽度，横跨 k × f32(fontSize) 与 k × double(fontSize) 两侧）。

### `MeasureIntervalPlanTable`：格数区间表与活 DOM 增量补丁

plan 对行长的依赖是阶梯函数：格量化无条件化之后，引擎看不到原始宽度，断点集与
行几何在格数 `N` 的整个区间内逐位相同，一切文种同型。一个格数区间称一个带，
跨越称为切换格数区间。切换格数区间的处置：

- **表形态**。构建期为可达带全集预计算每带的断点集，紧凑编码 O(行数)。
  可达全集指声明范围内每个整数格数一个带，缺省 3..48 共 46 个（上界取现行
  宿主最大版心：sveltekit 站点 744px ÷ 15.5px = 48 格）；值表 intern
  跨带共享，行几何与分配向量按带存（行长目标随格数变化，断点集相同的带行
  几何也不同）。带全集由构建方声明的宽度范围除以字号得出（构建方知道
  自己的版心 CSS）；未声明时默认理论全域 3..48 em，范围外宽度走 miss 路径。
  声明范围缩小表体积与构建时长，不界定正确性边界。区间划分按格数定义：
  引擎在格数 N 的区间内只见 N × em 的计量值，plan 相同，不依赖断点集随宽度的
  单调性；相邻带的断点集之间无包含关系假设，编辑脚本按任意两份断点向量计算，
  移动行比例高的跳变成本由 bench 记录。每带的三要素：
  断点（整数 source 偏移，是判定结果，不含判定过程）；行几何值（量化为 1/64 px
  整数，1/64 是本表的存储量化步长；Blink 与 WebKit 的 LayoutUnit 为 1/64 px，
  Gecko 的 app unit 为 1/60 px，小于步长的差值在跨过舍入边界时仍可改变量化
  结果，处置见亚像素边界一节）；值表引用
  （distinct 压缩量与 advance 进值表，行数据引用索引，与 ADR 0052 站表
  string region 同型，同型指 intern 加索引引用的做法，字节布局随本表定义；
  advance 由度量回放表（ADR 0053 扩展的通用表示）经引擎计算导出，是输出值的
  intern，不构成第二份度量副本）。行内容宽（分层挤压
  与邻行均摊之后的值）与空隙数随行几何存。本轮条目的行几何含行盒 y（垂直方向维持
  现状，ADR 0057 实施后改为水平方向几何）。两端对齐的拉伸分配是引擎决策：
  Justifier 按机会类别分配增量（词空格、技术空白、中西文边界各有 em 上限，另有
  优先顺序与紧急字距，Justifier.kt:63-71、:226、:307），行内逐空隙增量不相等。
  分配向量随行数据进值表（distinct 增量 intern，行数据引用索引），运行时只应用
  不重算。slack 摆放（bodyAlignment 的块偏移）不写入表：它依赖区间内的实际宽度，
  每次 resize 都可能变化，运行时每块一次乘法。
- **编码形态**。表编码为 ADR 0052 二进制容器的一组 region（断点差分区、行区、
  值表区，头部带每带偏移索引），读取用 DataView 按需取标量，命中路径零对象
  分配。加载复用 TableTransport（根属性指向内容哈希 URL、sha 比对、全页一份
  实例）；偏移对字节长校验、损坏在任何行被读之前抛错的纪律随站表 reader
  原样适用。适配的直接原因是内容全整数：1/64 px 量化之后没有浮点位格式问题。
  依据是 0052 第四批实测（站表文本形态换二进制：原始字节 −53.6%，gzip
  −13.0%，布局解码 0.12 ms 对 JSON.parse 3.1 ms）。
- **亚像素边界**。输入侧容器宽在 Blink 与 WebKit 是 1/64 px 格点（Gecko
  1/60），字号是任意浮点值，不落在格点上；断点判定不得使用量化豁免：临界宽度处任意小的宽度差
  都可移动一个字，且行内容宽是多次加法的结果，可落在任意位置。量化只作用于
  输出几何，断行与调整判定在引擎 `Float` 算术内完成，不经过输出量化。行端与
  行几何由行区存量单次舍入得出，不由逐空隙增量累加还原；逐空隙增量只决定空隙
  内分配，其累加误差上界为空隙数 × 1/128 px（量化步长之半），现行 plan 路径的 Float 值进入
  浏览器后同受 LayoutUnit 取整，量化不引入新的可见差。行长目标 N × fontSize
  不在 1/64 格点时（fontSize 为 16.3 一类值），行端值按不增方向量化，越界上界
  1/64 px（Gecko 1/60）。行几何以构建期 typography 的字号为前提，字号不匹配按既有
  typography 不匹配处理（miss、活排版），不存在跨字号复用。表存判定结果因此安全。
  `SingleGridArithmetic` 统一的是入口格数算术；引擎内部布局仍按平台 Float 语义
  （JS 为 binary64，Native 为 binary32），同格数下 Native 表与浏览器引擎重算的
  行几何在 1/64 量化域一致，量化边界处的残余分歧是既有平台差异（现行 worker
  重排与 Native 快照同样存在），由 parity 边界样本覆盖。每个带只有一个来源
  （构建期表或 root 带缓存），运行时不要求跨来源逐位一致。
- **格数区间切换补丁（`SparseBandPatch`）**。页面只保留一份 HTML（构建期写入静态页的
  那份）。跳表把 source 坐标换算到活 DOM 偏移：走查活 DOM、跳过引擎插入的标记
  节点（copy.js:100-110 对 `[data-tq-engine-break]`、`[data-tq-copy-ignore]` 的
  处理是同型逻辑）。补丁分三步：走查（只读 DOM 结构）先建跳表；从两份断点向量
  （活 `tq-line` 标记所记的旧带、表里的新带）算出完整编辑脚本；然后在一个同步
  批次里应用：文本 node 在新断点处拆分合并，跨行语义元素（`a`、`em` 一类）的
  逐行克隆随之拆分合并，`tq-line` 几何标记（prepared-dom.js:597-665 的每行标记
  span 与行尾哨兵）重写位置与属性。断点与行几何存量均未变的行零操作；断点未变
  而几何值变化的行（邻行均摊把邻行压缩改到另一个值一类）只重写属性，无结构性
  mutation。该路径保持 ADR 0039 `AtomicParagraphDomSwap` 的安全性质，增长界更紧：结构性
  mutation 只随断点移动的行数增长（整段交换的 childList 记录携带全部子 node，
  该增长界属补丁自身，整段交换不具此界），属性写入随几何值变化的行数增长；脚本期只读结构不读布局量，
  读写不交错（无强制同步 reflow）；单同步批次应用，渲染器只见前后两个状态，无
  「旧行盒已拆、新行盒未接」窗口。未触及的文本 node 保持同一性，其选区与 a11y
  对象存活；触及行内浏览器不保证选区存活，按 ADR 0044 的源偏移几何映射恢复，
  与整段重建时的处理一致。编辑脚本在首次 mutation 之前完整算出；走查与应用在
  同一同步 turn 内，单 JS 线程没有交错者，走查所得不会在脚本与应用之间过期。
  应用只由已算完的脚本与完整 DOM 操作构成，不存在运行时失败状态：实现抛错即为
  缺陷，按错误上报并修复，不做任何回退处理。digest 校验（sourceSha256、
  renderArtifactSha256）与结构走查发生在 connect 与每次切换格数区间。它们是与宿主页面
  的一致性校验，浏览器扩展一类的外部注入在此暴露；不匹配即 miss 走整段重建，与
  自身缺陷是两类事件。`AtomicParagraphDomSwap` 不删除，退为全量重建路径（初次水合即写入
  HTML、内容变更、校验不匹配）。内容变更按失效合一处置（见下）：换新 DataView，
  当前格数重算回填，全量重建；source 恢复为写入内容后 digest 与结构走查重新
  通过，回到表的路径，不匹配按次判定，不跨次保留。sourceSha256 校验的是抽取后的
  source 文本（copy.js 投影），不校验 DOM 树形，引擎重建的 DOM 不因树形差异
  被排除在表的路径之外。
  prepared-dom 已是从插入数据到 DOM 的扫描器，本决定新增的件是紧凑区间表与
  增量补丁。
- **运行时回填**。root 自带一份 DataView 作带缓存：引擎切换格数区间的结果在应用前编码为
  同型条目写入，条目格式、偏移校验纪律与构建期表同一，同一 reader 消费。命中
  顺序为构建期表、root 带缓存、引擎；引擎路径从终点变为回填来源，某带首次访问
  后再访同带不重算、不整段重建。断点不从宽度推断：旧带断点读活 DOM（`tq-line`
  标记，`SparseBandPatch` 的既有输入），新带断点读命中的条目，运行时从宽度算出
  的只有格数。运行位置：引擎经 ADR 0053 的 ffi/js 唯一引擎端进程内调用，本
  决定不依赖也不新建 Worker。回填把分解报告 §5 批次 0 判定的两个输入都压低：
  重算频次从每次切换格数区间降为每带首次访问（每段落每 digest 生命周期上界为可达带
  数），序列化从 plan JSON 往返降为条目字节一次本地写入。批次 0 的测量在回填
  已实施的工作负载上记录：两个判定输入是工作负载属性，本决定改变工作负载，
  旧负载数据回答旧问题；测量先于本表实施时，表实施后重测再判定。结论落在
  「移除」行时，0053 随之修订的条款是：`HostDeviceTopology` 的执行装置项与
  Consequences 图、`ExecutionInWorker` 全条、`WireFormatPerBoundary` 的 Worker
  段、`CoordinatorOwnedDispatch` 的在途窗口与紧急批发送段（任务池、deadline、
  generation、tier 保留，调度对象改为进程内引擎调用）、Verification 3 的跨线程
  协议用例；exact 与 fallback 两路径都回主线程，写入器在引擎调用处本地写入。
  结论落在「全量保留」或「阈值激活」行时，写入器跟随引擎位置在 Worker 内编码，
  条目字节搭既有每帧回程消息回传，其余不变。写入器单点：构建期与运行时同一实现（0052 的
  table-binary-writer 模式，Node 与浏览器同一模块），无第二写入器与跨写入器
  fixture；写入消费的 plan 输出须携带逐空隙分配向量（plan 已序列化 run 粒度 spacing 与
  逐 glyph advance，prepared-dom.js:358-401 即其消费范围；实施时核对的只有增量
  类别覆盖：词空格、技术空白、中西文边界是否都落在 run spacing 表示内）。条目缓存取代 plan 对象缓存成为 `RequestQuantizedAtBoundary`
  的存储形态，同格数只保留一份可直接应用的表达，plan 对象不再过任何传输与
  缓存。条目数以可达带全集为上界，无淘汰策略。无 snapshot 的宿主同样获得
  补丁路径。运行时回填随 `MeasureIntervalPlanTable` 整体受开工条件约束。
- **失效合一**。失效与切换格数区间是同一条管线的两种粒度：条目来源（构建期表、带
  缓存、引擎）到写入 root DataView 到应用。digest（source 或 typography）变更
  即整份换新：旧 DataView 弃引用，新 ArrayBuffer 从空开始，同一管线在当前
  格数重跑。不做逐条失效与原地重填：条目是 source 的函数，digest 变更后没有
  可保留的条目；原地重填留有中间窗口，带偏移索引指向旧 source 的仍有效条目，
  读得到错数据而不报错；新实例保证填充完成前的读取按 miss 处理，旧缓冲区立即
  回收。应用粒度按 source 分：同 source 的切换格数区间走 `SparseBandPatch`；跨 source
  全量重建，同一套逐行构建原语生成整段子树，以 DocumentFragment 与一次
  `replaceChildren` 提交（`AtomicParagraphDomSwap` 的机制），prepared-dom 的
  运行时 HTML 字符串路径删除，只在构建期使用。运行时的切换格数区间与重建共用
  条目这一种几何输入；文本与 run 样式来自 sampler 的五表记录，条目不携带文本。
  此条与运行时回填共同修订 0053 的 `SinglePlanLowerer` 与 plan 缓存条款：运行时
  lowerer 的输入从 plan 对象改为条目加五表文本，plan 缓存由条目缓存取代，plan
  对象的消费范围退到构建期。
- **闲时预热**。回填的填充顺序从访问驱动改为闲时驱动：coordinator 以最低优先级
  沿当前命中带向两侧按距离递增预烘，只烘构建期表未覆盖的带（补集；已由构建期
  表覆盖的带不复制进 root DataView，三级查找直接读构建期表）。两个机制前提：
  预热任务不参与防饿死 aging（不可见工作不被优先级提升）；启动走既有预算守卫，
  执行单元为每段每带，段内不可抢占（0039 调度架构弱点记录的取消粒度），剩余预算低于近期
  单元成本时不启动。resize 活跃期预热被高优先级任务挤掉是预期行为，拖动停止后
  恢复。预热有不动点：补集填满即静止，无周期性空转；隐藏标签页 rAF 停止，预热
  自动暂停；digest 变更换新 DataView 后从当前带重新开始。内存与收益按宿主分：
  构建宿主补集为空，零新增；无 snapshot 宿主稳态从访问过的带集增长到可达带集，
  上界不变（仍无淘汰策略），换来拖动首访不再走引擎重算，预热未用的带只消耗
  闲时。预热单元与格数区间切换 miss 走同一执行装置。闲时预热随 `MeasureIntervalPlanTable`
  整体受开工条件约束。
- **开工条件**。四项 bench（时序 golden 任务的度量集），各自记录绝对值与对比
  基线：可达带全集的表体积（二进制产物量，对比现行单带 HTML 产物）；区间命中
  后同步产 DOM 的成本（对比 120Hz 单帧 8.3ms 预算）；增量补丁对整段重建的差值
  （对比 `AtomicParagraphDomSwap` 路径，含每次切换格数区间的结构走查与 digest 重算
  成本）；每带首次访问的进程内引擎重算成本（对比同一 8.3ms 预算；0039 记录的
  第 1 条：移除分支回到同线程执行，以此项为接受依据）。条件数值待测量结果记录后再定，
  本决定锁度量集与基线；测量不达标则保持候选状态，不实施。

临界宽度分析记录为理论备选：若将来恢复原始像素计量路径，断点集对宽度仍是阶梯
函数（区间边界为前缀内容宽可容纳下一 token 的临界值，每个后缀起点的可达宽度
集是单区间，可编码为临界宽度区间树套共享后缀 DAG；贪心断行断点随宽度单调前移
的论断在阈值分支规则处不成立，0025 的分档禁则与悬挂在阈值两侧改变行内容宽的
计算；DP 断行确定性保持阶梯划分，单调性同样不保证）。格量化无条件化之后该
结构不需要。

### `RequestQuantizedAtBoundary`：请求与缓存键按格数构造

引擎请求与 plan 缓存键在构造处先过格量化：同格数区间的宽度共享同一条请求与
缓存条目。请求携带格数整数，引擎入口以格数 × 字号还原计量（乘法），不再对
请求宽度做第二次 `floor`；量化宽度先乘后除的双舍入（`fl(N × fontSize) / fontSize`
可落回 N−1）由此不存在。请求的宽度字段升 f64 并携带量化后的计量值，仅作诊断与
日志，格数以请求携带的整数字段为准。入口还原的计量不做 `min` 守卫：格数计量
的定义就是 N × fontSize，引擎入口没有需不越过的原始宽度；
`SingleGridArithmetic` 的 `min` 守卫只属于诊断字段一侧。

### `VerticalAxisDeferred`：垂直方向与装饰层移至 ADR 0057，本轮维持现状

垂直方向的行为变化整体移至 [ADR 0057](0057-vertical-axis-exits-cache.md)：
lineHeight 退出身份、条目改为水平方向几何、装饰层改 CSS em 盒与运行时公式。本轮
重构不实施：lineHeight 留在 typography 身份与失效 digest，条目含 y，装饰按现行
px 覆盖层在客户端运行。横向路径把格数区间切换成本降为查表与补丁后，性能余量足够，装饰
与几何反查是稀有用例，本轮没有调整它们的理由。

### `TypographyConfigFromCss`：配置由 CSS 层叠生成，手抄通道删除

构建顺序没有循环依赖：组件先产 HTML，层叠在 HTML 之后求值，布局在层叠之后；
要选的只是层叠解析的保真程度。三档：

1. 手抄（现状）：零保真，上文两种失败模式的来源。
2. 窄层叠：只解析排版要的继承属性（font-size、line-height、font-family、
   font-weight、font-style、text-indent 六项），库层面选择器匹配加特异性计算。不是完整 CSS
   引擎，范围有界；嵌套选择器与媒体查询逐个支持。
3. 无头浏览器实测：构建期跑页面读 `getComputedStyle`，完整保真，构建慢且 CI
   依赖浏览器。

取第 2 档。标量来源按字段分派：fontSize、lineHeight、fontWeight、italic 出自
级联的对应属性，firstLineIndent 出自 text-indent；maxWidth 与 locale 不是文本
继承属性，分别来自构建方声明的版心（与表形态节的宽度范围同源）与容器 lang
属性。响应式断点是残余误差：写入默认档的解析值，其他档字号不匹配；不匹配后果由
miss 路径承担：运行时读实际 computed、引擎重排，不再降级为浏览器排版；条目
回填与闲时预热随开工条件，条件通过后 miss 的引擎成本降为每带首次访问。本决定
修订 0053 采样器条款：五表的段落粒度标量不再由宿主手抄声明，按上述分派生成；
sveltekit 站点 `src/lib/server/tiqian.ts` 的三份配置删除，note 的 17.05 经层叠解析进入
构建集合，该段不再每次访问降级。

层叠同时读 font-size-adjust：非 `none` 的段落不生成条目，跳过增强并按
capability issue 记录，与段内混字号 run 的 ExactSessionBrowserFallback 同类。
该属性让 fallback 链上每个 face 的使用字号各自缩放，引擎的字号是段落粒度标量，
测量侧不消费；渲染侧 styles.css 的 `inherit`（styles.css:247）照常应用它，
测量与绘制不同源。各主流引擎已支持（Chrome 127、Safari 17 起），宿主启用它是
一行 CSS。运行时失效签名虽含该属性（element.js:52 的 TYPOGRAPHY_PROPERTIES），
但签名只捕捉构建后的变化：同 stylesheet 下构建与运行时一致地各自忽略与应用，
几何错位不报错。守卫由层叠生成给出，构建期与运行时 miss 路径共用该逻辑。

「配置」与「context」由此分离：配置是人写的声明，层叠生成后为零；context 是缓存
实例身份，由构建期解析与运行时发现自动出现。宿主不再枚举，漏声明的失败模式不
存在（未构建的 context 走回填），枚举从正确性前提变为成本决策。

### `FontSizeRatioDomainSpike`：字号比例域 spike 与身份收敛

字号退出身份的入口换算已经存在：`floor(W / fontSize)` 即把宽度换算为整 em 数，
就是格数；advance 侧回放表本存 advanceEm，运行时才乘字号，跳过该乘法则横向管线
运行在 em 域，fontSize 成为单位本身（计量 N em，advance 0.93 em，悬挂阈值
14 em）。配合 Context 记录的齐次性，精确算术下断点列跨字号复用成立。

工程阻碍在入口之后，四项：

1. 判定算术：引擎内部横向比较是 px Float（advance 各乘字号再累加），不同字号下
   浮点舍入不同，边界样本可翻转；跨字号保证断点相同，要求全部内部比较改到 em
   域。`SingleGridArithmetic` 随之覆盖全管线：内部布局在 em 域计算，
   入口一处除法扩展为全管线换算，typography gate 变
   比例 gate，per-context DataView 变 per-比例。
2. 输出回 px：DOM 路径构建期写 em 字符串与写 px 字符串同价，浏览器在样式计算内
   乘并缓存该结果；剩余的运行时乘法只有 overlay 的 SVG 坐标在绘制时算一次（次数
   随 overlay 元素数，有界）。LayoutResult 与 dump 出口乘回 px。
3. 垂直方向：行高绝对值（30px 一类）不是字号比例量；ADR 0057 实施后该项不再阻碍，
   本轮垂直方向维持 px 现状。
4. 证据面：golden、parity 语料（1078/1078 extents 一致）、js_compat 的 Float 语义
   仿真都在 px 语义下记录，换域后在新域重建，一次性有界成本。

先做 spike：一个分支把断行与调整的内部比较改到 em 域，重建 golden，记录换域前后
的断点与行几何 diff；数据划算再修订上述条款，不划算则本节仅作记录，context 模型维持
原案。触发场景是宿主使用连续字号：clamp() 流式排版让字号随视口宽度连续变化，
px-per-context 在拖动中每档字号一个 context，新 context 产生的速率超过回填速率；
当前两个宿主（sveltekit 站点、astro 站点）都是离散固定配置，不在该场景内。

段内混字号是 spike 的检查项：度量模型按 glyph 存，可以表示混排；当前边界在字号
是段落粒度标量，段内异号 run 走浏览器度量降级（ExactSessionBrowserFallback）。比例
域下 run 粒度比例因子（13px run 与 15.5px 段落的比值为 0.839）进 run 记录，em 写法的子
字号随段落字号等比、身份不变；绝对 px 写法的子字号在段落字号变化时改变比例，
仍是不同身份。可变字体的 opsz 维度让 advanceEm 随字号变化，开启光学尺寸的 face
上比例域复用不成立，该类 face 按字体维度拆分 context，列入 spike 检查项。
font-size-adjust 是 face 粒度变体：开启后 fallback 链上每个 face 的有效字号不同，
段落粒度标量与 run 粒度比例向量都不再够用，需要 face 粒度系数；建模前按
`TypographyConfigFromCss` 的守卫跳过，列入 spike 检查项。

身份收敛的完整路径：

| 维度 | 处置 | 身份去向 |
|---|---|---|
| 宽度 | 格数区间表（本 ADR 主体） | 退出，格数即索引 |
| 行高 | 运行时公式，零缓存（ADR 0057，本轮不实施） | 退出 |
| 字号 | em/比例域（本决定，待 spike） | 退出，剩比例向量 |
| 字体 | 构建期实测，宽度无关层 | 保留，不可约 |
| source | 内容哈希 | 保留 |

身份收敛为 `(source, faces)`（段内混字号的 run 比例向量另行进入身份，见上文
混字号一段）；宿主交给构建的输入只剩字体文件（子集化本就需要）与
source，不再抄写任何数字。字体是身份里不可约的成分：字号变化的本质是同一张
advance 表乘一个系数，字体变化的本质是表本身更换（拉丁、数字、标点的 halt 压缩
量与字距特性各字不同，断行判定随之改变），不存在把字体 A 的几何变换为字体 B 的
映射，没有不变量就没有单位技巧。该成分已是构建期静态因子：构建期 HarfBuzz 直接
cmap/hmtx/GSUB/GPOS/halt 直接 shaping 出最终 advance，fontReplay 存测量结果
（advanceEm、boundsEm、压缩量设计值），不建模字体内部结构；用哪副字来自宿主 CSS
的 font-family 声明与 fallback 链，构建时静态可知；运行时 cssFaceContract
（precomputed.js:1161）逐字段校验浏览器实际使用的 faces 与构建证据一致，不一致不
重放。两端都是机器读取，不携带手抄成本。格数索引 `floor(W / fontSize)` 不看
字体，表的索引结构跨字体共享，条目内容不共享；混字体当前已支持（回放表按 glyph
规范键存，fallback 链各查各的表），运行时浏览器 fallback 到未度量系统字体按
MissingServerShapingReplay 拒绝，不猜测。

## Consequences

- 快照宽度匹配失去分叉：`snapshotEntryWidthMatches` 只剩格数比较。manifest
  entry 的 `maxWidthPx` 更名为格数整数字段，引擎请求另设格数整数字段、宽度
  字段升 f64 携带量化计量值；两处的格数由同一 `Double` 算术导出。与 0053
  `WireFormatPerBoundary` 的传输格式变更合并为同一次 schema 版本升级。
- 格数区间切换成本从「引擎重算 + 整段重建」变为「查表 + 原地补丁」，拖动场景
  （120Hz 单帧 8.3ms 预算）的重复格数区间切换成本下降；代价是构建期新增可达带全集的
  断行计算与表体积。
- 运行位置合一与失效合一：重算只剩每带首次访问且无 plan 序列化往返；Worker
  去留由批次 0 判定并记录，回填把判定的两个输入压向移除一侧，判定以回填已实施
  的测量为准（0039 记录的第 1 条：移除分支回到同线程执行，接受依据是重算频次
  与开工 bench 的首访成本项）；失效与切换格数区间共用同一条回填管线，digest 变更
  换新 DataView 实例，prepared-dom 的运行时渲染路径退到构建期。
- 带内宽度变化不再进入格数区间切换路径：断点与拉伸分配不变，bodyAlignment 为左对齐时
  块偏移为 0、无 DOM 写入，非左对齐时重写一次块偏移。
- 框架集成边界不变（ADR 0042）：宿主框架拥有根元素，引擎拥有根内子树；切换格数区间对
  子树的变更方式在同一所有权边界内，adapter 生命周期与反应性面不受影响。
- 拖动停在格数边界时 N/N+1 来回翻转，每次翻转重划分文本 node；增量补丁使翻转
  便宜，翻转频率在 bench 中记录。翻转触及行的选区由 ADR 0044 恢复承担；若 bench
  记录的翻转频率构成负担，边界迟滞（切出新带需越过半格以上一类的间隔）是候选
  对策，随 bench 数据决定。
- 拉丁正文可用宽度至多减少 1em，两端对齐的右缘从容器边改为量化后的行长边，
  slack 摆放随 bodyAlignment，与 CJK 现状一致；这是排版取舍，随本决定生效。
- `MeasureIntervalPlanTable` 以 bench 条件为开工条件，未达标不实施；其余三个
  决定（唯一语义、统一算术、请求量化）与 `TypographyConfigFromCss` 的层叠生成
  不依赖该表，先行实施；后者的回填部分随条件。
- 手抄通道删除：构建期窄层叠从宿主 CSS 生成段落粒度标量，`tiqian.ts` 三份配置删除；
  改 CSS 后不需要人工 invalidate，note 一类的不匹配降级不再发生；「配置」消除，
  context 由解析与运行时发现产生。
- 身份收敛分三处：本轮为 CSS 生成配置与比例域 spike（golden diff 记录后再
  决定），垂直方向退出移至 ADR 0057、实施时机由 roadmap 排定；每处独立可回退。全部
  实施后身份为 `(source, faces)`，构建输入只剩字体文件与 source。

## Alternatives considered

### 全带预计算并按 O(全文) plan 运输

拒绝。现行 plan 的 cells 覆盖每个字（prepared-dom.js:455 以
`lines.flatMap(cells).join("")` 还原全文），HTML 重复全文；每带信息量实为
O(行数)（断点 + 行数据），source 与 shaping 跨带共享。按 O(全文) 运输是为
不为未发生的格数区间切换付永久字节；紧凑编码后全带预计算的代价才可接受（见 Decision）。

### 带格式表按某份 HTML 的偏移编码

拒绝。格数区间切换补丁的坐标基准必须是 source：跨行的 span 拆分与语义元素克隆随带变化，
HTML 树形不是跨带稳定结构。source 偏移稳定，跳表在补丁时把 source 坐标换算到
活 DOM 偏移。

### 行内几何用公共固定步长表示

拒绝。几何量来自三处（字体 halt 设计值、字体 advance 表、除法结果），不存在
公共整除步长。临界值表（值 intern）与 1/64 px 输出量化覆盖同一目标，且无损于
渲染。

### 量化函数从 ffi/js 导出、删除手写副本

次选，暂不采用。该方案要求浏览器引擎与 Native 先统一算术才能保证导出值与构建
值一致；`SingleGridArithmetic` 的入口统一（宽度与字号 wire 同升 f64）达到同一
效果。ADR 0053 的 ffi/js 唯一
引擎端实施后，手写 `lineLengthGridMeasure` 本就随宿主收敛删除。

## Verification

1. `SingleGridArithmetic` 实施：`maxWidthPx` 与字号的 f64/Double 全路径有测试
   （layout_request.rs、LayoutRequestReader.kt、缓存入口三处）；typography 字号
   的 f64 判等有测试（非 f32 可表示字号经 0.01px 容差命中，格数仍由 f64 除法
   导出）；全平台 golden 零
   diff；parity 语料加入整除边界宽度样本（± 1 ULP）；lazy-capabilities.js 的
   `fround` 删除后 jsBrowserTest 与 npm test 全部通过。
2. `GridQuantizationUnconditional` 实施：`lineLengthGridEnabled: false` 的旧
   manifest 拒读有测试；四处 layout 测试迁移后 layout 模块测试全部通过；normalize.rs
   字段删除后 Rust 侧测试全部通过。
3. `MeasureIntervalPlanTable` 开工前完成四项 bench 并记录数据；实施后格数区间切换路径
   以时序 golden 记录（断点表命中、补丁作用范围、翻转计数、闲时预热后的引擎
   调用计数）。
4. 格数区间切换补丁等价：采样若干带迁移，断言补丁后 DOM 与同格数整段重建
   （`AtomicParagraphDomSwap`）的输出结构等价（dump 对比）；表内格 N 的行几何
   与产出平台引擎同格重算逐位一致、与浏览器引擎同格重算在 1/64 量化域一致；
   触及行的选区与 a11y 恢复（ADR 0044 映射）有断言。
5. 回填与失效：写入器单点在 Node 与浏览器两端有测试；plan 输出携带逐空隙
   分配向量的核对结果记录；digest 变更换新 DataView 后旧条目不可读（填充前
   读取按 miss 处理）有断言；批次 0 判定数据按分解报告 §5 记录。
6. `RequestQuantizedAtBoundary` 实施：同区间不同像素宽度只产生一条 plan 缓存
   条目（计数断言）。
7. `TypographyConfigFromCss` 实施：窄层叠对 sveltekit 站点三组标量的解析值与现行手抄值
   逐字段相等；note 的 17.05 进入构建集合有断言；媒体查询其他档的不匹配走 miss
   与引擎重排、不走浏览器降级有断言；font-size-adjust 非 `none` 的段落跳过增强
   并记录 capability issue 有断言；开工条件通过后补条目回填命中断言。
8. `FontSizeRatioDomainSpike`：em 域分支换域前后的断点与行几何 diff 清单记录；
   跨字号复用断言（em 域条目在 15.5 与 17.05 两档字号下命中同一份数据）随 spike
   记录，作为是否修订 `SingleGridArithmetic` 内部 Float 条款的数据依据。

## 执行清单

状态标记约定同 ADR 0053（勾选、验收、`nix develop -c`）。第一组不依赖开工条件
与 0053 进度，先行实施；第二组是开工条件；第三、四组在条件通过后实施，不达标
整组保持候选；第五组 spike 独立分支，不阻塞其他组。0053 执行清单 D 组以本清单
54-10 完成为重测前提。每组统一验收：相关模块测试全部通过；layout golden 零 diff；
涉及 npm 产物时 npm test 全部通过。

### 第一组：先行实施

- [ ] **54-1 无条件格量化**（`GridQuantizationUnconditional`）：删除
  `LineLengthGrid.enabled`；manifest schema 升版本，旧 revision 整体拒读；
  normalize.rs 删字段读取；四处 layout 测试 em 对齐或改期望。
  KPI：`gridEnabled` 在代码与 manifest 生成物中出现 0 次；0053 五表标量清单同步删除。
  验收：Verification 2。
- [ ] **54-2 格数算术统一 Double**（`SingleGridArithmetic`）：宽度与字号 wire
  字段与 ABI 读取升 f64/Double（layout_request.rs:85-86、
  LayoutRequestReader.kt:44-45）；lazy-capabilities.js 的 fround 复刻删除；
  parity 语料补整除边界宽度样本（± 1 ULP）。
  KPI：格数计算路径的 Float 中转点 0 处。
  验收：Verification 1。
- [ ] **54-3 请求携带格数**（`RequestQuantizedAtBoundary`）：manifest 的
  maxWidthPx 更名格数整数字段，引擎请求另设格数字段、宽度字段升 f64 携带计量值；
  schema 升级与 54-1 合并为一次。
  KPI：同区间不同像素宽度的 plan 缓存条目数 1。
  验收：Verification 6 的计数断言。
- [ ] **54-4 窄层叠配置生成**（`TypographyConfigFromCss` 先行部分）：六项继承属性
  解析、maxWidth 与 locale 分派、font-size-adjust 守卫；`tiqian.ts` 三份配置删除。
  KPI：sveltekit 站点三组标量逐字段与手抄值相等；note 的 17.05 进构建集合。
  验收：Verification 7 除回填断言外全部；回填断言归 54-10。

### 第二组：开工条件

- [ ] **54-5 四项 bench 与条件判定**：表体积、同步产 DOM、补丁对重建差值、每带
  首访重算；度量集与对比基线按 `MeasureIntervalPlanTable` 开工条件一节；数值与
  条件结论记录。
  KPI：四项绝对值与对比基线数据记录；结论为通过或保持候选。
  验收：Verification 3 前半；不达标时第三、四组不开工。

### 第三组：表的主体（条件通过后）

- [ ] **54-6 条目编码与写入器单点**：ADR 0052 容器 region（断点差分、行区、值表、
  每带偏移索引）、DataView reader 与偏移校验；写入器 Node 与浏览器同一模块。
  KPI：命中路径对象分配 0；写入器实现份数 1。
  验收：编码 roundtrip 与损坏先抛错测试；Verification 5 写入器单点项。
- [ ] **54-7 构建期全带预计算**：可达带全集（缺省 3..48）每带断点集与行几何，
  值表 intern 跨带共享；TableTransport 加载复用。
  KPI：表体积落在 54-5 条件内；构建时长增幅记录。
  验收：构建产物与加载测试。
- [ ] **54-8 plan 分配向量核对**：plan 携带逐空隙分配向量；词空格、技术空白、
  中西文边界三类增量类别覆盖核对。
  KPI：核对结论记录（覆盖或欠缺清单）。
  验收：Verification 5 核对项。

### 第四组：运行时（条件通过后）

- [ ] **54-9 格数区间切换补丁**（`SparseBandPatch`）：source 到活 DOM 跳表、两份断点向量
  的编辑脚本、单同步批次应用；`AtomicParagraphDomSwap` 退为重建路径；digest
  校验在 connect 与每次切换格数区间。
  KPI：补丁后 DOM 与整段重建结构等价（dump 对比）；零操作行不产生 mutation。
  验收：Verification 4 全部断言。
- [ ] **54-10 运行时回填**：root DataView 带缓存；三级查找（构建期表、带缓存、
  引擎）；引擎结果编码写入；同带再访不重算。
  KPI：同带第二次访问引擎调用计数 0。
  验收：Verification 7 回填命中断言；0053 D 组以本项完成为重测前提。
- [ ] **54-11 失效合一**：digest 变更换新 DataView，填充前读取按 miss 处理；
  prepared-dom 运行时 HTML 路径删除；0053 `SinglePlanLowerer` 输入改为条目加
  五表文本。
  KPI：运行时切换格数区间与重建共用条目这一种几何输入；plan 对象运行时消费范围 0。
  验收：Verification 5 对应断言；0053 修订条款生效。
- [ ] **54-12 闲时预热**：最低优先级、当前带向两侧按距离递增、只烘构建期表
  补集、不动点静止、隐藏标签页暂停。
  KPI：预热静止后补集带首访引擎调用 0。
  验收：时序 golden 的预热后引擎调用计数断言（Verification 3 后半组成部分）。
- [ ] **54-13 schema 版本升级合并**：本组传输格式与 manifest 变更合并为同一次版本升级，
  与 0053 `WireFormatPerBoundary` 变更对齐。
  验收：两侧 Verification 对应项在同一次升级中通过。

### 第五组：spike（独立分支）

- [ ] **54-14 字号比例域 spike**（`FontSizeRatioDomainSpike`）：断行与调整的内部
  比较改 em 域的分支、golden 重建、换域前后 diff 清单、跨字号复用断言记录。
  KPI：15.5 与 17.05 两档命中同一份 em 域数据的断言结果记录。
  验收：Verification 8；结论为修订条款或维持原案。

### KPI 汇总

| 指标 | 基线 | 度量 |
|---|---|---|
| 格数区间切换路径 | 引擎重算加整段重建 | 查表加原地补丁；时序 golden 记录格数区间切换帧耗时与 mutation 数 |
| 同步产 DOM 成本 | 无既有数据 | 对 120Hz 单帧 8.3ms 预算的占比 |
| 补丁对重建差值 | AtomicParagraphDomSwap 路径 | 含结构走查与 digest 重算的差值 |
| 每带首访重算成本 | 无既有数据 | 进程内引擎调用毫秒数 |
| 表体积 | 现行单带 HTML 产物字节 | 可达带全集二进制产物字节 |
| 边界翻转频率 | 无既有数据 | 拖动停在格数边界的 N/N+1 翻转次数 |
| 回填命中 | 无既有数据 | sveltekit 站点与 astro 站点格数区间切换命中率 |
