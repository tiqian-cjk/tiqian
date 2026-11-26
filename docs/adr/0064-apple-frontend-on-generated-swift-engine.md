# ADR 0064: Apple 前端改用 boring 生成的 Swift 引擎

- Status: Accepted
- Date: 2026-11-26
- Amends: [ADR 0045](0045-apple-kotlin-native-target.md)（Apple 前端不再经 Kotlin/Native 消费引擎）、
  [ADR 0046](0046-core-text-shaping-adapter.md)（适配器改用 Swift 实现，接口约定不变）、
  [ADR 0047](0047-core-text-rendering-frontend.md)（renderer 与 facade 改用 Swift 实现，取消 XCFramework）

## Context

引擎源码在 `engine-haxe/src/`，boring 从它生成 Kotlin、Swift、Dart、TypeScript、Rust 代码。
`boring.json` 的 `swift-f32` 与 `swift-f64` 两个 bundle 生成 Swift 引擎，boring 的 driver 在
`packages/driver/src/driver/Plan.hx` 用 `swiftc -module-name TiqianEngine` 编译并运行生成的测试。

2026-11-26 之前，Apple 前端仍按 ADR 0045 与 ADR 0047 的方式构建：三个 Gradle 模块
`:platforms:apple:shaping`、`:platforms:apple:frontend:coretext-render`、`:platforms:apple:frontend`
依赖 `:boring-kotlin-f32`，经 Kotlin/Native 打成静态 `Tiqian.xcframework`，再由同目录 Swift
Package 以 `binaryTarget` 引用。这条路径有三项已核实的事实：

1. `module-tests.yml` 在 Linux runner 上只编译 Apple 目标的 klib，不链接 XCFramework，不构建 Swift
   Package，也不执行 appleTest（`tools/module-test-tasks.sh` 把这些任务列为只编译、不运行）。2026-11-11 引擎改为
   生成之后，Apple 的 Kotlin 测试与 Swift 包都没有在任何 CI 中运行过。
2. 构建 XCFramework 需要 Gradle、JDK 25 与 Android SDK 配置（所有 Gradle 模块在配置期都声明
   Android 目标），以及 boring 发布工程的暂存副本。
3. Swift 调用 Kotlin 时，`CGContext` 只能以不透明指针跨越边界，整数参数以 `Int32` 出现。

boring 发布到 tiqian Swift registry 的 `tiqian-engine-f32` 0.1.0-alpha.15 可以在 macOS 上编译并完成
排版，但它的 `Package.swift` 由 `packages/compiler/reflaxe/swift/swiftcompiler/Compiler.hx` 的
`packageManifest()` 生成，没有 `products:`，还无条件声明了归档中不存在的 `Resources` 目录。依赖它的
Swift 包构建失败，报错为 `product 'tiqian-engine' required by package 'consumer' target 'Probe' not found`。

## Decision

1. `AppleGeneratedSwiftEngine`：Apple 前端使用 `swift-f32` bundle 生成的 Swift 引擎。精度与原先
   Apple 端使用的 `kotlin-f32` 相同。
2. Apple 端由 `platforms/apple` 下三个本地 SwiftPM 包组成，目录边界与 AGENTS.md 的模块边界一致：
   - `platforms/apple/engine`：产品 `TiqianEngine`。`Sources/TiqianEngine` 是入库的符号链接，指向
     不入库的 `engine-haxe/out/swift-f32/gen`。该 bundle 设置 `package-shell=none`，boring 只写源码，
     清单由本包维护，`sources` 显式列出 `Runtime.swift`、`org`、`std`。
   - `platforms/apple/shaping`：产品 `TiqianCoreText`，包含 `CoreTextShaper`、
     `CoreTextFontMetricsResolver`、共享字体与 `CTLine` 缓存 `CoreTextSupport`，以及
     `CachingTextShaper`、`CachingFontMetricsResolver`。它实现生成引擎的 `TextShaper` 与
     `FontMetricsResolver` 协议，接口约定沿用 ADR 0046。
   - `platforms/apple/frontend`：模块 `Tiqian`（Core Text renderer、paragraph backend、document
     facade）与模块 `TiqianUI`（视图），唯一产品是 `TiqianUI`。`demo/apple` 与下游应用继续以
     `../../platforms/apple/frontend` 引用该包。
3. 删除三个 Gradle 模块、`Tiqian.xcframework` 与 `build-xcframework.sh`。Kotlin 引擎仍由
   `:boring-kotlin-f32` 发布 Apple Kotlin/Native 坐标，供 Kotlin 使用方消费；`module-tests.yml` 继续
   编译这些坐标的测试 klib。
4. `AppleEngineInvariant`：facade 在调用引擎前已限定所有偏移与宽度，因此引擎对 facade 输入抛出的
   `BoringException` 表示不变量被破坏。facade 以 `preconditionFailure` 停止，并给出失败的调用名与引擎
   错误，不推测替代布局或几何。
