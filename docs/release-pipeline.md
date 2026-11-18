# 发布流程

本文档记录 tiqian v0.1.0-alpha07 实际执行并验证过的发布流程。发布由推送版本标签触发，
CI 打包五个目标生态的产物，写入 registry 仓库并部署站点。下一个人按本文档执行即可复现。

## 0. 单一入口与发版前检查

推送 `v*.*.*` 标签只触发 `.github/workflows/release.yml`。这个 workflow 先运行
`.github/workflows/release-gate.yml`，由 `tools/release-gate.py` 读取
`release-manifest.json`，要求 `Native precompute CI` 与 `Build Neon precompute`
在标签 commit 上都有 completed 且 success 的运行记录；任一 workflow 失败或没有运行
记录时，全部发布 job 都不会开始。

检查通过后，`release.yml` 按依赖顺序调用 `publish-ffi.yml`、`publish-core.yml`、
`publish-web-component.yml`、`publish-precompute.yml`、`publish.yml` 与
`release-registry.yml`。registry 的元数据写在最后，前面的 npm 或 Maven workflow
失败时不会写出元数据。

Maven Central 的部署确认仍在 Central Portal 由人执行。Maven 快照与 fork 的 npm 快照
不属于按版本发版，继续使用 `workflow_dispatch`。

## 1. 触发方式

推送 `v*.*.*` 形式的标签触发 `.github/workflows/release.yml`：

```shell
git tag v0.1.0-alpha07
git push origin v0.1.0-alpha07
```

发版入口只响应标签推送。发布版本号从标签去掉前缀 `v` 得到，例如
`v0.1.0-alpha07` 对应 `0.1.0-alpha07`。发版运行失败后，在 GitHub 上对同一次
运行选择 "Re-run failed jobs"；重跑从同一个标签 commit 读取代码。


### 版本号形式

发布版本是点分的预发布标识符。标签 `v0.1.0-alpha.9` 对应包版本 `0.1.0-alpha.9`，
最后一段 `9` 是纯数字，不带前导零。这个形式下 `0.1.0-alpha.9` 小于
`0.1.0-alpha.10`；旧的单标识符形式按字符比较，到 `alpha100` 时会得到 `alpha100`
小于 `alpha99`。

两位补零的 `alphaNN` 形式（例如 `0.1.0-alpha07`）已经废弃，新版本只写点分纯数字。
该版本的目录随 `v0.1.0-alpha.9` 发布从 registry 删除（`tools/merge-registry-tree.py`
的 `--retire` 参数）。删除由用户确认：该版本只有一个消费者，用户会通知对方，所以
「不删除 registry 里已发布版本」的规则在这个版本上不再适用。

旧形式与新形式不可比较：`alpha` 是 `alpha07` 的前缀，短者优先，所以
`0.1.0-alpha.8` 小于 `0.1.0-alpha07`。registry 站点按包名下的版本列表计算 `latest`：
npm 与 pub 的元数据、Maven 的 `maven-metadata.xml` 都取同一个包里最高的版本。
旧 `alphaNN` 条目还在 registry 里时，这个指针会停在旧条目，不带版本号的安装因此
解析到旧版本。发版步骤以 `tools/merge-registry-tree.py --retire 0.1.0-alpha07`
（`.github/workflows/release-registry.yml` 的 Commit metadata to registry repo
一步）删除该版本目录，删除后指针指向 `0.1.0-alpha.9`。发版前
逐个生态核对指针，例如：

```shell
npm view tiqian-engine dist-tags --registry https://registry.tiqian.org/npm/
```

`--npm` 改写以下文件的 `version` 字段：根 `package.json` 的 `workspaces` 列出的每个
npm 清单，`release-manifest.json` 中各发布单元与 `notInRelease` 列出的每个 npm 清单。

同一次调用把仓库内部 `@tiqian/*` 依赖以及 `tiqian-engine`、`tiqian-protocol`、
`tiqian-shared` 的依赖版本改成同一个值。写成 `workspace:` 的依赖不在这一步改写：它
指向工作区里由 pack 生成的成员，发布工作流在 `npm pack` 之前用
`tools/publish-contract.py` 把它改写成发布版本，改写结果与标签版本一致。

### npm 发布规则

