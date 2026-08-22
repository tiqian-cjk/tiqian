# ADR 0050: 原生 precompute 引擎绑定与 Rust / npm 双生态分发

- Status: Accepted
- Date: 2026-08-20
- Relates: [ADR 0001](0001-core-pipeline-and-platform-boundary.md)（核心 pipeline 与平台边界）、
  [ADR 0039](0039-web-rendering-path.md)（Web 渲染路径，Node precompute 运行时）、
  [ADR 0040](0040-build-time-web-font-snapshots.md)（构建期字体证据与快照）、
  [ADR 0042](0042-framework-web-integrations.md)（Web 框架集成包与无宽度字体证据）、
  [ADR 0045](0045-apple-kotlin-native-target.md)（Apple Kotlin/Native 目标先例）、
  [ADR 0048](0048-suite-maven-and-package-namespaces.md)（套件 Maven 坐标与包命名）、
  [ADR 0052](0052-precompute-cache-and-batch-renderer.md)（缓存分层与批量渲染器，承接本 ADR
  初版的缓存契约设计）

## Context

Node precompute 现状分两层。`frontend/web-precompute` 编译为 Kotlin/JS，`@JsExport` 暴露扁平
wire ABI：分隔符编码的入参、JSON plan 出参。`@tiqian/prose` 内约 3400 行 Node JS 持有字体会话、
编排、prepared DOM 渲染与 manifest。字体会话依赖 `harfbuzzjs` 1.4.0 与 `woff2-encoder` 两个
WASM 包，经 `globalThis.__TiqianFontBackend` 回调协议服务 Kotlin 的 shaping / metrics 请求。

这个结构有三个代价：

1. precompute 与浏览器运行时混合发布于 `@tiqian/prose`。构建工具用户携带无关文件与两个 WASM
   依赖，包边界与 ADR 0042 的分层目标冲突。
2. 引擎只能经 Node 生态消费。Rust 使用者没有入口，也无法把 precompute 嵌入非 Node 工具链。
3. 构建期 shaping 走 WASM，加载与版本对齐受 npm 包发布节奏约束。

## Decision

### `NativePrecomputeEngine`：Kotlin/Native 静态库与扁平 C ABI

`frontend/web-precompute` 增加 `linuxX64`、`linuxArm64`、`macosArm64`、`mingwX64` 四个
Kotlin/Native 目标，各产出 `staticLib` 与 C 头文件。四个目标传递性地要求 `core`、`font`、
`shaping:api`、`linebreak`、`clreq`、`layout` 补齐缺失的 native 目标。这些模块以 commonMain
为主；断词资源的两处 expect/actual 目前 native 侧只有 appleMain 实现（ADR 0045），新目标需要把 actual
归位到 nativeMain 或补写。其余改动限于构建配置。wire 解析提升到 `commonMain`；`jsMain`
保留 `@JsExport`，`nativeMain` 新增 `@CName` 入口。

C ABI 保持现有 wire 契约：`tiqian_precompute_paragraph` 接收扁平参数，经 `nativeHeap` 返回
JSON，配对 `tiqian_precompute_release_string` 释放。错误经出参以具名 capability issue 字符串
返回，Kotlin 异常不跨 C 边界；绑定层把字符串映射为错误类型，名称与现有 npm 测试及 web
capability 断言一致。C 入口允许并发调用；backend 实现负责自身的线程安全。

字体回调协议采用可安装 vtable：`tiqian_install_font_backend` 注册 shape / metrics 回调与
backend revision，证据范围与 `__TiqianFontBackend` 相同，数据形态采用打包缓冲区，见
`PackedFfiCalls`。vtable 的 Kotlin 消费者放在 `shaping:api` 的 nativeMain，与 jsMain 的
`@JsFun` 实现并列。引擎未安装 backend 时对 shaping 请求报具名错误。安装模式让绑定 crate
可以脱离 precompute 单独链接与测试。

`macosX64` 不在目标内。ADR 0045 已决定不加该目标；Kotlin 2.3.0 起该目标进入弃用流程，官方
计划 2.4.0 移除。

### `RustPrecomputeStack`：字体会话与编排迁入 Rust

Rust 侧分两个 Cargo workspace，都在 `frontend` 下。`frontend/rust` 持有中性引擎绑定：`tiqian`
与后续的平台 crate；绑定不依赖 web 概念，Rust 使用者可不引入 precompute 直接消费引擎。
`frontend/web-precompute/rust` 持有 web 域的 `tiqian-precompute` 与 `tiqian-precompute-neon`，
以 path 加版本依赖 `tiqian`。crate 划分：

- `tiqian`：引擎绑定主包。暴露 `precompute_paragraph`、`install_font_backend` 与具名错误
  类型，链接平台 crate 提供的静态库。crates.io 上 `tiqian` 名称当前未被占用，发布前先注册。
- `tiqian-<platform>` 四个平台 crate：内含对应平台的静态库与头文件，`build.rs` 输出链接参数，
  由 `tiqian` 以 target-specific dependency 声明，cfg 谓词包含 arch 与 `target_env`。未覆盖
  目标（如 `x86_64-apple-darwin`、musl Linux）得到占位实现，调用时报具名错误。
- `tiqian-precompute`：字体会话与编排。字体会话复刻 `precompute-fonts.js`：harfrust
  shaping、
  WOFF2 解码、face 选择、unicode-range 匹配与回放证据。face 选择与 unicode-range 匹配属于
  CSS `@font-face` 的证据职责，复刻现有 JS 行为；字体 fallback policy 仍在 Kotlin `font`
  模块。编排覆盖 `precompute.js`、`prepared-dom.js`、`snapshot-manifest.js`、
  `snapshot-source.js` 与 `precompute-html.js` 的 Node 侧行为。只依赖 `tiqian`，不依赖
  napi，可独立 `cargo test`。
