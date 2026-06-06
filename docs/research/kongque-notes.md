# 孔雀计划阅读笔记

本文记录 The Type「孔雀计划：中文字体排印的思路」对提椠的工程启发。它不是规范原文摘要，也不是 CLREQ 的替代品；它用于帮助实现者理解为什么提椠要采用字格优先、加法标点、可解释断行决策这些模型。

## 阅读范围

- [「孔雀计划」序——中文排版思路的重建](https://www.thetype.com/2019/02/12498/)
- [从「行长为字号的整数倍」说起](https://www.thetype.com/2017/07/12513/)
- [中文排版的最大迷思：标点悬挂](https://www.thetype.com/2017/11/13290/)
- [全角半角碎碎念](https://www.thetype.com/2018/02/14211/)
- [挤进推出避头尾](https://www.thetype.com/2018/05/14501/)
- [中文排版网格系统的五大迷思](https://www.thetype.com/2020/01/16565/)

## 总体判断

孔雀计划最有价值的地方不是给出一张可直接编码的规则表，而是提供中文排版的思维顺序：

1. 先有正文规格、字格、行长和行数，再有版心。
2. 标点不是固定全宽字符，而是字面与空隙的组合。
3. 避头尾不是一个断行布尔规则，而是不可分字段、实际断行、行内调整三件事的协作。
4. 网格是基础工具，不是牺牲易读性的形式目标。
5. Unicode / CSS / 平台默认规则是重要输入，但不等于中文排版的最终风格。

这组判断与提椠当前方向一致：提椠应该是一个可解释的 CJK 排版物理模型，而不是在平台 text layout 之上堆补丁。

## 字格优先

孔雀计划反复强调中文排版的基本单位是字格。对于正文段落，行长应以正文字号的整数倍来思考，也就是“一行多少字”先于“文本框多少 px”。西文排版通常从页面网格和比例字宽出发，中文排版则天然有一字一格的内部网格。

对提椠的影响：

- `LayoutConstraints.maxWidth` 之外，需要逐步引入字格语义，例如 `LineGrid(widthInEm, bodyEm, lineCount)` 或 profile 里的 `idealLineEmCount`。
- debug 不能只输出 float 宽度，还应能解释 `naturalWidth = N em + punctuation delta`。
- 缩进、栏间距、标题占位、段前段后等后续 API 应优先支持“占几字 / 占几行”的表达。
- fixture 应包含固定字数行长，例如 12em、15em、22em，而不是只用随机 px 宽度。

重要取舍：

- 字格优先不是“强制所有字符纵横对齐”。标点、数字、西文、避头尾都会打破局部网格；引擎应记录这种打破的原因。

## 加法标点

《全角半角碎碎念》的核心启发是：中文标点不应只按“全角 / 半角字符”理解。传统活字工艺里，可以使用半身标点，再按需要补二分空、四分空等铅空。也就是说，标点的宽度来自字面与空隙的组合。

对提椠的影响：

- ADR 0004 的 `PunctuationAtom = glyph/body + leadingGlue + trailingGlue` 是正确模型。
- `halt` / `chws` / `palt` 可作为输入或优化，但不能成为唯一依赖，因为字体支持与平台支持不稳定。
- 标点挤压不应写成“全宽先占 1em，再到处减”。应把可调空隙作为资源交给 spacing compressor / justifier。
- `SpacingDecisionInfo` 应保留自然空隙、调整后空隙、目标 range 与 reason，避免后续 agent 只看到最终 advance。

需要补充的测试方向：

- 连续标点：`：“`、`。”`、`”！`、`！！`。
- 奇数个半宽标点造成的 0.5em deficit / surplus。
- 行尾点号半宽与两端对齐同时存在。
- `PreserveInput` 与 `PreferClreqRecommendedCodepoints` 下 atom 构造一致性。

## 避头尾三步

《挤进推出避头尾》把避头尾拆成三步，这对实现非常关键：

1. 定义避头尾字符，并组合不可分字段。
2. 用不可分字段与预设行长比较，决定实际断行位置。
3. 断行后做行内调整，例如挤进、撑开、推出或可选悬挂。

对提椠的影响：

- `KinsokuRule` 只应回答事实问题：哪些位置不能断，哪些字符不能位于行首或行尾。
- `LineBreaker` / `RepairResolver` 才负责在候选行之间选择 PushIn、CarryPrevious、LeaveRagged、Hang 等策略。
- `Justifier` 负责行内调整，不应被藏进 break candidate 生成阶段。
- line debug 必须同时暴露 forbidden break、chosen repair、adjustment capacity 与失败原因。

算法顺序建议：

```text
clusters
  -> punctuation atoms
  -> unbreakable spans
  -> break candidates
  -> line attempt against ideal width
  -> repair candidates
  -> spacing / justification
  -> final line geometry
```

注意点：

- 破折号、省略号既涉及“不在中间断开”，也可能涉及避头；严格处理会带来较大调整量，需要 profile 化。
- 百分号、单位、货币符号、数字中的分节号 / 小数点、脚注号等也会形成不可分字段，不能只处理传统中文标点。
- UAX14 是基础输入，但中文 profile 需要 override。蝌蚪引号就是典型例子：Unicode 默认行为可能与中文实际习惯冲突。

## 当前阶段：标点悬挂

《中文排版的最大迷思：标点悬挂》对 Slice 4b 的帮助最大。它把“悬挂”从精致排版神话里拉回到工程位置：悬挂是避头尾的一种可选处理，不是默认合格线，也不是可以代替标点挤压和断行修复的捷径。

对提椠当前阶段的影响：

- Slice 4b 应优先实现 PushIn，而不是 Hang。PushIn 要通过压缩当前行可用的 punctuation glue 把避头标点收回行尾。
- CarryPrevious 仍是 PushIn 容量不足时的默认退路。它可能牺牲本行字距或留下 ragged 状态，但这是可解释的避头尾修复。
- Hang 只应在 profile 显式开启后进入候选集，并且需要单独解释“挂什么、挂多少、何时允许挂”。
- 强制 Hang 可能导致一行少排一个字，再把整行字距拉开，反而破坏密排和字格。
- 是否 Hang 必须先看行尾标点策略：如果已经强制行尾半宽，行尾本来就齐，Hang 可能制造新的摆动。
- “常规 / 强制”不是简单开关，而是要和标点挤压、两端对齐、行长是否为字号整数倍联动。

因此，当前阶段的工程顺序应该是：

```text
line-end punctuation half-width
  -> adjacent punctuation compression
  -> PushIn via punctuation glue capacity
  -> CarryPrevious / LeaveRagged fallback
  -> opt-in Hang in a later profile-driven slice
```

## 网格与易读性

孔雀计划反对两种极端：

- 用西式网格随手拉文本框，导致中文行长不是字号整数倍、字距不均。
- 为了纵横绝对对齐，把所有标点、数字、西文都硬塞成全宽，牺牲现代中文的易读性。

对提椠的影响：

- profile 应区分“网格优先”和“阅读优先”的风格倾向，但默认必须保证避头尾这类现代中文合格线。
- 行尾是否整齐不是单个标点能决定的；必须由整行状态、alignment、available glue、repair policy 一起决定。
- playground 需要可视化 natural grid、adjusted geometry、line target。只看最终文本是不够的。

## 与现有 ADR 的关系

- ADR 0001：孔雀计划强化了“模型必须真”的要求。source text、display text、natural geometry、adjusted geometry 必须分开。
- ADR 0003：CLREQ 推荐码点是显示层策略，不应污染 source text。
- ADR 0004：加法标点模型有传统工艺依据，应作为长期方向。
- ADR 0005：结构化 debug 是必要条件，否则无法解释“为什么这一行推入而不是推出”。
- ADR 0006：悬挂不是默认兜底。孔雀计划也强调避头尾与行内调整有多种取舍，Hang 应 profile opt-in。

## 工程待办

- ADR 0007 已固化“字格优先 + 加法标点 + 可解释断行决策”。
- 在 roadmap 中把 Slice 4b 的 PushIn 明确为“借用 punctuation glue 容量”的实现，而不是简单把标点塞回上一行。
- 增加 research fixture：22em 行宽、句号触发行尾冲突，分别观察 PushIn / CarryPrevious / LeaveRagged。
- 在 `LayoutDebugInfo` 里为 line decisions 增加 target width、actual width、repair candidates、chosen repair。
- 后续 shaping 接入后，用真实 glyph ink box 校正 punctuation atom，而不是只依赖宽度表。
