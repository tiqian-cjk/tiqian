# 51. API<31 自然簇串合并绘制（NaturalRunCoalescedDraw）

日期：2026-08-17
状态：已接受

## 背景

API 31+ 走 `Canvas.drawGlyphs` 批量快路径（ADR 0047 的 `AndroidPlatformGlyphBatch`）。
API 23–30 没有定位字形批量 API，只能逐 cluster `drawTextRun`，导致块首次进入
组合时的 display list 录制成本与 cluster 数成正比。锁频 Pixel 2 XL 实测：重引用
块的单次入场录制 16–80ms，是滚动掉帧尾巴的全部残余（滚动期排版成本已由
预排清零，见 tiqian-markdown 的 `TableSubtreePrelayout` 等）。

## 决策

在 `AndroidParagraphDrawCache` 内新增一次性的**绘制计划**（per geometry，随
`invalidateGeometry` 失效）：把一行内**连续、同 paint 配置、非标点角色**且
**位置为自然 advance** 的 cluster 串合并为单条 `drawTextRun` 命令。

- **自然位置判定（测绘同源验证）**：候选串拼接文本用绘制 paint 做一次
  `getRunAdvance`，其宽度与「引擎给出的串首→串尾位置差 + 末簇 advance」在
  `NATURAL_RUN_EPSILON_PX`（0.1px/簇，累计上限 0.5px）内一致才允许合并；
  否则整串回退逐 cluster。这吸收了跨簇 kerning/shaping 差异的全部风险——
  平台若会画出与引擎位置不同的结果，验证必然失败。
- **排除项**：`FontRole.CjkPunctuation`（挤压调整的落点，且需上下文 GSUB
  裁剪绘制）；display 替换簇（`displayText` 与 source 不同）；italic；含
  fallback face 混排的簇。这些保持既有逐 cluster 路径。
- 两端对齐行照常参与：CLREQ 挤压优先落在标点 glue，标点之间的汉字串保持
  自然 advance，验证会自动放行这些子串、拒绝被字距调整波及的子串。
- 验证与分组只在绘制计划构建时执行一次（每 geometry 一次），录制回放走
  预构建命令表，均摊后录制成本随命令数（而非簇数）线性。

## 后果

- 行为不变性由测绘同源验证保证：任何合并绘制在数学上与逐簇绘制同位；
  设备端以逐像素截图对比作为回归证据。
- API 31+ 路径与非 Android 后端不受影响。
- 命令表使 drawCache 内存增加 O(命令数)；geometry 失效时随缓存重建。
