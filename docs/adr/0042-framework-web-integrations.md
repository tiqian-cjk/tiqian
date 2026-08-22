# ADR 0042：Web 框架集成包与无宽度字体证据

- Status: Accepted
- Date: 2026-07-21
- Amends: [ADR 0039 Web 渲染路径与真实站点接入](0039-web-rendering-path.md)、
  [ADR 0040 构建期 Web 字体证据与最大版心快照](0040-build-time-web-font-snapshots.md)

## Context

`@tiqian/prose` 已经能消费服务器生成的语义 HTML，并在浏览器按实时容器宽度增强；构建期路径还能
从宿主字体生成服务器 shaping / metrics 回放证据，以及可选的固定版心快照。真实 SvelteKit 与 Astro
宿主此前各自负责 HTML 投影、快照资产注入、客户端导航注册和 custom element 生命周期，重复逻辑已经
超过单个站点应该持有的范围。

同时，“构建期字体证据”和“固定版心快照”曾共用 `maxWidthPx` 形参。这会让集成作者误以为，只要想在
服务器准备提椠，就必须把 CSS 的响应式宽度手工抄进配置。实际上字体 face、glyph shaping 与 metrics
证据不以最终断行宽度为身份；只有复用已经算好的 line geometry 才需要固定 measure。

框架组件还必须诚实区分两种 SSR：普通包裹可以在服务器输出完整语义 HTML，但服务器不知道客户端
容器的真实宽度，不能据此宣称已经输出最终提椠断行。固定版心快照也只能作为严格校验后采用的 cache，
不能替代正文 source。

## Decision

### `CorePrepareThinAdapter`：同仓库、分 npm 包

框架中立能力留在 `@tiqian/prose`：

- `createHtmlPreparer()` 接收宿主已经渲染好的 HTML，保留原字符串，只为成功生成固定几何的段落插入
  `data-tq-snapshot-key`；
- 它统一完成段落选择、跳过规则、受控 snapshot 投影、字体证据聚合，以及 server / client transport
  的拆分；
- 默认只为纯文本与 `<br>` 生成固定几何。链接、代码和任意宿主 inline CSS 不由通用层猜测；宿主需要
  通过具名 projector 明确发布完整 contract；
- SSR 正文始终是原来的 semantic HTML，inert template、初始 geometry style 与字体 preload 是独立
  server assets。

框架接入作为同一仓库里的独立发布包：

- `@tiqian/sveltekit` 提供 `TiqianProse.svelte`，以及集中持有 precomputer、紧凑导航数据和 SSR head
  资产的 server boundary；
- `@tiqian/astro` 提供 Astro integration 与 `TiqianProse.astro`，在 static build 完成后把 component
  marker 中的 server assets 提升并去重到文档 `<head>`；
- adapter 只负责框架生命周期和传输，不复制排版、字体选择、DOM lowering 或 snapshot schema。

包不拆到独立仓库。它们需要与 `@tiqian/prose` 的 alpha wire / render revision 同步测试和发版；分仓会
增加版本漂移，却不会形成真正独立的能力所有权。独立 npm 包仍使未使用 Svelte 或 Astro 的用户不必
安装相应框架依赖。

2026-08-20 追记：[ADR 0050](0050-native-precompute-rust-bindings.md) 把 precompute 从
`@tiqian/prose` 迁入独立的 `@tiqian/precompute` 包。框架包改引新包并锁步发版。

### `WidthIndependentFontEvidenceCaptureMeasure`：字体契约不要求宿主宽度

`prepareFontContract()` 的公共输入不再要求 `maxWidthPx`。Node 内部为跑通同一条真实 layout / shaping
pipeline 使用由 source 和字体 span 推导出的宽 measure，但只发布 shaping、metrics 与 face evidence，
不把这次内部断行几何声明为可复用结果。旧的可选 `maxWidthPx` 字段暂时保留为 deprecated 兼容输入，
其值被忽略。

`prepareParagraph()` 与 `HtmlPrepareOptions.snapshot.maxWidthPx` 继续表示
`MaximumMeasureSnapshotCache`。只有用户显式选择固定 measure 首屏优化时才出现这个声明；响应式默认
路径、语义 SSR 和 exact-font browser replay 都不需要它。

### `SemanticSsrLiveMeasureEnhancement`：组件默认不伪装最终断行 SSR

两个组件的最低配置都输出 light-DOM `<tiqian-prose>` 与原语义 children / HTML。CSS、SEO、搜索、复制
和无 JavaScript 路径因此在服务器结果上成立；custom element 加载后读取真实 computed typography 与
content width，再由浏览器 Tiqian runtime 排版。这个默认路径不需要字体文件路径、字号声明或最大宽度。

宿主若提供构建字体与 typography，adapter 会附带 width-independent exact-font replay evidence，仍由
浏览器按实时宽度断行。宿主再显式提供 snapshot maximum measure 时，adapter 才额外生成固定几何；
浏览器必须继续验证 live source、字体、typography 与有效行宽，失配时用 semantic source 走实时布局。

SvelteKit 的 server boundary 支持 request / navigation data，因此只把 compact client bundle 放进 route
data，完整 inert server assets 保存在 request-scoped store 中，再由 `handle` 注入 `<head>`；即使宿主在
并发请求中复用显式 snapshot id，也不能把一篇文章的 inert DOM 注入另一篇。Astro 第一版只承诺 static / prerender build；
on-demand SSR 的进程生命周期、并发缓存与流式 head 注入另行设计，不在当前 integration 中静默支持。

## Consequences

- SvelteKit 用户可以直接写 `<TiqianProse html={...} />`，Astro 用户可以写
  `<TiqianProse><Content /></TiqianProse>`，得到语义 SSR 与按真实宽度增强。
- 需要 exact host font replay 时只声明字体与 typography，不再手算 CSS 最大宽度。
- `maxWidthPx` 成为明确的可选性能选择，而不是组件成立或 SSR 成立的前置条件。
- 两个框架共享相同 HTML prepare 和 snapshot transport 事实来源；修复 source mapping 或 wire contract 时
  不再修改每个真实站点的私有 renderer。
- 通用层不会猜宿主富文本盒模型。复杂 inline 没有完整 projector 时仍保留 semantic source，由浏览器
  live DOM lowering 决定是否可增强。

## Alternatives considered

- **把 SvelteKit / Astro 逻辑继续留在真实站点**：短期少两个包，但 source mapping、导航 payload 与
  snapshot 生命周期会持续分叉。否。
- **每个 adapter 独立仓库**：发布边界清晰，但 alpha render wire 必须跨仓同步，所有权并未真正解耦。
  否；保留独立 npm 包即可。
- **组件必须声明最大宽度**：能直接生成固定 line geometry，却把响应式 CSS 复制成构建配置，并把 cache
  误当成主路径。否。
- **默认宣称 Tiqian final-layout SSR**：服务器没有客户端 live measure；除非固定快照最终通过浏览器验证，
  这个声明不成立。否。
