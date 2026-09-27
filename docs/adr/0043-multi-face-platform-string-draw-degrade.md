# ADR 0043: 多 face 段降级为平台字符串绘制

- Status: Accepted
- Date: 2026-08-06
- Refines: [ADR 0016](0016-android-textpaint-adapter.md)（API 31+ 平台 shaping oracle 与 native 回放）

## Context

ADR 0016 的 API 31+ 平台默认路径靠 `AndroidPlatformFontOracle` 让平台 shape 当前段文本、读回
每个 glyph 落在哪个物理 `Font`，再由 native 后端用**同一份字节**重放 outline。这条路径隐含一个
不变量：**一个 shaping 段只落在单一物理 face 上**，oracle 用 `check(instances.size == 1)` 强制它。

该不变量对 oracle 早期的单码点探针（`中`/`A`/`。`）以及按脚本切好的 CJK / Latin 正文成立，
但对实际 UGC 不成立。`com.github.zly2006.zhplus.lite`（知乎++）在正文里出现泰文 `กิ`（Thai 基字 +
组合元音）时，平台按自身规则把这段拆到 `NotoSansThai` 与 `NotoSansDevanagari` 两个 face，`check` 抛出
`IllegalStateException: PlatformSelectionSpansMultipleFaces` 未被捕获，Compose measure 线程因此崩溃。

这是一整类问题；泰文只是其中一例。`clusterRoleRanges` 的 `GraphemeExtendStaysWithBaseCluster` 会**无条件**
把组合附标并入基字所在段（附标单独 shape 会得到会被 web 校验误判的零 advance），因此段可以是多码点、
甚至跨脚本的 grapheme。任何被平台拆到 ≥2 face 的段都会触发：

- **中文正文**：汉字逐字分段、单字永远单 face，但**基字 + 当前中文 face 不覆盖的组合附标**会拆 face；
- **Latin**：按词合并的段里混入主字体不含、fallback 才有的罕见拉丁扩展字；
- **Unknown**：泰文、阿拉伯文、天城文等非 CJK 脚本段。

「挑一个 face 重放整段」不是解：被选中 face 不覆盖触发拆分的那个字符，HarfBuzz 会给 `.notdef`，
把崩溃换成正好落在触发字符上的 tofu；方案内部自洽，但渲染结果错误。

## Decision

`PlatformMultiFaceStringDrawDegrade`：oracle 检测到多 face 时不再抛异常，改为**降级到平台字符串绘制**。

- **oracle**（`AndroidPlatformFontOracle.select`）：删除 `check(instances.size == 1)`，保留基字（首个）
  instance 供度量，记 `spansMultipleFaces` 标志，并用 `Paint.getRunAdvance` 量出平台实测 run advance。
- **catalog**（`ResolvedNativeFontFace`）：新增 `replayable` / `degradedRunAdvance`。多 face 段以
  `replayable = false` 返回基字 face（line height 仍取该 face 的实际 metrics）；此时「主 face 不覆盖
  整段」是有意的降级，绕过 `coversSelectionText → null` 的拒绝（该拒绝只在 `replayable` 时生效）。
- **native 后端**（`AndroidNativeTextShaper`）：`!replayable` 时产出一个**不可回放**的结果：单个
  `renderFontKey = null` 的 glyph，携带平台实测 advance，具名 decision
  `reason = PlatformMultiFaceStringDrawDegrade`、`capabilityIssue =`
  [`PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE`]。
- **renderer**：无需改动。`AndroidLayoutRenderer` 对 `renderFontKey = null` 的 glyph 本就无法 outline
  回放，落到既有的 `drawContextShapedText` → `Canvas.drawTextRun` 路径，由产生 advance 的**同一个平台
  文本栈**绘制，测绘天然同源。

`PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE` 是 `shaping/api` 的跨模块 capability 常量，与
`UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE` 并列。

这是对 ADR 0016「一段一 face、一律 outline 回放」模型的有意分层：**能干净观察（单字、单脚本正文）
就回放；平台按自身规则拆 face（组合附标、非 CJK 脚本、跨 face 的拉丁词）就复用平台绘制。** 它把 0016 的指导原则
「尽量复用平台已有能力」贯彻到无法逐字观察的边界上；在这个边界上也不放弃。

## Consequences

- **永不因多 face 崩溃。** 触发过崩溃的整类输入（泰文/阿拉伯文/天城文、Han + 未覆盖附标、跨 face 拉丁词）
  现在渲染正确或具名降级。
- **中文正文主体零影响。** 汉字逐字分段、单 face，继续走同字节 outline 回放。中文只有在
  **设备实际选中的 CJK face 不覆盖某组合附标**时才降级。
- **代价（诚实记录）**：多 face 段丢逐字墨迹（skip-ink、标点 `halt` 削边精修），换「永不崩 + 平台正确绘制」。
  advance 取平台 `getRunAdvance`；line height 取基字 face metrics。
- **bundled-catalog 路径不受影响。** 受控字节路径不经 oracle：其缺字仍由 HarfBuzz 报 `missingGlyphs`
  并触发 substitution rollback，与多 face 崩溃无关。
- oracle 单码点探针与既有 API 31 对照测试行为不变（单 face → `instances.first()` 等价于旧的 `single()`）。

## Alternatives considered

- **挑主 face 回放整段。** 否决：被选中 face 不覆盖触发字符 → 该字符显示为 tofu。自洽但渲染错误。
- **按 face 把段切成子 run，各自回放（完整解）。** 暂缓：需要把「一段 N face」贯穿 `ShapingResult` /
  `GlyphRun` / replay index 与 halt 测量，多个平台都要随之修改。降级路径先消除崩溃、保正确；子 run 回放
  作为未来在这类段上恢复逐字墨迹的独立 Slice。
- **保留 `check`。** 否决：实际 UGC 稳定复现崩溃。

## Verification

- 复现测试 `AndroidNativeFontBackendTest.multiFaceSegmentsDegradeToPlatformStringDrawInsteadOfCrashing`：
  仅在设备确实拆 face 时断言：非回放、源文本保真、advance > 0、具名 capability。
- 真机 Pixel 9 Pro XL（komodo，与崩溃日志同机，SDK 37）`connectedDebugAndroidTest` 全 15 项通过；
  日志 `multiFaceCasesExercised=1`：触发崩溃的 `กิ` 命中降级路径、断言全过、不再抛异常。
- `LayoutDumpGoldenTest` 不变（golden 走 stub，本决策为 Android 运行时专属 + 一个 additive 常量）。
