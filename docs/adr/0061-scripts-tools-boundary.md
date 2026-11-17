# ADR 0061: 仓库脚本与工具的分工

- Status: Accepted
- Date: 2026-11-17
- Relates: [ADR 0060](0060-single-release-entry-and-gate.md)（单一发版入口与发版前总检查）

## Context

`scripts/` 与 `tools/` 在仓库成立以来没有成文的分工。同一性质的文件分别放在两个目录：`scripts/generate-engine-gen.mjs` 是生成命令的入口，`tools/setup-haxe-env.sh` 同样是一条命令的入口却放在 `tools/`；`scripts/release-gradle-tasks.sh` 只被两个入口 source，是被共用的实现。`scripts/cutover/` 保留了迁移期的工作手册与三个一次性脚本，四个文件在仓库里已经没有可执行的引用。

目录缺少分工时，新增文件按作者习惯放置，CI 的调用点分散在两个目录，读者无法从路径判断一个文件能否直接执行。

## Decision

1. `scripts/` 存放流程入口。CI job 与人工命令直接执行的命令文件放在这里；入口按顺序调用其它程序，或在生成、测试之前准备运行环境。当前入口是 `scripts/staging-pipeline.sh`、`scripts/test-engine-rust.sh`、`scripts/generate-engine-gen.mjs` 与 `scripts/setup-haxe-env.sh`。
2. `tools/` 存放可复用的实现。被入口、git hook、构建脚本或文档直接调用的单步程序放在这里；同一实现被多处调用时只保留 `tools/` 里的一份。当前实现是七个 Python 发布程序、`tools/release-gradle-tasks.sh`、`tools/doc-style/check.py`、`tools/git-hooks/` 与四个 `tools/unicode-*` 数据生成器。
3. 入库的构建输入数据放在 `engine-haxe/data/`。生成期创建的目录写入 `.gitignore`，不进入 `scripts/` 或 `tools/` 的入库树。`tools/unicode-data/` 属于生成期目录：`reflaxe.unicode.GraphemeData` 按检出根解析该路径，README.md 的割接期临时前置登记它在 `t-mwcxehpz-fict` 完成后取消。
4. 工作手册与运行手册放在 `docs/`。`scripts/` 只保留可执行文件，不保留 Markdown 文档。
5. 构建模块不放在 `tools/`。`:tools:engine-probes` 是 Gradle 模块，迁移它会改动 `settings.gradle.kts` 与 `build.gradle.kts`，列入 engine、probes 与 jvm 那一轮，本轮保留原路径。

## Consequences

- `tools/setup-haxe-env.sh` 移动到 `scripts/setup-haxe-env.sh`；`scripts/release-gradle-tasks.sh` 移动到 `tools/release-gradle-tasks.sh`。`.github/workflows/` 的九个文件、`flake.nix`、`README.md`、`engine-haxe/README.md`、`platforms/web/client/engine-runtime/build-runtime.ts` 与 `docs/` 的路径同步更新。
- `scripts/cutover/` 的四个文件删除：`cutover-seat-handbook.md` 是割接期工作手册，`tq-vendor-check.sh` 检查的入库副本已由 `t-mwgrgela-p83q` 删除，`tq-pin-advance.sh` 的职能已由 `nix flake lock` 接手，`tq-mac-gen.sh` 没有引用与文档。
- `docs/release-pipeline-convergence.md` 指向已删除脚本的路径改为叙述，历史结论不变。

## Alternatives

- 合并 `scripts/` 与 `tools/`：入口与实现混在一个目录，读者仍需逐文件判断能否直接执行。
- 按语言分目录（shell、Python、mjs）：跨语言的流程入口被拆开，CI 的调用点无法集中。
- 保持现状，只在文档中说明：新增文件的放置方式仍依赖作者习惯，本次的两个入口继续分处两个目录。
