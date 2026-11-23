# 发版管线收敛：对照表与设计

本文记录 tiqian 现有发版工作流在打包与发布上的对照表，以及以 `boring.json` 的 bundle 列表为唯一输入的收敛设计。本文列出四点已确认的结论与需要分阶段完成的部分，不改动任何工作流文件。

## 1. 范围与结论

- 仓库有 15 个工作流文件；第 2 节的对照表覆盖其中 10 个与发版有关的文件，合计 2563 行（`wc -l .github/workflows/*.yml` 计数）。表外的 5 个文件是 `ci-native-precompute.yml`（268 行）、`build-neon-precompute.yml`（398 行）、`module-tests.yml`（155 行）、`bundle-verification.yml`（67 行）与 `staging-pipeline.yml`（95 行）；`ci-native-precompute.yml` 与 `build-neon-precompute.yml` 不发布，与 `bundle-verification.yml` 一起作为 `release-gate` 的 requiredLanes（`release-manifest.json:9-22`）。
- 同一批 boring 驱动输出有两条生产路径：各发布工作流自带的 npm 构建与 Gradle 构建，以及 `release.yml` 的 pack job 里的 `boring pack`（收敛前在 `release-registry.yml:86`；同一次 pack 也写出 registry 树）。
- `boring.json` 声明 13 个 bundle；收敛前 `release-registry.yml:86` 手写 12 个，收敛后列表来自 `tools/release-matrix.py --list-bundles`。
- `shared` 没有对应的 bundle，因此没有任何发布步骤产出该包。
- 第 5 节记录两条独立缺陷的形态与修复位置。

## 2. 现有工作流对照表

> **第 2 节的对照表记录当前工作流文件的状态。** 每行括号里的行数由 `wc -l .github/workflows/<文件名>` 得到，行内的行号由 `grep -n` 在同一个文件里定位。pack 已集中在 `release.yml` 的 pack job（:93-99），`release-registry.yml` 只下载并使用 pack 的制品。第 3 节的对照表记录收敛前的 bundle 登记，见该表下的说明。生成物的去向在收敛后另有变化，见 2.1。