npm 目标在 `boring.json` 的 `package` 块里有两个名字：`name` 是自建 registry 的
目录名（例如 `tiqian-engine`），`npmName` 是 registry.npmjs.org 上的包名（例如
`@tiqian/engine`）。boring 的 `Config.ecosystemName` 让 ts 目标写 `npmName`，所以
发布出去的包名是 scoped 名，而 pack 写出的 tarball 文件名把 scoped 名里的 `/` 换成
`-`、保留 `@`（`@tiqian-engine-<version>.tgz`）。`tools/release-matrix.py` 的
`registryName` 与 artifact 名都按这个规则派生，dist-tag 步骤用 `registryName`。

`tools/publish-contract.py` 是这条规则的唯一检查者，三种用法：

- `--artifacts <dir> --version <v>`：矩阵点名的 tarball 必须在目录里，manifest 名
  必须等于矩阵的 `registryName`，任何依赖字段不得残留 `workspace:` 范围。
- `--archive <file>`：单个 tarball 的同样检查，发布工作流在 `npm pack` 之后调用。
- `--resolve <dir> --version <v>`：把 `workspace:` 依赖范围改写成发布版本。npm 不会
  在 `npm pack` 时改写这个协议，不改写就会出现消费者装不上的 tarball。

`scripts/staging-pipeline.sh` 的 `publish-contract` 阶段对每次 push 到 main 的 pack
产物跑这三条并装进一个空项目 import 各包的 `/runtime` 入口。

`.github/workflows/release-gate.yml` 在解析发布版本之后运行
`tools/align-package-versions.py --check "${GITHUB_REF_NAME#v}"`。标签 commit 上的
任何 npm 清单或内部依赖版本不等于标签版本时，发布在开始之前终止。

`boring.json` 保持占位版本 `0.1.0`。打包 job 在 `boring pack` 之前运行不带 `--npm` 的
形式：

```shell
python3 tools/align-package-versions.py "${GITHUB_REF_NAME#v}"
```

它除了写入 npm 清单，还把 `boring.json` 里每个声明了 `package` 的 bundle 的
`version` 字段改成标签版本。registry 的产物名是 `<包名>-<版本>`，如果清单还带着
占位版本 `0.1.0`，下载地址就不存在。


制品与 registry 元数据由同一条 `boring pack` 命令产出。四个 registry 参数同时给出时，
`boring pack` 在写出每个 bundle 的制品之后，把 registry 树写到 `$RUNNER_TEMP/registry-tree`：

```shell
nix develop -c bash -c "boring pack protocol-rust protocol-ts protocol-kotlin protocol-swift protocol-dart engine-rust ts kotlin-f32 kotlin-f64 swift-f32 swift-f64 dart --registry-out "$RUNNER_TEMP/registry-tree" --owner "${{ github.repository_owner }}" --repo "${{ github.event.repository.name }}" --asset-base "${{ github.server_url }}/${{ github.repository }}/releases/download/${{ github.ref_name }}""
```

`--owner` 取仓库所有者，`--repo` 取仓库名，`--asset-base` 取当前标签的
GitHub Release 下载前缀，`--registry-out` 取树的根目录。四个参数写入 `metadata.json`
的 `repository`、`tag` 与各平台下载 URL。四个参数只给一部分时 `boring pack`
报错停止；一个都不给时只写制品，不写 registry 树。

从 `boring pack` 的输出到 registry 仓库提交之间有四个步骤，输入如下：

1. Collect artifacts：`tools/collect-release-artifacts.py` 读取同一次 pack 写出的
   registry 树，把每份 `metadata.json` 命名的文件从 `engine-haxe/out` 复制到扁平的
   `release-artifacts/`；某个命名的文件在输出根下找不到时该步骤失败。清单来自 pack
   写出的元数据，Gradle 的 `.module`、Kotlin/Native 的 `.klib` 与 Android 的
   `.aar` 因此随 pack 的产物一并进入发布资产。
2. Create GitHub Release：把 `release-artifacts/*` 作为标签的发布资产上传。
3. Upload the Swift archives：把 `release-artifacts/*.zip` 上传到 R2 的
   `swift/tiqian/<包名>/<版本>.zip`。元数据的 `archive` 字段指向这个路径，
   所以上传要在提交元数据之前完成。
