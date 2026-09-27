# S8+ 滚动卡顿调查（2026-08-15）

带日期的调查记录，非当前实现状态。目的：固定结论，避免在已排除的方向上重复调查。

## 背景

- 目标机：Galaxy S8+（`SM-G9550`，API 28 / Android 9，arm64-v8a，骁龙 835）。
- 场景：知乎++ 实际万字长文（`smpl` fixture，约 142k 字 / 205 块），Tiqian markdown 渲染器，连续滚动。
- 对照：同 App 的 legacy 渲染器（原生 Compose `Text` / `BasicText`，非 WebView）。

## 测量方法

- `OfflineArticleBenchmarkActivity`（zhplus `benchmark` build type，R8，离线 fixture，无网络）。
- `dumpsys gfxinfo <pkg> framestats` 逐帧分阶段（`measure_layout`、`draw_record`、`gpu_issue` …）。
- 主要指标：**Tiqian 减 Legacy 的 P90/P95 gap**。Legacy 不受本次改动影响，用它抵消未锁频 + 骁龙 835 发热带来的漂移。绝对 jank% 与 P99 抖动很大，不单独采信。
- 正确性：同一初始渲染的**逐像素对比**（裁掉状态栏/导航栏）；不使用 golden。

## 基线

Tiqian 比 legacy 卡约 1.4×；P50 约 10ms（没问题），问题全在尾部；**P90 gap ≈ +8ms**（Tiqian ~26ms vs legacy ~18ms），跨轮很稳。

## 直接原因（已测，非推测）

- **卡顿在 draw，不在 layout**：`measure_layout` 全程约 0.1ms。
- 探针实验（`debug.tiqian_probe`，已回退）三态对照：
  - 跳过画字形（resolveonly）→ P90 **26 → 16ms**，与 legacy 持平；
  - `resolveonly ≈ skipglyphs` → **per-cluster 解析成本 ≈ 0**（`toFontRole` 的 valueOf、`spans` 扫描、`AndroidClusterRun`/`TextStyle.copy` 分配合计约 50µs，可忽略）。
- 结论：那约 10ms 就是**画 positioned glyph 本身**（CPU 记录 + GPU 栅格化各占一半）。**API 31+ 有 `Canvas.drawGlyphs` 批量硬件路径，所以快；API 23–30 没有，只能逐 cluster `drawTextRun` / `drawPosText`，结构性更慢。** 且成本集中在**新块首次滚入**那一帧：新字形必须当场栅格化，任何缓存都救不了首次绘制。

## 试过的杠杆（都实测、都已回退）

1. **PrefetchDuringScroll**（放开 `DeferredMarkdownBlocks` 的 idle 预排、让它在滚动中也跑）：P90 无变化，因为 layout 不是瓶颈。
2. **`drawTextRun` 批量**（合并连续汉字为一次调用）：**破坏两端对齐**，因为 justification glue 落在 `Cluster.advance` 上，`drawTextRun` 的自然前进会把它抹掉，正文被压紧。回退。
3. **`drawPosText` 批量**（显式坐标，逐像素一致、保留对齐）：P90 无变化，成本不在调用数。
4. **`graphicsLayer`**（每个文本块的字形缓存成 RenderNode，逐像素一致）：**慢帧降至一半（59→29 / 120），`gpu_issue` 12→8ms**，但 P90 仅 26→24ms，**P99 反而恶化**（首次绘制要栅格化进 layer，比直接画更重）+ 内存代价。是"典型帧更顺、偶发尖峰更差"的权衡，没有带来净改善，丢弃。

## 明确不是原因的

layout、per-cluster 解析、draw 调用数、**代码块**（`DefaultMarkdownCodeBlock` 走原生 `BasicText` + `remember` 缓存的高亮 `AnnotatedString`，不经 Tiqian；测试 `tiqianMarkdownRendererRendersCodeBlocksWithoutLegacyFallback` 可证）。

## 唯一可能解决问题的方向（未做）

**预绘制**：把现有 idle/prefetch worker（`DeferredMarkdownBlocks`）从"预排 layout"扩到"预渲染进 layer/bitmap"，让新块首次滚入时只**合成**预渲染好的纹理，绕开关键帧上的栅格化。可与 `graphicsLayer` 组合。属大改动，且 CJK 转位图有质量/内存代价，payoff 需真机实测后再定。

## 本次保留的改动

- **benchmark 编译模式**：原先三场景全用 `CompilationMode.Full()`，对 JIT 与 baseline profile 是盲的（漏掉了实际安装态的回归）。改为 startup 用 `CompilationMode.None()`（全新安装最坏态）、scroll/recompose 用 `Partial(warmupIterations = 3)`（热 JIT 稳态）。
- `frontend/compose/src/androidMain/baselineProfiles/` 暂未提交：那是 **startup** 方向，与本次 scroll 的 draw 成本正交；且当前是手写通配、未接入、未验证，留待需要时用 Macrobenchmark 生成器在真机实采。
