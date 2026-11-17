<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/tiqian_wordmark_with_pinyin_and_logo_white.svg">
    <img src="docs/images/tiqian_wordmark_with_pinyin_and_logo_black.svg" alt="提椠 Tíqiàn" height="48">
  </picture>
</h1>

[![Maven Central](https://img.shields.io/maven-central/v/org.tiqian/tiqian-compose?label=maven)](https://central.sonatype.com/artifact/org.tiqian/tiqian-compose)
[![npm version](https://img.shields.io/npm/v/%40tiqian%2Fprose?label=npm)](https://www.npmjs.com/package/@tiqian/prose)
[![Telegram Link](https://img.shields.io/badge/Telegram-@tiqian__cjk-blue?logo=telegram&logoColor=fff)](https://t.me/tiqian_cjk)

提椠是一个中日韩段落书写器。

它在各平台的字体与绘制能力之上，统一处理中文正文里的字体选择、
断行、避头尾、标点空间、两端对齐、行内空间分配与行间注。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/sample-paragraph-white.svg">
  <img src="docs/images/sample-paragraph-black.svg" alt="提椠简体中文横排样张，包含拼音行间注与着重号">
</picture>

## 当前状态

提椠仍处于早期开发阶段，尚未发布稳定版本，公共 API 和模块结构可能继续调整。

- [x] 简体中文横排
- [ ] 繁体中文横排
  - [x] 注音
- [ ] 简 / 繁直排
- [ ] 日文排版（JLREQ）
- [ ] 韩文排版（KLREQ）

目前可以通过 Compose、Android View 和 Web 三种前端使用提椠。

## Compose

Compose 前端支持 Compose Desktop 和 Android 6.0 (API 23) 及以上版本：

```kotlin
implementation("org.tiqian:tiqian-compose:<version>")

// Material 3 项目可以改为依赖 tiqian-compose-material3，以便读取 `LocalTextStyle` 与 `LocalContentColor` 等
implementation("org.tiqian:tiqian-compose-material3:<version>")
```

普通文本可以直接把 Compose 的 `Text` 换成 `CjkText`，已有的 `AnnotatedString` 和
`TextStyle` 也可以继续使用。

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

`CjkText` 会保留源码换行，并支持常用富文本样式、行间注与链接。接入现有富文本渲染器时，
可以用 `cjkTextCompatibility()` 检查当前还不能保真的能力。只读正文可以用
`CjkSelectionContainer` 包住一个或多个 `CjkText`，支持选择与复制。

整篇 Markdown 正文可以使用基于提椠的[提椠 Markdown](https://github.com/tiqian-cjk/tiqian-markdown)，
段落排版之上，还可以统一处理代码、表格、公式、图片与脚注等。

## Android View

使用 View 体系的 Android 应用可以直接依赖原生前端，支持 Android 6.0 (API 23) 及以上版本：

```kotlin
implementation("org.tiqian:tiqian-android-view:<version>")
```

`CjkTextView` 可以在代码或 XML 布局中使用，段落交给提椠排版；选择与复制、
系统文本菜单、链接点击和 TalkBack 朗读都和系统控件一致。粗体、颜色、链接这类
富文本样式和行间注按正文的字符区间提交：

```kotlin
val paragraph = CjkTextView(context).apply {
    content = CjkTextContent(
        content = TiqianTextContent("编号 A-17 的青铜盉仍一并保留。"),
        textStyle = TextStyle(fontSize = textSizePx),
        paragraphStyle = ParagraphStyle(lineHeight = lineHeightPx),
        rubySpans = listOf(RubySpan(TextRange(11, 12), "hé")),
        decorations = listOf(DecorationSpan(TextRange(13, 17), DecorationKind.Emphasis)),
    )
}
```

已有的 `Spanned` 富文本可以直接提交，还不能保真的 span 可以用 `cjkSpannedCompatibility()`
检查。多段正文放进 `CjkTextSurface`，选择与复制跨段工作；把 `overflow` 设为可见后，注音和
悬挂标点可以避免被滚动容器裁切。长文列表可以共享字体测量并在后台预排段落，行内插图可以作为原生子 View
参与排版。 具体接入方式参见 [Android View 接入指南](platforms/android/view/README.md)。

## Web

`@tiqian/prose` 渐进增强服务器已经输出的正文 HTML。没有 JavaScript、加载失败或遇到暂不支持的
内容时，原文仍由浏览器排版；网站原有的字体、颜色、链接、选择与复制语义继续生效。

静态博客和 SSR 网站可以把现有正文放进 `<tiqian-prose>`，再导入自定义元素入口：

```html
<tiqian-prose class="prose">
  <!-- Markdown 或 SSR 生成的正文 -->
</tiqian-prose>

<style>
  tiqian-prose { display: block; }
</style>

<script type="module">
  import "@tiqian/prose/element";
</script>
```

安装、命令式 API、构建期预排与运行环境见
[`@tiqian/prose` 使用文档](platforms/web/client/web-component/README.md)。

## 引擎源码

engine-haxe/src/ 是引擎的 Haxe 源码。boring 编译器从它生成 Kotlin、Swift、
Dart、JS、Rust 五个目标的代码；platforms/engine 是编译生成 Kotlin 的 Gradle
模块，它的 commonMain 指向 engine-haxe/out/kotlin-f32/gen。

- 五个目标的生成、编译与测试见 engine-haxe/README.md。
- Kotlin 平台的行为改动落在 engine-haxe/src/ 的 Haxe 源码，生成物不入库。
- platforms/engine 只保留构建配置，模块自身不含源码。

## 体验与构建

项目使用 Gradle Wrapper，并会按需准备 JDK 25 toolchain；JVM 库产物以 Java 17 为目标：

```shell
./gradlew build
./gradlew runComposeDemo
```

在 Linux 的 XWayland 会话中，JVM 可能无法读取桌面环境的分数缩放。此时可以只为
demo 覆盖 Compose density，例如 Plasma 的 150% 缩放使用：

```shell
./gradlew runComposeDemo -PtiqianDemoDensity=1.5
```

该属性同时缩放 demo 中的 `dp`、`sp`、Compose 控件与 `CjkText`；未设置时保留系统报告的 density。

### Web 引擎包

`platforms/web/client/engine-runtime` 的 `engine-gen/` 与 `runtime/` 都是构建产物，不入库。
在仓库根目录执行 `bun install` 时，install 钩子按以下顺序补齐：

| 安装钩子步骤 | 作用 | 取消条件 |
| --- | --- | --- |
| 把 `.haxelib/boring/git/tools/unicode-data/` 拷到 `tools/unicode-data/` | `reflaxe.unicode.GraphemeData` 按 cwd 读取该目录 | boring 不再按 cwd 读取 `tools/unicode-data`（`t-mwcxehpz-fict`） |
| 用 `boring` 生成 `engine-gen/` | Web 引擎包的 TypeScript 产物 | 发布流程与本地开发都不再依赖 install 钩子生成 `engine-gen/` |
| 用 `tsc` 编译出 `runtime/` | Web 引擎包的运行时 | 发布流程与本地开发都不再依赖 install 钩子生成 `runtime/` |

`tiqian-protocol` 与 `tiqian-shared` 是根 `package.json` 的两个 workspace 成员，成员目录为
`engine-haxe/out/protocol-ts/gen` 与 `engine-haxe/out/shared-ts/gen`；消费方
`platforms/web/client/core` 与 `platforms/web/server/core` 用 `workspace:*` 依赖它们。成员目录的
`package.json` 由 `boring pack` 写出，`boring gen` 只写源码，两个目录不入库，所以干净检出按下面
的顺序执行：

```shell
nix develop -c bash -c 'bash scripts/setup-haxe-env.sh && boring pack protocol-ts shared-ts --project boring.json'
nix develop -c bun install --ignore-scripts
```

`workspace:*` 是 npm 不支持的协议，根目录安装用 `bun install`。上面两条命令之后由
`nix develop -c npm run build:runtime` 生成 `engine-runtime/engine-gen/` 与
`engine-runtime/runtime/`。`--ignore-scripts` 跳过根 postinstall。该钩子与 `boring pack` 都写
`engine-haxe/out/protocol-ts/gen/package.json`：钩子在 `engine-gen/` 缺失时重新生成该目录，删除
`package.json`。两个生产者对同一文件的所有权冲突，命令顺序只能规避它，不能消除它。

Unicode 数据的来源在仓库内：`.haxelib/boring/git/tools/unicode-data/` 来自 flake 固定的
boring 检出。`boring` 生成需要 flake 提供的驱动：

```shell
nix develop -c bun install
nix develop -c npm test --workspace @tiqian/ffi
```

缺少 `boring` 时 install 直接失败并打印下一步，不会留下无法运行的安装结果。

## 文档

- [`@tiqian/prose` 使用文档](platforms/web/client/web-component/README.md) 说明 Web 安装、接入方式与构建期预排。
- [Roadmap](docs/roadmap.md) 记录当前进度、已完成的 Slice 与下一步工作。
- [当前架构](docs/architecture.md) 说明 pipeline、模块边界与平台接入方式。
- [ADR 索引](docs/adr/README.md) 记录已经确定的架构和排版取舍。
- [贡献指南](docs/contributing.md) 说明开发环境、实现约定、验证方式与提交格式。

## 参考资料

- W3C[《中文排版需求》](https://www.w3.org/TR/clreq/)
- The Type[《孔雀计划：中文字体排印的思路》](https://www.thetype.com/kongque/)
- 教育部[《重訂標點符號手冊》（2008 年修訂版）](https://language.moe.gov.tw/001/Upload/FILES/SITE_CONTENT/M0001/HAU/c2.htm)
- 教育部[《國語注音符號手冊》](https://language.moe.gov.tw/001/Upload/files/site_content/M0001/juyin/html_ch/index.html)
- CY/T 154-2017[《中文出版物夹用英文的编辑规范》](https://std.samr.gov.cn/hb/search/stdHBDetailed?id=8B1827F23645BB19E05397BE0A0AB44A)

## 许可证

提椠以 [Mozilla Public License 2.0](LICENSE) 发布。
