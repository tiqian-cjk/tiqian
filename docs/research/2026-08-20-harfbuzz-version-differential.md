# HarfBuzz 跨版本与纯 Rust 移植差分测试（2026-08-20）

为 ADR 0050 Slice B 选型提供的实证：`tiqian-precompute` 的 Rust 字体会话是否必须把
HarfBuzz 固定在 `harfbuzzjs` 1.4.0 内嵌的 14.2.1，以及 rustybuzz / harfrust 两个纯
Rust 移植能否替代。测试不依赖上游声明，直接差分真实输出。

## 方法

oracle 是 npm 生产路径本身：`harfbuzzjs` 1.4.0 wasm（内嵌 HB 14.2.1），
`frontend/web/npm/node_modules/harfbuzzjs`。对照五个引擎：

- HB 8.4.0（`harfbuzz-sys` 0.6.1 内嵌源码，C++ 编译）
- HB 11.2.0（`harfbuzz-sys` 0.7.0 内嵌源码，C++ 编译）
- HB 14.2.1（上游 src，C++ 编译，与 wasm 同版本）
- rustybuzz 0.20.1（纯 Rust 移植）
- harfrust 0.13.0（纯 Rust 移植，Google 资助的延续线；生产栈组合的 shaping 侧，
  见「harfrust + skrifa 组合」节）

每个引擎复刻 `precompute-fonts.js` `shapeRecord` 的调用序列：`setScale(upem, upem)`、
`addText`、`guessSegmentProperties` 后覆盖 direction=LTR、language=zh-cn、script，
feature 用 `tag=1` 形式全局启用。输出全部为 font units 的规范化 JSON：逐字形的
id / cluster / flags / xAdvance / xOffset / yOffset / extents、hExtents、upem、
正文全部码点的 nominalGlyph 覆盖。

语料与字体取自仓库真实资产：`layout/src/jvmTest/resources/golden/layout-dumps/` 全部
49 个 fixture，SourceHanSansSC-Regular / Bold（CFF OTF）、EBGaramond-Bold、
DelaGothicOne-Regular 三个 TTF。脚本 × feature 组合覆盖 `shapingPolicyForRole` 的全部
出口：`Hani`×∅、`Hani`×fwid、`Latn`×∅、`Latn`×(pwid,palt)。合计每引擎
4 字体 × 4 组合 × 49 文本 = 784 份对照。

cluster 有一个单位差需要换算：harfbuzzjs 经 `hb_buffer_add_utf16` 喂文本，cluster 是
UTF-16 code unit 偏移；C 与 Rust 侧是 UTF-8 byte 偏移。对照前按同一文本逐字符换算。
这也确认了生产行为：npm 路径的 cluster 语义是 UTF-16 偏移，与 JS 字符串一致。

## 结果

### C 版 HarfBuzz：8.4 → 14.2.1 零差异

三个 C++ 版本在全部 784 份对照上与 wasm oracle **逐字段一致**：glyph id、cluster、
UNSAFE_TO_BREAK flags、advance、offset、extents、hExtents、upem、nominalGlyph 覆盖
全部相同。npm 使用面（Blob/Face/Font、setScale、guess 后覆盖 segment properties、
fwid/pwid/palt feature、UNSAFE_TO_BREAK、glyphExtents、hExtents、nominalGlyph）
全部落在跨版本稳定的核心 API 上，6 个大版本区间内无行为变化。

结论：**shaping 输出层面不存在跨版本风险**。固定 14.2.1 的作用是稳定两处间接产物：
`precompute-fonts.js` 把 `hb.versionString()` 写进 snapshot evidence，跨版本会改变
evidence 标签（几何不变，字节比对不等）；以及下述 extents 语义。几何输出本身跨版本
无漂移。升级 HarfBuzz 版本后的复查入口是仓库内差分 harness（ADR 0050 的
`tiqian-precompute` cargo 集成测试），复查不依赖本篇的一次性对照脚手架；需要复现
本篇矩阵时，按「方法」节列出的版本来源、调用序列、语料与字段清单重建。

未覆盖面：静态字体（语料字体均无可变轴，`setVariations` wght clamp 路径未测）、
Zyyy script 覆盖、collection face（契约本就拒绝）。

### rustybuzz 0.20.1：shaping 完全一致，extents 有语义缺口

rustybuzz 在全部 784 份对照上，glyph id、cluster（换算 UTF-16 后）、unsafe-to-break
flags、advance、offset、upem、hExtents、nominalGlyph 覆盖与 oracle **完全一致**。
差异只剩 extents，来自取数库 ttf-parser 与 HB 的语义约定，shaping 本身没有差异：