4. Commit metadata to registry repo：克隆 registry 仓库，运行
   `tools/merge-registry-tree.py` 把 `$RUNNER_TEMP/registry-tree/<owner>` 里的每个版本
   目录并入 `<owner>` 目录，提交并推送。合并保留 registry 里已有的版本，同一个版本重新
   发布时替换该版本目录；`--retire` 参数在合并之后删除指定的版本目录，包内没有其他版本时连包目录一起删除。这一步的输入是第 3 步写在 R2 的归档与 `boring pack` 写出的树。

### 生成物的编译点与跨目标一致性

`boring pack` 只对两个目标运行编译器：TypeScript 走 `package-tsc`（pinned boring 检出
`packages/compiler/PackageArtifacts.hx:184-209`），Kotlin 走 `package-kotlinc` 或 bundle 的
`mavenPublication`（同一文件 `:357-384`）。Swift 的 zip、Dart 的 pub 归档与 Rust 的 crate
是把生成源码打成归档，没有任何编译器读取它们。发版路径因此增加两个检查。

1. `python3 tools/compile-bundles.py --project boring.json` 对每个 bundle 的生成物运行一次
   目标编译器，逐 bundle 打印退出码；pack 已经编译的目标打印 `compiled by pack`。
   `.github/workflows/release.yml` 的 pack job 在打包之后运行这条命令，
   `scripts/staging-pipeline.sh` 的 `compile-bundles` stage 运行同一条命令。
2. `nix develop -c bash -c 'boring verify --project boring.json'` 生成全部 bundle、运行全部
   bundle 的生成测试，并比较参与比较的 bundle（driver `packages/driver/src/driver/Main.hx`
   的 `actionVerify`；`docs/cross-target-alignment.md:33` 把这条命令列为入口）。
   `.github/workflows/bundle-verification.yml` 运行这条命令，该 workflow 写在
   `release-manifest.json` 的 `release.requiredLanes` 里；标签 commit 上没有它的成功记录时
   `tools/release-gate.py` 拒绝发版。`scripts/staging-pipeline.sh` 的 `verify` stage 运行
   同一条命令。

`boring.json` 声明 `compare: false` 的 6 个 protocol 与 shared bundle 不参与
`boring compare`：该命令按单一 baseline（`kotlin-f32`）的测试 id 逐目标比对，而 protocol
bundle 的测试语料与 baseline 不同。它们的生成测试仍由 `boring verify` 运行。

提交之后执行 Deploy the registry site 一步，用 `PAGES_DEPLOY_HOOK` 触发 Cloudflare
Pages 构建。registry 工具在 boring 仓库构建并随发布资产上传
（`.github/workflows/publish-registry-tool.yml`），registry 仓库不同步该工具。

## 4. registry 目录模型

registry 树按 `<owner>/<包名>/<版本>/<平台>/metadata.json` 组织。每个版本下每个平台一个
`metadata.json`。

目录名按平台区分：

- cargo、npm、pub 用包名：`tiqian-engine`、`tiqian-protocol`；pub 把连字符换成下划线，写作 `tiqian_engine`
- maven 与 swift 用产物名：`tiqian-engine-f32`、`tiqian-engine-f64`

maven 的 `metadata.json` 带 `groupId` 与 `artifacts`：`groupId` 是这一版的 Maven 组，
`artifacts` 数组每一项为 `{file, url, artifactId}`，`file` 是发布资产的文件名，`url` 是
该文件的下载地址，`artifactId` 是这一项所属的 Maven 坐标。`artifactId` 可以省略，省略时
取顶层的 `name`，这一项对应旧模型里一个版本只有一个 artifactId 的形状。一个包的同一个
版本可以带多个 artifactId，Kotlin Multiplatform 的根坐标与八个 target 各占一个：根坐标
`tiqian-engine`，加 `tiqian-engine-jvm`、`tiqian-engine-android`、`tiqian-engine-iosarm64`、
`tiqian-engine-iossimulatorarm64`、`tiqian-engine-macosarm64`、`tiqian-engine-linuxx64`、
`tiqian-engine-linuxarm64` 与 `tiqian-engine-mingwx64`。SwiftPM 清单的包名是产物名，
swift 因此按产物名建目录。

