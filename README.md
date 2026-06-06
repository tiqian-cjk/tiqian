# 提椠 Tiqian

提椠是一个面向中文正文的 CJK paragraph layout engine。第一阶段目标是支持 CLREQ 横排核心需求，并为 Compose Multiplatform 与 Android View 提供前端适配。

当前仓库处于项目骨架阶段：模块边界、核心数据结构、测试 fixture 和可解释占位 layout engine 已建立；真实 shaping、字体 fallback、标点 glue、断行优化和绘制适配尚未实现。

## 模块

```text
tiqian-core
  平台无关的文本、几何、cluster、glyph run、line box、layout result 模型。

tiqian-font
  字体 fallback、字体角色、排版度量和标点字体策略。

tiqian-shaping-api
  平台 shaping adapter 的公共接口。

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
  JVM playground，占位用于后续 layout dump 和可视化调试。
```

## 实现约束

功能可以窄，模型必须真。早期实现可以只覆盖少数字符、少数标点和少数 profile，但仍应沿真实 pipeline 推进：

```text
text -> fallback -> shaping -> metrics -> punctuation atom -> glue -> line layout -> render
```

不要把 CLREQ、fallback、标点空间、避头尾或两端对齐逻辑写进 Compose 或 Android View 层。

## 提交格式

提交信息使用单行简化格式：

```text
type: subject
```

不写 description/body，不加 co-author。