- `tiqian-precompute-neon`：Neon cdylib。暴露现有 precompute 入口的全部导出（兼容性约束见
  `NpmPrecomputePackage`），并新增 `createFontSession` 与原始 `layoutParagraph` 入口。缓存入口
  与条目契约由 [ADR 0052](0052-precompute-cache-and-batch-renderer.md) 定义。
  Neon 打包与 CI 配置沿用同维护者 blurest 仓库验证过的 `neon dist` 与 `neon show ci github`
  流程。

Shaping 用 `harfrust`，metrics 与 extents 用 `skrifa` / `read-fonts`，WOFF2 解码用
`wuff`。四者都是纯 Rust 实现，构建不需要 C/C++ 工具链。采用版本 harfrust 0.13.0、
skrifa 0.46、read-fonts 0.43、wuff 0.2，前三者共用同一 read-fonts 版本。依据是
2026-08-20 的差分测试（见
[docs/research/2026-08-20-harfbuzz-version-differential.md](../research/2026-08-20-harfbuzz-version-differential.md)）：

- HarfBuzz 8.4 到 14.2.1 的输出逐字段一致。跨版本没有风险，将来若回到 C 路线，
  `harfbuzz-sys` 直接可用。
- rustybuzz 的输出同样一致，但它的仓库已于 2026-07-26 归档，不再维护。
- 静态字体与可变字体上 harfrust 0.13.0 与 skrifa 的全部字段与 oracle 逐字一致。extents
  按字形来源分派：静态 TrueType 读 glyf 头盒，CFF 与变实例坐标走轮廓包围盒。
- WOFF2 解码器选 `wuff` 0.2。`woff2` crate 0.3 自 2022-05 起无维护，并且严格校验
  header 的 `totalCompressedSize`，拒绝 `woff2-encoder` 生成且其自身可解的文件。
  `wuff` 解同一文件的输出与 JS 侧 wasm 解码器字节一致（sha256 相同）。依赖里的
  `bytes =1.9.0` 锁随 `woff2` crate 一并移除。

snapshot evidence 的 `harfbuzzVersion` 只校验同一 manifest 内条目一致
（`SnapshotFontEvidenceVersionConflict`）。Rust 侧报告自己的引擎标识与版本，同一
snapshot 不混入两个引擎的证据。升级 harfrust 或 skrifa 后重跑 `LegacyJsOracleCutover`
定义的差分 harness。HTML 解析用
`html5ever`。`harfbuzzjs`、`woff2-encoder`、`linkedom` 三个 npm 依赖随之删除。
Kotlin 引擎侧保持零字体依赖。排版规则仍全部在 Kotlin 核心，Rust 只承担 ADR 0001
平台 adapter 契约允许的平台层职责：字体加载、shaping 与度量。

### `PackedFfiCalls`：打包 FFI 数据与调用预算

跨 FFI 调用次数是本次迁移的设计指标，按段落计数：

- 未命中路径为两次加 K 次。进入与返回各一次；K 为引擎发出的 shaping 与 metrics 请求数，
  每个请求对应一次回调。
- Neon 批处理入口按文档计数。一次调用处理全部段落，段落循环留在 Rust 内部；单段入口
  面向单段调用方。

vtable 采用打包缓冲区，jsMain 的句柄协议保持现状。shape 回调把一个 segment 的全部字形写进
调用方提供的缓冲区：每字形一条定长记录，含 glyph id、advance、x、y 与四条 ink bounds；无 ink
bounds 的字段写 NaN。faceId、script、feature 等字符串证据写入同一缓冲的字节区，头部记录
偏移。

缓冲区容量由调用方按 segment 长度加余量预置。字形数可以超过码点数，GSUB 分解替换即属
此类；容量不足时回调返回所需容量，调用方扩容后重试，单个请求的回调次数上限为两次。metrics
回调同样返回定长记录。JS 侧现行协议在每个字形上最多花费八次访问器调用；打包形态
把一个 segment 的全部字形合并为一次调用。两个协议共用同一份会话证据结构。

plan JSON 保持单次返回的 C 字符串，Rust 解析一次。差分 parity 以 JSON 字节为比对层，二进制
plan 序列化不在本 ADR 范围内。

Neon 边界以字节为主。prepared DOM 与 bundle 经 Node Buffer 传输；输入侧 HTML 与文本仍为
JS 字符串，napi 转换一次。

并发契约：字体会话的 face 数据只读共享，shaping 线程各建 shaper 实例。批处理入口在
Rust 线程池并行执行，结果按输入顺序返回。入口保持同步语义，与现有 precompute API 一致。

### `StaticVendoredLinkage`：全部静态链接，禁止系统探测

shaping（`harfrust`）、metrics（`skrifa` / `read-fonts`）、WOFF2 解码（`wuff`）均为
纯 Rust 实现，无 C/C++ 构建依赖。构建禁用 pkg-config 与运行时 dlopen 探测。
CI 对每个平台产物执行 `ldd` / `dumpbin` 审计，动态依赖只允许 OS 基线库，出现
fontconfig、freetype、harfbuzz 系统库即失败。

Windows 静态库链接必须最先完成验证。Kotlin/Native mingw 产物与 MSVC 工具链存在
CRT 与运行时符号差异；MSVC 不兼容时 Windows 产物改用 GNU 工具链构建并在 CI 增加对应 job。

### `CargoPlatformBinaryCrates`：cargo 侧平台 crate 分发

cargo 用户经 crates.io 获得预编译静态库，无需 JDK 或 Gradle。`tiqian` 以
`[target.'cfg(...)'.dependencies]` 引用四个平台 crate。target 过滤使非当前平台的 crate 不进入
构建图，`cargo build` 只下载参与构建的 crate。`cargo fetch` 与 `cargo vendor` 仍会取全部
平台 crate，见 Consequences。平台 crate 与主包同版本发布，内嵌静态库携带引擎 revision，
绑定层加载时校验；revision 不一致时报具名错误。

