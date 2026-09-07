# ADR 0029: 中西混排的西文音节连字（行尾连字符）

- Status: Accepted
- Date: 2026-06-14

## Context

中文正文里混排西文非常常见。此前长西文词是单 cluster（`LatinWordSegmentation`
只按空格切），放不下时整词突出版心。CLREQ §换行与断词连字「横排中混排的西文
单词……**在可使用连字符处之外，不得分隔为两行**」，「可使用连字符处」即西文
体例的**音节连字点**，故通用规则**允许**西文在音节点加连字符换行（只禁止在别处
硬拆）。

注意区分：§纵横对齐「行尾**强制**断行（不依音节、不加连字符）」是繁体取向的覆盖
（该节自注「简体中文较为少见」），**不是**简体默认。我们做的是前者（音节连字），
不是后者。详见 clreq-gap-audit「缺失项 2」与「已知偏离」。

连字本身是平台/数据能力，不该在排版层凭印象自造。但目标平台不一：Android 有原生
断词器，JVM 桌面（测试/playground 平台）的 JDK 没有。

## Decision

**数据：内置 TeX 连字模式。** `linebreak` 定 `Hyphenator` 接口
（`hyphenate(word): List<Int>` 给音节断点），`NoHyphenator` 为无数据默认；
`LiangHyphenator` 实现 Frank Liang 算法（TeX/浏览器同款）。JVM/Android 内置标准
`hyph-en-us`（Kuiken/hyph-utf8，宽松许可、文件头声明原样保留，**非公有领域**），
`EnglishHyphenation.enUs` 加载之，左 2 右 3。

**接入：`LineEndHangingHyphen`。** 引擎注入 `hyphenator`。**默认启用**，
中西混排常见、短行尤其受益，故引擎默认取平台连字器（`defaultHyphenator()`，
`expect/actual`：JVM/Android = bundled en-US，无内置断词器的平台退化为不连字）；显式传
`NoHyphenator` 关闭。shaping 后把每个**全字母**西文词按连字点拆成音节
子 cluster（逐音节重排，实际宽度），断行器照常在 cluster 边界断（无需改断行器）。
连字符以**占版心宽**为常态：内容只填到 `measure − 连字符宽`，连字符落在版心内；
若内容已经放不下，才退为行尾悬挂。`LineBox.hyphenAdvance` 记该行行尾连字符宽度；
引擎在某行的**下一行**起始于某连字断点（音节续接）时给该行置 `hyphenAdvance`。

## Amendment (2026-06-14): LatinForcedHyphenBreak（硬断的最终手段）

音节连字救不了的情况，没注入 hyphenator，或某个音节/无连字点的长 token 本身
就比版心宽，此时需要最终手段。**直接补连字符然后硬断**：对任何**仍宽于版心**的
片段，在字符边界加断点（同样补显示层连字符，优先占版心宽、放不下才悬挂）。
断点**尽量满足前二后三**（`HYPHEN_MIN_LEFT=2` / `HYPHEN_MIN_RIGHT=3`，
与 en-US 连字同），把片段首
2 字、尾 3 字保留整块、中间逐字可断；片段短到连前二后三都满足不了时，才退化为
任意字符断（满足不了就算了）。

这步在 split pass 里与音节拆分合一：cut 点 = 音节点 ∪（超宽片段的字符断点），
两者都进 `hyphenOffsets`、都走同一套行尾连字符几何。需要版心宽度判断片段是否
超宽，故 grid 量化（measure）上移到 shaping 之前。在默认 NoHyphenator 设置下也生效，长西文词
（无音节点）照样硬断补连字符，不再突出版心。

注意与 §纵横对齐 的区别：那条是「**不加连字符**」的繁体硬切；我们这条**加**连字符
（更易读），是 CLREQ 字面之外的实用最终手段（一个词放不下时总得断在某处），它不同于
纵横对齐那套。`latin-hard-break` fixture（`中Network`@64）印证：`中 Ne-`/`tw-`/`ork`。

