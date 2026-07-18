# ADR 0041: 全段动态规划断行(ParagraphDpLineBreaker)

- Status: **冻结**(2026-07-18,三轮目检后收档:v3 代价下 DP 与 lookahead 在真实
  语料上基本收敛,残余收益——极窄版心灾难保险与个别孤立改善——不足以支付
  转默认、约 3–10% 端到端性能与后续边模型投入。lookahead 保持默认;DP 保留为
  实验策略、代价模型试验台与 `CatastropheGuard` 回归参照。解冻条件:真实站点
  出现 lookahead 的灾难行,或代价模型再次演进需要全局求解器验证)
- Date: 2026-07-17
- Refines: [ADR 0038](0038-neighbor-amortized-adjustment.md)(代价模型不变,本 ADR 换**求解器**)、
  [ADR 0031](0031-line-adjustment-direction.md)(「先挤压、后拉伸」不变,推入从事后级联改为解内变量)

## Context

ADR 0038 给了正确的代价模型(密度凸价 + 邻行差),但求解器是局部搜索:
`LookaheadLineBreaker` 每行只看 greedy 断点前 `window = 2` 个候选、向后模拟
`futureLineHorizon = 2` 行、当场提交。补偿传播不过两行。

`ParagraphDpReferenceExperiment`(jvmTest 参照实验:录制引擎喂给断行器的真实输入,
参照 DP 在同一输入、同一代价上求全局最优)量化了这个缺口:

- 真实中文段 + 窄版心(240px ≈ 15 字/行)下,lookahead 留下最坏行密度
  **15.67px/gap** 的灾难行,全局最优只需 1.60px/gap;
- 语料总代价保守下界(参照 DP 禁用连字符与推入边)已低 **43.8%**;
- lookahead 占优的行全部是绝对代价 < 1.5 的零钱,且源于参照实现宇宙较小
  (无悬挂/推入边),不是真实优势。

另一发现:ADR 0031 的填充推入级联(`applyFillPushIn`)是逐边界贪心,
叠在全局规划上会把规划逐格改写回贪心形态——实测把 1.1 代价的 DP 方案
还原成 46 代价的 lookahead 输出。全局求解器必须把推入收进解内,
不能留给事后级联。

## Decision

新增 `ParagraphDpLineBreaker`(`strategyName = "paragraph-dp"`,
`LineOptimizationStrategy.ParagraphDynamicProgramming` 落地):

1. **`ParagraphGlobalAmortizedOptimum`** — 以行为边、断点为节点做精确 DP。
   邻行差项使代价不可按行分离,故状态取「入边」:(行起点, 行终点,
   连字符游程桶),复杂度 O(n·w²),w 为每起点候选数(`candidateWindow = 8`
   加压缩边)。每段(mandatory break 分段)独立求解,密度跨段清零,
   与 lookahead 的 commit 语义一致。
2. **`CompressionAsDpEdge`** — 候选终点可越过自然装填点,只要超出量不超过
   该行的分档挤压容量(与 `tryPushIn` 完全相同的容量模型:正容量、
   `lineEndOnly` 仅限行末簇)。压缩行以**带符号密度**计价:拉伸
   `+deficit/gaps`、压缩 `−overflow/gaps ÷ compressBias`(Ws/Wc,
   CLREQ「先挤压、后拉伸」),凸项与邻行差项因此把「一行压、邻行拉」
   识别为它确实是的视觉跳变——这是 ADR 0038 缺失的挤压侧邻行一致性。
   commit 时压缩边经 `tryPushIn` 落地,repair 记录(分档顺序、行末削半晋升、
   allocations)与填充级联逐字节一致。本策略**不再运行** `withFillPushIn`。
3. **`KinsokuAvoidanceOverRepair`** — 有合法替代时,直接过滤会把避头尾
   违规带进解的候选终点;无替代时保留violating 终点,由共享的
   `applyKinsokuRepairs`(照常运行)修复。
4. **`SyntheticHyphenLastResortPenalty`** — 每个合成连字符断点加平坦罚分
   (默认 12),在代价驱动的优化器下保住 ADR 0029 的整词优先契约;
   连续连字符游程由 DP 状态里的游程计数(`HyphenRunStateCap = 3` 封顶)
   按 lookahead 同款递增罚分。
