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
