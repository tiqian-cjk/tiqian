# ADR 0057: 垂直方向退出缓存与装饰层 em 化

- Status: Proposed
- Date: 2026-08-22
- Relates: [ADR 0054](0054-measure-quantization-and-band-table.md)（格数区间表与
  身份收敛）、[ADR 0053](0053-web-prose-host-consolidation.md)（五表规格）、
  [ADR 0018](0018-inline-decoration-spans-emphasis-marks.md)（着重号）、
  [ADR 0024](0024-interlinear-lines.md)（行间线）、
  [ADR 0032](0032-ruby-annotations.md)（ruby）、
  [ADR 0044](0044-source-offset-glyph-geometry.md)（选区恢复）

## Context

### 垂直方向在缓存与身份里的现状

typography 记录含 lineHeightPx，行盒 y 值随行几何存进快照条目；行高因此参与缓存
身份与失效 digest，宿主改行高即换 context，整份缓存作废（ADR 0054 Context「宿主
配置与缓存身份的现状」）。

### 垂直方向的消费者

断行只消费水平方向：advance 累计、避头尾、悬挂阈值、压缩量全是宽度方向判定，行高
不改变任何一行装哪些字。首屏也不消费垂直方向：tiqian 的 DOM 行是内联流，纵向堆叠由
浏览器按 CSS line-height 完成，引擎不逐行写入。垂直方向的消费者全部懒执行，且行内
overlay 稀疏（一屏少量着重号一类）：

- overlay（着重号、行间线、ruby）：挂载时定位。公式
  `baseline_y(k) = k × lineHeight + halfLeading + ascent`，其中
  `halfLeading = (lineHeight − (ascent + descent)) / 2`（15.5px 字、ascent 与
  descent 合计约 18.6px、行高 30px 时 halfLeading 为 5.7px）。偏移量相对字体
  度量，baseline 的位置由行高给出；lineHeight 读 computed，ascent 在宽度无关层。
- 几何反查（点 → 字、source 范围 → 矩形）：事件驱动，点击或画高亮那一刻按同一
  公式算出 y，再在行内按 x 定位。
- 选区恢复（ADR 0044）：source 偏移到新 DOM 文本节点的映射（节点加字符偏移，
  重设 Range），不消费 y。

### 装饰层的绘制现状

现状（全部 px，锚点坐标同时把 fontSize 与 lineHeight 固定为常量）：

- 着重号与行间线共用按段落分组的 SVG 覆盖层：容器 `[data-tq-rendered]` 为
  `position: relative`（styles.css:26），`svg[data-tq-geometry]` 以
  `position: absolute; left: 0; top: 0` 铺在其上，宽高经
  `--tq-overlay-width/height` 给出（SharedDecorationOverlayCss，
  styles.css:45-57）；着重号是 `<circle cx cy r>`，专名号是 `<line>`，书名号
  甲式是波浪 `<path>`，坐标取引擎 `decorationDecisions` 与
  `decorationSegments` 的 px 值（DomParagraphRendererOverlays.kt:285-330、
  :223-280）。不走 CSS `text-emphasis`：原生着重号自持定位，无法使用引擎的
  装饰几何。不用 CSS 波浪下划线：波浪按 inline span 逐段重起，表示不了跨
  cluster 的连续书名号。
- ruby 是可选中 span（ADR 0032 `InlineSelectableRuby`），DOM 位置在 base
  最后一个 cluster 之后（复制带注文的底字时注文跟随，复制文本为「（拼音）」），
  样式 `position: absolute; left: centerX; top: baselineY − lineTop − ascent;
  transform: translateX(-50%)` 移出行内流（DomParagraphRendererOverlays.kt:181-215）。
- 正文留在浏览器内联流（保选区复制），`DomLineBaselineAlignment` 把内联
  baseline 挪到引擎行 baseline：`cssBaselineOffset = leading/2 + ascent`，
  ascent 与 descent 用 canvas measureText 的 fontBoundingBox 实测
  （DomParagraphRendererOverlays.kt:168-179）。

