# ADR 0053: Web prose 宿主收敛：装配规格、TS 宿主与统一执行装置

- Status: Proposed
- Date: 2026-08-22
- Relates: [ADR 0039](0039-web-rendering-path.md)（Web 渲染路径与「调度架构弱点记录」一节；本 ADR 给弱点第 1 条处置方向，第 2 条维持开放）、
  [ADR 0040](0040-build-time-web-font-snapshots.md)（构建期字体证据与快照）、
  [ADR 0042](0042-framework-web-integrations.md)（Web 框架集成包）、
  [ADR 0050](0050-native-precompute-rust-bindings.md)（原生 precompute 绑定与 EngineLevelAbi）、
  [ADR 0052](0052-precompute-cache-and-batch-renderer.md)（整站表传输与批量渲染）

## Context

### 引擎单一实现与三个消费端

排版引擎只有一份实现（core/font/linebreak/clreq/layout 的 Kotlin 多平台代码），以三个形态被消费：JVM 进程内直调（Compose、Android）；Kotlin/JS mjs（`:ffi:js` 编译产物，浏览器 module Worker 经 `layout-worker.js:8` 静态引入）；Kotlin/Native 静态库经 C ABI（`ffi/native/tiqian_layout_abi.h`，0050 amendment EngineLevelAbi）被 Rust 链接。Rust 侧的 `tiqian-precompute` 是编排层，不含第二套排版实现。

### @tiqian/prose 的构成与两条通道

`@tiqian/prose` 由手写 JS 与两个编译产物组成：

- `runtime/tiqian-web.js`：`:frontend:web` 的 Kotlin 主线程运行时 bundle。jsMain 共 5669 行（WebEnhancer 系列、`DomParagraphRenderer.kt` 与 Overlays 共 1335 行、`MarkdownParagraphLowering.kt` 880 行），配套 jsTest 3981 行行为测试。
- `precompute-runtime/*.mjs`：`:ffi:js` 的 Node 引擎运行时，生产消费者只有 `layout-worker.js:8` 一处静态 import。

宿主与 Kotlin 运行时之间有两条通道：11 个注册在 document 上的自定义事件（`WebEnhancer.kt:52-95`）与 `globalThis.TiqianWeb` 桥（`runtime.js:16-24` 挂 9 个轮询方法）。调度分布在两侧：element.js 的 `TiqianLayoutCoordinator` 维护 tier、generation、quota 并按帧发放凭证；Kotlin 内部另有 `ProgressiveJob` 队列与 pending 计数，两侧以轮询对齐。这些 Kotlin 代码包含领域逻辑：段落托管与回滚、渐进任务状态机、段落资格策略、响应式度量稳定化、富文本 run 的浏览器度量降级判定（`ExactSessionBrowserFallback*`，`WebEnhancerSupport.kt:135-157`）。这些逻辑目前无法被其他前端复用。

### worker 一词的三个指称

1. **真 module Worker**：`layout-worker.js`（107 行），只服务 exact-session lookahead 路径。init 必须携带 manifest 字体证据，否则 `LayoutWorkerFontContractInvalid`（layout-worker.js:21-23）。Worker 内没有 shaping：`__TiqianFontBackend` 按规范键查表并做字号缩放（browser-font-replay.js），缺键抛 `MissingServerShapingReplay`，fail-closed。它的职责是用宽度无关的服务端度量证据在任意新宽度重跑断行。
2. **TiqianWebWorkers**：Kotlin 主线程运行时上的轮询接口（`WorkerPolledScheduling`），不创建线程。
3. **无 bake 路径没有 Worker**：没有 exact font session 时 element.js 不引入 worker-layout（element.js:1668），排版在主线程由 `WebCanvasTextShaper` 以离屏 canvas `measureText` 逐 run 探测完成（`WebEnhancer.kt:265`）。

有 bake 与无 bake 解同一个问题：浏览器内有效宽度变化后重跑断行。差别只有两个变量：引擎在哪跑、度量从哪来（回放查表或现场探测）。宽度容差共用 LineLengthGridQuantization（0007/0028）语义，element.js 以 `lineLengthGridMeasure` 复刻签名判断失效（element.js:1857、3366、3411）。

### 渲染器的三份实现

「引擎几何到 paint-only DOM」的绘制规格存在三份实现：

- **DomParagraphRenderer.kt 与 Overlays（1335 行）**：输入活 `LayoutResult` 与宿主元素，建 detached fragment 后一次 `replaceChildren` 换入。持有需要活 DOM 特权的能力：宿主语义元素浅克隆并跨行连续（`ContinuousSemanticFlow`）、SVG 行间线与着重号、ruby/bopomofo span、原子换入。文件内含一块实时度量：`metricsCtx.measureText` 探注音基线（Overlays:170、200；:431 自述 "it is a renderer fallback, not a layout decision"）。
- **prepared-dom.js（821 行）**：同一规格的纯函数重述，输入 plan JSON，输出 HTML 字符串与 artifact 树。间隙表示模型（none、letter、overlap、trailing-letter）、OpenType 特性白名单（`"pwid,palt"` 与 `"fwid"`）、哨兵结构与原实现逐条对应，交叉注释记录同步关系（prepared-dom.js:676、310-315）。
- **prepared_dom.rs（1291 行）**：服务构建期编排的 Rust 移植。渲染发生在并行段内部：批量循环跑在 `std::thread::scope` 原生线程上（parallel.rs 的 `TIQIAN_PRECOMPUTE_THREADS`），每段字体证据经 thread-local 出借窗口回收，引擎回调在调用线程同步重入（precomputer.rs:392-394）；渲染在循环体内（precomputer.rs:314），HTML 与 artifact 摘要嵌入记录流入 manifest/bundle 组装。字节一致由 js_compat.rs 仿真 JS 数字格式化、UTF-16 排序与 Kotlin Float 由 f64 转入 f32 的舍入语义维持。

第三份实现由线程模型决定：渲染必须在并行段内、必须无宿主依赖，JS 版在该位置不可用（论证见 Alternatives）。

### 分散的装配逻辑

FFI 面与平台事实之间存在一层没有 schema 文件、没有单一归属的逻辑，负责把平台事实翻译成引擎可消费的纯数据、把 plan 翻译回宿主形态。四个关注点各有三到四份实现：

| 关注点 | 现有实现 |
|---|---|
| 度量证据会话 | browser-font-replay.js（Worker 回放）；session.rs 与 engine_bridge.rs（Rust 构建）；`HarfBuzzBuildBackend.kt`（ffi/js Node 遗留）；`ExactSessionBrowserFallback*`（主线程降级） |
| 输入装配与传输格式 | `WebEnhancerSupport` 手拼 JSON；worker-layout.js 字段表；PrecomputeWire 分隔符解码；C ABI 二进制缓冲。同一段过程四种编码 |
| plan 下游消费 | prepared-dom.js、prepared_dom.rs、DomParagraphRenderer.kt |
| 会话治理与能力策略 | element.js、precomputed.js、browser-fonts.js、WebEnhancer* 分散持有 |

ffi/js 自身同时做三件事：PrecomputeWire.kt 在一个文件内做分隔符解码（`\u001e`/`\u001d`/`\u001f`，:29-31）、逐字段校验、`LayoutInput` 组装、断行器选型（:164）与 plan JSON 编码（:168）。采集、schema、编码三层耦合在同一文件，是这层难以描述的直接原因。

### 调度权的分布

主线程有三个互不感知的循环：

1. **TiqianLayoutCoordinator**（element.js:283）：rAF 帧循环，帧预算 2.5-6ms 跟随实测帧距（element.js:415）；回调队列按可见度排序并带防饿死 aging；worker slot 缓存 tier 计数、generation 与自适应 quota（element.js:597-615）；两级凭证发放：每帧 `#pollWorkers`（element.js:762）与 ResizeObserver 回调内的 `grantImmediate` pre-paint 通道（element.js:625）。
2. **worker-layout.js 准备循环**（`prepareWorkerLayouts`，worker-layout.js:205）：按视口距离排序逐段发 Worker 请求，每 8ms 让出主线程（worker-layout.js:86）。协调器不感知该循环的在途请求；该循环没有配额、没有优先级、不占帧预算。
3. **Kotlin ProgressiveJob 队列**（WebEnhancer.kt:652）：由协调器凭证驱动，逐段执行度量、断行、DOM 换入。

真 Worker 的 layout 请求不携带 generation（`LAYOUT_REQUEST_FIELDS`，worker-layout.js:18-32）。过期判定只有主线程的 `isCurrent` 闭包在 await 点丢弃（element.js:1675-1676）；plan 缓存以请求内容为键，宽度在键内，跨代不复用依赖这一点成立。协调器的 `slot.generation` 来自 Kotlin 轮询接口（element.js:777-781），与 Worker 在途请求无关。Worker 按消息到达顺序执行，主线程无法重排或撤销已发出的请求。请求与响应消息里没有优先级信息。

### 0039「调度架构弱点记录」的处置

0039「调度架构弱点记录」第 1 条（调度者与被调度者同线程）仍然成立：fallback 路径的度量、断行、DOM 提交与协调器帧循环全在主线程。第 2 条（取消与预算的最小作用单位是整个段落）也仍然成立：`shouldStop` 在每个段落之后询问（`WebEnhancerParagraphLifecycle.kt:131-135`），检查点未下移断行循环。本 ADR 给第 1 条处置方向（执行移入 Worker）；第 2 条维持开放，属于未来的治理模型变更。

### 自行管理 webfont 宿主与 CSSOM 证据不足

`cssFaceContract`（precomputed.js:1161）把页面 CSSOM 的 @font-face 规则与构建期证据逐字段比对（family、style、weight 区间、unicode-range 集、src local() 列表、解析后的 url、描述符缺省），候选集只从 document.styleSheets 收集。宿主自己管理 webfont 加载是常见做法。sveltekit 站点的实测：首屏只内联 plexsc-fallback.css（20 个度量改写 faces），用户交互后的空闲期取回 CSS 文本、经 FontFace API 每帧注册 32 个 face 并写 plexsc-ready=1；回访改经 `<link>` 进 CSSOM（432 个 IBM Plex faces），校验通过。FontFace API 注册的 faces 进入 document.fonts，但不产生 CSSFontFaceRule，且 FontFace 接口不暴露 src，采集器无法从 document.fonts 读证据。结果：首次访问在任何浏览器上都判 `SnapshotExactFontContractMismatch:FontFaceContractMismatch`，命中的是命名的 fallback；回访才通过。这是证据来源不足，与浏览器差异无关。

### 无消费者导出与 shared 副本落后

`@tiqian/precompute` 迁出（d79be52）后遗留：digest.js 与 font-contract.js 没有生产消费者；`compactSnapshotManifest`、`loadedPrecomputedSnapshots`、`validatePrecomputedExactFontReplayRuntimeContract`、`renderPreparedParagraph` 的包装导出只有测试使用。`renderPreparedParagraph` 需要注明：web-precompute 的同名导出是它自己 shared 副本上的包装（`src/precompute.ts:14` import `../shared/prepared-dom.js`），不构成 `@tiqian/prose` 导出的消费者；Kotlin 走 `__TiqianPreparedDomRenderer` 桥（`WebEnhancerSupport.kt:199`）。

shared/ 副本曾落后一个 schema-2 常量批次，ADR 0052 批次补齐后与
`frontend/web/npm/snapshot-schema.js` 逐字节一致（2026-08-22 核对，diff 为空）。
precomputed.js 重复实现 `parseUnicodeRange` 与 `cssWeightPreference`（font-face-boundaries.js 同名）；`cssWeightMatchedFaces` 只在 precomputed.js。同步机制仍是 sync:shared cp 脚本（web-precompute/npm/package.json:67）与 parity 测试，不依赖类型系统。

## Decision

### `HostDeviceTopology`：采样器、协调器、执行装置

宿主重排为三个装置：

- **采样器（主线程）**：读活 DOM，收字体证据，以 canvas 度量按规范键填度量回放表，把平台事实与度量按规格合成为五表记录。
- **协调器（主线程）**：持有唯一带优先级的任务池；帧预算、tier、quota、generation、离屏防抖、pre-paint 通道延续现状；按帧打包收发 Worker 消息；DOM 提交与语义回放作为帧任务执行。
- **执行装置（Worker）**：ffi/js 引擎只在此处运行。输入是五表记录与度量回放表，输出是 plan。

bake 与 fallback 的差别收敛为度量表的填写方不同：构建期 HarfBuzz 或运行时 canvas。执行地点只有 Worker 一处（首批视口段落的 pre-paint 同步快路径除外，见 `ExecutionInWorker`）。

### `SingleEngineFace`：@tiqian/ffi 是唯一引擎出口面

所有 JS 宿主（浏览器主线程、module Worker、Node 构建期兼容面）只经 ffi/js 调引擎。ffi/js 新增浏览器度量后端模式：TS 采集器提供基于 canvas 的度量回调，无快照路径同样经该接口产出 plan。ffi/js 改为字节进出面：传输格式解析、校验与 `LayoutInput` 组装移入引擎入口，`PrecomputeWire` 的 parse 函数降为编解码器。ffi/js 改为独立 npm 包单独发包，
包产物导出类型定义与 source map：类型定义给宿主编译期检查，source map 把
宿主侧运行时栈映回源码。

### `AssemblySchemaAsContract`：五表记录的单一规格

装配输出是五张表：text、textSpans、sourceBoundaries、lineBreakSpans、inlineBoxes，外加段落粒度的标量（maxWidth、fontSize、lineHeight、locale、fontWeight、italic、firstLineIndent、gridEnabled）。规格写成一份正式定义（IDL 或同源生成的 TS/Rust 类型）。源语义投影规则（空白折叠投影、样式边界登记、硬断行映射）属于规格定义。两侧采集器对同一输入必须产出逐位相同的记录，parity 语料是该规格的可执行规格。`sourceBoundaries` 语义按 core/TextModel.kt:6-13 保持：无样式范围也必须成为簇边界，保证精确占用几何。

### `MetricTableAsEngineInput`：引擎只读表

`shapeReplayKey` 与 `metricReplayKey` 已定义度量身份。回放表扩展为度量的通用表示：canvas 探测是同一张表的另一个填写方，主线程量一次，按同一规范键写入同一表结构。引擎只认表，不关心填写方是构建期 HarfBuzz 还是运行时 canvas。此决定是 fallback 执行移入 Worker 的前提：Worker 内没有 CSSOM 与 FontFaceSet，度量必须先成为可在消息中传输的数据。

### `ExecutionInWorker`：bake 与 fallback 统一执行地点

前置条件：Worker 必要性判定（分解报告第 5 节的 node/bun/`--jitless` 净成本 bench）先行实施，测量在 ADR 0054 回填已实施的工作负载上记录。判定为「移除」时本决定与 `WireFormatPerBoundary` 的 Worker 段、`CoordinatorOwnedDispatch` 的在途窗口与紧急批发送段（任务池、deadline、generation、tier 保留）、`HostDeviceTopology` 的执行装置项与 Consequences 图示、Verification 3 的跨线程协议用例一并修订，修订条款以 ADR 0054 为准，exact 与 fallback 两路径都回主线程执行；判定为「全量保留」或「阈值激活」时本决定按原文生效，demo/web 的主线程反例（度量廉价且全缓存命中时主线程足够）由阈值激活分支吸收。

断行、行调整、plan 生成的引擎执行全部移入 Worker。fallback 路径不再在主线程执行引擎计算，首批视口段落的同步快路径除外：该快路径沿用 `grantImmediate` 的 pre-paint 通道语义，在 ResizeObserver 回调的 pre-paint 窗口内于主线程同步执行（现行 `grantImmediate` 即此形态，element.js:630），覆盖首帧视口内容。主线程其余保留采样、提交与语义回放。非首批段落比主线程同步执行晚一帧收到 plan，经 Worker。度量证据质量不变：fallback 本来就只有 advance 与 ink 两种粒度的证据，canvas 度量即浏览器实际绘制所用的数据。

### `CoordinatorOwnedDispatch`：任务池、deadline 共识与在途窗口

- **池的归属**。带优先级的任务池只在协调器。Worker 侧是有界在途队列；调度器只有一个，取消、重排、配额都在主线程决定。
- **统一入池**。帧内全部工作（布局分段、度量任务、字体校验重验、DOM 提交与语义回放）经同一任务池与同一凭证形态入队。任何触发源不得自带私有节奏、私有预算或第二条唤醒执行路径；执行器自制预算的 standalone 准入（分解报告 §6 约束 5 的废除决定）与逐批触发全量重验都按此原则排除。负载动态均衡集中在这一个装置与 GrantController 凭证里，不为各类工作分别设预算与唤醒机制。
- **优先级共识用两个标量**。每条请求携带 deadline 与 generation。deadline 用 Date.now 域：两端时钟同源，且与现有 GrantController 的截止时间语义一致（`GrantClockConversion`）。Worker 收件队列按最早 deadline 先执行；generation 与当前作业不符的请求在段落之间丢弃。两侧不需要同步更多调度状态。
- **紧急请求的路径**。`grantImmediate` 打包当帧 deadline 的紧急批立即发送。紧急批的等待上界由在途窗口容量与单段成本决定；窗口按 root 自适应，反馈法沿用 `AdaptiveGrantQuota`：deadline 命中扩窗，超时缩窗。Worker 逐段执行，段间让出消息循环，晚到的紧急批在下一个段间隙重排。
- **回程不参与优先级**。Worker 完成一段即回传。协调器在消息回调内只做 generation 验收与 plan 入库，提交任务交回帧循环，按现有 tier 顺序授予。回程到达顺序不影响提交优先级。
- **plan 缓存**延续现有键语义（请求内容含宽度），入库与读取都校验 generation。

### `WireFormatPerBoundary`：传输按边界收敛、二进制为主

主线程与 Worker 之间每帧每方向一条打包消息：请求侧五表记录按规格派生的二进制编码打包（方向与 snapshot-table-binary 一致），buffer 进 transfer list，所有权随消息转移；表字节（Uint8Array）transfer。不再手拼 JSON 字符串中转。plan 回传第一阶段保持引擎输出的 JSON 字符串（以 Uint16Array 装载并 transfer），二进制 plan 编码随引擎 ABI 演进后替换。FFI 边界沿用分隔符格式（JS）与二进制缓冲（Native），校验归引擎入口。

### `SingleCoordinator`：调度合并与通道废除

