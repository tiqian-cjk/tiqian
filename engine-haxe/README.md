# engine-haxe

> **唯一活跃源码**：本目录是 Tiqian 引擎的唯一活跃源码（Phase 1，2026-10-21）。
> 同级 engine/（Kotlin 手写引擎）已标记 Legacy，仅作为 Kotlin 平台当前
> 消费面保留，最终由 boring 从本目录生成的多目标产物取代。

`engine-haxe` 是排版引擎的 Haxe 源码树。`engine`（Kotlin）是当前的产品代码；
本目录与它并行存在：先把 Kotlin 逐包翻译成 Haxe，再用生成的 Kotlin 逐个
文件替换 `engine` 中的手写文件。全部替换完成后，删除 `engine`，本目录改名
为 `engine`，Haxe 成为唯一源码，Kotlin、Swift、Dart、JS、Rust 五种目标
都由 boring（Haxe 到五种语言的编译器，独立仓库）从本目录编译生成。

## 布局

- `src/`：Haxe 源码，含与引擎测试一一对应的测试类。
- `tests/`：测试入口 `Main.hx` 与编译清单 `compile.hxml`。
- `tools/compare-traces.py`：把 Haxe 测试记录的执行轨迹与基准轨迹逐行比对。
  基准轨迹（golden）随 Kotlin 割接删除；当前跨目标验证以
  `boring test kotlin-f32` 的生成测试为准。
- `targets/`：各 HXML 提供目标编译参数。进入 flake 开发环境时，driver 按
  `boring.json` 的 `engine` source set 生成忽略入库的 `classes.hxml`，供直接
  调用 HXML 的脚本使用；Haxe 不会仅凭 `-cp` 编译目录下全部类。
  `common.hxml` 提供引擎配置共用的
  类路径与宏，`kotlin-common.hxml` 等文件补充各目标的编译器与运行时
  参数，精度入口沿用这些设置。`protocol-*.hxml` 单列协议根类；
  `rust.hxml` 是 `boring.json` 正在使用的 Rust 入口。
- `boring.json`：生成与测试配置驱动器（boring feature spec 59）的项目文件，声明本目录
  的目标、精度及命名源码范围。`engine` 范围从六个包发现 `*Test.hx`，加上两个
  runtime 根类型；八个引擎配置共用它。生成与测试以此文件为准。
- `tools/setup-haxe-env.sh`：把 `tools/unicode-data/` 同步进当前检出，见下节。
- `textrange-kotlin.hxml`、`smoke-kotlin.hxml`：独立用途的 Kotlin
  生成清单。
- `data/`：生成 Unicode 数据类所需的区间数据。
- `patches/`：vendored boring（`.haxelib/`，不入库）之上的本地补丁存档。
- `out/`、`smoke/`：生成物与本地基线拷贝，不入库。

## 首次准备

生成阶段要读一组不入库的数据，新建的检出或 git worktree 里可能没有，
缺了会在生成时报出与准备无关的错误：

| 输入 | 谁读它 | 缺了会怎样 |
|---|---|---|
| `tools/unicode-data/` | 各 Unicode 数据类在编译期读取 | `pinned Unicode data file is missing: tools/unicode-data/GraphemeBreakProperty-17.0.0.txt` |

在检出根目录执行一次即可补齐（已存在的一律不动）。脚本默认选择主 worktree
作为已准备输入的源检出；目录布局不同时显式传入源检出。复制前会逐项检查输入：

```shell
bash tools/setup-haxe-env.sh
bash tools/setup-haxe-env.sh /path/to/prepared/tiqian
```

flake 把 boring 的 driver 与编译器固定在同一修订，并在进入开发 shell 时配置
`.haxelib/`。已有的本地 boring 检出会先备份，再由固定修订的可写副本接替，
以兼容现有 HXML 的相对路径及编译期诊断输出。`tools/unicode-data/` 包含
Unicode 17.0.0 的数据文件，不入库，因此新 worktree 仍需要从已准备的检出获取它。

## 生成与测试

tiqian 的 flake 从固定的 boring 修订安装 `boring` 命令，并配置相同修订的
Haxe 编译器与 reflaxe。进入开发 shell 后直接调用命令即可。

在 tiqian 检出根目录执行。修改 Haxe 后，先生成一个目标，再编译并运行它的测试：

```shell
cd /path/to/tiqian
nix develop -c boring gen kotlin-f32 --project boring.json
nix develop -c boring test kotlin-f32 --project boring.json
```

生成的代码位于 `engine-haxe/out/kotlin-f32/gen` 和 `gen-tests`；测试结果写入
`engine-haxe/out/test-results/kotlin-f32.jsonl`。换目标时，把命令中的
`kotlin-f32` 换成 `boring.json` 里的配置 ID。`test` 使用已生成的代码，
因此每次修改 Haxe 后要先运行该配置的 `gen`。

需要检查全部配置及跨目标测试结果时，运行：

```shell
nix develop -c boring verify --project boring.json
```

它依次生成各配置，运行可测试配置，并与 `boring.json` 指定的基准配置比较。
只想比较已有测试结果时运行 `boring compare --project boring.json`。
要生成发布包，运行 `boring pack <配置 ID> --project boring.json`；只有声明了
`package` 的配置可以打包。`verify --with-pack` 还会打包这些配置。

`protocol-c` 用于生成 C 头文件：`boring gen protocol-c --project boring.json`
先生成 JavaScript，再执行配置中的 `afterGen`，写出
`tiqian_protocol_constants.h`。它没有测试，也不参与结果比较。

进入开发 shell 会更新 `engine-haxe/targets/classes.hxml`。如果在同一个 shell 内
新增测试类，重新生成入口文件，再直接调用 HXML：

```shell
boring roots engine --project boring.json --output engine-haxe/targets/classes.hxml
```

已验证 `protocol-c` 与 `kotlin-f32` 的 `gen`。`kotlin-f32` 的 `test` 和完整
`verify` 尚未在当前检出运行；不能据此认定跨目标行为已经一致。

## Haxe-JS f32 参照输出

f32 层的比对参照由 Haxe 自己运行后生成的 JS 输出提供；`tests/compile.hxml` 将
`float-precision` 设为 `f32`，该入口不经过任何目标后端：

```shell
nix develop -c bash -c 'haxe engine-haxe/tests/compile.hxml'
bun engine-haxe/out/haxe-tests.js
```

`tools/compare-traces.py` 仍保留 trace 行解析与 `EXCEPTION_NAME_ALIASES`
规则，但引擎基准轨迹已随 Kotlin 割接删除，当前跨目标验证以
`boring test kotlin-f32` 的生成测试为准。

## 同步纪律

`engine` 的 Kotlin 由本目录生成，修改引擎行为只改本目录的 Haxe 源码，
然后重新运行 `boring gen` 与 `boring test`。进度与验证记录见 `PROGRESS.md`。
