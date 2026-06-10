# ADR 0015: Skiko adapter 作为第二个真实 shaper 与 AWT 交叉验证

- Status: Accepted
- Date: 2026-06-10

## Context

ADR 0013 用 `AwtTextShaper` 打通了真实 advance / ink bounds，但单一引擎的测量
无法区分「字体事实」和「引擎怪癖」：AWT 的 scaler、fractional metrics、bounds
取整都可能混进 punctuation atom 的输入。Slice 6 的目标之一（roadmap「Android /
Skia adapter 对照」）就是引入第二个独立实现交叉验证。

Skia（经 Skiko binding）是成本最低的第二引擎：纯 JVM 依赖即可运行、与未来
Compose / Android 渲染栈同源、且暴露 HarfBuzz 级别的 shaping 能力，是后续接
OpenType `halt` / `chws`（ADR 0014 follow-up）的自然载体。

## Decision

新增 `tiqian-shaping-skia`，提供 `SkiaTextShaper`：

- 依赖 `org.jetbrains.skiko:skiko-awt:0.148.1`（测试与 playground 另挂本机
  `skiko-awt-runtime-macos-arm64`；其它宿主退回 `TIQIAN_PLAYGROUND_SHAPER=jvm-awt`）。
- 用 `TextLine.make(displayText, font)` 测量：cluster advance = `line.width`，
  per-glyph advance 由相邻 glyph position 差分得出。
- glyph ink bounds 来自 `Font.getBounds(glyphs)`，本身就是 glyph-local
  （origin 在 pen position，baseline 上方为负 top），与 `AwtTextShaper` 减去
  originX 之后的约定一致；空 bounds（空格等）转为 null 并计入
  `ShapingDecisionInfo.glyphsWithoutInkBounds`（`MissingInkBoundsFallback`）。
- `SystemSkiaFontResolver` 与 `SystemAwtFontResolver` 使用同一份 CJK / Latin
  候选列表（`SystemSkiaFontProbe`），保证两引擎在同一台机器上测同一物理字体。
- 与 ADR 0013 相同的边界：adapter 不做 fallback、不做 CLREQ 替换、不做任何
  排版决策。

### 交叉验证 golden

`AwtSkiaShapingComparisonTest` 对全部 CLREQ 标点逐字符对照（16px）：

- advance 差 ≤ 0.5px（实测 Source Han Sans CN 下最大 0.45px，差异来自
  Skia 整数化 advance vs AWT fractional metrics）；
- ink 有无必须一致；
- Opening / Closing / PauseOrStop 的 ink 中心必须落在同一半侧——这是
  ADR 0014 glue 方向消费的输入。居中类（连接号、破折号、间隔号）ink 中心
  位于 advance/2 附近，亚像素舍入会任意翻面，不参与 side 断言。

实测结论（Source Han Sans CN）：Opening ink 中心 ≈ 12–14px（右半），
Closing / PauseOrStop ≈ 3–4px（左半），对称类 = 8px——两个独立引擎一致
复现了 ADR 0014 的 profile 模型。

### Amendment (2026-06-10): LocaleTaggedShaping

`TextLine.make` 不带语言参数，Pan-CJK 字体（Source Han Sans）默认给出
**西文形态**的 `—` / `⸺`：墨迹中心 -4.5（= 拉丁连字符高度），advance 14.3 /
26.8。字体里有专门的中文变体（OpenType `locl`，zh-Hans 下 `—` glyph 466→467、
`⸺` 1099→30587），位置在 CJK 视觉中心（-6.0，与「一」墨迹带一致）、宽度为
规范的 1em / 2em。

`SkiaTextShaper` 因此改走完整 SkShaper API（font/bidi/script/language run
iterator），语言标签取自 `TextStyle.locale`（默认 `zh-Hans`），记入
`ShapingDecisionInfo.reason` 的 `lang=` 段。命名启发式：`LocaleTaggedShaping`。

AWT 没有等价能力，`—` / `⸺` 成为**已记录的跨引擎分歧**：
`AwtSkiaShapingComparisonTest` 对这两个字符不再断言 advance 相等，改为断言
Skia 侧拿到整 em 宽的 locl 形态。playground 的 AWT 光栅化路径仍画西文形——
Skia 光栅化（或渲染层垂直校正）留作后续。

## Consequences

- punctuation atom 的 shaped 输入从「AWT 单方说法」升级为「双引擎互证」；
  advance/ink 出现 >0.5px 分歧时 golden 测试直接点名字符。
- playground 支持 `TIQIAN_PLAYGROUND_SHAPER=skia` 渲染对照。
- `halt` / `chws` 接入可以从 Skiko 路径开始（HarfBuzz 特性可用），AWT 路径
  保留为对照。
- Android adapter（`tiqian-shaping-android`）仍未接：Skiko 不是 Android 上的
  TextPaint，平台真值还需要单独 adapter；但 contract 与对照方法可直接复用。

## Alternatives considered

- **直接接 Android TextPaint。** 否决（当前轮次）：需要 Android instrumentation
  环境，反馈环路远慢于纯 JVM 的 Skiko。
- **JNI 直挂 HarfBuzz。** 否决：维护成本高，Skiko 已捆绑可用的 shaping 栈。
