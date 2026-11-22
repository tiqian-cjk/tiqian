# ADR 0060: 单一发版入口与发版前总检查

- Status: Accepted
- Date: 2026-11-13
- Relates: [ADR 0050](0050-native-precompute-rust-bindings.md)（原生 precompute 绑定与 Rust / npm 双生态分发）、
  [ADR 0055](0055-maven-central-file-quota.md)（Maven Central 文件配额）

## Context

仓库有九条与发布有关的 workflow。`release-registry.yml` 由 `v*.*.*` 标签触发，
只 pack `boring.json` 的 13 个 bundle，写出 `tiqian-engine` 与 `tiqian-protocol`
两个 registry 包。`publish-ffi.yml`、`publish-precompute.yml` 与
`publish-web-component.yml` 由各自的包标签触发。`publish.yml` 与
`publish-snapshots.yml` 只接受 `workflow_dispatch`，需要人手填写版本。
`build-neon-precompute.yml` 只产出编译产物，没有任何 workflow 调用它。

GitHub Actions 的运行记录与 npm 仓库的查询结果如下：

- `publish-ffi.yml` 与 `publish-precompute.yml` 在 `Losses/tiqian` 与
  `tiqian-cjk/tiqian` 的 runs 总数都是 0；`https://registry.npmjs.org/@tiqian%2fffi`
  与 `https://registry.npmjs.org/@tiqian%2fprecompute` 返回 `Not found`。
- `publish-prose.yml` 最后一次运行发布的是 `@tiqian/prose@0.1.0-alpha.5`，
  当前清单版本是 `0.1.0-alpha.6`。
- `build-neon-precompute.yml` 在 main 的最近一次运行 `891351ed6` 结论为
  `failure`；`Release to Registry` 在 `v0.1.0-alpha07` 的结论为 `success`。

因此一个版本标签只发布 registry 的 13 个 bundle，npm 包与 Maven 包各自独立触发，
一条发布 workflow 失败时 registry 元数据仍然可以写出。

## Decision

1. `.github/workflows/release.yml` 是唯一发版入口，由 `v*.*.*` 标签触发。
2. `.github/workflows/release-gate.yml` 是可复用的发布前检查，每个发布 workflow
   在发布前调用它。`tools/release-gate.py` 读取 `release-manifest.json`，要求
   `release.requiredLanes` 的每一条 workflow 在发版 commit 上都有 completed 且
   success 的运行记录。发布入口等待尚未登记或仍在运行的检查。检查结束后给出失败结果，
   或等待到期时仍缺少成功记录，发布作业停止。
3. `release-manifest.json` 记录发布单元；`tools/release-gate.py` 把
   `boring.json`、npm 清单与 `build.gradle.kts` 的包集合与清单交叉核对，
   出现未登记的包即拒绝。
4. `release.yml` 按依赖顺序调用各发布 workflow：ffi、core、prose、precompute、
   Maven 暂存、registry。registry 写在最后，前面任一 workflow 失败时不会写出元数据。
5. 三条 npm workflow 删除各自的包标签触发器，改为 `workflow_call`；在 v 标签上
   dispatch 作为重跑入口。
6. Maven 暂存由发版标签调用，Central Portal 的部署确认仍由人在 Portal 执行。
   Maven SNAPSHOT 与 fork 快照不属于按版本发版，继续使用 `workflow_dispatch`。

## Consequences

- 一个 v 标签要求所有 required workflows 在同一个 commit 上通过；新增的 required
  workflow 必须先在 main 上运行通过。
- npm 包继续使用各自 `package.json` 的版本：`@tiqian/ffi` 为 0.1.0-alpha.1，
  `@tiqian/core` 与 `@tiqian/prose` 为 0.1.0-alpha.6，`@tiqian/precompute`
  为 0.1.0-alpha.3。本次不改变版本策略，发布顺序按依赖关系固定。
- `publish-web-adapters.yml` 在同版本的依赖发布后构建并测试
  `@tiqian/astro`、`@tiqian/sveltekit` 与 `@tiqian/react`，检查安装结果，
  并将三个包发布到 npm 公共仓库。`snapshot-precompute.yml` 继续发布 fork 的测试版本。
  `release-manifest.json` 的 `notInRelease` 保留声明 `private: true` 的 `tiqian-web-demo`。
- 发版失败后的重跑使用 GitHub 的 "Re-run failed jobs"；npm 拒绝覆盖已经发布的
  版本号。
