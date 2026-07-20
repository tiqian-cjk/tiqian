# 提椠 Tíqiàn

[![npm version](https://img.shields.io/npm/v/%40tiqian%2Fprose?label=npm)](https://www.npmjs.com/package/@tiqian/prose)

提椠是一个中日韩段落书写器。

它复用各个平台已有的字体、文字测量与绘制能力，统一处理中文正文里的字体选择、
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

目前可以通过 Compose 和 Web 两种前端使用提椠。Android View 模块只保留了接入接口，
还不是可直接使用的完整前端。

## Compose

`frontend/compose` 支持 Compose Desktop 和 Android 31 及以上版本。普通文本可以直接把
Compose 的 `Text` 换成 `CjkText`，已有的 `AnnotatedString` 和 `TextStyle` 也可以继续使用。

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
可以用 `cjkTextCompatibility()` 检查当前还不能保真的能力。

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
[`@tiqian/prose` 使用文档](frontend/web/npm/README.md)。

## 体验与构建

项目使用 Gradle Wrapper，并会按需准备 JDK 25 toolchain：

```shell
./gradlew build
./gradlew runComposeDemo
```

## 文档

- [`@tiqian/prose` 使用文档](frontend/web/npm/README.md) 说明 Web 安装、接入方式与构建期预排。
- [Roadmap](docs/roadmap.md) 记录当前进度、已经完成的切片与下一步工作。
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