1. **空字形 extents 语义**（515,472 处，四字体均匀分布）：HB 对空格等无轮廓字形返回
   `[0,0,0,0]` 空矩形，ttf-parser 返回 `None`。纯 Rust 会话需要一个命名策略把
   「无轮廓」输出成零矩形，才能维持 plan JSON 字节 parity。
2. **EBGaramond-Bold 的 ±1 x_bearing**（26,464 处，仅此字体）：ttf-parser 按轮廓点
   求包围盒，HB 对静态 TrueType 字形读 glyf 字形头盒，两者在该字体上差 1 个
   font unit（upem 2048，约 0.05% em）。生产栈的 extents 分派读字形头盒，不经过
   此差异（见下节）。

rustybuzz 不公开 `glyph_extents`（`pub(crate)`），hExtents 与 nominalGlyph 也需另配
ttf-parser；UNSAFE_TO_CONCAT 不暴露，但 HB 默认也不产出，flags 字段实测一致。

### 可变字体补充测试

加入 NotoSansSC[wght].ttf（google/fonts，glyf+gvar+HVAR+avar，fvar wght 100–900，
默认 100），在 wght 300 / 700 × 三组 script/feature（`Hani`×∅、`Hani`×fwid、
`Latn`×(pwid,palt)）× 49 文本 = 294 份对照上扩展矩阵。三个 C 版在扩展矩阵上仍然
逐字段零差异。生产栈组合在同一矩阵上的结果见「harfrust 0.13.0」节。

### harfrust + skrifa 组合（生产栈形态）

metrics 从 fontations 系列库取：hhea 经 `read-fonts` 直读，nominalGlyph 用
`skrifa` 的 Charmap；空轮廓字形按 HB 语义输出 `[0,0,0,0]`。extents 按字形来源
分派，对应 HB 的取值语义：静态 TrueType 字形读 glyf 表的字形头盒（`read-fonts`），
CFF 与带变体坐标的字形用 `skrifa` 的 ControlBoundsPen 画轮廓取包围盒
（`Size::unscaled()` 让坐标直接用 font units，粗细值先经 fvar 与 avar 换算成
轴上的标准位置）；harfrust 的 extents 接口对带变体坐标的字形返回无结果（上游
TODO 指向维护者在 harfbuzz/harfrust PR #52 里的说明）。变实例坐标下的包围盒与
HB 相同；ttf-parser 在同位置有 ±1 到 ±2 的取整差。

### harfrust 0.13.0（read-fonts 0.43）的结果

harfrust 0.13.0（2026-08-13 发布）的 read-fonts 依赖为 0.43。生产栈组合
（harfrust 0.13.0 + skrifa 0.46 + read-fonts 0.43，三者共用同一 read-fonts
版本）在全部 1078 份对照（784 静态 + 294 可变）上：

- 全部 1078 份文件与 oracle 逐字段一致：glyph id、cluster、flags、advance、
  offset、extents、hExtents、upem、nominalGlyph 覆盖零差异。

## 对决策的影响

- 选型为 `harfrust`（shaping）+ `skrifa` / `read-fonts`（metrics），采用版本
  harfrust 0.13.0、skrifa 0.46、read-fonts 0.43。WOFF2 解码用纯 Rust 的 `wuff`
  0.2（只开 brotli feature），整个构建不需要 C/C++ 工具链。选择依据：rustybuzz 的
  仓库于 2026-07-26 归档，README 指向 harfrust 作为继任；harfrust 在 HarfBuzz 官方
  组织与 Google fontations 生态内持续开发。`woff2` crate 0.3 自 2022-05 无维护，
  严格校验 header 的 `totalCompressedSize`，拒绝 `woff2-encoder` 生成且其自身可解
  的文件；`wuff` 解同一文件的输出与 JS 侧 wasm 解码器字节一致（sha256 相同）。
- 生产栈组合在 1078 份对照上与 oracle 全字段一致。extents 按字形来源分派
  （见「harfrust + skrifa 组合」节）是达成一致的必要条件。
- C 版差分结论继续有效：HB 8.4 到 14.2.1 跨版本零差异，shaping 无跨版本风险；
  若未来回到 C 路线，`harfbuzz-sys` bundled 直接可用。
- snapshot evidence 的 `harfbuzzVersion` 只约束同一 manifest 内条目一致
  （`SnapshotFontEvidenceVersionConflict`），不要求与 JS 侧数字相同。Rust 侧如实
  报告引擎标识与版本，同一 snapshot 不得混入两个引擎的证据，现有校验已经强制这一点。