5. **`MandatoryBreakBindsPreviousLine`** — 段内不提供「紧邻控制符之前」的
   候选终点,零宽控制符必然随前行提交;行尾禁则退让仍走 lookahead 的
   commit 路径(`closeFilledLine` 记 CarryNext)。

进度保证:DP 无终态时回退纯 greedy 链;基线 greedy 断点始终在候选集内,
DP 在自身代价下不可能差于 greedy。

## Measured

committed 输出(走完整修复管线后)对 lookahead,同一结构性评估器:

- 语料总代价 **−30.3%**;灾难行(>5px/gap)全部消失
  (narrow@240px:46.02 → 1.97;mourning-frame:240 → 60);
- 回归全部 ≤ 1.12(px·gap 归一单位,视觉不可辨),
  已知来源:悬挂(hang)尚未进边模型 —— lookahead 可借行尾悬挂达成 0 密度;
- toy 修复 fixture(`lookahead-future-push-in` 等)与 lookahead 同分:
  参照实验在这些 fixture 上的优势是「未修复违规 + 末行免检」的假象,
  生产版老实付了修复成本,是正确行为。

## Consequences

- 默认断行器不变(lookahead)。转默认需要:悬挂边进 DP、
  三平台视觉 QA、layout report 语料目检。
- golden dump 新增 `paragraph-dp` 段(纯新增,greedy/lookahead 段零变化)。
- `tryPushIn` / `PushInResult` 由 file-private 提为 internal 供 commit 复用。
- `ParagraphDpReferenceExperiment` 保留为断行器对打的回归工具。
- 已知差距(后续切片):悬挂边、连字符宽度记账进边模型、
  compressBias 对带符号密度的折价系数需随视觉 QA 校准。

## 修订(2026-07-18):目检否决转默认——缺陷在代价模型,不在求解器

真实博客语料 + 真实宽度(360px)并排目检(多名读者一致):lookahead 观感更好,
DP 偏松、灰度不均、行间中西间距差异更大。探针复现(WTFPL 段 @360px,两侧同为 7 行,
单位 px/gap):

```text
lookahead 密度序列: 2.0, 0, 0, 0.8, 0, 0   正文行总拉伸  9.5px,中西最大 2.3px
paragraph-dp:       2.0, 1.4, 1.3, 1.2, 0, 0 正文行总拉伸 42.5px,三行中西全顶 3.9px cap
```

DP 是模型最优——模型错了,三个缺陷:

1. **`NaturalSetIsReference` 缺失**:邻行差项 `(dᵢ−dᵢ₋₁)²` 把「回到自然密排(d=0)」
   当成需要抹平的断崖,于是最优解把首行松量向后「平滑衰减」,造成松散传染。
   自然密排是参考态:一行松挨一行自然不是缺陷,多行递松才是。凸项 d² 无此问题
   (灾难行仍被正确定价),坏的只是邻行项的过零行为。
2. **`GapClassBlindDensity`**:d = 差额 ÷ 总 gap 数,但 justify 分层(中西先吃、有
   cap、CJK 后吃)。模型 d≈1.4px/gap 的行,渲染后单个中西间距已顶到 3.9px cap
   (词距近乎翻倍),模型不可见。密度需按 gap 类别分层计价,至少中西拉伸单独进
   邻行一致性。
3. **`FreeLastLine`**:末行零成本使「多断一行、把松量倒进末行」过于便宜
   (web 目检中 6→7、5→6 行的来源)。
4. **`CompressionFirstFill` 缺失**(评审补充,2026-07-18):压缩边被定价成
   最后手段,方向与 CLREQ「先挤压、后拉伸」相反。两个来源叠加:压缩边带
   `pushInPenalty = 2` 的平坦罚分(≈ 半个 cap 拉伸的代价);而 PushInFirst
   传入的 `compressBias = 1e6`(「能压就压」)被误用作密度折价除数,使密度
   项归零、只剩平坦罚分在错误方向上起效。方向偏好是引擎的策略旋钮,
   可见性是模型的度量,二者不可混用。