单一 TS coordinator。11 个 `tiqian:*` 自定义事件通道、`globalThis.TiqianWeb` 桥与 TiqianWebWorkers 轮询接口废除；废除的是 Kotlin 运行时与 element.js 之间的内部通道，外部触发源不变（document.fonts 事件、ResizeObserver、宿主 API 调用），直接入同一任务池；worker-layout.js 的准备循环与 pending/plans 并入协调器任务池。取消单位保持为段：本 ADR 不改变 0039「调度架构弱点记录」第 2 条的状态。

### `TsHostRuntime`：剥除 Kotlin 主线程运行时

删除 frontend/web 的 Kotlin 运行时层：WebEnhancer 系列、DomParagraphRenderer 与 Overlays、MarkdownParagraphLowering。宿主生命周期逻辑（段落托管与回滚、渐进任务状态机、内容 reconcile、复制保真）改写为 TypeScript，现有 jsTest 套件作为行为规格逐项移植后再删 Kotlin 源。引擎策略（富文本 run 降级判定、dash 能力判定）不参与迁移，经 ABI 输出决策。

### `SinglePlanLowerer`：绘制规格唯一实现与浏览器后处理

plan-based lowerer（prepared-dom.js 改为接受 plan 对象）是绘制规格的唯一实现。DomParagraphRenderer 删除；活 DOM 特权部分成为浏览器侧后处理：占位符替换式语义克隆（复用 restoreLiveSemanticElements 模式）、SVG 行间线与着重号绘制、注音 span 挂载、原子换入。无 bake 路径同样先产 plan 再 lower，两套渲染合并为一套。本条是先行形态：ADR 0054 的失效合一随后把运行时 lowerer 的输入改为区间表条目加五表文本，plan 对象的消费端退到构建期。

### `ProseCoreLayering`：三包拓扑与集成平级

npm 发布面拆为三个独立包，依赖方向单向：web-component → core → ffi。core 包收
engine（coordinator、loaders、web-worker）、sampler、measurement、cache、utils
子目录，只含 TS 源码与测试，引擎生成物只在 ffi 包。`<tiqian-prose>` 的集成薄层
（生命周期、属性反射、custody、诊断出口）单独成 web-component 包，同样只含 TS
源码与测试，与 Compose、Android 平台接入及 SvelteKit、Astro 框架集成（ADR 0042）
平级；框架集成包依赖 web-component 包。包间引用只经各包导出接口，跨包相对路径导入
在编译期失败；分层违反在构建时即暴露，无需等待 F3 的 lint 规则。三个包同次发布、
版本号一致，发布事务沿用既有 npm 多包流程。kotlin-js-store 随 Gradle JS 构建收敛到
ffi/js 后回归原位。

### `StrictTsDiscipline`：三包 TS 代码的类型制度

去 Kotlin 化产出的全部 TS 代码（core、web-component、ffi 三个包的 TS 面）适用同一制度，
无例外条款：禁止 `any`（显式与隐式，`noImplicitAny`）；禁止 `as unknown as` 双重
断言；禁止 `object`、`Object`、`{}` 类型；全部代码强类型（`strict: true` 全开）。
当前包没有 lint 配置，eslint（typescript-eslint）是新增工具链，配齐对应规则并设为 error：`no-explicit-any`、
`no-restricted-types` 禁宽类型（`ban-types` 已在 typescript-eslint v8 拆分废弃）、
`no-restricted-syntax` 禁双重断言。任何情况下不允许
`eslint-disable`（行、区块、文件、整包范围）；CI 对 `eslint-disable` 字符串
做 grep 检查，出现即失败，同时通过 lint 禁止任何形式的 inline type 出现，interface
和泛型内部禁止直接使用花括号撰写类型。

### `DeclaredFaceEvidence`：声明式字体证据与不匹配解释

- **宿主声明通道**：`declareTiqianFontFaces(cssText, options?)`，`options.baseUrl` 指明声明文本的 URL 基准。宿主把自行管理、不会进入 CSSOM 的 @font-face CSS 文本交给采集器；sveltekit 站点一类的预热流程在注册 FontFace 的同一处调用。注册表是模块作用域的，不新增 globalThis 名（与 `SingleCoordinator` 的通道废除同向）。`baseUrl` 必须显式传入：从远端取回的 CSS 文本里 src 是相对该 CSS 文件地址的相对路径，构造 sheet 的 `href` 为 null；采集器现有的 `sheet.href || document.baseURI` 回退（precomputed.js:336）会把相对 URL 错按页面地址解析。
- **解析复用且无副作用**：声明文本经与 CSSOM 相同的解析器读取，以 `new CSSStyleSheet({ baseURL: options.baseUrl })` 构造（`baseURL` 是 CSSStyleSheetInit 的既定选项，相对 url() 按它解析）、`replaceSync` 装载后读 rules；构造的 sheet 不采用进 document，不触发字体加载。不支持该选项的环境相对 URL 按 document.baseURI 解析，校验比对按字段不匹配进入 miss，fail-closed 不变。`replaceSync` 抛错（语法错误、@import 触发的 NotAllowedError）按该条声明缺席处理，diagnostic 记 `DeclaredTextInvalid`，detail 携带异常名，两类原因可区分。不支持构造 sheet 的环境降级为构造 detached `<style>` 元素读取其 rules（不接进 document，不触发样式计算）；detached `<style>` 也取不到 rules 的环境同样按声明缺席处理并记录。fail-closed 不受影响：声明只补充校验候选集，后续仍有 `document.fonts.load` 与 advance 几何探测两道独立校验，伪造声明绕不过构建期证据。
- **候选集合并与顺序**：校验候选集 = 声明文本规则加 CSSOM 规则，数组里声明在前、CSSOM 在后。现有挑选用 `findLast`（precomputed.js:1177），后出现的规则胜出；该顺序下 CSSOM 覆盖声明，与「同一 face 以 CSSOM 为准」一致。`BoundedInitialFontGate` 行为不变（仍只等正文用到 faces 的完成承诺）。未声明的宿主行为不变，校验仍 fail-closed。
- **声明唤醒，重验入池**：声明注册表变更时同步通知活跃会话；通知只负责唤醒，不内联执行。既有唤起只有 `document.fonts` 的 loadingdone/loadingerror（element.js:1475-1476、2763-2764）；宿主先完成 FontFace 注册、字体已 loaded 时，之后调用声明不会再有任何字体事件，被动等待会永久停留在 fallback。重验作为任务进协调器任务池：每个 root 至多一个 pending 重验任务，同帧多次声明合并为一次，任务执行前又有新声明只保持 pending；执行时以当前合并候选集整批比对。宿主的分批节奏是宿主侧的自由（sveltekit 站点每帧 32 个是它的注册步调；本设计不定义该常量），本设计的成本上界来自合并，不来自跟随宿主节奏。
- **不匹配解释结构化**：`SnapshotExactFontContractMismatch` 的 detail 区分两类：候选集为空（EmptyCandidateSet：页面与声明都拿不出可核对的 face）与字段不符（FieldMismatch：给出期望/实际面数与第一个不符字段）。逐字段核对顺序固定为 family → style → weight 区间 → unicode-range → src。`dataset.tiqianExactFontMiss` 保留命中名并携带该 detail；detail 字段形态进分解报告第 11 节的时序 golden。
- **注册表生命周期**：多次调用按追加处理，同一 `(cssText, baseUrl)` 判重跳过并计数递增，注销递减，计数置零才移除记录（两个组件注册同一声明时，单方注销不撤销另一方仍在用的声明）；空串与全空白是 no-op。调用返回注销函数，移除该条声明并同样触发重验；SPA 路由切换与微前端卸载（ADR 0042 框架集成的场景）需要撤走声明。不设 replace 模式，追加与注销已覆盖。

### `ServiceDirectoryRule`：全页单例集中一个目录

G2 全局清除后仍成立的运行时单例集中存放在 core/services/ 一个目录，
每个文件头注释写明两点：该对象为什么必须全页一份，为什么不能用参数
传递。幸存者清单（S5-tail 核定）：

- globalServices 容器（Symbol.for 键，跨 bundle 副本共享一份；
  参数传递无法覆盖副本各自 import 的场景）。
- S5-bc 核定：loaderState 已溶入 globalServices().runtimeLoader；
  Symbol.for worker 协调对象已溶入 globalServices().coordination.channel；
  declared-faces 登记表待后续批次处理。
- preparedStyle 全文档查找表：S3-a Part 2 将 prepared-dom.ts 的模块作用域
  preparedStyleRootsByHost 与 preparedScopeCounters 迁入
  globalServices.preparedStyles（rootsByHost: WeakMap<Element, Element>，
  scopeCounters: WeakMap<Document, PreparedScopeCounter>）；per-root 状态
  PreparedStyleState 迁入 EnhancedElementContext.preparedStyle。S4 时代曾记为
  待办的扫描已于此波完成。
- S5-tail 核定：snapshotTables（loadedTables / resolvedTables 迁入
  globalServices.snapshotTables，全页面 URL 去重缓存）；
  snapshotAdoption（snapshotFontReplayProofs / states / directServerArtifacts
  迁入 globalServices.snapshotAdoption，按段落元素索引的全页面缓存）；
  viewportAnchor（gestureTrackerInstalled / lastGestureAt /
  heldOwnerByRoot / ownerHolds 迁入 globalServices.viewportAnchor，
  文档范围手势与滚动锚定状态）；
  stylesheetLoader（stylesheetPromise / stylesheetElement 迁入
  globalServices.stylesheetLoader，全页面样式表加载句柄）；
  elementContexts（WeakMap<Element, EnhancedElementContext> 迁入
  core/services/element-contexts.ts，全页面元素上下文注册表）。
- 永久豁免（pure-memo，不迁入 services）：replayMetricsByView
  （snapshot-manifest.ts，按不可变表视图索引的派生缓存）；
  unicodeRangeCache（precomputed.ts，有界字符串→范围列表缓存）；
  graphemeSegmenter（markdown-lowering.ts，无状态 Intl.Segmenter 实例）。

目录之外的散置全局单例视为违反模块边界。AGENTS.md 代码组织节同步
收录本规则。

### `UnusedExportCleanup`：无消费者导出删除与 cp 机制删除

删除 digest.js、font-contract.js 与全部 test-only 兼容导出。shared/ 目录的字节拷贝删除：web-precompute 依赖 @tiqian/prose 的正式导出获取 prepared-dom 与 snapshot-source，cp 脚本删除。schema 常量由同源生成，不再依赖人工同步。

### `DualLoweringStance`：prepared-dom 维持双实现

JS 版与 Rust 移植版并存是明确决定：渲染位于原生并行循环内部，thread-local 证据出借要求引擎回调在调用线程同步重入，构建期无法调用 JS（论证见 Alternatives）。代价是持续维护 js_compat 的语义仿真；防漂移升级为两侧共享同一份 golden 语料的 CI 强制比对。若发生实际漂移或 wasm 工具链成熟，可重启「Rust 权威、浏览器加载窄体积 wasm」方案（仅此纯函数，无 DOM 依赖）。

## Consequences

收敛后的形态：

```
采样器（TS 读活 DOM ／ Rust 解析 HTML）→ 五表记录 + 度量回放表
  → 单一引擎接口（@tiqian/ffi，Worker 内执行）→ plan
  → 唯一 lowerer → 浏览器后处理 → 提交
度量来源（构建期 HarfBuzz ／ 运行时 canvas）是同一张表的两个填写方
执行地点收敛为 Worker 一处；主线程保留采样、调度、提交
```

正面：管道从四编码三语言双管道收敛为一规格两采样器一执行地点；三个调度循环合并为一个；测试面收敛为 TS 宿主测试加共享 golden；同步防护从 cp 脚本升级为类型生成与 CI 比对；5669 行 Kotlin 宿主代码与其编译产物移除，`runtime/tiqian-web.js` 不再存在；Worker 请求获得代际与优先级表示，主线程可按窗口控制可撤销的在途量。

代价与风险：3981 行行为测试需要先行移植为 TS 规格才能删除 Kotlin 源；迁移期新旧栈共存，混合页面必须继续通过 digest 校验与既有集成测试；capability issue 名称是跨语言协议，改名是破坏性变更；无 bake 页面首批视口段落之后的首排延迟多一帧（首批视口段落本身走同步快路径）。

## Alternatives considered

### 保留 Kotlin 宿主运行时，仅合并 JS 侧协调器

拒绝。调度合并只消三个循环里的一个；装配逻辑四个关注点的多份实现、11 个事件加 globalThis 双通道、渲染器三份实现中的两份 JS 侧并存，都随双语言宿主保留。TsHostRuntime 的成本（移植 3981 行 jsTest）是一次性的，双语言宿主的装配规格维护是持续的；引擎策略（富文本 run 降级判定、dash 能力判定）留在 Kotlin/JS 继续无法被其他前端复用，与 `AssemblySchemaAsContract` 的单一规格目标冲突。

### fallback 保持主线程同步执行

拒绝。此前拒绝 fallback 进 Worker 的三个理由在本架构下重新评估。逐段 postMessage 往返延迟：按帧打包后在途请求按窗口批量发送，摊销后剩余代价是首排多一帧，由同步快路径覆盖首批视口段落。取消与失效语义需要跨线程协议：generation 与 deadline 本来就要盖到 snapshot 路径请求上，fallback 复用同一协议，没有新增。canvas 探测需要 document 的 CSSOM 与 FontFaceSet、Worker 内不可得：该约束只要求度量留在主线程；度量成为表之后 Worker 不需要字体语境。原判断的前提是 fallback 进 Worker 等于 canvas 进 Worker；度量归采样器、执行归 Worker 之后该前提不成立。

### Worker 侧第二优先级调度器

拒绝。让 Worker 持有与主线程对等的优先级任务池，两侧需要同步排序状态、交换池快照或实现分布式优先级一致，协议面大且没有对应收益。有界在途窗口加 deadline 排序把共识压缩为两个标量，Worker 侧逻辑保持在很小范围内。

### prepared-dom 单源、构建期调 JS

拒绝。渲染点在 N 个原生线程的并行循环体内，JS 是单线程堆：逐段回调把 `TIQIAN_PRECOMPUTE_THREADS` 对渲染阶段串行化为 1；攒批则因 plan 由各线程并发产出而先串行化。把循环整体搬回 JS 不可行：thread-local 证据出借的存在理由是引擎回调在调用线程同步重入，隔一层 JS 该不变量失效，还需在 worker_threads 重造 scoped-thread 顺序保证与 panic 传播，渲染产物仍须回 Rust 拼 manifest/bundle。

### 大范围 WASM 化（引擎或 HarfBuzz 入浏览器）

拒绝重启。roadmap 记载 Edge 增强安全模式实测曾促使浏览器端 Kotlin/Wasm target 删除、HarfBuzz/WOFF2 WASM 限定在 Node precompute。重提需要新的实测证据。例外是 `DualLoweringStance` 预留的窄范围：仅 prepared-dom 一个纯函数的 wasm 化。

### 第二套 Rust 排版引擎

从未列入。EngineLevelAbi 已确立单引擎原则，Rust 侧经 C ABI 链接同一份 Kotlin/Native 引擎；新增第二实现只会重建三方 parity 负担。

## Verification

1. 五表规格定义后，TS 与 Rust 类型从同一定义生成；两侧采样器在共享 parity 语料（含 prepared-dom-corpus fixture 扩充）上的输出逐字节一致，CI 强制。
2. prepared-dom 双实现的字节比对纳入 CI，golden 语料单一来源存放，禁止两侧各自维护 fixture。
3. 双侧调度协议有独立测试：紧急批晚于后台批发送、先于其完成（优先级反转用例）；generation 不符的请求在 Worker 段间丢弃；在途窗口随 deadline 命中与超时扩缩；打包二进制请求与规格派生编码 roundtrip 一致。
4. TS 宿主重写以现 jsTest 套件为验收规格：同名行为断言逐项移植并通过后才删除对应 Kotlin 源；`LayoutDumpGoldenTest` 全程零 diff。
5. 迁移期间每个中间态满足：snapshot digest 校验照常通过、`verify-package` 与 `verify-release` 通过、已部署站点（blog 参考宿主）浏览器手工检查不回归。
6. 无消费者导出清理与 shared/ 删除各自独立提交，均以全量测试通过与 golden 零 diff 为准。
7. 声明通道有独立测试：声明在前 CSSOM 在后的合并顺序（findLast 语义下 CSSOM 胜出）、`baseUrl` 相对 URL 解析、字体已 loaded 后声明仍唤醒重验（无字体事件场景）、同帧多次声明合并为一个重验任务且执行前新声明不追加、`replaceSync` 抛错按声明缺席处理并记 DeclaredTextInvalid、注销函数移除声明并触发重验、EmptyCandidateSet 与 FieldMismatch 两类 detail 的字段形态各一组用例；dataset detail 进入时序 golden。
8. 三包拓扑有 CI 检查：包间依赖方向为 web-component → core → ffi，该方向之外的包间依赖与跨包相对路径导入使 CI 失败；`StrictTsDiscipline` 的 eslint 与 grep 检查覆盖三个包的全部 TS 代码。

## 执行清单

状态标记：`[ ]` 未开始，`[x]` 完成且验收通过。完成以验收命令与断言通过为准，
不以代码写完为准；勾选时在条目尾注提交哈希，未提交的完成以工作区测试为准。
验收引用本文件 Verification 条号，所列命令为补充；测试命令都在
`nix develop -c` 内执行。每个中间态持续满足 Verification 5。依赖顺序：前置批次
在先；0054 执行清单第一组可与其并行；A、B、C、E、F 组按进程内执行形态实施；
D 组在 0054 执行清单的 54-10（回填）完成后重测判定。B7 先按 plan 对象输入
验收，54-11 实施后输入改为条目。

### 前置：分解报告批次（web-prose-host-decomposition.md §11 表）

- [x] **P0 批次 0**：基线记录、通道与 import 图核对、Worker 必要性 bench 首测
  （判定以回填后重测为准）、时序锚点 golden 冻结。
  KPI：golden 覆盖 §11 表六类锚点，锚点数记录（报告 §11，合计 151）。
  验收：npm test、jsBrowserTest、demo/web 测试全部通过；golden 套件入库。
  提交：30528c9、b80a3bd、e34ce30、35a6abf、3874a9f、0172554、c1b457a。
- [x] **P1 批次 1**：八个模块纯移动回归原位，.d.ts 随同名 JS，根路径重导出。
  验收：同 P0 命令全部通过；golden 零 diff。
  提交：fc8cf38。