## Amendment (2026-06-14): 连字是最后一档（按行松紧触发）

最初的接法是 eager，断行器在任何音节 cluster 边界即时断，只要放得下就继续放入。这不对：
连字应当是**最后手段**，排在拉伸之后。改为：断行器**优先整词换行**，只有当
（a）词本身超宽放不下（mandatory），或（b）整词换行会把这行的**汉字间距**拉得
超过 `HYPHEN_LAST_RESORT_CJK_STRETCH_EM`（**0.5em/间距**）时，才回退到音节断
（last resort）。低于阈值则宁可拉伸汉字间距、不连字。

机制落在断行器一个共享判定 `decideHyphenBreak`（greedy + lookahead 共用）：贪心
溢出后，先退到最近的**整词边界**；若该词从行首就放不下 ⇒ 必断；否则量一下整词行
的松紧（`deficit / CJK↔CJK 间距数`），超阈才在音节点断。引擎把
`hyphenBreakClusters`（哪些 cluster 前是音节/硬断续接）、`cjkInterCharBoundaries`
（可拉伸的汉字间距）、阈值喂给断行器。**不动 justifier**，「必然填满」（ADR
0004）保留：断行器在「会太松」时改用连字把行填满，justifier 只需拉 ≤0.5em；连字
救不了（没有可连词、或词太短）时，再走原来的无上限拉伸的最终手段。所以连字符正好插在
「带上限的汉字间距拉伸」与「无上限最终手段拉伸」之间。

松紧度量：按 CLREQ 拉伸顺序，**先扣中西间距能吸收的**（每个 CJK↔Latin 间距
0.25em 余量 = cap 0.5 − 自然 0.25；词距是二分空、已在 0.5em cap，不吸收），
剩下的就是落到汉字间距的增量 `cjkDeficit / 汉字间距数`，与 0.5em 比。
`decideHyphenBreak` 收 `sinoWesternBoundaries` + 每档容量；
`DecideHyphenBreakTest` 锁定「扣掉中西间距后由松转不连字」。
`hyphenationIsSkippedWhenStretchingCjkStaysTight` 锁定「够紧就不连字」，
`western-hyphenation` golden 是够松仍连字的一侧。

## Amendment (2026-07-07): AvoidConsecutiveSyntheticHyphenBreaks

连续多行都在西文词中补连字符，会显得段落被切碎；但在窄栏/长词里，断词本身仍是
被规则允许且必要的最后手段。因此不做硬禁，只在 lookahead 评分里加入软惩罚：

- 第一处 synthetic hyphen 不罚。
- 第二处连续 synthetic hyphen 加 `consecutiveSyntheticHyphenPenalty`。
- 第三处及以后按连续 run 递增加罚。

判定只看 `hyphenBreakClusters`：也就是会生成显示层连字符的音节/硬断续接点。已有
`-` 处断行、CamelCase clean break、普通词边界都不受影响。greedy 快速模式保持原样；
它仍只做局部填满和禁则修复，不额外为了段落质感回看。

## Amendment (2026-06-14): 连字符占版心宽、放不下才悬挂

最初连字符**默认悬挂**（突出版心、不计入测量）。改为：连字符像行末标点一样
**占版心内的实宽**，连字行的内容只 justify 到 `measure − 连字符宽`，连字符落
在版心边缘内（content + 连字符 = 版心），不再默认突出。只有当内容宽于
`measure − 连字符`（超宽词、或行太窄塞不进）时，连字符才落到版心外（**悬挂**），
「真的放不下再悬挂」自然成立（justify 只拉不压，内容压不下去就让连字符
出界）。`western-hyphenation` golden：连字行 visual 由 160 变 144（=160−16），
汉字间距也少拉了（连字符填掉了那 16）。

