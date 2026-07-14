# AGENTS.md

提椠（Tiqian）是面向中文正文的 CJK 段落布局引擎。当前已经完成简体中文横排，
并通过 Compose、Android 与 Web 前端持续在真实应用中验证。`ExplainableStubParagraphLayoutEngine`
保留了历史名称，但运行路径已经接入真实 shaping、字体度量、标点几何、断行、行调整与绘制。

## 事实来源

开始非平凡改动前，按任务范围阅读：

- [README.md](README.md)：项目定位、当前能力与使用入口。
- [docs/roadmap.md](docs/roadmap.md)：当前工作、候选切片与已完成范围。
- [docs/architecture.md](docs/architecture.md)：当前 pipeline、模块边界与平台接入方式。
- [docs/adr/README.md](docs/adr/README.md)：ADR 索引。改变既有取舍前先读相关 ADR。
- [docs/clreq-gap-audit.md](docs/clreq-gap-audit.md) 与
  [docs/clreq-punctuation-audit.md](docs/clreq-punctuation-audit.md)：简体横排规则审计。

`docs/research/` 与 `docs/cjk-layout-engine-design.md` 是带日期的研究或初始设计记录，
用于解释背景，不代表当前实现状态。人类贡献流程见 [docs/contributing.md](docs/contributing.md)。

不要根据个人偏好覆盖已记录的取舍。新决策或有意改变既有模型时更新 ADR；普通 bug 修复、
测试和文档修正不需要为了形式创建 Slice。只有持续跟踪的新工作才更新 roadmap 状态。

## Build 与验证

项目使用 Gradle Kotlin Multiplatform，JVM toolchain 为 25；同时包含 Android、浏览器 Kotlin/JS
与 Node Kotlin/JS target。

```shell
./gradlew build

./gradlew :tiqian-layout:jvmTest
./gradlew :tiqian-layout:jvmTest --tests 'org.tiqian.layout.LayoutDumpGoldenTest'
./gradlew :tiqian-layout:generateLayoutReport

./gradlew :tiqian-compose:jvmTest
./gradlew :tiqian-compose:compileAndroidMain
./gradlew :tiqian-demo-android:assembleDebug
./gradlew runComposeDemo

./gradlew :tiqian-web:jsBrowserTest
./gradlew :tiqian-web-precompute:jsNodeTest
./gradlew :tiqian-web:assembleNpmPackage
(cd tiqian-web/npm && npm test)
```

Layout report 位于
`tiqian-layout/build/reports/tiqian-layout-report/index.html`。

任何会改变断行、字体选择、标点空间、行高或行内几何的改动都应：

1. 同步 fixture 与结构化 decision。
2. 运行相关模块测试和 `LayoutDumpGoldenTest`。
3. 行为变化需要更新 golden 时，使用
   `TIQIAN_UPDATE_GOLDEN=1 ./gradlew :tiqian-layout:jvmTest --tests 'org.tiqian.layout.LayoutDumpGoldenTest'`，
   然后逐项检查 golden diff。
4. 生成 layout report，并按涉及平台做浏览器、桌面或 Android 真机检查。

项目没有独立 lint 工具链；仅文档变化至少运行 `git diff --check`。文档中的命令和 API
示例发生变化时，应实际验证对应内容。

## 模块边界

- **排版核心**：`tiqian-core`、`tiqian-font`、`tiqian-linebreak`、`tiqian-clreq`、
  `tiqian-layout` 定义数据、字体策略、断行、中文规则与最终 `LayoutResult`。
- **平台 shaping**：`tiqian-shaping-api` 是契约；`tiqian-shaping-jvm`、
  `tiqian-shaping-skia`、`tiqian-shaping-android`、`tiqian-shaping-web` 提供各平台实现。
- **前端**：`tiqian-compose`、`tiqian-web`、`tiqian-android-view` 只消费布局结果并呈现。
- **Demo 与工具**：`tiqian-demo` 共享 Desktop / Android 示例界面，
  `tiqian-demo-android` 是薄 Android 启动壳；layout report 与 `tiqian-test` 提供诊断和共享语料。

平台层可以负责字体加载、shaping、glyph metrics、绘制和宿主样式读取，但不得自行决定
字体 fallback、标点 glue、避头尾、行调整或两端对齐。需要平台证据的规则应把证据送回
核心 decision，而不是在 renderer 中补视觉偏移。

## 实现约束

1. **走真实 pipeline。** 功能可以窄，但必须经过
   `source → fallback → shaping → metrics → punctuation/glue → line break/repair → adjustment → LayoutResult → render`。
2. **每个 heuristic 必须命名。** 名称应说明它解决什么问题、属于哪个 policy、是否可关闭、
   由什么 fixture 验证。不要留下无名字符判断或魔法偏移。
3. **`LayoutResult` 必须可解释。** 新决策同时进入结构化 debug info 与 dump；renderer 不得
   拥有布局真值的另一份副本。
4. **source text 不可改写。** display cluster 可以按 profile 选择码点或字形，但 source range、
   复制、搜索和无障碍语义必须保留输入。
5. **测量与绘制同源。** 平台 adapter 产出的字体、glyph、advance 与 placement 应能被前端重放；
   无法同源时明确报告 capability issue 或回退，不能静默猜测。
6. **不要假装支持竖排或 JLREQ。** 新 API 需要考虑 writing mode 扩展点，但当前不承诺尚未实现的能力。

## 工作区与提交

工作区可能同时存在其他任务的改动。不要还原、格式化或提交无关文件；同一文件已有并行改动时，
先理解并在其上继续。提交前检查 `git status`、目标 diff 与近期 history。

提交标题沿用仓库格式：

```text
type(scope): subject
```

提交只写单行标题，不写 body，不加 `Co-Authored-By` 或其他 trailer。大型改动按模块或可独立
回退的文档边界分批提交，不把 README、生成物和无关实现塞进同一个提交。
