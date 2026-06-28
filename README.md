# 提椠 Tíqiàn

提椠是一个中日韩段落书写器。

提椠在平台已有的文字测量与绘制能力之上，额外负责了段落中的断行、避头尾、标点挤压、两端对齐与行内空间分配等排版能力。

## 当前状态

目前提椠仍处于早期开发阶段，API 和模块结构可能继续调整。

- [x] 简体中文横排
- - [x] 行内调整
- - - [ ] 行间注（拼音 / 注音） 
- - [x] 段落调整
- - - [ ] 富文本
- - - - [x] 颜色 / 字号 / 字重 / 斜体 / generic 字体族
- - - - [x] 背景 / 普通下划线 / 删除线 / inline code role
- - - - [x] `softWrap` / `maxLines` / `minLines` / `TextOverflow.Clip|Visible`
- - - - [ ] link 点击与无障碍 action / inline placeholder / ellipsis overflow marker / letterSpacing
- [ ] 繁体中文横排
- [ ] 简 / 繁直排
- [ ] 日文排版（JLREQ）
- [ ] 韩文排版（KLREQ）

Compose 入口目前分两层：`CjkText(String | AnnotatedString, ...)` 是替代 Compose
`Text` 的源忠实纯文本入口，源码里的 `\n` / CRLF / Unicode mandatory break 会作为强制断行保留，
不会被当字形 shape；结构化正文、节与列表使用显式 `CjkText(blocks = ...)`。

## 模块

| 模块                       | 职责                                                                           |
|--------------------------|------------------------------------------------------------------------------|
| `tiqian-core`            | 定义平台无关的布局数据结构，包括文本片段、字形序列、行盒与布局结果。                                           |
| `tiqian-font`            | 处理字体选择、字符分类与字体度量，把平台返回的字体信息转换为提椠使用的排版度量。                                     |
| `tiqian-shaping-api`     | 定义文字测量与字形生成的统一接口。                                                            |
| `tiqian-shaping-jvm`     | 基于 JVM / AWT 实现 `tiqian-shaping-api`，用于测试、调试与桌面环境。                           |
| `tiqian-shaping-skia`    | 基于 Skia / Skiko 实现 `tiqian-shaping-api`，用于 Compose Desktop 等 Skia 渲染环境。      |
| `tiqian-shaping-android` | 基于 Android `TextPaint` 实现 `tiqian-shaping-api`，用于 Android 平台接入。              |
| `tiqian-linebreak`       | 提供断行机会计算，包括 CJK 断行、西文按词换行与连字符断词。                                             |
| `tiqian-clreq`           | 提供中文排版规则 profile，包括标点分类、禁则规则、标点挤压与间距策略。                                      |
| `tiqian-layout`          | 段落布局核心。根据文本、字体度量、行宽和排版规则生成最终的 layout result。                                 |
| `tiqian-compose`         | Compose 前端适配，负责把 `LayoutResult` 渲染到 Compose Desktop / Compose Multiplatform。 |
| `tiqian-android-view`    | Android View 前端适配接口，用于后续接入原生 Android 视图体系。                                   |
| `tiqian-playground`      | 生成 layout dump、HTML 调试报告和可视化预览，用于检查布局决策。                                     |
| `tiqian-test`            | 存放测试 fixture、golden 文件和跨模块测试辅助工具。                                            |


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

## 参考文献

- W3C[《中文排版需求》](https://www.w3.org/TR/clreq/)
- The Type[《孔雀计划：中文字体排印的思路》](https://www.thetype.com/kongque/)
- 教育部[《重訂標點符號手冊》（2008年修訂版）](https://language.moe.gov.tw/001/Upload/FILES/SITE_CONTENT/M0001/HAU/c2.htm)
- CY/T 154-2017[《中文出版物夹用英文的编辑规范》](https://std.samr.gov.cn/hb/search/stdHBDetailed?id=8B1827F23645BB19E05397BE0A0AB44A)