- [x] **P2 批次 2**：core/sampler/observers.js，失效源接口与四实例，A 类双重职责拆分。
  验收：npm test；demo/web resize 与 drag 系列。
  提交：18dae52。
- [x] **P3 批次 3**：engine/loaders，connectedCallback 收缩到生命周期。
  验收：npm test；demo/web。
  提交：5e6f04e。
- [x] **P4 批次 4**：engine/exact-font.js，两套会话状态机合并。
  验收：npm test；package.test.mjs。
  提交：5039835。
- [x] **P5 批次 5**：engine/face.js，派发点收拢，globalThis 读取收敛，detail.result
  改返回值（两份 loadExactFontFallback 已在批次 4 合并）。验收：npm test；jsBrowserTest；demo/web。
  提交：095c170。
- [x] **P6 批次 6**：快照四件回归原位，lazy-capabilities 拆分，element 快照失效区域
  提取，sync:shared 路径更新。验收：npm test；jsBrowserTest；web-precompute parity。
  提交：5097307、784d2ff（6a）；ea2dda8（6b）。
- [x] **P7 批次 7**：demo/web 以 @tiqian/prose 符号链接替换做 A/B 对比。
  验收：demo/web 对比数据记录。对照由 demo/web `npm-published-vs-dev` 套件执行：
  同一浏览器经 CDP 双开两页，一侧加载符号链接文件集指向的工作树（含批次 0-6，
  HEAD ea2dda8），一侧加载 registry 的 `@tiqian/prose@0.1.0-alpha.5`（重构前
  发布）。2026-08-23 记录：四个相位（initial@900、initial@700、
  after-dom-change@940、after-dom-change@700）两侧增强段落数相同（dev=41
  published=41），initial 相位像素逐字节一致，全程几何报告一致，宿主 DOM
  变更后按引擎真值断言一致；demo/web 全套 35/35。

### A 规格与引擎接口

- [x] **A1 五表规格定义**（`AssemblySchemaAsContract`）：单一 schema 定义文件，
  TS 与 Rust 类型同源生成；源语义投影规则写进规格定义。
  KPI：两侧手写类型文件 0 份；字段与 ADR 清单一致。
  验收：Verification 1 前半；类型生成进 CI。
  进度（2026-08-23）：ef06ac7 定义 ffi/schema/assembly-record.schema.json
  （revision 1，标量与六表字段、验证错误名、三 surface 字段序与两侧差异
  （gridEnabled 仅引擎接口、inlineObjects 仅运行时接口、fontSessionId 仅构建接口）、
  六条源语义投影规则与实现/测试指针）；371629a 生成器 tools/schema/
  generate_ts.py 与 generate_rust.py（零依赖、确定性输出、--check 模式），
  worker-channel 与 bench 的手写字段表删除改导入生成模块，layout_request.rs
  类型定义改生成物（#[path] 挂载），ci-assembly-record.yml 新鲜度检查进 CI。
  cargo check/fmt/test 与 npm test 393 例通过。
- [x] **A2 parity 语料扩充**：prepared-dom-corpus fixture 扩充，两侧采样器对同一
  输入输出逐字节一致。验收：Verification 1 后半，CI 强制。
  进度（2026-08-23）：3777e5b 用例 35 扩到 41（ruby plan ascent、emphasis dot
  颜色回调、cjk-emphasis 属性、second-line indent、三行 style-delta、
  inlineEdges 与 renderTextSpans 组合）。两侧命名模式（styleClassFor 之外新增
  emphasisDotColor）在 fixture 保留模式名字符串、两侧测试映射成回调，颜色字面量
  逐字符一致。Rust 侧两处差异补齐：PlanRuby 此前无 ascent 字段（比例回退
  顶替了测量值），options.cjkStrongSemantics 整条路径缺失（快照 strong span 的
  data-tq-cjk-emphasis 与 font-weight 属性）。cjk 属性写入改为对象赋值语义
  （同名键原位覆盖），与 js 对象展开一致。builder 再生幂等，TS/Rust corpus
  测试、tiqian-precompute 全部 205+测试、npm test 393 例通过。CI 连接见 F4。
- [x] **A3 ffi/js 改为字节进出面**（`SingleEngineFace`）：传输格式解析、校验与 `LayoutInput`
  组装移入引擎入口，`PrecomputeWire` parse 降为编解码器。
  KPI：ffi/js 内装配逻辑（非编解码）行数置零。
  验收：jsNodeTest 全部通过；golden 零 diff。
  提交：da92871（整体移入 `layout` 模块 `ParagraphWireFace`，`PrecomputeWire.kt`
  删除，ffi/js 只剩导出接口转发与会话连接）。
- [x] **A4 ffi/js 独立 npm 包**：单独发包，产物导出类型定义与 source map。
  KPI：.d.ts 与 .js.map 覆盖全部导出接口；@tiqian/prose 依赖切换完成。
  验收：包产物检查；消费者构建与测试通过。
  包位于 `ffi/js/npm`（`@tiqian/ffi` 0.1.0-alpha.1）。`generateTypeScriptDefinitions()`
  产出 `Tiqian-tiqian-ffi-js.d.mts`，声明两个 `@JsExport` 函数；九个引擎模块各带
  嵌入 sources 的 `.mjs.map`（dom-api 兼容层无源文件可嵌）。`@tiqian/prose` 声明
  精确依赖 `0.1.0-alpha.1`，`layout-worker.js` 与 worker bench 改从 `@tiqian/ffi`
  导入；开发侧以 `npm run link:ffi` 建符号链接指向工作树。发布工作流
  `publish-ffi.yml` 与 prose 相同，两包同一提交锁步发版，ffi 先发。2026-08-23
  验证：ffi 包测试 4/4，verify:package 通过；prose npm test 183/183；jsNodeTest
  与 jsBrowserTest 通过；两包 tarball 在隔离消费者成对安装并导入；demo/web 35/35。
  module worker 读取不到文档 import map，无打包器宿主无法加载 worker；现有宿主均经
  打包器消费，demo 的两个 import map 服务型用例在服务层把 worker 内对 `@tiqian/ffi`
  的导入改写为绝对 URL。提交：1ce873d（ffi 包）、15fb028（prose 依赖切换）。
- [ ] **A5 度量回放表扩展**（`MetricTableAsEngineInput`）：canvas 探测按同一规范键
  写同一表结构，引擎只认表；无 bake 路径经 ffi 唯一接口产出 plan。
  KPI：度量表示结构份数 1。
  验收：无快照路径端到端 plan 测试；MissingServerShapingReplay 语义不变。
  进度（2026-08-23）：现状调查与分片设计见
  docs/research/2026-08-23-a5-metric-table-unification.md（两套结构的位置、
  Worker 无 DOM 约束、空表会话与条目证据字段的待决点、A5a..A5d 顺序）。
  进度（A5a，2026-08-23）：3de7052。npm-core/replay-entry-codec.js 单点持有
  条目展开（decodeShapeReplayRow/decodeMetricReplayRow）、读取侧缩放
  （scaleShapeReplayItem/scaleMetricReplayItem）与 px→em 规范化
  （normalizeReplayNumber，复现 replay.rs 的 12 位小数与 -0 归 0）；
  snapshot-manifest.js 与 browser-font-replay.js 改为调用该模块，键函数与
  修订常量留在 snapshot-schema.js。18 例 roundtrip、损坏输入与 Rust 测试向量
  对齐；npm-core 167 例加 prose 246 例通过。
  进度（A5b，2026-08-23）：46182fc。npm-core/replay-probe.js
  （CanvasMeasureReplayProbePolicy）：会话可选注入同步 measure
  （cssFont, text）→ 度量结果；shape miss 探测产出单 glyph 条目
  （id 0、bounds null、faceId 以 canvas-probe: 前缀命名证据来源），metric
  miss 复现 WebCanvasFontMetricsResolver 的探针文本与 typo 计算，em 写入经
  normalizeReplayNumber，同键再访查表；探测失败或未注入时
  MissingServerShapingReplay 语义不变；条目校验复用 A5a 的 scale 函数。
  13 例新测试；npm-core 180 例加 prose 246 例通过。
  进度（A5c，2026-08-23）：de926c8（含 88557fc 的发布件修复）。空表会话判定
  放宽为「无 probe 才抛 ServerShapingReplayEmpty」，probe 校验前移到空表判定
  之前；replay-probe.js 增 createOffscreenCanvasMeasureAdapter（OffscreenCanvas
  或 2d context 不可用返回 null；ctx.font 缓存比较与 Kotlin currentCanvasFont
  同法）；新文件 core/engine/web-worker/session-bootstrap.js：manifestSession
  逐字搬移为 createManifestFontSession，createProbeBootstrapFontSession 以空表加
  probe 建会话（adapter 不可用抛 LayoutWorkerProbeUnavailable，错误名单仅增此
  一项）；layout-worker.js 只留消息循环，init 分支按 probeBootstrap 分派，
  "@tiqian/ffi" import 与 workerExactSubsetSourceBoundaries 连接原样保留。端到端
  parity 测试（独立文件即独立进程）以同一 fake measure 走探测会话与复现
  WebCanvasFontMetricsResolver 的 scripted backend，两侧 plan 字节一致、容差
  零命中（变异自检改 advance 立即检出）；npm-core 187 例加 prose 246 例通过。
  伴随缺陷：拆分把 core/engine/loaders/styles.js 移入 npm-core 后其相对引用的
  styles.css 不在包内，parcel 静态解析失败、运行时 URL 404；88557fc 在 npm-core
  落同名副本并列入 files，prose 测试断言两份字节一致。

### B TS 宿主重写（`TsHostRuntime`）

统一验收：对照清单同名断言移植通过；对应 Kotlin 源文件删除；npm test、
jsBrowserTest、jsNodeTest 全部通过；golden 零 diff。统一 KPI：对照清单移植覆盖率
100%，对应 Kotlin 文件行数置零。

- [x] **B1 行为断言清点**：jsTest 按主题清点断言，产出原名到 TS 用例名的移植
  对照清单。KPI：清单条目数与 jsTest 断言分组计数一致。验收：清单入库。
  产出：docs/ts-port-assertion-checklist.md（104 条、717 断言；content-reconcile
  主题在现 jsTest 无对应用例，清单留空节说明）。
- [x] **B2 段落托管与回滚**（custody，含 CustodyMoveAdoption 行为）。
  产出：custody 引擎（提交去重、状态快照、原子换入与回滚、
  CustodyMoveAdoption 重连采纳）以 custody.js（382 行）进 npm/core/engine，
  经通用化 gradle 生成器嵌入运行时 bundle；Kotlin 侧删除对应实现 451 行
  （WebEnhancerParagraphLifecycle、ParagraphPipeline 与 Support 的 custody
  段），WebEnhancerCustodyBridge.kt 桥接调用。断言经 fd50dc6 移植
  （custody-bridge.test.mjs，347 行）。提交：fd50dc6、5c978f4、febeea7。
  验证：npm test 与 jsBrowserTest 在提交后历次批次运行与当前树复验
  （315/315 两次）均通过。
- [x] **B3 渐进任务状态机**（ProgressiveJob 队列与 pending 计数）。
  产出（2026-08-23）：断言半段 71ae9a9（progressive.test.mjs 456 行，
  runtime-host.mjs 补 worker 作业驱动与滚动几何助手）；实现半段 0b03b91，
  状态机整体迁入 `npm/core/engine/progressive-job.js`（302 行 plain script，
  经 generateProgressiveJobBridge 嵌入运行时），按 custody 模式经
  `WebEnhancerProgressiveJobBridge.kt` 调用。作业注册表、generation、
  tier 跟踪与 pending 计数、分段执行、stale 守卫、parking、完成与失败
  迁移全部在 JS；作业构造（候选、measure 快照、引擎闭包）与事件派发留在
  Kotlin（WebEnhancerProgressiveJob.kt 的 startProgressiveJob helper 与
  finish/fail 回调）。`TiqianWebWorkers` 签名不变，方法改为一行桥转发；
  WebEnhancer.kt 删 progressiveJobs/generation/workerRoots 与
  ProgressiveJob/Kind 类，relayout 头部改经 jobKind 加 states WeakMap 取
  运行中作业（enhance 在 startProgressiveJob 前 states.set，两者同对象）。
  commitSkipped 无写者，完成事件的 stale 不再含常假臂（CommitSkippedRemoved）；
  MAX_PROGRESSIVE_IDLE_ITEMS_PER_SLICE 无消费者，一并删除。嵌入式单测 9 条
  （npm/progressive-job-bridge.test.mjs），覆盖 tier 阈值跳过后作业保持
  打开、stale 跳过、过期 generation 拒绝与 detach 当场跑完。jsTest 两个测试类的内部 harness
  改调 TiqianWebWorkers 对外方法（原 internal 扩展函数已删）。
  验证：npm test 324/324 两次（产物刷新前后各一次）；
  assembleNpmPackage 与 jsBrowserTest 通过；grep 复核 progressiveJobs、
  progressiveJobGeneration、workerRoots、GrantAdmission、
  PROGRESSIVE_TIER_COUNT、jobPayload 在 Kotlin 源内 0 命中。
- [x] **B4 段落资格策略与响应式度量稳定化**。
  进度（2026-08-23）：资格策略半段已完成。三个资格谓词
  （shouldTryParagraph、isPureBlockImageParagraph、hasOpaqueInlineCandidate）与
  常量（NON_TEXT_INLINE_TAGS、OPAQUE_INLINE_DISPLAYS、SKIPPED_ANCESTOR_SELECTOR）
  迁入 `npm/core/engine/eligibility.js`，按 custody 模式经通用化 gradle 生成器
  嵌入运行时，Kotlin 侧与 MarkdownParagraphLowering 经
  `WebEnhancerEligibilityBridge.kt` 调用；嵌入式单测 6 条
  （npm/eligibility-bridge.test.mjs）。提交：4a74774。
  响应式度量半段（2026-08-23）：effectiveLineMeasure、sourceParagraphWidth、
  isCurrentResponsiveMeasure 与 elementContentWidth 的 JS 体（原
  WebEnhancerSupport.kt 的 @JsFun）迁入 `npm/core/engine/responsive-measure.js`，
  同一生成器嵌入，Kotlin 侧经 `WebEnhancerResponsiveMeasureBridge.kt` 调用；
  WebEnhancerParagraphPipeline 与 WebEnhancerParagraphLifecycle 的调用点全部改走
  桥，Kotlin 实现删除。嵌入式单测 6 条（npm/responsive-measure-bridge.test.mjs，
  量化格数、最宽 fragment 减 padding、rects 为空退 bounding rect、三级宽度
  回退、同格判定）；jsBrowserTest 102/102、npm test 372/372、时序 golden 零 diff。
- [x] **B5 内容 reconcile**。
  产出（2026-08-23）：断言半段此前已随行为测试批完成；实现半段 b194156，
  分类（dead、drifted、custody、tainted、stranded 与
  StrandedCapabilityNoRetry 阈值）、只读探针 probeContentDrift 与两个 DOM
  准备助手（HostEditRelowering、CloneDescaffoldEngineMarkup，含
  EngineInlineStyleStrippingOnClone）迁入
  `npm/core/engine/content-reconcile.js`，按 custody 模式经
  generateContentReconcileBridge 嵌入运行时，Kotlin 侧经
  `WebEnhancerContentReconcileBridge.kt` 调用；WebEnhancerContentReconcile.kt
  只保留作业组装、段落跟踪与引擎动作（processParagraph、托管恢复），JSON
  判定串由 JS 侧拼接返回，与原字符串逐字节一致。嵌入式单测 6 条
  （npm/content-reconcile-bridge.test.mjs）。动作执行、视口距离排序与作业
  启动留在 Kotlin，随 B7 管线批次迁移。
  验证：npm test 330/330（含 content-reconcile 行为测试 9 条与嵌入式
  单测 6 条）；assembleNpmPackage 与 jsBrowserTest 通过；grep 复核
  prepareTrackedParagraphForRelowering 与
  stripEngineMarkupFromStrandedParagraph 在 Kotlin 源内除桥定义与调用点外
  0 残留；content-reconcile.js 嵌入方言检查（可选链、空值合并、展开、
  for-of、无绑定 catch、美元符、三引号）0 命中。
- [x] **B6 复制保真**（copy.js 投影语义保持）。
  产出（2026-08-23）：断言半段 4e0cebf（copy-fidelity.test.mjs 经 runtime-host
  驱动运行时的 copy 事件）；实现半段 8cf6ea3，`npm/core/utils/copy.js` 改为
  plain script，安装 globalThis.__TiqianCreateClipboardPayload 与
  __TiqianInstallCopyHandler，按 custody 模式经 generateCopyBridge 嵌入运行时，
  Kotlin 侧经 `WebEnhancerCopyBridge.kt` 在原有三个调用点安装，
  WebEnhancerSupport.kt 内 133 行重复实现删除；api.js 与 element.js 改为
  副作用导入后调用全局安装函数，根 copy.js 保留名导出维持既有导入面；
  TiqianWebCopyTest.kt 删除，断言由 copy-fidelity.test.mjs 承接。Kotlin raw
  string 与 JsParser 不接受可选链、空值合并、展开实参与 for-of，copy.js 按
  嵌入方言重写：可选链与空值合并展开为显式条件，展开实参改 apply，for-of
  改下标循环，语义逐处等价。
  验证：npm test 324/324；assembleNpmPackage 与 jsBrowserTest 通过两次。
  jsTest 世界没有 npm 模块导入，处理器此前由内联重复实现提供，删除后
  15 个 copySelection 断言失败，嵌入后 0 失败。grep 复核
  installTiqianCopyHandler 在源内仅余 copy.js 定义、根 copy.js 名导出与
  copy-fidelity.test.mjs 注释。
