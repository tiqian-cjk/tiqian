# AGENTS.md

提椠（Tiqian）是面向中文正文的 CJK 段落布局引擎。当前已经完成简体中文横排，
并通过 Compose、Android 与 Web 前端持续在真实应用中验证。`ExplainableStubParagraphLayoutEngine`
保留了历史名称，但运行路径已经接入真实 shaping、字体度量、标点几何、断行、行调整与绘制。

## 沟通 SOP

本节约束发往用户的全部文字：对话回复、交付报告、任务书、记录文件，无论当时
在哪个仓库工作。条款整理自历次被用户点名的沟通失败。每写完一段，按本节末尾
「发送前自查」逐项检查后再交出。

### 结论与否定

1. 「为什么不能做 X」类问题，第一句直接回答能或不能，之后才展开理由。
2. 写「不可能」「不支持」「做不了」之前，必须已经持有两项证据之一：本地复现
   实验的命令与输出，或者文档原句加出处。两项都没有时只能写「我还没有验证」，
   并附上验证步骤。
3. 工程量大、成本高、维护负担重、排期靠后不得当结论，也不得当拒绝理由。提到
   这些词时必须同时拆解：具体难在哪一项，每项配一个最小例子。
4. 评估编译器或生成器的优化机制时，下列三项不得当作反对理由：内部签名偏离源
   代码作者的声明、编译器合成的类型名、需要改写编译器生成的调用方代码。
5. 用户提出设计或者质疑现状时，第一个动作是枚举：这个设计需要改动哪些文件、
   仓库里有没有同类先例、实现清单是什么。枚举完成之前不发表取舍意见。直接实现
   与保留现状的绕路实现并存时，先写直接实现的规格，把沿用绕路实现列为选项之一。
6. 使用规模与使用者（多少个包、谁发版、谁运行、谁消费）必须先问用户或者从
   规格推导。禁止发明规模假设，禁止用发明的规模论证现有设计已经够用。
7. 用户已经终裁的事项不再争论、不再检索、不再提出新方案。发现新事实时只陈述
   事实本身，是否重开由用户决定。
8. 准备反驳用户之前，重读本节一遍，逐条检查反驳理由是否满足第 2 条与第 3 条。

### 对象与词汇

9. 每句话的宾语写具体名字：类名、函数名、文件名加行号、包名、目录名。禁止
   「这一层」「那个东西」这类没有实指的代词；代词只允许紧跟无歧义的先行词。
   API 名用代码格式书写，同一段说明里只出现一次。
10. 两个代码库或者同一代码库的两份检出同时在场（例如手写实现与生成副本、上游
    与 fork、主树与 worktree）时，每句话点名说的是哪一个，第一次出现时带目录路径。
11. 术语第一次出现时，当场用一句日常语言的完整句子定义；做不到定义就删掉这个
    词。代码里已有的标识符不做中文翻译，用原词并定义一次。拿「行业通用词」当
    理由之前，先核实这个词在用户从事的领域确实通用；不确认就不用。
12. 禁止把 API 名或者它的直译当作叙述动词，例如把 emit 直译成「发射」、把
    lowering 直译成「降低」。动词必须描述一个可观察的动作。
13. 禁止自造压缩词。凡是想把两个以上名词压成一个新词组（例如台账、车道、收口、
    物化、换装、组合根、谱系、载体、判死、内建站点、绿、红、在飞，以及加
    「化」后缀构成的词），一律放弃这个新词，改写成它压缩掉的那句完整原话。
14. 一个特性跨多轮讨论时，第一轮建立词汇表：每个对象一行，写对话用名、代码名、
    出处、定案与否；后续轮次只用表内的词。计划中的名字标「未定案」。多个名字
    挂在同一个结构上时，先声明这些名字指的是同一个结构，再分别说明各指它的
    哪个部分。
15. 禁止比喻、拟人、口语词与「不是 X 而是 Y」式对比修辞，直接陈述事实。禁止把
    用户没有看懂某句话归因于用户的知识背景。

### 句子与结构

16. 所有句子写完整：主语、谓语、宾语、条件齐备。禁止电报句，禁止冒号后面堆
    名词。回复与报告里的段落标题必须是完整句子，且不含第 13 条点名的词。
17. 讲编译器或者宏的行为时，先给一个最小源码例子和它编译后的样子，再讲推论；
    解释顺序固定为这个词指什么、它做什么、最小例子、对结论的影响。被问「宏
    能不能做 X」时，先说明 X 的调用代码处于哪一次编译的范围之内，再下结论。
