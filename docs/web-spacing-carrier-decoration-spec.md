# Web 间距元素保留宿主下划线的修改规格

本文规定 Web 前端把塑造段末尾的正间距改写为行内文字间距元素的方法，使宿主 `<u>`、`<a>` 等元素的 CSS 下划线跨过两端对齐拉宽的间距连续绘制。本文记录已在分支 `web-spacing-carrier-inline` 实现的设计，[ADR 0039](adr/0039-web-rendering-path.md) 的 2026-11-26 修订段落引用本文。

## 现状：正间距由 `inline-block` 元素承载，浏览器不在其下方绘制下划线

`PreparedDom.renderRun`（`platforms/web/shared/src/org/tiqian/shared/prepared_dom/PreparedDom.hx`）处理 `trailing-letter` 类间距时，在塑造段末尾插入 `[data-tq-spacing-carrier]` 元素。修改前，该元素的样式为 `display:inline-block`、`inline-size:<间距>`、`height:0`、`overflow:hidden`，内容为一个 U+00A0。Rust 预计算使用由同一份 Haxe 共享层生成的 Rust 代码，写出相同的结构。

CSS 规定祖先元素的文字装饰线不传播到原子行内元素（atomic inline，即 `inline-block` 等作为整体参与行内排布的元素），浏览器因此不在该元素下方绘制宿主下划线。两端对齐拉宽西文词间距时，断口宽度等于间距宽度，肉眼可见。

2026-11-24 的提交 9689079a7 与 87c726f1f 删除了用 `letter-spacing` 写出正间距的分支，原因是 Firefox 的对称字距模型把字距平分到字形两侧，字形会偏离引擎给出的 `drawX`。本规格不使用 `letter-spacing`，与这两个提交的决定一致。

## 实测依据：继承字号的行内间距元素在三个引擎上宽度精确且下划线连续

实验页面为临时构造，每行结构为 `<u>前文<span>U+00A0</span>后文</u>`。间距元素设置 `display:inline`、`white-space:pre`、`letter-spacing:0`、`word-spacing:<间距 − U+00A0 前进量>`，字号继承正文。页面用 `Range.getBoundingClientRect` 读取浏览器自身的 U+00A0 宽度，代替引擎给出的前进量，然后检查间距元素宽度并要求它等于目标间距。

| 用例 | Chrome 158（设备像素比 1） | Firefox 162（`layout.css.letter-spacing.model=2`） | WebKit（与 Safari 27.3 同版本） |
|---|---|---|---|
| 西文 32px，间距 40px | 误差 0 | 误差 0 | 误差 0 |
| 中文 32px，间距 3.25px | 误差 0 | 误差 0 | 误差 0 |
| 衬线体链接 30px，间距 17.3px | +0.0125px | 误差 0 | 误差 0 |
| 宿主设置 `letter-spacing:2px` | 误差 0 | 误差 0 | 误差 0 |
| 红色波浪下划线 | 误差 0 | 误差 0 | 误差 0 |
| 15px 正文，间距 12px | 误差 0 | 误差 0 | 误差 0 |

三个引擎在所有用例中都跨过间距绘制了下划线，并保留宿主声明的颜色与线型。Chrome 的 0.0125px 误差来自 Chrome 以 1/64px 为单位排布文字，现有字形绘制受同一约束。

同一批实验排除了以下写法：

- 字号缩小的间距元素：Chrome 只在文字至少占 0.5 个设备像素时绘制祖先装饰线，在设备像素比为 1 时，字号须达到 0.5px，每个间距因此多出约 0.17px。浏览器的最小字号设置还会把间距元素放大到最小字号，在最小字号 12px 时每个间距多出约 3px。
- `word-spacing: calc(<间距> - 100%)`：三个引擎都把其中的百分比按字号解析，没有按空格前进量解析，并且把小于 0 的结果截为 0。
- 零宽字符加 `letter-spacing`、行内元素加 `padding-right` 或 `margin-right`：浏览器不对这两类前进量绘制装饰线。

## U+00A0 前进量由引擎通过同一塑造器给出