平台矩阵按需扩展，四个初始目标不构成封闭清单。`tiqian` 绑定不绑定 web 用途，
Kotlin/Native 与 Rust 的目标交集还覆盖 iOS、tvOS、watchOS 的设备与 simulator 变体，以及
Android native 的 aarch64、x86_64、x86、armv7（需 NDK sysroot）。新增目标按既有模式扩展：
`frontend/web-precompute` 补编译目标，发布对应平台 crate，CI 补链接 job 与二进制审计。
没有消费者需求时不预先发布，也不在文档宣称支持。Intel macOS 与 Intel iOS simulator 沿用
ADR 0045 的排除。

### `NpmPrecomputePackage`：precompute 从 `@tiqian/prose` 迁出

npm 侧新增 `@tiqian/precompute`。主包持有 JS 入口、`.d.ts` 与 Neon 加载器；四个 npm 平台包
持有 `.node`，经 `optionalDependencies` 按平台安装。同维护者的 blurest 仓库验证过 Neon 多
平台 npm 分发，包结构沿用其主包与平台包的形式。npm 平台包同样内嵌 revision；加载器在
require 时校验主包与平台包的版本及 revision 配对；不一致时报具名错误。产物基于 N-API，跨
Node 大版本稳定；`engines` 沿用 `@tiqian/prose` 的 Node 22 下限。musl Linux 与 win32-arm64 不在
首版支持清单，加载时与 darwin-x64 一样报具名错误；需求出现时按同一平台包模式补充。

兼容性约束：`./precompute` 与 `./precompute-html` 的全部现有导出在 Neon 重构后同名同签名
继续提供，含 `createPrecomputer`、`createHtmlPreparer`、`renderSnapshotBundle`、
`renderFontContractBundle`、`renderSnapshotTemplate`、`renderPreparedParagraph`、
`snapshotPlainTextIssue`、`findHtmlOpeningTags`、`injectHtmlAttributes`、
`snapshotServerAssets` 与 `renderSnapshotServerAssets`。实现归属：Node 侧纯计算全部在 Rust
实现，经 Neon 导出。现有导出中只有 `renderPreparedParagraph` 例外，它与浏览器运行时共享同一份
prepared-dom 实现；浏览器无法加载 `.node`，该实现留在 JS，由主包再导出。平台加载器与类型声明
留在 JS，它们是接线代码。README 说明推荐用法：常见站点只用 `createPrecomputer` 或
`createHtmlPreparer` 配合 bundle 渲染，其余导出供调用方灵活组合。Astro / SvelteKit 集成与新
站点只改 import 来源。`@tiqian/astro` 与 `@tiqian/sveltekit` 新增
`@tiqian/precompute` 依赖，与 `@tiqian/prose`、`@tiqian/precompute` 同版本发布。

`@tiqian/prose` 删除 `./precompute`、`./precompute-html` 入口、Node 侧 precompute 文件与
三个 WASM 依赖，移除随 0.2.0-alpha 发布生效；`@tiqian/precompute` 以同一版本号起步。这是一次
breaking change，发生在 alpha 阶段，不提供兼容 re-export。浏览器运行时继续使用
`prepared-dom.js`、`snapshot-manifest.js` 等共享文件的浏览器副本。

字体会话独立公开：`createFontSession` 接受 `faces` 或 `fontStylesheets`，`createPrecomputer`
复用同一字体会话。其中一个站点为三种 typography 各建一个 precomputer，同一字体解码三遍；
共享字体会话取代此用法。

### `LegacyJsOracleCutover`：JS 实现先作 parity oracle，后移除

切换分三阶段：

1. Rust 侧与 JS 侧并行存在。差分 harness 以 `tiqian-precompute` 的 cargo 集成测试承载，
   语料期望值由现行 Kotlin/JS npm 产物生成并入库；语料为 npm 测试语料、layout golden 语料与
   两个站点的正文。比对前 harness 先断言两侧 layout / render / backend revision 逐字相等；
   shaping 引擎标识两侧按设计不同（JS 侧 `harfbuzzjs` 版本、Rust 侧 `harfrust` 标识），
   属差异豁免字段。此后逐层比对 shaping 证据、plan JSON、prepared DOM、manifest 与 bundle，
   豁免清单为引擎标识字段。
   byte-identical 按 canonical 序列化定义：字段顺序、浮点格式与 DOM 属性顺序由契约固定；
   浮点序列化在 Kotlin/JS 与 Kotlin/Native 间的差异是首要核对项。harness 发现差异
   时先判断属于格式还是语义：格式差异修 canonical 层，语义差异阻塞。门槛按最终支持平台全集计算；
   Windows 链接验证长期受阻时把 Windows 移出支持清单并记录，legacy 移除按剩余平台达标执行。
2. 删除 `@tiqian/prose` 的 Node precompute 与 WASM 依赖；`frontend/web-precompute` 的 js
   目标降为 oracle。
3. 删除 js 目标，发布 `@tiqian/precompute` 稳定版并更新架构文档。

oracle 期间 Rust 侧逐字复用 `snapshot-schema.js` 的既有 revision 常量。迁移完成后 revision
常量在 `@tiqian/prose` 与 Rust 侧各持一份声明，npm 测试断言两侧相等；`@tiqian/prose` 不依赖
`@tiqian/precompute`，浏览器包不引入原生依赖。`snapshot-schema.js` 还定义 replay key 函数，
Rust 会话产出相同的 replay key，该层一致性由差分 harness 与共享 golden 覆盖。
字体会话层的 parity 曾由 `tiqian-precompute` 的 `js_session_parity` 集成测试承载：同一
case matrix 分别经 Rust 会话与 Node 下的 `precompute-fonts.js` 执行，两侧输出 JSON
逐字节比对。2026-08-20 矩阵输出一致：六个会话（含四个错误路径与 session 计数器语义）、
22 次 shape、10 次 metrics、renderFamilies、beginCapture 与 evidence 捕获，豁免字段
仅 `harfbuzzVersion`。js 目标删除后该测试一并移除：oracle 实现与其 npm 依赖不再存在，
会话层的持续回归由 crate 单元测试与引擎链接测试承担。

