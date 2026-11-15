# 割接席位手册（Stage 1）

本文件是割接各席位共用的执行规则，任务书里会引用它。任务书里的范围与验收判据优先。

## 0. 先读，再动手

1. 生成器修订是 `tiqian/.haxelib/boring/git` 的 HEAD（**以 `git -C <你的检出>/.haxelib/boring/git rev-parse --short HEAD` 实测为准**，本手册不固定版本号；每一轮读数都要带上你实测到的那个修订）。禁止在该目录内写任何文件（PIT-63）。收工前核对 `git -C tiqian/.haxelib/boring/git status --porcelain` 为空。
2. 判断「某个 Haxe 构造在目标上支持什么形态」的第一权威是 `tiqian/.haxelib/boring/git/docs/specs/**`，第二是 boring 自己的样本 `samples/**` 与参考生成物 `reference/**`。生成端源码是第三顺位。
3. 读 spec 时按「文件:行 + 该行原文片段」记笔记，只写行号不算。P1 的笔记样板见 `tiqian/engine-haxe/protocol-spec-notes.md`。

## 1. 回话闸门

读完 spec、动手改代码之前，先回队长三行：①打算用哪些构造（写出类型名与调用）；②每条依据哪份 spec 的哪一条（文件加行号）；③哪些地方判断需要先取证才能定形态、取证对象是哪个生成端的哪个函数。收到确认再开始改。

## 2. 禁止项（按失败模式点名）

- 不许手写字节编解码、UTF-8 编码、IEEE754 位运算拆分。字节一律经 `haxe.io.Bytes` / `BytesBuffer`（spec stdlib/01）；f64 位形经 `haxe.io.FPHelper`（spec stdlib/05）。
- 不许为目标差异在 Haxe 源里加条件分支，也不许为目标单独写一份实现。
- 不许因为某个构造在某个目标上「不灵」就改源码形态去躲。触发点定义：**只要你在 Haxe 源里冒出「换个写法让这个目标过」的念头，那就是触发点**；要么按第 3 条补齐四步取证，要么停下报告，没有第三条路。
- 不许 hand-write 链文件里的输出目录 define。输出目录一律由束驱动器从 `outRoot`/`<id>` 派生（spec 59:62-67）。
- 不许直接跑 `cargo test`。只用 `cargo build --lib --tests`，或同时给 `BORING_TEST_TIMEOUT_MS` 与进程的 `timeout`（PIT-71/PIT-87：不加时限会无限转，已烧过 47 分钟）。
- 生成前清空输出目录（PIT-54：残留文件会伪装成当前源码的错误）。
- 不许改 `boring/` 主检出；本阶段 Rust 生成端的改动由队长统一安排。

## 3. 取证模板（任何「生成器不支持/有缺陷」的结论都要齐）

① 被编译的 Haxe 源结构（文件加构造）；② 渲染它的生成端函数与行号（在 pin 内）；③ 生成出来的目标文本片段与行号；④ 目标编译器或运行时的原始报错。缺任一步只能写「未验证」，且不得据此改源码形态。
另：凡是「目标侧签名或参数序与源码不一致」的结论，第三步之后必须再从 `samples/boring/**` 与对应 spec 抄下同一调用的规定签名做比对（判据 PIT-159：生成端按源码参数序转发，签名不符时多半是源码写错）。

## 4. 束与生成