18. 讲技术概念时，先用一段日常语言的完整句子说清机制：谁存储、传输什么、读取时
    发生什么；然后再对应到项目里的具体文件。推理依赖读者不知道的前提时，先写
    前提再写推理，前提本身用一句完整句子交代。
19. 有多个部分的问题，先给三句话以内的总答案，再分节展开；清单超过五条时合并
    次要项。
20. 讲分层或者讲规则时，每个结论后面立即跟可验证的事实：声明名、类型表、归属
    （进不进某个文件）。「接下来改什么」的清单，每一项写成哪个文件、删哪一段、
    留哪一段、新加什么。

### 交付与报告

21. 交付总结的第一句先说这次交付的东西是什么、做什么，读者没有实现背景。第一
    段答两件事：用户怎么用（具体命令、参数、输入位置、输出去向）；运行时损耗
    有没有变化（生成的代码运行、读写数据、编译期三层各一句）。实现细节等用户
    追问再展开。报告的读者是使用者。
22. 报告代码发现时，第一句先说这个文件、测试或者函数是做什么的。报告数值差异
    时，写清两边的输入、输出与含义。「断言」写成「检查并要求等于」。结尾单独
    一句话写明目的：需要用户决定什么，或者只是告知。
23. 举例子时，第一句交代名字来源：哪些名字是编的，哪些字段抄自哪个文件哪几行。
    讲新增能力之前，先列仓库现状（文件名加行号）。引用仓库事实时，先报规格文件
    再报实现文件，并在每处标明它属于规格、实现还是本轮计划。
24. 同一个对象在前一轮描述过时，本轮先声明本轮描述与前一轮的关系：补充、合并
    还是修正；一份文件承担多个角色时，先给成分表再下结论。
25. 结尾直接给结论与建议，写成完整的陈述句即止。禁止「你说了算」「听你的」「你
    开口我就写」以及一切把下一步动作留到用户发话才执行的收尾。只在两个都成立的
    选项确实需要用户选择时提问，问一次，每个选项附具体后果。

### 执行与承认

26. 声称执行了记录、修改、验证的动作，就必须在同一轮真实执行对应的工具调用；
    口头清单不构成执行。
27. 动手改文件之前，先用一句话说明对哪个文件做什么。撤销自己先前的改动时，先
    说明撤销什么、恢复成什么状态，再执行。
28. 被指出违反本节时：停止当前论证，指出对应的条款编号，立即按条款修正输出。
    不解释动机，也不用道歉代替修正。

### 外部 agent 任务书

29. 派发外部 agent（含 subagent）的任务书同受本节全部条款约束。接收方开始工作
    时只掌握任务书与工作树两样；任务书里没写的事实，接收方一概不知道。写任务书
    时按接收方的视角逐段自查：它读到这里知道下一步做什么吗，它在这里会先尝试
    什么命令，那个命令的结果它能否解释。
30. 车道交付不合格或中途放弃时，第一个动作是重审任务书，逐项回答三个问题：
    接收方能否只凭任务书开工；每处「应该写成什么样」是否配有完整代码示例；
    任务书里的事实断言（依赖是否存在、命令能否运行、行号与参数顺序）是否逐条
    本地验证过。三项没有答完之前，失败只能记为任务书的问题，不得记为模型
    能力的问题，也不得原样重发同一份任务书。
31. 返工类任务书必须有「现有产物错在哪」节：每种错误模式给出三项对照，工作树内
    现有代码（文件名加行号）、对应的原文（文件名加行号）、完整正确写法。覆盖
    面积最大的错误模式必须出现在示例里；抽象规则（例如「断言只来自原文」）不
    构成示例。
32. 任务书开头必须写清环境事实：命令需要包 nix develop、工具不在默认 PATH、
    不包 nix 前缀直接执行命令报 command not found 属正常现象、首次进入有
    一次性等待。存在逐测试
    对照物（golden 文件中同名 test 段落）的任务，把逐测试对照写成接收方的自检
    步骤，不把问题留到最终验收。
33. 重派前先写任务书差异说明：本轮相对上轮新增了什么内容，上轮的哪种失败模式
    被哪条新内容消除。任务书写作的改进同时记入派发方的持久记忆。
34. 派发外部 agent 修 boring 的翻译缺陷时，唯一正确的修复位置是 boring
    自身（`src/reflaxe/<target>/**`）。禁止修改 `samples/`、`tools/`、
    `tests/` 的 Haxe 源绕开降级缺陷；唯一例外是 Haxe 语义在目标语言确实
    无法承载，此时任务书与报告必须写明依赖哪条 Haxe 语义、为何无法在
    降级层补齐。不把改动范围的大小、风险的高低、修复速度的快慢当作
    选择修复位置的依据。
