# `@tiqian/prose`

提椠是一个中日韩段落书写器。`@tiqian/prose` 是提椠的 Web 前端，目前用于简体中文横排。

它适合已经用 Markdown、静态站点生成器或 SSR 输出文章的网站。网站继续生成普通 HTML，
`@tiqian/prose` 在浏览器支持时接管能够保真处理的段落。你不需要重写现有内容管线，字体、颜色、
链接和交互样式也仍由网站自己控制。

提椠会按整段正文计算字体、标点空间和断行，再把结果呈现为普通 DOM 文字，而不是 Canvas 或图片；
排版后的文章仍然可以正常选择、复制、搜索和访问。

没有 JavaScript、包加载失败或某段内容暂不支持时，原文会继续由浏览器正常排版。这个包目前是
alpha 版本，不承诺稳定 API，也还不支持竖排、日文 JLREQ 或所有复杂富文本结构。

## 安装

```shell
npm install @tiqian/prose@alpha
```

## 自定义元素

静态博客和 SSR 网站推荐使用 `<tiqian-prose>`：

```html
<tiqian-prose class="prose">
  <p>提椠是一个中日韩段落书写器。</p>
</tiqian-prose>

<style>
  tiqian-prose { display: block; }
</style>

<script type="module">
  import "@tiqian/prose/element";
</script>
```

`<tiqian-prose>` 直接使用页面原有的 DOM，不会用 Shadow DOM 隔开正文。原有字体、颜色、链接、
选择与复制语义都会保留；容器宽度或排版样式改变时，组件会重新排版。暂时不能保真处理的段落
不会被接管。

请把 `display: block` 放进网站自己的首屏 CSS。这样即使 JavaScript 还没加载或不可用，
`<tiqian-prose>` 也不会按浏览器默认的行内元素显示。

提椠默认让原生列表标记保留在正文外侧，并用 `2ic` 作为列表正文缩进。已有站点需要延续自己的
列表几何时，可以在正文根节点覆盖 `--tq-list-indent`：

```css
tiqian-prose {
  --tq-list-indent: 40px;
}
```

Markdown 的加粗默认保留为原生 `<strong>` 粗体。如果站点把 `<strong>` 用作中文的着重语义，
可以开启着重号转换：

```html
<tiqian-prose strong-as-emphasis-marks>
  <p><strong>这里改用着重号</strong>，西文仍使用粗体。</p>
</tiqian-prose>
```

需要让宿主或用户关闭增强时，使用标准 Boolean attribute `disabled`：

```html
<tiqian-prose disabled>
  <p>当前保留浏览器原生排版。</p>
</tiqian-prose>
```

`disabled` 初始存在时，组件保留服务器输出的语义 DOM，不采用构建期快照，也不启动排版 runtime
或观察器。运行中增加该属性会取消在途排版并恢复原文；移除后会重新进入完整生命周期，并可复用
已经注册的快照。它只控制客户端增强，不会从已经生成的 SSR HTML 中删除 inert snapshot 数据。
和所有 HTML Boolean attribute 一样，`disabled="false"` 仍表示关闭；需要开启时应移除该属性。

## 响应式容器与 CSS 布局注意事项

### 1. Flexbox / Grid 布局中的 `min-width: 0`

在 CSS 规范中，Flexbox 与 CSS Grid 子项的 `min-width`（或 `min-inline-size`）默认值为 `auto`（即 `min-content` 内容最小宽度）。

当 `<tiqian-prose>` 放置在 Flexbox 或 Grid 布局的子容器（例如 `.card`、`.main-content` 或双栏布局列）内时，若未解除默认最小宽度约束，容器在窗口缩小（resize）时可能会拒绝收缩，进而导致响应式观察器陷入尺寸死锁。

**建议**：在承载正文的 Flex / Grid Item 上显式设置 `min-width: 0`（或 `min-inline-size: 0`）：

```css
.flex-item,
.grid-column,
.article-wrapper {
  min-width: 0;
  /* 或 min-inline-size: 0; */
}
```

### 2. 避免缩放冲出：外层容器 `overflow: clip` 与标点悬挂安全区