标点挤压（CLREQ）：内容宽于 `measure − 连字符` 时，先**挤压本行可压的标点/词距/
中西间距 glue**（复用 PushIn 那套 `shrinkOpportunities`，按 CLREQ 挤压 tier 顺序、
扣掉 PushIn 已用的）把连字符收回版心，只有挤不动的剩余量才悬挂。落在 geometry 前、
并入 PushIn 的 consume map。`reservedHyphenSqueezesPunctuationGlueToPullItIn` 单测
锁定（逗号 trailing glue 被压）；行内无可压 glue（如 `中Network` 只有 autospace
间距、不在 shrinkOpportunities）时照旧悬挂，「真的放不下」。

## Amendment (2026-06-14): CY/T 154-2017 §9 对齐 + 已有连字符处断词（§9.3）

**CY/T 154-2017《中文出版物夹用英文的编辑规范》§9 转行的规则**是本场景（中文
夹用英文）最直接的权威依据，比 CLREQ 更对口。逐条对齐：

- **§9.1** 中文夹英文、英文在行末尽量不拆，确需才按英文断词 → 我们的**最后一档**
  （`decideHyphenBreak`）。
- **§9.2** 按音节/构词断 + **加英文连字符**在断开词前半行尾 → 音节连字 +
  行尾连字符（`LineEndHangingHyphen`）。
- **§9.3** 带连字符的合成词**在连字符处断、一般不再加新连字符** → 本次新增
  `ExistingHyphenBreak`：含 `-` 的 Latin run 在**已有 `-` 处**拆 cluster、**不进
  `hyphenOffsets`**（不加合成连字符，已有的 `-` 自然落行尾），是 clean 断点（非
  最后一档，像词边界）。保持**两侧各 ≥2 字母**（§9.4），顺带把数字区间 `3-4`、
  缩写带数字 `COVID-19` 排除（数字不计字母数）。
- **§9.4** 不留单个字母、单音节词/人名/缩写/数字+单位不断词 → 数字已由
  `all { isLetter() }` 排除；不留单字母由前二后三（硬断）/ ≥2 两侧（已有连字符/
  驼峰）保证；**全大写缩写**（`NASA`/`HTML`，≥2 全大写）`isAbbreviation` →
  **不断词**。**单个人名**（首字母大写+小写）靠纯大小写不可靠（与句首词无法区分，
  误伤正常的长大写词），故**不**当人名特判，仍按普通词处理。

附带新增 **`CamelCaseBreak`**（产品名驼峰常见）：内部含大写的全字母 token
（`isCamelCase`，非缩写）在**驼峰处**断，lowercase→Upper，或缩写边界
Upper→Upper-then-lower（`XML|Http`），**不补连字符**（大写字母本身标示断点），
≥2 字母两侧（§9.4）。clean 断点（不进 hyphenOffsets、优先于音节），故驼峰词不再
走音节连字。`latin-camelcase` fixture 印证 `用Power`/`Point做`。

附带修掉一个潜伏 bug：`punctuationAtoms` 此前对**所有** cluster 建标点 atom，
导致含 ASCII `-`/`/` 的 **LatinText cluster**（英文连字符，非 CJK 连接号）被
误当 短横线 forcedHalfWidth、占宽被压到 0.5em。改为**跳过 LatinText cluster**
（标点 atom 是 CJK 文本的事）。`latin-existing-hyphen` fixture 印证
`out-of-/the-way`。

## Amendment (2026-07-07): LatinOpaqueTokenBreak（URL / 标识串不是英文词）

链接显示文本、URL、hash、query string、混合字母数字 id 这类 Latin run 不是英文
单词，不应该套 §9.2 的「音节 + 合成连字符」模型。它们走独立的
`LatinOpaqueTokenBreak`：

- URL-like token（`://`、`www.`、域名式 `example.com`）在 ASCII 分隔符后给
  clean 断点：`/ . - _ ? & = # % ~`。短 URL 可把 `https://` 作为一个前缀块；
  当整个 URL 已经超出版心时，`/` 也参与降级断点，避免为了保 scheme 把前一行中文
  拉得极松。