5. 文本边界：引擎以 UTF-16 码元数组 `[UInt16]` 表示字符串。`CTLine` 由码元直接构造，`Document`
   以码元保存源文本，所有偏移都是 UTF-16 偏移。`String` 与码元数组的转换集中在
   `TiqianCoreText/EngineInterop.swift`。
6. 发布路径暂不依赖 registry 上的 `tiqian-engine-f32`。boring 的 `packageManifest()` 写出 `products:`
   并只在存在资源时声明 `resources` 之后，再决定发布版本如何引用 registry 包。

## Consequences

- 构建 Apple 前端的步骤变为：先执行 `nix develop -c boring gen swift-f32 --project boring.json`，
  再在 `platforms/apple/frontend` 执行 `swift build` 或在 Xcode 打开 `demo/apple`。不再需要 Gradle、
  JDK 与 Android SDK。
- `TiqianUI` 的公共接口不变：`CJKText`、`CJKTextView`、`CJKBlock`、`Indent`、`ListMarker` 与
  `AttributedString` 属性键保持原名。`Tiqian` 模块的 facade 接口改为 Swift 原生类型：偏移为 `Int`，
  绘制方法为 `draw(in: CGContext, canvasHeight:)`，`DocBuilder` 与 `ParagraphContent` 的首个参数不带
  标签，装饰以 facade 枚举 `Decoration` 表示。
- boring 的 Swift 后端生成无标签参数。替换 `ExplainableStubParagraphLayoutEngine` 第 11 个参数
  `textShaper` 时必须写出前 10 个参数；`appleParagraphEngine()` 对其余参数使用
  `ParagraphLayoutEngine.hx` 在参数为 null 时所用的默认构造。`DocBuilder` 从 `ParagraphStyle()` 读取
  默认值，不重复写数值。
- Kotlin appleTest 的 50 个用例移植为 XCTest，放在 `TiqianCoreTextTests` 与 `TiqianTests`。只检查
  `cfRange` 辅助函数的 1 个用例随该函数删除；新增 OpenType feature 语法解析、缓存淘汰顺序与汉字数字
  格式化 3 个用例，移植后共 52 个。连同 `TiqianUITests` 原有的 5 个 macOS 视图用例，macOS 共 57 个。
  斜体用例的度量改为字形上半与下半墨迹重心的水平差：原用例比较最右墨迹列，
  「永」的最右墨迹是靠近基线的捺笔，斜切位移很小，macOS 27 上只有 2 px，低于原阈值 4 px。
- Swift 包尚未进入 CI。tiqian flake 的 devShell 已在 `aarch64-darwin` 上求值并完成生成（见 Verification）；
  在 macOS runner 上运行还需要 Xcode 与 iOS 模拟器运行时，`swift test` 与 `xcodebuild` 在 Nix shell 之外执行。

## Alternatives

- 保留 Kotlin/Native XCFramework：Apple 构建继续依赖 Gradle、JDK 与 Android SDK 配置，Swift 与引擎之间
  多一层 Objective-C 导出，XCFramework 链接也仍不在 CI 覆盖范围内。
- 立即依赖 registry 上的 `tiqian-engine-f32`：生成的清单没有 `products:`，Swift 包无法依赖，见 Context
  中的报错。
- 把生成源码复制进 `platforms/apple/engine`：每次 `boring gen` 之后副本都会与生成结果不一致，并会把
  生成物带入版本库。

## Verification

- 环境：macOS 27.0，Xcode 27.2（Swift 6.4.2），Determinate Nix 3.24.3，iOS 27.2 模拟器运行时。
- 生成：`nix develop -c bash -c 'bash tools/setup-haxe-env.sh && boring gen swift-f32 --project boring.json'`
  输出 `bundle driver: ok`，生成器修订为 boring `4a87c173`（`.haxelib/boring/git/.boring-flake-revision`），
  `engine-haxe/out/swift-f32/gen` 含 239 个 `.swift` 文件与 `_GeneratedFiles.txt`，根目录的 `Test.swift`
  由 `sources:` 排除。tiqian 修订为 `dd504925`（tag `v0.1.0-alpha.15`）。
- macOS：在 Nix shell 之外执行 `swift test`，`platforms/apple/shaping` 18/18 通过，
  `platforms/apple/frontend` 39/39 通过（`TiqianTests` 34，`TiqianUITests` 5）。
- iOS：`xcodebuild test`，目标 `platform=iOS Simulator,name=iPhone 18 Pro`，scheme `TiqianCoreText`
  18/18 通过，scheme `TiqianUI` 41/41 通过（`TiqianTests` 34，`CJKIOSViewTests` 7）。
- demo：`demo/apple` 的 `TiqianDemo` 与 `TiqianDemo-iOS` 均 `BUILD SUCCEEDED`。macOS 应用窗口截图与
  iOS 模拟器截图中，拼音、注音、着重号、专名号、书名号、示亡号、链接下划线、行尾连字符与列表凸排
  均按 `LayoutResult` 绘制。
