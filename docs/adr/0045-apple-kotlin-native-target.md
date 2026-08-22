# ADR 0045: Apple (Kotlin/Native) 目标

- Status: Accepted
- Date: 2026-08-08
- Amended: 2026-08-20（macosX64 处置状态表述修正，决定不变）
- Refines: [ADR 0001](0001-core-pipeline-and-platform-boundary.md)（核心 pipeline 与平台边界）

## Context

提椠原有 JVM、Kotlin/JS、Android 目标,没有 Apple 原生目标。一个原生 macOS/iOS 阅读器要直接调用排版核心(而非经 JVM 或 WebView),需要组合核心跑在 Kotlin/Native 的 Apple 目标上,并最终作为 Swift 可消费的库。核心能否干净移植到 Native 是开工前的最大未知数。

## Decision

`AppleNativeCompositionTarget`:给组合核心模块(`:core`、`:font`、`:shaping:api`、`:clreq`、`:linebreak`、`:layout`)加 `macosArm64`、`iosArm64` 与 `iosSimulatorArm64` 目标，继续预留 writing-mode 等扩展点。

依据与做法:

- 组合核心为纯 `commonMain`,且**已能编译到 Kotlin/JS**——这证明它不含 `java.*` / `android.*` 依赖,Kotlin/Native 面对的是同一约束。
- 全核心只有 **2 个 `expect/actual`**,都是西文断词资源加载:`:layout` 的 `defaultHyphenator()` 与 `:linebreak` 的 `loadBundledEnglishHyphenationPatterns()`。补 `macosArm64Main` actual:前者返回 `EnglishHyphenation.enUs`(与 JVM/JS/Android 一致);后者复用嵌入式常量——把原 JS 专用的 `generateJsHyphenationPatterns` 任务泛化为 `generateEmbeddedHyphenationPatterns`(**Web 与 Kotlin/Native 都无同步资源加载**,从同一份 `hyph-en-us.tex` 生成 `EN_US_HYPHENATION_PATTERNS`),`jsMain` 与 `macosArm64Main` 共用同一真源。
- **不加 `macosX64`**:Kotlin 2.3.0 起该目标进入弃用流程，官方计划 2.4.0 移除。2026-08-20
  修正：本条原写「Kotlin 2.3.20 已移除该目标」，版本号与处置状态均有误；不加该目标的决定
  不变。iOS 同时保留 device 与 Apple Silicon simulator slice。
- 平台 shaping / 度量 / 绘制不在核心,由独立适配器提供(见 [ADR 0046](0046-core-text-shaping-adapter.md) / [ADR 0047](0047-core-text-rendering-frontend.md)),核心保持平台无关,继续遵守 ADR 0001 的边界。

## Consequences

- Apple 原生目标可用;英文断词在 Native 上与其他平台**同源**工作(同一份 `.tex`)。
- **JVM / JS / Android 零影响**:JVM/Android 仍读资源文件,JS 仍用嵌入常量,只是任务名从 `Js` 改为 `Embedded`。
- 构建需 JDK 25 toolchain(foojay 自动 provision)+ 现有 Android SDK(配置期即需,即便只构建 Apple 目标——所有模块都声明了 android 目标)。
- 代价(诚实记录):增加 Apple 平台的构建面与长期维护；当前承诺的是横排、只读 Core Text 正文
  view 与 source-faithful selection/copy，不因已有 UIKit/SwiftUI 入口就宣称支持编辑器、IME 或直排。

## Alternatives considered

- **在 Swift 重写排版核心。** 否决:重复实现整套 CLREQ 逻辑、丢失单一真源、与既有引擎分叉,维护灾难。
- **JavaScriptCore 桥接 JS 构建。** 否决:hack、性能与调试都差,且把一个已很干净的 common 核心绕远路。

## Verification

- `:core`、`:font`、`:shaping:api`、`:clreq`、`:linebreak`、`:layout` 均编译到 `macosArm64`、
  `iosArm64` 与 `iosSimulatorArm64`。
- `:clreq:macosArm64Test` 与 `:linebreak:macosArm64Test` 在 Native 全过——避头尾分级、标点 glue 锚定、数字/符号连排、注音解析、Liang 断词等规则在 Kotlin/Native 上正确执行。
- `LayoutDumpGoldenTest`(走确定性 stub,平台无关)不变;JVM 侧验证未受影响。
