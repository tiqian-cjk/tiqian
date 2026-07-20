# 提椠 ADR 索引

ADR 记录已经做出的架构与排版决定。它们按编号保留当时的 Context、Decision、Consequences
与 Alternatives；后续实现或修订通过 amendment 和新的 ADR 补充，不把历史背景改写成当前状态。

当前 pipeline 与模块边界见 [architecture.md](../architecture.md)，实施状态见
[roadmap.md](../roadmap.md)。阅读较早的 ADR 时，应同时查看文首 amendment、文末跨 ADR 指针和
本索引中的说明。除 ADR 0022 明确标为 Rejected 外，以下均为 Accepted。

## 核心模型

- [0001 核心 pipeline 与平台边界](0001-core-pipeline-and-platform-boundary.md)
- [0002 Script-aware 字体度量](0002-script-aware-font-metrics.md)
- [0003 推荐码点只改 display、不改 source](0003-prefer-clreq-recommended-codepoints.md)
- [0004 标点空间的加法 glue 模型](0004-punctuation-additive-glue-model.md)
- [0005 结构化 LayoutDecision 与 SpacingPlan](0005-structured-layout-decisions.md)
- [0006 标点悬挂为可选项](0006-hanging-punctuation-opt-in.md)
- [0007 字格优先、加法标点与可解释断行](0007-grid-first-explainable-cjk-typography.md)
- [0008 Shaping adapter contract](0008-shaping-adapter-contract.md)
- [0009 AutoSpacePolicy](0009-autospace-policy.md)
- [0010 LineEdgeGlueTrim](0010-line-edge-glue-trim.md)
- [0011 PunctuationGeometryLedger](0011-punctuation-geometry-ledger.md)
- [0012 CarryPrevious 溢出验证](0012-carry-previous-overflow-validation.md)

## 平台 shaping 与绘制

- [0013 JVM AWT shaping adapter](0013-jvm-awt-shaping-adapter.md)
- [0014 Ink-bounds 标点几何校准](0014-ink-bounds-calibrated-punctuation-geometry.md)
- [0015 Skiko shaping adapter 交叉验证](0015-skiko-shaping-adapter-cross-check.md)
- [0016 Android TextPaint adapter](0016-android-textpaint-adapter.md)
- [0017 Compose Desktop renderer](0017-compose-desktop-renderer.md)

## 行内与段落排版

- [0018 Inline decoration 与着重号](0018-inline-decoration-spans-emphasis-marks.md)
- [0019 Latin 分词与西文词距](0019-latin-word-segmentation.md)
- [0020 分层挤压与调整风格](0020-tiered-push-in-compression.md)
- [0021 段首缩进](0021-first-line-indent.md)
- [0022 ShrinkToFit 断行（Rejected）](0022-shrink-to-fit-line-breaking.md)
- [0023 双齐为基线](0023-justification-as-baseline.md)
- [0024 专名号与书名号甲式](0024-interlinear-lines.md)
- [0025 按行长自适应的禁则档与悬挂](0025-measure-adaptive-kinsoku-default.md)
- [0026 行尾禁则](0026-line-end-kinsoku.md)
- [0027 标点宽度风格](0027-punctuation-width-styles.md)
- [0028 行长字号整数倍量化](0028-integer-line-length-grid.md)
- [0029 西文音节连字](0029-western-hyphenation.md)
- [0030 富文本 per-span 样式](0030-rich-text-spans.md)
- [0031 行调整方向](0031-line-adjustment-direction.md)
- [0032 拼音 ruby](0032-ruby-annotations.md)
- [0033 注音 ruby](0033-bopomofo-annotations.md)
- [0034 `ic` 字身框单位](0034-ic-zishenkuang-unit.md)

## 前端与宿主接入

- [0035 Android Compose frontend 与共享 Demo](0035-android-compose-gallery.md)
- [0036 Compose TextStyle interop 与 capability report](0036-compose-text-interop.md)
- [0037 Source-faithful plain text 与 mandatory breaks](0037-source-faithful-plain-text.md)
- [0038 邻行均摊](0038-neighbor-amortized-adjustment.md)
- [0039 Web 渲染路径与真实站点接入](0039-web-rendering-path.md)
- [0040 构建期 Web 字体证据与最大版心快照](0040-build-time-web-font-snapshots.md)

## 早期状态说明

以下早期 ADR 的核心决定仍然有效，但其中“当前”“后续”等实施状态已经被后续工作推进：

- 0002 的字体声明度量与 OpenType BASE 后续由 0014、0033、0034 及平台 resolver 落地；
- 0004、0008、0011 中的 stub / placeholder ink 说明由 0013–0016 的真实 shaping 与
  0014 的 ink-bounds 几何取代；
- 0009 的 Insert 模式由 Slice 10 落地；
- 0021 中的 `firstLineIndentEm` / `blockIndentEm` 命名由 0034 改为 `Ic` 类型的
  `firstLineIndent` / `blockIndent`；
- 0017 的 Desktop-only 前端由 0035 扩展到 Android，并由 0039 增加 Web 前端。
- 0039 的客户端实时度量路径由 0040 增加构建期最大版心快照与服务器 shaping / metrics 回放；
  快照失配但证据仍有效时继续走回放，证据不可用时才保留原生正文或回到 0039 的具名降级路径。