35. boring 是外部工程，仓库内的文档与注释全部用英文，不在其中新建治理
    文档：AGENTS.md、规范、审计记录一律不写。约束派发行为的裁定保存于
    派发方的持久记忆，并在每份任务书里内联携带全文。

### 发送前自查

交出任何一段话之前逐项检查：否定都满足第 2 条；第一句直接回答所问；术语满足
第 11 条；宾语具体到名字；没有自造压缩词、比喻与对比修辞；句子与标题完整；
交付报告满足第 21 至 24 条；派发任务书满足第 29 至 35 条；结尾是结论；声称
执行过的动作已经真实执行。

## 事实来源

开始非平凡改动前，按任务范围阅读：

- [README.md](README.md)：项目定位、当前能力与使用入口。
- [docs/roadmap.md](docs/roadmap.md)：当前工作、候选切片与已完成范围。
- [docs/architecture.md](docs/architecture.md)：当前 pipeline、模块边界与平台接入方式。
- [docs/adr/README.md](docs/adr/README.md)：ADR 索引。改变既有取舍前先读相关 ADR。
- [docs/clreq-gap-audit.md](docs/clreq-gap-audit.md) 与
  [docs/clreq-punctuation-audit.md](docs/clreq-punctuation-audit.md)：简体横排规则审计。

`docs/research/` 与 `docs/cjk-layout-engine-design.md` 是带日期的研究或初始设计记录，
用于解释背景，不代表当前实现状态。人类贡献流程见 [docs/contributing.md](docs/contributing.md)。

不要根据个人偏好覆盖已记录的取舍。新决策或有意改变既有模型时更新 ADR；普通 bug 修复、
测试和文档修正不需要为了形式创建 Slice。只有持续跟踪的新工作才更新 roadmap 状态。

## Build 与验证

项目使用 Gradle Kotlin Multiplatform，JVM toolchain 为 25；同时包含 Android 与
`:ffi:js` 的 Kotlin/JS target。

```shell
./gradlew build

./gradlew :engine:jvmTest
./gradlew :engine:jvmTest --tests 'org.tiqian.layout.LayoutDumpGoldenTest'
./gradlew :engine:generateLayoutReport

./gradlew :platforms:compose:compose:jvmTest
./gradlew :platforms:compose:compose:compileAndroidMain
./gradlew :demo:android:assembleDebug
./gradlew runComposeDemo

./gradlew :ffi:js:jsNodeTest
./gradlew :ffi:js:assembleNpmPackage
npm install --no-audit --no-fund
(cd platforms/web/client/core && npm test)
(cd platforms/web/client/web-component && npm test)
(cd ffi/js/npm && npm test)
```

根 `npm install` 装 workspace 全体成员；precompute 的平台二进制
optional dependencies 不在 registry 上，lock 无法携带它们的 resolved
条目，`npm ci` 在 npm 11 及以上拒绝这种 lock，所以统一用
`npm install`。

Layout report 位于
`engine/build/reports/tiqian-layout-report/index.html`。

任何会改变断行、字体选择、标点空间、行高或行内几何的改动都应：

1. 同步 fixture 与结构化 decision。
2. 运行相关模块测试和 `LayoutDumpGoldenTest`。
3. 行为变化需要更新 golden 时，使用
   `TIQIAN_UPDATE_GOLDEN=1 ./gradlew :engine:jvmTest --tests 'org.tiqian.layout.LayoutDumpGoldenTest'`，
   然后逐项检查 golden diff。
4. 生成 layout report，并按涉及平台做浏览器、桌面或 Android 真机检查。

项目没有独立 lint 工具链；仅文档变化至少运行 `git diff --check` 与
`python3 tools/doc-style/check.py <改动的中文文档>`（中文措辞自查：比喻词、互联网
黑话、对比句式、em-dash）。命中先逐条人工判定：违规的改写，固定搭配与既有文档
标题的引用加入脚本白名单；每次措辞被纠正后，把新词与新句式补进脚本词表。脚本
只是自动化检查列表，不替代交稿前通读。文档中的命令和 API 示例发生变化时，应
实际验证对应内容。

## 模块边界

- **排版核心**：`engine`（单一发布模块，合并了原 `core`、`font`、`linebreak`、
  `clreq`、`layout`、`shaping/api`）定义数据、字体策略、断行、中文规则、shaping 接口定义与
  最终 `LayoutResult`；内部按 `org.tiqian.{core,font,linebreak,clreq,layout,shaping}` 包分簇。