站点为每个 artifactId 写一份 `maven/<groupId 的点换成斜杠>/<artifactId>/maven-metadata.xml`
与同名的 `.sha1`，这些文档在同一个 groupId 目录下并列。`_redirects` 为每个 Maven 制品文件
写一条规则，路径同样带 artifactId：`/maven/<groupPath>/<artifactId>/:version/<file>`。

cargo 的索引路径、依赖解析结果、tarball 名与下载重定向都取包名，`tiqian-engine` 的 crate
因此按包名建目录，文件名是 `tiqian-engine-<版本>.crate`。

`boring pack` 的 registry 写出（`packages/driver/src/driver/RegistryMetadata.hx`）为每个
bundle 选择目录名与产物文件：maven 与 swift 取 `haxeArgs` 里的 `package-artifact-stem`
（未设置时取包名），cargo、npm 与 pub 取 `bundle.package` 的 `name`，pub 再把连字符
换成下划线。Maven 的 artifacts 从 Gradle 发布目录采集，`artifactId` 取版本目录上一级的
目录名，`groupId` 取该 artifactId 目录以上各层目录名用点连接得到的字段。engine-rust
不设置 `package-artifact-stem`，cargo 目录名与文件名都取包名 `tiqian-engine`；精度在 Rust
编译期由 cargo feature `f32` 选择，不再有第二个 Rust 制品。

registry 工具（`packages/registry/src/registry/Core.hx`）校验每个版本下每个平台只有一个
`metadata.json`，并拒绝版本不一致、平台不一致、未知平台与 artifactId 不是单个路径段等错误。

站点生成读取树里保留的全部版本。`Core.hx` 的 `scan` 遍历
`<owner>/<包名>/<版本>/<平台>/metadata.json`，`writeNpm`、`writePub`、`writeCargo`、
`writeSwift` 与 `writeMaven` 分别为一个包列出扫描到的版本，`writeMaven` 按 artifactId
分组后为每个 artifactId 列出它所属的版本；`latest` 只决定 npm `dist-tags`、pub `latest`
与 maven `<latest>`、`<release>` 指向哪个版本。合并写入让站点同时列出历史版本与最新版本，
registry 工具不需要修改。历史版本会增加 `Core.hx:554-565` 生成的 `_redirects` 行数，
`Core.hx:574-577` 在静态行数超过 2000 或动态行数超过 100 时让站点构建失败。

## 5. Swift 归档

Swift 归档有两个硬性要求：

- zip 必须只有一个顶层目录。SwiftPM 解包时要求归档根目录只有一个目录，成员位于
  `<包名>-<版本>/` 之下。
- 归档上传到 R2 的 `swift/tiqian/<包名>/<版本>.zip`。

`boring pack` 从它生成的 `Package.swift` 读取清单正文，写入 `metadata.json` 的
`packageSwift` 字段。这个字段存放清单正文，不存放 URL。registry 工具校验 `archive`
字段必须等于 `swift/<scope>/<包名>/<版本>.zip`，否则报 `invalid Swift archive`。

## 6. Pages 部署

registry 站点不随每次提交自动部署。发布工作流内置一个 Deploy Hook 步骤，用
`PAGES_DEPLOY_HOOK` 触发 Cloudflare Pages 构建：

```shell
curl -fsS -X POST "$PAGES_DEPLOY_HOOK" | head -c 200
```

手动重建站点时执行同一条命令。`PAGES_DEPLOY_HOOK` 未配置时该步骤打印提示并跳过，
工作流继续执行。

## 7. 本地复现

本地复现发布环境需要 `nix develop`。开发 shell 必须包含 `unzip`：SwiftPM 解包
registry 源码归档时调用宿主 `unzip`，缺少它每次 registry 拉取都会报
`could not find executable for 'unzip'`。

registry 本地校验用 `bash build.sh`。脚本下载 `registry-tool` 二进制，把当前目录
里除 `.git`、`.tool-bin`、`.tree`、`dist` 之外的顶层目录复制到 `.tree`，然后对
这个树运行 registry 工具生成 `dist` 站点。校验通过时命令退出码为 0。

## 8. 五个生态的实测命令

以下命令在 v0.1.0-alpha07 发布后逐一实测。registry 基址是 `https://registry.tiqian.org`。

### npm

```shell
npm install tiqian-engine --registry https://registry.tiqian.org/npm/
```

实测输出：

```
added 1 package in 4s
```

失败定位顺序：

