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

默认情况下，`@tiqian/prose` 会等页面字体准备好后再排版。如果网站使用固定的 web font，桌面正文
也有固定的最大版心，可以在 Node 构建阶段提前排好纯文本段落，减少首屏从原生排版切换到提椠排版
时的变化。普通接入不需要使用这项能力。

构建期预排直接读取字体文件，不需要启动 Headless Chromium：

```js
import {
  createPrecomputer,
  renderSnapshotTemplate,
} from "@tiqian/prose/precompute";

const precomputer = await createPrecomputer({
  faces: [{
    family: "Example CJK",
    source: new URL("./ExampleCJK.woff2", import.meta.url),
    publicUrl: "/assets/ExampleCJK-a81f0932.woff2",
    weight: 400,
    style: "normal",
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

浏览器只在正文内容、版心宽度、排版参数和字体全部匹配时采用快照；任何一项不匹配都会忽略快照，
使用页面原文重新排版。字体的公开 URL 应包含内容 hash，以便浏览器确认它仍是构建时的版本。
完整契约见
[ADR 0040](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/0040-build-time-web-font-snapshots.md)。

上面的 inert template 不会改变浏览器首次绘制。如果希望首屏直接使用预排结果，可以改用
`renderSnapshotBundle()`。服务端需要：

1. 把 `entries[].html` 写入对应的 keyed `<p>`；
2. 把 `rootAttributes` 应用到 `<tiqian-prose>`；
3. 把 `fontPreloads`、`initialStyle` 和 manifest template 写入 `<head>`。

客户端导航仍应传递原始正文 HTML。创建新的 `<tiqian-prose>` 前，可以用
`@tiqian/prose/snapshot-client` 的 `registerSnapshotBundle()` 注册 `clientTemplate`，复用同一份
快照而不重复传输整篇预排 HTML。用于精确绘制的 `@font-face` 必须使用默认
`font-display: auto` 或显式 `block`，不能使用 `optional` 或 `swap`。

## 运行环境

- 包是 ESM-only；CommonJS 宿主需要使用动态 `import()`。
- `@tiqian/prose/precompute` 需要 Node.js 22 或更高版本。
- 布局、断行、行调整与 DOM 增强发布为 Kotlin/JS；生成 runtime 不需要 WebAssembly GC、
  Exception Handling 或 `application/wasm` MIME 配置。可选的 exact-font / 破折号字体证据会懒加载
  `harfbuzzjs` 自带的基础 WebAssembly；普通 host-font 路径与已命中的构建期快照不加载它。
  JavaScript 或可选字体能力加载失败时，原始 SSR 正文仍然可读。

## 了解提椠

- [项目主页](https://github.com/tiqian-cjk/tiqian)介绍当前能力、Compose 前端与本地体验方式。
- [Roadmap](https://github.com/tiqian-cjk/tiqian/blob/main/docs/roadmap.md)记录正在推进和已经完成的工作。
- [当前架构](https://github.com/tiqian-cjk/tiqian/blob/main/docs/architecture.md)说明排版 pipeline 与模块边界。
- [ADR 索引](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/README.md)记录重要设计取舍。

## 许可证

[Mozilla Public License 2.0](./LICENSE)