| 工作流（行数） | 打包的包 | 工具 | 发布目标 | 凭据 | 与 boring pack 的重复 |
| --- | --- | --- | --- | --- | --- |
| `.github/workflows/release-gate.yml`（51） | 无 | `python3 tools/release-gate.py`（:45-51） | 无 | `github.token` | 无 |
| `.github/workflows/publish-ffi.yml`（202） | `@tiqian/ffi` | `node tools/generate-engine-gen.mjs ts`（:106-111）运行 `boring gen ts` 与 `boring gen protocol-ts`（`tools/generate-engine-gen.mjs:38-56`），`npm run verify:release` 产出 tarball（:137-140） | `registry.npmjs.org`，`alpha` 标签，随后 `latest` | OIDC（`id-token: write`，:28）、`NPM_DIST_TAG_TOKEN` | 输入是 bundle `ts` 与 `protocol-ts` 的生成树；`release.yml` 的 pack job 对同两个 bundle 运行 `boring pack`（:93-99） |
| `.github/workflows/publish-core.yml`（185） | `@tiqian/core` | `boring pack protocol-ts shared-ts`（:89-94，`tsc` 由 `BORING_PACKAGE_TSC` 指向 `typescript@5.9.3`），再 `npm run build` 与 `npm pack`（:113-123） | npmjs，`alpha` 与 `latest` | OIDC（:31）、`NPM_DIST_TAG_TOKEN` | `src/sampler/snapshot/protocol-gen` 与 `prepared-dom-gen` 曾是 `protocol-ts` 的入库副本；两个目录已随 `t-mwgrgela-p83q` 删除，见 2.1 |
| `.github/workflows/publish-web-component.yml`（187） | `@tiqian/web-component` | `boring pack protocol-ts shared-ts`（:101-107）写出包清单，`npm run verify:release` 产出 tarball（:122-125） | npmjs，`alpha` 与 `latest` | OIDC（:27）、`NPM_DIST_TAG_TOKEN` | 发布单元不重复，依赖 `@tiqian/core`；与 pack 的重复只在 :101-107 重写 `protocol-ts` 与 `shared-ts` 的包清单 |
| `.github/workflows/publish-precompute.yml`（408） | `@tiqian/precompute` 与 4 个平台二进制包（:131-138） | `cargo build`（:185-186）、`npx neon dist`（:187）、`npm pack`（:200、:271） | npmjs，`alpha` 与 `latest` | OIDC（:292）、`NPM_DIST_TAG_TOKEN` | 输入是 `protocol-rust`、`protocol-ts`、`engine-rust` 的生成树；其中 `protocol-rust` 与 `engine-rust` 为构建期生成的目录，`protocol-ts` 的入库副本已删除，见 2.1 |
| `.github/workflows/publish.yml`（184） | 7 个 Maven 模块（`build.gradle.kts:36-67`，`grep -c 'to PublishedModule' build.gradle.kts` 得 7） | Gradle KMP；生成树只由 boring 的发布工程编译，`settings.gradle.kts` 把该工程的 `:engine` 模块注册为 `:boring-kotlin-f32`（:92-93、:116），`gradle.properties:12` 的 `kotlinGenDir` 指向本仓生成树，`:126-127` 先运行 `boring gen kotlin-f32` 写出该目录 | Central staging，由人在 Portal 确认（:174-184） | `MAVEN_CENTRAL_USERNAME`、`MAVEN_CENTRAL_PASSWORD`、`SIGNING_KEY_ID`、`SIGNING_KEY`、`SIGNING_PASSWORD` | `kotlin-f32` 与 `protocol-kotlin` 既由 Gradle 编译，又由 `boring pack` 写出 maven 目录（`PackageArtifacts.hx:347-397`） |
| `.github/workflows/release-registry.yml`（104） | `tiqian-engine` 与 `tiqian-protocol` 的 registry 元数据；制品由 pack job 产出 | 下载 pack job 的 `release-artifacts` 与 `registry-tree`（:43-53），`tools/check-registry-tree.py` 核对树与制品（:55-59） | GitHub Release（:61-67）、`tiqian-cjk/registry`（:69-92）、Pages（:93-104） | `REGISTRY_REPO_TOKEN`、`PAGES_DEPLOY_HOOK` | 收敛后这条工作流不再运行 `boring pack`，只消费 `release.yml` 的 pack job 写出的制品 |
| `.github/workflows/release.yml`（362） | 无；pack job 产出全部制品与 registry 树 | `tools/release-matrix.py`（:49-62）、`boring pack`（:93-99）、`tools/compile-bundles.py`（:105-106），并按依赖顺序调用上述工作流（:309-361） | 无 | `secrets: inherit` | 这条工作流包含收敛后的 `boring pack` 路径本身 |
| `.github/workflows/publish-snapshots.yml`（69） | 7 个 Maven 模块 | Gradle（:68-69 的 `publishTiqianToCentralSnapshots`，`build.gradle.kts:251-255`） | Central snapshots | `MAVEN_CENTRAL_USERNAME`、`MAVEN_CENTRAL_PASSWORD` | 无 |
| `.github/workflows/snapshot-precompute.yml`（811） | 11 个 npm 包（4 个客户端包，:697 断言 `-eq 4`；4 个平台二进制包，:787；1 个主包，:790；2 个集成包，:550 断言 `-eq 2`） | `npm pack`，时间戳版本（:67-74） | `npm.pkg.github.com`（:741） | 仓库内置凭据 | 无 |

表中每个数字的复核命令：

