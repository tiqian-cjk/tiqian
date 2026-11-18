# ADR 0063: 可执行文件只保留 tools/ 一个目录

- Status: Accepted
- Date: 2026-11-18
- Supersedes: [ADR 0061](0061-scripts-tools-boundary.md)（仓库脚本与工具的分工）
- Relates: [ADR 0060](0060-single-release-entry-and-gate.md)（单一发版入口与发版前总检查）

## Context

ADR 0061 把仓库分成两个目录：`scripts/` 放流程入口，`tools/` 放被入口调用的实现。
它的判据是「CI job 与人工命令直接执行的命令文件放在 `scripts/`」。按这条判据，`tools/`
里的 `release-gate.py`、`release-matrix.py`、`align-package-versions.py`、
`compile-bundles.py`、`project-file.py`、`module-test-tasks.sh`、`release-gradle-tasks.sh`
全部都是 CI 步骤直接执行的命令，应当与 `setup-haxe-env.sh` 同处一个目录。ADR 0061 把它们
留在 `tools/` 的依据不是判据，是它自己列的清单，所以新增文件无法从判据推出该放哪里。

仓库里也没有任何检查在读这两个目录的布局，放置方式仍然依赖作者习惯，这正是 ADR 0061
在 Context 里写下的问题。2026-11-18 新增的 `publish-contract.py` 与 `check-npm-package.sh`
就落在灰区：它们是单步实现，也由 CI 步骤直接执行。

把「入口」与「实现」重划成可判定的形式只剩一条人为约定：多步编排留在 `scripts/`，其余
全进 `tools/`。按这条约定，`scripts/` 只剩 `staging-pipeline.sh` 一个文件，两个目录为
一次判断付的代价超过它能提供的信息。

## Decision

1. 可执行文件只放在 `tools/`。CI job、人工命令、git hook 与构建脚本调用的一切命令文件
   都在这里，路径不再表达「能否直接执行」这一信息，改由每个文件头部的用法注释表达。
   当前可执行文件是四个流程命令（`staging-pipeline.sh`、`test-engine-rust.sh`、
   `generate-engine-gen.mjs`、`setup-haxe-env.sh`）与发布实现、`doc-style/`、`git-hooks/`、
   `unicode-ranges/` 等实现文件。
2. 仓库不再有顶层 `scripts/` 目录。子目录里的 `scripts/`（例如
   `platforms/web/server/core/scripts/`）属于各自的包，不受本决定约束。
3. 入库的构建输入数据放在 `engine-haxe/data/`；生成期创建的目录写入 `.gitignore`，
   不进入 `tools/` 的入库树。
4. 工作手册与运行手册放在 `docs/`，`tools/` 只保留可执行文件与它们的实现。
5. 构建模块不放在 `tools/`。`:tools:engine-probes` 是 Gradle 模块，保留原路径。

## Consequences

- 四个命令文件从 `scripts/` 移到 `tools/`，顶层 `scripts/` 目录删除。
- 引用同步 27 个文件：10 个 workflow、`flake.nix`、`settings.gradle.kts`、`.gitignore`、
  两个 `Cargo.toml` 注释、`platforms/web/client/engine-runtime/build-runtime.ts`、
  `README.md`、`AGENTS.md`、`engine-haxe/README.md`、三份 `docs/` 文档，以及被移动的
  四个文件自身。旧路径在入库文本中 0 命中（ADR 0061 按决策记录保留原文，其 Status 标为
  Superseded）。
- `tools/staging-pipeline.sh` 与 `tools/setup-haxe-env.sh` 仍按
  `dirname "${BASH_SOURCE[0]}"/..` 解析仓库根，移动一层后该表达式的结果不变。

## Alternatives

- 保留 ADR 0061 的分工并给它加机械检查：判据本身无法决定新文件的位置，检查只能复制一份
  清单，清单变动时两处都要改。
- 按语言分目录（shell、Python、mjs）：跨语言的流程入口被拆开，CI 的调用点无法集中。
- 保持现状不改：新增文件继续落在灰区，本次两个新文件就是例子。
