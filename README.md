# 提椠 Tíqiàn

提椠是一个中日韩段落书写器。

提椠在平台已有的文字测量与绘制能力之上，额外负责了段落中的断行、避头尾、标点挤压、两端对齐与行内空间分配等排版能力。

## 当前状态

目前提椠仍处于早期开发阶段，API 和模块结构可能继续调整。

- [x] 简体中文横排
- [ ] 繁体中文横排
- [ ] 简 / 繁直排
- [ ] 日文排版（JLREQ）
- [ ] 韩文排版（KLREQ）

## 模块

| 模块                       | 职责                                                                           |
|--------------------------|------------------------------------------------------------------------------|
| `tiqian-core`            | 定义平台无关的布局数据结构，包括文本片段、字形序列、行盒与布局结果。                                           |
| `tiqian-font`            | 处理字体选择、字符分类与字体度量，把平台返回的字体信息转换为提椠使用的排版度量。                                     |
| `tiqian-shaping-api`     | 定义文字测量与字形生成的统一接口。                                                            |
| `tiqian-shaping-jvm`     | 基于 JVM / AWT 实现 `tiqian-shaping-api`，用于测试、调试与桌面环境。                           |
| `tiqian-shaping-skia`    | 基于 Skia / Skiko 实现 `tiqian-shaping-api`，用于 Compose Desktop 等 Skia 渲染环境。      |
| `tiqian-shaping-android` | 基于 Android `TextPaint` 实现 `tiqian-shaping-api`，用于 Android 平台接入。              |
| `tiqian-shaping-web`     | 基于浏览器离屏 Canvas 实现 shaping / font metrics 度量，不负责上屏绘制。                         |
| `tiqian-linebreak`       | 提供断行机会计算，包括 CJK 断行、西文按词换行与连字符断词。                                             |
| `tiqian-clreq`           | 提供中文排版规则 profile，包括标点分类、禁则规则、标点挤压与间距策略。                                      |
| `tiqian-layout`          | 段落布局核心。根据文本、字体度量、行宽和排版规则生成最终的 layout result；golden dump 在其测试资源里。            |
| `tiqian-compose`         | Compose 前端适配，负责把 `LayoutResult` 渲染到 Compose Desktop / Compose Multiplatform。 |
| `tiqian-gallery-android` | Android Compose 真机 gallery，用真实设备 dogfood 排版能力。                                |
| `tiqian-android-view`    | Android View 前端适配接口，用于后续接入原生 Android 视图体系。                                   |
| `tiqian-web`             | Web ESM package 与 light-DOM `<tiqian-prose>` 渐进增强前端；保留宿主 SSR、语义节点与 CSS。          |
| `tiqian-playground`      | 生成 layout dump、HTML 调试报告和可视化预览，用于检查布局决策。                                     |
| `tiqian-test`            | 存放跨模块共享的测试 fixture 文本。                                                        |


## 上手

编译 + 全部测试
```shell
./gradlew build
```

生成 layout dump + HTML 调试报告
```shell
./gradlew :tiqian-playground:runPlayground
```

Jetpack Compose Desktop Demo
```shell
./gradlew :tiqian-compose:runComposeDemo 
```

### Web 使用

`@tiqian/web` 用来增强服务器已经输出的正文 HTML。页面会先按普通 HTML 显示，
提椠加载完成后再接管支持的段落。没有 JavaScript、加载失败或遇到暂不支持的内容时，
原文仍然可读；网站原有的字体、颜色和链接样式也会继续生效。

#### 构建

```shell
./gradlew :tiqian-web:assembleNpmPackage
```

构建结果位于 `tiqian-web/npm/`，可以把这个目录作为本地的 `@tiqian/web` package 接入网站。

#### 推荐：`<tiqian-prose>`

静态博客和 SSR 网站推荐使用 custom element。把现有正文放进 `<tiqian-prose>`，
然后在页面中导入一次入口：

```html
<tiqian-prose class="prose">
  <!-- Markdown 或 SSR 生成的正文 -->
</tiqian-prose>

<script type="module">
  import "@tiqian/web/element";
</script>
```

组件会等页面字体和样式准备好后再增强正文，并在容器宽度或排版样式变化时重新排版。
节点从页面移除时，它也会自动清理，因此可以直接用于 Astro、Swup 等带页面导航的网站。

`<tiqian-prose>` 使用 light DOM，不会把正文隔离进 shadow DOM。原有的 `.prose a`、
`p > a`、`:hover` 等 CSS 仍然有效，也不需要为提椠重新写一套链接或字体样式。
暂时无法处理的段落会保留浏览器原生排版。

#### 命令式 API

如果正文根节点不能改成 custom element，或者应用需要自行管理页面生命周期，
可以直接调用包根导出的 API：

```js
import { enhance, destroy } from "@tiqian/web";

const article = document.querySelector("article");

await enhance(article);

// 在替换或移除正文前还原原始 DOM。
await destroy(article);
```

## 参考文献

- W3C[《中文排版需求》](https://www.w3.org/TR/clreq/)
- The Type[《孔雀计划：中文字体排印的思路》](https://www.thetype.com/kongque/)
- 教育部[《重訂標點符號手冊》（2008年修訂版）](https://language.moe.gov.tw/001/Upload/FILES/SITE_CONTENT/M0001/HAU/c2.htm)
- 教育部[《國語注音符號手冊》](https://language.moe.gov.tw/001/Upload/files/site_content/M0001/juyin/html_ch/index.html)
- CY/T 154-2017[《中文出版物夹用英文的编辑规范》](https://std.samr.gov.cn/hb/search/stdHBDetailed?id=8B1827F23645BB19E05397BE0A0AB44A)