- 普通 Latin token 内的 solidus（如 `TeX/LaTeX`）也是结构性分隔符：断点在 `/`
  **之后**，slash 留在前一行（`TeX/` + `LaTeX`），不把 `/` 推到下一行行首，也不补
  合成连字符。
- 非 URL 但含数字/符号的 opaque token，只有当整个 token 超出版心时才启用这些分隔符
  断点，避免把普通短缩写/编号提前拆开。
- 若分隔符之间的片段仍宽于版心，则在字符边界硬断，**不进 `hyphenOffsets`**，也就
  **不画合成连字符**。源文本仍保持原样。
- 超长全字母 token 若整体没有可信 hyphenator 断点，或内部有一段足够长、无法被
  hyphenator 解释的连续片段，也降级为 opaque：这覆盖纯字母 base64/hash 片段、
  `ssss...herstory` 这类合成串。短全大写缩写（`NASA`/`HTML`）仍按 §9.4 不断；
  超过阈值的全大写长串不再假设是人类缩写。
- 长 opaque token 即使单独能放进一整行，也暴露 clean 字符边界；这些断点让前一行
  能带上一部分 token，避免只剩几个 CJK 字被强行拉满。普通英文词不走这个分支。
- 这些分隔符仍是 `LatinText` cluster 内部的 clean break，不因此进入 CJK
  标点几何；ASCII 开闭括号与暴露在 cluster 边缘的西文点号自 2026-08-11 起由
  ADR 0026 amendment 的 `Uax14WesternPunctuationBoundary` 提供基础断行边界。
  ASCII 点号在 hard-cut 后成为前导 cluster 时的极窄版心悬挂例外，见下一 amendment。

这个分支和 `LatinForcedHyphenBreak` 的关系是：英文**词**仍按 hyphenator / 前二后三
补连字符；opaque token 只提供 clean break。这样链接不会出现源文本里不存在的 `-`，
长 id 也不会把前一行中文拉到极松后再整块下移。

## Amendment (2026-07-12): AttachedAsciiPointMarkKinsoku

CLREQ 明确记录了西文较多的中文横排使用 U+002C COMMA `,` 作逗号或顿号的
非典型体例，又一般规定点号不得居行首。直接码点证据是 U+002C；提椠将同一断行
语义保守推广到方向明确的 `, . : ; ! ?`，不声称 CLREQ 已按码点逐个列举后五者。

这里保留两条独立的维度：

- 字体/测量方面：它们仍是 `LatinText`，保留平台 shaping 得到的比例 advance，不建
  `PunctuationAtom`，不获得 CJK glue、行尾半宽或相邻标点压缩。
- 断行方面：非 `None` 禁则档下，点号直接紧随非空白可见 cluster 时，
  `AttachedAsciiPointMarkKinsoku` 把它加入行首禁则，并与前一 cluster 形成 no-break
  边界。段首、空白或源文强制换行之后不跨边界推断。

`AttachedAsciiPointMarkSegmentation` 在初始角色分段时把前导点号 run 与后续 Latin
文本分开；`PostCutAsciiPointMarkPrefixSegmentation` 在 opaque/hard-cut 之后再做同样的
前缀分离。因此 `中文,anyway` 不会把整个 `,anyway` 绑成禁则单元，而超长 token
硬拆出的 `,A` 也不会遗漏。未硬拆的 `foo,bar` / `1,234` 仍保持原 Latin cluster；
U+0022 / U+0027 直引号无法仅凭码点判定开闭，`AttachedAsciiPointMarkKinsoku` 不猜测它们，
但 ADR 0026 的独立 UAX 边界层会按 LB19 保护两侧。

若“前一 cluster + 连续点号 run”连它所在行的可用宽度都无法容纳（包括段首缩进后的
首行），单纯 no-break 没有被规则允许的解。这个判定必须使用 breaker 实际消费的
`baseGeometry.resolveClusters()` advance，包括 ruby/注音 structural spread，不得回看 shaping 阶段的
natural advance。

