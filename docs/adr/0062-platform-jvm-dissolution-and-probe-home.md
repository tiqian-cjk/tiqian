# ADR 0062：删除 platforms/jvm 分组，Skia 模块移入 Compose，探针集中到 engine-probes

- Status: Accepted
- Date: 2026-11-17
- Relates: [ADR 0056](0056-engine-module-and-platform-reorg.md)（按平台的仓库重组）、
  [ADR 0061](0061-scripts-tools-boundary.md)（scripts/ 与 tools/ 分工）

## Context

`platforms/` 在 ADR 0056 之后按宿主分组为 `android`、`apple`、`web`、`jvm` 与
`compose`。`platforms/jvm` 下有 `:platforms:jvm:shaping`（类 `AwtTextShaper`）与
`:platforms:jvm:skia`（Skia / Skiko 实现）两个 Gradle 模块，两个模块都发布 Maven 坐标。

两个模块的实际消费者决定 `jvm` 分组是否成立：

- `:platforms:jvm:skia` 的生产消费者只有 `platforms/compose/compose` 的 `jvmMain`。
  `platforms/compose/compose/src/jvmMain` 的 5 个文件中有 2 个通过
  `org.tiqian.shaping.skia` 引用 `SkiaTextShaper`、`SkiaFontMetricsResolver`、
  `SkiaSystemTypefaces` 与 `lineInkSkipIntervalsWithPositions`。
- `:platforms:jvm:shaping` 没有生产消费者。`platforms/compose/compose` 不引用
  `org.tiqian.shaping.jvm`；引用 `AwtTextShaper` 的位置只有 `:platforms:jvm:skia` 的
  `jvmTest` 与 `tools/engine-probes` 的 5 个探针类。

探针所在的源集与执行入口不一致。`tools/engine-probes/build.gradle.kts` 把探针放在
`jvmMain`，用 `runProbe -PprobeClass=<FQCN>` 手工执行。仓库另有 6 个同类类放在测试源集：
`:platforms:jvm:skia` 的 `jvmTest` 3 个、`platforms/compose/compose` 的 `jvmTest` 2 个、
`platforms/android/shaping` 的 `androidTest` 1 个。发布任务集是
`tools/release-gradle-tasks.sh` 里的 `assemble` 与 `publishTiqianToMavenLocal`，这些测试
源集没有对应的发布任务，因此带 `@Test` 的探针类不会被发布流程执行。

## Decision

1. `:platforms:jvm:skia` 的目录移到 `platforms/compose/skia-jvm`，Gradle 路径改为
   `:platforms:compose:skia-jvm`，Maven 坐标 `tiqian-jvm-skia` 不变。依据：该模块唯一的
   生产消费者是 Compose 的 JVM 目标。
2. `AwtTextShaper` 不发布，也不再是平台模块。类 `AwtTextShaper` 连同
   `AwtTextShaperTest`、`InkBoundsCoverageTest` 与 `AwtSkiaShapingComparisonTest` 移入
   `tools/engine-probes/src/jvmMain`，作为 Skia 的 AWT 对照实现。删除
   `:platforms:jvm:shaping` 模块，把 `tiqian-jvm-shaping` 从 `build.gradle.kts` 的
   `publishedModules` 与 `release-manifest.json` 的 maven 发布单元删除。依据：
   `AwtTextShaper` 实现 engine 的 `TextShaper` 接口，AWT 路径没有生产前端，消费者只有探针与
   对照测试。
3. 探针集中到 `tools/engine-probes/src/jvmMain`，`runProbe` 是执行入口。
   `DashVerticalPositionProbe`、`FontProvidedMetricsProbe`、`SkiaHaltFeatureProbe` 与
   `EmphasisClearanceProbe` 移入该模块；`EmphasisClearanceProbe` 的包名从
   `org.tiqian.compose` 改为 `org.tiqian.layout`，因为该类不引用 Compose 类型。
   两个类保留在原模块并改名：`ComposeReflowBenchmarkProbe` 改名为
   `ComposeReflowBenchmarkTest`（`platforms/compose/compose/src/jvmTest`），
   `PartialRunDrawProbe` 改名为 `PartialRunDrawTest`
   （`platforms/android/shaping/src/androidTest`）。

## Consequences

- `platforms/` 只保留 `android`、`apple`、`web` 与 `compose` 四个宿主分组。
- `publishedModules` 从 8 项减为 7 项。本仓库发布 7 个平台坐标；`tiqian-engine` 仍由 boring
  的 kotlin-f32 publication 发布。
- `tools/engine-probes/src/jvmMain` 编译 14 个含 `@Test` 的类，`runProbe` 按类名执行其中
  一个。
- `ComposeReflowBenchmarkTest` 与 `PartialRunDrawTest` 不移动：前者使用
  `platforms/compose/compose/src/commonMain/kotlin/org/tiqian/compose/ComposeBackendCaches.kt`
  里的 internal 类，移出模块需要把这些类改成 public；后者使用 `android.graphics.Canvas`、
  `android.text.TextPaint` 与 `AndroidJUnit4`，只能在 Android instrumentation 环境执行。
- `AwtTextShaper` 的包名保持 `org.tiqian.shaping.jvm`。`SkiaTextShaper` 的 KDoc 引用
  `AwtSkiaShapingComparisonTest`，该类保持原名。
- ADR 0013、0015、0048、0056 保留当时的模块路径，不改写。

## Alternatives

- 保留 `:platforms:jvm:shaping` 并继续发布：该坐标没有生产消费者，发布流程会维护一个无人
  引用的坐标。
- 把 `AwtTextShaper` 放进 `:platforms:compose:skia-jvm` 的 `jvmTest`：
  `tools/engine-probes` 的 5 个探针依赖该类，跨模块引用测试编译产物需要额外的 Gradle 配置；
  把 5 个探针一起移入 Compose 的测试源集后，它们没有可执行的任务。
- 给三个测试源集增加发布任务：发布任务集由 `tools/release-gradle-tasks.sh` 固定为两个任务，
  增加测试任务会改变发布验证的内容，本轮不扩大该范围。