迁移完成后 prepared DOM lowering 有 Rust 与浏览器 JS 两份实现。共享 golden 语料常驻双向
断言：`cargo test` 与 npm 测试对同一语料断言字节一致，取代 ADR 0040 的单文件共享不变量。
js 目标删除时，`build_fonts_parity` 与 `precompute_html_parity` 无法再运行 js oracle，
改为与固定不变的 golden dump 比对（`tests/build-fonts-golden.txt` 与
`tests/precompute-html-golden.txt`）。golden 录自两侧输出逐字节一致的时点；重新生成用
`TIQIAN_UPDATE_GOLDEN=1`，行为变化以 golden diff 为准。`precompute_html_parity` 的 golden
在 `prepareHtml` 文档循环改为并行执行的当天重新生成；生成前先从 git 历史恢复 js oracle
的输出，核对与 Rust 输出一致后再写入。

## Consequences

- 构建工具用户获得原生 precompute，Rust 使用者获得可组合的 crate 入口，两者共享同一引擎
  revision 与字节级输出。
- CI 面扩大：macosArm64 的静态库在 macOS runner 产出，mingw 在 Windows runner 产出，两个
  Linux 目标可交叉编译；konan 产物由 CI 上传为平台 crate 与 npm 平台包的发布产物。七个
  crate 与五个 npm 包同版本发布。
- `cargo fetch` 与 `cargo vendor` 携带全部平台 crate。
- 支持清单不含 Intel macOS、musl Linux 与 win32-arm64，加载时报具名错误；Windows 支持取决于
  mingw 链接验证结果。
- 迁移后构建期走 Kotlin/Native，浏览器运行时仍走 Kotlin/JS。同一 Kotlin 源跨两个编译后端，
  revision 校验与共享 golden 语料防止两侧输出漂移。
- Node 使用者的运行依赖变为原生插件，升级时需按具名错误自查平台支持。
- `frontend/web-precompute` 在 js 目标外增加四个 native 目标，上游六个模块补齐构建配置与
  断词 actual，模块职责不变。
- flake 开发环境引入 rust-overlay；linux 与 mingw 的 Kotlin/Native 目标为仓库首次启用。

## Amendment (2026-08-20)：引擎级 ABI 取代 precompute wire，出口归引擎层

初版把 precompute wire 直接铺在 C ABI 上，`tiqian_precompute_paragraph` 用 15 个扁平参数
加 U+001E/U+001D/U+001F 分隔符编码入参、plan JSON C 字符串出参。这让绑定层持有 precompute
词汇，js 门面与 C ABI 门面留在 precompute 目录。本修订按当天的架构裁定重定层的边界。

### `EngineLevelAbi`：`tiqian_layout_paragraph` 打包二进制协议

- 废除初版「C ABI 保持现有 wire 契约」段与 `tiqian_precompute_paragraph`、
  `tiqian_precompute_release_string` 两个符号。新符号为
  `tiqian_layout_paragraph(const uint8_t* request, uintptr_t request_len,
  uint8_t** response_out, uintptr_t* response_len, const char** error_out)` 与
  `tiqian_release_buffer`。
- 协议沿用 `tiqian_font_backend.h` 的形式：头文件 `tiqian_layout_abi.h` 是双侧单一事实源，
  Rust 直接编译；Kotlin 侧常量镜像并以注释锚定，与 shaping 修订常量的既有形式一致。
  缓冲区带 magic 与 protocol revision，版本化演进。
- request 携带 `LayoutInput` 的引擎级字段：正文 UTF-8 字节、textStyle、paragraphStyle、
  constraints、text spans、source boundaries、line-break spans、inline boxes。所有文本
  索引按 UTF-16 code unit 定义，与引擎 `TextRange` 一致；Rust 侧不得按 UTF-8 重新编号。
- response 是 plan JSON：UTF-8、NUL 结尾、nativeHeap 分配，经 `tiqian_release_buffer`
  释放。plan JSON 的序列化只有 Kotlin 一份实现（`toPreparedParagraphJson`），prose 的
  js 路径与 Rust 的原生路径共同消费。在 Rust 侧重写序列化被否决：双实现存在行为漂移
  风险。这是本修订认可的唯一层间扭曲，引擎出口携带 web-core 的 plan JSON。浮点格式
  经 Kotlin/JS 与 Kotlin/Native 两个编译后端，统一为 `PlanNumberCanonicalForm` 描述的
  ECMAScript 形式。
- `PackedFfiCalls` 中「plan JSON 保持单次返回的 C 字符串，Rust 解析一次」段继续有效。

### `PrecomputeInRust`：precompute 词汇全部回到 Rust 消费侧

初版把 wire 解析、入参校验与 `LayoutInput` 组装放在 Kotlin commonMain。修订后这三项移植为
`tiqian-precompute` 的 Rust 代码：typed 请求结构、具名校验错误（错误名与 npm 测试断言
一致）、ABI request 打包与调用。plan JSON 序列化留在 Kotlin 单点；Rust 侧只做反序列化，
供后续 prepared DOM 下放消费，不提供发射器。分隔符 wire 解析不移植；该编码只在 js 门面
内部继续服务浏览器路径。

### `EngineFfiModules`：Kotlin FFI 门面归引擎层

- `frontend/web-precompute` 的 Kotlin 全部迁出。C ABI 门面进入新模块 `ffi/native`，
  四个 Kotlin/Native 目标与 `linkReleaseStatic*` 产物随之迁移；`tiqian_install_font_backend`
  的重导出留在该模块。js 门面（`@JsExport`、wire、`HarfBuzzBuildBackend`）进入新模块
  `ffi/js`，npm precompute-runtime 组装任务跟随。`frontend/web-precompute` 只保留
  Rust workspace 与 npm 包，不再含一行 Kotlin。
