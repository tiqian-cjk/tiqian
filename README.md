# 提椠 Tíqiàn

提椠是一个中日韩段落书写器。

它复用各个平台已有的字体、文字测量与绘制能力，统一处理中文正文里的字体选择、
断行、避头尾、标点空间、两端对齐、行内空间分配与行间注。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/sample-paragraph-white.svg">
  <img src="docs/images/sample-paragraph-black.svg" alt="提椠简体中文横排样张，包含拼音行间注与着重号">
</picture>

样张由提椠实际排版，包含段首缩进、两端对齐、中西混排、中文标点、拼音行间注与着重号。

## 当前状态

提椠仍处于早期开发阶段，尚未发布稳定版本，公共 API 和模块结构可能继续调整。

- [x] 简体中文横排
- [ ] 繁体中文横排
  - [x] 注音
- [ ] 简 / 繁直排
- [ ] 日文排版（JLREQ）
- [ ] 韩文排版（KLREQ）

目前可以通过 Compose 和 Web 两种前端使用提椠。Android View 模块只保留了接入接口，
还不是可直接使用的完整前端。

## Compose

`tiqian-compose` 支持 Compose Desktop 和 Android 31 及以上版本。普通文本可以直接把
Compose 的 `Text` 换成 `CjkText`；已有的 `AnnotatedString` 和 `TextStyle` 也可以继续使用。

```kotlin
val paragraph = buildAnnotatedString {
    append("编号 A-17 的青铜")
    ruby("盉", "hé")
    append("仍")
    emphasis { append("一并保留") }
    append("。")
}

CjkText(
    text = paragraph,
    style = MaterialTheme.typography.bodyLarge,
)
```

接受 `String` 或 `AnnotatedString` 的 `CjkText` 会保留源码中的换行，并支持常用的 Compose
字体样式、背景、下划线、删除线、inline code 与链接点击。接入现有富文本渲染器时，可以先调用
`cjkTextCompatibility()` 查看当前段落中尚不能保真的能力。结构化正文、节和列表使用显式的
`CjkText(blocks = ...)` 入口。

## Web

`@tiqian/web` 用来增强服务器已经输出的正文 HTML。页面会先按普通 HTML 显示，提椠加载
完成后再接管支持的段落。没有 JavaScript、加载失败或遇到暂不支持的内容时，原文仍然可读；
网站原有的字体、颜色、链接和交互样式也会继续生效。

### 构建 Web 包

```shell
./gradlew :tiqian-web:assembleNpmPackage
```

构建结果位于 `tiqian-web/npm/`，可以把这个目录作为本地的 `@tiqian/web` 包接入网站。

### 使用 `<tiqian-prose>`

静态博客和 SSR 网站推荐使用自定义元素。把现有正文放进 `<tiqian-prose>`，然后导入一次入口：

```html
<tiqian-prose class="prose">
  <!-- Markdown 或 SSR 生成的正文 -->
</tiqian-prose>

<script type="module">
  import "@tiqian/web/element";
</script>
```

组件会等待页面字体与样式准备好，再逐段增强正文；容器宽度或排版样式变化时会重新排版，
节点移除时会自行清理，因此可以直接用于 Astro、Swup 等带客户端导航的网站。

`<tiqian-prose>` 使用 light DOM，不会把正文隔离进 shadow DOM。原有的 `.prose a`、
`p > a`、`:hover` 等 CSS 仍然有效，也不需要为提椠重新定义字体或链接样式。暂时无法
保真处理的段落会保留浏览器原生排版。

### 命令式 API

如果正文根节点不能改成自定义元素，或者应用需要自行管理页面生命周期，可以直接调用
包根导出的 API：

```js
import { enhance, destroy } from "@tiqian/web";

const article = document.querySelector("article");

await enhance(article);

// 在替换或移除正文前还原原始 DOM。
await destroy(article);
```

## 运行仓库

项目使用 Gradle Wrapper 构建，并会按需准备 JDK 25 工具链。Android 模块需要本机安装
Android SDK；Web 浏览器测试需要 Chrome 或 Chromium。

```shell
# 编译并运行全部测试
./gradlew build

# 生成 layout dump 和 HTML 调试报告
./gradlew :tiqian-layout:generateLayoutReport

# 打开 Compose Desktop demo
./gradlew runComposeDemo

# 构建同一 Demo 的 Android 启动壳
./gradlew :tiqian-demo-android:assembleDebug
```

Layout report 位于
`tiqian-layout/build/reports/tiqian-layout-report/index.html`。

## 项目结构

- **排版核心**：`tiqian-core`、`tiqian-font`、`tiqian-linebreak`、`tiqian-clreq`、
  `tiqian-layout` 定义排版数据、字体度量、断行与中文排版规则，并生成可解释的
  `LayoutResult`。
- **平台测量**：`tiqian-shaping-api`、`tiqian-shaping-jvm`、`tiqian-shaping-skia`、
  `tiqian-shaping-android`、`tiqian-shaping-web` 使用各平台的文字系统取得字形、排版宽度
  与墨迹边界。
- **前端**：`tiqian-compose`、`tiqian-web`、`tiqian-android-view` 把同一份
  `LayoutResult` 呈现在 Compose、DOM 或 Android View 中。
- **Demo**：`tiqian-demo` 提供 Desktop 入口和共享示例界面，`tiqian-demo-android`
  只负责把同一界面装进 Android 应用。
- **工具与测试**：`tiqian-layout` 的报告与样张任务、`tiqian-test` 的共享语料提供
  调试和跨模块验证。

平台层只负责测量与绘制，字体回退、标点空间、避头尾和两端对齐等决策都由排版核心完成。

## 文档

- [Roadmap](docs/roadmap.md) 记录当前进度、已经完成的切片与下一步工作。
- [当前架构](docs/architecture.md) 说明 pipeline、模块边界与平台接入方式。
- [ADR 索引](docs/adr/README.md) 记录已经确定的架构和排版取舍。
- [初始设计备忘录](docs/cjk-layout-engine-design.md) 保留项目早期的目标与设计背景。
- [贡献指南](docs/contributing.md) 说明开发环境、实现约定、验证方式与提交格式。

## 参考资料

- W3C[《中文排版需求》](https://www.w3.org/TR/clreq/)
- The Type[《孔雀计划：中文字体排印的思路》](https://www.thetype.com/kongque/)
- 教育部[《重訂標點符號手冊》（2008 年修訂版）](https://language.moe.gov.tw/001/Upload/FILES/SITE_CONTENT/M0001/HAU/c2.htm)
- 教育部[《國語注音符號手冊》](https://language.moe.gov.tw/001/Upload/files/site_content/M0001/juyin/html_ch/index.html)
- CY/T 154-2017[《中文出版物夹用英文的编辑规范》](https://std.samr.gov.cn/hb/search/stdHBDetailed?id=8B1827F23645BB19E05397BE0A0AB44A)

## 许可证

提椠以 [Mozilla Public License 2.0](LICENSE) 发布。
