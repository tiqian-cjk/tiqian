# ADR 0002: Script-aware 字体度量与 CenteredCjkVisual

- Status: Accepted
- Date: 2026-06-06

## Context

直接用平台 raw font metrics (ascent / descent / top / bottom) 排中文段落，思源黑体等字体常见症状是：

- 汉字在 line box 中视觉偏下。
- line height 偏大（字体为兼容附加符号留了上方空间）。
- 中西混排 baseline 漂移。

raw metrics 本身没有错，只是它服务的目标（覆盖所有可能 glyph 的极端范围）和中文正文排版需要的目标（视觉居中、密度可控）不同。

## Decision

显式区分两层度量：

```text
RawFontMetrics       — 来自字体表 / 平台 API 的原始事实
LayoutFontMetrics    — 提椠用于排 line box 的度量
```

中文正文默认策略：

```text
CJK text / CJK punctuation -> BaselineClass.IdeographicCentered + MetricBox.IdeographicEmBox
Latin text                 -> BaselineClass.Roman              + MetricBox.RawFontBox
```

`FontMetricsPolicy` 提供 `Raw / IdeographicBox / GlyphBoundsSampled / ManualOverride`。`BaselinePolicy` 提供 `Alphabetic / Ideographic / CenteredCjkVisual`。中文正文默认 `CenteredCjkVisual + IdeographicBox`。

实现位于 `ScriptAwareFontMetricsNormalizer`，它的输入是 `FontMetricsNormalizationInput(request, rawMetrics)`，输出是 `LayoutFontMetrics`，并附带 `source` 与 `reason` 字段供 dump 解释。

## Consequences

- 所有 line box 必须从 `LayoutFontMetrics` 计算，不允许直接用 raw ascent/descent。
- dump 中每个 cluster 都能看到 `raw(...) -> layout(...) : reason`，layout 决策可追溯。
- 第一版 IdeographicEmBox 通过代表汉字采样估算（候选采样集：`一 中 国 口 日 言 語`），后续可被 OpenType BASE 表或字体特定 override 替换。
- 用户/字体级 override 通过 `FontMetricsPolicy.ManualOverride` 注入，不需要碰核心代码。

## Alternatives considered

- **只信任 raw metrics + 手动调 line height。** 否决：把决策推给调用者，违反「核心模型必须真」。
- **直接 hardcode 思源黑体的度量。** 否决：换字体就崩。
- **依赖平台高级 API (Apple typographer / Android FontMetricsInt)。** 否决：跨平台一致性破裂。

## Follow-up

- OpenType BASE 表读取作为 `FontMetricSource.OpenTypeBase` 后续补齐。
- variable font axis / hinting 对采样的影响需要在 ADR 之外有专门 fixture。
- 竖排时 baseline class 切换为 `IdeographicCentered` 的竖排变种，policy 名字保持稳定。

## Amendment (2026-06-16)：CenteredCjkVisual 合成框 → 字体声明的度量

原决策的 `CenteredCjkVisual + IdeographicEmBox` 在实现里退化成了**写死的对称方块**
（`ascent = descent = 0.5em`，`source = SynthesizedIdeographicBox`），既没做本 ADR
原计划的「代表汉字采样估算」，也没读字体。后果：

- 「基线」被钉在 em 正中，而 Skia/AWT 实际把字画在字体真基线上——引擎模型的基线
  与渲染基线错位 0.38em，汉字在行内偏上，着重号/示亡号框（已硬编码 `0.88/0.12`
  的真字面框）与 line box 互相矛盾。
- 字身框被当成正方形，而汉字字身框本不对称。

实测系统字体 Source Han Sans CN（`FontProvidedMetricsProbe`）确认字体**直接声明**了
干净的表意度量：`OS/2 sTypoAscender/Descender = 0.880 / −0.120`（合 1.000em，非对称），
`BASE` 表 `ideo` 基线 −0.120、字面框 `icfb/icft = −0.074 / 0.834`，而 hhea 是
1.448em 的「偏大」框。

**修订决策**：

```text
CJK text / CJK punctuation -> 用字体声明的表意框（首选 OS/2 sTypoAscender/Descender），
                              真基线（罗马基线），不再合成对称方块、不再把基线放 em 正中。
```

- `RawFontMetrics` 增 `typoAscent/typoDescent`——CJK **字面框**：per-edge **优先 BASE
  `ideo`(框底)/`idtp`(框顶),缺则回退 OS/2 sTypo,再缺回落 hhea**（amendment 2026-06-20,
  ADR 0033 账）。Source Han 上 BASE/sTypo 重合(0.88/0.12);此框同供行高 + 拼音 + 注音。
- `ScriptAwareFontMetricsNormalizer` 的 CJK 分支改为透传 typo 框，`baselineClass`
  从 `IdeographicCentered` 改为 `IdeographicLow`（表意基线在罗马基线下方），`source`
  反映来自字体表而非合成。
- 新增 `SkiaFontMetricsResolver`（读 OS/2 sTypo），Compose measurer 注入它；
  `StubFontMetricsResolver` 同步提供 typo 字段以保持 golden 走真模型。AWT/Android
  resolver 同构后补。
- **墨迹采样（`GlyphBoundsSampled`）降级为字体缺 OS/2/BASE 时的劣质字体兜底**，不再是
  主路径。
- `BaselinePolicy.CenteredCjkVisual` / `BaselineClass.IdeographicCentered` /
  `FontMetricSource.SynthesizedIdeographicBox` 三个枚举值**弃用**（保留以兼容旧 dump）。
- `BASE` 表 `icfb/icft` 字面框接入 resolver、替换示亡号/着重号里硬编码的 `0.88/0.12`
  常量、以及行距/着重号净空按真字面收紧，列为后续 slice。
