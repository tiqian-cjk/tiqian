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

[README](../README.md) 用于快速了解项目。开始修改前，请通过[当前架构](architecture.md)
确认代码应当属于哪个模块；排版核心、平台适配和界面前端之间有意保持了清晰的边界。

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
./gradlew :tiqian-web:jsBrowserTest
./gradlew :tiqian-web-precompute:jsNodeTest
./gradlew :tiqian-web:assembleNpmPackage
./gradlew :tiqian-demo-android:assembleDebug
```

准备 npm 发布候选时，还应验证实际 tarball，而不只检查工作目录：

```shell
(cd tiqian-web/npm && npm run verify:release)
```

该命令会重建 browser 与 precompute Kotlin/JS runtime、运行 npm 测试，再把 tarball 安装到临时 consumer
验证 `@tiqian/prose` 的公开 exports；它不会执行 `npm publish`。

## 发布 `@tiqian/prose`

发布以 annotated Git tag `@tiqian/prose@<version>` 为唯一触发器。维护者在干净的 `main` 上运行：

```shell
(cd tiqian-web/npm && npm run release:prepare -- 0.1.0-alpha.3)
git push origin main '@tiqian/prose@0.1.0-alpha.3'
```

`release:prepare` 只更新 `package.json` 与 lockfile，运行完整 `verify:release`，然后按仓库格式创建版本
提交和 annotated tag；它不会推送或发布。tag 推送后，`publish-prose.yml` 在 GitHub-hosted runner 上
重新构建并验证一个 tarball，通过 npm Trusted Publishing（OIDC）把同一个文件发布到 `alpha`，再把
`latest` 同步到相同版本。workflow 最后同时检查两个 dist-tag，任一个未更新都会失败。

仓库的一次性配置包括：

- 在 npm 的 `@tiqian/prose` 设置中，将 GitHub 仓库 `tiqian-cjk/tiqian` 的
  `publish-prose.yml` 配置为允许 `npm publish` 的 Trusted Publisher；
- 在 GitHub Actions secrets 中配置 `NPM_DIST_TAG_TOKEN`。它只供 npm 当前无法通过 OIDC 完成的
  `npm dist-tag add` 使用，应采用仅授权 `@tiqian/prose`、具有 read/write 权限并开启 Bypass 2FA
  的 granular token；在该 job 仍依赖 token 时，不要把包的 Publishing access 设为 disallow tokens；
- 用 GitHub ruleset 限制 `@tiqian/prose@*` tag 的创建权限。

发布 job 只使用 OIDC，不读取 `NPM_DIST_TAG_TOKEN`。`latest` 同步是独立 job；如果它失败，重跑失败
job 即可，不应重复发布已经存在的版本。

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

根 README 只保留项目定位、当前范围、最小使用入口和文档导航。模块或包的具体用法放在对应的
用户文档中；pipeline 与模块职责放在架构文档中；已有取舍的原因与实现契约放在 ADR 中。不要在
多个层级复制同一份说明。

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