```shell
wc -l .github/workflows/*.yml                        # 每行括号里的行数
ls .github/workflows/*.yml | wc -l                   # 15 个工作流文件
wc -l .github/workflows/{release-gate,publish-ffi,publish-core,publish-web-component,publish-precompute,publish,release-registry,release,publish-snapshots,snapshot-precompute}.yml | tail -n 1   # 2563
grep -c 'to PublishedModule' build.gradle.kts        # 7 个 Maven 模块
```

### 2.1 收敛后 protocol-gen 的位置

TS 侧的入库副本已删除。`platforms/web/client/core/src/sampler/snapshot/protocol-gen/`、`platforms/web/client/core/src/sampler/snapshot/prepared-dom-gen/` 与 `platforms/web/server/core/src/protocol-gen/` 在收敛前是 `protocol-ts` 的入库副本，`t-mwgrgela-p83q` 完成后随提交 `6d1a305ea` 从仓库删除；`platforms/web/client/core/package.json` 与 `platforms/web/server/core/package.json` 改为依赖 npm 上的 `tiqian-protocol@0.1.0-alpha.8` 与 `tiqian-shared@0.1.0-alpha.8`。`scripts/cutover/tq-vendor-prepared-dom.sh` 与 `platforms/web/server/core/scripts/copy-protocol-gen.sh` 同步删除。

Rust 侧的 `platforms/web/server/precompute/protocol-gen/` 改为构建期生成（`t-mwgxnvsu-wn10`）。`tools/generate-engine-gen.mjs` 的 rust 分支在 `boring gen engine-rust` 之后运行 `boring gen protocol-rust`，把 `engine-haxe/out/protocol-rust/gen` 复制到该目录；`platforms/web/server/precompute/Cargo.toml` 的 `exclude` 列出 `protocol-gen`，`platforms/web/server/precompute/engine/Cargo.toml` 仍以 `tiqian-protocol-gen = { path = "../protocol-gen" }` 依赖它，`.gitignore` 以 `/platforms/web/server/precompute/protocol-gen/` 排除该目录。`.github/workflows/build-neon-precompute.yml` 在生成 job 上传 `protocol-gen` 制品，并在 binaries job 下载到同一路径。

## 3. bundle 对照表

| bundle | target | package | 制品名 | 生态（`tools/release-matrix.py` 的映射） | pack 列表（收敛前的 `release-registry.yml:86`，现在是 `release.yml:93-99` 的 pack job） | 入库副本（收敛前 `scripts/cutover/tq-vendor-check.sh` 的登记行；该脚本已删除） |
| --- | --- | --- | --- | --- | --- | --- |
| `kotlin-f32` | kotlin | `tiqian-engine` | `tiqian-engine-f32` | maven | 是 | :78、:85-88 |
| `kotlin-f64` | kotlin | `tiqian-engine` | `tiqian-engine-f64` | maven | 是 | 无（Gradle 只编译 f32 的生成树） |
| `ts` | ts | `tiqian-engine` | `tiqian-engine` | npm | 是 | :72、:92 |
| `swift-f32` | swift | `tiqian-engine` | `tiqian-engine-f32` | swift | 是 | 无 |
| `swift-f64` | swift | `tiqian-engine` | `tiqian-engine-f64` | swift | 是 | 无 |
| `dart` | dart | `tiqian-engine` | `tiqian-engine` | pub | 是 | 无 |
| `protocol-ts` | ts | `tiqian-protocol` | `tiqian-protocol` | npm | 是 | :61-63、:71、:92 |
| `shared-ts` | ts | `tiqian-shared` | `tiqian-shared` | npm | 是 | 无 |
| `protocol-rust` | rust | `tiqian-protocol` | `tiqian-protocol` | cargo | 是 | :59 |
| `protocol-dart` | dart | `tiqian-protocol` | `tiqian-protocol` | pub | 是 | 无 |
| `protocol-kotlin` | kotlin | `tiqian-protocol` | `tiqian-protocol` | maven | 是 | :93 |
| `protocol-swift` | swift | `tiqian-protocol` | `tiqian-protocol` | swift | 是 | 无 |
| `engine-rust` | rust | `tiqian-engine` | `tiqian-engine` | cargo | 是 | :60 |

