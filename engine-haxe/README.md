# engine-haxe

`engine-haxe` 是排版引擎的 Haxe 源码树。`engine`（Kotlin）是当前的产品代码；
本目录与它并行存在：先把 Kotlin 逐包翻译成 Haxe，再用生成的 Kotlin 逐个
文件替换 `engine` 中的手写文件。全部替换完成后，删除 `engine`，本目录改名
为 `engine`，Haxe 成为唯一源码，Kotlin、Swift、Dart、JS、Rust 五种目标
都由 boring（Haxe 到五种语言的编译器，独立仓库）从本目录编译生成。

## 布局

- `src/`：Haxe 源码，含与引擎测试一一对应的测试类。
- `tests/`：测试入口 `Main.hx` 与编译清单 `compile.hxml`。
- `tools/compare-traces.py`：把 Haxe 测试记录的执行轨迹与引擎 golden
  逐行比对。golden 指引擎测试留下的基准轨迹文件，位于
  `engine/src/jvmTest/resources/golden/test-traces/`（本地生成，不入库）。
- `targets/`：每个目标×精度一个生成入口，只含 include、输出目录与精度
  define。`common.hxml` 存五目标共享的类路径与宏，`classes.hxml` 存全部
  根类清单。以 `rust-` 与 `common-` 开头的其余文件是 Rust 目标调查期间的
  临时入口，不属于常规流程。
- `boring.json`：束驱动器（boring feature spec 59）的项目文件，声明本目录
  有哪几个目标束。生成与测试以它为准，不再逐个手敲 hxml。
- `tools/setup-haxe-env.sh`：把三个不入库的输入同步进当前检出，见下节。
- `textrange-kotlin.hxml`、`smoke-kotlin.hxml`：独立用途的 Kotlin
  生成清单。
- `data/`：生成 Unicode 数据类所需的区间数据。
- `patches/`：vendored boring（`.haxelib/`，不入库）之上的本地补丁存档。
- `out/`、`baseline-goldens/`、`smoke/`：生成物与本地基线拷贝，不入库。

## 首次准备

生成阶段要读三个不入库的输入，新建的检出或 git worktree 里一个都没有，
缺任何一个都会在生成时报出与准备无关的错误：

| 输入 | 谁读它 | 缺了会怎样 |
|---|---|---|
| `.haxelib/` | `-lib boring` 与 `-lib reflaxe` 的解析 | `Type not found : Intercept` |
| `engine-haxe/baseline-goldens/` | `GoldenDataMacros.init()` | `Golden data directory not found: engine-haxe/baseline-goldens/layout-dumps` |
| `tools/unicode-data/` | 各 Unicode 数据类在编译期读取 | `pinned Unicode data file is missing: tools/unicode-data/GraphemeBreakProperty-17.0.0.txt` |

在检出根目录执行一次即可补齐（已存在的一律不动）：

```shell
bash tools/setup-haxe-env.sh                  # 源检出自动从同级目录里找
bash tools/setup-haxe-env.sh /path/to/tiqian  # 或者显式指定
```

`.haxelib/` 用符号链接接过来，因为 `targets/` 下的入口以相对路径引用它。
`.haxelib/boring/git` 的检出修订就是生成器修订，它决定生成的代码里有什么；
换修订会换掉全部目标的产物。

## 生成与测试

束驱动器的实现在 boring 检出里，先把它编成 js：

```shell
cd /path/to/boring
nix develop -c bash -c 'haxe tools/bundle/driver.hxml'
```

之后在 tiqian 检出根目录执行。驱动器按 `boring.json` 派生每个束的输出目录
（`engine-haxe/out/<id>/gen` 与 `engine-haxe/out/<id>/gen-tests`）与结果文件
（`engine-haxe/out/test-results/<id>.jsonl`）：

```shell
cd /path/to/tiqian
nix develop -c bash -c 'bun /path/to/boring/out/bundle/driver.js gen ts --project boring.json'
nix develop -c bash -c 'bun /path/to/boring/out/bundle/driver.js test kotlin-f32 --project boring.json'
nix develop -c bash -c 'bun /path/to/boring/out/bundle/driver.js compare --project boring.json'
```

五个动作：`gen` 生成该束的两棵源码树，`test` 把该束已生成的树编译并运行、留下结果文件（它不生成，跑 test 之前先对该束跑 gen；`verify` 会自动先做全部 gen），`pack` 打发布包，
`compare` 按 `boring.json` 的 `baseline` 逐用例比对各束的结果文件，
`verify` 依次做完全部束的 gen、test、compare（加 `--with-pack` 连 pack）。
束的清单与精度写在 `boring.json` 里，当前六个束是 `kotlin-f32`、`kotlin-f64`、
`ts`、`swift-f32`、`swift-f64`、`dart`。

## Haxe-JS 参照束

f64 层的比对参照是 Haxe 自己跑出来的 JS 束，它不经过任何目标后端：

```shell
nix develop -c bash -c 'haxe engine-haxe/tests/compile.hxml'
bun engine-haxe/out/haxe-tests.js
python3 engine-haxe/tools/compare-traces.py \
  engine-haxe/baseline-goldens/test-traces engine-haxe/out/haxe-traces \
  --mode tolerance --classes <已移植的测试类，逗号分隔>
```

比对脚本在 `raises exception=` 行上把 Kotlin 标准库异常名与 Tiqian 前缀名
视为同名（`EXCEPTION_NAME_ALIASES`），每次运行输出放过的行数；引擎 golden
全部改为 Tiqian 前缀名后删除该规则。

## 同步纪律

`engine` 中已翻译区域的任何 Kotlin 改动，必须同步修改本目录的 Haxe 副本，
并重新运行上面的比对；引擎行为有意改动、golden 随之刷新时，重新拷贝
`baseline-goldens`。进度与验证记录见 `PROGRESS.md`。