1. 检查 `https://registry.tiqian.org/npm/tiqian-engine` 是否返回 200。
2. 检查 `metadata.json` 的 `url` 是否指向可下载的 tarball。
3. 检查 `sha512` 是否与 tarball 实际内容一致（registry 用 base64 编码的 `sha512-` 前缀）。

### cargo

在 `.cargo/config.toml` 写入：

```toml
[registries.tiqian]
index = "sparse+https://registry.tiqian.org/cargo/index/"

[source.crates-io]
replace-with = "tiqian"
```

然后按精度选择。默认精度是 f64：

```shell
cargo add tiqian-engine
cargo build
```

f32 精度：

```shell
cargo add tiqian-engine --features f32
cargo build
```

精度在编译期由 cargo feature `f32` 选择。crate 的 `lib.rs` 用两个条件声明定义同一个类型：

```rust
#[cfg(feature = "f32")]
pub type TiqianFloat = f32;
#[cfg(not(feature = "f32"))]
pub type TiqianFloat = f64;
```

crate 的 `Cargo.toml` 声明 `[features] default = []` 与 `f32 = []`。cargo 从索引条目读取
依赖的 feature 列表，索引条目必须带 `"features": {"f32": []}`，缺少时报
`does not have that feature`。

生成树的 f32 覆盖由 `scripts/test-engine-rust.sh` 提供：它对同一份生成树依次运行
`cargo test` 与 `cargo test --features f32`，`.github/workflows/ci-native-precompute.yml`
的 rust job 调用该脚本。改动生成入口或 bundle 时，这一轮不依赖第二个 bundle。

以下 cargo 输出在本地 sparse registry 上实测（cargo 1.97.1，crate 由 boring 064eed863 打包）。

`cargo add tiqian-engine` 与 `cargo build`：

```
    Updating `local` index
      Adding tiqian-engine v0.1.0 to dependencies
             Features:
             - f32
    Updating `local` index
     Locking 1 package to latest compatible version
 Downloading crates ...
  Downloaded tiqian-engine v0.1.0 (registry `local`)
   Compiling tiqian-engine v0.1.0 (registry `local`)
   Compiling consumer v0.1.0
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 5.26s
type_name = f64
size_of_val = 8
```

`cargo add tiqian-engine --features f32` 与 `cargo build`：

```
    Updating `local` index
      Adding tiqian-engine v0.1.0 to dependencies
             Features:
             + f32
    Updating `local` index
     Locking 1 package to latest compatible version
   Compiling tiqian-engine v0.1.0 (registry `local`)
   Compiling consumer v0.1.0
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 4.85s
type_name = f32
size_of_val = 4
```

索引条目不带 `f32` 时，`cargo build` 报：

```
error: failed to select a version for `tiqian-engine`.
    ... required by package `consumer v0.1.0`
versions that meet the requirements `^0.1.0` are: 0.1.0

package `consumer` depends on `tiqian-engine` with feature `f32` but `tiqian-engine` does not have that feature.
```

失败定位顺序：

1. 检查 `https://registry.tiqian.org/cargo/index/config.json` 是否返回 200。
2. 检查 crate 的 index 文件（`cargo/index/ti/qi/tiqian-engine`）是否存在。
3. 检查 `cksum` 是否与 `.crate` 实际内容一致。
4. 检查 `_redirects` 里 `/cargo/dl/tiqian-engine-:version.crate` 是否指向 GitHub Release 资产。
5. 检查索引条目的 `features` 是否声明了 `f32`。

#### 从 `tiqian-engine-f32` 与 `tiqian-engine-f64` 迁移

`0.1.0-alpha.8` 起 registry 只输出 `tiqian-engine` 一个 cargo 包，`tiqian-engine-f32` 与
`tiqian-engine-f64` 不再有 `0.1.0-alpha.8` 的新版本。发版步骤把新版本目录并入 `<owner>` 目录
（`.github/workflows/release-registry.yml` 调用 `tools/merge-registry-tree.py`），
同一次运行以 `--retire 0.1.0-alpha07` 删除每个包的 `0.1.0-alpha07` 目录；
`tiqian-engine-f32` 与 `tiqian-engine-f64` 只有这一个版本目录，删除后整个包目录随之移除。
锁定 `0.1.0-alpha07` 的消费者要在 `v0.1.0-alpha.8` 发布前迁移到 `tiqian-engine`，
发布后这两个包不再解析。