- [x] **B7 lowerer 统一**（`SinglePlanLowerer` 先行形态）：prepared-dom.js 改接受
  plan 对象，成为绘制规格唯一实现；DomParagraphRenderer 删除。
  产出（B7.1，2026-08-23）：62a7cc9，`toPreparedParagraphJson(renderEvidence)` 以
  默认省略的可选字段追加 cell 粒度与段落粒度的绘制证据；默认路径字节不变，schema 仍为
  1，两个既有读者（prepared-dom.js、tiqian-precompute plan.rs）按字段名读取、
  容忍未知字段，无需改动。`:layout:jvmTest`（含 LayoutDumpGoldenTest 零 diff）与
  `:frontend:web:jsBrowserTest` 通过。B7.2 起改 prepared-dom.js 读取这些字段。
  产出（B7.2，2026-08-23）：90de8da。prepared-dom.js 读取 B7.1 的证据字段：dash 属性
  （strategy/advance/font-family/face/glyph-ids/evidence 与 lang）、标点 ink-floor 与
  body-width、样式增量（font-size/weight/style 带 important）、latin 在着重范围内补
  italic、行内对象占位 span（data-tq-inline-object="pending" 加 object-range）、
  ruby/bopomofo 注文 span、SVG 行间线与着重圆点；断 run 与合并键扩展（dash run 不合并、
  样式与标点签名、italic、证据字体）。行构造改为按 children 有序遍历，行内对象与注音
  边界先冲刷 pending run；流宽校验改按 children 求和，bopomofo 占用 base 的松量
  （非末字 max(布局尾隙,0)，末字 max(advance−naturalWidth−行内边,0)，有注音时 base
  尾隙置零）。plan.inlineEdges 非空时优于 options.inlineBoxes。ruby ascent 无画布取
  fontSize×0.8 的降级值，B7.4 重估是否入 plan。为守 1000 行约束拆出
  prepared-dom-markup.js（8 个字符串标记构件，纯移动）与 prepared-dom-evidence.js
  （注音、占位与覆盖层构件）。验证：npm test 349/349（新增 10 条，含无证据精简输出、
  dash 属性、标点属性与断 run、样式增量、latin 着重 italic 正反例、占位流宽、ruby
  比例 ascent、bopomofo 松量与声调字号公式、覆盖层、inlineEdges 优先级）；
  `:frontend:web:jsBrowserTest` 通过。
  产出（B7.4，2026-08-23）：7569649。ruby 注文 ascent 进 plan：B7.1 序列化补
  `RubyDecisionInfo.ascent` 字段（注文字面的 declared ascent，来自度量 resolver），
  prepared-dom-evidence.js 优先读 plan ascent，缺失时退 RubyAscentRatioFallback
  （fontSize×0.8，只与 stub 度量一致，真字体 ascent 并非 0.8em）。验证：
  `:layout:jvmTest`（含 LayoutDumpGoldenTest 零 diff，golden 语料无 ruby 证据
  字段）、npm test 新增 plan ascent 正例与比例回退既有例、
  `:frontend:web:jsBrowserTest` 通过。
- [x] **B8 浏览器后处理**：占位符替换式语义克隆、SVG 行间线与着重号、
  ruby/bopomofo span 挂载、原子换入。SVG 行间线与着重号、ruby/bopomofo span
  已随 B7.2 进入 lowered HTML（90de8da）。
  产出（克隆换入原语，2026-08-23）：4fe2227。占位 span 在尾隙绝对值 ≥ 0.01 时
  增加 data-tq-object-trailing-margin（值为该尾隙）；renderPreparedParagraphInto
  在 innerHTML 换入后把 data-tq-inline-object="pending" 占位替换为调用方经
  options.inlineObjects 按 start-end 对位传入的源元素深克隆，克隆带
  data-tq-inline-object="true" 与 data-tq-object-range，尾隙存在时写
  margin-right = marginRight + 尾隙（important），与
  DomParagraphRenderer.appendInlineObject 逐项一致；缺源抛
  InlineObjectSourceUnavailable，重复区间抛 ConflictingInlineObjectRange，
  无占位的传入项忽略（与 Kotlin associateBy 后未被命中的条目同行为）。
  调用方连接未动：workerLayoutRequest 仍排除含行内对象的段落，exact 运行时路径
  仍限于 canonical plain 段落，两条路径都到不了含行内对象的 plan，连接随本项
  原子换入一起改（移除该排除，把 domInlineObjects 的元素与 margin 经桥传入）。
  产出（运行时 exact 路径扩展到富段落，2026-08-23）：exact 运行时路径的
  renderPreparedParagraphDom 桥接收与 Worker 换入桥同形的 options：sourceSpans 以
  sourceIndex（列表序）加 order（嵌套深度，并列区间的 tie-break）序列化为
  live-source semantics，元素数组同序传入；domInlineObjects 以
  {start, end, marginRight} 元数据配对元素数组传入，换入原语按区间对位深克隆。
  纯段落两条数组皆空，桥传 undefined options，渲染输出与扩展前逐字节一致。
  准入从 isCanonicalPlainParagraph 放宽为 isRuntimeExactPreparedDomEligible
  （排除 decorations、clone 边缘装饰与 locale 不匹配 span，与 Worker 请求的排除
  项一致但不再排除行内对象）；富段落照旧走 semanticExactEngine 的逐 run 降级，
  严格 exact session 仍只属于纯段落；plan 对富段落开 renderEvidence（逐 cell
  renderFontFamily、inlineObject advance、inlineEdges）。canonical-plain 属性仅对
  纯段落设置，富段落只带 canonical-source，重排经活克隆重降。Worker 请求的
  行内对象排除与 domInlineObjects 经 Worker 桥的传入属下一步（B8.2）。
  产出（Worker 路径行内对象接入，2026-08-23）：workerLayoutRequest 撤销行内对象
  排除，其余排除项与 isRuntimeExactPreparedDomEligible 对齐。请求线新增
  inlineObjects 字段：每条记录五段（start、end、advance、ascent、descent），分隔符
  与既有 wire 相同，经 ParagraphWireFace 解析进 LayoutInput；ascent 与 descent 为
  必填，行内对象的逐行度量扩张由引擎按值计算。缓存键（LAYOUT_REQUEST_FIELDS）
  纳入该字段，advance 变化即新键。plan 的 renderEvidence 判定加入行内对象非空
  （无 span、无行内盒、无行内对象的纯段落 plan 与扩展前逐字节一致）。
  ffi 的 precomputeParagraph 增补第 16 个可空参数：旧 15 参 JS 调用方缺参得到
  undefined，Kotlin 侧以空串补齐，包版本错位双向兼容。commit 桥
  renderPreparedWorkerParagraphDom 与运行时桥同形：元素数组配 {start, end,
  marginRight} 元数据，换入原语按区间对位深克隆；worker 分支的 canonical-plain
  判定从 sourceSpans.isEmpty() 改为 isCanonicalPlainParagraph()，行内对象段落
  重排时重测对象，不再误标纯段落。
  产出（着重圆点颜色、cjk-emphasis 标记与 dash 面校验进 prepared 路径，
  2026-08-23）：e2be1b4。着重圆点颜色在渲染时解析：取覆盖该 cluster 且 order
  （嵌套深度）最大的 semantic 的 getComputedStyle 颜色，无命中回退
  currentColor，与 native 渲染器 sourceSpans.maxByOrNull{depth} 的取值一致；
  无 live 元素时圆点维持 currentColor，artifact 输出字节不变。npm 侧新增
  cjkStrongSemantics 选项：按区间相等匹配 semantic，artifact 分支写
  data-tq-cjk-emphasis 与 font-weight important，live-source 分支在
  restoreLiveSemanticElements 换入克隆时补同样的标记与样式。校验器新增
  renderedDashFaceIssue：[data-tq-dash-font-family] 的 computed font-family
  与属性值比对（首个逗号前 token、去引号、小写比较），不一致时报
  RenderedPreparedParagraphDashFaceMismatch，位于段 advance 校验之后。npm test
  360/360（新增着重圆点颜色、深度优先、cjk-strong 标记与 dash 面四组）。
  产出（cjk-strong 路径连接与装饰段落准入，B8.3b 首批，2026-08-23）：
  preparedCjkStrongSemanticsJson 从带 cjkStrongBaseWeight 的 sourceSpans 序列化
  {start, end, weight}，经运行时桥与 Worker 换入桥的 options.cjkStrongSemantics
  传入，上一批的 npm 侧由此接通。isRuntimeExactPreparedDomEligible 撤销
  decorations 排除：装饰段落的 plan 无条件序列化 decorationSegments 与
  emphasisDots，运行时 LayoutInput 本就携带 decorations，富段落照常开
  renderEvidence，commit 走 prepared 分支。Worker 请求仍排除装饰段落：请求线
  没有装饰输入字段，此类段落主线程降层后经同一 prepared 桥提交。新增 jsTest：
  exact 会话下 strong-as-emphasis 段落经 prepared 路径，semantics 与 cjk-strong
  线、emphasisDots、canonical-source 与复制保真逐项断言。无 strongAsEmphasisMarks
  时 decorations 为空，默认页面行为不变。
  产出（全段落 prepared 路由与 native 渲染器删除，B8.3c，2026-08-23）：
  DomParagraphRenderer.kt 与 DomParagraphRendererOverlays.kt 删除，运行时不再
  保有第二份绘制路径。prepare 阶段 fail-closed：桥缺失报
  PreparedDomBridgeUnavailable（detail 记 expectedLayoutRevision），locale 不匹配
  span 报 SpanLocaleMismatchUnsupported（detail 记 spanRange、spanLocale、
  paragraphLocale）。isRuntimeExactPreparedDomEligible 只再排除 locale 不匹配
  span：单行克隆边缘装饰经 plan 的 inlineEdges 重放，跨行的仍由布局后的
  InlineCloneDecorationBreakUnsupported 拦截；workerLayoutRequest 维持自身更严的
  排除清单（请求线没有行数信息）。commit 校验失败时先摘属性再分支：exact 会话
  度量且浏览器回退引擎可用则以浏览器度量重排并仍经 prepared 桥重放（重试传
  browserFallbackEngine=null，递归深度有界）；否则报 PreparedDomRenderMismatch
  Unsupported，段落保持输入原样。RootState.preparedDomEnabled 只表示 exact
  会话度量是否可信，段落绘制一律走 prepared 桥。
  validatePreparedParagraphDom 的校验器全局只在测试环境存在，生产缺失时返回
  null（PreparedDomValidatorIsTestOnly），不再把每个段落判为
  PreparedDomRenderMismatch。plain host 的
  桥安装走 font-loader 的 ensurePreparedDomBridge（memoized，槽位已被占用时让位
  给已装实例），element.js 的 enhance 派发与 api.js 的 withTiqianWeb 等待它。
  demo 页经 gradle Sync 把 snapshot-schema.js 与四个 snapshot 文件按相对路径
  装进资源，index.html 的 module script 自装桥后派发
  tiqian-demo-prepared-bridge-ready，Main.kt 的首次布局等该事件。测试迁移：
  karma 102/102（run-spacing 两测删除，npm 双生覆盖同一行为）；npm 366/366，
  installPreparedRendererFixture 从 exact fixture 抽出并装进 loadHostRuntime，
  五项断言迁到 prepared 词汇（data-tq-engine-hyphen 选择器、首缩进的
  line-shift 加 --tq-line-flow-start、着重号字重落在 strong 主体、currentColor
  按 color 链解析、超脚本行宽自检改行标记双属性）。demo 页浏览器复测：可见
  段落全部 prepared 渲染，基准段 24/24，含 CJK dash 的 1 段按
  NoConformingCjkDashGlyph 保持输入原样。
- [x] **B9 MarkdownParagraphLowering 迁移**（880 行）。
  进度（第一步，2026-08-23）：33f6526。降层逻辑移植 npm/core/engine/
  markdown-lowering.js（IIFE 安装 globalThis.__TiqianMarkdownLowering，嵌入
  raw-string 约束内），gradle generateMarkdownLoweringBridge 三处连接，
  WebEnhancerMarkdownLoweringBridge.kt 只做声明。返回 `{ok, lowered|issue}`，
  classifyRole 经 helpers 回调（策略留 Kotlin，B10 处置）。npm 新增
  markdown-lowering-bridge.test.mjs 20 例（投影三模式、run 切分、opaque
  对象、失败路径、canonical 快速路径）。
  进度（第二步，2026-08-23）：c866219。facade 改调桥并解码
  （MarkdownParagraphLowering.kt 899→303 行），降层实现删除；locale 通道补齐
  （JS 缺省 zh-Hans 与 core TextStyle 一致，非空 options.locale 覆盖）；
  `??` 全部改 firstDefined（@JsFun 嵌入体不接受空值合并运算符）；
  WebEnhancerSupport.kt 删 7 个仅降层消费的 external（650→494 行）。
  `:frontend:web:jsBrowserTest`（B9a 断言组全量重放）与 npm test 393 例通过。
- [x] **B10 引擎策略出 ABI**：富文本 run 降级判定与 dash 能力判定经 ABI 输出
  决策，不迁 TS。验收补充：策略行为与现行判定逐例一致（jsTest 对应组）。
  进度（2026-08-23）：策略点 2（富文本 run 降级判定）完成，提交 7dc65e1：
  十六属性清单与首个分叉判定移入 font 模块 `InlineShapingStylePolicy`
  （`InlineShapingStyleParityContract`），markdown-lowering 只按清单收集
  规格化 computed 值，经 helpers.inlineShapingDecision 回调问判定（与
  classifyRole 同形）；issue 命名与 detail 组装在 Kotlin facade。bridge
  测试改经回调 stub 断言同名 detail（em:font-kerning），新增规格化值捕获
  与无回调跳过两例；jsTest SourceFidelity 组不改且通过，npm test 395 例、
  golden 零 diff。
  进度（策略点 1，2026-08-23）：9ef3606。dash issue 命名与 detail 组装移入
  font 模块 `CjkDashCapabilityPolicy`（null status、空白 detail、带 detail
  共五分支 commonTest），WebCanvasTextShaper 只递探针的 status/detail 证据
  并调用策略，name 与 detail 输出字节不变。TS 侧的 cjk-dash.js 删除无消费者
  的 issue 字段（宿主 Lifecycle 只读 status 与 detail；demo/web 与
  exact-session 测试读的是引擎输出的 data-tiqian-capability-issue 属性），
  期望同步更新。jsTest dash 断言组不改且通过，npm test 395 例、golden
  零 diff。两处策略点的位置记录见
  docs/research/2026-08-23-b10-engine-policy-abi.md。

### C 调度合并（`SingleCoordinator`）

- [x] **C1 通道废除**：11 个 `tiqian:*` 事件、`globalThis.TiqianWeb` 桥（9 个轮询
  方法）、TiqianWebWorkers 轮询接口删除，外部触发源直入任务池；verify-package 的
  marker 检查改为锚定桥存在的形式。
  KPI：`tiqian:` 派发点 0；globalThis 挂载 0。
  验收：grep 双零；verify-package 与 verify-release 通过；时序 golden 更新后零 diff。
  产出：`TiqianEngine` JsExport 面（11 个入口方法）成为宿主到引擎的唯一调用端。
  事件监听、`installTiqianGlobalApiBridge` 与 `__tiqianKotlinBridge` 自运行时删除，
  `install()` 只安装复制处理器；element.js、worker 通道、node 宿主与测试经
  `core/engine/face.js` 与 `runtime-loader.js` 直调，测试以 `setEngineOverride`
  替换引擎。时序 golden 以 `engineCalls` 记录替代 3 个内部事件；断言清单登记
  engine-api 3 条（docs/ts-port-assertion-checklist.md）。verify-package 的 marker
  改为锚定 `TiqianEngine`；verify-release 的隔离消费者改为成对安装工作树打出的
  `@tiqian/ffi` tarball，与锁步发版同源。TiqianWebWorkers 轮询接口删除与外部触发
  直入任务池在 C2/C3 中完成：element.js 的授予循环是该接口的现行消费者。
  验证：运行时 grep，11 个内部事件名与 globalThis 挂载均为 0（`tiqian:` 剩余命中为
  element 上的公开事件 ready/relayout-ready/relayout-error）；npm test 307/307 两次；
  jsBrowserTest 通过；verify-package 与 verify-release 通过；golden 更新后零 diff。
  提交：d78b725、5028c8f、158db36、876612e、767ecbb。
  消费者核对（2026-08-23 补记）：demo/web 全套 31/35。四项失败在 14357f3（A4 提交）
  与 fd50dc6 的净检出 worktree 复测中逐字节相同，C1 与 B4c 的提交不引入这些失败；
  此前两次 35/35 记录产生于含未提交改动的夜间工作树。两项按如下处置：
  resize-destroy 的 relayout 计数从已删的 `tiqian:relayout` 迁到 element 上的
  `tiqian:relayout-ready`（事件记录器同时从事件 target 取 root），迁移后该套件
  10/10。oneshot-equivalence 的选项捕获与 one-shot 重放仍依赖已删的
  `tiqian:enhance-progressively`/`tiqian:enhance` 通道，公开面上没有逐 root 已解析
  options 的读取口，待公开 API 决定后迁移。late-enhance 第 3 条暴露既有不足：页面
  内禁用后启用的增强在单次同步提交内完成，coordinator 的逐分段视口补偿从未
  触发（scrollTop 拦截为零次写入），滚动位置完全由浏览器原生 scroll anchoring
  承担；无动画时原生承担方向正确、入场动画进行中会反向跳变（scrollY 5022 到
  5911，锚点移动 1006.69px）。该不足属调度路径（增强未经授予路径），随 C2/C3
  处置。
  消费者核对补记（2026-08-23）：4370925。EnhanceOptionsOracle：element.js 在
  增强前把逐 root 已解析 options 写入 dataset.tiqianEnhanceOptions，demo/web
  暴露 __tiqianOneShot 入口；oneshot-equivalence、oneshot-visual-regression 与
  resize-destroy-transient 三套测试改读 dataset，删除对已删事件通道的最后依赖，
  时序 golden 同步再生成。oneshot-equivalence 第一阶段逐字节一致；第二阶段剩余
  分歧为 dash 探测包络过期（enhance 时读一次 root.textContent，其后追加的
  长破折号不再探测，协调侧停留 not-needed），修复需在 reconcile 刷新
  RootState options，随端口计划 Slice 6 处置。drag 预算两断言超限
  （DragMutationRecordBudget 25189>21000；ResponsiveFinishSkipsDoomedSignatureReads
  gBCR 12.13>4、gCS 53.13>24，基线注释为 3.0/18.2），待判定缺陷或基线更新。