表中「入库副本」列记录收敛前 `scripts/cutover/tq-vendor-check.sh` 的登记行。该脚本已随割接期清理删除（`ls scripts/cutover` 报 No such file or directory，`git ls-files` 中没有该路径），列中的行号是脚本删除前的行号，当前仓库无法复核。`protocol-rust` 与 `engine-rust` 在收敛后改登记为构建期生成的挂载点，`protocol-ts` 的入库副本已删除（见 2.1）。

`engine-rust` 不设置 `package-artifact-stem`，cargo 目录名与文件名都取包名 `tiqian-engine`；精度在 Rust 编译期由 cargo feature `f32` 选择，不再有第二个 Rust 制品。`tools/release-matrix.py` 的 `EXCLUDED_BUNDLES` 当前为空表。

## 4. 研究结论

1. 重复的形态是同一 bundle 的生成树存在两条消费路径。收敛前 `scripts/cutover/tq-vendor-check.sh`（已随割接期清理删除）的登记表把驱动输出登记为挂载点，登记到的生成树全部是入库副本并交给 npm 与 Gradle 构建；`release-registry.yml` 对相同 bundle 运行 `boring pack`。两条路径各自改动时没有交叉检查。收敛后 `protocol-rust` 与 `engine-rust` 的挂载点改为构建期生成的 gitignored 目录，`boring pack` 只剩 `release.yml` 的 pack job（:93-99）一处。
2. 收敛前覆盖范围由三处手写清单决定：`release-registry.yml` 的 12 个 id、`release-manifest.json` 的 2 个包名、各 `publish-*.yml` 内的包路径。`boring.json` 新增 bundle 时，三处都需要人工修改。现在 registry 单元的包名由 `packagesFrom` 从 `boring.json` 派生（`release-manifest.json:126-146`），bundle 列表由 `tools/release-matrix.py --list-bundles` 给出（13 个）。
3. `shared` 没有 bundle。prepared-dom 与 shared-gen 产自 `protocol-ts`，收敛前分别以入库副本形式进入 `@tiqian/core` 与 `platforms/web/server/core`；这些副本已随 `t-mwgrgela-p83q` 删除，两个包改为依赖已发布的 `tiqian-protocol@0.1.0-alpha.8` 与 `tiqian-shared@0.1.0-alpha.8`（见 2.1）。`boring pack` 写出的 registry 元数据只覆盖 `tiqian-engine` 与 `tiqian-protocol` 两个包。
4. 官方仓库与私有 registry 可以互相校对的依据已经存在：registry 元数据的 digest 字段由 `boring pack` 对制品文件计算（`release.yml:93-99` 的同一次 pack），两边记录同一个文件时摘要相同。

## 5. 已发现并已修复的两条缺陷

### 5.1 publish.yml 缺少生成 Kotlin 源的步骤

缺陷形态：`engine/build.gradle.kts` 曾把 `commonMain` 的 Kotlin srcDirs 指向 `engine-haxe/out/kotlin-f32/gen`，`.gitignore:44` 排除 `/engine-haxe/out/`，`publish.yml` 全文没有调用 boring 或其它生成步骤，这条工作流在干净的检出上缺少它发布的输入。修复后的形态：编译该生成树的工程是 boring 的发布工程，`settings.gradle.kts:68` 指向 `.haxelib/boring/git/tools/kotlin-publication`，该工程的 `engine/build.gradle.kts:66-68` 把 `commonMain` 的 srcDirs 指向 `genDir`；`publish.yml:126-127` 在 Gradle 之前运行 `boring gen kotlin-f32` 写出该目录，`:105-119` 的注释说明这一步留在发布作业里的理由。相关任务：`t-mwgl8lkb-59i3`。

