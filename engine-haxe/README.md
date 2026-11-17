# engine-haxe

`engine-haxe/src/` 是排版引擎的 Haxe 源码。boring（Haxe 到五种目标语言的编译器，
独立仓库）从这棵树生成 Kotlin、Swift、Dart、JavaScript、Rust 的代码。

仓库根的 `boring.json` 声明每个 bundle 的目标、精度、源码范围与发布信息；
`platforms/engine` 编译 `kotlin-f32` 生成的 Kotlin。tiqian 的 flake 把 boring 的
driver 与编译器固定在同一修订，进入开发 shell 时配置 `.haxelib/` 并重新生成
`engine-haxe/targets/classes.hxml`。

## 布局

- `engine-haxe/src/`：Haxe 源码，含与引擎测试一一对应的测试类。
- `engine-haxe/tests/`：Haxe 参照测试的入口 `Main.hx` 与编译清单
  `compile.hxml`、`compile-js-f64.hxml`。
- `engine-haxe/targets/`：各目标的生成参数。`common.hxml` 提供共用的类路径与
  宏，`kotlin-common.hxml`、`swift-common.hxml`、`rust-common.hxml` 补充各
  目标的编译器与运行时参数，精度入口沿用这些设置。`protocol-*.hxml` 单列协议
  根类，`rust.hxml` 供 `engine-rust` 配置使用。`classes.hxml` 由开发 shell 的
  `boring roots engine` 写出，不入库：Haxe 不会仅凭 `-cp` 编译目录下的全部类。
- `engine-haxe/textrange-kotlin.hxml`、`engine-haxe/smoke-kotlin.hxml`：不经
  `boring.json` 的 Kotlin 生成清单，前者只列出 `org.tiqian.core.TextRange` 相关
  类型，后者编译 boring 的 `boring.Fp16` 样例。
- `engine-haxe/data/`：生成 Unicode 数据类所用的区间数据。
- `engine-haxe/tools/`：`compare-traces.py` 解析 trace 行，并用
  `EXCEPTION_NAME_ALIASES` 把 `raises exception=` 行上的 Kotlin 内建异常名对到
  对应的 `Tiqian` 前缀名；`f64-trace-compare.sh` 调用
  `compare-f64-traces.py` 比对 f32 与 f64 两侧的轨迹。`gates.sh`、`serial-test.sh`、
  `ts-gate.sh` 供本地检查使用。
- `boring.json`（仓库根）：生成与测试配置的项目文件。`engine` source set 从六个
  包发现 `*Test.hx`，并给出 `types` 列出的五个入口类型；各目标的引擎配置共用
  它。生成与测试以此文件为准。
- `scripts/setup-haxe-env.sh`（仓库根）：把 Unicode 数据同步进当前检出，见下节。
- `engine-haxe/out/`、`engine-haxe/smoke/`：生成物与本地基线拷贝，不入库。

## 首次准备

生成阶段要读一组不入库的数据，新建的检出里没有，缺了会在生成时报出与准备无关
的错误：

| 输入 | 谁读它 | 缺了会怎样 |
|---|---|---|
| `tools/unicode-data/` | 各 Unicode 数据类在编译期读取 | `pinned Unicode data file is missing: tools/unicode-data/GraphemeBreakProperty-17.0.0.txt` |

`tools/unicode-data/` 由 `.gitignore` 排除，内容取自 boring 检出的 Unicode 17.0.0
数据文件。在仓库根目录执行一次即可补齐，已经存在的输入不做改动：

```shell
bash scripts/setup-haxe-env.sh
bash scripts/setup-haxe-env.sh /path/to/prepared/tiqian
```

脚本按顺序尝试三个源：参数给出的检出、`.haxelib/boring/git/tools/unicode-data/`、
flake 注入的 `BORING_SOURCE`。flake 在修订变化时先把原有的
`.haxelib/boring/git` 备份为 `.haxelib/boring/git.pre-flake-<时间戳>`，再复制固定
修订的可写副本；各 HXML 里的 `.haxelib/boring/git/...` 类路径因此一直指向该修订。

## 生成与测试

tiqian 的 flake 从固定的 boring 修订安装 `boring` 命令，并配置相同修订的 Haxe
编译器与 reflaxe。在 tiqian 检出根目录执行。修改 Haxe 后，先生成一个目标，再
编译并运行它的测试：

```shell
cd /path/to/tiqian
nix develop -c boring gen kotlin-f32 --project boring.json
nix develop -c boring test kotlin-f32 --project boring.json
```

`gen` 写出 `engine-haxe/out/kotlin-f32/gen` 与
`engine-haxe/out/kotlin-f32/gen-tests`；`test` 的结果写入
`engine-haxe/out/test-results/kotlin-f32.jsonl`。换目标时，把命令中的
`kotlin-f32` 换成 `boring.json` 里的配置 ID。`test` 使用已经生成的代码，因此
每次修改 Haxe 后要先运行该配置的 `gen`。

`boring verify --project boring.json` 依次生成各配置、运行可测试的配置，并与
`boring.json` 的 `baseline`（`kotlin-f32`）比较。只想比较已有的测试结果时运行
`boring compare --project boring.json`。`boring pack <配置 ID> --project boring.json`
生成发布包，只有声明了 `package` 的配置可以打包，`verify --with-pack` 会一并打包
这些配置。

`classes.hxml` 由开发 shell 写出。在同一个 shell 内新增测试类之后，重新生成入口
文件，再直接调用 HXML：

```shell
boring roots engine --project boring.json --output engine-haxe/targets/classes.hxml
```

## Haxe-JS f32 参照输出

f32 层的比对参照由 Haxe 自己运行后生成的 JS 输出提供。`engine-haxe/tests/compile.hxml`
把 `float-precision` 设为 `f32`，该入口不经过任何目标后端：

```shell
nix develop -c bash -c 'haxe engine-haxe/tests/compile.hxml'
bun engine-haxe/out/haxe-tests.js
```

`engine-haxe/tools/` 的脚本用 trace 行比较两侧结果；`EXCEPTION_NAME_ALIASES` 把
`raises exception=` 行上的 Kotlin 内建异常名对到对应的 `Tiqian` 前缀名。

## 同步纪律

引擎行为只在 `engine-haxe/src/` 修改。改完 Haxe 后运行该配置的 `boring gen` 与
`boring test`；Kotlin 平台通过 `platforms/engine` 使用生成结果。