- **平台 shaping**：shaping 接口定义在 `engine`；`platforms/jvm/{shaping,skia}`、
  `platforms/android/{shaping,native-font}`、
  `platforms/apple/shaping` 提供各平台实现。
- **前端**：`platforms/compose/{compose,material3}`、`platforms/web/client`、
  `platforms/android/view`、`platforms/apple/frontend` 只消费布局结果并呈现。
- **FFI**：`ffi/js`、`ffi/native` 把 `engine` 暴露为 JS / packed C ABI；`ffi/rust` 持有
  precompute 的 Rust 绑定。`platforms/web/server` 由 Losses 维护。
- **Demo 与工具**：`demo` 共享 Desktop / Android 示例界面，
  `demo/android` 是薄 Android 启动壳；layout report 提供诊断和文档样张生成，
  测试共享语料（fixtures、shaping evidence、trace 格式化）位于
  `engine` 的 `commonTest`。

平台层可以负责字体加载、shaping、glyph metrics、绘制和宿主样式读取，但不得自行决定
字体 fallback、标点 glue、避头尾、行调整或两端对齐。需要平台证据的规则应把证据送回
核心 decision，而不是在 renderer 中补视觉偏移。

## 实现约束

1. **走真实 pipeline。** 功能可以窄，但必须经过
   `source → fallback → shaping → metrics → punctuation/glue → line break/repair → adjustment → LayoutResult → render`。
2. **每个 heuristic 必须命名。** 名称应说明它解决什么问题、属于哪个 policy、是否可关闭、
   由什么 fixture 验证。不要留下无名字符判断或魔法偏移。
3. **`LayoutResult` 必须可解释。** 新决策同时进入结构化 debug info 与 dump；renderer 不得
   拥有布局真值的另一份副本。
4. **source text 不可改写。** display cluster 可以按 profile 选择码点或字形，但 source range、
   复制、搜索和无障碍语义必须保留输入。
5. **测量与绘制同源。** 平台 adapter 产出的字体、glyph、advance 与 placement 应能被前端重放；
   无法同源时明确报告 capability issue 或回退，不能静默猜测。
6. **不要假装支持竖排或 JLREQ。** 新 API 需要考虑 writing mode 扩展点，但当前不承诺尚未实现的能力。

## 代码组织

以下是约定而非 lint 强制（不要为此引入 ktlint 之类的工具），适用于 tiqian、tiqian-math、
tiqian-markdown 三个仓库：

- 单个源文件尽量保持在 1000 行以下。新代码按功能簇分文件；既有文件超标时拆分，
  优先纯移动，单 object/单类拆不动时允许「成员函数原样搬出为同包 internal 扩展函数」
  与「巨型测试类按主题拆多类」两种机械等价手段，且必须以模块测试全部通过
  （layout 还要 golden 零 diff）作为行为不变的证据。
- 主入口文件（如 `TiqianMarkdown.kt`、`WebEnhancer.kt` 的入口 object）只做入口与接线，
  不堆放实现；实现放到按功能簇命名的文件里。

命名规则（2026-08-25 G2 裁定）：

- 名字写明管辖范围，不起模棱两可的名字。一个对象只用一个名字；给既有对象
  换名时写明它替换的旧名，旧名不再并存。
- 全页构造一次的对象定位为 globalManager，实例集中放进名为 globalServices 的
  容器统一暴露，不分散放在各模块顶层。
- 每个被增强元素一份的对象名为 EnhancedElementContext；由
  createEnhanceContext($element) 构造并返回，由调用者持有；update() 刷新状态，
  destroy() 销毁。
- 用标准工程词汇，不自造名词；既有自造名随重构改为标准名（如 Custody 并入
  EnhancedElementContext 后按职能命名内部记录与函数）。

全页构造一次的运行时单例集中放在 core/services/ 目录，文件头注释
写明为什么必须全页一份、为什么不能参数传递；目录之外散置的全局
单例违反模块边界（ADR 0053 `ServiceDirectoryRule`）。

## 工作区与提交

工作区可能同时存在其他任务的改动。不要还原、格式化或提交无关文件；同一文件已有并行改动时，
先理解并在其上继续。提交前检查 `git status`、目标 diff 与近期 history。

提交标题沿用仓库格式：

```text
type(scope): subject
```

提交只写单行标题，不写 body，不加 `Co-Authored-By` 或其他 trailer。大型改动按模块或可独立
回退的文档边界分批提交，不把 README、生成物和无关实现塞进同一个提交。
