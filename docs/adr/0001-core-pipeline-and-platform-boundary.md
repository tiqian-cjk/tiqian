# ADR 0001: 核心 pipeline 与平台边界

- Status: Accepted
- Date: 2026-06-06

## Context

提椠的真正价值是在 shaping 之后、绘制之前的这一层：字体 fallback、CJK 度量归一、标点 atom/glue、断行修复、justification、段落优化。如果这些决策被分散到 Compose / Android View / Skia 渲染层，会出现三个长期问题：

- 平台之间排版不一致（同一段中文在 Android View 和 Compose 上断行不同）。
- 任何排版 bug 必须在 N 个平台上重复修。
- 后续加竖排 / JLREQ 时找不到统一的注入点。

## Decision

固定一条单向 pipeline，所有排版决策都在 `core` ~ `layout` 之间完成：

```text
text + style + locale + profile
  -> font selection (font)
  -> shaping        (shaping/api, 平台 adapter 实现)
  -> CJK metric normalization (font)
  -> punctuation atom / glue  (layout)
  -> break candidates         (linebreak + clreq)
  -> line repair / optimization (layout)
  -> justification            (layout)
  -> LayoutResult             (core)
  -> renderer (frontend/compose / frontend/android-view)
```

平台前端模块 (`frontend/compose`, `frontend/android-view`) 只允许做：接收 constraints、调用 core layout、绘制 glyph runs、提供 hit-test、暴露调试 overlay。它们**不可以**决定 fallback 顺序、标点空间、避头尾、对齐分配、段落优化。

平台 shaping/font 能力通过 `shaping/api` 的接口注入，差异落到 capability report，不进入 core 规则。

## Consequences

- 任何「为了显示效果好」在渲染层挪 glyph 的改动都是技术债，应该在 review 时打回。
- 平台 adapter 实现可以缺失（第一阶段 stub 足够），不会卡住核心模型推进。
- core 模型可以独立测试，不需要起 Compose / Android。
- 加新平台（iOS、Skiko desktop）的成本主要是 adapter，不是重写排版。

## Alternatives considered

- **平台各自做排版（类似当前 Android StaticLayout / Skia Paragraph 的状态）。** 否决：与项目立项动机直接冲突，无法解决 CJK 默认排版问题。
- **完全自绘 shaping。** 否决：成本过高且没有差异化收益，平台 shaping 已经够用。

## Follow-up

- `shaping/android-adapter` / `shaping/skia` 在 Slice 6 (M5) 才真正出现。
- 竖排接入时复用同一 pipeline，writing mode 进入 profile，不应另起一条 pipeline。