- [x] **C2 任务池统一入池**（`CoordinatorOwnedDispatch` 进程内段）：帧内全部工作
  经同一池与同一凭证；executor 私有节奏与 standalone 准入排除。
  验收：时序 golden 授予轮锚点更新后绿。
  产出（C2a，提交 c7acecf）：worker-channel 准备循环删除自有节奏
  （MAIN_SLICE_BUDGET_MS 与 yieldMainIfNeeded），逐段向 coordinator 申请共享准入；
  grantImmediate 的立即窗口提取为 #admitMainSlice，prepaint 与 prepare 两条帧外
  主线程路径共用同一份额；凭证加表示授予来源的字段（polled 授予 grant、pre-paint 授予
  prepaint），帧 trace 末列记录窗口已花费；准备循环只把同步段计入窗口
  （SyncOnlySliceAccounting），worker 往返等待不计入。element.js 传入
  coordinator 单例；browser-fonts 与 timing-golden 的通道测试改传总是准许的池。
  产出（C2b，提交 6e3e906）：standaloneGrantAdmission 与两个上限常量删除，无
  coordinator 的直调宿主作业一次跑完；宽度正确性由 processItem 内逐条 measure
  守卫承担，分段头部 stale 检查保留为协调路径的中途放弃。
  验证：npm test 313/313 两次（两批各自跑）；jsBrowserTest 通过（两批各自）；
  golden 仅加该字段与 trace 末列（39 行插入），event-dispatch、
  token-transitions、dataset-first-writes、cache-invalidation 四条 journey 零
  diff；grep MAIN_SLICE_BUDGET_MS、yieldMainIfNeeded、standaloneGrantAdmission、
  两个上限常量均 0 命中。demo/web 的 scroll-adaptive-quota 由失败转为通过
  （滚动驱动增强期间最大事件循环延迟 257.40ms 降到 4.10ms，覆盖 36/36）。
- [x] **C3 worker-layout 准备循环并入**：pending/plans 进协调器任务池，准备循环
  删除。KPI：主线程调度循环 3 收敛为 1。验收：npm test；jsBrowserTest。
  产出：worker-channel 导出 createPrepareJob(root, exactFontSession, options,
  isCurrent)。异步段完成守卫、API 检查、会话核对、候选排序与 ensureSession
  等待，返回带 done、settled、step(shouldYield) 的作业对象；step 同步构造
  请求并发送，发送不等待回复，回复在自身微任务里写入计划并递减在途计数，
  全部候选应答后作业完成。coordinator 新增 runPrepare：注册作业并返回
  promise，#pollPrepare 排在 #pollWorkers 之后按同一帧预算推进，每个作业
  每帧送达至少一个候选；worker 回复经 onSettled 再次启动帧循环；unregister
  与 remove 经 #cancelPrepare 完成成员。element 在 enhanceProgressively 前
  等待 runPrepare，派发顺序不变。审查补入 CancelledPrepareSettlesEarly：
  isCurrent 失效且候选未尽时作业以已存计划当场完成并删除该成员，消除
  relayout 顶替增强后成员滞留、帧循环持续保持的路径。
  KPI 复核：prepareWorkerLayouts、yieldToMain、grantPrepareSlice、
  yieldMainIfNeeded、MAIN_SLICE_BUDGET_MS 源内 0 命中；scheduler.yield 仅存于
  快照采样器（precomputed.js；快照采样属独立子系统）；准备路径的私有循环
  并入完成，主线程调度循环 3 收敛为 1。
  验证：npm test 315/315 两次；jsBrowserTest 通过；时序 golden fixture 零
  diff；demo/web 全套顺序执行 34/35，其中 resize-destroy 10/10、drag 3/3、
  late-enhance 3/3；唯一失败 oneshot-equivalence 为 C1 补记登记的遗留项，
  待逐 root 已解析 options 的公开读取口决定后迁移。
  late-enhance 第 3 条（C1 补记移交本批）修复与测量教训：run-to-completion
  增强与 relayout 派发原先在锚点补偿范围外，element 调用点加同任务
  capture/compensate 对并持有原生锚定（RunToCompletionAnchorBracket）；快照
  采纳的逐段提交经 anchors 参数取得同任务对
  （SnapshotAdoptionAnchorCompensation）。修复后锚点段落位移 1038.61px 降到
  0.61px。demo 断言纪律：demo 的 parcel 缓存在更换服务器后仍提供旧
  transform，三个代码状态测得逐字节相同的失败值即由此产生；跑 demo 断言前
  须停止 8888 服务器并删 demo/web/.parcel-cache。

### D Worker 判定与执行地点（依赖 0054 的 54-10）

- [ ] **D1 判定重测**：node、bun、`--jitless` 净成本 bench 在回填后负载重跑，
  结论（移除、全量保留、阈值激活）记录。
  KPI：判定数据按分解报告 §5 模板记录。
  验收：0054 Verification 5 末句即本项。
- [ ] **D2 执行地点实施**（按 D1 结论二选一）：
  - 移除：exact 与 fallback 回主线程；修订清单（`HostDeviceTopology` 执行装置项
    与 Consequences 图、`ExecutionInWorker` 全条、`WireFormatPerBoundary` Worker 段、
    `CoordinatorOwnedDispatch` 在途窗口与紧急批发送段、Verification 3 跨线程用例）
    随判定提交。验收：修订后全量测试通过。
  - 保留：执行移入 Worker，首批视口同步快路径保留；deadline 与 generation 双标量、
    在途窗口、紧急批实施；二进制请求打包与 transfer。验收：Verification 3 四用例；
    时序 golden 记录格数区间切换的帧。

### E 字体证据（`DeclaredFaceEvidence`）

- [x] **E1 声明通道与解析**：`declareTiqianFontFaces` 与显式 `baseUrl`；
  CSSStyleSheet 构造解析、detached style 降级、缺席记录；候选集声明在前
  CSSOM 在后。验收：Verification 7 前三组用例。
  产出（2026-08-23）：897245a，`npm/core/sampler/snapshot/declared-faces.js`
  模块作用域注册表：同一 `(cssText, baseUrl)` 引用计数，注销函数置零移除，空串与
  全空白 no-op，变更同步通知 `onDeclaredFacesChanged` 订阅者，不新增
  globalThis 名。解析阶梯为构造 CSSStyleSheet 加 replaceSync，降级构造
  detached `<style>`，规则都取不到时记 DeclaredRulesUnavailable，replaceSync
  抛错记 DeclaredTextInvalid 并携带异常名。precomputed.js 的同步与协作两个
  采集器在 styleSheets 遍历前先遍历 declaredFaceSheets()，声明规则的 URL 按
  声明 baseUrl 解析（采集器以 visit 的 fallbackBaseUrl 入参解析，构造 sheet
  的 baseURL 选项不参与该路径）；collectFontFaces 导出供测试断言合并顺序，
  api.js 公开 declareTiqianFontFaces。
  验证：npm test 337/337（declared-faces.test.mjs 7 条：空串 no-op、引用计数
  与共享声明只通知一次、声明在前与 URL 基准断言、同 family 两条 CSSOM 在后
  由 findLast 胜出、DeclaredTextInvalid、无 CSSStyleSheet 环境的
  DeclaredRulesUnavailable、通知与退订）；jsBrowserTest 通过；grep 复核
  declaredFaceSheets 在 precomputed.js 为 1 处 import 与 2 处调用，
  relevantFontFaceLiveSignature 函数体无 declared 引用（声明变更的重验走
  E2 的通知，不进 CSSOM 漂移签名）。
- [x] **E2 重验入池与注册表生命周期**：唤醒不内联执行；每 root 至多一个 pending
  重验任务、同帧合并；引用计数注销。验收：Verification 7 对应用例。
  产出（2026-08-23）：402ea3a。`createTypographyInvalidationSource` 在 start() 订阅
  `onDeclaredFacesChanged`、stop() 退订；element.js 的 handler 以 force 走
  `#scheduleTypographyCheck(true)`，注册表变更无 FontFaceSetEvent 且声明 sheet 不进
  CSSOM 签名，必须 force 才能越过比较。同帧合并由 `#scheduleTypographyCheck` 既有的
  rAF 去重承担，不新增 pending 结构。测试三层：declared-faces.test.mjs 用真 source 验证
  订阅、注册与注销都唤醒、stop 后不再唤醒；element.test.mjs 用 timing-golden 的
  element drive 驱动元素实体端到端（S1 settle 后两次同帧声明合并为一次
  enhanceProgressively；补发 relayout-ready 结束首个任务后再声明触发 destroy 加
  enhanceProgressively 的一次刷新；禁用后声明既不排帧也不产生引擎调用）。驱动期间发现
  stub 引擎不会完成第一个唤醒打开的排版任务，排版观察停在停止状态；drive 以运行时
  在 root 上派发的 relayout-ready 事件补上完成信号。timing-golden-host.mjs 为此把
  S1 建场抽成 startElementDrive 供两条驱动共用，冻结 golden 零 diff 证明抽取行为
  不变。
- [x] **E3 不匹配解释结构化**：EmptyCandidateSet 与 FieldMismatch 两类 detail、
  字段核对顺序固定、dataset detail 进时序 golden。验收：Verification 7 末组用例。
  产出（2026-08-23）：b97b794。`cssFaceContract` 的失败返回携带结构化 detail
  （候选集为空时 `{kind: "EmptyCandidateSet"}`；有候选时不符时
  `{kind: "FieldMismatch", expectedFaces, actualFaces, firstField}`），
  `computeFirstMismatchingField` 按 family → style → weight → unicode-range →
  src 的固定顺序逐步过滤给出第一个不符字段。`formatContractMismatchDetail`
  把它编进 `SnapshotExactFontContractMismatch` 的 detail 字符串
  （browser-fonts.js），api.js 的消息解析与 element.js 的
  `exactFontMissDatasetValue` 各自识别两类后缀；dataset 值随
  exact-font-contract-mismatch 过程进入时序 golden（s1-adopt 与 s4-reconnect
  两条 dataset write 记录 `...|FieldMismatch|expectedFaces=1|actualFaces=1|
  firstField=src` 全形态）。Verification 7 末组用例：precomputed.test.mjs 覆盖
  EmptyCandidateSet 字段形态、五级 firstField 顺序与两类 detail 的校验出口，
  browser-fonts.test.mjs 覆盖消息后缀两形态，element.test.mjs 覆盖 dataset 值
  正则与具体值。

### F 收尾

- [x] **F1 无消费者导出清理与 shared 删除**（`UnusedExportCleanup`）。
  进度（第一步，2026-08-23）：93124d6。删 digest.js、font-contract.js 与
  package.json files 条目；删 validatePrecomputedExactFontReplayRuntimeContract
  别名与 loadedPrecomputedSnapshots 导出，两处测试改用正名
  （validatePrecomputedExactFontReplayContract 与 isLoadedSnapshotAdopted）。
  进度（第二步，2026-08-23）：c0d2712。prose 包新增 ./prepared-dom 导出与
  prepared-dom.d.ts；web-precompute 删除 shared/ 五个副本与
  sync:shared/check:shared 脚本，改依赖 @tiqian/prose 0.1.0-alpha.5
  （link-prose.mjs 建工作树符号链接），renderPreparedParagraph 与 styles.css
  经包导出消费。
  验收：Verification 6。
