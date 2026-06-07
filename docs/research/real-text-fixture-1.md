# 真实文本压力测试 1：`real-paragraph-1`

第一次让排版引擎跑一段接近正文长度的真实中文（含 Latin 词、混合标点、引号、破折号、省略号、列表式短语），观察现有模型在真实输入上的表现，并把可观察到的问题按优先级整理。这不是一次性 bug 列表，而是后续 ADR / Slice 计划的输入。

## Fixture

```text
id:      real-paragraph-1
text:    提椠（Tiqian）是一个面向中文正文的 CJK 段落排版引擎。第一阶段的目标
         不是复刻浏览器级文本系统，而是在 shaping 之后、绘制之前的薄薄一层
         里——字体 fallback、CJK 度量、标点 atom、避头尾修复、两端对齐——
         做出一个可观察、可调试、可扩展的物理模型。换句话说，「功能可以窄，
         模型必须真」。第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、
         编辑器、IME……这些不是被遗忘，而是被故意推后到模型稳定之后。
maxWidth: 320 px (16 px font ≈ 20em)
textAlign: Justify
length:   ≈220 codepoints, 14 spaces, 13 Latin runs
```

跑出来 12 行。Greedy 出 2 次 `CarryPrevious`，5 次 justification；lookahead 出 0 次 repair、8 次 justification——lookahead 在长真实文本上明显赚。

## 决策 dump 摘要

```text
[greedy   ] size=320.0×268.8  lines=12  visual-sum=3656.0  repairs=2  justifications=5
  line[0]  adj=320 visual=320 range= 0– 20
  line[1]  adj=320 visual=320 range=20– 40
  line[2]  adj=256 visual=312 range=40– 56  justify=CjkInterChar(+56.0)         ← 未填满
  line[3]  adj=320 visual=320 range=56– 76
  line[4]  adj=320 visual=320 range=76– 96
  line[5]  adj=304 visual=320 range=96–115  justify=CjkLatinSpace+CjkInterChar(+16.0)
  line[6]  adj=336 visual=336 range=115–136  repair=CarryPrevious                 ← 溢出 maxWidth
  line[7]  adj=300 visual=320 range=136–155  justify=PunctuationTrailing+CjkInterChar(+20.0)
  line[8]  adj=284 visual=320 range=155–173  repair=CarryPrevious  justify=PunctuationTrailing+CjkInterChar(+36.0)
  line[9]  adj=304 visual=320 range=173–192  justify=CjkLatinSpace+CjkInterChar(+16.0)
  line[10] adj=320 visual=320 range=192–212
  line[11] adj=128 visual=128 range=212–220  (last)

[lookahead] size=320.0×268.8  lines=12  visual-sum=3648.0  repairs=0  justifications=8
  (全部 12 行都≤maxWidth；deficit 分布更均匀；最大单行注入 +32)

spacing decisions (整段共 2 处):
  143–145 '，「'  reduction=4.0
  156–158 '」。'  reduction=4.0
```

## 观察清单

### High：真文本立刻触发，必须修

#### 1. 空格 U+0020 落到 `Unknown` → `symbol-fallback`

整段 14 个 ASCII 空格（每个中西交界点都有一个）当前在 [`CjkFontRoleClassifier`](../../tiqian-font/src/commonMain/kotlin/org/tiqian/text/font/FontPolicy.kt) 里依次：
不是 CJK 码点；不是 `isAmbiguousAsciiPunctuation`（只有 `- / ~`）；不是 curly quote；不是 CJK 标点；不是 `isLatinCodePoint`（只覆盖字母数字）；不是 `isAsciiLatinPunctuation`（刚加的括号集）；不是 emoji；`isSymbolCodePoint` 不命中（SPACE_SEPARATOR 不在 math/currency/modifier/other_symbol）。最终 → `FontRole.Unknown` → `PreferCjkForAmbiguousPunctuationResolver` 给出 `symbol-fallback`。

playground HTML 里之所以**看起来正常**，是因为 [`renderGlyphBox`](../../tiqian-playground/src/jvmMain/kotlin/org/tiqian/playground/Main.kt) 的 `else` 分支默认按 `cjk-text` 上色——纯粹是 viz bug 掩盖了 model bug。

潜在后果：