- `RustPrecomputeStack` 中「`frontend/rust` 持有中性引擎绑定」的表述修正为：`tiqian` crate
  是 sys 绑定，声明 `tiqian_layout_abi.h` 的符号并链接平台静态库。ABI 升级为引擎级之后，
  「绑定不依赖 web 概念」才真实成立。sys 层允许同时承载 web-core 契约的绑定，当前修订
  未行使该许可；plan JSON 的 schema 常量在 `tiqian-precompute`。
- precompute 域对引擎的全部访问只经 `frontend/rust` 的绑定。Kotlin 出口与 sys 同属引擎
  出口面，不留在 precompute 目录。

### `JsTargetStaysBrowserSide`：LegacyJsOracleCutover 第 3 阶段修正

初版第 3 阶段「删除 js 目标」与浏览器 `layout-worker.js` 的依赖冲突。修正为：js 目标长期
保留，承担浏览器 exact-font 回退 worker 与 parity oracle 两个角色；删除的是 Node 生产路径
对 js 产物的消费。`ffi/js` 模块因此是常驻出口，非过渡产物。

### `PlanNumberCanonicalForm`：plan JSON 浮点统一为 ECMAScript 形式

`appendJsonNumber` 原样使用 `Float.toString`，三个 Kotlin 后端输出三套字节：Kotlin/JS 打印
f64 加宽值（`20.34000015258789`、整数无小数点），JVM 与 Kotlin/Native 打印 f32 最短形式
（`20.34`、整数带 `.0`）。数值本身一致，分歧只在表示。修订后 plan 数字在 commonMain 单点
规范化为 ECMAScript `Number::toString` 形式：位数取自 `Double.toString`，布局按 ECMA 阈值
重排，末位从 Float 的精确十进制展开按 half-even 取整。选择 ECMAScript 形式使两个 JS 消费
方（npm 生产路径与浏览器 worker）字节不变，只影响 JVM 与 Native 输出；dtoa 库在精确
十进制半值处的舍入差异由精确展开消除。JVM golden dump 不含 plan JSON，无 fixture
变化。

### Verification 增补

- plan parity：同一语料经原生路径（Rust 打包 → ABI → 引擎 → Kotlin plan JSON）与 js oracle
  （`precomputeParagraph` ESM bundle）双路输出字节一致，进入 `LegacyJsOracleCutover` 的
  比对层清单。载体为 `tiqian-precompute` 的 `plan_parity` 集成测试与
  `frontend/web-precompute/scripts/plan-parity-oracle.mjs`；两侧语料与 fixture 字体后端
  数值一一对应，fixture 取自 `PrecomputeExportsTest` 的 canonical 数。2026-08-20 起
  九个语料（标点压缩、中西混排、缩进、span、source boundaries、断行 policy、inline box、
  ellipsis 回退、纯换行）字节一致；`plan_parity` 在无 oracle dump 时按理由跳过，
  CI 以 `TIQIAN_REQUIRE_PARITY_ORACLE=1` 强制比对。
- `tiqian` sys crate 在 `TIQIAN_NATIVE_LIB_DIR` 指向 Gradle `linkReleaseStatic*` 产物时
  链接真实引擎，`cargo test` 在 linux CI 的 `rust-engine-parity` job 跑通 plan parity。
  build script 对归档文件声明 `rerun-if-changed`，引擎归档重建后 cargo 侧强制重链接。
- `EngineFfiModules` 已实现：js 门面位于 `ffi/js`（bundle 名 `Tiqian-tiqian-ffi-js`），
  `jsNodeTest`、npm runtime 组装任务与 parity oracle 的 bundle 路径同步；`ffi/native` 的
  四个 `linkReleaseStatic*` 目标成为唯一 native 产物；`frontend/web-precompute` 只剩
  Rust workspace、npm 包与 parity 脚本，不含 Kotlin。

## Alternatives considered

- **保留 Node Kotlin/JS 与 WASM 运行时。** 否决：构建期 WASM 加载成本仍在，Rust 生态无入口，
  包边界维持现状。
- **build.rs 构建期下载预编译二进制。** `ort` 一类模式。否决：构建依赖网络与硬编码第三方
  下载源，开发体验差；crates.io 平台 crate 获得原生缓存与离线构建。
- **全平台二进制打包进单一 crate。** 否决：crates.io 单包 10MB 上限，且所有用户全量下载全部平台。
- **字体会话留在 Kotlin/Native 内直接链接 HarfBuzz。** 否决：字体会话属于 precompute 消费层，
  Rust 编排也消费同一会话；vtable 安装模式保持引擎与现有 JS 架构同构，shaping 引擎
  版本只在 Rust 一处维护。
- **backend 函数表按每次调用传参。** 否决：要求改动扁平 wire 签名并让每次调用携带函数表；
  全局安装与现行全局对象协议同构，只需一次安装。
- **napi-rs 代替 Neon。** 否决：blurest 已在 CI 验证 Neon 多平台发布流程；napi-rs 没有本
  仓库的验证记录。
- **Kotlin/Native 直接产出 Node addon。** 否决：Kotlin/Native 无法独立产出 N-API addon；
  Rust 生态入口仍缺失。
- **precompute 继续留在 `@tiqian/prose`。** 否决：混合发布与 ADR 0042 分层冲突，breaking
  迁移趁 alpha 阶段完成。

## Verification

- `:frontend:web-precompute` 四个 native 目标编译并通过 native 测试；`jsNodeTest` 行为不变。
- `cargo test -p tiqian-precompute` 覆盖 wire 解析、face 选择与 manifest。
- 差分 harness：最终支持平台全集 × 全语料 byte-identical，是移除 legacy 的硬门槛。
- 差分 harness 记录每段落的跨 FFI 调用次数，断言与 segment 数线性相关。
- 迁移完成后共享 golden 语料在 `cargo test` 与 npm 测试双向断言字节一致。
- revision 常量由 `@tiqian/prose` 与 Rust 两侧声明，npm 测试断言相等。
- CI `ldd` / `dumpbin` 审计四平台 `.node` 与示例二进制。
- npm 测试套件经 Neon 路径全部通过；Astro / SvelteKit 集成测试改引 `@tiqian/precompute` 后
  全部通过。
