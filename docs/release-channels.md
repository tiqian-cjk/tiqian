> 本文记录 2026-11 早期七条发布通道的状态。`publish-ffi.yml` 与 `@tiqian/ffi` 包已删除；`@tiqian/engine` 由 bundle 车道发布，本文的 ffi 行仅作历史记录。

# 发布通道对照

本文档记录 tiqian 七条发布通道在 2026-11-13 之前的配置，指出它们之间的不一致，并给出
一份统一方案。统一方案已经实现为单一发版入口，现行流程见
[release-pipeline.md](release-pipeline.md) 的 0 节与
[ADR 0060](adr/0060-single-release-entry-and-gate.md)。

## 1. 七条通道

| 工作流 | 触发 | 目标仓库 | 发布单元 | 版本来源 |
| --- | --- | --- | --- | --- |
| `publish.yml` | `workflow_dispatch`，手填 `version` 与 `namespace`（第 3-14 行） | Maven Central 暂存区 | 8 个 Maven 模块 | 输入参数 `version`，写入环境变量 `TIQIAN_VERSION`（第 27 行） |
| `publish-snapshots.yml` | `workflow_dispatch`，手填 `version`（第 3-10 行） | Maven Central 快照仓库 | 8 个 Maven 模块 | 输入参数 `version`，必须带 `-SNAPSHOT` 后缀（第 34-37 行） |
| `publish-ffi.yml` | 推送标签 `@tiqian/ffi@*`（第 3-6 行） | npmjs.com | 1 个 npm 包 | `platforms/web/client/engine-runtime/package.json` 的 `version`（第 54 行） |
| `publish-precompute.yml` | 推送标签 `@tiqian/precompute@*`（第 8-11 行） | npmjs.com | 5 个 npm 包 | `platforms/web/server/core/package.json` 的 `version`（第 43 行） |
| `publish-web-component.yml` | 推送标签 `@tiqian/web-component@*`（第 3-6 行） | npmjs.com | 1 个 npm 包 | `platforms/web/client/web-component/package.json` 的 `version`（第 54 行） |
| `release-registry.yml` | 推送标签 `v*.*.*`（第 2-4 行） | 自建 registry 仓库 `tiqian-cjk/registry`、R2 存储、Pages 站点 | 13 个 bundle，归并为 2 个包 | 标签名去掉 `v` 前缀（第 56 行） |
| `snapshot-precompute.yml` | `workflow_dispatch`，无输入（第 13-14 行） | GitHub Packages | 11 个 npm 包 | `platforms/web/server/core/package.json` 的主版本加 `-snapshot.<UTC 时间戳>`（第 59-70 行） |

发布 8 个 Maven 模块：`tiqian-engine` 由 boring 的 kotlin-f32 publication 发布，其余 7 个平台模块在 `build.gradle.kts:35-67` 的 `publishedModules` 里声明，分别是 `tiqian-jvm-skia`、`tiqian-android-shaping`、`tiqian-android-native-font`、`tiqian-android-rendering`、`tiqian-android-view`、`tiqian-compose`、`tiqian-compose-material3`。

13 个 bundle 在 `release-registry.yml:61` 的 `boring pack` 参数里逐个列出，`boring.json` 里每个 bundle 都声明了 `package` 字段，归并后只有两个包名：`tiqian-engine` 与 `tiqian-protocol`（`boring.json` 里每个 bundle 的 `package.name` 只取这两个值）。

11 个 npm 包在 `snapshot-precompute.yml:634` 的 `expected` 变量里逐个列出：ffi、core、prose、react、precompute、4 个平台二进制包、astro、sveltekit。

## 2. 四处不一致

### 2.1 触发方式有三种，互不联动

- 手工 dispatch：`publish.yml:4`、`publish-snapshots.yml:4`、`snapshot-precompute.yml:14`。
- `v*.*.*` 标签：`release-registry.yml:3-4`。
- `@tiqian/<包名>@*` 标签：`publish-ffi.yml:4-6`、`publish-precompute.yml:9-11`、`publish-web-component.yml:4-6`。

七条通道之间没有任何调用关系。推送 `v1.2.3` 只触发 registry 通道；推送 `@tiqian/ffi@1.2.3` 只触发 ffi 的 npm 发布。两者不会同时发生。

### 2.2 包集合有四套，互不包含

- Maven 侧 9 个模块（`build.gradle.kts:32-67`）。
- npmjs 侧 7 个包：`@tiqian/ffi`、`@tiqian/precompute` 与 4 个平台包（`publish-precompute.yml:246-249`）、`@tiqian/web-component`。
- 自建 registry 侧 2 个包（`boring pack` 的 registry 写出按 `bundle.package` 归并）。
- GitHub Packages 侧 11 个包（`snapshot-precompute.yml:634`）。

没有任何一份清单同时描述这四套集合。同一个名字 `tiqian-engine` 同时出现在 Maven 与自建 registry 两个生态里，含义不同。

### 2.3 版本来源有四种，当前取值已经不一致

- 输入参数：`publish.yml:27`、`publish-snapshots.yml:23`。
- 三个独立的 `package.json`：`publish-ffi.yml:54`、`publish-precompute.yml:43`、`publish-web-component.yml:54`。
- 标签名：`release-registry.yml:56` 把标签去掉 `v` 前缀后写进 `boring.json`。
- 时间戳派生：`snapshot-precompute.yml:59-70` 用 core 包的主版本加 `-snapshot.<UTC 时间戳>`。