- [ ] **F2 三包拆分**（`ProseCoreLayering`）：`@tiqian/prose` 拆为 core 与
  web-component 两个 npm 包，连同 ffi 包共三个；依赖方向 web-component → core →
  ffi 单向，跨包相对导入 0；kotlin-js-store 回归原位。可在 B 组之前执行，使 TS 移植
  全程处于包边界内，跨层引用即时暴露。
  KPI：包数 3；跨包相对导入 0。
  验收：Verification 8；verify-package；demo/web 测试。
  进度（第一步，2026-08-23）：bf506b3。新包 @tiqian/prose-core
  （frontend/web/npm-core，0.1.0-alpha.5，依赖 @tiqian/ffi）：core/ 整树、
  顶层引擎模块（snapshot-schema/manifest/tables/table-binary、
  browser-font-replay、layout-worker 与六个顶层垫片）与运行时产物通道迁入；
  @tiqian/prose 留原目录成为 web-component 面（api、element、prepared-dom、
  snapshot-client、styles），依赖 prose-core，对外 exports、metadata 与版本
  不变。跨包引用经包名子路径；Gradle 桥生成与产物路径、assembly-record
  schema 与类型生成器目标路径、link-prose（双链接）、ci 语料 job 的
  link:core 步与 ci-assembly-record 路径过滤同步。prose-core 149 例加
  prose 246 例（合计与拆分前 395 例一致）、web-precompute 72 例、
  jsBrowserTest、assembleNpmPackage、语料再生 git diff --exit-code、两侧
  verify:package（runtime 标记与 wasm 禁令随产物迁入 prose-core 侧）全部
  通过；跨包相对导入与反向依赖 grep 零命中。测试文件
  browser-fonts-fixtures.mjs 与 snapshot-dom-fixtures.mjs 两侧各有消费者，
  各留一份副本。待办：kotlin-js-store 回归原位已于 2026-08-29 完成（git mv 至
  ffi/js/kotlin-js-store，root build.gradle.kts 经 kotlinYarn.lockFileDirectory
  固定；:ffi:js:jsNodeTest 通过，kotlinStoreYarnLock 回写与迁移前字节一致）；
  demo/web 消费端指向旧快照副本，刷新为独立后续；Verification 8 的 CI 拓扑检查随
  F3 配置。
  进度（拓扑 CI，2026-08-23）：e2123ca。tools/package-topology/check.mjs
  （零依赖 node 脚本）查两件事：三包 package.json 的 @tiqian/* 边只允许
  prose→prose-core、prose→ffi、prose-core→ffi；发布源内相对导入解析后
  逸出本包且落入另一拓扑包即失败。扫描规则与 ts-discipline 的 patterns、
  ignores 一致（另排除 *.test.mjs）。逸出包外但目标位置在三个包之外（现存
  bench 对 web-precompute 的两条 dev 导入）记 note 不失败，留
  TIQIAN_TOPOLOGY_STRICT=1 升级开关。ci-package-topology.yml 与
  ci-ts-discipline 同骨架（同对 SHA-pinned actions、concurrency、
  contents: read，无 install 步骤）。正向 78 文件零违规、反向依赖边与
  跨包导入注入各非零退出，均本地验证。
  进度（demo 消费端，2026-08-23）：93371ea。demo/web 改为直接消费三包拓扑：
  package.json 以 file: 覆写把 @tiqian/prose-core 与 @tiqian/ffi 指向
  frontend/web/npm-core 与 ffi/js/npm 的产物目录，import map 增 /npm-core/
  路由，layout-worker 路径改由 npm-core 目录解析；framework-commit-conflict
  与 npm-published-vs-dev 两个测试文件随该提交进入仓库。两条发布金丝雀
  （npm-published-vs-dev、scroll-adaptive-quota）在下次 @tiqian/prose 发布前
  保持失败，属设计。
  进度（jsMain 置零路径，2026-08-23）：a460ab7。端口计划
  docs/research/2026-08-23-tshost-runtime-port-plan.md 按七个 Slice 给出 jsMain
  运行时到 TS 的移植顺序、jsTest 102 个测试函数的删除节奏与 kotlin-js-store
  回归原位（Slice 7）。该计划同时更正两处依赖次序：jsTest 计数随 5c76cf6 等五个提交
  漂移到 102；Kotlin 删除统一推迟到消费者所在文件被删除的 Slice（6aae1b7），
  中间桥只产出后续 Slice 会删除的脚手架。
  进度（Slice 1，2026-08-23）：43bed65。npm-core 新增
  core/engine/lowered-paragraph.js（LoweredParagraph 传输格式的 JSDoc 模型与
  isCanonicalPlainParagraph、isRuntimeExactPreparedDomEligible 两个谓词，
  语义与 Kotlin 扩展逐条一致）与 lowered-paragraph.test.mjs（10 例）。
  npm-core 197 例、ts-discipline 通过、LayoutDumpGoldenTest 零 diff。
  进度（Slice 2a，2026-08-23）：0be8ac5。npm-core 新增 core/engine/lifecycle.js
  （globalThis.__TiqianLifecycle：optionsFromJs 解码、精确字体 session 谓词、
  capability 标记的捕获与还原、宿主尺寸捕获与稳定；Kotlin 同名实现随 Slice 6
  删除）与 lifecycle.test.mjs（26 例）。
  进度（Slice 3a，2026-08-23）：b8bc5d9。lowered-paragraph.js 增补
  preparedSemanticReplayJson、preparedInlineObjectMetaJson、
  preparedCjkStrongSemanticsJson 与 escapeJson。复查时对照
  npm-core/runtime/tiqian-web.js 的编译产物更正一处数值格式：Kotlin/JS 的
  Float append 编译为 n.toString()，整个产物没有 fround，marginRight 按原值
  输出，不做 32 位舍入。
  进度（Slice 3b，2026-08-23）：733d779。npm-core 新增
  core/engine/worker-request.js（globalThis.__TiqianWorkerRequest：
  workerLayoutRequestJson 按 Support.kt 的字段次序逐字段序列化，
  workerLayoutRequest 按 Pipeline.kt 第二重载做准入判断后取
  effectiveLineMeasure；首重载随 Slice 4 移植）与 worker-request.test.mjs
  （13 例，含富语料整串比对与逐条准入判断）。npm-core 249 例、ts-discipline
  通过。
  进度（Slice 3c，2026-08-23）：7776c20。ffi/js 新增
  LoweringHelperExports.kt：classifyFontRole、
  unsupportedInlineShapingProperties、firstDivergentInlineShapingProperty
  三个 @JsExport，字体模块保持唯一实现；package.test.mjs 与
  verify-package.mjs 的导出接口清单同步到五项。:ffi:js 的 npm 测试与
  jsNodeTest 通过。
  进度（Slice 3d，2026-08-23）：cbb3f9e。layout 的 ParagraphWireFace 拆出
  共有的 layout 组装，新增 planWithDiagnostics(zeroAdvanceEpsilonPx)；
  PreparedParagraph 增补 toPlanWithDiagnosticsJson：diagnostics 内嵌
  capabilityIssues 与 advanceSuspects 两组事实，suspect 的 advance 一律
  序列化为字符串以携带 NaN 与 Infinity，判定由宿主完成。ffi/js 新增
  @JsExport precomputeParagraphWithDiagnostics（十六参加 epsilon），
  ParagraphWireFaceTest 增四例，导出接口清单同步到六项。:layout:jvmTest 与
  golden 零 diff；:ffi:js 的 npm 测试与 jsNodeTest 通过。
  进度（Slice 4a 第一批，2026-08-23）：73d46db。npm-core 新增
  core/engine/canvas-fonts.js 与 canvas-metrics.js：WebFontFamilies、
  cssFamilyToken、StubFontMetricsResolver 与 WebCanvasFontMetricsResolver
  的 TS 移植，度量经注入的 canvas context 工厂取得，模块自身不触碰
  document；canvas-fonts.test.mjs 与 canvas-metrics.test.mjs 共 27 例。
  npm-core 276 例、ts-discipline 通过。canvas shaper 移植与 ffi
  browser-metrics 导出随后分片进行。
  进度（Slice 4a 第二批，2026-08-23）：6625372。npm-core 新增
  core/engine/canvas-shaping.js：WebCanvasTextShaper 的 TS 移植，含共享 LRU
  度量缓存（命中重插、超 2048 逐出最旧）、字体加载失效、dash 能力策略、
  ellipsis 显示替换判定、hidden-DOM 回退与栅格化 ink bounds，全部经注入的
  env 取 DOM 与 canvas。canvas-shaping.test.mjs 13 例；npm-core 289 例、
  ts-discipline 通过。
  进度（Slice 4a 第三批，2026-08-23）：4256f83。ffi/js 新增 BrowserMetricsExports：
  JsCallbackTextShaper 与 JsCallbackFontMetricsResolver 经两个 JSON 回调承接
  shaping 与字体度量，ShapingInput 与 FontMetricsRequest 的序列化字段序固定；
  解析侧按字段组区分 null 语义（advance 组 null 还原 NaN，偏移组 null 取 0），
  FontMetricSource 按名解析、未知值抛出。@JsExport
  precomputeParagraphWithBrowserMetrics（十六参加 epsilon 加两回调）走
  planWithDiagnostics。BrowserMetricsExportsTest 八例含回调回显与直连
  字节相等；导出接口清单同步到七项。
  进度（Slice 4a 第四批，2026-08-23）：7205314。npm-core 新增
  core/engine/browser-metrics-bridge.js：__TiqianBrowserMetricsBridge 把
  canvas shaper 与 metrics resolver 适配为 precomputeParagraphWithBrowserMetrics
  的两个 JSON 回调，唯一字段映射是 candidateKey 到 candidate.key，NaN 由
  JSON.stringify 的 null 表示承载。browser-metrics-bridge.test.mjs 六例：两组
  请求字节锁、端到端 plan、与 scripted canvas-model 后端全量比对、dash 能力
  透传。npm-core 295 例、ts-discipline 通过。Slice 4a 完成。
  进度（Slice 4b 第一批，2026-08-23）：5502736。排版流水线
  ParagraphWireFace 新增 parseDecorations（三字段记录，InvalidDecorationWire、
  InvalidDecorationRange，DecorationKind 按名解析），layout 与
  planWithDiagnostics 尾部携带 decorations 与 emphasisDotGapEm（null 取
  DEFAULT_EMPHASIS_DOT_GAP_EM，非有限或负值抛 InvalidEmphasisDotGapEm）；
  renderEvidence 判定补 decorations 非空，装饰独占的段落与直连路径一致取得
  渲染证据。两条诊断路径 ffi 导出尾部加可空同形参数，JS 调用方省略尾参时
  行为不变。ParagraphWireFaceTest 六例、BrowserMetricsExportsTest 一例；
  golden 无差异。
  进度（Slice 4b 第二批，2026-08-23）：5ff3a99。npm-core 新增
  prepare-paragraph-layout.js：准备步骤直连移植，返回 unchanged、
  unsupported（命名能力事实）或 ready 三种裁决；wire 序列化器与
  worker-request.js 同值双写，两文件保持可嵌入；exact session 命名能力
  失败时整段改走 browser metrics，逐 run 回退不移植（沿 Slice 4a 记录）；
  maxWidthPx 取量化测度，ready.width 保留原始宽度。21 例单测含两条 ffi
  导出位置参数的字节锁。npm-core 327 例、ts-discipline 通过。
  进度（Slice 4b 第三批，2026-08-23）：dae7929。worker-request.js 新增
  workerLayoutRequestForRoot：root 范围判定、shouldTryParagraph、
  allowsSnapshotExactLayout、withRootDefaults 之后经 markdown lowering 桥
  取 lowered，helpers 由 3c 的三个导出注入；lowering 抛错或 ok 不真返回
  null 且不读 issue（只有 processParagraph 报告 lowering 问题）；随后走
  既有 lowered 序列化。12 例单测；withRootDefaults 的桩在还原段恢复原
  方法。
  进度（Slice 4b 第四批与 4c，2026-08-23）：f31638b、bd4e719、6496422。
  排版流水线 ParagraphWireFace 的 plan 与 planWithDiagnostics 以及三条 precompute
  ffi 导出尾部新增可空 renderEvidenceOverride：省略时沿用 wire 四集合判定，
  传入时取宿主判定（isCanonicalPlainParagraph 的六集合；sourceSpans 与
  domInlineObjects 不上 wire，纯链接段落两条路径的 renderEvidence 结论不同）。
  prepare-paragraph-layout.js 计算六集合判定并作为尾参传两条布局导出；Kotlin
  侧 plan、planWithDiagnostics 各三形态加 ffi 一例共七例，golden 无差异。
  npm-core 新增 commit-prepared-paragraph.js：两个 commit 函数直连移植，
  worker 路径记录 effectiveLineMeasure 并 stampRendered，直连路径 mismatch
  时按 ExactSessionMetricDistrust 以去 exactFontSession 的选项重准备并递归
  提交一次（browserFallback 置空，二次 mismatch 关闭为 PreparedDomRender
  Mismatch）；渲染包在 __tqCustodyEngineWrites 计数窗口内，planJson 直接取
  准备裁决（六集合判定已经由准备步骤传入，与 Kotlin 提交时再序列化的结果
  一致）。10 例单测；npm-core 338 例、ts-discipline 通过。
  进度（Slice 4b 第五批与 4d-1，2026-08-23）：aece337、a2caef8。worker
  请求 JSON 在 inlineObjects 之后携带 renderEvidence 六集合判定，layout
  worker 原样转发为 ffi 尾参（旧宿主缺字段时 undefined 落到可空参数为
  null，wire 判定作为回退，双向版本偏斜安全；仓库内 ffi 调试副本已随 bd4e719
  重建，npm-core canary 全量走新签名）。npm-core 新增 process-paragraph.js：
  processParagraph 与 layoutParagraph 分发的 TS 编排模块，按 Kotlin 89-264
  逐步移植：eligibility、样式捕获、降级（DomLoweringFailure 与
  UnsupportedParagraph 两条失败路径）、custody begin 十四参、
  applyConfiguredHostFontSize、activeOptions、worker 请求与 plan/issue、
  canUseRichBrowserFallback、exact worker 检查（style 属性还原）、take 与
  stabilize、rendered/runtime-render-font、commit、worker 与直连两条 commit
  分发、失败 restoreParagraph；三个 prepared 元数据 JSON 构建器与降级
  helpers 以内联孪生进入模块（ESM 源不可 import）；issue 对象补 element
  与 reportToConsole 缺省（reportIssue 读这两个字段，等价 Kotlin
  CapabilityIssue 缺省）。12 例单测；npm-core 352 例、ts-discipline 通过。
  进度（Slice 5a，2026-08-23）：f3e0874。process-paragraph 的三个内联元数据
  构建器与 escapeJson 移入 core/engine/prepared-metadata.js，成为各编排模块
  共用的单一 plain-script 模块，编排模块改为消费 __TiqianPreparedMetadata。
  新增 core/engine/progressive-relayout-session.js：WebEnhancer.kt 407-477
  ProgressiveRelayoutSession 的 TS 移植。构造快照（段落分段、Map 快照、
  成功与不支持两组配对、两个状态前照）、processItem 三分支（unchanged 直返；
  unsupported 先 captureLive 再入组并 restoreParagraph；ready 先 captureLive
  再以 RAW state.options 提交、成功记 lastMeasure、失败入组并还原）、finish
  的条件性 measure 重置与逐项 splice/上报、rollback 的列表还原、按插入序
  custody.rollback 与按 source 身份补 lastMeasure。12 例单测；npm-core 365 例、
  ts-discipline 通过。
  进度（Slice 4d-2a，2026-08-23）：eeebdb6。build.gradle.kts 以
  registerBridgeGenerator 再注册九座桥（lifecycle、worker-request、
  prepare-paragraph-layout、commit-prepared-paragraph、process-paragraph、
  canvas-fonts、canvas-metrics、canvas-shaping、browser-metrics-bridge），
  srcDir 与 compileKotlinJs dependsOn 各补九行。六个包装文件给出类型化
  external interface（LifecycleBridgeJs 十一成员全量）与 require 型安装
  accessor；browserMetricsBridge 的安装闭包按 fonts、metrics、shaping、
  bridge 的依赖序装满四个 global。TiqianWebBridgeInstallTest 七例以 @JsFun
  探针断言安装产物。compileKotlinJs 与 jsBrowserTest（109 例）通过。
  进度（Slice 4d-2b，2026-08-24）：6f5e031。宿主切换到 TS 编排模块。build
  gradle 再注册 prepared-metadata 与 progressive-relayout-session 两座桥并补
  api(project(":ffi:js"))。新增 WebEnhancerTsHost.kt 为互操作核心：ffi facade
  五成员以显式参量 lambda 包装 @JsExport（browserMetrics 被
  prepare-paragraph-layout.js 以 apply 展开，缺省参量不匹配该调用形态）；
  选项双轨规范化，toTsOptions 先 optionsFromJs 再 withRootDefaults 供引擎
  state，toTsCanonicalOptions 只做 optionsFromJs 供 worker 请求（TS 侧自跑
  快照准入判断与 root 缺省，喂入已解析的字体 family 会让该判断每次失败）；
  browserFallback 描述符内建 canvas 与 span 探针工厂（env 描述符含
  attachProbe 幂等挂载）；引擎 state 描述符携带 ffi、选项、exact 会话、
  browserFallback、三个回调与两个按引用共享的活数组（TS 会话模块对同一
  数组 push 与 splice，Kotlin 宿主经 @JsFun 索引器读写，external interface
  上的 operator get 编译为 .get() 方法调用而普通数组没有该方法）。段落粒度的
  processParagraph 参数为 {ffi, paragraph, state}，ffi 位于参数顶层（模块读
  argument.ffi）。WebEnhancer.kt 的 enhance、enhanceProgressively、relayout、
  destroy、refresh 全部改走 TS 编排器：relayout 会话经
  createProgressiveRelayoutSession，宽度采样经 responsive-measure 桥；Kotlin
  侧 ProgressiveRelayoutSession、ParagraphLayoutPreparation、
  ParagraphCommitResult、EnhancedParagraph 四个类删除；
  WebEnhancerParagraphPipeline.kt 的删除从 4d-3 提前到本 Slice（切换点就是
  它的全部消费者）。行为差异两处随切换固化：其一，计算字号为零的段落先前
  进入引擎并由 advanceSuspects 报 InvalidWebShapingAdvance，现在
  ParagraphWireFace 的输入校验先行拒绝（InvalidFontSize），process-paragraph
  的 catch 汇报为 WebEnhancementFailure、detail 携带 InvalidFontSize，段落
  保持原生与 issue 上报的失败关闭结果不变，两例 jsTest 期望随之更新；其二，
  无键富段落在 exact 会话单 run 失败时按 4a 决策整段重试 browser 度量，
  dash 能力非 conforming 时该 run 失败关闭（NoConformingCjkDashGlyph），
  段落保持原生，原 per-run 混排用例改写为记录此结果。
  jsBrowserTest 112/112 通过。
  进度（Slice 4d-3，2026-08-24）：78adf6a、596c0a1。删除随切换移除的
  Kotlin 实现与对应 jsTest。实现部分（78adf6a，-747 行）：
  WebEnhancerSupport.kt 删 ExactSessionBrowserFallback 两包装类、
  workerLayoutRequestJson 与三个 worker 记录分隔符、LoweredParagraph 的三个
  prepared 元数据 JSON 扩展、takePreparedWorkerLayoutPlan 与
  preparedWorkerLayoutIssue 两个 worker 侧查询函数、renderPreparedWorkerParagraphDom
  与 renderPreparedParagraphDom 及 CustodyEngineWriteSuspension 注释、
  releasePreparedParagraphDomStyles、isPreparedDomBridgeAvailable、
  validatePreparedParagraphDom、isExactFontSessionCapabilityFailure 判定与
  EXACT_FONT_SESSION_CAPABILITY_FAILURES 清单、hasClosest、consoleWarn、
  paragraphIsWithinProgressiveForegroundRange、elementAttributesJson、
  appendWorkerJsonString、INLINE_EDGE_EPSILON 与 ZERO_ADVANCE_EPSILON 常量及
  Event 与 kotlin.js.js 两个死 import（上述成员在删除后全部零引用，逐一
  grep 验证）；MarkdownParagraphLowering.kt 整文件删除（lower 与
  decodeLowered 的 Kotlin 入口、LoweredParagraph 与两个谓词，TS 侧
  markdown-lowering.js 为唯一实现，markdownLoweringBridge 的全局安装与桥文件
  保留）；WebEnhancerParagraphLifecycle.kt 删 reportIssue、clearIssue 与
  restoreAttribute 三个成员（optionsFromJs 保留，EngineExport 仍消费）；
  WebEnhancer.kt 删 CapabilityIssue data class。测试部分（596c0a1，-750 行）：
  先验证 npm 侧 exact-session（19 例）、renderer-output（10 例）、
  renderer-source-fidelity（10 例）与 timing-golden（1 例）四套件 40 例通过，
  再删 TiqianWebExactSessionTest.kt（20 个测试，规格已由上述 TS 套件覆盖）。
  compileKotlinJs 与 jsBrowserTest（92/92）通过。实现删除一路委托执行
  与（套件验证与测试删除）两路并行委托，diff 复核后补删规格
  范围外的零引用成员。
  进度（Slice 5，2026-08-24）：afb0fde、62be699。npm-core 新增
  core/engine/root-state.js（globalThis.__TiqianRootState：WeakMap 状态表与
  DetachedRootWeakOwnership、createRootState 自 bag 起点的解析链与快照
  准入检查、createRootStateFromCanonical 供已解析选项再入、engineState 十字段
  描述符与 processParagraph/session/prepare 三个参数构建器、
  paragraphCandidates 的 RuntimeEligibleMeasureSet 过滤、
  strandedSourceParagraphs、publishState 三分支与属性维护、
  disableExactPreparedDom 幂等降级；monospace family 按 canvas-fonts.js 的键名
  以 latinMonospace 传入）与 root-state.test.mjs（7 例）；
  core/engine/progressive-drivers.js（globalThis.__TiqianProgressiveDrivers：
  enhanceProgressively 的工作序按（距离，索引）双键排序、逐项 measure 守卫、
  StaleFinishKeepsCommittedParagraphs、SharedRuntimeStylesCapabilityGate、
  relayout 四分支含 WidthDependentCapabilityTransitionRetry 与
  StrandedEnhanceResume、WidthSnapshotPerRelayoutJob 的宽度快照与 0.5px
  漂移判定、startProgressiveJob 规格与 finish/fail 收尾上报层）与
  progressive-drivers.test.mjs（20 例）。两处设计决定随本 Slice 固化：其一，
  relayout 分支一与分支三以已解析 options 再入 enhance 驱动时走
  createRootStateFromCanonical，bag 形状不再经 optionsFromJs 二次解析；其二，
  驱动层不含 destroy 语义，Kotlin enhanceProgressively 入口先 destroy 再
  重建的次序由 Slice 6 的引擎入口负责。npm-core 全套 392 例、npm 侧
  progressive/custody/timing-golden 18 例通过。jsTest 侧先验证上述 TS 套件
  覆盖，再删 TiqianWebProgressiveRelayoutTest.kt（25 个测试，974 行）与
  TiqianWebEnhancerTestSupport.kt、TiqianWebEnhancerTestFixtures.kt 里仅被
  该文件引用的辅助成员 304 行（删除后零引用，逐一 grep 验证）；
  jsBrowserTest 67/67 通过。root-state 与驱动两路并行委托
  两路并行委托，驱动初版 16/20 复核后修复三处测试装配（假元素
  rect 读取、ResponsiveMeasure 全局缺省、measures 序列缺 live 采样）与
  一处实现缺陷（canonical 再入误走 bag 解析），并补删委托规格范围外的
  零引用辅助簇。demo/web 基线同步复核：33/35 稳定通过，
  NpmPublishedVsDev 在下次 @tiqian/prose 发布前按设计保持失败，
  OneShotEquivalence 失败原因已另档记录（增量通道不刷新 dash 能力属性）。
  进度（Slice 6，2026-08-24）：9f799c97、e8752ae4、65608fde。npm-core 新增
  core/engine/engine-entry.js（globalThis.__TiqianEngine：enhance 的
  bag/canonical 双入口与 destroy 先行序、enhanceAll 根扫描、destroy 的
  custody/issue/快照属性收尾、detach 的 DetachedRootWeakOwnership 最小面、
  refresh 双分支、cancelLayoutWork、probeContentDrift 的 unknown 缺省
  JSON、reconcileContent 的 ReconcileSpec 组装与 drifted/custody/tainted/
  stranded 四类动作编排、DeadTrackedParagraphDrop、
  WidthSnapshotPerReconcileJob 的（距离，索引）双键 itemTierIndex 与
  0.5px stale 闭包、workerLayoutRequest 的 optionsFromJs 前置；
  globalThis.__TiqianEngineWorkers 以 worker 前缀名直暴露九个轮询方法）与
  engine-entry.test.mjs（18 例）；progressive-drivers.js 追加
  rejectMissingSharedRuntimeStyles、startProgressiveJob、
  enhanceProgressivelyFromCanonical 三个公开导出（实现零变化，
  progressive-drivers.test.mjs 增至 23 例）。宿主连接：build.gradle.kts
  新增 rootStateBridge、progressiveDriversBridge、engineEntryBridge 三座
  嵌入生成器；TiqianWeb init 块 eager 安装三个 TS 模块与 copy、
  content-reconcile 两个脚本并经 bindTsRootStateFfi 注入 shaping
  facade；runtime-loader.js 与 runtime-host.mjs 的 engine/workers 解析改为
  TS global 优先、Kotlin 导出回退。Slice 5 固化的「驱动层不含 destroy
  语义」决定随本 Slice 修正：relayout 分支一与分支三直接再入驱动内部函数，
  不经引擎入口包装层，destroy 连同 copy handler 安装因此移入
  progressive-drivers.js 的 enhanceProgressively 入口（无引擎入口的单测
  世界回退为直接调用 cancelJob），引擎入口两处包装层只余委派；relayout 分支一的
  重启 kind 同时改正为 Kotlin 双参重载默认的 Enhance（初版误写 Relayout，
  完成事件因此误发 tiqian:relayout-ready，tiqian:ready 不触发）。npm 侧
  测试期望同步：4d-2b 宿主切换后滞后的五处期望更新（InvalidFontSize
  前置拒绝改走 WebEnhancementFailure 上报、无键富段落单 run 失败整段回退
  浏览器度量且 dash 不合规失败关闭、回退段落基线来源改为浏览器度量），
  root-state.js 一处转写笔误修正
  （EXACT_PREPARED_FALLBACK_ATTRIBUTE 误写 data-tq- 前缀，测试 7 处同步），
  progressiveJob 两例按上述 kind 与 destroy 修复恢复；npm-core 侧修复
  progressive-drivers.test.mjs 测试 2 覆写单例 jobKind 后未还原的问题（测试 4
  在顺序执行时因此从未进入分支三，单跑即 2!==1 失败，已还原 jobKind 并按
  分支三语义改期望）。随本 Slice 关闭一项既有缺陷：F2a 拆包删除了 attach 系短名到
  worker 前缀名的映射后，真 bundle 内 coordinator 的 worker 面板自
  2026-08-23 起从未生效（#ensureLayoutWorker 早退，轮询与逐分段视口补偿
  未注册），__TiqianEngineWorkers 直接以消费名暴露后恢复；demo/web 基线
  （33/35、drag 预算）测于该缺陷存续期，修复后复测仍为 33/35，仅余两项已知
  失败，drag 与滚动预算断言通过，预算数字未因 worker 面板恢复轮询而调整；清
  parcel 缓存后的首跑曾报 31/35，两个额外失败在单跑与复跑中均未复现，判定为
  冷缓存下的负载时序敏感，非本 Slice 回归。
  删除 Kotlin 三文件（WebEnhancerContentReconcile.kt、
  WebEnhancerEngineExport.kt、WebEnhancerWorkerProtocol.kt）与 jsTest 两文件
  （TiqianWebEnhancerTest.kt、TiqianWebSourceFidelityTest.kt），bundle 导出
  面只剩 web 命名空间。npm-core 全套 413 例、npm 侧 246 例（删除 Kotlin 导出
  后在新 bundle 上复跑）、jsBrowserTest 10/10（仅剩 TiqianWebBridgeInstallTest）、
  demo/web 33/35（仅余两项已知失败）均维持基线。engine-entry 模块与连接两路并行委托；复核后修复上述分支一 kind 与
  destroy 次序两处缺陷、补 content-reconcile 的 eager 安装（映射删除后
  bundle 内无人再装该 global），并核实「npm 246/246 旧 bundle 回归验证」的汇报不成立：其运行时间先于 engine-entry.js 产生，
  InvalidFontSize 等期望滞后项与 bundle 无关，4d-2b 之后的任何时间点都
  不应全部通过。
  进度（Slice 7，2026-08-24）：73449b70、2aafd7f1、6cccf7e9。npm-core 新增
  core/engine/loaders/ts-runtime.js 与 ts-runtime.test.mjs：ts-runtime 按
  build.gradle.kts bridge 次序以副作用 import 安装全部 21 个引擎脚本，从
  @tiqian/ffi 直接引用五个函数组成 facade，经 __TiqianRootState.bindFfi
  注入；runtime-loader.js 的 loadTiqianRuntime 改为 import("./ts-runtime.js")，
  engineApi/workerApi 改从 globalThis.__TiqianEngine/__TiqianEngineWorkers
  解析；runtime-host.mjs 的 bridge.install 自行安装 copy handler。bundle
  世界的安装方是 webpack demo main()（Main.kt 的 fun main() 调
  TiqianWeb.install()，模块求值即把剪贴板监听注册到测试宿主缓存的
  document double 上），bridge.install 的空实现因此从未被触发；在实际
  宿主环境 import 旧 bundle，实测监听计数为 1，空实现回归为 0，
  bridge.install 补调 installer 后恢复 1，该修复随本 Slice 必要。npm 侧
  五个 bridge 测试头注释同步。Lane B 删除：frontend/web/src 全树
  （jsMain 23 文件、jsTest 3 文件，jsBrowserTest 退出）、
  frontend/web/build.gradle.kts（299 行）、npm-core/build-runtime.mjs 与
  runtime/ 产物目录（tiqian-web.js 580535 字节，git 忽略）、
  shaping/web-adapter（两个 .kt 与 build 脚本）；settings.gradle.kts 撤
  两个 include；npm-core package.json 的 files/exports/scripts 撤
  runtime/ 通道，verify-package.mjs 保留 runtime.js 必备项并停止扫描
  runtime 产物；package.test.mjs 把「发布包含 runtime/」的既有断言迁移为
  TS runtime 模块断言并删除 build:runtime 内容测试（npm 245 例为 246 删
  1）；sveltekit 集成门从 npm/runtime/tiqian-web.js 的存在性检查（F2a
  之后始终为 false、测试静默 skip）改为 @tiqian/prose-core 链接检查，
  「component builds in a real SvelteKit application」自此执行并通过
  （14/14）；compare-refs A/B 改为指纹 :ffi:js:assembleNpmPackage 的
  Tiqian-tiqian-ffi-js.mjs；kotlin-js-store/yarn.lock 再生（+30/-1198，
  webpack dev-server 依赖树随 project 撤除），F2 登记的 kotlin-js-store
  回归原位就此完成。demo 消费端：framework-commit-conflict 与
  npm-published-vs-dev 两个 fixture 的 import map 补
  "@tiqian/ffi": "/npm-ffi/Tiqian-tiqian-ffi-js.mjs"；bundle 时代引擎链
  自包含、无需 bare specifier 映射，ts-runtime 的文档上下文 import 需要
  该条目（worker 侧 rewrite 维持原状）；framework-commit-conflict 在
  运行时切换后两次复现「initial mount never rendered」，根本原因即此，补映射
  后单跑与全套通过。文档同步：AGENTS.md 撤 :frontend:web 两条 gradle
  命令与 shaping/web-adapter，architecture.md 与 contributing.md 同步，
  roadmap 行 36 验证命令列改 :ffi:js 路径。验证：npm-core 419、npm 245、
  sveltekit 14、astro 10、ts-discipline eslint 通过且两条 grep 零命中、
  package-topology OK、verify-package 两侧、npm-core pack 69 文件含
  ts-runtime.js、npm verify:release 隔离消费者通过、:ffi:js:jsNodeTest 与
  assembleNpmPackage 绿、demo/web 33/35（两项已知失败：发布金丝雀
  npm-published-vs-dev 与 OneShotEquivalence）。ts-runtime 一路委托
  安装器与 loader/host 连接）与（target 删除与包面收缩）两路
  并行委托；复核后实证 Main.kt 掩蔽链、裁决 package.test.mjs 的
  runtime/ 期望过时并迁移、修复 demo import map、完成文档与提交拆分。
  Kotlin/JS 编译自此只余 :ffi:js。
- [x] **F3 类型制度上 CI**（`StrictTsDiscipline`）：eslint 三规则设 error；
  CI grep `eslint-disable`。KPI：`any`、`as unknown as`、`object`/`Object`/`{}`、
  `eslint-disable` 计数均为 0（三包 TS 面）。验收：CI 任务绿。
  进度（2026-08-23）：f8a5f3b。tools/ts-discipline 私有工具目录（eslint 10.9.0、
  typescript-eslint 8.67.0，精确版本）持 flat config：no-explicit-any、
  no-restricted-types（object/Object/{} 各给替代写法）与 no-restricted-syntax
  （TSAsExpression 双重断言）三条全部 error，lint 对象为三包的非生成 js/mjs/d.ts。
  ci-ts-discipline.yml 固定 SHA 的 checkout 与 setup-node 后跑 eslint，再以两条
  grep 作为补充检查：eslint-disable，以及 JSDoc 形态的 any，eslint 的 TS 语法规则只看
  TS 语法节点，JS 文件 JSDoc 注释里的类型不在覆盖范围内，零基线由 grep 锁定
  （花括号
  类型内出现 any、冒号后的 any 标注、any 数组三种形态）。本地验证：eslint 零
  违规（向 .d.ts 注入违规后三条规则都报错）、两条 grep 零命中（注入
  `@type {any}` 后命中）、npm-core 180 例与 prose 246 例不变；远端 CI 运行随
  下次 push 验证。
- [x] **F4 双实现 CI 比对**（`DualLoweringStance`）：prepared-dom 双实现共享单一
  golden 语料强制比对。验收：Verification 2。
  进度（2026-08-23）：ci-native-precompute.yml 新增 prepared-dom-corpus job。
  Rust 侧语料测试原已随 rust job 的 cargo test 运行；新 job 从 js oracle 再生
  fixture 并以 git diff --exit-code 拒绝漂移（expect 只能由 builder 产出），
  再经 js 语料测试回放同一字节。两条命令在仓库根目录验证通过。
  进度（双实现修正，2026-08-23）：6ff37b4。FloatDustSpacingZeroing：两端
  prepared 实现把 run 路径两处间距置零判定的阈值从 SPACING_EPSILON(0.01)
  改为 SPACING_DUST_EPSILON(1e-6)，置零范围只覆盖浮点运算误差；两端对齐行
  在逐边界留有千分之几像素的伸展，0.01 的置零丢弃后累计 0.1342px，触发
  SnapshotRenderFlowMismatch。语料新增 justified-sub-epsilon-stretch 与
  float-dust-gap 两例（共 43 例），Rust 侧输出逐字节一致；demo/web 的
  host-content-mutation、justify-grid、responsive-relayout、viewport-unfreeze
  与 drag 覆盖 36/36 因此恢复通过。
  进度（运行时类名寻址，2026-08-23）：ba01d04。runtimeValueStyleKey 把
  tqvr- 类名从逐 root 递增序号改为声明文本的 FNV-1a 内容寻址（双累加器），
  单次重放在任意宽度与历史下逐字节重现协调 DOM；快照 tqv- 命名空间不变
  （Rust 侧只生成 tqv-）。

### G Slice 7 后代码品控（2026-08-24 登记待办）

- [x] **G1 TypeScript 落实**（`ActualTypeScriptMigration`）：端口产物目前仍是
  JS；ESLint 配置未包含泛型相关约束，与开发文档要求的 TypeScript 约束不一致；
  测试文件与仓库工具同样停留在 JS，部分文件把 JSDoc 当作 TypeScript 的替代。
  处置：先产出依赖树分析，自叶模块起逐层完成类型标注与语法转换；Lint 按
  ADR 已登记的禁用语法配置；类型定义严格去重，同一形状只允许一处定义。

  进度（G1，2026-08-24）：npm-core 运行时源全部转为同名 .ts（62 文件），
  就地 emit（tsconfig composite + verbatimModuleSyntax +
  erasableSyntaxOnly），.js 成为 emit 产物。按依赖序分 14 波执行，每波
  验收：值代码无改动以 emit 对 HEAD 原 .js 逐字节 diff 为准，非空差异走
  AST 等价判定（printer 固定类别规范化差异可接受）；npm-core 419 例、
  eslint 零错误（ts-discipline 规则集含 inline 对象与函数类型注解两条
  禁令）；类型逐文件登记 `.agent-specs/g1-type-registry.md`，两包类型名
  唯一。ambient 全局收敛到单属主 declare global（18 个 `__Tiqian*`）。
  ffi 消费端合并为单一声明：`core/engine/ffi-face.ts` 以
  `typeof import("@tiqian/ffi").<fn>` 派生 `EngineFfiFacade`，五个引擎
  文件的本地 ffi 声明与成员别名删除，emit 零 .js 差异。prose 包 P1 完成
  （api、copy、两个 re-export shim 转换，三个手写 .d.ts 移除，emit 的
  声明随包分发；npm-core package.json files 增 `*.d.ts` glob）；prose
  245 例、npm-core 419 例、verify-package 与 verify-release 全部通过。
  P2 完成（element.js 2350 行转换、element.d.ts 移除；emit 等价经
  第 7 类规范化判定：类含私有成员且其体内引用类名时，TS 类变换把该引用
  提升为模块作用域临时变量，对原件施加同一机械变换后 AST 等价）。收尾矩阵
  全部通过：npm-core 419、prose 245、eslint 零错误、类型名唯一、
  package-topology、astro 集成 fixture 10 例、gradle build（本机
  Skiko 原生库缺失使 :shaping:skia:jvmTest 环境性失败，经 HEAD worktree
  强制重跑证实与转换无关）。提交区间 8cbc0820..32c3647e（26 个提交，
  按 14 波转换与集成、ffi 面孔、prose P1/P2、lint 禁令与 CI 构建步骤
  分批）。
  .test.mjs 测试与
  工具脚本维持 JS：它们是运行时接口的消费方，按 node:test 通道执行，不进
  tsc 程序。
  产物跟踪（2026-08-24 裁定）：emit 出的 .js/.d.ts 是构建产物，不进
  版本库；发布面由包脚本在打包时再生（两包 pretest/prepack 均先跑
  tsc），两包 .gitignore 以 `*.js`/`*.d.ts`/`*.tsbuildinfo` 覆盖全部
  产物。执行首版曾把 emit 产物提交进库（npm-core 59 个 .js、prose
  根 6 个 .js 与 4 个 .d.ts），同日裁定后重写本地提交历史为 rename
  形态，上述区间即重写后的哈希。消费侧不足与处置：
  ci-native-precompute 的 prepared-dom-corpus 泳道此前靠树里的 .js
  免构建，现改为 npm-core `npm ci`（锁内 @tiqian/ffi 是本地路径链接，
  不触 registry）、prose `link:core`、借用 npm-core 的 tsc 做
  `tsc -b --noCheck`。用 --noCheck 的原因：@tiqian/ffi 的类型声明是
  gradle 产物（ffi/js/npm/runtime），fresh checkout 不构建 ffi 就没有，
  而该泳道验证的是语料字节；两包完整 typecheck 需要 ffi runtime，
  本地流程按 CLAUDE.md 先跑 `:ffi:js:assembleNpmPackage` 再
  `npm test`，publish 链经 prepack 自带构建。注意 CI 目前没有任何
  泳道执行两包测试套件，此不足在 G1 之前已存在，与产物跟踪裁定无关。
- [ ] **G2 模块边界与副作用**（`ModuleBoundaryDiscipline`）：运行时以
  `__Tiqian*` 下划线全局变量互相调用，模块体以 IIFE 与 `var` 编写，模块装载
  即产生全局副作用；应属于组件实例的状态存放在全局闭包；测试环境读取内部
  数据依赖这些全局。处置：模块改为正规 ES module 导入导出；ffi 不再作为
  函数参数传递，也不挂全局后跨模块调用；实例状态收回组件；测试读取内部
  数据的机制另行设计；构造函数的参数编排逐个复核；`var` 声明全部替换为
  let/const，不保留任何 var 写法（2026-08-24 复审补充：var 属必须清除的
  过时语法，G2 批内一并执行）。

  执行标准（2026-08-24 复审定型，转换按四条验收）：

  1. 模块只导出声明：类型、纯函数、工厂。纯函数模块直接导出函数；
     有依赖或有状态的模块导出 `createXxx(deps)` 工厂。禁止 `export let`
     单例、禁止 import 时实例化依赖、禁止任何 `*ForTest` 变更器进入
     生产源码。
  2. 组装根唯一：engine 工厂构建依赖图并向下游传递，依赖必须出现在
     参数签名中；测试自行构造对象图（以假件代入依赖），不改动模块
     绑定。
  3. 实例状态归所有者：按 DOM 节点键控的状态（custody 状态表、
     viewport-anchor 持有表、prepared 状态表、copy 安装表）移入工厂
     闭包或 root state；模块作用域只允许常量与纯缓存。
  4. 事件只用于宿主边界（字体加载、剪贴板、worker postMessage）与
     向宿主发出通知；引擎与前端组件之间的内部通信改为直接调用与
     返回值，组件不得消费自己派发的事件。

  复审同时否决了执行中段采用过的可变导出绑定（`export let xxxApi` 加
  `setXxxForTest`）：该写法以模块绑定代替全局对象，import 副作用与测试
  变更器同样存在，判定为未完成转换。已采用该写法的模块随 G2 后续批次
  改为工厂与注入；IIFE 外壳与重入守卫随模块转换删除；`EligibilityGlobal`
  一类含 Global 的类型名一并清除。

  2026-08-24 二次复审补充两条：

  5. 模块先分类再定形：无实例状态的模块直接导出命名函数，不包装成
     `createXxx()` 返回的 Api 对象；deps 参数只收有状态协作者与宿主资源，
     纯函数模块的 import 不属于待注入依赖。eligibility、responsive-measure、
     prepared-metadata、markdown-lowering 为无状态模块；custody、copy
     安装器、任务池为有状态模块。
  6. 转换期间不设任何过渡单例：不新建 `export const defaultXxx =
     createXxx()` 一类 import 时实例化的模块；阶段之间生产源允许 tsc
     报错，报错限于尚未转换的消费者文件，由组装根批次统一消除。

  全局使用清点（2026-08-24，grep 实测）：生产面 `globalThis` 名字 17 个，
  其中模块自装 10 个、engine 入口自装 2 个、跨包桥 2 个、worker 握手 1 个、
  遥测出口 2 个；模块作用域可变绑定 18 处。必要性裁定：任务队列协调为
  唯一必要项，目标形态仍是 engine 实例图内持有（一页多个 engine 互不
  共享）；worker 版本握手属于宿主边界协议；renderer/validator 桥改为
  组装根显式注入（宿主构造 engine 时传入，双拷贝协商移入组装根）；遥测
  出口改为显式调试接口或并入 decision dump，后续批次裁定；其余全局与
  模块作用域可变绑定全部改为参数传递、实例闭包或组装根持有。

  G2 执行进度（S 波，2026-08-25 起分波执行）：

  - R1b..R4（状态清点与收编准备）完成，npm-core 416/416。
  - S1（LayoutJobPool 改名）：progressiveJob 系列改名 LayoutJobPool，
    progressive-relayout-session.ts 改名 relayout-session.ts。
  - S1b（deps 拆散）：EngineEntryDeps 与 ProgressiveDriversDeps 拆散，
    ffi 槽删除（root-state.ts 直接 import ffi 五函数），commit bundle
    退出 deps。提交 ab4f7a75。
  - S2-a（CoordinationService 与 globalServices 容器）：coordinator
    改名 CoordinationService，coordination/ 目录分簇，core/services/
    global-services.ts 以 Symbol.for("@tiqian/prose.global-services.v1")
    挂 globalThis，提供 installGlobalServicesForTesting 注入钩。
    提交 3f53c1bc。
  - S2-b（散置状态收编）：font-loader、declared-faces、browser-fonts、
    canvas-shaping、browser-font-replay 七处模块作用域可变状态移入
    CoordinationService 的 fonts 与 measurement 状态簇（coordination/
    fonts.ts、coordination/measurement.ts）。提交 51efc35a。
  - S3-a（EnhancedElementContext 生命周期补全）：createEnhanceContext 成为根路径统一构造入口，调用方持有返回的 context；新增 update() 与 destroy() 分别接管既有的代际递增与销毁清理路径；preparedStyle 状态随 context 生命周期管理。提交 4c217470、d1b6e982。
  - S3-b（custody 系列改名 RawDom）：custody.ts 已更名为 raw-dom.ts，expando 删除，段落记录统一走 context.rawDomParagraphs。提交 3a195866。
  - S4（全局名删除）：
    - renderer/validator 桥走 loaderState：runtime-loader.ts 模块作用域 loaderState 溶入 globalServices().runtimeLoader；worker-channel.ts 模块作用域 coordinator 溶入 globalServices().coordination.channel。S5-bc 批次完成。
    - 版本挑选器删除：源码中无版本挑选器痕迹，该条目或为规划中的候选，已在主线上消失。
    - __TiqianLayoutWorker 并入 Symbol.for 协调对象：未完成。测试 fixture 仍以 globalThis 属性形式引用，Kotlin 生成的 JS 通过 defineProperty 安装。待后续批次执行。
    - trace 双全局改 enhance 初始化选项：核心 TS 迁移完成（TraceConfig 作为 EnhanceOptions 字段，CoordinationService 实例属性替代 globalThis.__tqTrace/__tqFrameTrace）；注释与 demo 测试中仍有遗留引用，待清理。
    - eslint declare-global 豁免废除：已执行（两处 `declare global` 块只含 interface 声明，豁免选择器无消费者）；`ci(ts-discipline): drop the unused declare-global var exemption` 移除选择器后两包 eslint 保持零错误。

  S2-b 实施时的实现约束（后续模块改动适用）：globalServices 静态 import
  闭包不得抵达 prepared-dom 与 browser-fonts。这两条链的模块体含安装
  只读桥的顶层副作用；提前到测试 fixture 之前装载会破坏 fixture 预置。
  协调服务对重链成员只允许 import type；实例构造放首次使用处
  （browserFontLoader 懒构造先例，coordination/fonts.ts 注释）。
- [x] **G3 ffi 包边界**（`FlatFfiExportSurface`）：ffi/js 的要求与
  frontend/rust 相同：导出 tiqian Kotlin 模块的全部 API 供下游消费。实际产物
  移动了部分源代码，包内混入新实现的宿主逻辑，属于 web 侧的逻辑应留在 web
  仓库；ffi 包只做引擎代码导出，Rust FFI 与 JS FFI 的导出接口保持平行；现有
  混入内容收回库内或删除；HarfBuzzBuildBackend 的消费点核对后处置。

  进度（G3，2026-08-24）：只读审计完成（导出清单、Rust 对照面、
  平行性分歧表、消费点与 npm 目录核查），审计逐项裁定后执行。
  裁定与结果：

  - `LoweringHelperExports.kt` 三个函数（`classifyFontRole` 等）不含宿主
    概念，实现是引擎策略（`CjkFontRoleClassifier`、`InlineShapingStylePolicy`）
    的委托加字符串编码，编码属于 ffi 边界的 ABI 职责，保留原位；
    `WireFormatPerBoundary` 已记录 JS 边界的字符串与 JSON 传输格式。
  - `BrowserMetricsExports.kt` 的 JSON codec 与回调适配器运行在边界的
    Kotlin 一侧（宿主度量经 JSON 回调进出引擎），等价于 Rust 侧
    `install_font_backend` 的宿主供后端模式，保留；其中与
    `layout/PreparedParagraph.kt` 逐字节重复的四个数字规范化函数
    （PlanNumberCanonicalForm 第二份拷贝）已删除，ffi/js 改用 layout 的
    `ecmaJsonNumber` 单源（layout 仅该函数提升 public）。
  - `HarfBuzzBuildBackend.kt` 两个 typealias 是纯重命名层，唯一消费点在
    `PrecomputeExports.kt` 的后端组装；文件已删除，组装处直接使用库内
    `HarfBuzzSessionTextShaper` 与 `HarfBuzzSessionFontMetricsResolver`。
  - source map 嵌源（A4 既定行为）与 npm 目录下的构建、验证、发布脚本
    （开发期工具，不在 `files` 白名单）维持现状。
  - 提交 1c0d63a8。验证：`:layout:jvmTest`、`:ffi:js:jsNodeTest`、
    ffi/js npm 测试与 `verify:package`、Native 编译全部通过；导出接口
    7 个符号与签名前后不变。

#### QA 复审记录（2026-08-24，G3 后续录，原文照录，依序处置）

- 执行过程当中要求是 `@tiqian/core`，结果被执行成了 `@tiqian/prose-core`，
  冗余的模块重新导出；alpha 版本的软件不需要考虑兼容性问题。
- 工具脚本和程序源码混在一起，工具应该在 scripts 里，源码应该在 src 里。
- npm-core 是一个错误的文件夹名称，它应该叫 core；npm-core/core 这个
  Core 里有 Core 的逻辑也非常怪；npm-core 根目录下有大量散装文件没有进
  src 也没有按照职能进入对应目录。
- CI 炸了，Rust 侧编译完成后发现数据结构对不上，可以用 gh 看一下；
  Kotlin 迁出的时候 CI 就已经跑不过了，cargo build 的时候 test 合不上。
- .b2-tmp、.agent-specs 目录挂在哪里有点怪：首先里面的内容已经不只是 b2，
  其次如果它有价值可以供以后的 Agent 参考，至少应该把它放到 git ignore 里，
  现在都堵在未提交文件里面有点让人困扰。
- 我怎么感觉 Kotlin、Rust、JS 之间的精度问题逻辑开始出现分散的情况了，
  之前好像是都集中在 Rust 侧处理了。
- FFI 包还是脏的，里面还是有独立的 Kotlin 文件不知道被谁用过，非常奇怪。
  对于所有包，所有测试还是 js 文件不是 ts 文件，ffi 包里面也都是 js 文件。

处置记录（依序执行，2026-08-24 起逐项落定）：

- QA3（CI Rust 结构对不上）：已修，提交 af9d80d9。原因是 wire face
  派生默认值（bd4e7197）只改了 JS oracle 侧字节；parity oracle 显式
  renderEvidence=false 后 CI 恢复。
- QA5（精度逻辑分散）：审计结论无系统性分散。Rust 持有按字体粒度的精度与
  输出量化，Kotlin 持有排版规则容差，TS 只持有 Rust 驱动的重复实现
  （golden 验证逐字节一致）与浏览器专用容差，FFI 透传。一处过渡态
  分歧（grid-metrics.ts 的 Math.fround 对照 responsive-measure.ts 的
  Double 除法）在 ADR 0054 SingleGridArithmetic 实施时收敛。一处真
  缺陷（session.rs 安全整数上界 2^53 写成 992）已修，提交 aa93983c。
- QA6（ffi 包清洁与测试 TS 化）：已完成，提交 2a0586b2。ffi 包测试
  源改 .mts，emit 产物解除跟踪，runtime 产物哈希前后相同。
- QA9（ffi 导出对齐 Rust）：已完成，提交 e6a11f9e（六个引擎能力
  @JsExport 带类型）。Part B 裁定不补导出，理由两条：LayoutQueries
  是自绘 UI 的查询面，web 是 DOM 渲染，光标、选区、复制由浏览器原生
  处理，JS 侧零调用方；27 类诊断 web 端零消费者，其中两类 shaping
  派生诊断已为 fail-closed 导出。
- QA4（.b2-tmp/.agent-specs）：盘点完成（.agent-specs 154 文件
  5.5M，spec 与报告为主；.b2-tmp 268 文件 9.9M，agent 日志与临时
  产物）。处置已执行（2026-08-25）：两条目录进 `.gitignore`，磁盘文件保留
  供 agent 参考与考古，不再进入提交队列。
- QA1（包名纠偏 @tiqian/core）：提交 b995fff1（改名）、c792d719
  （删除 copy 与 styles 重导出垫片）。
- QA2（目录重组 scripts/src 分离、npm-core 改名 core）：提交 4ca49e71。
- QA7（npm workspace 化）：机制预演在 .b2-tmp 复制品完成
  （.agent-specs/qa7-dryrun-report.md），三风险结论各一条：提升冲突
  成立于 typescript，@tiqian/precompute 因 ^6 范围在成员内嵌套
  6.0.3、根提升 5.9.3，eslint 单版本提升无冲突；成员锁与根锁冲突
  未复现，删除全部成员 package-lock.json 后只生成根锁；file: 依赖
  静默回退 registry 在 file: 边改为与成员版本字段一致的精确版本后
  未复现，@tiqian/* 全部解析到本地成员、零 registry 命中。正式转换
  提交 4818b3f3，随后 2377a65a 把 CI 安装命令改为 npm install。
- QA8（styles.css 副本消除）：前提核验（npm 与 core 双胞胎 md5 一致
  54a5e3fc）。三条疑似重复裁定：element.ts 的 mutation 过滤知识是
  行为不是样式重复，留在原处；styles.css 的 position:relative（层叠
  基线）与 custody 恢复时的内联 !important（恢复正确性）是独立两层，
  记录不改动；DemoWebBreakWordMask 是 demo 局部 counter-style，留在
  demo。正式转换提交 6f427a50。

#### ffi 边界复审记录（2026-08-25；五条原话已按 2026-09-06 裁定删除，逐字原文见本提交的父版本）

判定（哪些既有决定是错的）：

- A3（`SingleEngineFace` 字节进出面，提交 da92871）判定为错误决定。它把
  JS 通道的传输格式解析、校验与 `LayoutInput` 组装从 ffi/js 移入 engine
  commonMain（`ParagraphWireFace`），引擎从此持有单一通道的传输格式代码。
  按 ffi 边界终则，这类代码属于 ffi/js 的数据转换层。plan JSON 文本定性为
  诊断与校验格式：布局数据是生产数据，文本形态服务 dump、golden 与 parity
  oracle 的字节比对；生产跨界（TS 运行时、node 构建驱动、native 返回）一律
  类型化。`toPreparedParagraphJson` 与 `toPlanWithDiagnosticsJson` 留在引擎，
  作为 `LayoutResult` 的可解释 dump 输出（实现约束 3）。
- engine jsMain 的 `HarfBuzzSessionBackend.kt` 违规：21 处 `@JsFun` 内联读
  `globalThis.__TiqianFontBackend`。native 对应面是安装式 vtable
  （ADR 0050），js 面依赖环境全局。处置为整系列删除，session 与 replay 的
  查找留在 TS 侧。
- 跨界载荷审计：无声明协议的穿越共四处。JS 请求（五个分隔符串，分隔符
  常量在 TS 与 Kotlin 两侧各持一份私有拷贝）、JS 逐段 shaping（JSON 字符串
  回调往返，每段四次文本转换）、JS 返回（转义 plan JSON 信封）、native
  返回（plan JSON 原始 C 字符串，`plan.rs` 按字段名读取并忽略未知字段）。
  native 请求与 shaping 的打包协议（`TQLR` 与 `tiqian_font_backend.h`）
  有声明与版本号校验，合规。
- `PrecomputeExports.kt` KDoc 中「Keeping the exported values primitive
  avoids exposing the core model」一句出自执行层，任何需求里不存在此要求，
  作废。
- 命名裁定：调试用途的文件名字必须含调试；非调试且有跨界消费者的文件
  禁止发出无声明协议的载荷。`ExplainableStubParagraphLayoutEngine` 名字含
  Stub、承载的是全部生产路径，裁定改名 `TiqianParagraphLayoutEngine`；
  名字出自 scaffold 提交 1a37d54a（Claude session 写入），出处与裁定标注在
  ADR 0008 Amendment。

处置记录（依序执行）：

- 纠偏 1：删除 HarfBuzzSession 系列与全部相关环境全局。
- 纠偏 4：删除 `buildPrecomputeBackends` 与失去实现的 session-id 入口。
- 纠偏 3：ffi 数据转换层按职能定名并合并文件。
- 纠偏 2：六个请求解析器移回 ffi/js，按标准工程词汇命名。
- 纠偏 5：请求、回调与返回信封改为声明 DTO 对象过界，运行时与构建驱动
  拿类型化对象；冻结 JSON 文本只保留给字节比对处（parity oracle 与
  golden 证据）。
- native 返回类型化：C ABI 返回从 plan JSON 原始字符串改为打包声明协议
  （与请求侧 `TQLR` 同模式），Rust 解码进既有 Plan 结构体；plan JSON 保留
  为引擎 dump，服务 oracle 与 golden 的字节比对。
- 引擎改名：`ExplainableStubParagraphLayoutEngine` 改为
  `TiqianParagraphLayoutEngine`，旧名不再并存；出处与署名标注在
  ADR 0008 Amendment。
- npm workspace 化：根 `package.json` 声明七个工作区成员，成员间依赖按
  精确版本解析到工作树符号链接，全部 link 脚本与各成员的 lock 删除。npm
  不支持 `workspace:` 协议；声明版本与成员版本不一致时安装回退
  registry，成员升版必须在同一改动里同步全部依赖方声明。
- 共享样式表单源：`styles.css` 只由 `@tiqian/core` 发布并导出，prose
  停止随包携带与导出；全部下游改为解析 `@tiqian/core/styles.css`。Node 22
  要求 exports target 以 `./` 开头，跨包转发子路径不可实现，只能由下游
  直接解析上游。
- 终则定稿已随纠偏 5 三波收尾落回本 ADR（见下节）；ADR 0050 附注记录
  JS 通道侧判定（2026-08-25）与 vtable 字体 family 类型化（2026-08-26）。

#### ffi 边界终则（2026-08-26 定稿）

复审处置全部执行完毕，边界规则定稿如下，后续跨界改动以此为准：

1. **跨界载荷声明化。** JS 请求（`WorkerLayoutRequest` /
   `PrepareParagraphRequest`）、浏览器度量回调（`BrowserMetricsCallbacks`）、
   字体 family 列表（C ABI `const char* const*` 加计数）、native 请求与返回
   （`TQLR` 与 `tiqian_plan_abi.h` 打包协议）一律以声明 DTO 或打包协议
   跨界传递。生产跨界路径禁止分隔符拼接字符串与未声明 JSON 文本。
2. **冻结 JSON 只服务字节比对。** plan JSON 与 snapshot 文本形态保留给
   golden 证据与快照 bundle 产物；native 引擎 dump 与 parity oracle 已于
   2026-08-30 移除（ADR 0050 修订）；生产路径不产生也不解析整段文本载荷。
3. **Kotlin/JS 导出接口承载规则。** 数据 DTO 用 @JsExport 接口承载，集合用
   Array 字段，边界断言只允许 `as` 到带 brand 标记的接口；函数型回调
   @JsExport 不支持函数属性，用非导出接口加 @JsName 固定属性名承载。
4. **协议版本三处同步。** 字体后端协议版本号在 C 头文件、Rust
   `font_backend.rs` 与 Kotlin `NativeFontBackendVtable` 三处同值（当前 2），
   不兼容变更同步递增；返回侧打包协议按同规则独立编号。
5. **缓存键字节始终相同。** replay key 的字符串形态（字体 family 以 U+001F 连接）
   是兼容承诺，结构体化改造不得改变 render 输出；键格式确需变更时先
   停下记录，不得静默换键。
6. **归属不变。** 传输格式解析与组装属 ffi/js 数据转换层；引擎持有排版
   规则与 dump；平台层与宿主不得持有布局真值的第二份副本（实现约束 3、5）。

执行机构：`tools/boundary-check/check.mjs` 机械门逐条比对豁免清单，豁免
必须写明理由，数量只减不增（2026-08-26 终止状态：85 命中、25 豁免、15 复核
导出）。

纠偏 5 提交证据：请求 DTO（ef399347、b4f90ec3、19f5f261、af4f310f、
5423a174）；字体 family DTO 跨 C ABI（08a7ebb8 至 f12eba9f，合并 83d99d02）；
回调 DTO 与 replay key 结构体（b5397a85 至 0c135ee3，合并 f4aaa982）。
字节不变式验证：replay key render 输出与既往基线逐字节相同（Rust 单测与
集成测试）；golden 全程零 diff。

### KPI 汇总

| 指标 | 基线 | 目标 |
|---|---|---|
| Kotlin 宿主 jsMain 行数 | 5669 | 0 |
| jsTest 行数 | 3981 | 0（断言以 TS 规格形态存在） |
| runtime/tiqian-web.js | 1 份产物 | 不存在 |
| tiqian:* 事件通道 | 11 | 0 |
| globalThis 桥挂载方法 | 9 | 0 |
| 主线程调度循环 | 3 | 1 |
| 渲染实现份数 | 3 | 2 |
| 同过程装配编码 | 4 | 1 |
| npm 包拓扑 | 1（@tiqian/prose；ffi 未独立发包） | 3（ffi、core、web-component），依赖方向 web-component → core → ffi 单向 |
| 跨包相对导入 | 无检查 | 0 |
| core 与 web-component 包内手写 JS 源文件 | 全部为 .js | 0（全部为 .ts） |
| any、as unknown as、object/Object/{}、内联类型与 eslint-disable | 无检查 | 全部为 0 |

## Amendment（2026-08-29）：撤除 enforcement gate

按用户指令撤除本 ADR 附带的全部机械执法装置：五个 CI 流水线
（ci-service-directory.yml、ci-boundary-check.yml、ci-package-topology.yml、
ci-ts-discipline.yml、ci-assembly-record.yml）与四个工具目录
（tools/service-directory、tools/boundary-check、tools/package-topology、
tools/ts-discipline）同时删除。ffi/schema 与 tools/schema 的类型生成器保留，
生成新鲜度不再有 CI 检查。本 ADR 记录的裁定（ServiceDirectoryRule、
三包拓扑与依赖方向、StrictTsDiscipline 的类型制度、 ffi 边界裁定）继续作为
仓库约定存在，由 CLAUDE.md 与评审执行，不再有自动 gate。Verification 8 所指
的 CI 检查自本修订起不存在。