间距元素继承所在塑造段的字体设置，浏览器按 CSS 字体栈为 U+00A0 选择字面。不同字面的 U+00A0 前进量不同：在同一个 `sans-serif` 下，Chrome 测得 10.66px，Firefox 与 WebKit 测得 8.88px。前进量因此必须与浏览器绘制间距元素时选中的字面一致。

引擎的塑造接口 `TextShaper.shape(ShapingInput)` 满足这个要求。浏览器运行时的 canvas 塑造后端（`canvas-shaping.ts`）按 `WebFontFamilies.fallbackStacks` 生成的字体栈测量；构建期的 Rust 编排用站点发布的字体建立 HarfBuzz 会话。用某个字体段的 `FontDecision` 与 `TextStyle` 塑造文本 U+00A0，得到的前进量与该段字形前进量来自同一来源。U+00A0 的塑造结果同时进入构建期的塑造证据，浏览器在快照未命中时按同一证据回放。

仓库已有同类先例：`ParagraphShapingStage.hx` 用所在字体段的 `decision` 单独塑造 `"-"`，结果写入 `line.hyphenAdvance`。

## 数据从引擎流向 DOM 的顺序

1. 引擎构造参数 `measureSpacingCarrierAdvance` 为真时（只有 Web 共享层的 `PreparedParagraphLayout` 与 Rust 预计算的 `engine_bridge.rs` 传入真值，其他平台默认不测量），`WidthIndependentAnnotationCache` 完成整段的宽度无关塑造（`baseShapingStage`）后，调用 `SpacingCarrierAdvance.measure`。该函数遍历 `baseShapingStage.segmentShapingCache` 中的每个字体段，在 `fontDecisionByRange` 中查找覆盖该字体段的字体决策。`fontDecisionByRange` 的键是字体角色相同的连续簇范围，一整段西文只登记一个键，所以查找条件是包含关系：`k.start <= segment.start` 且 `segment.end <= k.end`。
2. 字体段样式按 `ParagraphShapingStage.shapeSegment` 的同一规则还原（西文强调段改为斜体）。同一“字面键、字体角色、样式”的组合只塑造一次 U+00A0，`openTypeFeatures` 为空。塑造器抛出 `IllegalStateException` 时，该组合不产生记录。宿主塑造器的任何失败都以这个类型到达引擎：Rust 端 `engine_bridge.rs` 已有这一映射；TS 端 `core/src/engine/prepared-paragraph.ts` 把宿主回调抛出的错误包装为继承 `IllegalStateException` 的 `HostShapingFault`，错误离开引擎时再由 `mapRefusal` 还原为宿主的原始错误，对外抛出的错误与修改前相同。因此字面缺少 U+00A0、浏览器端回放清单缺少 U+00A0 记录（`MissingServerShapingReplay`）两种情况都只跳过该字体段，不中断排版。
3. 相邻且组合相同的字体段合并为一条 `SpacingCarrierAdvanceDecisionInfo`（字段 `range`、`fontKey`、`advance`、`reason`），记入 `LayoutDebugInfo.spacingCarrierAdvanceDecisions`，并由 `LayoutDumpFormat` 输出为 `carrieradvance` 行。
4. `PlanLowering.toPlan` 把记录写入 `Plan.spacingCarrierAdvances`（字段 `rangeStart`、`rangeEnd`、`advance`）。这张表在普通计划与渲染证据计划中都存在。`PlanJson` 把它排在 `lines` 之后、所有渲染证据字段之前，“证据 JSON 以普通 JSON 为前缀”的约束因此保持不变。构建期快照使用普通计划，所以快照页面同样拿到这张表。`PlanPacked` 把这张表追加在着重号列之后。
5. Web 共享层 `PreparedArtifact` 为每个单元格查找覆盖其范围的条目，写入 `PreparedRunTyped.spacingCarrierAdvance`。规则 `InlineCarrierEligibility` 规定两类单元格不查找、取值为空：行末单元格，以及带 `renderFontFamily` 的单元格（塑造段以证据字体绘制，间距元素会继承该字体，而引擎测量 U+00A0 时用的是字体段的字体栈）。
6. `PreparedDom.renderRun` 对 `trailing-letter` 间距按下一节的规则选择写法。

## `renderRun` 的写法选择规则

