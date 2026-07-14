# CLREQ 标点码点审计

本文记录提椠对 CLREQ 标点表中“同类码点、推荐码点、地区差异、特殊宽度规则”的审计，
并于 2026-07-11 按当前 profile 与 Web 字体证据路径复核，2026-07-12 补审中文正文采用
ASCII 点号的非典型体例。原则是：source text 不改写，
display text 可以按 profile 选择更合适的显示码点；分类为中文标点不等于一定替换显示码点。

参考：W3C CLREQ 附录 A 标点符号表，以及正文中破折号、省略号、连接号、间隔号、分隔号相关说明。

## 默认显示替换

默认 profile 使用 `PreferClreqRecommendedCodepoints`。以下替换只影响 layout cluster 的 `displayText`，不影响 source text、复制、搜索或 range mapping。

```text
source "……" -> display "⋯⋯"
source "——" -> display "⸺"
source "・" -> display "·"
source "‧" -> display "·"
source "•" -> display "·"
```

这些是候选 display 替换，不是无条件保证。目标字体缺字、advance 或 ink 无法满足规范几何时，
引擎会记录具名原因并回滚为 source text；Web 的两字破折号还需要 ADR 0039 规定的真实 face / glyph
证据，不能只凭 Canvas 画出了正宽字符就宣称候选成立。

理由：

- CLREQ 将 `⋯⋯` 列为省略号的 Unicode 对应形式之一，并要求省略号占两个汉字空间、六点居中。
- CLREQ 推荐 `⸺` 作为两字宽破折号，也接受两个连续 `—`。
- CLREQ 将 `·` 作为间隔号，并列出 `・`、`‧` 等历史或编码兼容写法。

## 只做语义区分，不默认替换

以下字符在 CLREQ 中有明确的标点功能或地区用法，但源码选择的码点必须保留，不能为了
统一外观默认改写。这里的“语义区分”也不等于一律改用中文字体：CJK 专有码点走
`CjkPunctuation`，可打印 ASCII 仍按后文的字体面规则走 `LatinText`，必要的中文断行语义
由独立的上下文规则补足。

```text
括号变体: 【】 〔〕 〖〗 〘〙 〚〛
连接号: ～ ~ - – —
分隔号: / ／
句号变体: ．
双叹号/双问号: ‼ ⁇
```

理由：

- 连接号在 CLREQ 中是一组功能相近但长度不同的符号，不能把 `-`、`–`、`—` 简单归一成某一个码点。
- 方头/龟甲/白方头括号等变体是明确的中文开闭夹注符号，应参与 Opening/Closing
  glue、禁则、行首行尾半宽 trim；但源码选择哪一种括号具有语义/风格，不默认替换。
- `/` 和 `／` 有地区差异；CLREQ 说明 `/` 主要用于中国大陆，`／` 主要用于繁体中文。默认替换需要 region profile 参与。
- `．` 既可出现在中文句号表中，也可能在数字、外文、技术文本中有别的语义；不应无上下文替换成 `。`。
- `‼` 和 `⁇` 是独立码点，CLREQ 描述的是宽度和占位，不是把多个叹号或问号替换为这些码点。

## 行首禁则的范围

CLREQ 行首行尾禁则分四档（`KinsokuLevel`，命名对齐第六节原文：不处理 /
基本处理 / GB 法 / 严格处理）。`KinsokuMode.Fixed` 可以固定任一档；默认
`KinsokuMode.MeasureAdaptive` 按版心行长在基本处理、GB 法与严格处理间解析，并在窄行
启用顿逗句悬挂。基本处理禁于行首：点号（PauseOrStop）、结束引号括号（Closing）、
间隔号/中点/连接号/分隔号（居中分隔类，行首观感破碎）。

破折号与省略号在 **基本处理 / GB 法** 下**允许**行首——CLREQ 对它们的
保护是「不得以适配分行之由断开或拆至两行」（不拆，而非禁首），对话破折号
天然出现在行首；其不可拆分由 display 替换（`——`→`⸺`、`……`→`⋯⋯`
单 cluster）结构性保证。只有 **严格处理** 才追加「破折号、省略号不得居
行首」；分隔号居行尾的禁则则在 **GB 法 / 严格处理** 追加。

## 后续需要 profile 化的事项

- Mainland / Traditional profile 下 `/` 与 `／` 的显示偏好。
- 连接号在日期、范围、外来词、表格编号等语义中的不同宽度。
- `！！！`、`？？？` 的二字宽压缩策略（整组占两字宽的专门规则）。注意：这条推迟的
  只是「整组二字宽」策略本身；连用点号的**逐对挤压**是简体横排的预期行为，
  `PunctuationSpacingCompressor` 对 `！！` 这类相邻对照常折叠。