在窗口快速缩放或高频拖拽过程中，为避免排版完成前内容冲出外层视口或卡片边界，建议对外层容器添加溢出裁剪。但需要注意**层级与内边距搭配**，以避免破坏中西文排版的视觉悬挂：

* **避免直接在 `<tiqian-prose>` 上设置 `overflow: hidden`**：
  中文排版中，行首/行末的悬挂标点（Punctuation Hanging）可能向外延伸约 `0.5em`，着重号与下划线也位于字形基线下方。直接在组件根节点裁剪会导致突出的标点或行末点号被生硬切断。
* **正确做法**：将 `overflow: clip`（或 `overflow: hidden`）设置在**外层卡片 / 版心容器（Article Container / Card Wrapper）** 上，并为该容器保留至少 `0.5em`（建议 `16px` 以上）的 `padding-inline`：

```css
/* 推荐：外层版心卡片负责裁剪与提供悬挂安全区 */
.article-card,
.prose-container {
  overflow: clip; /* 或 overflow: hidden */
  padding-inline: max(16px, 1em); /* 为标点悬挂预留安全缓冲区 */
  box-sizing: border-box;
}

tiqian-prose {
  display: block;
  min-width: 0;
}
```

## 命令式 API

不能使用自定义元素时，可以自行管理正文根节点的生命周期：

```js
import { destroy, enhance } from "@tiqian/prose";

const article = document.querySelector("article");
await enhance(article);

// 替换或移除正文前还原原始 DOM。
await destroy(article);
```

## 构建期预排（可选）

使用固定 web font，且桌面正文有固定最大版心的网站，可以在 Node 构建阶段提前排好段落，减少
首屏从原生排版切换到提椠排版时的变化。普通接入不需要使用这项能力。

构建期预排在 Node 里直接读取网站已有的 `@font-face` 样式表和字体文件，不需要 Headless 浏览器，
也不改变网站自己的字体交付方式。入口在独立的 `@tiqian/precompute` 包中，通过 Neon 原生插件
执行；安装时会按平台带入对应的二进制可选依赖：

```sh
npm install @tiqian/prose @tiqian/precompute
```

```js
import {
  absorbSnapshotTables,
  assembleSnapshotBundle,
  createPrecomputer,
  createSnapshotTables,
  finalizeSnapshotTables,
  renderSnapshotBundleData,
} from "@tiqian/precompute/precompute";

const precomputer = await createPrecomputer({
  fontStylesheets: [{
    source: new URL("./static/fonts/article.css", import.meta.url),
    publicUrl: "/fonts/article.css",
  }],
  typography: {
    fontFamilies: ["Example CJK", "sans-serif"],
    fontSizePx: 18,
    lineHeightPx: 31.5,
  },
});

const paragraph = await precomputer.prepareParagraph({
  key: "intro",
  text: "需要预排的正文。",
  maxWidthPx: 720,
});
if (paragraph.status !== "prepared") {
  precomputer.close();
  throw new Error(paragraph.issue);
}

// 一次构建一组站级表：先吸收全部条目，渲染数据，冻结后拼装。
const tables = createSnapshotTables();
absorbSnapshotTables(tables, [paragraph]);
const data = renderSnapshotBundleData([paragraph], {
  id: "tq-post-snapshot",
  snapshotTables: tables,
});
const file = finalizeSnapshotTables(tables); // { bytes, sha256 }
const bundle = assembleSnapshotBundle(data, tables);
precomputer.close();
```

`source` 是构建机上的样式表路径；`publicUrl` 是同一张样式表部署后的地址，用来解析其中的相对
字体 URL。需要程序化生成字体配置时，可以改用 `faces` 数组（与 `fontStylesheets` 二选一）。

`file.bytes` 是一次构建共享的站级表，按内容哈希命名写入静态目录（例如
`/tiqian-tables/<sha256>`），页面根元素用 `tq-tables` 属性指向该地址。`bundle.inertTemplate`
作为 HTML 写入 `<head>`，`bundle.initialStyle` 是 CSS 字符串，需要放进 `<style>`：

