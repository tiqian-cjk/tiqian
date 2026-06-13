# ADR 0007: 字格优先、加法标点与可解释断行决策

- Status: Accepted
- Date: 2026-06-06

## Context

提椠的早期实现已经覆盖字体 fallback、CJK 度量规整、CLREQ 推荐码点、PunctuationAtom、SpacingPlan、初步 kinsoku repair 与 justification。继续向 PushIn、真实 shaping、平台 renderer 前进之前，需要把项目的中文排版思维约束写清楚，避免后续 agent 把实现改回“西文文本引擎 + 中文特例补丁”的形状。

参考阅读：

- [The Type — 「孔雀计划」序——中文排版思路的重建](https://www.thetype.com/2019/02/12498/)
- [The Type — 从「行长为字号的整数倍」说起](https://www.thetype.com/2017/07/12513/)
- [The Type — 全角半角碎碎念](https://www.thetype.com/2018/02/14211/)
- [The Type — 挤进推出避头尾](https://www.thetype.com/2018/05/14501/)
- [The Type — 中文排版网格系统的五大迷思](https://www.thetype.com/2020/01/16565/)

这些材料不是 CLREQ 的替代品。CLREQ / JLREQ 仍是规范目标；孔雀计划提供的是中文排版的工程思维顺序。

## Decision

提椠采用以下三条长期设计约束。

### 1. 字格优先

中文正文布局应以正文字号形成的字格为基础。行长、缩进、栏间距、标题占位、段落占位等概念应优先能用“占几个字 / 占几行”表达，再映射到平台像素或浮点 advance。

这意味着：

```text
ideal line width = bodyEm * lineEmCount + style adjustments
```

而不是：

```text
line width = arbitrary px box, then stretch CJK text to fit
```

`LayoutConstraints.maxWidth` 仍然保留，因为 Compose / Android / Skia 都需要实际像素约束。但 profile 与 debug 必须能表达这一行是否落在字格目标上、偏离多少、偏离原因是什么。

### 2. 加法标点

标点不是固定 1em 字符。提椠继续采用 ADR 0004 的模型：

```text
punctuation = body / ink + leadingGlue + trailingGlue
```

所有行内空间调整都应优先消费结构化 glue，而不是散落在代码里的 `advance -= 0.5em`。

OpenType `halt` / `chws` / `palt` 可以参与 atom 构造，但不能作为唯一实现。平台和字体不支持时，提椠仍需能用 profile 表、glyph ink bounds、manual override 合成合理 atom。

### 3. 可解释断行决策

避头尾不是单个断行规则，而是三个阶段：

```text
forbidden / unbreakable spans
  -> actual break choice
  -> line repair and spacing adjustment
```

因此：

- `KinsokuRule` 只描述禁止断行和禁止行首 / 行尾的事实。
- `LineBreaker` 负责生成候选行。
- `RepairResolver` 负责比较 PushIn、CarryPrevious、LeaveRagged、Hang 等候选。
- `Justifier` 负责消费 glue 做行内调整。
- `LayoutDebugInfo` 必须能解释候选、选择与失败原因。

Hang 继续遵守 ADR 0006：默认关闭，只能由 profile 显式启用。

## Consequences

- API 设计会逐步出现 em / grid / line occupancy 语义，而不是只暴露 px。
- Playground 必须能显示 natural grid、adjusted geometry、spacing decisions 和 line decisions。否则它只能证明代码跑了，不能证明排版判断合理。
- Slice 4b 的 PushIn 不能写成“把标点塞回上一行”的特例。它必须查询 `SpacingPlan` / `AdjustmentOpportunity`，确认当前行有足够可压缩 glue，才能选择 PushIn。
- UAX14 / CSS / Android / Apple / Web 行为都只是输入和对照。提椠允许针对 CLREQ profile 做 override，例如中文蝌蚪引号、破折号、省略号、分隔号的处理。
- 后续 JLREQ 支持不应重写核心 pipeline，而应新增 profile 和规则表。字格、加法标点、可解释断行这三层模型应跨 CLREQ / JLREQ 共用。

## Alternatives considered

- **完全跟随平台 TextLayout。** 否决。Android / Compose / Skia 对中文 fallback、度量、标点空间和 kinsoku 的默认行为都不足以表达提椠目标。
- **完全跟随 UAX14。** 否决。UAX14 是断行基础，但中文引号和部分标点需要 profile override。
- **网格绝对优先。** 否决。现代中文排版必须处理标点、数字和西文混排；为了纵横对齐牺牲避头尾和易读性是错误目标。
- **视觉结果优先，模型不暴露。** 否决。提椠的目标包含可调试、可审查、可由多 agent 协作维护；没有结构化决策就无法长期演进。

## Follow-up

- 行长字号整数倍量化已落地，见 ADR 0028（`LineLengthGridQuantization` /
  `GridBodyAlignment`）——grid-first 的「行长」部分。剩下的「行内内容凑整」
  （混排西文/数字用弹性空白凑到整字位）仍属远期，见 clreq-gap-audit「8 杂项」。
- 引入 line grid / em-count fixture，覆盖 12em、15em、22em 等典型行宽。
- 扩展 `LineDecisionInfo`，记录 target width、natural width、candidate repairs、chosen repair、available shrink / stretch。
- Slice 4b 实现 PushIn 时，把 `PunctuationGlue` capacity 作为前置条件。
- shaping adapter 接入后，用真实 glyph ink bounds 改进 `PunctuationAtomBuilder`。
- 在 playground HTML 中增加 grid overlay，显示 natural grid 与 adjusted cluster advance。
