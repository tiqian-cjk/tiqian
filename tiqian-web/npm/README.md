# `@tiqian/prose`

`@tiqian/prose` 用提椠的 CJK 段落布局引擎渐进增强中文正文。服务器仍然输出普通 HTML；
浏览器支持且加载成功时，提椠接管可保真处理的段落。没有 JavaScript、运行时加载失败或正文
超出当前能力范围时，原文继续由浏览器原生排版。

这是 alpha 版本。目前承诺简体中文横排，不承诺竖排或 JLREQ。

## 安装

```shell
npm install @tiqian/prose@alpha
```

## 自定义元素

静态博客和 SSR 网站推荐使用 light-DOM `<tiqian-prose>`：

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

原有的字体、颜色、链接、选择与复制语义保留在宿主 DOM 中。容器宽度或排版样式改变时，
自定义元素会重新排版；暂时无法保真处理的段落不会被接管。
`display: block` 应放进宿主自己的首屏 CSS，而不是只依赖 JavaScript 加载后的包内样式，避免
no-JS 或模块尚未加载时 custom element 按默认 inline 显示。

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

## 构建期快照

固定 web font 和最大版心的 SSR 网站可以在 Node 构建阶段预排纯文本段落，不需要启动
Headless Chromium：

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

把 `snapshot` 原样写入 SSR HTML 的 inert template 位置，并让 live 正文以相同 id 和 paragraph key
引用它；live `<p>` 仍是 no-JS、搜索与失配回退的事实来源：

```html
<head>
  <!-- renderSnapshotTemplate() 的输出；自带 data-pagefind-ignore -->
</head>
<tiqian-prose snapshot-ref="tq-post-snapshot">
  <p data-tq-snapshot-key="intro">需要预排的正文。</p>
</tiqian-prose>
```

浏览器只在 source、宽度、排版参数与字体证据全部命中时采用快照；失配时保持或恢复 SSR
正文，再进入浏览器排版路径。字体 URL 应当内容寻址。完整契约见
[ADR 0040](https://github.com/tiqian-cjk/tiqian/blob/main/docs/adr/0040-build-time-web-font-snapshots.md)。

希望首次绘制就是预排结果时，使用 `renderSnapshotBundle()`。服务端需要：

1. 把 `entries[].html` 写入对应的 keyed `<p>`；
2. 把 `rootAttributes` 应用到 `<tiqian-prose>`；
3. 把 `fontPreloads`、`initialStyle` 和 manifest template 写入 `<head>`。

客户端导航仍应传递原始正文 HTML。创建新的 `<tiqian-prose>` 前，可以用
`@tiqian/prose/snapshot-client` 的 `registerSnapshotBundle()` 注册 `clientTemplate`，复用同一份
快照证据而不重复携带 prepared HTML。用于精确绘制的 `@font-face` 必须使用默认
`font-display: auto` 或显式 `block`，不能使用 `optional` 或 `swap`。

## 运行环境

- 包是 ESM-only；CommonJS 宿主需要使用动态 `import()`。
- `@tiqian/prose/precompute` 需要 Node.js 22 或更高版本。
- 浏览器增强路径需要 Wasm GC、Exception Handling 与 JS string builtins；不支持时原始 SSR
  正文仍然可读。
- 直接部署包内 Wasm 时，服务器应以 `application/wasm` 返回 `.wasm` 文件。

项目说明、支持边界与开发命令见
[Tiqian 仓库](https://github.com/tiqian-cjk/tiqian)。

## License

[Mozilla Public License 2.0](./LICENSE)
