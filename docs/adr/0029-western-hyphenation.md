# ADR 0029: 中西混排的西文音节连字（行尾连字符）

- Status: Accepted
- Date: 2026-06-14

## Context

中文正文里混排西文非常常见。此前长西文词是单 cluster（`LatinWordSegmentation`
只按空格切），放不下时整词突出版心。CLREQ §换行与断词连字「横排中混排的西文
单词……**在可使用连字符处之外，不得分隔为两行**」——「可使用连字符处」即西文
体例的**音节连字点**，故通用规则**允许**西文在音节点加连字符换行（只禁止在别处
硬拆）。

注意区分：§纵横对齐「行尾**强制**断行（不依音节、不加连字符）」是繁体取向的覆盖
（该节自注「简体中文较为少见」），**不是**简体默认。我们做的是前者（音节连字），
不是后者。详见 clreq-gap-audit「缺口 2」与「已知偏离」。

连字本身是平台/数据能力，不该在排版层凭印象自造。但目标平台不一：Android 有原生
断词器，JVM 桌面（测试/playground 平台）的 JDK 没有。

## Decision

**数据：内置 TeX 连字模式。** `tiqian-linebreak` 定 `Hyphenator` 接口
（`hyphenate(word): List<Int>` 给音节断点），`NoHyphenator` 为无数据默认；
`LiangHyphenator` 实现 Frank Liang 算法（TeX/浏览器同款）。JVM/Android 内置标准
`hyph-en-us`（Kuiken/hyph-utf8，宽松许可、文件头声明原样保留——**非公有领域**），
`EnglishHyphenation.enUs` 加载之，左 2 右 3。

**接入：`LineEndHangingHyphen`。** 引擎注入 `hyphenator`。**默认启用**——
中西混排常见、短行尤其受益，故引擎默认取平台连字器（`defaultHyphenator()`，
`expect/actual`：JVM/Android = bundled en-US，无内置断词器的平台退化为不连字）；显式传
`NoHyphenator` 关闭。shaping 后把每个**全字母**西文词按连字点拆成音节
子 cluster（逐音节重排，真实宽度），断行器照常在 cluster 边界断（无需改断行器）。
连字符以**占版心宽**为常态：内容只填到 `measure − 连字符宽`，连字符落在版心内；
若内容已经放不下，才退为行尾悬挂。`LineBox.hyphenAdvance` 记该行行尾连字符宽度；
引擎在某行的**下一行**起始于某连字断点（音节续接）时给该行置 `hyphenAdvance`。

## Amendment (2026-06-14): LatinForcedHyphenBreak（硬断兜底）

音节连字救不了的情况——没注入 hyphenator，或某个音节/无连字点的长 token 本身
就比版心宽——需要兜底。此时**直接补连字符然后硬断**：对任何**仍宽于版心**的
片段，在字符边界加断点（同样补显示层连字符，优先占版心宽、放不下才悬挂）。
断点**尽量满足前二后三**（`HYPHEN_MIN_LEFT=2` / `HYPHEN_MIN_RIGHT=3`，
与 en-US 连字同）——把片段首
2 字、尾 3 字保留整块、中间逐字可断；片段短到连前二后三都满足不了时，才退化为
任意字符断（满足不了就算了）。

这步在 split pass 里与音节拆分合一：cut 点 = 音节点 ∪（超宽片段的字符兜底点），
两者都进 `hyphenOffsets`、都走同一套行尾连字符几何。需要版心宽度判断片段是否
超宽，故 grid 量化（measure）上移到 shaping 之前。**默认 NoHyphenator 下也生效**——长西文词
（无音节点）照样硬断补连字符，不再突出版心。

注意与 §纵横对齐 的区别：那条是「**不加连字符**」的繁体硬切；我们这条**加**连字符
（更易读），是 CLREQ 字面之外的实用兜底（一个词放不下时总得断在某处），不是
纵横对齐那套。`latin-hard-break` fixture（`中Network`@64）印证：`中 Ne-`/`tw-`/`ork`。

## Amendment (2026-06-14): 连字是最后一档（按行松紧触发）

最初的接法是 eager——断行器在任何音节 cluster 边界即时断，能塞就塞。这不对：
连字应当是**最后手段**，排在拉伸之后。改为：断行器**优先整词换行**，只有当
（a）词本身超宽放不下（mandatory），或（b）整词换行会把这行的**汉字间距**拉得
超过 `HYPHEN_LAST_RESORT_CJK_STRETCH_EM`（**0.5em/间距**）时，才回退到音节断
（last resort）。低于阈值则宁可拉伸汉字间距、不连字。

机制落在断行器一个共享判定 `decideHyphenBreak`（greedy + lookahead 共用）：贪心
溢出后，先退到最近的**整词边界**；若该词从行首就放不下 ⇒ 必断；否则量一下整词行
的松紧（`deficit / CJK↔CJK 间距数`），超阈才在音节点断。引擎把
`hyphenBreakClusters`（哪些 cluster 前是音节/硬断续接）、`cjkInterCharBoundaries`
（可拉伸的汉字间距）、阈值喂给断行器。**不动 justifier**——「必然填满」（ADR
0004）保留：断行器在「会太松」时改用连字把行填满，justifier 只需拉 ≤0.5em；连字
救不了（没有可连词、或词太短）时，再走原来的无上限拉伸兜底。所以连字符恰好插在
「带上限的汉字间距拉伸」与「无上限兜底拉伸」之间。

