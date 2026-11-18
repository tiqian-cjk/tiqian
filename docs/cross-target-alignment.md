# 跨目标行为对齐判据

本文定义 engine-haxe（Haxe 版引擎）在五个目标语言上的行为对齐判据，以及
判定用的命令入口。文末表格是 2026-09-05 的历史测量，不能代表当前检出。

## 三项目标对齐

1. f32 生成物对原生 Kotlin：Haxe 生成的 Kotlin（`boring.json` 的 `kotlin-f32` bundle，
   带 `precision: f32` 声明）编译并运行后，其测试轨迹与原生 Kotlin 引擎的
   基准轨迹逐类一致。这条判据回答「Haxe Kotlin 与原本 Kotlin 行为是否相同」。
   原生 Kotlin 引擎的基准轨迹（golden）已在 105/105 对齐达成后随 golden 机制
   一起删除；当前判定入口是 `boring test kotlin-f32` 的生成测试。
2. 五目标 f64 相互比对：五个目标（ts、kotlin、rust、swift、dart）在全精度
   模式下各自运行同一组测试，产出的逐测试记录（jsonl，一行一事件）逐行比对后
   完全一致。这条判据回答「所有输出语言的全精度行为是否相同」。
3. rust 与 kotlin 的 f64 比对：第 2 项的第一步验收只做这两个目标，判据是
   两目标的 jsonl 逐行一致。

第 1 项的 JS oracle 比对曾由 `engine-haxe/tools/gates.sh` 的 compare 检查执行；
该检查依赖的基准轨迹已删除，检查随之移除（`gates.sh` 现为 g4、tests、ts 三项）。
第 1 项最终验收时把同一份基准轨迹用在生成物上：生成的 Kotlin 运行产出与基准
对齐，证明从 Haxe 源码生成目标语言代码、再编译运行的整个过程没有改变行为。

## 分层判据

每层有独立判据，上层依赖下层通过：

| 层 | 判据 | 命令入口 |
|---|---|---|
| 生成 | 各配置生成成功 | `nix develop -c boring gen <配置 ID> --project boring.json` |
| 编译与运行 | 目标工具链编译测试、运行成功并写 jsonl | 先运行对应配置的 `gen`，再运行 `nix develop -c boring test <配置 ID> --project boring.json` |
| f32 对照 | kotlin（f32）的生成测试全部通过 | `boring test kotlin-f32`；基准轨迹已随 golden 机制删除 |
| 跨目标对照 | 参与比较的配置逐测试结果一致 | `nix develop -c boring compare --project boring.json`；完整生成、测试与比较用 `nix develop -c boring verify --project boring.json` |

当前 `boring.json` 的比较基准是 `kotlin-f32`。上表的 `compare` 命令按这个
配置运行；第 2、3 项要求的纯 f64 比对，还需在项目配置中指定同精度的
比较基准与参与配置，再运行该命令。

f32 对照的判据说明：两边数值都是单精度，判据取位模式一致。历史比对中
基准轨迹的文本由 JVM 的 `Float.toString` 写出，被比较一侧的文本由另一套运行时的
浮点转十进制规则写出，同样的单精度位模式会打印成位数不同的十进制文本，所以
比对前先把两侧文本解析回 binary32 位模式，再逐位比较。基准轨迹已删除，
这段说明保留为 `compare-traces.py` 的判据记录。

sin/cos/pow 在不同运行时的末位差按偏离处理，不作为豁免项。
放宽容差会让 480 与 479.99982 这类差异通过比对，而这类差异在排版里会改变
断行位置。

配置 ID、生成参数、输出目录和打包元信息由仓库根目录的 `boring.json`
指定。driver 为测试运行设置结果文件路径；手动运行生成物时才需要自行设置
`BORING_TEST_RESULTS`。具体生成与测试步骤见
[engine-haxe/README.md](../engine-haxe/README.md#生成与测试)。

## 历史测量（2026-09-05，vendored boring 副本 5034e98）

| 目标 | 生成 | 编译 | 运行 |
|---|---|---|---|
| kotlin（f32） | 通过 | 3569 错 / 168 文件 | 未达（编译未过） |
| kotlin（f64） | 通过（282＋111 文件） | 3589 错 / 169 文件 | 未达（编译未过） |
| ts / swift / dart | 生成拒绝（Std.string 不接受纯 class 的元素类型） | 未达 | 未达 |
| rust | 生成拒绝（每函数只支持一个 error enum） | 未达 | 未达 |

当时的三个阻塞位于 boring 仓库 `packages/compiler/reflaxe/**`：记录合成
`toString` 时，缺少普通 class 元素的处理；Rust 函数的调用路径到达两个
error enum 时，缺少 union 合成；Kotlin 生成代码中还有 null 赋给非空参数、
参数默认值缺失等错误。这些是当时的诊断，不能据此判断当前编译器状态。
当时 `gates.sh all` 的四项检查覆盖 121 类，均已通过。
