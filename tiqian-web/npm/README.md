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

Markdown 的加粗会保留为原生 `<strong>` 粗体，不会默认改成着重号。只有站点明确把
`<strong>` 当作中文着重语义时才显式开启转换：

```html
<tiqian-prose strong-as-emphasis-marks>
  <p><strong>这里改用着重号</strong>，西文仍使用粗体。</p>
</tiqian-prose>
```

## 命令式 API

不能使用自定义元素时，可以自行管理正文根节点的生命周期：

```js
import { destroy, enhance } from "@tiqian/prose";

const article = document.querySelector("article");
await enhance(article);

// 仅在宿主明确采用这套语义时启用。
// await enhance(article, { strongAsEmphasisMarks: true });

// 替换或移除正文前还原原始 DOM。
await destroy(article);
```

## 构建期预排（可选）

默认情况下，`@tiqian/prose` 只等待正文实际使用的字体和字符子集，最多等待 3 秒；超时会继续显示
原生 SSR 正文，字体完成加载或宿主字体样式变化后再按最新状态重试。如果网站使用固定的 web font，
桌面正文也有固定的最大版心，可以在 Node 构建阶段提前排好纯文本段落，减少首屏从原生排版切换到
提椠排版时的变化。普通接入不需要使用这项能力。

构建期预排直接读取网站已有的 `@font-face` 样式表和字体文件，不需要启动 Headless Chromium，
也不会复制字体、生成别名或增加浏览器端字体请求：

```js
import {
  createPrecomputer,
  renderSnapshotTemplate,
} from "@tiqian/prose/precompute";

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
const snapshot = renderSnapshotTemplate([paragraph], { id: "tq-post-snapshot" });
precomputer.close();
```

把 `snapshot` 原样写入 SSR HTML 中的 inert template，并让页面正文使用相同的 id 和 paragraph key
引用它。原始 `<p>` 始终保留，负责无 JavaScript 显示、站内搜索和快照失效后的回退：

```html
<head>
  <!-- renderSnapshotTemplate() 的输出；自带 data-pagefind-ignore -->
</head>
<tiqian-prose snapshot-ref="tq-post-snapshot">
  <p data-tq-snapshot-key="intro">需要预排的正文。</p>
</tiqian-prose>
```

`source` 是构建机读取的本地样式表；`publicUrl` 是同一张样式表在网站上的地址，用于解析其中的
相对字体 URL，不是提椠代理。样式表里的 `local()` 会保留为宿主自己的字体选择，提椠不会重新暴露
本地字体，也不会为中文字体的数百个分片创建第二套 URL。需要程序化生成字体配置时，仍可使用底层
`faces` 数组，但不能和 `fontStylesheets` 同时传入。

浏览器只在正文内容、版心宽度、排版参数和宿主实际选中的字体全部匹配时采用快照；任何一项不匹配
都会保留页面原文并在浏览器中重新排版。提椠不要求宿主字体 URL 带内容 hash。
完整契约见
[ADR 0040](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/0040-build-time-web-font-snapshots.md)。

上面的 inert template 不会改变浏览器首次绘制。响应式 SSR 必须保留原始 `<p>`；服务端不知道
客户端的实际版心宽度，也无法预先证明 `local()` 最终选中的字形，因此不应把 `entries[].html`
直接替换成首屏可见内容。需要同时拿到初始样式和客户端导航契约时，可以使用
`renderSnapshotBundle()`，把它的 `initialStyle` 与 `inertTemplate` 写入 `<head>`。

客户端导航仍应传递原始正文 HTML。创建新的 `<tiqian-prose>` 前，可以用
`@tiqian/prose/snapshot-client` 的 `registerSnapshotBundle()` 注册 `clientTemplate`，复用同一份
快照而不重复传输整篇预排 HTML。字体的加载与 preload 策略始终由宿主样式表决定。

当一个正文根包含暂时无法预排的富文本，但仍希望浏览器复用构建时生成的 shaping 与度量证据时，
使用 `renderFontContractBundle()`。它只输出紧凑的宿主字体契约和 server replay 数据，不输出可采用
的段落几何，也不会要求宿主把正文标记成已使用快照；浏览器仍从原始语义 DOM 完成全部段落布局。

## 运行环境

- 包是 ESM-only；CommonJS 宿主需要使用动态 `import()`。
- `@tiqian/prose/precompute` 需要 Node.js 22 或更高版本。
- 布局、断行、行调整与 DOM 增强发布为 Kotlin/JS；生成 runtime 不需要 WebAssembly GC、
  Exception Handling 或 `application/wasm` MIME 配置。HarfBuzz / WOFF2 WebAssembly 只在 Node
  构建期生成字体证据；浏览器端的快照 miss 使用纯 JavaScript 缩放并重放服务器证据，不加载或执行
  WebAssembly。JavaScript、字体或回放证据不可用时，原始 SSR 正文仍然可读。

## 了解提椠

- [项目主页](https://github.com/tiqian-cjk/tiqian)介绍当前能力、Compose 前端与本地体验方式。
- [Roadmap](https://github.com/tiqian-cjk/tiqian/blob/main/docs/roadmap.md)记录正在推进和已经完成的工作。
- [当前架构](https://github.com/tiqian-cjk/tiqian/blob/main/docs/architecture.md)说明排版 pipeline 与模块边界。
- [ADR 索引](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/README.md)记录重要设计取舍。

## 许可证

[Mozilla Public License 2.0](./LICENSE)
