# 贡献指南

欢迎为提椠修复问题、补充测试、改进平台适配或完善文档。项目仍在快速演进，
涉及公共 API 或排版规则的大改动，建议先通过 issue 说明使用场景和预期行为，
避免双方在实现完成后才发现方向不同。

## 准备环境

项目使用 Gradle Wrapper 构建，不需要另外安装 Gradle。构建脚本会请求 JDK 25
toolchain；Android 相关模块还需要可用的 Android SDK，Web 浏览器测试需要本机安装
Chrome 或 Chromium。

首次检出后可以运行完整构建：

```shell
./gradlew build
```

如果只修改一个模块，可以先运行该模块的测试，减少等待时间。

## 了解项目

[README](../README.md) 列出了各模块的职责。开始修改前，先确认代码应当属于哪个模块；
排版核心、平台适配和界面前端之间有意保持了清晰的边界。

- [roadmap](roadmap.md) 记录当前正在推进和已经完成的工作，可以用来了解项目方向。
- [当前架构](architecture.md) 说明 pipeline、模块边界与平台接入方式。
- [ADR 索引](adr/README.md) 记录已经确定的架构和排版取舍。

roadmap 不是贡献许可清单。修复明确的 bug、增加测试或改善文档，不需要先创建 Slice；
只有在开启一项需要持续跟踪的新工作时，才需要补充 roadmap。

## 实现约定

排版规则应放在拥有这项职责的核心模块中。Compose、Android View 和 Web 前端负责把
`LayoutResult` 呈现出来，不应各自实现一套标点挤压、避头尾或两端对齐逻辑。

修改排版行为时，请同时注意以下几点：

- 保留原始文本及其范围。显示时替换字形或码点，不应改变复制、搜索和无障碍语义。
- 将新的排版策略放进现有模型，并使用能说明意图的名称；避免在渲染代码中散落特殊字符判断或魔法数字。
- 让新增决策出现在 layout dump 中，并用能够说明真实问题的文本 fixture 覆盖它。
- 平台测量与绘制应使用同一套字体和字形数据，避免布局结果与实际上屏几何分叉。

不确定改动应放在哪里时，可以先查看相关 ADR，或在 issue 中附上最小复现再讨论实现位置。

## 验证改动

提交前至少运行与改动范围对应的测试。常用命令如下：

```shell
./gradlew :tiqian-layout:jvmTest
./gradlew :tiqian-compose:jvmTest
./gradlew :tiqian-web:wasmJsBrowserTest
./gradlew :tiqian-web:assembleNpmPackage
./gradlew :tiqian-demo-android:assembleDebug
```

如果改动会影响断行、标点空间、字体选择或行内几何，还需要运行 layout golden test
并生成诊断报告：

```shell
./gradlew :tiqian-layout:jvmTest --tests '*LayoutDumpGoldenTest*'
./gradlew :tiqian-layout:generateLayoutReport
```

Layout report 位于
`tiqian-layout/build/reports/tiqian-layout-report/index.html`。

预期中的布局变化可以用下面的命令更新 golden：

```shell
TIQIAN_UPDATE_GOLDEN=1 ./gradlew :tiqian-layout:jvmTest --tests '*LayoutDumpGoldenTest*'
```

更新后请检查 golden diff，确认变化只出现在预期的 fixture 中。涉及 Web 或平台渲染的
改动还应在真实页面或设备上检查文字是否被裁切、交互是否正常，以及调整窗口宽度后能否稳定重排。

只有文档发生变化时，运行 `git diff --check` 通常就足够了；如果文档中的命令、API 示例
或构建说明发生变化，请实际验证对应内容。

## 文档与设计决策

修复实现与既有文档不一致的问题时，应让代码回到已经记录的行为。若贡献有意改变公共 API、
模块边界或既有排版取舍，请在同一个改动中更新或新增 ADR，并说明使用场景、决定及影响。

只有当 roadmap 中工作的状态确实发生变化时才更新它，不要为了普通代码提交制造状态噪音。

## 提交与 Pull Request

提交标题沿用仓库近期使用的格式：

```text
type(scope): subject
```

例如：

```text
fix(layout): keep closing punctuation off line start
feat(web): preserve host link styles
docs(adr): record web rendering boundary
```

每个提交应围绕一个可以独立解释和验证的改动，避免混入无关格式化或生成文件变化。

Pull Request 请说明：

- 要解决的实际问题，以及如何复现；
- 采用的实现方式和重要取舍；
- 已运行的自动化测试与人工检查；
- 行为变化涉及的 issue、ADR 或 roadmap 条目（如有）。