| 条件 | 写法 |
|---|---|
| `spacingBoundary` 非空（间距位于语义元素末尾） | 保持 `inline-block`，宿主装饰在语义元素末尾停止 |
| 单元格是行末单元格 | 保持 `inline-block`，行末剩余空白不画装饰 |
| 单元格带 `renderFontFamily`（证据字体） | 保持 `inline-block` |
| `spacingCarrierAdvance` 为空 | 保持 `inline-block` |
| 其余情况 | 写出行内文字间距元素 |

行内文字间距元素保留现有属性 `aria-hidden="true"`、`data-tq-copy-ignore="true"`、`data-tq-geometry="true"`、`data-tq-spacing-carrier="true"`，新增 `data-tq-spacing-carrier-inline`，内容仍为一个 U+00A0。动态样式只携带一项数值：

```text
word-spacing:<trailingGap − spacingCarrierAdvance>px!important
```

不随数值变化的声明放在 `platforms/web/client/core/styles.css` 的 `SpacingCarrierInlineText` 规则中：

```css
[data-tq-rendered="true"] span[data-tq-geometry="true"][data-tq-spacing-carrier-inline] {
  display: inline !important;
  white-space: pre !important;
  letter-spacing: 0 !important;
  font-feature-settings: normal !important;
  font-variant: normal !important;
  text-transform: none !important;
  vertical-align: baseline !important;
}
```

选择器带 `span[data-tq-geometry="true"]`，优先级高于已有的 `SharedRuntimeGeometryCss` 规则（其 `all: unset` 会把 `letter-spacing` 改回继承值）。规则不声明 `word-spacing`，样式类写出的 `word-spacing` 因此不被覆盖。`data-tq-advance` 的计算方式不变，仍为 `naturalWidth + trailingGap`。

## 改动文件清单

| 范围 | 文件 | 改动 |
|---|---|---|
| 引擎 | `engine-haxe/src/org/tiqian/layout/SpacingCarrierAdvance.hx`（新增） | 按字体段塑造 U+00A0 并产出记录 |
| 引擎 | `engine-haxe/src/org/tiqian/core/SpacingCarrierAdvanceDecisionInfo.hx`（新增） | 决策记录类型 |
| 引擎 | `WidthIndependentAnnotationCache.hx`、`LineBreakPlanningStage.hx`、`LineAdjustmentStage.hx`、`LayoutDebugAssembly.hx`、`core/LayoutDebugInfo.hx` | 沿 `shapingDecisions` 的路径传递记录，构造参数均为末尾可选参数 |
| 引擎 | `LayoutDumpFormat.hx` | 输出 `carrieradvance` 行 |
| 协议 | `protocol/Plan.hx`、`PlanJson.hx`、`PlanPacked.hx`、`layout/PlanLowering.hx` | 新增 `PlanSpacingCarrierAdvance` 表及其编码 |
| Web 共享层 | `PreparedSpacingCarrierAdvance.hx`（新增）、`PreparedPlan.hx`、`PreparedRunTyped.hx`、`PreparedRunRenderInput.hx`、`PreparedArtifact.hx`、`PreparedDom.hx` | 查表与写法选择 |
| Web 客户端 | `core/src/sampler/snapshot/prepared-dom.ts`、`core/styles.css` | 解析计划中的表；共享样式规则 |
| 引擎 | `layout/ParagraphLayoutEngine.hx` | 构造参数 `measureSpacingCarrierAdvance` |
| 引擎 | `layout/RubySpread.hx`（新增） | 从 `WidthIndependentAnnotationCache.hx` 原样移出 `computeRubySpread`，使该文件行数低于修改前 |
| Web 共享层 | `layout/PreparedParagraphLayout.hx` | 打开 U+00A0 测量 |
| Web 客户端 | `core/src/engine/prepared-paragraph.ts`、`core/tests/spacing-carrier-probe.test.ts`（新增） | 宿主塑造失败经 `HostShapingFault` 进入引擎；新增三个用例 |
| Rust 预计算 | `plan.rs`、`plan_packed.rs`、`shared_prepared.rs`、`engine_bridge.rs`、`tiqian/src/engine.rs` | 读取计划中的表并交给生成的共享层；打开 U+00A0 测量 |
| 测试辅助 | `web-component/tests/runtime-host-text-spacing.ts`（新增） | 模拟 DOM 的字距与词距计算，从 `runtime-host.ts` 移出 |
| 修订号 | `protocol/Revision.hx` 及 16 个引用 `prebroken-dom-v16` 的文件、`ContextFingerprintTest.hx` | 见“版本号”一节 |
| 文档 | `docs/adr/0039-web-rendering-path.md` | 2026-11-26 修订段落 |