lookahead 的两行视野令它无法利用这些模型漏洞——此前 −30.3% 的「改进」在度量上真实,
但该度量已被证伪为感知代理。求解器本身(全段 DP、压缩进边、tryPushIn 复用)
保持不变——它把模型缺陷暴露得比局部搜索快得多,这正是保留它的价值。

### v2 代价模型(2026-07-18 实现,待目检重赛)

- `NaturalSetIsReference`:邻行差项过零门控——仅当两侧都偏离自然密排时生效,
  压缩(负)贴拉伸(正)两侧非零、照罚。
- `GapClassBlindDensity` 修复:按 justify 真实渲染分层计价——中西 gap 先吸收
  差额(每个至 `sinoWesternStretchCap` 封顶),余量落 CJK 字距,逐类凸项;
  两类都吸不动的残差回线性 raggedness。
- `CompressionFirstFill`:压缩无平坦罚分,密度与拉伸 1:1(与 fill pass 的
  ADR 0038 闸同一汇率);`compressBias` 不再参与定价。
- `FreeLastLine` 暂不动,待上述三项重赛后按数据决定。

验证:WTFPL 段 @360px 下 v2-DP 与 lookahead 收敛到同一方案(三行由推入压缩
至自然密排、仅一行 2.3px 中西拉伸),松散传染消失;灾难场景保留
(mourning-frame 240→60、narrow@240px maxD 15.67→1.45)。回归断言从「总代价
不劣」改为 `CatastropheGuard`(任一输入上 DP 最坏行密度不得比 lookahead 高
1.5px/gap;容差对应尚未进边模型的行尾悬挂,悬挂边落地后收紧到 0.5)。

### v3(2026-07-18 二次目检):邻行差项本身是错的度量,换 `StretchRunSparsity`

二次目检(240px)发现 v2 仍比 lookahead 松:DOM 实测第 4 段 DP 产生**连续三行
1.9px/gap 的拉伸块**,而 lookahead 的 6 个拉伸行全部孤立、被自然行隔开——
读者一致偏好孤立分布。根因:邻行差项奖励「相邻行拉伸相近」(diff≈0 免费),
最优解于是制造均匀拉伸块;而感知要的是**可见拉伸行的稀疏性**——孤立的
4.2px 行好过 3×1.9px 连排。ADR 0038 的原始诉求(别让一行独扛)由凸项单独
覆盖,「邻行平滑」是对该诉求的误建模。

v3:删除邻行差项,代之以拉伸游程罚(与连字符梯子同构)——连续「可见拉伸行」
(单类密度 > `VisibleStretchFloor` 0.5px/gap)按游程递增计价
(`consecutiveStretchPenalty`,默认 3,`StretchRunStateCap = 3` 封顶);
自然行与压缩行都重置游程(压缩近不可见,CLREQ 先挤压,故压缩行同样能
「隔断」拉伸带)。DP 状态从邻行密度改为(连字符游程, 拉伸游程)两个计数。

DOM 实测(第 4 段 @240px):拉伸行 6→4、拉伸 gap 54→36、最大密度持平
(4.2px)、压缩行 4→7,拉伸块消失、全部孤立;360px 全段可见拉伸行 6 vs 6
持平。灾难场景与 `CatastropheGuard` 全部保持。

### 收档结论(2026-07-18 三次目检)

v3 之后 DP 与 lookahead 在真实语料、真实宽度上基本收敛,残余差异不构成
可感收益——**这本身是本 ADR 最有价值的发现**:lookahead(窗口 2 + 两行
rollout)加上 ADR 0031 压缩优先与 ADR 0038 凸密度,已接近修正后感知模型
的最优;两行视野丢掉的全局收益集中在真实语料罕见的极窄灾难场景。两天内
被全局最优暴露并证伪的五条模型信念(松散传染、gap 类别盲、末行免检、
压缩定价倒置、邻行平滑目标本身)全部记录在案——全局求解器作为「代价模型
的试验台」的价值,大于它作为默认断行器的价值。