松紧度量：按 CLREQ 拉伸顺序，**先扣中西间距能吸收的**（每个 CJK↔Latin 间距
0.25em 余量 = cap 0.5 − 自然 0.25；词距是二分空、已在 0.5em cap，不吸收），
剩下的才是真正落到汉字间距的增量 `cjkDeficit / 汉字间距数`，与 0.5em 比。
`decideHyphenBreak` 收 `sinoWesternBoundaries` + 每档容量；
`DecideHyphenBreakTest` 锁定「扣掉中西间距后由松转不连字」。
`hyphenationIsSkippedWhenStretchingCjkStaysTight` 锁定「够紧就不连字」，
`western-hyphenation` golden 是够松仍连字的一侧。

## Amendment (2026-07-07): AvoidConsecutiveSyntheticHyphenBreaks

连续多行都在西文词中补连字符，会显得段落被切碎；但在窄栏/长词里，断词本身仍是
合法且必要的最后手段。因此不做硬禁，只在 lookahead 评分里加入软惩罚：

- 第一处 synthetic hyphen 不罚。
- 第二处连续 synthetic hyphen 加 `consecutiveSyntheticHyphenPenalty`。
- 第三处及以后按连续 run 递增加罚。

判定只看 `hyphenBreakClusters`：也就是会生成显示层连字符的音节/硬断续接点。已有
`-` 处断行、CamelCase clean break、普通词边界都不受影响。greedy 快速模式保持原样；
它仍只做局部填满和禁则修复，不额外为了段落质感回看。

## Amendment (2026-06-14): 连字符占版心宽、放不下才悬挂

最初连字符**默认悬挂**（突出版心、不计入测量）。改为：连字符像行末标点一样
**占版心内的实宽**——连字行的内容只 justify 到 `measure − 连字符宽`，连字符落
在版心边缘内（content + 连字符 = 版心），不再默认突出。只有当内容宽于
`measure − 连字符`（超宽词、或行太窄塞不进）时，连字符才落到版心外（**悬挂**）
——「真的放不下了再悬挂」自然成立（justify 只拉不压，内容压不下去就让连字符
出界）。`western-hyphenation` golden：连字行 visual 由 160 变 144（=160−16），
汉字间距也少拉了（连字符填掉了那 16）。

标点挤压（CLREQ）：内容宽于 `measure − 连字符` 时，先**挤压本行可压的标点/词距/
中西间距 glue**（复用 PushIn 那套 `shrinkOpportunities`，按 CLREQ 挤压 tier 顺序、
扣掉 PushIn 已用的）把连字符收回版心，只有挤不动的残差才悬挂。落在 geometry 前、
并入 PushIn 的 consume map。`reservedHyphenSqueezesPunctuationGlueToPullItIn` 单测
锁定（逗号 trailing glue 被压）；行内无可压 glue（如 `中Network` 只有 autospace
间距、不在 shrinkOpportunities）时照旧悬挂——「真的放不下」。

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
  误伤合法长大写词），故**不**当人名特判，仍按普通词处理。

附带新增 **`CamelCaseBreak`**（产品名驼峰常见）：内部含大写的全字母 token
（`isCamelCase`，非缩写）在**驼峰处**断——lowercase→Upper，或缩写边界
Upper→Upper-then-lower（`XML|Http`）——**不补连字符**（大写字母本身标示断点），
≥2 字母两侧（§9.4）。clean 断点（不进 hyphenOffsets、优先于音节），故驼峰词不再
走音节连字。`latin-camelcase` fixture 印证 `用Power`/`Point做`。

附带修掉一个潜伏 bug：`punctuationAtoms` 此前对**所有** cluster 建标点 atom，
导致含 ASCII `-`/`/` 的 **LatinText cluster**（英文连字符，非 CJK 连接号）被
误当 短横线 forcedHalfWidth、占宽塌成 0.5em。改为**跳过 LatinText cluster**
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
- 这些分隔符仍是 `LatinText` cluster 内部的 clean break，不触发 CLREQ 的 CJK 行首/
  行尾禁则；ASCII 括号若包住 CJK 内容，仍由独立的 `CjkContextAsciiBracketKinsoku`
  规则处理。

这个分支和 `LatinForcedHyphenBreak` 的关系是：英文**词**仍按 hyphenator / 前二后三
补连字符；opaque token 只提供 clean break。这样链接不会出现源文本里不存在的 `-`，
长 id 也不会把前一行中文拉到极松后再整块下移。

## Consequences

- 长西文词在窄版心混排时按 en-US 音节断点换行（`in-ter-na-tion-al-iza-tion`），
  行尾补显示层连字符；短词、纯 CJK 行不受影响。
- **源文本不动**：连字符只在显示层（行尾画 `-`），source range / 复制 / 搜索保持
  输入（与码点替换同一原则）。
- 默认启用（JVM/Android=en-US）。golden/单测等确定性测试**显式 pin**
  `NoHyphenator`（同 repair fixture pin `Fixed` kinsoku 的先例）——故既有 golden
  零漂移；连字 fixture（`western-hyphenation`，`LayoutFixture.useEnglishHyphenation`）
  显式注入 `enUs`。`HyphenationLayoutTest` 锁定「默认引擎即连字」「拆分点恰等于
  hyphenator 输出」「连字符默认计入版心，放不下才悬挂」。
- 渲染：共享 skia cluster-walk（`drawTiqianGlyphs`，compose + playground 共用）与
  playground AWT 在内容末尾画 `-`；dump（golden + playground）的行尾加 `hyphen=` 标记。
- 未实现：仅 en-US（接口语种无关，按需加模式）。Knuth-Plass 式整段最优连字留作
  后续；当前是贪心/lookahead 在音节点、URL/标识串 clean 断点、必要硬断点之间选择。
- 连字符当前会预留版心宽度；只有内容挤不回 `measure − 连字符宽` 时才悬挂。若日后
  要新增“始终悬挂”或其它 discretionary-break 风格，再另记 amendment。
