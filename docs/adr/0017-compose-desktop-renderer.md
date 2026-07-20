# ADR 0017: Compose Desktop 渲染前端

- Status: Accepted
- Date: 2026-06-10

> [!NOTE]
> 本 ADR 记录最初的 Desktop 前端。Compose 公共 API 后续由
> [ADR 0035](0035-android-compose-gallery.md) 扩展到 Android，并由
> [ADR 0036](0036-compose-text-interop.md) 收口为 `CjkText` interop；早期 public
> `CjkParagraph` 已删除。当前前端边界见 [architecture.md](../architecture.md)。

## Context

M1–M5 落地后引擎模型已真（三平台 shaping 互证、决策 golden、吞吐基线），但
唯一的渲染出口是 playground 的调试 PNG。`frontend/compose` 一直是空 contract
外壳。Slice 7 把 playground 验证过的 Skia 渲染路径变成可消费的前端。

## Decision

`frontend/compose` 接 Compose Multiplatform 1.11.1（Kotlin compose compiler
2.3.20），先做 **Desktop (jvm)** target：

- **`CjkParagraph` composable**：自定义 `Layout` 在 measure 阶段用注入的
  `ParagraphLayoutEngine`（默认 Skia shaper + lookahead breaker）排版，按
  `LayoutResult.size` 报告尺寸；draw 阶段经 `drawIntoCanvas` 拿到
  `org.jetbrains.skia.Canvas`，逐 cluster 画 language-tagged TextBlob——
  glyph 与 engine 度量同源（`LocaleTaggedShaping`，locl 破折号等直接正确）。
- **前端零排版决策**（[AGENTS.md](../../AGENTS.md) 中的项目约束）：composable 只调 engine、只画
  `LayoutResult`；fallback / glue / 避头尾 / justification 全部在上游。
  渲染遍历逻辑（autospace strip、行边 gap 抑制）与 playground skia raster
  同构。
- **共享件下沉到 `shaping/skia`**：language-tagged TextBlob 构建
  （`shapeTextBlob`）与系统字体探测（`SkiaSystemTypefaces`）从 playground
  提取为公共 API，playground 与 compose 渲染共用，消除三份重复。
- **验收 = 离屏渲染**：`ImageComposeScene` 把 `CjkParagraph` 渲染成 PNG
  （存 `build/reports/`）并断言有墨迹像素；`runComposeDemo` 提供窗口 demo。

### 暂不做（预留点）

- **Android composable**：渲染要走 `android.graphics.Canvas`+TextRunShaper，
  与 desktop 的 skia interop 不同源；等 Android 渲染需求明确再开 slice，
  contract（消费 `LayoutResult`）不变。
- **Density 映射**：当前引擎单位按 px 直出（desktop density 1 时即物理像素）。
  fontSize × density 的换算放 composable 入参层处理，后续接真实 DPI 时
  在 `TextStyle` 构造处乘 density，引擎不感知。
- **增量重排 / 文本编辑**：每次 measure 全量 layout，220 字 ~2ms
  （`LayoutBenchmarkProbe`），正文展示场景足够。

### Amendment (2026-06-12): 渲染契约补条——leading glue 消费要左移绘制原点

被消费的 **leading** glue 必须反映在绘制位置上：glyph blob 内仍带着字体
设计的前置空白（如全宽 `“` 的左半），而引擎已把这段空白从 cluster advance
里扣掉（行首削半、间隔号双侧挤压）。渲染器按
`x - geometryDecisions.leadingGlueConsumed` 落笔，否则字面会叠进下一个
cluster（首行 `“` 与汉字重叠的实际事故）。trailing 侧消费不需要偏移——
字面左锚。该规则同样适用于 playground 两个 raster；它是机械应用引擎已
dump 的几何决策，不构成前端排版决策。

同日第二条：**role 查询必须用包含匹配**。`LatinWordSegmentation`
（ADR 0019）把 font decision 的 range（` espresso`，含空格）切成多个
cluster（`espresso`），渲染器原来的 `range == cluster.range` 全等查询
落空，Latin 词静默退回 CJK 字体——引擎用 Latin 字体量的 advance 与
实际画出的 CJK-Latin 字形宽度不一致，差值在每个西文词右侧显形为幻影
空白（`espresso，` 间隙事故）。cluster range ⊆ decision range 才是
分词后的正确关系。

## Consequences

- 引擎第一次有了「真前端」：Compose 应用可直接 `CjkParagraph("…")`。
- 渲染正确性与 engine 度量绑定在同一 Skia 栈，playground 修过的渲染 bug
  （locl glyph、baseline）不会在前端复发。
- `frontend/compose` 从 commonMain 空壳变为 jvm-first；Android target 留待
  后续 slice。
