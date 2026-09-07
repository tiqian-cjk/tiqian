# TsHostRuntime 完成路径分片规划

本文档规划 ADR 0053（`docs/adr/0053-web-prose-host-consolidation.md`）中 `TsHostRuntime` 的剩余移植路径，明确从当前 Kotlin/JS 宿主运行时到纯 TypeScript 宿主运行时的分片实施方案、测试验收映射与构建系统处置。

## 1. 现状到目标的差距清单

当前 `frontend/web/npm-core/core/engine/face.js` 导出的宿主入口函数通过 `frontend/web/npm-core/core/engine/loaders/runtime-loader.js` 读取 Kotlin/JS 编译产物中的 `TiqianEngine`（[WebEnhancerEngineExport.kt:15](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerEngineExport.kt#L15)）。目标是将该运行时完全重写为 TypeScript 实现，彻底移除 Kotlin 主线程运行时（`frontend/web/src/jsMain` 下 18 个 Kotlin 源文件，共 2943 行）。

以下列出 Kotlin 侧尚无 TypeScript 对应实现的状态与逻辑项，逐项标注源码位置：

### 1.1 RootState 生命周期与状态维护
- **弱引用根状态表**：[WebEnhancer.kt:32-33](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L32-L33) 以 `WeakMap` 持有各根元素（`HTMLElement`）对应的 `RootState` 实例。
- **状态对象构造与更新**：[WebEnhancer.kt:199-251](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L199-L251)（`createRootState`）解析选项并实例化三套排版引擎；[WebEnhancer.kt:558-594](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L558-L594) 定义 `RootState` 数据结构（包含 `root`, `options`, `engine`, `semanticExactEngine`, `browserFallbackEngine`, `paragraphs`, `issues`, `preparedDomEnabled`, `preparedDomFallback`）。
- **状态发布至 DOM 属性**：[WebEnhancer.kt:271-291](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L271-L291)（`publishState`）向根节点同步 `data-tiqian-enhanced`、`data-tiqian-enhanced-count` 与 `data-tiqian-issue-count`。
- **根节点销毁与断开连接**：[WebEnhancer.kt:160-187](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L160-L187)（`destroy`）取消任务、逐段调用 custody 恢复原始 DOM、清理 issue 标记并移除根属性；[WebEnhancer.kt:194-197](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L194-L197)（`detach`）在单页路由切换时取消任务并释放样式。
- **排版重排与样式刷新**：[WebEnhancer.kt:301-390](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L301-L390)（`relayout`）与 [WebEnhancer.kt:398-405](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L398-L405)（`refresh`）。
- **未渲染遗留段落提取**：[WebEnhancer.kt:293-299](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L293-L299)（`strandedSourceParagraphs`）。

### 1.2 引擎选择与构造逻辑
- **三套排版引擎实例装配**：[WebEnhancer.kt:208-241](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L208-L241) 根据是否存在精确字体会话构造 `browserEngine`、`engine` 与 `semanticExactEngine`。
- **逐 run 浏览器降级适配器**：[WebEnhancerSupport.kt:149-171](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L149-L171)（`ExactSessionBrowserFallbackTextShaper` 与 `ExactSessionBrowserFallbackFontMetricsResolver`），在精确字体会话遇到未覆盖字体或字形时单独将该 run 回退至浏览器度量与离屏 canvas 塑形。
- **精确会话能力异常匹配**：[WebEnhancerSupport.kt:136-141](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L136-L141) 与 [WebEnhancerSupport.kt:483-490](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L483-L490)（`EXACT_FONT_SESSION_CAPABILITY_FAILURES`）。

### 1.3 段落 prepare / commit 布局管线
- **段落处理主入口**：[WebEnhancerParagraphPipeline.kt:89-227](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L89-L227)（`processParagraph`），包含样式捕获、降层调用、托管接管、Worker plan 尝试与同步排版分发。
- **排版准备阶段**：[WebEnhancerParagraphPipeline.kt:319-498](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L319-L498)（`prepareParagraphLayout`），包含网格有效度量计算、`LayoutInput` 组装、prepared DOM 桥可用性核验、语言属性一致性检查、引擎排版执行、字形 advance 有效性校验以及跨行克隆装饰检测。
- **排版提交阶段**：[WebEnhancerParagraphPipeline.kt:500-584](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L500-L584)（`commitPreparedParagraph`），包含调用 prepared DOM 桥执行渲染、调用校验器比对、精确会话校验失败时回退浏览器度量重排并再次提交，以及提交成功后的标记盖戳。
- **Worker 准备结果提交**：[WebEnhancerParagraphPipeline.kt:266-313](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L266-L313)（`commitWorkerPreparedParagraph`）。
- **同步排版分发**：[WebEnhancerParagraphPipeline.kt:229-264](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L229-L264)（`layoutParagraph`）。
- **管线准备与提交结果类型**：[WebEnhancer.kt:596-612](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L596-L612)（`ParagraphLayoutPreparation` 与 `ParagraphCommitResult`）。

### 1.4 Capability Issue 收集与上报
- **Issue 写入与清理**：[WebEnhancerParagraphLifecycle.kt:13-28](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L13-L28)（`reportIssue` 设置 `data-tiqian-capability-issue` 与 `data-tiqian-capability-detail` 并输出控制台警告）；[WebEnhancerParagraphLifecycle.kt:155-168](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L155-L168)（`clearIssue` 与 `restoreAttribute`）。
- **Issue 数据结构**：[WebEnhancer.kt:626-635](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L626-L635)（`CapabilityIssue`）。
- **共享样式就绪校验**：[WebEnhancer.kt:134-150](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L134-L150)（`rejectMissingSharedRuntimeStyles`，上报 `MissingSharedRuntimeStyles`）。
- **事件派发辅助**：[WebEnhancerSupport.kt:433-464](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L433-L464)（`dispatchTiqianReady`, `dispatchTiqianRelayoutReady`, `dispatchTiqianProgressiveError`）。

### 1.5 ProgressiveRelayoutSession 与渐进状态机接入
- **重排会话实现**：[WebEnhancer.kt:407-477](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L407-L477)（`ProgressiveRelayoutSession`），在分片执行期间收集 `CustodyLiveSnapshotJs`、记录成功度量与未支持 issue，支持在发生异常时调用 `custodyBridge().rollback()` 回滚全部节点。
- **渐进作业构造与事件衔接**：[WebEnhancerProgressiveJob.kt:16-118](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerProgressiveJob.kt#L16-L118)（`startProgressiveJob`, `finishProgressiveJob`, `failProgressiveJob`, `dispatchProgressiveSummary`）。

### 1.6 Worker 请求拼装与元数据序列化
- **Worker 布局请求构造**：[WebEnhancerParagraphPipeline.kt:28-87](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphPipeline.kt#L28-L87)（`workerLayoutRequest`）与 [WebEnhancerSupport.kt:21-135](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L21-L135)（`workerLayoutRequestJson`），将 lowered 段落序列化为分隔符编码的字段结构（包含 `textSpans`, `inlineBoxes`, `lineBreakSpans`, `inlineObjects`, `semantics` 等）。
- **富文本渲染元数据序列化**：[WebEnhancerSupport.kt:378-426](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L378-L426)（`preparedSemanticReplayJson`, `preparedInlineObjectMetaJson`, `preparedCjkStrongSemanticsJson`）。

### 1.7 Markdown 降层解码层
- **桥接返回值的 Kotlin 类型解码**：[MarkdownParagraphLowering.kt:36-243](frontend/web/src/jsMain/kotlin/org/tiqian/web/MarkdownParagraphLowering.kt#L36-L243) 将 `markdown-lowering.js` 返回的 JS 纯对象反序列化为 Kotlin 的 `LoweredParagraph`, `TextStyle`, `TextSpan`, `DecorationSpan`, `InlineBoxSpan`, `InlineObjectSpan`, `DomInlineObject`, `DomSourceSpan`, `DomInlineBoxStyle`, `LineBreakSpan` 等强类型实例。

### 1.8 宿主生命周期辅助、选项与 Reconcile 编排
- **JS 选项解析**：[WebEnhancerParagraphLifecycle.kt:30-76](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L30-L76)（`optionsFromJs` 与 `optionFloat`）。
- **DOM 内容盒测量与尺寸稳定化**：[WebEnhancerParagraphLifecycle.kt:78-84](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L78-L84)（`captureSourceInlineSize`），[86-90](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L86-L90)（`applyConfiguredHostFontSize`），[92-119](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L92-L119)（`responsiveSourceMeasure`），[121-153](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerParagraphLifecycle.kt#L121-L153)（`stabilizeContentSizedItemInlineSize`）。
- **内容变化 Reconcile 编排**：[WebEnhancerContentReconcile.kt:16-95](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerContentReconcile.kt#L16-L95)（`probeContentDrift` 与 `reconcileContent`，将 `content-reconcile.js` 的判定结果转化为具体 DOM 恢复与重新处理动作并提交渐进任务）。
- **引擎与 Worker 导出桥**：[WebEnhancerEngineExport.kt:14-56](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerEngineExport.kt#L14-L56)（`TiqianEngine`）与 [WebEnhancerWorkerProtocol.kt:29-52](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerWorkerProtocol.kt#L29-L52)（`TiqianWebWorkers`）。

---

## 2. 分片移植方案

为保证重构过程中的可验证性与持续可运行状态，将剩余的 Kotlin 主线程运行时拆分为 7 个串行推进的分片（Slice）。

协调器（`frontend/web/npm/element.js`）与测试宿主通过 `face.js` 的 `engineApi()`（由 `runtime-loader.js` 提供）调用引擎。在分片推进期间：
- 初期 Slice 在 TypeScript 侧构建数据结构、选项解析、序列化与管线执行函数，并在 `npm/` 下添加对应单元测试。
- 中期 Slice 组合出 TypeScript 宿主引擎对象，在 `face.js` 中直接接入（或通过 `setEngineOverride` 在测试中优先验证）。
- 最终 Slice 切换生产导出并移除 Kotlin/JS 产物通道与源文件。

Kotlin 删除时机的一般规则：剩余各文件（管线、`WebEnhancer.kt`、引擎导出）的消费者存活到 Slice 6 的 TS 入口接入，为它们搭中间桥只产出 Slice 4..6 内会再删除的脚手架。因此 Slice 1..5 各自只让 TS 实现就位并由测试覆盖；Kotlin 实现随其消费者所在文件的删除时机统一消失：Slice 4 删管线文件与解码层，Slice 5 删会话与作业文件，Slice 6 删 `WebEnhancer.kt`、lifecycle 实现、reconcile 壳与引擎导出。各 Slice 范围中「删除对应 Kotlin 实现」的表述按此规则理解。

```
Slice 1: LoweredParagraph 数据模型与谓词的 TS 侧就位
  ↓
Slice 2: EnhanceOptions 选项解析、尺寸稳定化与 Issue 管理
  ↓
Slice 3: Worker 布局请求序列化与装配生成收敛
  ↓
Slice 4: Paragraph Pipeline 布局准备与提交管线（含三选一引擎）
  ↓
Slice 5: RootState 状态机与 ProgressiveRelayoutSession
  ↓
Slice 6: 内容 Reconcile 编排与 TiqianEngine TS 入口实现
  ↓
Slice 7: jsMain 源码清除、桥生成器移除与构建配置收敛
```

### Slice 1：LoweredParagraph 数据模型与谓词的 TS 侧就位
- **范围**：
  - 在 `npm-core/core/engine/` 新增 `lowered-paragraph.js` 模块，以 JSDoc 类型定义 `LoweredParagraph` 及各子结构（`TextStyle`, `TextSpan`, `DecorationSpan`, `InlineBoxSpan`, `InlineObjectSpan`, `DomInlineObject`, `DomSourceSpan`, `DomInlineBoxStyle`, `LineBreakSpan`），字段名与 `markdown-lowering.js` 的输出对象逐字符一致。
  - 实现谓词 `isCanonicalPlainParagraph(lowered)` 与 `isRuntimeExactPreparedDomEligible(lowered)`，语义与 `MarkdownParagraphLowering.kt` 的 Kotlin 扩展逐条一致，配单元测试。
  - Kotlin 侧解码层（`decodeLowered`, `decodeTextStyle` 等）本 Slice 不删：`WebEnhancerSupport.kt` 的元数据 JSON 构建与 `WebEnhancerParagraphPipeline.kt` 的 LayoutInput 组装仍消费强类型模型，分别待 Slice 3 与 Slice 4 删除其消费者后随之删除。
- **依赖顺序**：无前置依赖，作为基础数据结构层首个实施。
- **验收**：
  - 运行 `npm test`，确保 `npm/markdown-lowering.test.mjs` 与 `npm/markdown-lowering-bridge.test.mjs` 全部通过，新增谓词测试通过。
  - `LayoutDumpGoldenTest` 零 diff。
- **风险**：`LoweredParagraph` 内部集合与属性字段命名必须与现行 Kotlin 模型严格逐字符对齐。

### Slice 2：EnhanceOptions 选项解析、尺寸稳定化与 Issue 管理
- **范围**：
  - 在 TypeScript 侧实现 `EnhanceOptions` 解析（`optionsFromJs`、字号、行高、缩进、着重号间隙、字体 family 回退解析及 `conformingExactFontSessionId` 等方法）。
  - 在 TypeScript 侧实现宿主字体应用与尺寸稳定化（`applyConfiguredHostFontSize`, `captureSourceInlineSize`, `stabilizeContentSizedItemInlineSize`, `responsiveSourceMeasure`）。
  - 在 TypeScript 侧实现 `CapabilityIssue` 管理与 DOM 属性标注（`reportIssue`, `clearIssue`, `restoreAttribute`）。
  - `WebEnhancerParagraphLifecycle.kt` 的 Kotlin 实现本 Slice 不删（消费者存活到 Slice 4 与 Slice 6，见删除时机规则），随消费者所在文件删除。
- **依赖顺序**：依赖 Slice 1。
- **验收**：
  - 运行 `npm test`，验证 `npm/eligibility.test.mjs` 与 `npm/responsive-measure.test.mjs`。
  - 运行 `jsBrowserTest` 保持通过。
- **风险**：CSS 属性读写在空值与 `important` 优先级处理上的细微差异可能影响尺寸测量。

### Slice 3：Worker 布局请求序列化与装配生成收敛
- **范围**：
  - 在 TypeScript 侧实现 `workerLayoutRequest` 与 `workerLayoutRequestJson`。
  - 在 TypeScript 侧实现富文本渲染元数据生成函数（`preparedSemanticReplayJson`, `preparedInlineObjectMetaJson`, `preparedCjkStrongSemanticsJson`）。
  - `WebEnhancerSupport.kt` 中请求字符串拼接与元数据生成的 Kotlin 代码（[WebEnhancerSupport.kt:21-135](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L21-L135) 与 [378-426](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancerSupport.kt#L378-L426)）本 Slice 不删（消费者为管线与引擎导出，见删除时机规则）。
- **依赖顺序**：依赖 Slice 1 与 Slice 2。
- **验收**：
  - 运行 `npm test`，验证 `npm/exact-session.test.mjs` 中的 Worker 请求断言。
  - 与 `ffi/js` 的传输格式解析进行往返比对测试。
- **风险**：分隔符（`\u001e`, `\u001d`, `\u001f`）及转义字符处理必须与 `ParagraphWireFace` 完全一致。

执行时本 Slice 拆成三个子部分（2026-08-23 记录）：

1. **3a 元数据构建器**：`preparedSemanticReplayJson` 等三个函数进
   `lowered-paragraph.js`（ES module，消费者是宿主安装的 prepared 渲染桥，终点形态
   不经 Kotlin 运行时）。已提交 b8bc5d9。
2. **3b 请求序列化**：`workerLayoutRequestJson` 与第二重载
   `workerLayoutRequest(paragraph, lowered, options)` 进
   `core/engine/worker-request.js`（普通脚本安装 `globalThis.__TiqianWorkerRequest`，
   与 lifecycle.js 同风格：Slice 4 的管线模块由 Kotlin 侧驱动到 Slice 6，嵌入约束
   要求自包含）。第一重载 `(root, paragraph, options)` 不随本片移植：其 `lower()`
   调用向降级引擎注入 Kotlin 分类器回调，随 Slice 4 的管线接入移植。
3. **3c/3d ffi 导出接口预备**：Slice 4 的 TS 管线需要两类引擎侧能力经 `@tiqian/ffi`
   进入 TS。3c 导出降级辅助回调（`classifyFontRole`、
   `unsupportedInlineShapingProperties`、`firstDivergentInlineShapingProperty`），
   字体模块保持唯一实现。3d 为 `precomputeParagraphWithDiagnostics`：同一组入参加
   `zeroAdvanceEpsilonPx`，返回 `{"plan":"<转义后的 plan JSON>","diagnostics":{...}}`；
   diagnostics 只携带事实（capabilityIssue 非空的 shaping 决策的 name/reason/range，
   与按宿主阈值筛出的可疑 advance 决策的 displayText/advance/reason/range，advance
   一律按字符串输出以容纳 NaN/Infinity），三项核对判定仍归宿主；克隆装饰跨行计数
   不进 diagnostics，plan JSON 的 lines 段已带 `rangeStart`/`rangeEnd`。RootState 的
   engine 三元组映射为会话描述（exact session id 或浏览器度量后端），逐 run 回退
   由宿主捕获能力失败 detail 后换后端重试实现，等价于
   `ExactSessionBrowserFallback*` 两个包装类。

### Slice 4：Paragraph Pipeline 布局准备与提交管线

Slice 4 按依赖拆四个子部分（2026-08-23 决定）：

1. **4a ffi 浏览器度量后端模式**：ADR 0053 的「TS 采集器提供基于 canvas 的
   度量回调」尚未实现（ffi 现有导出全部按 HarfBuzz 会话取后端）。新增导出
   `precomputeParagraphWithBrowserMetrics`：与 3d 相同的入参，后端改为两个
   JS 回调（shaping 段进 `ShapingInput` JSON 串出 `ShapingResult` JSON 串；
   字体度量请求进 `FontMetricsRequest` JSON 串出 `RawFontMetrics` JSON 串），
   沿字节进出面惯例。配套把
   `shaping/web-adapter` 的 `WebCanvasTextShaper.kt`（767 行，含度量缓存、
   字体加载失效、dash 能力探测、ink bounds 栅格化、hidden-DOM 回退）与
   `WebCanvasFontMetricsResolver` 的度量逻辑移植为 TS 回调实现模块，固定输入
   下的输出与 Kotlin 实现逐项比对。`ExactSessionBrowserFallback*` 两个包装类
   不移植：逐 run 回退由宿主换会话描述重试实现（见 3d 记录）。
2. **4b TS prepareParagraphLayout**：管线核对模块消费 3d 的
   plan-with-diagnostics 信封，三项命名判定
   （capabilityIssue、InvalidWebShapingAdvance 按宿主阈值与 displayText 谓词、
   InlineCloneDecorationBreakUnsupported 按 plan JSON lines 的
   rangeStart/rangeEnd）在 TS 复核事实后裁决；引擎调用按会话描述走
   ffi（exact session id 或 4a 浏览器度量模式）；`workerLayoutRequest`
   首重载（root 变体，分类器回调经 3c 导出）随本片移植。
3. **4c TS commit 路径**：`commitPreparedParagraph`、
   `commitWorkerPreparedParagraph`，prepared-dom 渲染调用、校验器、
   ExactSessionMetricDistrust 的换宽度重排与 ignoreUnchangedMeasure。
4. **4d 切换与删除**：TS 管线上线，删除
   `WebEnhancerParagraphPipeline.kt`、`WebEnhancerSupport.kt` 降级适配器类与
   `MarkdownParagraphLowering.kt` 解码层；golden 与 demo/web 全量验证。

原范围描述（保留为总述）：
- **范围**：
  - 在 TypeScript 侧实现 `prepareParagraphLayout`：集成 `LineBreaker`、度量解析器与 TextShaper，执行 shaping 决策核对、advance 校验与克隆装饰跨行拦截。
  - 在 TypeScript 侧实现 `commitPreparedParagraph` 与 `commitWorkerPreparedParagraph`：调用 `__TiqianPreparedDomRenderer.render`，调用校验器，处理精确会话校验失败后的浏览器度量回退重排。
  - 在 TypeScript 侧实现 `ExactSessionBrowserFallbackTextShaper` 与 `ExactSessionBrowserFallbackFontMetricsResolver`。
  - 删除 `WebEnhancerParagraphPipeline.kt`（583 行）、`WebEnhancerSupport.kt` 中的降级适配器类与 `MarkdownParagraphLowering.kt` 的解码层（强类型模型最后的消费者随管线消失，数据类与谓词一并删除）。
- **依赖顺序**：依赖 Slice 1、Slice 2、Slice 3。
- **验收**：
  - 运行 `npm test`，验证 `npm/renderer-output.test.mjs`, `npm/renderer-source-fidelity.test.mjs`, `npm/exact-session.test.mjs`。
  - 验证时序 golden 零 diff。
- **风险**：精确字体会话回退到浏览器度量的两级重试逻辑需防止递归发散。

### Slice 5：RootState 状态机与 ProgressiveRelayoutSession
- **范围**：
  - 在 TypeScript 侧实现 `RootState` 状态维护与弱引用管理（`states = new WeakMap()`）。
  - 在 TypeScript 侧实现 `ProgressiveRelayoutSession`：记录快照、执行 processItem、完成时更新 state、发生异常时调用 `custody.rollback` 回滚。
  - 在 TypeScript 侧实现 `relayout` 与 `enhanceProgressively` 的作业调度包装，对接 `npm-core/core/engine/progressive-job.js`。
  - `WebEnhancer.kt` 中的 `ProgressiveRelayoutSession`（[WebEnhancer.kt:407-477](frontend/web/src/jsMain/kotlin/org/tiqian/web/WebEnhancer.kt#L407-L477)）与 `WebEnhancerProgressiveJob.kt` 本 Slice 不删（驱动方是 Kotlin 引擎入口，Slice 6 接入，见删除时机规则）。
- **依赖顺序**：依赖 Slice 4。
- **验收**：
  - 运行 `npm test`，验证 `npm/progressive.test.mjs` 与 `npm/custody.test.mjs`。
  - 运行 `npm/timing-golden.test.mjs` 验证状态转换时序。
- **风险**：跨帧分片执行时的 stale 判定与度量比较需确保数值精确。

### Slice 6：内容 Reconcile 编排与 TiqianEngine TS 入口实现
- **范围**：
  - 在 TypeScript 侧实现 `probeContentDrift` 与 `reconcileContent` 的动作编排（将判定结果映射为 drifted/custody/tainted/stranded 的具体 DOM 处理并提交作业）。
  - 构造 TypeScript 宿主引擎入口对象 `TiqianEngine`（实现全部 11 个入口方法：`enhance`, `enhanceProgressively`, `enhanceAll`, `destroy`, `detach`, `relayout`, `refresh`, `cancelLayoutWork`, `probeContentDrift`, `reconcileContent`, `workerLayoutRequest`）。
  - 将 `frontend/web/npm-core/core/engine/loaders/runtime-loader.js` 与 `face.js` 的默认调用目标切换为该 TypeScript 引擎实现。
  - 删除 `WebEnhancerContentReconcile.kt`、`WebEnhancerEngineExport.kt` 与 `WebEnhancerWorkerProtocol.kt`。
- **依赖顺序**：依赖 Slice 5。
- **验收**：
  - 运行 `npm test`，验证 `npm/content-reconcile.test.mjs`, `npm/engine-api.test.mjs`, `npm/element.test.mjs`。
  - 运行 `demo/web` 全部测试套件（35/35 通过）。
- **风险**：协调器与直接调用方在引擎解析就绪状态判定上的时序需保持兼容。

### Slice 7：jsMain 源码清除、桥生成器移除与构建配置收敛
- **范围**：
  - 删除 `frontend/web/src/jsMain` 下全部剩余 Kotlin 文件（`WebEnhancer.kt`, `WebEnhancerSupport.kt`, `Main.kt`, 以及 8 个 Bridge 文件）。
  - 删除 `frontend/web/src/jsTest` 下全部 Kotlin 测试文件及 support/fixtures 文件。
  - 在 `frontend/web/build.gradle.kts` 中移除 Kotlin/JS target、7 个 bridge 生成任务、`vendorPreparedDom` 与 `assembleNpmPackage` 任务。
  - 清理 `npm-core/runtime/tiqian-web.js` 产物及分发配置。
- **依赖顺序**：依赖 Slice 1 至 Slice 6 全部验收通过。
- **验收**：
  - 运行 Gradle 构建，确认 `:frontend:web` 不再参与 Kotlin/JS 编译。
  - 运行 `npm test`（npm-core 与 prose 全量测试）。
  - 运行 `tools/package-topology/check.mjs` 与 `tools/ts-discipline` 静态检查。
  - 运行 `verify-package` 与 `verify-release` 验证发布包完整性。
- **风险**：确保无任何遗留测试或构建脚本引用已删除的 Kotlin 产物路径。

---

## 3. jsTest 规格映射与删除顺序

根据 `docs/ts-port-assertion-checklist.md`，原 `frontend/web/src/jsTest/kotlin/org/tiqian/web/` 下共有 5 个测试文件、104 个 `@Test` 测试函数、717 条行为断言。此前 `TiqianWebCopyTest.kt`（4 个测试，28 条断言）已在 B6 批次中移植至 `npm/copy-fidelity.test.mjs` 并删除源文件。

当前仍保留在 `src/jsTest/kotlin/` 中的 4 个测试文件（共 102 个测试函数）与已有的 TypeScript 测试套件对照如下：

`docs/ts-port-assertion-checklist.md` 冻结于 158db36，当时 4 个文件共 100 个测试函数、689 条断言。此后四个提交移动了计数：9bd7105、f6049f1、0835074 向 `TiqianWebExactSessionTest.kt` 净增 3 个测试（语义段落经运行时 prepared 路径回放、inline object 经 worker 与浏览器两条路径回放、带 CJK strong metadata 的装饰段落准入）；5c76cf6 把该文件的 prepared 几何不一致测试重写为常驻校验失败与浏览器度量重试两个测试，并删除 `TiqianWebProgressiveRelayoutTest.kt` 的 2 个多字符 run 间隙测试（对应规格 `rendererOutput_negativeGapResolvesToOverlapCarrier` 与 `rendererOutput_positiveGapUsesSelectableZeroHeightCarrier` 已在 `npm/renderer-output.test.mjs`）。下表主题行的测试数与断言数沿用 checklist 冻结值；删除文件前以文件内 `@Test` 实数为准。

| 行为主题 | jsTest 来源文件与测试数 | 断言数 | TS 验收测试套件文件 | 覆盖状态与移植要求 |
|---|---|---|---|---|
| **custody** | `TiqianWebProgressiveRelayoutTest.kt` (6) | 42 | `npm/custody.test.mjs`<br>`npm/custody-bridge.test.mjs` | 已由 TS 测试全量覆盖（B2 批次完成），待 Slice 5 完成后删除 Kotlin 测试。 |
| **progressive-job** | `TiqianWebProgressiveRelayoutTest.kt` (10)<br>`TiqianWebSourceFidelityTest.kt` (1) | 100 | `npm/progressive.test.mjs`<br>`npm/progressive-job-bridge.test.mjs` | 已由 TS 测试全量覆盖（B3 批次完成），待 Slice 5 完成后删除 Kotlin 测试。 |
| **eligibility** | `TiqianWebEnhancerTest.kt` (7)<br>`TiqianWebProgressiveRelayoutTest.kt` (1)<br>`TiqianWebSourceFidelityTest.kt` (1) | 51 | `npm/eligibility.test.mjs`<br>`npm/eligibility-bridge.test.mjs` | 已由 TS 测试全量覆盖（B4 批次完成），待 Slice 2 完成后删除 Kotlin 测试。 |
| **responsive-measure** | `TiqianWebEnhancerTest.kt` (4)<br>`TiqianWebExactSessionTest.kt` (2)<br>`TiqianWebProgressiveRelayoutTest.kt` (4)<br>`TiqianWebSourceFidelityTest.kt` (1) | 74 | `npm/responsive-measure.test.mjs`<br>`npm/responsive-measure-bridge.test.mjs` | 已由 TS 测试全量覆盖（B4 批次完成），待 Slice 2 完成后删除 Kotlin 测试。 |
| **content-reconcile** | 现 jsTest 中无对应用例 (0) | 0 | `npm/content-reconcile.test.mjs`<br>`npm/content-reconcile-bridge.test.mjs` | 已在 TS 侧补充 9 条行为规格测试（B5 批次完成）。 |
| **copy-fidelity** | `TiqianWebProgressiveRelayoutTest.kt` (1)<br>`TiqianWebSourceFidelityTest.kt` (2) | 14 | `npm/copy-fidelity.test.mjs` | 已由 TS 测试全量覆盖（B6 批次完成，原 CopyTest 已删，剩余 3 条交叉测试随所属文件删除）。 |
| **exact-session** | `TiqianWebEnhancerTest.kt` (2)<br>`TiqianWebExactSessionTest.kt` (14)<br>`TiqianWebSourceFidelityTest.kt` (2) | 94 | `npm/exact-session.test.mjs`<br>`npm-core/cjk-dash.test.mjs` | 已由 TS 测试全量覆盖（B10 与 A5 批次完成），待 Slice 4 完成后删除 Kotlin 测试。 |
| **source-fidelity** | `TiqianWebEnhancerTest.kt` (1)<br>`TiqianWebProgressiveRelayoutTest.kt` (2)<br>`TiqianWebSourceFidelityTest.kt` (6) | 57 | `npm/source-fidelity.test.mjs`<br>`npm/renderer-source-fidelity.test.mjs` | 已由 TS 测试全量覆盖，待 Slice 4 完成后删除 Kotlin 测试。 |
| **renderer-output** | `TiqianWebEnhancerTest.kt` (6)<br>`TiqianWebProgressiveRelayoutTest.kt` (3)<br>`TiqianWebSourceFidelityTest.kt` (11) | 173 | `npm/renderer-output.test.mjs`<br>`npm/prepared-dom.test.mjs` | 已由 TS 测试全量覆盖（B7 与 B8 批次完成），待 Slice 4 完成后删除 Kotlin 测试。 |
| **markdown-lowering** | `TiqianWebEnhancerTest.kt` (5)<br>`TiqianWebSourceFidelityTest.kt` (5) | 76 | `npm/markdown-lowering.test.mjs`<br>`npm/markdown-lowering-bridge.test.mjs` | 已由 TS 测试全量覆盖（B9 批次完成），待 Slice 1 完成后删除 Kotlin 测试。 |
| **engine-api** | `TiqianWebEnhancerTest.kt` (3) | 8 | `npm/engine-api.test.mjs` | 已由 TS 测试全量覆盖（C1 批次完成），待 Slice 6 完成后删除 Kotlin 测试。 |

### 3.1 测试文件删除顺序
依据 Slice 完成与验证通过的节奏，Kotlin 测试文件按如下顺序依次删除：
1. **Slice 1 完成后**：验证 `markdown-lowering.test.mjs` 通过。
2. **Slice 2 完成后**：验证 `eligibility.test.mjs` 与 `responsive-measure.test.mjs` 通过。
3. **Slice 4 完成后**：验证 `exact-session.test.mjs`、`source-fidelity.test.mjs` 与 `renderer-output.test.mjs` 通过，删除 `TiqianWebExactSessionTest.kt`（20 个测试，743 行）。
4. **Slice 5 完成后**：验证 `custody.test.mjs` 与 `progressive.test.mjs` 通过，删除 `TiqianWebProgressiveRelayoutTest.kt`（25 个测试，968 行）。
5. **Slice 6 完成后**：验证 `npm/element.test.mjs`、`npm/engine-api.test.mjs` 与 `npm/content-reconcile.test.mjs` 通过，删除 `TiqianWebEnhancerTest.kt`（30 个测试，833 行）与 `TiqianWebSourceFidelityTest.kt`（27 个测试，835 行）。
6. **Slice 7 收尾时**：删除剩余的测试辅助文件 `TiqianWebEnhancerTestSupport.kt`（1209 行）与 `TiqianWebEnhancerTestFixtures.kt`（46 行），使 `jsTest` 目录下行数完全降为 0。

---

## 4. Main.kt 的处置

### 4.1 现状确认
- `frontend/web/src/jsMain/kotlin/org/tiqian/web/Main.kt`（170 行）包含 `fun main()` 入口函数，负责在页面挂载一个包含滑块与基准测试按钮的简易交互界面（[Main.kt:35-136](frontend/web/src/jsMain/kotlin/org/tiqian/web/Main.kt#L35-L136)）。
- 在 `frontend/web/build.gradle.kts:124` 中，配置了 `binaries.executable()`，Webpack 打包将 `Main.kt` 编译进 `tiqian-web.js` 执行体。
- 现代的 Web 示例与交互测试位于 `demo/web/` 目录，其入口为 `demo/web/index.html` 与 `demo/web/main.js`。`demo/web/main.js:1-2` 直接引入 `@tiqian/prose/element` 与 `@tiqian/prose` 的公开 `enhance` 函数，并通过 Parcel 完成模块打包。
- `Main.kt` 中的代码不被 `demo/web` 消费，也不被 `@tiqian/prose` npm 包的生产导出路径引用。

### 4.2 处置结论
- `Main.kt` 是早期基于纯 Kotlin/JS bundle 的过渡演示外壳，当前已完全由 `demo/web` 替代。
- 在 Slice 7 中，随着 Kotlin/JS 编译目标的废除，`Main.kt` 可直接删除，无需进行 TypeScript 移植。

---

## 5. kotlin-js-store 清除与构建系统收敛

在 `frontend/web/src/jsMain` 行数降为 0 后，Gradle 与 npm 构建系统需进行收敛处理，彻底解除 Kotlin/JS 编译器对主前端工程的侵入。

### 5.1 frontend/web/build.gradle.kts 的改造
1. **移除 Kotlin/JS 编译目标**：
   - 移除 `kotlin { js { ... } }` 配置块（[build.gradle.kts:114-125](frontend/web/build.gradle.kts#L114-L125)），不再生成 `Tiqian-tiqian-web` 模块及其 Webpack bundle。
   - 移除 `sourceSets.jsMain` 与 `sourceSets.jsTest`（[build.gradle.kts:127-147](frontend/web/build.gradle.kts#L127-L147)）。
2. **废除 7 个 Bridge 生成任务**：
   - 移除 `generateCustodyBridge`, `generateEligibilityBridge`, `generateProgressiveJobBridge`, `generateCopyBridge`, `generateContentReconcileBridge`, `generateResponsiveMeasureBridge`, `generateMarkdownLoweringBridge` 及其注册函数 `registerBridgeGenerator`（[build.gradle.kts:8-90](frontend/web/build.gradle.kts#L8-L90)）。
3. **移除产物搬运任务**：
   - 移除 `vendorPreparedDom` 任务（[build.gradle.kts:99-111](frontend/web/build.gradle.kts#L99-L111)）。
   - 移除 `assembleNpmPackage` 任务（[build.gradle.kts:164-172](frontend/web/build.gradle.kts#L164-L172)）。
4. **模块定位收敛**：
   - 若 `frontend/web` 不再包含任何 Kotlin 源码，则可将其从根目录 `settings.gradle.kts` 的多平台项目中解除关联，或仅保留极简的任务用于 npm 构建钩子触发。

### 5.2 产物通道与 kotlin-js-store 清除
- **产物文件清理**：`frontend/web/npm-core/runtime/tiqian-web.js` 与 `build/kotlin-webpack` 不再生成，`runtime/` 目录从发布包配置（`package.json` 的 `files` 字段）中移除。
- **kotlin-js-store 清除**：此前由 Kotlin/JS Gradle 插件在 `frontend/web` 引入的 Yarn/npm 依赖解析与 `kotlin-js-store` 存储完全消除；Kotlin/JS 编译仅局限在 `:ffi:js` 模块（供 Node.js 排版 Worker 独立使用），Web 前端完全转入 Bun/npm 原生工具链管理。
- **发布与 CI 检查**：
  - `tools/package-topology/check.mjs` 继续确保 `web-component → core → ffi` 单向依赖。
  - `tools/ts-discipline` 对新增的 TypeScript 实现执行静态类型检查，确保无 `any`、无双重断言、无未受限宽类型。