以上类名与行号按当前 Kotlin 实现记录；0053 的 TS 宿主化删除该层后（B8.3c，
2026-08-23），对应逻辑位于 npm/core/sampler/snapshot/prepared-dom-evidence.js
（appendEvidenceOverlays 与 wavyLinePath），锚点语义不变。

每个装饰锚点分解为三段：行 k 的 baseline（行高域）、行内 x（横向布局域）、
baseline 以下偏移（字体度量域）。第三段在引擎内部本来就是 em 量，出口才乘
字号：点径 = clusterEm × 0.19（AnnotationGeometryStage.kt:318），点 y 偏移 =
faceDescent + clusterEm × emphasisDotGapEm + 点径/2（:330-332），行间线粗 =
fontSize × LINE_THICKNESS_EM（DomParagraphRendererOverlays.kt:243），ruby
ascent 回退 = fontSize × RUBY_ASCENT_RATIO（:201）。随行高变化的只有第一段；
垂直方向退出后装饰层几乎零成本跟过去。

## Decision

### 实施时机：本轮不调整

本文件不随 ADR 0054 的重构批次实施：垂直方向与装饰层维持现状在客户端运行，lineHeight
留在 typography 身份与失效 digest，条目含 y，装饰按现行 px 覆盖层绘制。理由：
横向路径把切换格数区间的成本从引擎重算降为查表与补丁，性能余量随之扩大；装饰与几何反查是
稀有用例，现状的运行时定位与 px 覆盖层在余量内不构成排版负担。实施时机由
roadmap 排定，实施前本文件作为目标形态的参考。

### `VerticalAxisExitsCache`：垂直方向退出条目与身份

条目只存水平方向的值（断点、行内容宽、空隙数、拉伸增量、advance 与压缩量引用），
y 不入条目；
ADR 0054 格数区间表每条带的条目的「行几何值」随本决定改为水平方向几何。纵向按
运行时公式计算，两个输入（computed line-height、字体度量）都读活环境；该公式即
CSS 行盒的堆叠规则，结果与浏览器堆叠同源，不构成第二份真值。行高在段内不均匀、
或行盒被 in-flow 内容撑高时（行内图片一类；ruby 现按 absolute 移出行内流，
不撑高行盒，折回行内的变体才属此类），增设例外列，出现该行才写。引擎内部
照旧计算 y（LayoutResult 完整性与 dump 可解释性不动）；改变的是缓存存什么、身份
认什么。

lineHeight 退出 typography 身份与失效 digest，修订 ADR 0053 五表规格中按段落粒度取值的标量
清单（lineHeight 不再入表）。行高变回普通 CSS 属性：宿主改行高只触发浏览器重排
重画，横向条目与身份判定不受影响，不存在 invalidate。预先计算阶段引擎调用的
lineHeight 取样式继承链上解析完成的值（见 ADR 0054 的 `TypographyConfigFromCss`），只进 dump。

直接后果：sveltekit 站点的 p（30px）与 li（28px）字号相同、行高不同，合并为一个
context；脚注（13px）因字号仍在身份而独立，其合并待比例域（ADR 0054 的
`FontSizeRatioDomainSpike`）。本决定不动引擎算术，独立可回退。

### 装饰层目标形态

- 装饰记录携带 `(行 k, 行内 x, baseline 偏移 em)`，点径与线粗以 em 携带；挂载
  时 `cy = baseline_y(k) + 偏移em × fontSize`。水平方向 x 的表示跟随水平方向决定
  （px 条目或比例域条目），不在本决定内。
- 行内锚定变体：装饰挂到每行 `tq-line` 标记上做行内相对定位，纵向位置由浏览器
  行堆叠给出，`k × lineHeight` 不需要计算，剩余输入只有 baselineOffset
  （halfLeading + ascent），即 `cssBaselineOffset` 现算的量。