## 版本号

预备 DOM 的输出改变，并依赖新的 `SpacingCarrierInlineText` 样式规则，所以 `Revision.RENDER_REVISION` 从 `prebroken-dom-v16` 提升到 `prebroken-dom-v17`；旧快照与新客户端不再互相接受。`ContextFingerprintTest` 的三个黄金哈希随之更新，用 `v16` 重新计算能得到原值，差异只来自修订号。打包计划在末尾增加了表，所以 `PLAN_PROTOCOL_REVISION` 在 `PlanPacked.hx` 与 `plan_packed.rs` 中同时从 1 提升到 2。

## 测试与验证结果

| 范围 | 命令 | 结果 |
|---|---|---|
| Haxe 引擎 | `nix develop -c boring test ts --project boring.json` | 1341 项通过；新增 `PreparedParagraphRenderEvidenceTest.spacingCarrierAdvanceFollowsShapedSegments`，检查记录有序不重叠、普通计划与证据计划都包含 `spacingCarrierAdvances`、每个西文单元格都被记录覆盖 |
| Haxe 协议 | `nix develop -c boring test protocol-ts --project boring.json` | 37 项通过；`PlanJsonTest`、`PlanPackedTest` 覆盖新表的编码与往返 |
| Web 共享层 | `nix develop -c boring test shared-ts --project boring.json` | 53 项通过；新增行内写法与语义边界写法两项 |
| Rust 预计算 | `cargo test -p tiqian-precompute` | 221 项通过；`precomputer_parity` 的五个预期字符串更新，差异只有字体覆盖文本增加 U+00A0、回放塑造记录增加一条、计划增加 `spacingCarrierAdvances` |
| 客户端与服务端 | 各包 `npm test` | `core` 454、`web-component` 242、`server/core` 92 项通过 |
| DOM 预期数据 | `node platforms/web/server/core/scripts/build-prepared-dom-corpus.ts` | 新增 `inline-spacing-carrier`、`inline-spacing-carrier-with-classes` 两个用例，原有 43 个用例不变 |

测试用模拟 DOM（`web-component/tests/runtime-host.ts`）原先计算文字宽度时忽略 `word-spacing`；修改后它与浏览器一致，把 `word-spacing` 加到 U+0020 与 U+00A0 上。

浏览器端用 `@tiqian/web-component` 的运行时打包渲染一个窄栏中英混排页面（含 `<u>`、`<a>`、波浪下划线），在 Chrome 156、Firefox 162（对称字距模型）与 WebKit 中检查：三个引擎的下划线都跨过了拉宽的词间距；Chrome 与 WebKit 中带行内间距元素的塑造段宽度与 `data-tq-advance` 的偏差不超过 0.01px。Firefox 中一个位于中文与链接之间的纯空格塑造段偏差 0.44px；测量显示该段间距元素与引擎前进量只差 0.009px，偏差来自空格字形本身在 DOM 与 canvas 中的宽度差，与间距元素的写法无关。这一处空格宽度差没有在修改前的版本上实测。

## 已知限制

- 宿主装饰来自更外层的祖先，而塑造段又是 `data-tq-shaping-boundary` 的 `inline-block` 时，该塑造段通过 `text-decoration: inherit` 只能取得直接父元素的装饰。这是现有限制，本规格不改变它。
- 两个嵌套语义元素中只有内层在间距处结束时，间距仍按语义边界写成 `inline-block`，外层元素的下划线在此断开。这与 fa7e41522 的现有行为一致。
- 行末单元格之后的普通空格字符仍由浏览器绘制下划线，下划线因此会越过行末最后一个词，延伸一个空格的宽度。这是修改前已有的现象。
- 已发布的旧快照不含 `spacingCarrierAdvances`，这些页面的间距元素保持 `inline-block`，重新构建快照后才会使用行内写法。
