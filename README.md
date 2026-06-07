# 提椠 Tíqiàn

提椠是一个面向中文正文的 CJK paragraph layout engine。第一阶段目标是支持 CLREQ 横排核心需求，并为 Compose Multiplatform 与 Android View 提供前端适配。

当前仓库处于项目骨架阶段：模块边界、核心数据结构、测试 fixture 和可解释 layout pipeline 已建立；JVM playground 已有 AWT 真实 advance adapter，标点 atom 能用 shaped glyph bounds 校准 body/glue；字体 fallback、平台 shaping、断行优化和绘制适配仍在逐步替换占位实现。

## 模块

```text
tiqian-core
  平台无关的文本、几何、cluster、glyph run、line box、layout result 模型。

tiqian-font
  字体 fallback、字体角色、排版度量和标点字体策略。

tiqian-shaping-api
  平台 shaping adapter 的公共接口。

tiqian-shaping-jvm
  JVM/AWT 真实 advance 测量 adapter，用于 playground 和早期 contract 验证。

tiqian-linebreak
  断行机会与 line break analyzer 接口。

tiqian-clreq
  CLREQ profile、标点分类和基础策略表。

tiqian-layout
  标点 atom/glue、break candidate、repair option、paragraph layout engine。

tiqian-compose
  Compose Multiplatform 前端 contract。

tiqian-android-view
  Android View 前端 contract。

tiqian-test
  早期排版 fixture。

tiqian-playground
  JVM playground，用于生成 layout dump 和 HTML 可视化调试报告。
```

## 实现约束

功能可以窄，模型必须真。早期实现可以只覆盖少数字符、少数标点和少数 profile，但仍应沿真实 pipeline 推进：

```text
text -> fallback -> shaping -> metrics -> punctuation atom -> glue -> line layout -> render
```

不要把 CLREQ、fallback、标点空间、避头尾或两端对齐逻辑写进 Compose 或 Android View 层。

## Roadmap 与 ADR

- [docs/roadmap.md](docs/roadmap.md) — Slice/Milestone 状态表与「当前位置」。
- [docs/adr/](docs/adr/) — 已确定的取舍（pipeline 边界、字体度量、CLREQ 码点替换、标点 glue 模型）。

新决策走 ADR，散文设计文档负责讲「为什么」，ADR 负责讲「定了什么」。

## Playground

生成控制台 dump 和 HTML 调试报告：

```shell
./gradlew :tiqian-playground:runPlayground
```

报告输出到：

```text
tiqian-playground/build/reports/tiqian-layout-playground/index.html
```

Playground 默认使用 `jvm-awt` shaper；需要回到 deterministic stub 对照时：

```shell
TIQIAN_PLAYGROUND_SHAPER=stub ./gradlew :tiqian-playground:runPlayground
```

## 提交格式

提交信息使用单行简化格式：

```text
type: subject
```

不写 description/body，不加 co-author。