该 run 此时获得具名 `AttachedAsciiPointMarkImpossibleMeasureHang` 的候选资格，但 repair 顺序
仍是 PushIn 在先、Hang 在后。只有最终 Hang 的 cluster 才在
`contextualKinsokuDecisions.impossibleMeasureFallback` 中记录该名称；若 PushIn 已将内容收回版心，
decision 不冒充“已悬挂”。run 因样式/shaping 边界分成多个 cluster 时，这些候选 cluster 可
连续延伸同一次 Hang；不放宽 profile 的普通“行尾只挂一个点号”。

最终悬挂的 cluster 仍保留原 source range 与 glyph 几何。`LineBox.hangingPunctuationAdvance`
累计整个悬挂 run 的 advance；Compose `TextOverflow.Clip` 只在该字段非零时把行的最终
`visualWidth` 视为被规则允许的绘制边界。因此 justify 把前置内容拉宽，或极窄版心下前一 cluster
自身已超宽，点号也不会被 clip 误裁。前端没有 ASCII 码点特判。

### 2026-08-11 边界分层补充

ADR 0026 amendment 已把 UAX #14 的 `EX` / `IS` 基础 no-break 边界用于非 CJK 标点，
因此 `KinsokuLevel.None` 只关闭 CLREQ tailoring，不再允许西文 `, . : ; ! ?` 自动落到行首。
`AttachedAsciiPointMarkKinsoku` 仍保留其不重复的职责：非 `None` 中文正文中记录上下文来源、
把连续点号 run 与前一可见 cluster 组织成同源 protected group，并在组本身宽于版心时提供
`AttachedAsciiPointMarkImpossibleMeasureHang`。字体面、比例 advance 与 CJK glue 仍与该规则解耦。

### 2026-08-11 BibliographicNumericLocatorBreak

文献定位串 `44(10):21-38.` 是“卷（期）：页码范围”的结构化西文内容。该串不属于英文词，
也不属于不可拆的阿拉伯数字。旧 `LatinOpaqueTokenBreak` 只有在非 URL token 自身宽于
版心（或达到长 token 阈值）时才暴露分隔符；该串能独占一行时就保持单 cluster，导致前行
只能用少量汉字间距吸收大额 deficit。

新增具名 `BibliographicNumericLocatorBreak`，只匹配严格的
`digits(digits):digits[-digits][.]` 形式，并提供两个 clean source 断点：期号开括号之前、
冒号之后。于是可以排成 `44 | (10): | 21-38.`，但每段连续数字和页码范围本身仍保持完整；
不补合成连字符，也不改写 source。普通整数、小数、千分位、日期、时间和短标识串不进入
该策略。命中的 source range、绝对 UTF-16 断点与策略名进入
`breakOpportunityDecisions` 和 layout dump。

括号边界仍由 ADR 0026 的 `Uax14WesternPunctuationBoundary` 约束，因而开括号不会被留在
行末，闭括号不会落到下一行行首。数字及前后缀单位的 `NumberSymbolCohesion` 不变。

## Consequences

- 长西文词在窄版心混排时按 en-US 音节断点换行（`in-ter-na-tion-al-iza-tion`），
  行尾补显示层连字符；短词、纯 CJK 行不受影响。
- **源文本不动**：连字符只在显示层（行尾画 `-`），source range / 复制 / 搜索保持
  输入（与码点替换同一原则）。
- 默认启用（JVM/Android=en-US）。golden/单测等确定性测试**显式 pin**
  `NoHyphenator`（同 repair fixture pin `Fixed` kinsoku 的先例），故既有 golden
  输出逐项一致；连字 fixture（`western-hyphenation`，`LayoutFixture.useEnglishHyphenation`）
  显式注入 `enUs`。`HyphenationLayoutTest` 锁定「默认引擎即连字」「拆分点正好等于
  hyphenator 输出」「连字符默认计入版心，放不下才悬挂」。