- SVG 可整体 em 化：svg 元素的 width/height 用 em，viewBox 用等值的无单位
  数值（1 用户单位 = 1 em），浏览器缩放连带 stroke-width（线粗是 em 量，
  缩放性质相合）。纵向随字号均匀缩放的前提是宿主行高为 em 写法
  （`line-height: 1.94` 一类，lineHeightEm 固定）；绝对 px 行高（sveltekit 站点的
  30px）下 lineHeightEm 随字号变化，垂直方向仍走公式。该约束即「行高绝对值不是
  字号比例量」。
- 绘制元素按装饰形状分派：离散、矩形、圆形改用 CSS em 盒，着重号点是
  `width/height` 为点径 em、`border-radius: 50%` 的 span，专名号线是高为线粗
  em 的色块 span，left/top 用 em，浏览器在样式计算内乘，不维护 viewBox；点径
  的 final paint geometry 语义从 px 终值改为 em 终值（LayoutModel.kt:512 的
  注释随之修订），乘法移交浏览器样式计算。引擎拥有连续曲线几何的保留 SVG
  路径，当前的成员只有书名号甲式波浪。CSS 侧替代不了波浪：
  `text-decoration: wavy` 按 inline box 重起且波长不可设，渐变拼不出引擎的
  抛物线与端点裁剪。
- 波浪走「预先计算段界、挂载时生成路径」：预先计算阶段只存段界（行 k 与 left/right），
  路径字符串挂载时按实际 fontSize 构造（`wavyLinePath` 现即渲染期构造，
  DomParagraphRendererOverlays.kt:395-409）。生成时拿得到实际字号，半波下限
  `coerceAtLeast(1f)` 与端点 epsilon（WAVY_ENDPOINT_EPSILON_PX）两处 px 语义
  按 px 用即可；它们只在把 em 路径烘进缓存时才破坏字号不变性，该变体不采用。
  单个段落 SVG 的纵高由运行时公式折算。书名号甲式在现代横排正文出现频次低，
  挂载时生成的成本按稀有装饰接受。
- 波形做 SVG data-URI 当 background-image 与参数化波形格式（把引擎输出改为
  周期 em、振幅 em 加截断语义）都不做。data-URI 的问题：`background-size` 用
  em 时缩放连同笔画成立，但末半波只能被元素边界截断在任意相位，重现不了引擎
  把末半波压缩到落在段尾的几何；data-URI 不继承 currentColor，需按色生成
  URI 或改用 mask-image 加 background-color；每段一个 span，节点数多于单个段落
  SVG。单位问题由 em 坐标系解决，元素 SVG 与 CSS 盒在此等价，两条路都不
  产生单位收益。
- 示亡号：引擎已有逐行矩形几何（AnnotationGeometryStage.kt:345 起），web 未
  绘制；框可用 CSS border 盒，虚线节律归浏览器还是归引擎待定，归引擎则入
  路径类。

## Consequences

- 本轮（ADR 0054 批次）垂直方向与装饰层维持现状运行，实施时机由 roadmap 排定。
- lineHeight 成为普通 CSS 属性：宿主改行高只触发浏览器重排重画，无缓存失效；
  sveltekit 站点的 p 与 li 合并为一个 context；条目存量减少 y 列，overlay 与几何
  反查的 y 从运行时公式取得。
- 与 ADR 0054 的衔接：实施时其格数区间表条目的「行几何值」改为水平方向几何，
  身份收敛表的行高行随之生效，`FontSizeRatioDomainSpike` 的垂直方向阻碍项解除。
- 实施时修订 ADR 0053 五表规格中按段落粒度取值的标量清单：lineHeight 不再入表，预先计算阶段
  引擎调用的 lineHeight 取样式继承链上解析完成的值，只进 dump；实施前 lineHeight 维持入表。

## Verification

1. `VerticalAxisExitsCache` 实施：同段落同字号同行高下，运行时公式 y 与引擎 y
   输出逐行等值（golden 对比）；装饰锚按三段分解重算后，着重号、行间线、ruby
   的位置与引擎 px 直出逐点等值（golden 对比）；lineHeight 变更后 DataView
   不换新、条目仍命中有断言；overlay 与几何反查两条路径的测试改走运行时公式；
   选区恢复回归测试确认不受本决定影响。