- Windows mingw 静态库链接验证最先执行，覆盖 MSVC 与 GNU 两条工具链路径。

## 附录（2026-08-21）：两站生产基准与等效性审计

测试平台：Ryzen 7 8845HS（16 硬件线程）、92 GiB 内存、linux x86-64。
原实现为 `@tiqian/prose` 0.1.0-alpha.5（Kotlin/JS 引擎 + harfbuzzjs 14.2.1）；
Native 为 `@tiqian/precompute`（Neon addon + harfrust 0.13.0 + 静态链接的
Kotlin/Native 引擎，release 构建；blog3 四组实测时 linux-x64 addon 为
8,439,088 字节，neo-blog 实测时为 8,366,448 字节）。每轮清除快照缓存冷启动，
各跑三轮；RSS 用 `/proc` 对进程组内全部进程按 50ms 采样；端到端耗时为整条
构建命令的端到端耗时。调用计数与耗时按调用逐条追加落盘：vite 在多个 worker
线程各自实例化宿主模块，单个统计文件只保留最后写入线程的视图，逐条追加覆盖
全部调用。十二次构建的退出码均为 0。线程数由 `TIQIAN_PRECOMPUTE_THREADS`
固定；未设置时取 available_parallelism（本机为 16）。批处理入口按线程分摊，
单一段落入口不读该变量。

### 性能结果

blog3（bun + vite v8.0.8 SSG；285 页，183 页含 precompute；单轮 6 次
`createPrecomputer`、6519 次 `prepareParagraph`、946 次 `prepareFontContract`、
297 次 `renderSnapshotBundle`；306 条缓存条目）：

| 实现 | 端到端耗时 ms（三轮） | 内存峰值 KiB（三轮） | vite build 阶段 s（三轮） |
|---|---|---|---|
| 原实现 | 233,637 / 250,558 / 237,972 | 3,750,964 / 4,047,492 / 3,787,024 | 228 / 245 / 233 |
| 单线程 Native | 80,687 / 80,669 / 81,822 | 1,859,896 / 1,868,508 / 1,887,940 | 76 / 75 / 77 |
| 双线程 Native | 64,387 / 64,049 / 64,456 | 1,971,664 / 2,037,328 / 1,949,232 | 59 / 59 / 59 |
| 四线程 Native | 57,040 / 56,601 / 56,584 | 2,043,836 / 2,057,448 / 2,033,940 | 52 / 51 / 51 |

vite build 阶段取构建日志两行 `built in` 中的长值。原实现一轮的调用计时合计
228.2 s：`prepareParagraph` 6519 次 197.7 s、`prepareFontContract` 946 次
23.2 s、`renderSnapshotBundle` 297 次 7.3 s。Native 批处理耗时按捕获的批次
输入离线重放测得（379 个批次、6519 段，预热一轮后取 7 轮）：

| 线程数 | 最佳 ms | 中位 ms | 相对单线程 |
|---|---|---|---|
| 1 | 41,478 | 41,865 | 1.00× |
| 2 | 25,964 | 26,214 | 1.60× |
| 4 | 18,732 | 18,851 | 2.21× |
| 8 | 16,554 | 16,664 | 2.51× |

vite build 阶段约等于 33 s 构建基线加批处理耗时（1/2/4 线程的残差为 34.5 /
33.1 / 32.8 s）。批次大小中位 4 段、p90 47 段、最大 248 段；89 个单段批次
直接内联执行，2 线程以上收益随之收敛。对照实验：宿主改走单一段落入口后，
1 与 4 线程共四轮端到端 83.5–89.3 s，线程变量不产生影响。四线程相对原实现
的端到端耗时为 0.24，内存峰值为原实现的 0.54，自身比单线程多约 9% 内存
（每线程一份证据缓冲与栈）。

neo-blog（pnpm + astro static + pagefind；每轮 326 段落 + 18 字体契约；327 条
缓存条目；astro 单进程串行渲染，调用计数无分摊）：

| 实现 | 端到端耗时 ms（三轮） | 内存峰值 KiB（三轮） | 引擎计时合计 |
|---|---|---|---|
| 原实现 | 21,359 / 20,332 / 20,085 | 2,013,588 / 2,036,740 / 2,021,608 | 13.8–14.7 s |
| 单线程 Native | 8,494 / 8,269 / 8,247 | 2,042,900 / 2,076,572 / 2,054,008 | 1.9–2.0 s |

单线程 Native 的端到端耗时为原实现的 0.40；内存峰值持平（astro 与 vite
占据该站内存主体）。`prepareParagraph` 326 次从 11.8–12.7 s 降到 1.15–1.23 s
（约 10 倍），引擎计时合计从 13.8–14.7 s 降到 1.9–2.0 s（约 7.3 倍）。

### 等效性审计

按层给出结论。请求层逐字节一致；plan 层只差浮点尾数；产物层差异全部来自
Kotlin `Float` 精度与 HarfBuzz 版本两个来源；断行与行结构在两站语料上零差异。

- **请求层。** blog3 抽样页 70 条记录的 `prepareParagraph` / `prepareFontContract`
  全部入参（text、maxWidthPx、sourceBoundaries、textSpans、inlineBoxes、
  semantics）两侧逐字节一致。Rust 字体会话的 font-face boundary 移植与
  alpha.5 行为一致，sourceBoundaries 的会话侧贡献没有引入差异。
- **plan 层。** 差异全部落在 `naturalWidth` 与 `drawX` 的浮点值上，结构与枚举零
  差异。机制：引擎几何类型是 Kotlin `Float`，Kotlin/JS 的 `Float` 由 JS number
  （binary64）承载，Kotlin/Native 是 IEEE binary32。`PlanNumberCanonicalForm`
  统一了数字的表示，数值本身仍随后端精度不同。blog3 抽样页 1003 对浮点差、
  neo-blog 全站 327 条中 174 条共 4114 对；float-float 对里可验证
  `f32(原实现值)==Native 值` 的占 585/975 与 2847/4114，其余是逐次累加的
  `drawX` 单精度舍入。最大偏差 7.3e-4 px
  （约 883 px 处的行尾 drawX），单字形宽偏差不超过 4e-5 px。