- 束登记在 `tiqian/boring.json`。P1 已建立 `protocol-ts` 与 `protocol-rust` 两束，roots 文件是 `engine-haxe/targets/protocol-ts.hxml` 与 `protocol-rust.hxml`；新模块把根类加进去即可，不要新开束（除非任务书要求）。
- 生成一律走驱动器：`cd <tiqian 检出> && nix develop -c bash -c 'node ${BORING_ROOT}/out/bundle/driver.js gen protocol-rust --project boring.json'`（ts 同理）。生成前先 `rm -rf engine-haxe/out/protocol-* `。
- 生成物去向：Stage 1 把生成物搬进仓库，TS 搬进 `platforms/web/server/core/src/protocol-gen/`（P1 的做法），Rust 搬进 `platforms/web/server/precompute/protocol-gen/`（workspace member，`engine` 经 path 依赖）。**以上为收敛前状态。** 当前 TS 侧的 `platforms/web/client/core/src/sampler/snapshot/protocol-gen/`、`platforms/web/client/core/src/sampler/snapshot/prepared-dom-gen/` 与 `platforms/web/server/core/src/protocol-gen/` 已删除（`t-mwgrgela-p83q`），`@tiqian/core` 与 `@tiqian/precompute` 依赖 npm 上的 `tiqian-protocol@0.1.0-alpha.8` 与 `tiqian-shared@0.1.0-alpha.8`；Rust 侧的 `platforms/web/server/precompute/protocol-gen/` 改为构建期生成（`t-mwgxnvsu-wn10`）：`node scripts/generate-engine-gen.mjs` 在 `nix develop` 内运行 `boring gen protocol-rust`，把 `engine-haxe/out/protocol-rust/gen` 复制到该目录，`platforms/web/server/precompute/Cargo.toml` 把它列入 `exclude`，`platforms/web/server/precompute/engine/Cargo.toml` 以 `path = "../protocol-gen"` 依赖它，`.gitignore` 以 `/platforms/web/server/precompute/protocol-gen/` 排除它。搬运仍只从驱动器产物搬，结构与 gen 根逐项一致。
- **搬运必须双向可核（PIT-174）**：搬完跑 `bash ${WORKSPACE}/scripts/tq-vendor-check.sh <tiqian 检出>`。extras（挂载里有、驱动不产）与 full 挂载的 missing 都必须为零；非零不许交回、更不许 pin advance。挂载换了路径就在脚本登记表的重映射字段里声明（例：client 的 `Revision.ts` ← `org/tiqian/protocol/Revision.ts`），不要在树里留无出处的文件。
- **新增测试类必须在每个目标的 roots hxml 里同时加根**。漏加会被搬运成「看着在、其实不编译」的死文件；本轮实测两例（`snapshot_table_binary_test.rs` / `snapshot_table_test_support.rs`）；只查 missing 的比对抓不到这一类，必须双向查。

## 5. 验收与证据

- 验收命令按任务书写，常见的有：`cargo build -p tiqian-precompute --lib --tests`（在 mac；先生成 `protocol-gen` 与 `engine-gen`，见第 4 节）、`cargo build --manifest-path platforms/web/server/precompute/protocol-gen/Cargo.toml --lib --tests`（单独编生成的协议 crate）、`cargo test -p tiqian-precompute canonical`、`(cd platforms/web/server/core && npm test)`、`(cd platforms/web/client/engine-runtime && npm test)`、`bash engine-haxe/tools/gates.sh all`。
- Rust 侧的生成与编译默认在 mac 上做。mac 一次只跑一轮整链，走 `/tmp/tq-mac-gen.lock`（`scripts/tq-mac-gen.sh` 自带）；产物只落 `~/tq-dc/<label>`，不要写 mac 内置盘。mac 8 核 16 GB，别并行跑两条 cargo 或 cargo 与 swiftc。
- **本机例外（2026-09-27 加，mac 不可用时）**：先按第 4 节生成 `protocol-gen`；生成出来的协议 crate 是小 crate（`protocol-gen` 十几到二十几个 `.rs`、无第三方依赖），允许在本机编：`cp -a <树>/platforms/web/server/precompute/protocol-gen/. /tmp/<label>-pg/`，再 `XDG_CACHE_HOME=/tmp/tq-nix-cache nix develop -c bash -c 'cd /tmp/<label>-pg && CARGO_TARGET_DIR=/tmp/<label>-pg-target cargo build --lib --message-format=short'`，跑完删掉 target 目录（实测 2.7 MB）。**只对小 crate 生效**：整棵引擎树的生成与构建仍然只许在 mac 上做（PIT-81：一棵树 0.8 GB）。
- 证据格式：`<数字> @ <修订> @ <生成配置>`，并写清跑的是哪棵树、哪条路径（PIT-48 / TCN-16）。
- 提交在 tiqian 仓库内做，Conventional Commits 单行标题；**只落在自己的分支上，不许直接提交到 main**（main 由队长合并，别的席位同时读它）。若你的修复会立刻解除别人的阻塞，先提交到自己分支并在交回里说明「建议优先合并」，由队长决定是否插队。

