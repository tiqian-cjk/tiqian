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
3. core 新建 `src/engine/engine-access/`：wire 类型、字体角色判定、宿主结果转换、prepared-paragraph
   组装。宿主回调改为 `{ shape, resolve }` 的类型化对象进出，core 内不再出现
   `shapeJson`/`metricsJson` 字符串通道。
4. 发版：`@tiqian/engine` 由 bundle 车道发布；`release-manifest.json` 删除 `npm-ffi` 单元，
   `npm-core` 不再声明前置依赖，与 `@tiqian/protocol`/`@tiqian/shared` 同一处理方式。
5. 快照车道同步收口：`snapshot-swap.ts` 的改名集合加入 `@tiqian/engine`、`@tiqian/protocol`
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

## Alternatives

- 保留 ffi 并在其中重新导出 engine：维持两个发布面与两份生成树，行为不变但删除目标落空。
- 只改 core 依赖而不删包：可以快速验证，但仓库继续维护一份无人消费的兼容层。