- **产物层。** blog3：`clientTemplate` 与 `renderedContent` 306/306 一致（把
  `harfbuzzVersion` 标识替换为占位符后比对）；`inertTemplate` 275/306、
  `initialStyle` 239/306 不同。机制有二。其一，5 位小数处的 letter-spacing 值
  不再字符串去重，声明条目从 26 增至 33，每个值与对侧相差 1e-5 px 量级。
  其二，单字符 clamp 判定 `naturalWidth + trailingGap >= 0` 的一个记录值落在
  距零点 1.2e-4 px 内，两侧落在不同分支，该处 `letter-spacing` 翻转为
  `margin-right`；两个分支的 CSS 都由 lowering 的同一段代码生成。neo-blog：
  dist 742 个文件中 736 个一致；3 个页面是上述 tqv 变体机制；2 个页面仅标识
  长度差与一处 replay 记录位。
- **shaping 证据层。** harfbuzzjs 14.2.1 与 harfrust 0.13.0 在 neo-blog 全站
  1525 条 replay shape 上 advance、glyph 位置、glyph id 全一致；`unsafeBreakCount`
  31 条不同（原实现 ≥ Native，如 3 对 2、1 对 0）；3 个字形
  （JetBrains Mono Variable 的 t）`boundsEm` xMax 差 0.001 em。引擎消费的
  advance 与位置没有差异，两站没有任何断行因 `unsafeBreakCount` 改变。
  该字段未纳入此前的版本差分维度，此处补记。
- **线程等价。** 单线程、双线程、四线程 Native 三轮构建写出的 306 条缓存
  两两字节一致（0 差异）。线程只改分摊调度，不改任何输出。
- **标识层。** 除 `fontEvidence.harfbuzzVersion`（`14.2.1` 对 `harfrust-0.13.0`）
  与 `backendRevision` 外，face 指纹全量一致；两个标识维持既有豁免。

### 后续（不阻塞）

- 引擎几何 `Float` 迁移 `Double` 的评估：消除跨后端小于 0.001 px 的位置偏移、
  tqv 变体数增加与 clamp 边界翻转三类产物差异；代价是引擎几何类型的全量替换。
- plan parity 语料补入 binary32 不可表示的 advance 值，使平台精度差进入
  CI 比对。
- `unsafeBreakCount` 与 glyph extents 纳入 HarfBuzz 版本差分的比对维度。
- `renderSnapshotBundle` 原生路径单次多 3.6 ms，可单独复查。

## 附录（2026-08-21 第二轮）：契约批量入口与 prepareHtml 文档循环的并行执行

本轮改动三处：新增 `prepareFontContracts` 批量入口（Rust 方法、Neon 导出、
TypeScript API）；`prepareHtml` 的文档循环先按文档顺序遍历，再把各元素并行处理，
最后按文档顺序重组输出，各元素的快照尝试与契约回退发生在并行阶段；blog3 宿主
改为按 article 批量提交契约请求。测试平台与采样方法同第一轮；本轮 linux-x64
addon 为 8,465,208 字节。blog3 每轮仍为 946 次契约请求，批调用按
article × precomputer 合并。

### 性能结果

blog3 端到端（每个线程数三轮，每轮从空缓存开始；第一轮数字来自上一附录）：

| 线程数 | 第一轮 ms | 第二轮 ms | 第二轮内存峰值 KiB |
|---|---|---|---|
| 1 | 80,687 / 80,669 / 81,822 | 82,815 / 83,519 / 83,520 | 1,874,628 / 1,860,768 / 1,887,944 |
| 2 | 64,387 / 64,049 / 64,456 | 65,544 / 67,555 / 66,150 | 1,939,708 / 1,970,060 / 1,958,276 |
| 4 | 57,040 / 56,601 / 56,584 | 57,248 / 57,823 / 57,102 | 1,986,160 / 2,002,688 / 2,017,944 |

九次构建的退出码均为 0。耗时差全部出现在 vite build 阶段：1/2/4 线程该阶段的
三轮中位数从 76 / 59 / 51 s 变为 78 / 61 / 52 s。契约请求的离线重放（946 条站点
正文文本，预热一轮后取 7 轮，单进程）：

| 调用方式 | 线程数 | 最佳 ms | 中位 ms |
|---|---|---|---|
| 逐条 `prepareFontContract` | 1 | 7,636.9 | 7,712.0 |
| 逐条 `prepareFontContract` | 4 | 7,663.8 | 7,704.9 |
| 批量 `prepareFontContracts` | 1 | 7,688.2 | 8,225.1 |
| 批量 `prepareFontContracts` | 2 | 4,507.8 | 4,684.6 |
| 批量 `prepareFontContracts` | 4 | 3,036.5 | 3,073.1 |
| 批量 `prepareFontContracts` | 8 | 2,374.4 | 2,454.8 |

按中位数，批量入口在 2/4/8 线程下的耗时分别为逐条调用的 0.61 / 0.40 / 0.32；
1 线程比逐条调用慢 6.7%（批入参的 JSON 序列化与结果数组分配）。端到端没有出现
同量级的缩短，原因是：946 次契约请求分布在 6 个 vite worker 上，每个 worker 的
串行契约耗时约 1.3 s（7.7 s 除以 6）；进程内并行最多为每个 worker 节省约 1 s，
在约 33 s 的构建基线里不可分辨。宿主端的合并已到上限：单个 article 内全部快照
未命中的回退请求都通过同一次调用提交。跨 article 合并要求宿主先收集各页请求再
统一执行，可节省的上限相同，本轮不做。1 线程的端到端差值约 +2.8 s，其中约
+0.5 s 与离线
重放的差值一致；其余约 2.3 s 本轮未查明原因。

