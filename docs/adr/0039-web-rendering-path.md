# ADR 0039: Web 渲染路径 —— 引擎持有行布局,DOM 只画预断行

- Status: Accepted(边界决策;实现属第二阶段,未排期)
- Date: 2026-07-07
- Relates: [ADR 0008](0008-shaping-adapter-contract.md)(shaping adapter 契约)、
  [ADR 0014](0014-ink-bounds-calibrated-punctuation-geometry.md)(`halt` = 度量入口非渲染依赖)、
  [ADR 0031](0031-line-adjustment-direction.md) + [ADR 0038](0038-neighbor-amortized-adjustment.md)(推入推出 / 邻行均摊)、
  [ADR 0037](0037-source-faithful-plain-text.md)(源忠实)

## Context

第二阶段要给提椠加 web 前端。一个诱人的误判是「web 没有 Compose 那些平台能力缺口
(ink skip / 度量补足),所以只要用字体的 `halt` 渲染标点、往里插空、让浏览器换行就行」。
逐条证伪:

1. **提椠在任何平台都不是「用 `halt` 渲染」的**。ADR 0014 已定:排版 advance 来自
   无 feature 的 shaping pass,空白削减由 glue 模型显式执行,`halt` 只是度量入口 + 交叉
   校验;body 恒为 policy 0.5em。AWT 桌面 adapter 完全没有 `halt` 能力,照常出半宽标点。
   所以「字体没有 `halt`」在 web 上不构成结构性损失——降级路径本就在跑。
2. **把断行交给浏览器会丢掉推入推出**。`line-break: strict` 只做一种粗暴避头尾:把犯忌
   字**永远推出**到下一行,没有方向偏好、没有压缩预算、没有 ADR 0038 的邻行均摊,也不可
   解释。这恰恰是引擎最不可让渡的部分。委托浏览器折行 = 丢掉皇冠。
3. **canvas 渲染对正文是错的**。提椠面向中文**正文**,canvas 丢失文本选择、无障碍、复制、
   原生 reflow,还要自管 devicePixelRatio 与重绘。canvas 只适合整块图形。

结论:web 既不能把排版决策让给浏览器(违背「模型必须真」),也不能用 canvas 换取控制权
(丢正文该有的文本语义)。

## Decision

Web = **第四个平台 adapter + 引擎完整行布局 + DOM 画预断行的文本节点**。

### `OffscreenMeasureTextShaping` —— 度量而非渲染

web 的 shaping adapter(ADR 0008 的第四个实现)用**离屏 canvas** `measureText` 取 advance、
`TextMetrics.actualBoundingBox*` 取 ink bounds、`ctx.lang="zh"` + Han-context 子串驱动 `locl`
字形选择。canvas 真正重的是**渲染**,不是**度量**;离屏 `measureText` 不上屏、开销可忽略。
与 AWT / Skia / Android 三个 adapter 同契约。

### `EngineOwnedLineBreaking` —— 断行留在引擎

引擎持有整套行布局:断行 + 推入推出(ADR 0031)+ 邻行均摊(ADR 0038)+ justify。**浏览器
不参与任何断行决策**。这是本 ADR 的核心红线。

### `PreBrokenLineDom` —— DOM 画预断好的行

每个引擎行盒 → 一个块级元素,行内汉字是**裸文本节点**(浏览器画字形、可选中、可复制),
`white-space: nowrap` 禁止浏览器二次折行;推入的压缩、推出留下的空、autospace、justify 落成
行内 `letter-spacing` / `margin`。节点数 ≈ 行数 + 稀疏 span,不是每字一个 span。

### `EngineOwnedHyphenation` —— 断词也归引擎,不甩给浏览器

拉丁词的断词(ADR 0029:`LineEndHangingHyphen` / `LatinForcedHyphenBreak` /
`ExistingHyphenBreak`)与 CJK 断行同理,**必须由引擎决定,DOM 一律不用 `hyphens: auto`,
也不得把未断的整词交给浏览器去折**。委托浏览器断词会丢两样东西:

1. **连字符拿不到**:引擎的行尾连字符是受控几何——`LineEndHangingHyphen` 把连字符
   预留进版心、放不下才把残余悬挂(ADR 0029)。浏览器 `hyphens: auto` 用自己的词典和
   自己的连字符,不是 CLREQ / 引擎那一个,也不进 justify 计量。
2. **断点两端的字偶间距(kerning)被扔掉**:引擎是把**整词**连同字偶间距一起度量、再在
   词内选断点的;一旦交给浏览器重折,两段被独立重排,断点两侧的 kerning 与两行各自的
   advance 都跟引擎算的对不上,justify 也就错位。