```html
<head>
  <style data-tq-initial-snapshot="tq-post-snapshot"><!-- bundle.initialStyle --></style>
  <!-- bundle.inertTemplate；自带 data-pagefind-ignore -->
</head>
<tiqian-prose snapshot-ref="tq-post-snapshot" tq-tables="/tiqian-tables/<sha256>">
  <p data-tq-snapshot-key="intro">需要预排的正文。</p>
</tiqian-prose>
```

原始 `<p>` 始终保留，负责无 JavaScript 显示、站内搜索和快照失效后的回退。快照以 inert
template 的形式进入页面，不改变浏览器的首次绘制。浏览器只在正文内容、版心宽度、排版参数、
站级表和宿主实际选中的字体全部匹配时采用快照；任何一项不匹配都会保留页面原文并在浏览器中
重新排版。完整契约见
[ADR 0040](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/0040-build-time-web-font-snapshots.md)
与
[ADR 0052](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/0052-precompute-cache-and-batch-renderer.md)。

客户端导航照常传递原始正文 HTML；创建新的 `<tiqian-prose>` 前，用 `@tiqian/prose/snapshot-client`
的 `registerSnapshotBundle()` 注册 bundle 中的客户端数据即可复用快照，不必重复传输整篇预排
HTML。

若正文必须保留原始语义 DOM，并由浏览器完成布局（例如包含链接的富文本），可以在关闭
precomputer 前用 `prepareFontContract()` 只生成字体与度量证据，再走同一条拆分路径，
数据阶段换用 `renderFontContractBundleData()`，拼装换用 `assembleFontContractBundle()`，
契约条目同样先进表：

```js
const evidence = await precomputer.prepareFontContract({
  key: "intro-font-contract",
  text: "需要在浏览器排版的正文。",
});
if (evidence.status !== "prepared") {
  throw new Error(evidence.issue);
}

const contractTables = createSnapshotTables();
absorbSnapshotTables(contractTables, [evidence]);
const contractData = renderFontContractBundleData([evidence], {
  id: "tq-post-font-contract",
  snapshotTables: contractTables,
});
finalizeSnapshotTables(contractTables);
const fontBundle = assembleFontContractBundle(contractData, contractTables);
```

`fontBundle` 的注入和客户端注册方式与上面的 `bundle` 相同，`<tiqian-prose>` 仍用
`snapshot-ref` 引用它的 id；段落布局在浏览器完成，并复用构建期的 shaping 结果，正文段落
不需要设置 `data-tq-snapshot-key`。字体证据与最终断行宽度无关，因此这里不需要声明
`maxWidthPx`；只有前面的固定版心 snapshot 才需要宽度。

## 框架集成

同一仓库还提供独立的 `@tiqian/sveltekit` 与 `@tiqian/astro` 包。最小用法只包裹站点已经渲染的
正文，即可得到 semantic SSR 和按浏览器真实容器宽度运行的提椠增强；无需声明最大宽度。需要构建期
exact-font replay 时再配置宿主字体，只有主动开启 fixed-measure snapshot 时才传 `maxWidthPx`。

框架包保持独立，是为了不让普通 `@tiqian/prose` 用户安装 Svelte 或 Astro；它们与核心放在同一仓库，
以便 snapshot wire 和发布版本始终一起验证。开启构建期预排时，框架包的服务端入口同样来自
`@tiqian/precompute`，需要一并安装。

## 运行环境

- 包是 ESM-only；CommonJS 宿主需要使用动态 `import()`。
- 构建期预排入口在 `@tiqian/precompute`，需要 Node.js 22 或更高版本。
- 浏览器端 runtime 是纯 JavaScript，不加载 WebAssembly，也不需要特殊的服务器配置。

## 了解提椠

- [项目主页](https://github.com/tiqian-cjk/tiqian)介绍当前能力、Compose 前端与本地体验方式。
- [Roadmap](https://github.com/tiqian-cjk/tiqian/blob/main/docs/roadmap.md)记录正在推进和已经完成的工作。
- [当前架构](https://github.com/tiqian-cjk/tiqian/blob/main/docs/architecture.md)说明排版 pipeline 与模块边界。
- [ADR 索引](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/README.md)记录重要设计取舍。

## 许可证

[Mozilla Public License 2.0](./LICENSE)