索引条目缺失时的消费者行为如下（本地 sparse registry 实测，条目为手工删除）：

- 已有工程带着 `Cargo.lock` 与已下载的 crate 缓存时，`cargo build` 仍然成功（0.01s，使用缓存）
- 新建工程或清空 `CARGO_HOME` 后，`cargo add tiqian-engine-f32` 报
  `error: the crate tiqian-engine-f32 could not be found in registry index.`

迁移方式是把依赖名换成 `tiqian-engine` 并显式选择精度，这样 `0.1.0-alpha.8` 及之后的版本可用：

```toml
# 原 tiqian-engine-f32 = "0.1.0-alpha07"
tiqian-engine = { version = "0.1.0-alpha.8", features = ["f32"] }
```

```toml
# 原 tiqian-engine-f64 = "0.1.0-alpha07"
tiqian-engine = "0.1.0-alpha.8"
```

### pub

在 `pubspec.yaml` 写入：

```yaml
dependencies:
  tiqian_engine:
    hosted: https://registry.tiqian.org/pub/
    version: ^0.1.0-alpha07
```

然后：

```shell
dart pub get
```

实测输出（`dart pub get`）：

```
Resolving dependencies...
Downloading packages...
+ tiqian_engine 0.1.0-alpha07
Changed 1 dependency!
```

注意版本约束必须写成 `^0.1.0-alpha07`。写成 `^0.1.0` 时 pub 不匹配预发布版本，报
`version solving failed`。

失败定位顺序：

1. 检查 `https://registry.tiqian.org/pub/api/packages/tiqian_engine` 是否返回 200。
2. 检查版本约束是否包含预发布版本（`^0.1.0-alpha07`；`^0.1.0` 不匹配）。
3. 检查 `metadata.json` 的 `url` 是否指向可下载的 `.tar.gz`。
4. 检查 `sha256` 是否与 `.tar.gz` 实际内容一致。

### maven

在 Gradle 构建文件写入：

```kotlin
repositories {
    maven { url = uri("https://registry.tiqian.org/maven") }
    mavenCentral()
}
```

然后：

```shell
gradle dependencies --configuration runtimeClasspath
```

实测输出（`gradle dependencies --configuration runtimeClasspath`）：

```
runtimeClasspath - Runtime classpath of source set 'main'.
\--- tiqian-engine-f32:tiqian-engine-f32:0.1.0-alpha07
     \--- org.jetbrains.kotlin:kotlin-stdlib:2.4.10
          \--- org.jetbrains:annotations:13.0
```

注意需要把 `mavenCentral()` 作为回退仓库。tiqian 引擎的 maven 产物依赖
`org.jetbrains.kotlin:kotlin-stdlib`，这个依赖不在 tiqian registry 里，只配置 tiqian
仓库时解析失败。

失败定位顺序：

1. 检查 `https://registry.tiqian.org/maven/<包名>/<包名>/maven-metadata.xml` 是否返回 200。
2. 检查 `maven-metadata.xml` 的 `latest` 版本是否正确。
3. 检查 `_redirects` 里 `/maven/<包名>/<包名>/:version/<文件>` 是否指向 GitHub Release 资产。
4. 检查是否配置了 `mavenCentral()` 回退仓库。

#### 平台坐标的消费关系

`publishTiqianToMavenLocal` 写出的七个平台坐标里，应用构建文件只需要声明 `tiqian-compose` 或
`tiqian-compose-material3`。`tiqian-compose-material3` 以 api 依赖引入 `tiqian-compose`；
`tiqian-compose` 的 jvm 变体把 `tiqian-jvm-skia` 记为 runtime 依赖，消费方不单独声明它。
源码里调用 `MaterialTheme.typography` 的消费方需要自己声明 Compose Material 3 依赖。

2026-11-17 的消费验证：在仓库外建一个 Gradle 工程，只声明 `org.tiqian:tiqian-compose`、
`org.tiqian:tiqian-compose-material3`、`org.tiqian:tiqian-jvm-skia` 三个坐标，源码调用
`org.tiqian.compose.CjkText`、`org.tiqian.compose.material3.CjkText` 与
`org.tiqian.shaping.skia.SkiaTextShaper`，`compileKotlin` 通过。该工程不入库。