### 5.2 release-registry.yml 的 Sync compiled registry tool 步骤条件不成立

缺陷形态：`release-registry.yml` 的 `Sync compiled registry tool` 步骤条件曾是 `[ -d packages/registry/gen ]`。main 上不存在 `packages/registry`（registry 工具在 boring 的 `packages/registry`），该条件为假，步骤不会执行。该步骤已按第 8 节第 3 步删除；当前文件 104 行，`grep -n 'packages/registry' .github/workflows/release-registry.yml` 没有输出。

## 6. 收敛设计

### 6.1 单一输入与编排

- 新增 `tools/release-matrix.py`。它读 `boring.json`，自己去注释并解析 JSON，把 target 到生态的映射与各生态的状态写在自己内部；仓库里不再有 `tools/registry-metadata.py`。它校验每个 bundle 有 `package.name/version/license`（`driver Main.hx:324-325` 的 pack 前置条件）。`--list-bundles` 取代 `release-registry.yml` 里手写的 12 个 id 列表；`--matrix` 输出 GitHub Actions 用的 `include` 列表，并接受 `--version`：`boring.json` 的 `package.version` 是占位值，`tools/align-package-versions.py` 只在 pack 的检出里把它改成标签版本，所以 matrix 的制品名也按标签版本生成。
- `--check` 的断言：matrix 的 bundle 集合等于 `boring.json` 的集合；每个 bundle 的 target 有对应生态；每个用到的生态在矩阵里为启用或显式未启用（未启用必须写原因）；没有进 pack 的 bundle 必须在排除表里有显式声明与原因；同 (生态, registryName, 版本) 的制品名冲突直接失败。
- matrix 区分两个维度：`packed` 表示是否进 pack 与私有 registry，`official` 表示是否发到该生态的官方仓库（由 `ECOSYSTEM_STATE` 决定）。`--check` 的汇总输出为 `packed for the registry: 13` 与 `published to official registries: 9` 两行；`--matrix` 的条目同时带这两个字段。
- 每个 publish 实例先核对制品：pack job 写 `release-artifacts/SHA256SUMS`，实例按 bundle 重算 sha256 并与该清单比对，对不上的实例失败；随后 npm 用 `npm publish --tag alpha` 与 dist-tag 校验（沿用 `publish-ffi.yml:142-151`、:170-190），swift 把 zip 上传 R2（`release.yml:261-285`），maven 在过渡态仍由 maven job 发布。
- `release.yml` 增加 matrix job 与一次 `boring pack` job。发布 job 用 `strategy.matrix` 按 platform 从 matrix job 展开。
- 制品位置固定：`engine-haxe/out/<id>/<stem>-<version>.<后缀>`（`PackageArtifacts.hx:130-216`、`:937-941`），Kotlin 为 `engine-haxe/out/<id>/maven/<group>/<name>/<version>/`（`PackageArtifacts.hx:347-397`）。
- 顺序：`release-gate`、matrix 与 pack、各生态发布、registry 最后写元数据。`release-manifest.json:126-146` 的 `last` 语义与 `tools/release-gate.py:373-379` 的检查保持不变。

### 6.2 各生态的步骤与凭据