- 渲染：共享 skia cluster-walk（`drawTiqianGlyphs`，compose + playground 共用）与
  playground AWT 在内容末尾画 `-`；dump（golden + playground）的行尾加 `hyphen=` 标记。
- 未实现：仅 en-US（接口语种无关，按需加模式）。Knuth-Plass 式整段最优连字留作
  后续；当前是贪心/lookahead 在音节点、URL/标识串 clean 断点、必要硬断点之间选择。
- 连字符当前会预留版心宽度；只有内容挤不回 `measure − 连字符宽` 时才悬挂。若日后
  要新增“始终悬挂”或其它 discretionary-break 风格，再另记 amendment。

## Amendment (2026-08-14): ProgressiveTechnicalBreak

链接与行内代码由前端降为同一个 `LineBreakSpan(ProgressiveTechnical)`，核心对其西文 token
先保留 source 中已有的实际空白边界，再使用三级 clean 断点：第一档为结构符号之后与 CamelCase
hump；第二档复用当前语言 hyphenator 的音节 offset，但不进入 `hyphenOffsets`、不绘制连字符；
第三档才是 source-grapheme 安全边界的
硬断。整个 token 能否放进另一条完整行，不参与当前行的断点判定。首次 shaping 保留未断开文本的
kerning，并先暴露结构与音节断点；若 `WholeToken` 换行会使当前行正文机会超过可见拉伸上限，
`CurrentLineTechnicalTierRejection` 记录实际失败的 tier，只对该技术 span 补充 grapheme-safe 候选并重跑同一 pipeline。
超过当前行完整可用宽度的技术 segment 仍直接暴露这些必要硬断点。每档通常只有在更高档
不存在可用断点时才参与 greedy、lookahead 与 paragraph-DP 选择；若高档断点会让 span 外少数正文
机会产生任何 tracking，`ProgressiveTechnicalStretchBoundedTierFallback` 也把它视为不可用并进入
下一档；也就是 tier 降级阈值为 0。若所有 clean tier 都留有余量，必须选择最靠右的 Emergency
硬断，之后才让技术串自身吸收余量；不能保留 Structural / Syllable 再用 tracking 补齐。
fill PushIn 不得把已经选择的高档断点无条件改写成低档断点。
`ProgressiveTechnicalTierPromotionRequiresFullLine` 只允许 clean-tier promotion 在拉入后已经填满
（或需要压缩）时发生；若拉入后仍有正余量，必须保留 breaker 选中的更靠右硬断。
若上游避头尾改变了下一行起点，refill 的首个 grapheme 正好落在 cleaner tier 但仍填不满，
`ProgressiveTechnicalFillRefillSkipsIntermediateCleanerTier` 跨过这个中间边界，继续拉到下一个与原
断点同 tier 的边界；不能让旧行尾停在原地，也不能以 cleaner 标签为由制造新的大余量。
lookahead 与 paragraph-DP 可以比较 span 之前的 whole-token wrap，但一旦决定在 span 内断开，
`ProgressiveTechnicalRightmostTierBoundary` 要求它们重放 tier policy 选出的唯一最靠右边界，不能为
平滑后续行而改选同一 tier 中更早、当前行 tracking 更大的候选。

技术 span 不封闭 span 内或正文中的普通伸缩机会，所有非末行仍走同一条 Justifier。为了不把小额
余量先推给 span 外的正文，技术文本中 source 实际存在的空格提供一个额外、有上限的
`ProgressiveTechnicalWhitespaceStretch`；不足的余量继续使用既有词空格、中西间距与中文正文机会。
结构符号、CamelCase、音节与硬断边界本身只是可断点，不直接成为 glue。
正文数字与单位适用的 `NumberSymbolCohesion` 不得覆盖显式 `ProgressiveTechnical` span；URL、hash
和 inline code 中的数字仍服从同一套 Structural → Syllable → Emergency 层级。否则 raw greedy
进入数字串后会被正文数字禁则退回较早的字母数字边界，再用 tracking 补上本可由硬断占据的宽度。