- 真实 shaping adapter 接上后，符号 fallback 字体绘制 ASCII 空格的宽度行为完全不可预测。
- cluster aggregation 在 ` CJK ` 这种序列里会切成 `[space|CJK|space]` 三块，不与左右 Latin 合并，也不与左右 CJK 合并；后续做 `CjkLatinSpace` justification 时空格 cluster 自己被独立处理，结果就是「空格 + glue 双账」。
- 空格本身归属决定了 CJK ↔ Latin 之间到底该被 justifier 视作「有 1em 空格」还是「需要再插入 CjkLatinSpace」。当前两者都发生，等于双层间距。

修复方向：空格属于「结构性分隔符」类，不是字形也不是 CJK 标点。应该新增 `FontRole.Space`（或扩 `LatinText` 的范围），并在 cluster 聚合阶段让它跟相邻 Latin run 合并。Justifier 在 CJK-Latin 边界遇到已经有空格 cluster 时不再额外加 `CjkLatinSpace`。

#### 2. `CarryPrevious` 后行宽溢出 `maxWidth`

`line[6]` greedy：`adjusted=336, maxWidth=320`。原因：[`applyKinsokuRepairs`](../../tiqian-layout/src/commonMain/kotlin/org/tiqian/text/layout/LineBreaker.kt) 把 prev 行末尾 cluster carry 到 curr 行头时，只重算 prev/curr 两侧的 `naturalWidth/adjustedWidth`，不再检查 curr 是否超 `maxWidth`。

`line[8]` 同问题：carry 完之后 `adjustedWidth=284`，但加上 justifier 的 `+36`，`visualWidth=320` 刚好打住——这次是 justifier 把溢出吞了，但**模型上仍然依赖 justifier 强行拉伸**，没有真正修复。

修复方向：CarryPrevious 应至少标记 `LineCandidate.repair` 为 `LeaveRagged + over-budget-after-carry`，或者在 `applyKinsokuRepairs` 里 carry 之后再次评估 PushIn 的可行性。最差也应该 emit 一条 `RepairCandidate.rejectionReason = "carry-overflows"` 进 debug。

#### 3. 行尾标点半宽 (`LineEndHalfWidthPunctuation`) 未实现

`line[11]` 结尾 `。`：`adjusted=128`，`。` 仍占 16f 完整 advance。但 [ADR 0004](../adr/0004-punctuation-additive-glue-model.md) 的 follow-up 与 [research/kongque-notes.md](kongque-notes.md) 明确写过「行尾标点自然半宽」是核心目标，[`PunctuationAtomBuilder`](../../tiqian-layout/src/commonMain/kotlin/org/tiqian/text/layout/PunctuationModel.kt) 也给标点设了 `trailingGlue.natural = sideGlue`——但 `LineBreaker` 在 commit 行的时候从不消耗这条 glue。

孔雀计划文章直接指出：判断是否悬挂之前**必须**先把「行尾半宽」做出来，否则悬挂只是把不齐换成更不齐。

修复方向：在 `LineCandidate` 收尾时，如果 last cluster 是 `PauseOrStop` 或 `Closing` 类，自动把 `trailingGlue.natural` 算作 0（半宽语义）。这是 ADR 0006 推荐默认开启的「严格行尾半角」，跟 Hang 没关系。

### Medium：架构债，越晚改越贵

#### 4. CjkInterChar 是 justification 的唯一兜底，单线吃饱

`line[2]` greedy 的 `+56` 是把 15 个 CJK-CJK 间隙各拉到接近 0.25em 上限。`line[8]` 也是 PunctuationTrailing 给 4f 之后 CjkInterChar 兜了 32f。在 maxWidth=320 这种「窄到中等」的栏宽下，纯 CJK 行的最大可填充量 = 字数 × 4px ≈ 64-80f，**还不足一个 em**——再短的 maxWidth（比如 240px ≈ 15em）一定会有「填不满」的行。

不是 bug，是 ceiling。但说明现在的优先链只有四级，且 PunctuationGlue + CjkLatinSpace 在纯 CJK 长段落里实际容量趋近零。

修复方向：

- 把行尾半宽（#3）做了之后，行尾「让出 0.5em」本身就是一种新的 justification capacity。
- 考虑「不可压不可伸」标点之外，对句号、逗号、引号等的 trailing glue 允许**双向**（伸+缩），让 justifier 既能借又能还。
- 长期：cluster anchor 改成 `flexAnchor`，左右 glue 都参与。

#### 5. 相邻标点压缩极稀（整段 2 处）

`PunctuationSpacingCompressor` 只在两个 atom 边界相邻时触发：`，「` 和 `」。`。但孔雀计划「挤进推出」一文明确说，传统排版「先动标点」的对象远不止 atom-atom：