| 生态 | 目标 | 步骤 | 凭据 | 现状 |
| --- | --- | --- | --- | --- |
| npm | `registry.npmjs.org` | `npm publish <tgz> --tag alpha`，随后把 `dist-tag` 指向 `latest` | OIDC、`NPM_DIST_TAG_TOKEN` | 已具备（`publish-ffi.yml:46-53`、:142-151、:170-190；`release.yml:208-260`） |
| cargo | crates.io | `cargo publish --token` | `CARGO_DIST_TOKEN` | 预留，未启用（`docs/release-pipeline.md:49`） |
| maven | Central staging | 过渡态由 Gradle 发布 7 个模块（`build.gradle.kts:35-67` 的 `publishedModules`，任务 `publishTiqianToCentral` 在 `:245-249`）；目标形态见 7.1 | `MAVEN_CENTRAL_*`、`SIGNING_KEY_*` | 已具备，Portal 由人确认（`publish.yml:174-184`） |
| pub | pub.dev | `dart pub publish` | 需要新增 pub 凭据 | 未启用 |
| swift | 无中心仓库 | zip 上传 R2，registry 提供 SwiftPM 接口 | `R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` | 已具备（`release.yml:261-285`） |
| registry | `tiqian-cjk/registry` 与 Pages | 写元数据树、提交、触发 Pages | `REGISTRY_REPO_TOKEN`、`PAGES_DEPLOY_HOOK` | 已具备 |

未确认包名占用与凭据的生态在 matrix 中记为未启用，由 matrix 显式列出。

### 6.3 私有 registry 与官方仓库记录同一批制品

registry 元数据由同一次 pack 写出（`release.yml:99` 的 `--registry-out`、`--owner`、`--repo` 与 `--asset-base` 四个参数）；`url` 与 `archive` 指向该次 pack 产出的制品位置（GitHub Release 资产；swift 用 R2，`release.yml:261-285`），digest 由 pack 对制品文件计算。官方仓库与私有 registry 记录同一份字节，私有 registry 不触发第二次构建。registry 工具的校验不改：树结构与平台一致检查在 boring 的 `packages/registry/src/registry/Core.hx:264-328`，名称、重定向与摘要冲突检查在 `Core.hx:513-543`。 release-registry job 不再运行 boring：它下载 pack job 的 `release-artifacts` 与 `registry-tree`，先用 `tools/check-registry-tree.py` 核对树里的每个 `metadata.json` 与制品一一对应（每个制品都比对 `release-artifacts/SHA256SUMS` 的 sha256；npm 另比 `sha512`、cargo/pub/swift 另比 `sha256`，maven 没有摘要字段所以依赖 SHA256SUMS），再创建 GitHub Release、提交树并触发 Pages。

### 6.4 新增 bundle 自动进入发布清单

在 `boring.json` 增加带 `package` 的 bundle 后，matrix 自动把它加入 pack 与对应生态的发布 job，工作流文件不需要修改，registry 元数据在同一次运行写出。`shared` 的 bundle 由 `t-mwgrgela-p83q` 完成：prepared-dom 的割接期登记行与 `scripts/cutover/tq-vendor-prepared-dom.sh` 都已随割接期清理删除，`@tiqian/core` 与 `@tiqian/precompute` 改为依赖已发布的 `tiqian-shared@0.1.0-alpha.8`。

`release-manifest.json:126-146` 的 registry 单元不再写静态包名，改为 `packagesFrom` 从 `boring.json` 派生：`tools/release-gate.py` 的 `check_coverage`（:226-292）对 `kind=boring` 的单元比较 matrix 的输出。

防漏判据：bundle 缺少 `package`、target 不在映射内、同 (platform, registryName, version) 的制品名冲突时，matrix 直接失败。没有进 pack 的 bundle 必须在 `tools/release-matrix.py` 的排除表上显式声明并写明原因；缺少声明会让 `--check` 失败。

### 6.5 过渡态

Maven 的目标形态等 `t-mwgpst5a-8rxn` 完成后进入。在此之前，Maven 按 6.2 表运行：Gradle 发布 7 个模块到 Central，`boring pack` 只把单 jar 写进 registry。这一状态在本文与后续脚本中以过渡态标注，`t-mwgpst5a-8rxn` 完成后删除标注。 registry 一侧已不再是单 jar：pack 写出 `tiqian-engine` 的 9 个坐标，Gradle 的 7 个模块由 `publish.yml` 的 Maven Local 预检收集、registry 作业写入（`docs/release-pipeline.md` 的「Gradle 的 Maven 模块进入 registry」）。 matrix 的 maven 实例当前不发布到 Central：它只核对 pack 制品并打印交接说明（`release.yml:286-294`），Central 仍由 `release.yml` 的 maven job（`publish.yml`，Gradle 的 7 个模块）发布。按 bundle 重复运行该发布会重复上传同一批坐标。

