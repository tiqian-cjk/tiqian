# ADR 0029: 中西混排的西文音节连字（行尾悬挂连字符）

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
`LiangHyphenator` 实现 Frank Liang 算法（TeX/浏览器同款）。JVM 内置标准
`hyph-en-us`（Kuiken/hyph-utf8，宽松许可、文件头声明原样保留——**非公有领域**），
`EnglishHyphenation.enUs` 加载之，左 2 右 3。

**接入：`LineEndHangingHyphen`。** 引擎注入 `hyphenator`（默认 `NoHyphenator`
⇒ 不连字、golden 零漂移）。shaping 后把每个**全字母**西文词按连字点拆成音节
子 cluster（逐音节重排，真实宽度），断行器照常在 cluster 边界断（无需改断行器）。
连字符**悬挂**在行尾——像 CLREQ 行尾点号悬挂那样**不占版心**：内容填满版心、
连字符挂在其外，故内容的行尾对齐不被连字符破坏。`LineBox.hyphenAdvance` 记该行
行尾连字符宽度（不计入 width 字段）；引擎在某行的**下一行**起始于某连字断点
（音节续接）时给该行置 `hyphenAdvance`。

## Consequences

- 长西文词在窄版心混排时按 en-US 音节断点换行（`in-ter-na-tion-al-iza-tion`），
  行尾挂连字符；短词、纯 CJK 行不受影响。
- **源文本不动**：连字符只在显示层（行尾画 `-`），source range / 复制 / 搜索保持
  输入（与码点替换同一原则）。
- 默认 `NoHyphenator` ⇒ 既有 golden 零漂移；连字行为靠注入 `enUs` 显式开启，
  `western-hyphenation` fixture（`LayoutFixture.useEnglishHyphenation`）端到端印证，
  另有 `HyphenationLayoutTest` 单测锁定「拆分点恰等于 hyphenator 输出、连字符不计
  入版心」。
- 渲染：共享 skia cluster-walk（`drawTiqianGlyphs`，compose + playground 共用）与
  playground AWT 在内容末尾画 `-`；dump（golden + playground）的行尾加 `hyphen=` 标记。
- 未实现：仅 en-US（接口语种无关，按需加模式）；Android 原生断词器可后续接同一
  `Hyphenator` 接口。已有连字符处（`well-known`、`/`）的断点、Knuth-Plass 式整段
  最优连字，均留作后续；当前是贪心在音节点断 + 悬挂连字符。
- 连字符目前不为换行预留版心宽度（**悬挂**模型）。若日后要「连字符占版心」的风格，
  再走断行器的 discretionary-break 回退，另记 amendment。