- 竖排时破折号、省略号、连接号顺时针旋转 90 度。
- 简体横排常用弯引号，繁体和竖排常用角引号；这属于 writing mode 与 region policy，不应作为当前横排默认替换。

## 字体面归属（中西共用码点）

字体**面**（Latin vs CJK）是码点问题，不是字形问题。中西真·共用码点只有
弯引号 U+2018–201D，按上下文判定（两侧 Latin → Latin 面，否则 CJK 面）；其余各归各：
所有可打印 ASCII（U+0020–007E，含 `% . , : ; - / ~ | \` 等）是 typed Western intent →
**Latin 面**；CJK 专有码点（`—` U+2014、`…` U+2026、`、`、全宽 `FF**`、`·`、`•`）→
**CJK 面**。判定在 `CjkFontRoleClassifier`。

历史 drift（已收回）：曾把 ASCII `- / ~` 误塞 `isCjkPunctuationCodePoint` 并给它们加
`isLatinTechnicalPunctuation` 上下文补丁，其余 ASCII 标点漏到 `Unknown` → CJK 面，
导致 `%` 等用中文字体渲染（全宽）。

禁则例外（不改变字体面）：`CjkContextAsciiBracketKinsoku` 只在 ASCII `()[]{}` 成对且
内部含 CJK 文本/标点时，把开括号加入行尾禁则、闭括号加入行首禁则。这样
`份额(国产品牌)，` 不会断成行首 `)，`，但 `(` / `)` 仍用 Latin 字体，不进入中文
标点 glue / atom 模型。

另一项禁则例外是 `AttachedAsciiPointMarkKinsoku`。CLREQ 明确记录了西文较多的中文横排
采用 U+002C COMMA `,` 作为逗号或顿号的非典型体例；这是直接的码点证据。
CLREQ 另一般规定点号不得居行首，提椠因此将同一语义推广到方向明确的 ASCII
点号 `, . : ; ! ?`；后五者是项目策略，不冒充 CLREQ 已按码点逐个列举。这些点号
形成独立 cluster 且**直接紧随非空白可见文字**时，在 `Basic` / `GbStyle` /
`Strict` 下加入行首禁则，并与前一 cluster 形成 no-break 边界。这样既覆盖中文正文采用
半角点号，也覆盖超长 Latin token 硬拆后暴露出的 comma cluster。它们仍保持 Latin face、
平台 shaping 得到的比例 advance，也不进入 CJK
`PunctuationAtom`、glue、行尾半宽或相邻标点压缩。它们不加入 profile 的常规点号
悬挂集；仅当“前一 cluster + 连续点号 run”按 breaker 实际使用的几何（含注音/
ruby spread）仍无法容纳时，才具备极窄版心悬挂资格。repair 仍先尝试 PushIn；
只有最终确实选中 Hang 的 cluster 才在结构化 decision 中记录
`AttachedAsciiPointMarkImpossibleMeasureHang`。连续 run 因样式边界分成多个 cluster 时可延伸同一次
具名 Hang；profile 的普通悬挂仍只挂一个点号。`KinsokuLevel.None` 显式关闭整条规则。

`AttachedAsciiPointMarkSegmentation` 与 `PostCutAsciiPointMarkPrefixSegmentation` 只把这种
前导点号 run 与其后的 Latin 文本分开，包括二次 hard-cut 才产生前导点号的情况，避免
`中文,anyway` 因一个禁则把整个 `,anyway` 绑成 offender；普通 `foo,bar`、`1,234`、URL、
`%`、`- / ~` 的既有 Latin 分段不变。U+0022 / U+0027 直引号没有开闭方向信息，不在本
规则中猜测；弯引号继续由 `QuotePairAnalyzer` 成对判定。
前端不按 ASCII 码点补逻辑；Compose `TextOverflow.Clip` 仅在 `hangingPunctuationAdvance`
非零时将该行的最终 `visualWidth` 视为合法绘制边界，确保 justify 后的点号或前字自身
超宽时都不会被误裁掉。

### 已知限制：ASCII 符号紧贴 CJK 的竖向对齐

Latin 字形按小写基线设计，`/ \ | ~` 等竖向延展符号**无空格**直接夹在汉字之间时会
**靠下**，不像 CJK 标点那样字身框居中。正文里这种紧贴罕见（多见于表格/路径/代码），
且最常见的带空格分隔 `中文 | 英文` 两侧本就是 Latin、不会被「两侧 Latin 才用 Latin」
之类的上下文规则纠正，故**暂不做**符号级上下文感知/居中（评估后认为得不偿失）。归
CLREQ 中西基线对齐范畴，与竖排/JLREQ 一并搁置，待真实正文语料触发再议。