## 7. 四点结论

### 7.1 Maven 的生产者

形态是 Gradle 编译、pack 采集与发布。Kotlin/Native 目标的编译只有 Gradle 能做，`boring pack` 无法自行产出 `tiqian-engine` 的 9 个 Maven 坐标；registry 只放一个 jar 而 Central 放 9 个模块会造成两边记录不同。`boring pack` 调用 Gradle 的 publication 任务，把根坐标与 8 个 target（jvm、android、macosArm64、iosArm64、iosSimulatorArm64、linuxX64、linuxArm64、mingwX64，`.haxelib/boring/git/tools/kotlin-publication/engine/build.gradle.kts:49-63`，该目录由 flake devShell 从 boring 检出展开）的发布目录放进同一次 pack 的制品集合，元数据由 pack 写出。

依赖 `t-mwgpst5a-8rxn`（registry 的多 artifactId 模型）先完成。它完成前按 6.5 的过渡态运行。

### 7.2 官方 npm、crates.io、pub.dev

方向是发布，逐条开启，不阻塞管线。npm 的凭据已经具备，保持现状；cargo 需要先确认 `tiqian-engine` 在 crates.io 未被占用，并加入 `CARGO_DIST_TOKEN`（`docs/release-pipeline.md:49` 记为预留）；pub 需要新增凭据并确认 `tiqian_engine` 可用。确认之前，该生态在 matrix 中记为未启用。

### 7.3 四个 npm 工作区包

`@tiqian/ffi`、`@tiqian/core`、`@tiqian/web-component`、`@tiqian/precompute` 现在不声明为 bundle。它们保留 npm 自身的构建，输入改为依赖 pack 发布的制品，不再读包内的入库副本。让它们成为 bundle 需要 pack 支持工作区模式，属于另一条任务。

### 7.4 precompute 的 Rust addon

不并入 `engine-rust`。它是包装引擎的 Neon 模块，是独立 crate，消费引擎的制品；并入会让两个发布单元的生命周期绑在一起。

## 8. 实施步骤

以下步骤已按顺序实施，命令用于复核。

1. 新增 `tools/release-matrix.py` 与它的自检：`--check`、`--list-bundles`、`--matrix`；`--check` 断言 bundle 集合相等、每个 bundle 的 target 有对应生态、每个生态为启用或显式未启用、没有发布的 bundle 有显式排除与原因。
2. 改 `release.yml`：增加 matrix 与 pack job，发布 job 按 platform 展开。
3. 改 `release-registry.yml`：pack 列表改用 `--list-bundles`；删除 `Sync compiled registry tool` 步骤（5.2 的缺陷）。
4. 新增各生态发布 job，消费 pack 的制品；未启用的生态按 7.2 处理。
5. 改 `release-manifest.json` 与 `tools/release-gate.py`：registry 单元从 `boring.json` 派生。
6. npm 工作区包的输入改为依赖 pack 制品，删除包内的入库副本与登记表中的对应行（依赖 `t-mwgrgela-p83q` 与 `t-mwgs07xa-v05b` 完成）。
7. Maven 等 `t-mwgpst5a-8rxn` 完成后进入 7.1 的形态，此前按过渡态运行。
8. dry run：所有 bundle 都有目标生态与发布步骤，没有遗漏（`tools/release-matrix.py --check` 与 `tools/release-gate.py` 的 `--runs-json` 演练）。

## 参考

- `docs/release-pipeline.md`
- `docs/release-channels.md`
- `docs/adr/0060-single-release-entry-and-gate.md`

