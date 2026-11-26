# ADR 0064: 退役 `@tiqian/ffi`，core 直接调用 `@tiqian/engine`

- Status: Accepted
- Date: 2026-11-26
- Relates: [ADR 0053](0053-web-prose-host-consolidation.md)（`SingleEngineFace` 由本记录取代）、
  [ADR 0060](0060-single-release-entry-and-gate.md)（发版单元由本记录修订）

## Context

`platforms/web/client/engine-runtime` 曾以 `@tiqian/ffi` 的名义提供 Kotlin/JS 时代的引擎出口：
13 个 JSON 字符串进出的函数，包内是生成树加一层手写 facade。引擎改写为 Haxe 并经 `boring gen ts`
生成 TypeScript 树之后，这层字符串边界只为兼容已删除的 Kotlin 接口而存在；`@tiqian/engine` 作为
bundle 产物已经发布，core 却仍从 `@tiqian/ffi` 取用。

## Decision

1. 删除 `platforms/web/client/engine-runtime` 与 `.github/workflows/publish-ffi.yml`。
2. `engine-haxe/out/ts/gen` 作为根 `package.json` 的 workspace 成员，包名 `@tiqian/engine`；
   core 以 `workspace:*` 依赖它，直接编译生成树的 `.ts` 源码。
3. core 的引擎边界按职责分散存放：请求体类型由 `@tiqian/protocol` 的 `ParagraphRequest` 派生
   （`src/engine/wire-types.ts`）；worker 消息类型独立在 `src/engine/web-worker/wire-types.ts`；
   宿主结果解码在 `src/engine/host-result.ts`；字体角色判定调用引擎的 `FontRoleClassification`；
   prepared-paragraph 的请求归一化、LayoutInput 组装与两个 plan 入口在 `@tiqian/shared` 的
   `org.tiqian.shared.layout.PreparedParagraphLayout`，core 只保留宿主回调、注解缓存与错误名归一化。宿主回调改为
   `{ shape, resolve }` 的类型化对象进出，core 内不再出现 `shapeJson`/`metricsJson` 字符串通道。
4. 生成树包之间用 boring 的 bundle 依赖声明：`shared-ts` 的 `dependsOn` 指向 `ts`，生成时跳过
   依赖包提供的模块并改为 `@tiqian/engine/...` 的 import；`boring pack` 顺序中 `ts` 必须在
   `shared-ts` 之前。boring 的 `dependsOn` 支持 ts、rust、kotlin、swift、dart 五个发射目标，
   由驱动器测试覆盖。
5. 发版：`@tiqian/engine` 由 bundle 车道的 `ts protocol-ts shared-ts` 分组打包发布；
   `release-manifest.json` 删除 `npm-ffi` 单元与 `registry` 对它的依赖项，`npm-core` 不再声明
   前置依赖，与 `@tiqian/protocol`/`@tiqian/shared` 同一处理方式。`release.yml` 的 `npm-ffi` 作业移除；
   `prepare-release-web-workspace` 动作与 `build-precompute-release.yml` 改为生成并解析三棵生成树，
   `pack-release-bundles.yml` 上传下载 `engine-haxe/out/{ts,protocol-ts,shared-ts}`，不再组装 ffi runtime。
6. 快照车道同步收口：`snapshot-swap.ts` 的改名集合加入 `@tiqian/engine`、`@tiqian/protocol`
   与 `@tiqian/shared`；`snapshot-precompute.yml` 的 client-packages 在 `boring pack` 之后用
   `tools/rewrite-npm-tarball.py` 把三个生成树 tarball 的包名与版本改写为快照 scope 与快照版本，
   发布顺序把三个生成包放在 core 之前。core 的快照 tarball 因此不再携带 `workspace:*` 依赖。

## Consequences

- 行为等价以删除前采集的基线验证：23 条语料中 22 条 plan 逐字节相同、22 条 diagnostics 相同、
  1 条非法枚举错误名称与消息相同；837 组区间角色输出全部相同。
- 测试：core 451、web-component 242、react 6，全部通过；三者的 `tsc -b` 通过。
- `core` 包不再有 JSON 字符串形式的引擎入参出参；`demo/web` 的三个浏览器测试改由
  `tests/browser-engine.ts` 把生成树编译为 ESM 后提供给 Chromium。
- npm 上的 `@tiqian/ffi` 历史版本保留；后续版本不再发布，需要时可 `npm deprecate`。
- 预计算侧的 `prepared_dom.rs` 从未在 `lib.rs` 声明，属于未编译代码，已删除；`snapshot_source.rs`、
  `plan.rs`、`snapshot_table_binary.rs`、`replay.rs` 是平台外壳或对浏览器 `core` 的 TypeScript 模块的
  移植，不是 `platforms/web/shared` 的副本。
- 生成的 `@tiqian/engine`、`@tiqian/protocol`、`@tiqian/shared` 的 `package.json` 不含 `dependencies`；
  发布与快照两条打包路径需要在消费方按 `dependencies.tsv` 补入依赖声明。

## Alternatives

- 保留 ffi 并在其中重新导出 engine：维持两个发布面与两份生成树，行为不变但删除目标落空。
- 只改 core 依赖而不删包：可以快速验证，但仓库继续维护一份无人消费的兼容层。