### swift

```shell
swift package-registry set https://registry.tiqian.org/swift --scope tiqian
swift package resolve
```

实测输出（`swift package-registry set https://registry.tiqian.org/swift --scope tiqian` 后
`swift package resolve`）：

```
Computing version for tiqian.tiqian-engine-f32
Computed tiqian.tiqian-engine-f32 at 0.1.0-alpha07 (0.69s)
Fetching tiqian.tiqian-engine-f32
```

注意：本次验证时 `swift package resolve` 在拉取归档后报校验和不一致。registry 元数据
记录的 `sha256` 与 R2 上实际归档的 `sha256` 不一致，且 R2 上的归档没有单一顶层目录。
这属于发布后状态，重新发布时需要保证归档结构与校验和一致。

失败定位顺序：

1. 检查 `https://registry.tiqian.org/swift/tiqian/<包名>.json` 是否返回 200。
2. 检查 `https://registry.tiqian.org/swift/tiqian/<包名>/<版本>.json` 的 `checksum`。
3. 下载 `https://registry-storage.tiqian.org/swift/tiqian/<包名>/<版本>.zip`，计算 `sha256`
   与元数据对比。
4. 检查 zip 是否只有一个顶层目录（`unzip -l` 查看顶层条目）。
5. 检查 `metadata.json` 的 `packageSwift` 字段是否存清单正文，不存放 URL。

## 9. staging 管线

`.github/workflows/staging-pipeline.yml` 在 push 到 `main` 与手动 dispatch 时运行，
用 staging 版本执行发版流程的打包、registry 树生成、cargo 消费与 Maven 本地发布，
不推送任何远端、不打标签。命令实现放在 `scripts/staging-pipeline.sh`，本地检出运行
同一条脚本即可复现。

版本号取 `0.0.0-staging.<提交前七位>`，由 `tools/align-package-versions.py` 写入
`boring.json` 与各 npm 清单。脚本按 `tools/release-matrix.py --list-bundles` 的列表逐个调用
`boring pack`，单个 bundle 失败时其余 bundle 仍会执行并记录结果。

`boring pack` 在 ts 目标上调用 `package-tsc`，按 `BORING_PACKAGE_TSC`、PATH 上的
`tsc` 的顺序解析编译器，两者都缺时以 `pack on the ts target needs tsc` 结束。flake
devShell 不提供 `tsc`，脚本因此在两者都缺时把 bun 承载的 shim 写到 staging 根目录并
导出 `BORING_PACKAGE_TSC`，与 `release.yml` 的 Pack every bundle 步骤做法一致。

脚本步骤与对应的发版步骤：

| staging 步骤 | 对应的发版步骤 |
| --- | --- |
| `align` | `release.yml` 的 Align the package versions |
| `pack` | `release.yml` 的 Pack every bundle |
| `collect-artifacts` | `release.yml` 的 Collect the artifacts 与 Record the artifact digests |
| `registry-tree` | `release-registry.yml` 的 Check the registry tree against the artifacts |
| `maven-artifact-ids` | maven 元数据的 `artifacts` 数组要带 `artifactId` |
| `cargo-consume` | cargo 消费者从 pack 产物构建依赖 |
| `maven-local-publish` | `publish.yml` 的 `publishTiqianToMavenLocal`，写出平台模块 |
| `maven-local-repo` | 九个 `tiqian-engine` 坐标：把 `pack` 阶段 kotlin-f32 的 `kmpPublication` 产物复制进隔离仓库后逐个断言 |

隔离方式：`--registry-out` 指向 staging 根目录，owner 写成 `staging-local`，
`--asset-base` 写成保留域 `staging.invalid`；Maven 发布加
`-Dmaven.repo.local=<staging 根>/maven-repo`。脚本不含 npm publish、cargo publish、
`git push`、标签创建与 R2 上传。

刻意不覆盖的动作是需要凭据的上传：npm 与 pub 的正式发布、crates.io 发布、Swift 归档
上传到 R2、Maven Central 部署、registry 仓库提交与 GitHub Release 创建。这些动作在
staging 管线里没有对应步骤。

## 验证命令

本文档的命令在 v0.1.0-alpha07 发布后逐一实测。文档修改后运行：

```shell
git diff --check
python3 tools/doc-style/check.py docs/release-pipeline.md
```