三个 npm 包当前的版本互不相同：`@tiqian/ffi@0.1.0-alpha.1`、`@tiqian/precompute@0.1.0-alpha.3`、`@tiqian/prose@0.1.0-alpha.6`。按现有配置，「一次发版一个版本号」无法表达。

## 3. snapshot 的去向

| 生态 | 快照目标 | 可见性 |
| --- | --- | --- |
| Maven | `https://central.sonatype.com/repository/maven-snapshots/`（`build.gradle.kts:89`，由 `publish-snapshots.yml:66` 触发） | 公开，任何人可拉取 |
| npm | `https://npm.pkg.github.com`（`snapshot-precompute.yml:621`） | 私有，需要 GitHub 认证 |
| 自建 registry | 没有快照通道 | 不适用 |

npm 快照只发 GitHub Packages 属于有意设计。`snapshot-precompute.yml:3-12` 的文件头写明快照发布属于 fork 的测试发布，`snapshot-precompute.yml:38-41` 在正式仓库 `tiqian-cjk` 下直接拒绝运行。正式仓库只保留 `@tiqian` 的发布通道。

后果是外部用户无法通过 npm 取得任何快照版本，而 Maven 快照任何人可拉取。统一方案需要决定是否新增一条公开的 npm 快照通道（发布到 npmjs.com，使用 `snapshot` dist-tag）。如果维持现状，发布文档里应写明 npm 快照只对持有 GitHub 认证的 fork 维护者可见。

另外 `snapshot-precompute.yml` 这个名字与内容不符：它发布 11 个包，其中只有 1 个是 precompute 主包。统一方案里应改名。

## 4. 统一方案

### 4.1 单一版本源

新增一个只存版本号的文件（例如根目录 `release-version.json`，只有一个 `version` 字段）。所有发布单元在打包前从它派生版本：

- npm 包：打包前把版本写进各 `package.json`，打包后还原。`snapshot-precompute.yml:59-70` 已有同类的改写与还原做法，可以直接复用。
- Maven 模块：`build.gradle.kts:22-24` 已经读环境变量 `TIQIAN_VERSION`，改成读同一个文件。
- 自建 registry：`tools/align-package-versions.py` 已经按标签版本改写 `boring.json`，改成读同一个文件。

第一步是把三个 npm 包的版本对齐到同一个版本，否则单一版本源没有可写入的值。

### 4.2 单一触发

一个 `v<version>` 标签触发一个编排工作流，内部按通道分 job。三个 `@tiqian/<包名>@*` 标签与 `v*.*.*` 标签合并成一个。保留带 `version` 输入的 `workflow_dispatch` 作为重跑入口。

### 4.3 一份包清单

新增 `release-manifest.json`，每个发布单元一行：名称、生态（maven / npm / registry）、目标仓库、dist-tag、是否快照。编排工作流与各通道脚本都读它。`boring` 的 `pack` 现在从 `boring.json` 推导 registry 包集合，改成读这份清单。

清单需要一条校验：所有发布单元都被某个通道覆盖，且没有单元被两个通道重复发布。

### 4.4 一次发版的动作数

- 改前：2 次 dispatch（Maven 发布，以及按需的 Maven 快照）+ 3 个 npm 标签 + 1 个 `v*.*.*` 标签，共 6 个动作。三个 npm 包的版本还要人工保证一致。
- 改后：1 个动作（推送 `v<version>` 标签，或一次带 `version` 的 dispatch）。

## 5. 迁移代价与风险

1. 已发布的版本不能被覆盖。npm 与 Maven Central 都拒绝重复发布同一版本。编排工作流一次运行失败会留下部分通道已发布、部分未发布的版本，而这个版本号已经用掉。方案必须先做全量预检（逐个目标检查版本是否已存在），再逐通道发布；每个通道 job 可单独重跑，重跑时跳过已存在的版本。规则要写明：任何一个通道接受了某个版本，这个版本号就不能再用在别的构建上。
2. 标签语义不同。npm 的 `@tiqian/ffi@1.2.3` 是包版本指针，可以移动；`v1.2.3` 是 git 引用，不可移动。现在的 npm 通道用「标签必须等于 package.json 版本」做校验（`publish-ffi.yml:56`），registry 通道用「标签名就是版本」（`release-registry.yml:56`）。统一到 `v<version>` 后，npm 通道要改成「标签给出发布版本，打包前把版本写进清单」，校验从「标签等于清单」改成「清单由标签派生」。
3. Maven Central 的暂存发布是人工步骤。`publish.yml:87-97` 调用 Central Portal 的 manual upload 接口，发布动作由人在 Portal 上确认。单标签触发无法替人做这个决定；方案里要么保留这一步为人工，要么明确接受自动发布。
4. GitHub Packages 快照通道只对 fork 开放。`snapshot-precompute.yml:38-41` 在 `tiqian-cjk` 下直接失败。合并触发时必须保证这个 job 在正式仓库上不运行，否则每次正式发版都会失败一次。
5. 风险集中在单个编排工作流。它失败会让多个通道同时停在半途。缓解办法是每个通道 job 独立、可重跑，并且编排工作流的第一步是跨清单一致性检查（版本、包集合、目标仓库），检查不通过就不发布任何通道。

## 6. 未决问题

1. 是否新增公开的 npm 快照通道。
2. Maven Central 的暂存发布是否保持人工确认。
3. 三个 npm 包的版本是否先对齐到同一个版本（当前分别是 alpha.1、alpha.3、alpha.6）。该问题已有结论：
   所有 npm 清单一律由 `tools/align-package-versions.py --npm` 写到标签版本，标签 commit 由此
   定位每个手写包版本；现行流程见 [release-pipeline.md](release-pipeline.md) 的 3 节。