- `中文，中文` 里 `，` 的 trailing glue 在「下一字不是标点」时应该可以被压缩腾给行调整（视觉上「逗号靠近后字」）。
- `中。」` 这种三连接的尾段没被处理（compressor 只看 zipWithNext）。
- 真实文本里 1em 标点造成的「空洞」不是出现在 atom-atom，而是出现在「全宽标点 + 普通汉字」的边界。当前模型对这块完全沉默。

修复方向：把 `PunctuationSpacingCompressor` 扩展为「标点 + 字符」的 trailing glue 削减，由 profile 控制最大削减量（保持密排但允许略微吸气）。

#### 6. Latin cluster 是 nominal-em 虚构宽度

`Tiqian` 在引擎里是 96px，`shaping` 是 112px，`fallback` 是 128px——每个字符都按 1em。真实 Latin shaping 大约会得到 50/55/60 px 左右。所有 `CjkLatinSpace` 注入 / `CjkInterChar` 兜底 / lookahead 评估都在这种「假宽 Latin」上做的，本身的视觉合理性**没有任何参考**。

不算 bug，因为我们明知是 stub。但意味着：

- 现在所有「这行看起来太挤 / 太松」的视觉判断都不可信。
- 接 Slice 6b shaping adapter 时所有 Latin advance 会同时变窄，每一行的 deficit、断行位置、justification 分配都会变——前面所有 fixture 的 baseline 都要重算。

不需要现在修。需要写进 Slice 6b 的「预期变化」清单。

#### 7. 弯引号 + ASCII 空格组合无测试

`「功能可以窄，模型必须真」` 在文本里的左右都是中文标点；按 `QuotePairAnalyzer` 默认 fallback 到 `CjkPunctuation`，正常。但真实写作里 `他说："Hello, world."` 这种「弯引号 + 空格 + Latin 内容」组合还没在 fixture 出现过。当 #1 修好后，应专门加 fixture 覆盖。

### Low：观察 / 未来工作

#### 8. lookahead 在真实长文本上明显赚

greedy 出 2 repair + 1 个 line overflow；lookahead 出 0 repair + 0 overflow + justification 分布更均匀。证明 [`LookaheadLineBreaker`](../../tiqian-layout/src/commonMain/kotlin/org/tiqian/text/layout/LineBreaker.kt) 默认 `window=1, futureLineHorizon=2` 这个组合在 ~200 字段落上撑得住。是积极发现，不是问题。

#### 9. `」。` 压缩工作正常

第二处 spacing reduction 落在 `「功能可以窄，模型必须真」。` 末尾，把 `」` 和 `。` 之间的内联空隙从 8px 减到 4px。视觉合理。

#### 10. 没有 fixture 之前的工作 100% 都用满了

打完 fixture 我才发现：lookahead 评分、kinsoku CarryPrevious、PushIn、Justification、QuotePair、spacing compression、bracket / Latin punctuation 分类**全部**在这一个真实段落里被同时触发并产生结果。说明前 5 个 slice 的覆盖面是真的；问题不在「功能没做」，而在「功能没经过真实文本」。

## 优先级与下一步

按上面观察排出修复顺序（成本由小到大）：

| # | 项 | 估算 | 阻塞物 |
|---|----|----|------|
| 1 | 空格 → 结构性分隔符 | 半天 | 无（纯 classifier 改） |
| 2 | CarryPrevious 溢出标记 | 半天 | 无 |
| 3 | 行尾半宽 `LineEndHalfWidthPunctuation` | 1 天 | 无 |
| 4 | 标点 + 字符 trailing glue 压缩 | 1–2 天 | 需要先确定 profile 字段（轻度 ADR） |
| 5 | flex anchor / 双向 glue justifier | 2–3 天 | 需要先做 #3、#4 |
| 6 | Latin 真宽度 | 跟 Slice 6b 一起 | 平台 shaping adapter |

**建议立刻动手的三件：#1（空格）→ #2（CarryPrevious overflow 记账）→ #3（行尾半宽）**。这三件做完后，应该重新跑同一个 fixture 拍 snapshot，对比前后视觉差别，再决定是否继续 #4 / #5 还是先做 Slice 6b。

每修一项都对照 [research/kongque-notes.md](kongque-notes.md) 的「字格优先 / 加法标点 / 可解释断行」三原则确认没有偏离。