实际 trim 与 justification 可能证明 breaker 的松度估算偏低。breaker 与最终正文的容许值均为
**0**：若选中的非 Emergency 技术断点产生任何 `CjkInterChar`，或借用了其他 opaque token 的
`EmergencyGraphemeTracking`，`CurrentLineTechnicalTierRejection` 拒绝这次实际失败的 tier 并重跑。
尚未失败的下一档仍按 Structural → Syllable → Emergency 参与；只有最终采用 Emergency 时，才为
行末技术 span 开放 source-grapheme tracking。它在有界空格与 inline-object 资源之后、中文正文字距
之前吸收余量；行中技术 span、后续正文和无关行不进入这一提前档。若该行末 span 没有可用 grapheme
边界，普通正文机会仍在其他路径都不能用时作为最终手段，因此这不是冻结正文或封闭 range。被拒绝 tier、候选 source offset、
最终采用的 tier、实际空格补偿与 `TerminalTechnicalEmergencyTracking` allocation 都进入结构化
debug 和 dump。

反向调整时，技术 span 与普通正文的西文词距统一遵守最小 `1/4em`，不能因 code/link 语义获得
更窄的角色特例。`ProgressiveTechnicalTierPromotion` 允许 fill PushIn 在既有普通压缩容量足够时，
把已经选择的 Emergency 边界升级到 Syllable / Structural；它只禁止相对当前边界降档，不能让更早
但因过松已被淘汰的结构断点再次阻塞升级。paragraph-DP 把同一升级作为可压缩 edge，不能另行过滤。
实际若前行的等档硬断可前移并消除 overflow，可以不消费空格容量；否则所有 compression allocation
仍遵守原有 CLREQ 顺序、下限并进入 repair debug。

`ProgressiveTechnicalWhitespaceBreakPricing` 让断点层级的松度估算先扣除候选行内实际存在的源码空格
已经拥有的有界技术伸缩量；正好落在行尾并将被折叠的空格不计入。该容量直接取自同一个
`Justifier` 配置，不能在 breaker 另写常量。paragraph-DP 提交可压缩 edge 时，promotion 也必须
比较该行未经压缩时实际选中的技术断点与最终断点；同档 Structural → Structural 或
Syllable → Syllable 仍是普通 `LineAdjustmentPushIn`，不得因更早存在低档候选而伪报升级。

## Amendment (2026-08-15): TechnicalAlphaNumericTransitionBreak 与 non-lexical 排除

`ProgressiveTechnical` 的 Structural 档增加字母↔数字边界，`Machine2Machine` 因而明确得到
`Machine|2|Machine` 两个 clean 断点；它们与符号、CamelCase 一样不补连字符。断点档序不变：
源码空白、Structural（符号/驼峰/字母数字转换）、Syllable、WholeToken、Emergency。

技术 span 的 Syllable 枚举改为逐 Structural piece 进行。命中具名强 non-lexical 证据的 piece
不交给语言 hyphenator，避免 hex/hash 被英文模式解释出无语义的“音节”断点。当前证据只包括：
`LongRepeatedLetterRun`、`LongHexIdentityRun` 与 `LongMixedAlphaNumericIdentifier`；
每项都有最小长度要求并进入
`emergencyTrackingEligibilityDecisions`。这不是“ordinary Western”分类器：默认结果是无资格，
不能因为某段文字用了 Latin 字体、没有空格、全大写或 hyphenator 没返回结果，就反推它是
技术 token。

普通西文仍按本 ADR 的单词/音节/连字符路径。只有显式 `ProgressiveTechnical` span 或命中上述
强 non-lexical 证据的 source range，才可在必要硬断后开放下一份 ADR 0023 所述的 emergency
tracking；source range、复制和搜索语义不变。
