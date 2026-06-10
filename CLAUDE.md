# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

提椠 (Tiqian) 是一个面向中文正文的 CJK paragraph layout engine。当前阶段是骨架 + 可解释占位实现，真实 shaping、字体 fallback、glue、断行、绘制都还没接入。所有决策都必须服务一个目标：**功能可以窄，模型必须真**。

## 必读文档

在写任何非平凡改动之前，至少扫一遍：

- [README.md](README.md) — 模块边界、pipeline 形状、commit 格式。
- [docs/roadmap.md](docs/roadmap.md) — **先看这个**。Slice/Milestone 状态表 + 「当前位置」一行，告诉你下一步该做什么。
- [docs/adr/](docs/adr/) — 已确定的取舍：pipeline 边界 / 字体度量 / CLREQ 码点替换 / 标点 glue 模型。新决策走 ADR。
- [docs/cjk-layout-engine-design.md](docs/cjk-layout-engine-design.md) — 核心模型、字体度量、标点 atom/glue、断行修复的设计取舍（讲「为什么」）。
- [docs/multi-agent-collaboration.md](docs/multi-agent-collaboration.md) — 协作原则、推荐 slice 切法、禁止的协作模式。
- [docs/clreq-punctuation-audit.md](docs/clreq-punctuation-audit.md) — CLREQ 标点替换/分类的逐条记录。

这些文档是项目事实来源。不要根据自己的偏好覆盖里面的取舍——如果要改，先改文档/ADR 再改代码。开新 slice 时把对应行从 `todo` 推进到 `wip`，合入后改 `done` 并更新 roadmap 的「当前位置」。

## Build & test

Gradle Kotlin Multiplatform 项目，所有模块当前只有 `jvm()` target；JVM target = 25。

```shell
./gradlew build                                 # 编译 + 所有模块测试
./gradlew :tiqian-layout:jvmTest                # 单个模块测试
./gradlew :tiqian-layout:jvmTest --tests 'ink.duo3.tiqian.layout.QuotePairAnalyzerTest'
./gradlew :tiqian-playground:runPlayground      # 跑 playground，生成 layout dump + HTML 调试报告
```

Playground HTML 报告输出：`tiqian-playground/build/reports/tiqian-layout-playground/index.html`。任何会改 layout 决策的改动都应该跑一次 playground 并看 dump。

没有 lint 工具链；`kotlin.code.style=official` 通过编译器/IDE 生效。

## 模块依赖方向

依赖必须只向「上游核心」走，平台层只暴露 contract，**不参与排版决策**：

```text
core ── shaping-api ── font ── linebreak ── clreq ── layout
                                                      │
                                          ┌───────────┴───────────┐
                                       compose                android-view   (前端，只是外壳)
                                          │
                                       playground / test
```

- `tiqian-core` — 平台无关数据模型 (Cluster, GlyphRun, LineBox, LayoutInput, LayoutResult)。**不可** 依赖任何其它模块。
- `tiqian-font` — Font role / fallback policy / FontMetricsPolicy / 标点字体策略。
- `tiqian-shaping-api` — shaping 抽象，平台 adapter 实现这个接口。
- `tiqian-linebreak` — UAX#14 / BreakIterator adapter 接口。
- `tiqian-clreq` — CLREQ profile、标点分类、glue 策略表。
- `tiqian-layout` — `ParagraphLayoutEngine`、`PunctuationModel`、`LineOptimization`、`QuotePairAnalyzer`。当前为可解释占位实现。
- `tiqian-compose` / `tiqian-android-view` — 前端 contract。**不允许** 在这里做 fallback、glue、避头尾、justification 任何决策。
- `tiqian-playground` (JVM only) — 生成控制台 dump + HTML 调试可视化。
- `tiqian-test` — fixture 文本与 golden 数据。

如果改动让前端模块开始关心 profile/glue/避头尾，几乎一定是放错层了——把它推回 `layout` 或 `clreq`。

## 项目必守的约束

这些是反复出现且容易被「快速 demo」诱惑破坏的：

1. **真 pipeline，不要快捷绕过**。即使只支持少数标点和单一字体，也要走完整 `text → fallback → shaping → metrics → punctuation atom → glue → line layout → render`，不要在渲染层或 if-char 里硬编码规则。
2. **每个 heuristic 必须命名**。`PreferCjkForAmbiguousPunctuation`、`LineEndHalfWidthPunctuation` 这类大写驼峰名字是项目语言。不接受 `// looks better; x -= 0.5f`。命名应能回答：解决什么问题、属于哪个 profile、是否可关闭、测试语料是什么、是否影响竖排/JLREQ。
3. **LayoutResult 必须可解释**。每个 cluster 的字体、每个 glyph run 的 raw/layout metrics、每个标点的 ink/body/glue、每个断点的候选与禁则原因、每行的 repair plan，都要能被 dump 出来。新增决策同时新增 dump。
4. **source text 不可改写**。display cluster 可以根据 profile 选择更合适的码点 (例：`……` → `⋯⋯`)，但 source range / 复制 / 搜索行为必须保留输入。详见 clreq-punctuation-audit.md。
5. **不要过早承诺竖排和 JLREQ**。预留接口可以，假装已经解决不行。新 API 设计要问一句「竖排时它该怎么改」，但不要在第一阶段做完。

## Commit 格式（严格执行）

单行简化格式，**不写 body/description，不加 Co-Authored-By，不加任何 trailer**：

```text
type: subject
```

`type` 沿用近期 history (`feat`, `fix`, `docs`, `build`, ...)。即使工具默认建议加 Claude/Anthropic co-author，也要去掉。这个仓库 README 和用户都明确说过。

## 状态快照

当前 layout engine 是「可解释占位实现」(`ExplainableStubParagraphLayoutEngine`)，目的是先把 dump/解释路径打通，再逐步替换为真实 shaping。修改它时请同步更新对应 fixture/test，并确保 dump 仍可读。