## 6. worktree 与时间盒

- 每席用自己的 tiqian worktree：`git -C ${TIQIAN_ROOT} worktree add ../tiqian-wt-<席名> -b <分支> main`，然后在该 worktree 里 `bash tools/setup-haxe-env.sh`（补 `.haxelib` 与 `tools/unicode-data`；golden 机制已随 Kotlin 割接删除）。不要几个人共用主检出（PIT-26）。
- 时间盒见任务书。把绕行写进提交比不提交更糟；第一个提交允许只含束登记与 spec 阅读笔记。
- **交回前 worktree 必须干净**：未完成的部分要么提交成一个自洽的提交，要么还原；带着未提交改动交回会让读数混入它们（PIT-79），也让人无法判断交回的是哪一版。已出现两次同类问题。
- 交回格式：一句话总括 + 五条（任务与分支；交付物与路径；跑过的命令与原始读数含修订；没做完的部分与卡点；下一步建议）。

## 7. 通道容量（2026-09-27 起）

本机推理服务（`ninfer-serve`，模型 qwen）已调参：`--pending-timeout-ms 900000`（Admission 等待 15 分钟）、`--max-pending-requests 64`、`--host-kv-mib 49152`（48 GiB）、`--host-state-slots 48`、容器 shm 64 GiB。**此前「本地通道只能跑一席、并发会报 inference request expired while waiting for admission」的限制已解除**：本地通道现在可同时容纳 3–4 席。但席位自己是长上下文（历史越长，Prefill 越贵），所以仍按下面的配比使用：

- 本地 qwen：**2–3 席**（适合机械与验证类任务，也够做协议模块这种中量级工作）
- zai/GLM：**2–3 席**（5 小时滚动配额，写排班时带复核时间）
- ty：**2 席**（复杂任务优先）

## 8. 环境坑（各席实测，直接照用，别再各踩一遍）

- **Gradle 必须在 `nix develop` 里跑**：PATH 上的 java 21 缺 `java.logging`，wrapper 起不来。
- **`GRADLE_USER_HOME` 用工作区共享的那一份**：`${WORKSPACE}/.gradle-home`（`~/.gradle` 的锁文件 Permission denied，不能用）。**不要各席在自己的 worktree 里再建一份**；实测每个副本约 2.5 GB，四席并行就占用 10 GB，本机 /home 现在只剩 33 GB。
- **`XDG_CACHE_HOME=/tmp/tq-nix-cache`**：`~/.cache/nix` 只读。
- **npm 侧先在 worktree 根 `npm install`**：`tsc` 来自 workspace devDeps，不装就没有。
- **`platforms/web/client/engine-runtime` 的 `npm run build:runtime` 会清空重建 `runtime/`**：vendored 生成物一律放 `platforms/web/client/engine-runtime/engine-gen/`，再由构建步骤复制进 runtime 产物（`package.json` 的 `files` 发布 `runtime/` 与 `engine-gen/`）。
- **Node 的 strip-types / transform-types 直载生成的 TS 会失败**（生成模块对纯类型模块做值导入），必须走 tsc 路线：`target es2022 + module esnext + moduleResolution bundler + allowImportingTsExtensions + rewriteRelativeImportExtensions`；生成代码不动，若个别诊断（如 `FontRoleContext` 的 TS2322）需要放宽，**只许写在 vendored 目录自己的 tsconfig 里并注明取消条件**（指向里程碑 30 的 T1/T2），不许改包或工作区的配置。
- **跨机器复核要同步完整源码树**：只同步部分子目录会让读相对路径的防漂移断言假失败（实测过一次，失败信息看起来像「文件没生成」）。
