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
- `core-kotlin.hxml`、`textrange-kotlin.hxml`、`smoke-kotlin.hxml`：
  调用 boring 生成 Kotlin 的编译清单。
- `data/`：生成 Unicode 数据类所需的区间数据。
- `patches/`：vendored boring（`.haxelib/`，不入库）之上的本地补丁存档。
- `out/`、`baseline-goldens/`、`smoke/`：生成物与本地基线拷贝，不入库。

## 验证命令

在仓库根目录执行。`baseline-goldens` 用 `cp` 从引擎 golden 目录同步：

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