所以 DOM 侧:引擎断的词,行尾连字符由渲染层**显式画出**(引擎已把它算进版心 / 悬挂量),
两行的拉丁 run 用**引擎的 per-cluster advance**(含 kerning),不让浏览器重新 shape。
CSS `hyphens` 恒为 `manual`(即不自动断词)。断词开不开、用哪套词典,是引擎默认
(ADR 0029,当前默认开)的事,与 web 后端无关——web 只负责忠实画出引擎的断词结果。

### `ReflowByRebreak` + `WidthIndependentAnnotationCache` —— resize 只重跑折行

放弃「浏览器免费 reflow」,换成 resize 时重跑引擎。但**只重跑折行那一趟**:cluster advance、
locl 字形、基础 autospace 这些**与宽度无关**的量算一次即缓存,`ResizeObserver` 触发时喂给
断行/推入推出/justify 复算即可。贪心 + 有界 lookahead 跑一段几百字是微秒级,与浏览器自身
resize 重排同量级。justify 的邻行均摊因此免费带上,无需单独重档。

### `CssTextAsCrossCheckNotDependency` —— CSS Text 4 是快路径不是依赖

`text-spacing-trim` / `text-autospace` / `hanging-punctuation` 支持时,可对**与宽度无关的**
标点半宽 / 中西间距走纯 CSS 快路径(零 span);不支持(Safari / Firefox 现状)则落到引擎烘出的
span / thin-space 兜底。引擎标注是**跨浏览器真相来源 + 通用兜底**,CSS 只是 Chromium 上的优化。
契约与 `halt` 同构:有则精修、无则降级。**CSS 一律不碰断行**。开发期可拿引擎几何对拍
`getBoundingClientRect`、dump「浏览器是否同意」,保留可解释性。

### `CopyTransparentSpacingSpans` —— 复制仍守源忠实

行是结构块,注入的 spacing span 做成 copy-transparent(不进 selection 文本),选中 / 复制拿回
的是源文本(ADR 0037)。

## Consequences

- 推入推出 / 邻行均摊 / 避头尾在 web 上与 Compose **同源同模型**,不被浏览器策略稀释。
- 常见路径(ragged 正文)只是 DOM 文本 + 稀疏 span,轻;可 SSR 出首屏(固定宽),客户端
  仅在 resize 时重跑折行。
- **真损失**:ADR 0014 §2 那个「低质字体 ink 居中 → 渲染层亚像素平移字形」的补丁,DOM 做不到
  子像素 glyph 挪位。记为具名降级 `InkShiftUnavailableOnDom`,web 上接受(坏字体 polish,非核心)。
- web adapter 的 dump 与 golden 复用现有结构化 dump 通道,新增 `OffscreenMeasureTextShaping`
  geometry source。

## Alternatives considered

- **canvas 渲染**:引擎全权、与 Compose 像素一致,但丢文本选择 / 无障碍 / 复制 / 原生 reflow /
  SSR。对正文是错的取舍。否。
- **DOM + CSS Text 4 一把梭(浏览器折行)**:最省事,但排版模型退化成「Chromium 当前版本怎么
  解释 CLREQ」,丢推入推出、跨浏览器不一致、违背「模型必须真」。否。
- **断词交给浏览器(`hyphens: auto`)**:连字符不受控(不是引擎/CLREQ 那一个、不进 justify),
  且断点两端 kerning 与两行 advance 与引擎度量对不上。见 `EngineOwnedHyphenation`。否。
- **DOM 冻结引擎算好的断点 + x 坐标**:resize 后几何全部失效需整体重发,并未保住原生 reflow,
  反而更脆。被 `ReflowByRebreak`(只重跑折行 + 缓存宽度无关量)取代。否。
- **Houdini CSS Layout API**:理论最优——把断行器注册进浏览器布局树,推入推出跑在**原生 reflow
  内部**,引擎拥有算法、浏览器驱动重排。但 Chromium-only、基本弃坑,不能做主路径。仅作渐进
  增强候选,不阻塞主设计。

## Follow-up

- 第二阶段起 web slice 时:先落 `tiqian-shaping-web`(`OffscreenMeasureTextShaping`)对齐 ADR 0008
  契约,再落 DOM renderer(`PreBrokenLineDom` + `ReflowByRebreak`)。
- 复用现有 golden:web adapter 的逐标点 advance / ink 侧与 AWT / Skia / Android 对照,分歧入
  `haltValidation` 通道。
- roadmap「倾向等 Rust core」的考量与本 ADR 不冲突:core 换 Rust 只改引擎实现语言,
  `OffscreenMeasureTextShaping` 度量后端与 `PreBrokenLineDom` 渲染边界不变。
