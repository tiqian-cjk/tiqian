# Tiqian 布局一致性套件（conformance suite）

- Schema 版本：**1**（fixture JSON 的 `schema` 字段；不匹配的实现必须拒绝加载）
- 消费方式：任何引擎实现（Kotlin、Rust、其他）读取 `fixtures/` 下的输入，
  按本文规格复算布局，产出与 `dumps/` 逐字节一致的结构化 dump。
- 变更纪律：fixture、dump、本文三者的任何改动同一提交落地，diff 像 golden
  一样逐项 review。Kotlin 侧回归入口：
  `TIQIAN_UPDATE_GOLDEN=1 ./gradlew :engine:jvmTest --tests '*LayoutDumpGoldenTest*'`。

## 1. Fixture 格式（`fixtures/*.json`）

每个文件一个段落用例。字段与默认值（省略字段取默认）：

| 字段 | 类型 | 默认 | 语义 |
| --- | --- | --- | --- |
| `schema` | int | 必填 | 本文版本号，当前为 1 |
| `id` | string | 必填 | 用例名，与文件名、dump 首行一致 |
| `text` | string | 必填 | 源文本（不可改写，见引擎不变量） |
| `maxWidth` | float | 必填 | 容器宽 px |
| `maxHeight` | float | +∞ | 容器高 |
| `maxLines` | int | ∞ | 行数上限（`MaxLinesLineTruncation`） |
| `lineHeight` | float? | null | 请求行高；null 走引擎默认 |
| `decorations` | `{start,end,kind}[]` | [] | `kind` ∈ `DecorationKind` 枚举名 |
| `rubySpans` | 见下 | [] | 拼音/注音 |
| `rubyLineHeightMode` | string | `PerLine` | `RubyLineHeightMode` 枚举名 |
| `firstLineIndentEm` | float? | 0 | 段首缩进（字）；配合 `firstLineIndentDefault` |
| `firstLineIndentDefault` | bool | false | true = 走 `MeasureAdaptiveFirstLineIndent` 默认（此时忽略上项） |
| `pinBasicNoHang` | bool | false | 钉死 kinsoku 为 Fixed(Basic, 不悬挂) |
| `useEnglishHyphenation` | bool | false | 注入内置英文断词器（ADR 0029） |
| `lineLengthGridEnabled` | bool | true | 整数 ic 行长网格 |
| `lineLengthGridBodyAlignment` | string? | null | `LastLineAlignment` 枚举名；null=跟随末行对齐 |
| `lineBreakSpans` | `{start,end,policy}[]` | [] | `policy` ∈ `LineBreakPolicy`（如 `ProgressiveTechnical`） |

`rubySpans` 元素：`{start,end,text,fontFamilies=[],kind="Pinyin"|"Bopomofo",locale,localeExplicit=false}`；
`localeExplicit=false` 时 locale 取引擎默认（注音 `zh-TW`，拼音 null）。
所有 `start/end` 均为 UTF-16 码元下标、end 开区间——与引擎 `TextRange` 一致。

未出现的输入维度（spans 字号/字重、inline box/object、autoSpaceSuppressedRanges 等）
属于 schema 的未来扩展；扩展必须递增 `schema` 并同步本文。

## 2. 确定性度量模型（免字体）

一致性套件运行在**确定性 stub shaper** 上（Kotlin 参考实现
`ExplainableStubTextShaper`），完全不依赖平台字体与 shaping 库：

- 段落字号取引擎默认 `TextStyle.fontSize = 16`（fixture 目前不覆写）。
- cluster advance = `fontSize × nominalAdvanceEm(source, display)`：
  - 二倍破折 `⸺`（U+2E3A，source 或 display 任一）→ **2 em**；
  - 纯空格串（全部 U+0020）→ **0.5 em × 长度**（简中网格里的二分空）；
  - 其余 → **max(源码点数, display 码点数) × 1 em**。
  - 码点计数按 Unicode code point（代理对算一个）。
- 字形模型：每个 display 码点一枚字形，advance 均分，`x = i × 均分值`，
  id 为区间内序号；**不提供墨迹盒**（所有字形报告为无 ink bounds，
  下游标点几何因此走 `ProfileGlueFallbackWithoutFontGeometry` 路径）。
- 真实字体/HarfBuzz 的跨实现对齐是 **v2** 范畴（需钉字体文件与 shaper 版本，
  参见 `docs/research/2026-08-20-harfbuzz-version-differential.md`），本版不承诺。

## 3. Dump 格式（`dumps/*.txt`）

文本格式，一 fixture 一文件。结构：

```
fixture: <id>
text: <escaped text>
maxWidth: <float>
== greedy ==
<records…>
== lookahead ==
<records…>
== paragraph-dp ==
<records…>
```

三个 section 对应三种断行器，各自输出同一组记录类型（按出现顺序）：

- `size WxH` — 最终 `LayoutResult.size`。
- `kinsoku measure=… level=… hang=… reason=…` — 避头尾档位决策。
- `line[i] start-end natural=… adjusted=… visual=… repair=… candidates=… justify=…`
  — 行盒；`justify=` 后逐项列出拉伸机会 `类型@行内序+量`。
- `cluster start-end 'text' adv=…` — 显示簇与其（含调整后）advance。
- `font start-end role=… key=… display=… sub=…` — 字体角色决策与标点字形替换。
- `punct … class=… adv=… body=… lead=… trail=… anchor=… source=…` — 标点几何账本。
- `geom … body=… lead=…/… trail=…/… justify=… resolved=…` — 标点几何终值。
- `autospace range side=… boundary=… reduction=…`（或 mode/reason 变体）— 中西间距决策。
- `edgetrim … side=… trim=… reason=…` — 行端空白修剪。
- `linespacing natural=… requested=… resolved=… floor=… applied=… reason=…` — 行距决策。
- 其余记录类型（repair、ruby、hyphen、maxlines 等）在启用对应特性的 fixture 中出现，
  字段命名与上同风格：`键=值`，浮点一位小数，区间 `start-end` 开区间。

数值格式：浮点按 Kotlin 参考实现的一位小数输出（`%.1f` 语义，
四舍六入五成双以 IEEE float 计算为准）；实现间以**逐字节 diff** 判定一致。
本文与 49 份既有 dump 互为规格与样例；描述有歧义处以 dump 为准并回填本文。

## 4. 工作流

- **Kotlin（参考实现）**：`./gradlew :engine:jvmTest --tests '*LayoutDumpGoldenTest*'`
  从 `fixtures/` 加载、双向复算、与 `dumps/` 比对。
- **其他实现**：读 `fixtures/`，产出各自 dump，与 `dumps/` diff；差异要么是实现 bug，
  要么升级为对本规格的 issue。
- **新增用例**：直接添加 JSON（`schema: 1`），跑 Kotlin 参考实现生成 dump
  （`TIQIAN_UPDATE_GOLDEN=1`），review 后提交三件套。