`prepareHtml` 的并行执行没有端到端测量：blog3 宿主自行遍历 DOM，调用
`prepareParagraphs` 与 `prepareFontContracts`；neo-blog 宿主逐条调用
`prepareParagraph` 与 `prepareFontContract`。两个站点都不经过 `prepareHtml`，
该入口的行为等价由重新生成的 `precompute-html-golden.txt` 与 npm 测试承担。

neo-blog 第二轮（每个线程数三轮，每轮从空缓存开始；第一轮单线程 Native 为
8,494 / 8,269 / 8,247 ms、内存峰值 2,042,900 / 2,076,572 / 2,054,008 KiB）：

| 线程数 | 端到端 ms（三轮） | 内存峰值 KiB（三轮） |
|---|---|---|
| 1 | 8,201 / 8,199 / 8,144 | 2,126,288 / 2,144,424 / 2,183,952 |
| 2 | 8,357 / 8,179 / 8,094 | 2,187,552 / 2,171,708 / 2,143,788 |
| 4 | 8,093 / 8,081 / 8,089 | 2,178,408 / 2,178,912 / 2,157,480 |

九次构建的退出码均为 0。该站宿主只逐条调用 `prepareParagraph` 与
`prepareFontContract`，这两个入口不读取线程数环境变量；1/2/4 线程三轮的中位数
8,199 / 8,179 / 8,089 ms 之间的差值小于同一线程数内三轮之间的波动（2 线程组内
为 263 ms），与第一轮的 8,269 ms 处于同一量级。内存峰值比第一轮高约 4 至 5%。

### 等效性审计

第二轮 1/2/4 线程三轮构建写出的 306 条缓存两两字节一致（0 差异），并与第一轮
4 线程构建的缓存在把 `generation` 字段替换为占位符后 306/306 逐字节一致；该字段把宿主
源文件计入哈希，本轮宿主有源码改动，其余字段全部相同。批量与逐条调用对同一
输入产出相同的缓存条目。neo-blog 第二轮 1/2/4 线程的 `prepared-paragraphs.json`
两两字节一致，dist 的 742 个文件把版本标识替换后 742/742 一致；两者并分别与
第一轮 native 构建的缓存（327 条、plan 零差异、共享字段全部相同）与 dist
（742/742）一致。

## 附录（2026-08-21 第三轮）：宿主缓存下相对 JS 基线的构建对比

本轮测量引擎接入宿主持久缓存后的端到端构建耗时，对照沿用宿主 JSON 缓存的
JS 引擎基线。语料为两个参考站点（blog3 与 neo-blog），测量维度为墙钟时间，
未采样内存。空缓存指引擎缓存从零开始的构建，缓存命中指宿主缓存可命中状态下
的构建。

### 性能结果

blog3（306 条条目；两个引擎的空缓存构建均产出 297 条快照与 9 条契约回退，
工作量一致）：

| 引擎 | 空缓存 | 缓存命中 |
|---|---|---|
| JS | 263.3 s / 268.1 s | 16.2 s |
| native | 55.0 s / 54.8 s | 14.3 s / 14.4 s / 15.6 s |

空缓存构建耗时 263.3 s 对 55.0 s，为 4.8 倍。缓存命中的差值 1 至 2 s：该阶段
两个引擎都不执行 shaping，条目只被读取与解析，耗时主体在宿主自身的构建流程。

neo-blog：

| 引擎 | 空缓存 | 缓存命中 | 缓存字节数 |
|---|---|---|---|
| JS | 137.3 s | 8.0 s | 16,143,660 |
| native | 29.3 s / 28.8 s | 9.2 s / 9.1 s | 16,326,219 |

空缓存构建耗时 137.3 s 对 29.3 s，为 4.7 倍。缓存命中时 native 比 JS 慢约
1.1 s；两侧的命中构成相同（快照 1232 命中 59 缺失，契约 40 命中 9 缺失），
缓存文件字节数相当。宿主缓存把构建耗时从空缓存到缓存命中分别压缩为 blog3
55.0 s 到 14.3 s、neo-blog 29.3 s 到 9.2 s。

### 等效性审计

native 的 blog3 两轮空缓存构建写出的 306 条缓存逐字节一致；JS 基线的空缓存
构建与 native 的条目数、快照与回退构成相同（297 条与 9 条），内容差异按
第一轮附录的引擎差分方法比较。

## 附录（2026-08-21 第四轮）：持久缓存与预填接入后的构建对比

同一语料（blog3）上比较接入前后的构建耗时。接入内容为 0052 第二批附录的
提交出口、渲染池与预填；预填开启与关闭各测一组。

| 配置 | 空缓存 | 缓存命中 |
|---|---|---|
| 接入前 | 56.5 s / 56.4 s | 15.5 s / 15.3 s |
| 接入，预填开启 | 54.0 s / 54.2 s | 15.7 s / 16.4 s |
| 接入，预填关闭 | 54.1 s | 15.5 s |

空缓存构建快 2.2 至 2.5 s。缓存命中的构建差 0.2 至 1.1 s：三个 PersistentCache
的建立与字体文件哈希约 1.6 s，其余为枚举时逐项检查缓存命中。预填在空缓存构建
与页面渲染共用同一渲染池，计时与关闭相当；缓存全命中时预填没有需要提交的条目。

空缓存构建的引擎计数：构建进程含两个相互隔离的模块上下文，分别计数为 5217 次
内存命中、11528 次计算、2117 次预填、6960 次写出，与 200、565、157、370。
缓存命中时只余约 29 次计算，均为无快照条目的契约项。

### 等效性

空缓存构建的产物按内容逐份配对比较，两侧各 144 份快照 JSON，差异 0。把每个
构建自身的随机量（bundler 哈希文件名、构建时间戳、宿主侧加密内容的随机密文）
替换为占位符后，页面与数据文件无剩余差异。
