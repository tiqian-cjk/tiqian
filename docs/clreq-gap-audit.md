# CLREQ 简体横排覆盖审计

2026-06-11 对照 [CLREQ](https://w3c.github.io/clreq/) 原文逐节核对的结果。
范围：简体中文横排（项目第一阶段目标）。每条引用 CLREQ 简体原文。
第五节（标点符号与其他行内特性）与第六节（行与段落版式）全文摘录见
[research/clreq-section-5-punctuation-and-inline-features.md](research/clreq-section-5-punctuation-and-inline-features.md)
与
[research/clreq-section-6-line-and-paragraph.md](research/clreq-section-6-line-and-paragraph.md)——
引用示亡号/着重号/省略号/挤压/拉伸/禁则原文时以摘录为准。

## 已覆盖且被原文印证的

- **标点调整空间六分类**：「标点符号分为“不可调整”和“可调整”两类，“可调整”再
  根据调整空间分为六类：横排字面左、横排字面右、横排左右两侧……」——与
  `PunctuationGluePlacement`（LeadingOnly / TrailingOnly / BothSides）一致。
- **「先挤进，后推出」**：「不希望标点符号出现在行首时，应在已经标点挤压的基础上
  再次检讨是否有机会将其挤到前一行，最后没有挤压机会再从前一行取最后一个字至
  下一行。前行多出来的空间需按照优先顺序拉伸，最后没有拉伸机会再按平均拉大字距
  的方式处理。」——与 PushIn → CarryPrevious → justify 链完全对应。
- **句问叹行内挤压下限**：「位于行内的句号、问号、感叹号……最小挤为半个汉字字宽」
  ——与 body floor（halt 半宽）一致。
- **西文行边无间距**：「西文、数字出现在行首或行尾时，则无须加入空白」——
  `TextAutoSpaceLineEdgeTrim`。
- **标点旁不加中西间距**：tracking 不出现在中文点号与西文之间、开闭引号括号内侧
  ——autospace 仅 ideograph↔alpha + `GlueSideAwareJustification`。
- **着重号**：码点（●/•）、横排字底端、点号引号括号不加点、与字符居中对齐
  （疏排仍居中）——Slice 8；锚点 0.45em（2026-06-13 下移）。
- **行间标点的行距下限**（5.6.1.1）：单面装 ≥1/2 字号、双面装 ≥5/8——
  `InterlinearMarkLineSpacingFloor` + `ParagraphStyle.printingSides`
  （2026-06-13，ADR 0018 amendment；此前默认行高 1.0em 行距为 0，违例）。
- **行尾点号悬挂为非默认**：「绝大多数的中文出版物没有悬挂行尾点号的惯例」——
  ADR 0006 opt-in 立场正确（Slice 17 已实现，见缺口 6）。
- **行首行尾禁则四档**（2026-06-13 补审，初版 audit 漏列）：「可以分为四种
  级别」不处理 / 基本处理 / GB 法 / 严格处理——`KinsokuLevel` 命名对齐
  原文，默认基本处理（CLREQ「最推荐」，= 原有行为），逐档收紧分隔号行尾、
  破折号省略号行首；CLREQ 明示「行首行尾禁则规定属于排版风格……可以选择
  或者自定义」，故落为 `ClreqProfile.kinsokuMode`（`Fixed` 固定一档 /
  `MeasureAdaptive` 按行长自适应，默认后者，ADR 0025）。行首与**行尾**
  禁则均生效——行尾违禁标点（开括号；GB·严格的分隔号）用断点回退处理
  （`CarryNext`，ADR 0026）。

## 缺口（按影响排序）

### 1. 中西文间距的「无空格插入」（Insert 模式）——已解决（Slice 10，ADR 0009 amendment）

> 「原则上，汉字与西文字母、数字间使用不多于四分之一个汉字宽的字距或空白。」

作者**没有**键入空格时（`中文English中文`），仍应有 ≤1/4 em 间距。当前只实现了
Replace 模式（有 typed space 时替换为 gap）；`AutoSpaceMode.Insert` 是空挂枚举。
这是日常混排文本的正确性缺口，影响所有无空格书写习惯的输入。

### 2. 西文词距（断行 + 调整）——已解决（Slice 12，ADR 0019；挤压档随缺口 4）

> 拉伸优先顺序第一条：「西文词距……一行内若有多处……应该同时、同等量处理」；
> 挤压：「每个西文词距最小可以挤压到四分之一汉字宽」。

Latin run 目前是单 cluster：长西文句**无法换行**，词距不参与挤压/拉伸
（justify 的 WordSpace 档 no-op）。已列 roadmap 候选。

**西文音节断词（连字符换行）——已解决（ADR 0029）。** CLREQ 通用规则
（§换行与断词连字 →「横排中混排的西文单词……在可使用连字符处之外，不得分隔
为两行」）**允许**西文在「可使用连字符处」（西文体例的音节断点）加连字符换行，
只禁止在别处硬拆。落为 `tiqian-linebreak` 的 `Hyphenator` 接口
（`NoHyphenator` 无数据默认 + `LiangHyphenator` + 内置 `hyph-en-us` TeX 模式），
引擎 `LineEndHangingHyphen`：全字母西文词按音节点拆成子 cluster、行尾**悬挂**
连字符（不占版心、内容行尾对齐不破）。默认 NoHyphenator ⇒ golden 零漂移，靠注入
`enUs` 显式开启。⚠️ 不要把 §纵横对齐 的「行尾强制断行（不依音节、不加连字符）」
当作简体默认——那是繁体取向的覆盖，该节自注「纵横对齐……简体中文较为少见」。
仅 en-US、已有连字符处断点、整段最优连字留作后续。

### 3. 拉伸优先顺序与 CLREQ 有出入——已解决（Slice 11，ADR 0004 amendment：去标点档；2026-06-12 复审三条：末档去 cap 必然填满；末档为均匀 tracking——实心侧与折叠对同份额参与，不优先补齐。2026-06-16 修正一条：**标点↔西文 也在末档「剩余所有字符间距」之内、要拉伸**——此前「CjkInterChar 限定双侧 CJK」误把 §西文比例字体混排 的「均排仅调整汉字、汉字-西文」当作 tier③ 限制，实为 §纵横对齐 邻近的特例句；tier③ 只排除不可断标点字间距 + 连接号/分隔号。中西间距=汉字↔西文 仍属 tier②）

CLREQ 拉伸顺序：①西文词距 →②中西间距（1/4→1/2 em，实践常限 1/3）→
③平均拉大汉字字距。**不含「标点空隙拉伸」**——标点调整空间在 CLREQ 里只参与
挤压。当前 Justifier tier-1 是标点 glue 侧扩展（0.125em cap，来自
design doc「优先利用标点 glue」的取舍）。两个文档立场冲突，需要拍板：
跟 CLREQ（去掉 tier-1 或降为最后）还是保留项目取舍（记为有意偏离）。

### 4. 挤压侧没有优先级分层——已解决（Slice 13，ADR 0020）

CLREQ 挤压顺序：①行末标点固定半宽 →②西文词距 →1/4em →③间隔号两侧等量 →0
→④行内句问叹 →半宽（部分风格禁止）。另：「在一些排版风格中，中西间距……
不允许被挤压」。当前 PushIn 把全行标点 trailing glue 按比例摊——没有分层、
不含间隔号双侧等量挤压、不含中西间距与词距档。

已实现为六档 `ShrinkOpportunity`（严格按 tier 耗尽、同 tier 比例分摊），
其余标点 glue 作为项目扩展排最后档；风格分歧落为 `AdjustmentStylePolicy`
三开关（行末强制半宽默认 / 行内句问叹压缩 / 中西间距挤拉）。

2026-06-13 第六节全文入库后复核：最初的六档表漏了夹注外侧（原文④）与
逗顿分（原文⑤）两档、句问叹位置记错（应为最后一档⑦）、中西间距 floor
应为 1/8em 而非 0。已按七档原序修正（ADR 0020 amendment），拉伸侧补
连接号/分隔号前后不拉伸的限制。

### 5. 段首缩进——已解决（Slice 14，ADR 0021）

> 「段首缩排以两个汉字的空间为标准。若遇到杂志等多栏排版……时有改用缩排一字」；
> 「若首行行首出现开始夹注符号，可以缩减该符号始侧二分之一个汉字大小的空白。」

段落级特性完全缺失：`ParagraphStyle` 无 indent；首行行首开括号的半宽缩减是
配套规则。

已实现：首行行宽收窄 + `LineBox.indent` 渲染偏移；开括号半宽缩减不需要
实现——加法模型的行首 leading glue trim（ADR 0010）已天然给出该行为。
缩进默认随行长自适应（`MeasureAdaptiveFirstLineIndent`，2026-06-13 amendment，
ADR 0021）：窄行（measure < 14 字）缩 1 字、宽行 2 字，阈值与悬挂同默认但
独立、在 `KinsokuMode.Fixed` 下仍生效；`firstLineIndentEm`（`Float?`）为
显式覆盖。

### 6. 行尾点号悬挂——已解决（Slice 17，ADR 0006 amendment）

> 「行尾只可悬挂一个标点符号；适合行尾悬挂的标点符号有顿号、逗号及句号。
> 简体中文排版中，其余标点符号因其字面分布偏向被标注文字的一侧，也可进行
> 行尾悬挂配置。」

实现时的细则已齐：限一个、顿逗句优先、简体可扩大范围。

已实现：悬挂落在 `ClreqProfile.kinsokuMode`（`Fixed` 的 `hanging` 或
`MeasureAdaptive` 的 <14 字自动开，ADR 0025）；`LineEndHangingPunctuation`
在 kinsoku 链中排 PushIn 之后、CarryPrevious 之前；悬挂标点排除出
measure-fill（内容满排版心、标点出版心），行尾只挂一个；窄行宽（手机
正文）下避免 Carry 整字的大幅字距重摊。简体扩大范围、连续标点悬挂
留作后续。

### 7. 行间线：专名号与书名号甲式（波浪线）——已解决（Slice 16，ADR 0024）

> 「专名号（下划线）、书名号（仅指甲式的波浪线）、着重号要摆放在行与行之间……
> 合称“行间线”」；「长度应与相应文字外框一致。若两个专有名词……相邻一侧……
> 缩短……不应超过 1/8 em」；「先线后点」（与着重号同现时线贴字、点在线下）；
> 「有几个标注项目就用几条线段，不能任意从中断开，也不能用多条线段拼接」。

`DecorationSegmentInfo` 通道现成（示亡号同型），缺 `ProperNoun` / `BookTitle`
两个 kind + 相邻缩短 + 先线后点组合规则。

已实现：一项一线（行内不拆分、跨行各段独立）、长度与文字外框一致并随
justify 延长、`AdjacentInterlinearLineShortening`（相邻侧各回缩 1/16em）、
先线后点由 0.18em（线）/0.45em（点）常数序保证、行距 floor 自动生效。

### 8. 杂项（audit 级，暂不动）

- **数字+前后缀符号 符号分离禁则**——已解决（2026-06-16）：CLREQ §符号分离禁则
  「阿拉伯数字应作为整体不能拆成两行；百分/千分/度数（% ‰ ° ℃ ℉）与其前数字、
  正负号（+ - ±）与其后数字、货币符号（前置 ¥ / 后置 ₫）与数字 均不能断行」。
  落为 `NumberSymbolCohesion.unbreakableRanges(text)`（tiqian-clreq，含内部小数点/
  千分位 `. ,`），引擎并入 breaker 的 `unbreakableRanges`。**仅当该组宽度 ≤ 版心
  才生效**——比版心还宽的数字组无法整行保留，回退正常断行而非强加不可能约束。
- **中西自动间距「字母 vs 数字」按边界字符接线**——已解决（`modeForWestern`：
  边界相邻西文字符是数字→`cjkDigit`、否则→`cjkLatin`，逐侧判定；默认两者相同
  Insert，`autospaceDistinguishesLetterFromDigitAtBoundary` 单测覆盖）。
- **GB 式固定半宽标点**——已解决（ADR 0027）：「不可调整的标点包括：GB 式
  半字连接号、间隔号、分隔号，固定半个字宽」。落为 `PunctuationWidthPolicy.
  gbFixedSeparators` opt-in（连接/间隔/分隔→0.5em、glue 0 不可调）；并顺带
  引入**开明式**（`interior = Kaiming`：句中点号+夹注半字、句末点号一字）。
- **连接号按字细分宽度**——已解决（ADR 0027 amendment）：短横线（–
  U+2013 / - U+002D）占半个字位置（CLREQ 5.1.6），浪纹线 ～（一字）不变。
  落为 `forcedHalfWidth` 对短横线无条件返回 true（grid 占位，覆盖 glyph
  advance）。
- **省略号两个连用**「占四个汉字位置并须单独占一行」——`…………` 四字宽特例。
- **行长字号整数倍**——已解决（ADR 0028）：grid-first 的行长部分。向下取整
  maxWidth 到 N×fontSize 版心（`LineLengthGridQuantization`），余量按末行
  对齐在容器内摆放正文（`GridBodyAlignment`），默认开、可旁路。纯汉字行落格
  后 justify 余量归零。
- **纵横对齐（grid）的行内凑整**：西文/数字前后用 0~1/2 em 弹性空白把混排
  行内内容也凑到整字位——grid-first 的**行内内容**部分（行长部分已由
  ADR 0028 解决），远期。
- **三个以上标点连续**时禁则的放宽——**有意不做**（非缺口）。CLREQ 第六节
  注：遇连续三标点（如 `。』」`）可局部「不处理」行首行尾禁则以免字距过松，
  但原文明示「**应视为救济措施的个例，不作为推荐**」；另一 facet（纵横对齐
  时第二个起标点可居行首）是 grid 专属、尚未做 grid。其要解决的「字距过松」
  本就由 PushIn glue 压缩 + 行尾悬挂（Slice 17）缓解，故跟随 CLREQ 推荐
  路径（不放宽），见「已知偏离」末条。

## 已知偏离（2026-06-13 逐字复核）

实现与 CLREQ 原文有意/已知不一致、但非缺口的几处：

- **纯西文行可能略参差（ragged）**：CLREQ 西文词距拉伸最终宽度 ≤0.5em
  （`Justifier.wordSpaceMaxEm`，绝对 cap）；stub 把 U+0020 建模为二分空
  （0.5em，非全宽），恰在 cap 上、无拉伸余量。一行纯西文（无汉字边界、
  无中西间距）于是只有词距可调而词距已满 → 无法拉满版心，留参差。
  真字体的西文空格 <0.5em 有余量、能拉满，故此为 stub 边界情形；CLREQ
  也不对西文做字母间距拉伸（「平均拉大字距」限汉字），参差是诚实结果。
- **间隔号可调 vs GB 固定半宽**：见上「8 杂项」首条——全宽间隔号双侧
  可调是有意选的并存风格，GB 固定半宽留作 profile 选项。
- **着重号不加于数字/西文**：CLREQ 明列标点不加点（已实现），数字/西文
  未明确；我们按 `CjkText` only 加点（西文用斜体是惯例）——保守取舍，
  非原文强制。
- **连续三标点不放宽行首行尾禁则**：CLREQ 自标该放宽「不作为推荐」（救济
  个例），我们不实现，跟随推荐的完整禁则。见上「8 杂项」末条。

## 状态

缺口 1–7 全部已解决（Slice 10–17）；行尾禁则（ADR 0026）已落地；`cjkDigit`
自动间距按边界字符独立接线（CLREQ 字母/数字之分）+ 数字符号分离禁则
（`NumberSymbolCohesion`）已于 2026-06-16 补齐（见「8 杂项」前两条）。
剩下只有「8 杂项」的风格选项与远期项，不在第一阶段主线。
