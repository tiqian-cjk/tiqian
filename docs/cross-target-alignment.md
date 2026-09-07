# 跨目标行为对齐判据

本文定义 engine-haxe（Haxe 版引擎）在五个目标语言上的行为对齐判据，以及
判定用的命令入口。当前状态数字见文末表格；表格随整改进度更新。

## 三项目标对齐

1. f32 生成物对原生 Kotlin：Haxe 生成的 Kotlin（`engine-haxe/core-kotlin.hxml`，
   带 `-D float-precision=f32`）编译并运行后，其测试轨迹与原生 Kotlin 引擎的
   golden 轨迹（`engine/src/jvmTest/resources/golden/test-traces/`）逐类一致。
   这条判据回答「Haxe Kotlin 与原本 Kotlin 行为是否相同」。
2. 五目标 f64 相互比对：五个目标（ts、kotlin、rust、swift、dart）在全精度
   模式下各自运行测试束，产出的逐测试记录（jsonl，一行一事件）逐行比对后
   完全一致。这条判据回答「所有输出语言的全精度行为是否相同」。
3. rust 与 kotlin 的 f64 比对：第 2 项的第一步验收只做这两个目标，判据是
   两目标的 jsonl 逐行一致。

第 1 项已有一组在运行的检查：`engine-haxe/tools/gates.sh all`（四项检查）里的
JS oracle 比对，用 Haxe 原生运行时对 golden 逐字节核对。第 1 项最终验收时还把
同一份 golden 用在生成物上：生成的 Kotlin 运行产出与 golden 对齐，证明从 Haxe
源码生成目标语言代码、再编译运行的整个过程没有改变行为。

## 分层判据

每层有独立判据，上层依赖下层通过：

| 层 | 判据 | 命令入口 |
|---|---|---|
| 生成 | 五目标入口各 RC=0 | `nix develop -c haxe engine-haxe/core-<t>.hxml` |
| 编译 | 各目标自身工具链无错误 | kotlinc 2.4.10（boring nix shell）、cargo、bun/tsc、swift build、dart analyze |
| 运行 | TestMain 无失败并写 jsonl | `BORING_TEST_RESULTS=<路径>` 后运行各目标测试束 |
| f32 对照 | kotlin（f32）运行轨迹对 golden 逐类一致 | 复用 `engine-haxe/tools/compare-traces.py`，数值相对容差 1e-6 |
| f64 对照 | 五目标 f64 jsonl 逐行一致 | boring 的 `tools/test-consistency/manager.hxml` 加 `manager.js` 范式 |

f32 对照的容差说明：两边数值都是单精度；golden 文本由 JVM 的
`Float.toString` 写出，被比较一侧的文本由另一套运行时的浮点转十进制规则
写出，同样的单精度位模式会打印成位数不同的十进制文本，且 sin/cos/pow 在
不同运行时的实现有末位差。1e-6 的相对容差（约一个单精度 ulp）只吸收这些
文本化末位差，不放宽数值本身。

生成与测试入口的 defines 取值与 boring 仓库 `examples/<t>.hxml` 相同：
`<t>-output`、`<t>-test-output`、`runtime-import`、`runtime-emit`，ts 另带
`package-shell=none` 并经仓库根 tsconfig 的 paths 解析 runtime；rust 另带
`package-name` 与 `package-license`。jsonl 的写入机制与 boring 相同：测试束
运行时读 `BORING_TEST_RESULTS` 环境变量并按行写事件。

## 当前状态（2026-09-05，vendored boring 副本 5034e98）

| 目标 | 生成 | 编译 | 运行 |
|---|---|---|---|
| kotlin（f32） | 通过 | 3569 错 / 168 文件 | 未达（编译未过） |
| kotlin（f64） | 通过（282＋111 文件） | 3589 错 / 169 文件 | 未达（编译未过） |
| ts / swift / dart | 生成拒绝（Std.string 不接受纯 class 的元素类型） | 未达 | 未达 |
| rust | 生成拒绝（每函数只支持一个 error enum） | 未达 | 未达 |

三个阻塞的修复位置都在 boring 仓库 `packages/compiler/reflaxe/**`：
Std.string 拒绝＝记录合成 toString 时，对声明了 toString 的普通 class 元素缺少
对应的 case 分支；rust 限制＝一个函数的调用路径到达两个 error enum 时没有
union 合成；kotlin 编译错误集中在 null 赋给非空参数、参数默认值缺失等几类
原因（错误来自生成的代码），按原因分批整改。f32 行为比对的既有结论不受
影响：`gates.sh all` 四项检查 121 类全过、比对全部一致。
