# 五目标生成代码编译错误普查与修复追踪

本文记录 engine-haxe 生成代码在五种输出语言（Kotlin、TypeScript、Rust、Swift、
Dart）下的编译错误，作为跨目标行为对齐（见
[cross-target-alignment.md](cross-target-alignment.md)）的修复计划与进度追踪。
普查对象是 engine-haxe/out/ 下由 boring 从 Haxe 源码翻译出的目标语言代码目录。
原生 `engine` 模块的 `./gradlew :engine:jvmTest` 无失败，不在本文范围内。

当前状态：Kotlin 的 f32 与 f64 两个目录已完成逐类普查（第 3 节，基线为
tiqian `105dfb30` 加 boring `4b1fec9`）；rust 的生成命令退出码为 0，首次
编译普查已完成，2026-09-06 在 boring `75b08ed2` 复测为 180 条错误，按消息
骨架 15 类，全部在语法层（第 6 节）；
Swift 的生成命令自 boring `2c9257d` 起退出码为 0，首次编译普查已完成
（第 5 节：8 条错误，按消息骨架 2 类）；TypeScript 的生成命令自 boring
`de11c06a`（合并 UStringException 生成修复 `f270c670`）起退出码为 0，首次
编译普查已完成（第 7 节：1127 条错误，按消息骨架 19 类，其中测量环境
308 条、引擎侧 819 条）；Dart 的生成命令退出码为 1，第一处报错见第 4 节。

## 1 更新规则

- 每个修复项只有一个复选框。满足以下四条后在复选框勾选，并在文末进度记录表
  追加一行：修复已合入 boring main（写提交号）或 tiqian（写提交号）；vendored
  副本已推进并重新生成相关目录；该错误种类在相关目录的计数都是 0；boring 的
  验收命令全部通过。
- 一次修复只允许勾选一次对应的复选框；不允许一次勾选多项，也不允许提前勾选。
- 计数必须来自本文「测量配方」一节的命令输出，不允许凭印象填写。
- 错误按消息骨架逐行记录，每一类一行（2026-09-06 用户裁定：不设「未归类」
  「其余」聚合行，折叠会让任务量检验失真）。新暴露的错误类在逐类表加新行，
  不允许并入既有行，也不允许并入任何聚合行。每张逐类表必须附求和校验，各类
  计数之和等于总数。
- 大类内部的分解同样逐条列出：名称、模块、文件等维度的分布写全每一个名字
  与计数，不设「前 N 位」的截断，也不设把多个名字合并成一行的聚合行
  （2026-09-06 用户裁定：条目折叠省略会让工作量检验失真）。
- 修复项与 KPI 的切分必须反映修复工作量：每条修复项写明它覆盖的错误类、
  类内条目与计数，KPI 的现值写各目标逐类表的实测计数；不把多个修复面合并
  成一个指标（2026-09-06 用户裁定）。

## 2 测量配方

### 2.1 Kotlin（f32 与 f64）

```shell
# 前置：vendored 副本指向要测的 boring 提交
cd /home/losses/Development/tiqian/.haxelib/boring/git && git fetch origin && git checkout <提交号>

# 从 tiqian 仓库根目录重新生成两个 Kotlin 目录。每次 haxe 前在同一个
# nix shell 里重写 .dev（.dev 损坏时 haxe 报 Type not found : Intercept，
# 所以每次生成前都重写一次）
nix develop -c bash -c 'printf "%s" /home/losses/Development/tiqian/.haxelib/boring/git > .haxelib/boring/.dev; haxe engine-haxe/core-kotlin.hxml'      # f32
nix develop -c bash -c 'printf "%s" /home/losses/Development/tiqian/.haxelib/boring/git > .haxelib/boring/.dev; haxe engine-haxe/core-kotlin-f64.hxml'  # f64

# 编译普查。kotlinc 不在默认 PATH，必须用绝对路径；退出码 1 是预期，
# 错误计数来自日志
cd /home/losses/Development/tiqian
nix develop -c bash -c '
KOTLINC=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin/kotlinc
$KOTLINC -Xallow-kotlin-package \
  $(find engine-haxe/out/kotlin-gen engine-haxe/out/kotlin-gen-tests -name "*.kt") \
  -d /tmp/tiqian-f32.jar 2> /tmp/census-f32.log
$KOTLINC -Xallow-kotlin-package \
  $(find engine-haxe/out/kotlin-gen-f64 engine-haxe/out/kotlin-gen-f64-tests -name "*.kt") \
  -d /tmp/tiqian-f64.jar 2> /tmp/census-f64.log
grep -a -c " error: " /tmp/census-f32.log
grep -a -c " error: " /tmp/census-f64.log'

# 逐类枚举（第 3.2 节逐类表的产出命令）。消息骨架指把消息里的具体
# 标识符与数字替换成占位符后得到的模板：单引号内的标识符替换为 'X'，
# 数字串替换为 N，重复的枚举项收敛。输出每一行是一个错误类与其计数；
# 两列各自求和必须等于上面的总数，此校验缺失的表无效。
for LOG in /tmp/census-f32.log /tmp/census-f64.log; do
  echo "== $LOG"
  grep -a " error: " "$LOG" | sed 's/^.* error: //' \
    | sed "s/'[^']*'/'X'/g; s/\(, 'X'\)\{2,\}/, 'X'…/g; s/[0-9]\+/N/g" \
    | sort | uniq -c | sort -rn
  grep -a " error: " "$LOG" | sed 's/^.* error: //' \
    | sed "s/'[^']*'/'X'/g; s/\(, 'X'\)\{2,\}/, 'X'…/g; s/[0-9]\+/N/g" \
    | awk '{s+=$1} END{print "sum=" s}'
done

# argument type mismatch 类的形状分解（第 3.3 节的产出命令）。形状按
# 实际类型与期望类型的可空性、是否数值转换分类；「其余转换」收集还没有
# 定名的形状，下次分解时如出现新的成批形状，拆成具名形状行。
for LOG in /tmp/census-f32.log /tmp/census-f64.log; do
  echo "== $LOG"
  grep -a " error: argument type mismatch" "$LOG" \
    | sed "s/.*actual type is '\([^']*\)', but '\([^']*\)' was expected.*/\1 \2/" \
    | awk '{a=$1; e=$2
        an=(a~/\?$/); en=(e~/\?$/)
        if (an&&!en) k="可空给非空"
        else if (a=="Int"&&(e=="Float"||e=="Double")) k="Int 给浮点"
        else if (a~/^Number/) k="Number 装箱给浮点"
        else if (a=="Long"&&(e=="Float"||e=="Double")) k="Long 给浮点"
        else k="其余转换"
        c[k]++}
      END{for(k in c) printf "%5d  %s\n", c[k], k}' | sort -rn
done

# unresolved reference 类的符号分布（第 3.4 节的产出命令）
grep -a " error: unresolved reference" /tmp/census-f32.log \
  | sed "s/.*unresolved reference '\([^']*\)'.*/\1/" | sort | uniq -c | sort -rn
```

### 2.2 其余四目标

```shell
nix develop -c bash -c 'haxe engine-haxe/core-ts.hxml'      # TypeScript，自 boring de11c06a 起退出码 0
nix develop -c bash -c 'haxe engine-haxe/core-rust.hxml'    # Rust，当前退出码 0
nix develop -c bash -c 'haxe engine-haxe/core-swift.hxml'   # Swift，自 boring 2c9257d 起退出码 0
nix develop -c bash -c 'haxe engine-haxe/core-dart.hxml'    # Dart，自 boring `31627b5c` 起退出码 0

# Swift 重生成与首次编译普查（2026-09-06；boring 185cf02，tiqian 3240f50a）
cd /tmp/tiqian-swiftcens && nix develop -c bash -c 'printf /tmp/boring-swiftcens > .haxelib/boring/.dev; haxe engine-haxe/core-swift.hxml; echo REGEN_RC=$?'
cd /tmp/tiqian-swiftcens && nix develop /home/losses/Development/boring -c bash -c 'find engine-haxe/out/swift-gen -name "*.swift" | sort | xargs swiftc -typecheck 2> /tmp/swiftc-census.log; echo SWIFTC_RC=$?; grep -c ": error:" /tmp/swiftc-census.log'
```

boring 遇到尚未实现生成规则的 Haxe 构造时，在第一处这样的构造上报错并中止。
四个目标的生成命令退出码均已为 0，四者的编译普查命令都已记在本节。

TypeScript 重生成与首次编译普查（2026-09-06；boring `7606ff85`，tiqian
`f2517918`，工作树 /tmp/tiqian-audit，重生成日志 /tmp/audit-gen.log，
编译普查日志 /tmp/audit-tsc.log，逐类表 /tmp/audit-tsc-families.txt，
类内分解 /tmp/audit-tsc-subfamilies.txt）：

```shell
# 重生成（.dev 指向 boring 主树检出，检出位于 7606ff85）
cd /tmp/tiqian-audit && nix develop -c bash -c 'printf /home/losses/Development/boring > .haxelib/boring/.dev; haxe engine-haxe/core-ts.hxml; echo "TS_RC=$?"'

# 编译普查。tsc 用 tiqian 主树 node_modules 里的副本（5.9.3）；有错误时
# 退出码非 0 是预期，错误计数来自日志
cd /tmp/tiqian-audit/engine-haxe/out && nix develop -c bash -c 'bun /home/losses/Development/tiqian/node_modules/typescript/bin/tsc --noEmit --allowImportingTsExtensions --module esnext --moduleResolution bundler --target es2022 $(find ts-gen ts-gen-tests -name "*.ts") > /tmp/audit-tsc.log 2>&1; echo "TSC_RC=$?"; grep -c "error TS" /tmp/audit-tsc.log'

# 逐类枚举（第 7 节逐类表的产出命令）。tsc 的诊断首行含 error TSNNNN，
# 续行不含，计数只取首行。骨架化在去掉行首文件位置后的消息段上进行：
# 单引号内文本替换为 'X'，花括号与尖括号内的类型文本替换为 {…} 与 <…>
# （各两轮，处理嵌套），数字替换为 N（错误码里的数字同样被替换，输出里
# 显示为 TSN，逐类表的「错误码」列从原始行对照取回；本表 19 个骨架与
# 错误码一一对应）
grep -a 'error TS' /tmp/audit-tsc.log | sed 's/^.*error //' \
  | sed -E "s/'[^']*'/'X'/g" \
  | sed -E 's/\{[^{}]*\}/{…}/g' | sed -E 's/\{[^{}]*\}/{…}/g' \
  | sed -E 's/<[^<>]*>/<…>/g' | sed -E 's/<[^<>]*>/<…>/g' \
  | sed -E 's/[0-9]+/N/g' \
  | sort | uniq -c | sort -rn
# 求和校验：上式输出第一列求和必须等于错误总数

# 类内分解（第 7.2 节的产出命令）：对指定错误码按名字、模块名或文件抽取
# 计数，下面以 TS2304 的名称分布为例，其余错误码的抽取规则见第 7.2 节
grep -a 'error TS2304' /tmp/audit-tsc.log | sed -E "s/.*Cannot find name '([^']+)'.*/\1/" | sort | uniq -c | sort -rn
```

rust 的编译普查命令如下（2026-09-06 首次运行，F4a）：

```shell
# Cargo.toml 由 boring Compiler.hx 在 PackageShell 启用时写进输出目录本身
# （core-rust.hxml 的 -D rust-output 指到 .../rust-gen/src），cargo 从该
# 目录运行。退出码 101 是预期，错误计数来自日志；必须带
# --message-format=short，原因见 2.3 节
nix develop -c bash -c 'cd /tmp/tiqian-census4/engine-haxe/out/rust-gen/src && cargo check --message-format=short' \
  2> /tmp/census-r4-rust.log; echo rc=$?

grep -a -c ": error" /tmp/census-r4-rust.log   # 错误总数

# 逐类枚举（第 6 节逐类表的产出命令）。骨架化规则与 Kotlin 相同：引号与
# 反引号内的文本替换为占位符、重复枚举项收敛、数字替换为 N；另把
# error[E####] 收敛为 [E]
grep -a ": error" /tmp/census-r4-rust.log | sed 's/^.*: error//' \
  | sed 's/^\[E[0-9]*\]:/[E]:/' \
  | sed 's/`[^`]*`/`X`/g' \
  | sed "s/'[^']*'/'X'/g" \
  | sed 's/\(, `X`\)\{2,\}/, `X`…/g' \
  | sed 's/[0-9]\+/N/g' \
  | sort | uniq -c | sort -rn
# 求和校验：上式输出第一列求和必须等于错误总数
```

Dart 重生成与首次编译普查（2026-09-06；boring `31627b5c`，tiqian `17a646da`，
工作树 /tmp/tiqian-dartic，普查日志 /tmp/dartic-census-gen.log 与
/tmp/dartic-census-tests.log，逐类表 /tmp/dartic-code-combined.txt，类内分解
/tmp/dartic-undef-name.txt 等）：

```shell
# 重生成（消费树克隆与 .dev 都指向合并工树 /tmp/boring-darticm 的 main
# 检出 31627b5c；两处须指向同一提交，不一致时报 Type not found）
cd /tmp/tiqian-dartic && nix develop -c bash -c 'printf /tmp/boring-darticm > .haxelib/boring/.dev; rm -rf engine-haxe/out/dart-gen engine-haxe/out/dart-gen-tests; haxe engine-haxe/core-dart.hxml; echo DART_RC=$?'

# 编译普查。dart SDK 来自 boring 的 nix develop（3.13.0）；有错误时退出码
# 非 0 是预期，错误计数来自日志；两个目录分别运行
cd /tmp/tiqian-dartic/engine-haxe/out/dart-gen && nix develop /home/losses/Development/boring -c bash -c 'dart analyze --format=machine > /tmp/dartic-census-gen.log 2>&1; echo rc=$?; grep -c "^ERROR" /tmp/dartic-census-gen.log'
cd /tmp/tiqian-dartic/engine-haxe/out/dart-gen-tests && nix develop /home/losses/Development/boring -c bash -c 'dart analyze --format=machine > /tmp/dartic-census-tests.log 2>&1; echo rc=$?; grep -c "^ERROR" /tmp/dartic-census-tests.log'

# 逐类枚举（第 8 节逐类表的产出命令）。机器格式为
# 级别|类别|错误码|文件|行|列|长度|消息，错误码取第 3 列；WARNING 与 INFO
# 不计入；gen 与 tests 两目录合并计数，keys 收两侧并集
for side in gen tests; do awk -F'|' -v s=$side '/^ERROR/{print $3"\t"s}' /tmp/dartic-census-$side.log; done \
  | awk -F'\t' '{if($2=="gen") g[$1]+=1; else t[$1]+=1; keys[$1]=1} END{for (k in keys) printf "%s\t%d\t%d\t%d\n", k, g[k]+0, t[k]+0, g[k]+t[k]+0}' \
  | sort -t$'\t' -k4 -rn
# 求和校验：上式输出合计列求和必须等于错误总数 2931

# 类内分解（第 8.2 节各表的产出命令）。以 UNDEFINED_IDENTIFIER 的名称
# 分布为例，其余错误码的抽取规则见第 8.2 节
cat /tmp/dartic-census-gen.log /tmp/dartic-census-tests.log | awk -F'|' '/^ERROR/ && $3=="UNDEFINED_IDENTIFIER" {msg=$8; if (match(msg, /Undefined name '\''[^'\'']*'\''\.\''/)) print substr(msg, RSTART+16, RLENGTH-18)}' | sort | uniq -c | sort -rn
```

### 2.3 已知的测量错误

- kotlinc 2.4.10 的错误消息是「null cannot be a value of a non-null type」
  （cannot 为小写），按旧版消息「Null can not be」搜索会计 0，得出错误结论。
- kotlinc 诊断是多行的：候选列表等文本出现在错误行的后续行上。2026-09-06
  实测，「None of the following candidates」在一份日志里命中 384 行，全部是
  续行，错误行本身的消息是「none of the following candidates is
  applicable:」（该日志里 18 行）。因此计数一律先过滤含 ` error: ` 的行；
  对全日志直接 grep 会把续行计入，得出虚高的数。
- 消息文本必须按当前编译器版本逐字写进模式。「cannot infer type for type
  parameter」在旧版作「Not enough information to infer」，按旧文本搜索在
  kotlinc 2.4.10 上一条也匹配不到，该类会被误记为 0（2026-09-06 实测）。
- kotlinc 与 bun test 并发运行会竞争 CPU，使 boring 仓库
  `tests/ts/package-shell.test.ts` 的 5 秒超时项失败，普查与测试不要同时运行。
- haxe 的宏阶段错误打印格式是「文件:行号 : 消息」，与警告格式相同，没有
  「Error:」前缀；判断一条输出是错误还是警告，唯一依据是命令的退出码。
- rust 的 `cargo check` 默认输出多行诊断：错误行以行首 `error` 开始，没有
  `文件:行:列: error:` 前缀，本节的 `: error` 锚点一个都数不到
  （2026-09-06 实测：同一棵生成树，默认形按该锚点数得 0，short 形数得
  180）。普查命令必须带 `--message-format=short`。
- rust 的默认多行输出里，`grep -c "^error"` 会把末尾的汇总行 `error:
  could not compile ... due to N previous errors` 也计入（同一棵树 180 条
  诊断加 1 行汇总数得 181）；short 形没有汇总行，不存在这个问题。

## 3 Kotlin 普查结果

### 3.1 基线快照

- 测量基线：tiqian `105dfb30`（本地 main）加 boring `4b1fec9`，2026-09-06
  在工作树 /tmp/tiqian-census4 实测（脚本 /tmp/census-r4.sh，日志
  /tmp/census-r4-f32.log 与 /tmp/census-r4-f64.log，逐类表存于
  /tmp/census-r4-f32-families.txt 与 /tmp/census-r4-f64-families.txt）。
  主树 vendored 副本当时仍在 `012ab59`，重测前先按第 2.1 节推进。
- f32 目录（out/kotlin-gen 与 kotlin-gen-tests）1183 条错误；f64 目录
  （out/kotlin-gen-f64 与 kotlin-gen-f64-tests）1201 条错误；两目录 warning
  计数均为 0。
- 基线历史：`a75601a` 上首次普查 f32 3338 / f64 3358；`5d7417e` 上
  f32 3335 / f64 3355；`8d17b59`（nullargs 合入）上 f32 1535 / f64 1553；
  `4b1fec9`（knarrow 合入）加 tiqian 侧 onlysafe 上半（`3ce6f511`）与
  sbuf-bind（`0b152313`）后为本次的 f32 1183 / f64 1201。旧分桶表按消息
  种类聚合了 28 桶，2026-09-06 起作废，由第 3.2 节逐类表取代。

### 3.2 逐类全表（f32 36 类，f64 39 类）

「判定」列的含义：一个错误类的修复位置（boring 生成器的机制位置，或
tiqian 源的一类写法）已经探针证实时，记修复面；只有猜测记「假设」；都没有
记「未判定」。判定的方法见 T-attr（第 11 节第 1 组）：对类内抽样错误点读
生成代码后定性。假设不构成派发依据，证实后才开修复项。本轮新增一档
「形状证实」：探针读过该类抽样错误点的生成代码、确认错误落在生成形状上，
但还没有把生成器机制定位到文件与分支；它的可信度高于假设、低于修复面，
不单独构成派发依据。本文用到两个修复面名：修复面 A 指可空接收者上方法调用
的生成机制；数值转换面指数值类型互转的生成机制。

判定来源：T-attr r1 报告 /tmp/dispatch-state/tiqian-tattr-r1.report.md（基线
boring `4b1fec9`）。该报告的逐类「修复面位置」段是同一份七条引用的重复粘贴，
不构成逐类定位，本文不采信其定位、只采信其抽样形状；数值转换面
（KotlinExpr.hx:2806-2820 的 renderCallArgs 只在实参位插入转换）与 getter
降级可见性（`5628b4d` 生成 `private override`）两处机制由派发方在 4b1fec9
检出复核。

| 错误消息类（骨架） | f32 | f64 | 判定与处置 |
|---|---:|---:|---|
| argument type mismatch: actual type is 'X', but 'X' was expected. | 407 | 416 | 形状分解见 3.3；Int 给浮点与 Long 给浮点两形状已判数值转换面（F3j），可空、装箱与其余形状仍待证 |
| unresolved reference 'X'. | 333 | 326 | 假设（T-attr 抽样读到缺失导入 UString 与成员 kind 两形，机制未逐一定位）；符号分布见 3.4；#23 |
| only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver of type 'X'. | 75 | 75 | 修复面 A（探针列出的三个原因见 boring-onlysafe-probe.report.md）；#22 执行中 |
| operator call is prohibited on a nullable receiver of type 'X'. Use 'X'-qualified call instead. | 60 | 60 | 假设：修复面 A 延伸（接收者类型相同；InlineObjectLayoutTest.kt:48 可空算术实测）；待探针 |
| cannot infer type for type parameter 'X'. Specify it explicitly. | 42 | 42 | 假设（T-attr 抽样集中在 run 块与长实参表，未定位统一推断机制）；随第二轮定位 |
| operator 'X' cannot be applied to 'X' and 'X'. | 35 | 32 | 修复面＝数值转换面：运算位没有 Int 到 Float 的转换（EmergencyGraphemeTrackingTest.kt:33 比较 `hyphenAdvance != 0` 实测；机制位置 KotlinExpr.hx:2806-2820 的 renderCallArgs 只在实参位插入转换，派发方复核）；F3j |
| return type mismatch: expected 'X', actual 'X'. | 28 | 28 | 修复面＝数值转换面：return 位没有转换（GreedyLineBreakerTest.kt:366 给 Float 函数 `return -1` 实测）；F3j |
| cannot access 'X': it is private in 'X'. | 27 | 27 | 修复面＝getter 降级可见性与私有静态跨类调用（形状实测：get_strategyName 于 LineBreakerCoverage2Test.kt:21、get_isMixed 于 ContextualQuoteRoleResolver.kt:88、emptyHanging 于 LineOptimizationCoverageTest.kt:151；生成位置待定位）；F3k |
| assignment type mismatch: actual type is 'X', but 'X' was expected. | 19 | 23 | 修复面＝数值转换面：赋值位没有转换（Justifier.kt:89 `remaining = 0`、LineAdjustmentStage.kt:134 Math.round 结果回赋实测；可空赋值形状混在此类，修复后剩余归可空形状再判）；F3j |
| none of the following candidates is applicable: | 18 | 18 | 假设（T-attr 抽样为构造实参 Float 与 Number 混型、复合赋值两形混杂）；待证 |
| initializer type mismatch: expected 'X', actual 'X'. | 15 | 17 | 修复面＝数值转换面：默认值位没有转换（RawFontMetrics.kt:3 `val leading: Float = 0` 实测）；F3j |
| too many arguments for 'X'. | 14 | 14 | 形状证实：std 影子数组的 indexOf 带了 null 第二实参（CoreBoundaryTest.kt:58 `indexOf(3, null)` 实测）；机制位置待定位 |
| modifier 'X' is incompatible with 'X'. | 14 | 14 | 修复面＝getter 降级生成 `private override`（boring `5628b4d` 引入的降级形状；LineBreakerCoverage2Test.kt:138 与 LineBreaker.kt:42 实测，Kotlin 语法禁止 private 与 override 并用）；F3k |
| conflicting declarations: | 13 | 13 | 形状证实：循环外提升的临时名 `_g` 在同一函数体重复声明（PreparedParagraphJfTest.kt:116 与 :126 实测）；机制位置待定位 |
| 'X' modifier is required on 'X'. | 11 | 12 | 假设：Number 装箱值走比较运算触发（Justifier.kt:85 `d > 0` 实测，d 为 Number 装箱）；待证 |
| type mismatch: inferred type is 'X', but 'X' was expected. | 11 | 11 | 假设（T-attr 抽样含异常第二代嵌套类引用 LayoutQueries.kt:390 `TiqianNoSuchElementException.Message`，疑与 #37 异常子类是同一机制）；待证 |
| function invocation 'X' expected. | 8 | 8 | 形状证实：方法名作值使用时没有带调用括号（ContextualQuoteRoleResolverNestedAndSurrogateTest.kt:84 读 `surrogateText` 实测）；机制位置待定位 |
| cannot weaken access privilege private for 'X' in 'X'. | 7 | 7 | 修复面＝getter 降级可见性（同 modifier incompatible 行：实现可见性低于接口成员）；F3k |
| no 'X' operator method providing array access. | 6 | 6 | 形状证实：数组 set 访问器渲染（PreparedParagraph.kt:1726 `a[i] = …` 实测）；机制位置待定位 |
| receiver type 'X' contains star projection which prohibits the use of 'X'. | 6 | 6 | 假设：Number 装箱（LineRepair.kt:198 `shrink > 0` 实测，shrink 为 Number 装箱）；待证 |
| 'X' is prohibited here. | 5 | 5 | 形状证实：return 语句被生成到不可用位置（BilingualEmphasisTest.kt:16 实测）；机制位置待定位 |
| jvmField has no effect on a private property. | 5 | 5 | 形状证实：@JvmField 注解在私有属性上无条件生成（PreparedParagraph.kt:25 实测）；机制位置待定位 |
| 'X' expression must be exhaustive. Add the 'X', 'X'… branches or an 'X' branch. | 4 | 4 | 形状证实：枚举 when 缺少未列构造器的臂（FontMetrics.kt:15 缺 CjkPunctuation、Emoji、Unknown 实测）；机制位置待定位 |
| variable 'X' must be initialized. | 3 | 3 | 形状证实：var 声明无初始化器、分支赋值后读取（FontMetrics.kt:21 实测）；机制位置待定位 |
| unresolved reference 'X' for operator 'X'. | 3 | 3 | 形状证实：可空算术混型（PunctuationGeometryLedger.kt:36 实测）；T-attr 判操作符名称渲染，派发方未复核 |
| 'X' hides member of supertype 'X' and needs an 'X' modifier. | 2 | 2 | 形状证实：dataClass 生成的 hashCode 覆写缺 override 修饰（BopomofoReading.kt:15 实测）；机制位置待定位 |
| redeclaration: | 2 | 2 | 形状证实：两个外层类各自生成同名嵌套类 Resolution（ContextualDashEllipsisRoleResolver.kt:241 与 ContextualQuoteRoleResolver.kt:311 实测）；机制位置待定位 |
| condition type mismatch: inferred type is 'X' but 'X' was expected. | 2 | 2 | 假设：修复面 A 延伸（可空 Boolean 作条件，PunctuationGeometryLedgerCoverageTest.kt:46 实测） |
| 'X' cannot be a callee. | 1 | 1 | 修复面＝KotlinDecl 异常子类第二代的生成规则：super 调用被放进 init 块（IllegalStateException.kt:5:5，该类计数 1 即全部样本）；与 #37 同构造不同目标，修复项在 #37 完成后按修复面开列 |
| this declaration needs opt-in. Its usage must be marked with 'X' or 'X' | 1 | 1 | 测量环境（kotlinc 2.4.10 对实验性标准库 API 的 opt-in 要求，LineRepair.kt:114；可用编译器参数消除，不派修复） |
| smart cast to 'X' is impossible, because 'X' is a local variable that is mutated in a capturing closure. | 1 | 1 | 修复面＝闭包捕获的局部变量在闭包外读取（ParagraphDpLineBreaker.kt:261 实测；Kotlin 语义要求拷贝到不可变局部）；修复项随第二轮定位开列 |
| non-nullable value required to call an 'X' method in a for-loop. | 1 | 1 | 假设：修复面 A 延伸（可空迭代器，LineAdjustmentStage.kt:610 实测） |
| names _, __, ___, ... are reserved in Kotlin. | 1 | 1 | 形状证实：下划线参数名直接输出（UnicodePunctuationBoundaryTestSupport.kt:118 `resolve(_: LayoutProfileId)` 实测）；机制位置待定位 |
| method 'X' is ambiguous for this expression. Applicable candidates: | 1 | 1 | 形状证实：for-in 迭代候选二义（LineRepair.kt:160 实测）；机制位置待定位 |
| infix call is prohibited on a nullable receiver of type 'X'. Use 'X'-qualified call instead. | 1 | 1 | 假设：修复面 A 延伸（可空区间端点，LineBreakPlanningStage.kt:409 实测） |
| classifier 'X' does not have a companion object, so it cannot be used as an expression. | 1 | 1 | 形状证实：std Type 反射把枚举类名作值使用（TextShaperCoverageTest.kt:55 实测）；机制位置待定位 |
| Expecting an element. | 0 | 9 | f64 独有；#25 定位任务 |
| 'X' must have both main and 'X' branches when used as an expression. | 0 | 2 | f64 独有；#25 定位任务 |
| the expression cannot be a selector (cannot occur after a dot). | 0 | 1 | f64 独有；#25 定位任务 |
| 合计（求和校验） | 1183 | 1201 | 与 3.1 节总数相等 |

判定进度小结（2026-09-06 T-attr r1 抽样并入后）：修复面 10 整类（only safe；
operator applied、return、initializer 三类与 assignment、argument 的数值形状
同属 F3j 的数值转换面；cannot access、modifier incompatible、cannot weaken
三类同属 F3k 的 getter 降级可见性；smart cast；cannot be a callee）加
argument 类内 Int 给浮点与 Long 给浮点两形状；测量环境 1 类（opt-in）；
形状证实 14 类（机制位置待定位，不单独构成派发依据）；假设 10 类（修复面
A 延伸 4 类：operator call prohibited、condition、for-loop 迭代、infix；
Number 装箱候选 2 类：modifier required、star projection；其余 4 类：
unresolved、cannot infer、none of candidates、type mismatch）；f64 独有
3 类已排定位任务。T-attr 第二轮的剩余工作＝把 14 类形状证实定位到文件与
分支、证实或否证 10 类假设、对 3.4 节符号逐个定位所属机制。

### 3.3 argument type mismatch 形状分解

2026-09-06 实测（r4 日志，产出本表的命令见第 2.1 节）：

| 形状 | f32 | f64 | 判定 |
|---|---:|---:|---|
| 可空给非空（actual 类型以 ? 结尾，expected 非空） | 261 | 261 | 假设：疑与修复面 A 同源；待探针 |
| Int 给浮点 | 80 | 88 | 修复面＝数值转换面（F3j）：FontPolicyCoverageTest.kt:243 里 `(13).toFloat()` 与未经转换的 `0` 并存，实参位已转换、未经转换的 `0` 是该机制没有覆盖的形状；运算、return、默认值、赋值位同样没有转换（对应 3.2 表四类） |
| Number 装箱给浮点 | 33 | 32 | 假设：T-attr 抽样为可空两臂条件表达式（FontPolicyCoverageTest.kt:125 实测），装箱路径未定位；待证 |
| Long 给浮点 | 0 | 2 | 修复面＝数值转换面（F3j）：renderCallArgs 的 isIntType 不覆盖 Long（PreparedParagraphJsonNumberTest.kt:32 实测）；f64 独有 |
| 其余转换 | 33 | 33 | 未判定；随 T-attr 第二轮 |
| 合计（等于该类计数） | 407 | 416 | |

旧版 K4 的统计命令只覆盖数值形状（当时 f32 144 / f64 152），由本表取代；
「其余转换」行的存在不违反第 1 节的禁折叠裁定，它是对 argument type
mismatch 这一个类内部的形状分类，下次分解出现新的成批形状时拆成具名行。

### 3.4 unresolved reference 符号分布（导航用，非修复面）

2026-09-06 实测（r4 f32 日志，产出命令见第 2.1 节）：去重后 111 个符号，
计数合计 336，与该类的 f32 计数相等。按第 1 节裁定全量列举，每格为
「计数 符号」。

| 计数 符号 | 计数 符号 | 计数 符号 | 计数 符号 | 计数 符号 | 计数 符号 |
|---|---|---|---|---|---|
| 37 kind | 29 UString | 24 clusterRange | 16 Ic | 10 endReason | 9 compareTo |
| 8 f | 7 TiqianNoSuchElementException | 7 floatToI32 | 6 s | 6 copy | 5 sourceRange |
| 5 region | 5 pi | 5 i32ToFloat | 5 concat | 5 bi | 5 adjustedWidth |
| 4 trailingGlue | 4 splice | 4 SortedMap | 4 pop | 4 naturalWidth | 4 lineIndex |
| 4 hangingClusterIndices | 4 __functional_shim | 3 text | 3 start | 3 minus | 3 compareRawFontMetrics |
| 3 compareFontMetricsRequest | 2 Type | 2 top | 2 shift | 2 right | 2 repair |
| 2 reason | 2 pow | 2 openStart | 2 openEnd | 2 NodeFileSystem | 2 length |
| 2 left | 2 compareTextStyle | 2 compareLayoutFontMetrics | 2 bottom | 1 unshift | 1 trailingGlueInitiallyConsumed |
| 1 repairCandidates | 1 punctuationClass | 1 policyBodyFloor | 1 message | 1 leadingGlueInitiallyConsumed | 1 leadingGlue |
| 1 insert | 1 inkWidth | 1 inkContainmentBodyFloor | 1 inkContainmentApplied | 1 inkCenter | 1 inkBoundsFallback |
| 1 inkBounds | 1 haxe | 1 haltValidation | 1 haltAdvance | 1 glyphPlacementReason | 1 glyphInlineShift |
| 1 get_hangingClusterIndex | 1 geometrySource | 1 count | 1 cornerRadius | 1 compareSpacingDecisionInfo | 1 compareSize |
| 1 compareShapingEvidenceKey | 1 compareShapingDecisionInfo | 1 compareRubyDecisionInfo | 1 compareRepairCandidate | 1 compareRecordedShapingResult | 1 compareRecordedFontMetrics |
| 1 comparePunctuationWidthPolicy | 1 comparePunctuationDecisionInfo | 1 compareParagraphStyle | 1 compareMetricsEvidenceKey | 1 compareMetricDecisionInfo | 1 compareLineRepairCandidateInfo |
| 1 compareLineEdgeTrimDecisionInfo | 1 compareLineCandidate | 1 compareLineBox | 1 compareLayoutConstraints | 1 compareJustificationDecisionInfo | 1 compareInlineObjectSpan |
| 1 compareInlineObjectPunctuationAttachmentDecisionInfo | 1 compareInlineObjectDecisionInfo | 1 compareInlineBoxSpan | 1 compareInlineBoxDecisionInfo | 1 compareGlyphRun | 1 compareGlue |
| 1 compareDecorationSegmentInfo | 1 compareDecorationDecisionInfo | 1 compareClusterGeometryDecisionInfo | 1 compareCluster | 1 compareBopomofoGlyphPlacement | 1 compareAutoSpacePolicy |
| 1 compareAutoSpaceDecisionInfo | 1 compareAdjustmentStylePolicy | 1 charCodeAt | 1 char | 1 bodyWidth | 1 anchor |
| 1 advanceExpansion | 1 advance | 1 add |  |  |  |

f64 侧（326 行）按第 2.1 节命令重新统计后再列举。符号名只是导航线索；哪些
符号共享一个修复面（数据类比较合成、import 登记、成员名映射、操作符生成等
机制中的哪几个）由 T-attr 第二轮判定，不按符号名分组派发。

## 4 ts、swift、dart 三个目标的当前位置（2026-09-06 实测）

boring 对尚未实现生成规则的 Haxe 构造，在生成阶段调用 `Context.error` 报错
并中止，不做猜测性输出。每消除一处报错都要重新生成一次才知道下一处；本文把
这套循环称为逐处重跑。kotlin 与 rust 的生成命令退出码为 0，不在表内；swift、
ts 与 dart 三行只列出编译普查的去向。swift 行沿用 /tmp/tiqian-swiftcens
实测；ts 行 2026-09-06 在工作树 /tmp/tiqian-audit（tiqian `f2517918` 加
boring `7606ff85`，重生成日志 /tmp/audit-gen.log）实测；dart 行 2026-09-06
在工作树 /tmp/tiqian-dartic（tiqian `17a646da` 加 boring `31627b5c`，普查
日志 /tmp/dartic-census-gen.log 与 /tmp/dartic-census-tests.log）实测。

| 目标 | 第一处报错的文本 | tiqian 触发点 | 处置 |
|---|---|---|---|
| TypeScript | 重生成退出码为 0（boring `47d6cea` 修复 std/Type.hx extern 错误类、`f270c670` 修复 UStringException 值引用后达成）；tsc 首次编译普查见第 7 节 | — | 修复项见第 11 节 F3e、T-ts |
| Swift | 重生成退出码为 0（boring `2c9257d` 修复异常超类报错后达成）；swiftc 首次编译普查见第 5 节 | — | 浮点字面量渲染、字符串控制字符转义；修复项 F3f、F3g |
| Dart | 重生成退出码为 0（boring `189e01ad` 修复静态成员顶层重名后达成，原 F0l）；dart analyze 首次编译普查见第 8 节 | — | 修复项见第 11 节 F3h、F3i、T-dart |

已越过并完成修复的阻断（保留索引）：dart 变体 switch 语句位（boring
`4e2b441`）、swift 与 dart 的 Math.pow 调用点（boring `fc0d577`）、实例字段
默认值构造器赋值（boring `81362c3`）、enum sorted keys 与 kotlin concat
（boring `556bf13`）、Math.abs 三目标（boring `7f2bced`，原 F0e）、整型容量
上界（boring `012ab59`，原 F0j）、表达式位块 features/43（boring `6251842`，
原 F0h）、StringBuf.toString 表达位（tiqian `0b152313`，源侧绑局部）、
rust 目录的 Std.string 参数域（随裁定二 A 解除：`ParagraphLayoutPrep` 移除
`@:dataClass`、`ProgressiveBreakTier` 改为真枚举，tiqian `04777e8b` 合并后
六个生成命令实测，rust 退出码为 0，原 F0k）、dart 变体 switch 条件臂位置
（boring `01e59c2e`，合并 `18b316a8`；本节旧表的 PunctuationModel.hx:264
条目由此解除）、ts 的 std/Type.hx extern 错误类（boring `47d6cea`，合并
`a0b7416e`，原 F0i）、ts 的 UStringException 值引用（boring `f270c670`，
合并 `de11c06a`，ts 生成命令自此退出码为 0）。ts 与 swift 的变体 switch
赋值位（原 F0g）在 r4 实测中两个目标都已越过；完成该规则的提交号已核对：
ts 为 boring `73c076d8`，swift 为 boring `ab1d7882`，同一缺陷的样本为
boring `2b0189c9`（2026-09-06 用 git merge-base --is-ancestor 验证三者都在
main）。

## 5 Swift 首次编译普查（2026-09-06）

基线为 boring `185cf02`、tiqian `3240f50a`。重生成命令退出码为 0，输出目录含 283 个 `.swift` 文件；使用 boring devshell 的 `swiftc -typecheck` 退出码为 123（xargs 聚合码），`/tmp/swiftc-census.log` 中含 8 条 `: error:`。

| 错误消息类（骨架） | 条数 | 代表样本文件:行 | 一句成因假设 |
|---|---:|---|---|
| expected member name following `.` | 7 | `org/tiqian/layout/PunctuationGeometryStage.swift:139` | Haxe 浮点字面量 `0.` 未被 Swift 渲染为有效浮点字面量 |
| unprintable ASCII character found in source file | 1 | `org/tiqian/test/ShapingEvidenceJson.swift:445` | Haxe 字符串转义 `\\b` 被生成成源文件中的控制字符 |
| 合计（求和校验） | 8 | 与 `/tmp/swiftc-census.log` 相等 | |

逐类定位：

- `expected member name following '.'`：生成位置为 `PunctuationGeometryStage.swift:139, 203, 255, 277, 409, 492, 493`；对应 Haxe 源 `engine-haxe/src/org/tiqian/layout/PunctuationGeometryStage.hx` 的 `pairWidth`、`runWidth`、`characterPen`、`totalAdvance`、`added`、`lead`、`trail` 初始化表达式（分别为 135、205、255、278、403、约 492、493 行）。可判定为已知的浮点字面量渲染错误类。
- `unprintable ASCII character found in source file`：生成位置为 `ShapingEvidenceJson.swift:445`；对应 Haxe 源 `engine-haxe/src/org/tiqian/test/ShapingEvidenceJson.hx` 的 `e == "b"` 分支（约 478 行）调用 `buf.addChar(8)` 的表达式。可判定为字符串控制字符转义错误类。

swift 错误逐行原文保存在 `/tmp/swiftc-census.log`；该节不修改 boring 或生成器。

## 6 rust 首次编译普查（2026-09-06）

首测基线与第 3.1 节相同（tiqian `105dfb30` 加 boring `4b1fec9`，工作树
/tmp/tiqian-census4，日志 /tmp/census-r4-rust.log，逐类表
/tmp/census-r4-rust-families.txt），报 181 条错误。2026-09-06 在 boring
main `75b08ed2`（tiqian 仍为 `105dfb30`，工作树 /tmp/tiqian-rustcens2，
日志 /tmp/rustcens2-short.log，逐类表 /tmp/rustcens2-families.txt）复测：
生成命令退出码为 0（403 个 .rs 文件），`cargo check --message-format=short`
退出码 101，报 180 条错误；与首测的唯一差异是 expected identifier, found
keyword 类从 11 条降为 10 条（`type` 从 6 处降为 5 处）。下表数字为复测值，
按 15 个消息骨架分类，求和校验相等。这 180 条全部在语法层（rustc 还没有
开始类型检查），第 3 节 Kotlin 侧的语义层错误类（可空形状、数值转换等）
在 rust 侧尚未进入测量。

| 错误消息类（骨架） | 计数 | 判定与处置 |
|---|---:|---|
| float literals must have an integer part | 124 | 修复面＝rust 浮点字面量生成规则：写成 `.25` 形，rust 语法要求 `0.25`（justifier_test.rs:311 实测样本）；生成函数定位随修复立项 |
| expected identifier, found keyword `X`（尾段重复消息） | 10 | 修复面＝rust 保留字标识符转义缺失：字段名 `type` 5 处、`match` 5 处原样输出（quote_pair_analyzer.rs:116 实测结构字段 `type:`；首测 4b1fec9 时 `type` 为 6 处） |
| expected one of `X`, `X`…, or an operator, found `X`（8 词消息） | 10 | 未判定；match 臂体生成在语句位（layout_queries.rs:379 实测 `=> let faces = …`）；随探针 |
| expected expression, found `X` | 10 | 未判定；记号分布 `.` 6、`+` 2、`)` 1、`=` 1；随探针 |
| expected pattern, found `X` | 7 | 未判定；记号分布 `=` 6、`:` 1；随探针 |
| `X` has been removed（box 语法位） | 4 | 未判定；box 记号位于 layout_queries_residual_coverage_test.rs:734 一带；随探针 |
| expected identifier, found `X` | 4 | 未判定；记号分布 `=` 2、`;` 2；随探针 |
| [E] the name `X` is defined multiple times（INSTANCE 四处） | 4 | 未判定；`pub static INSTANCE` 在同一文件四个类各一份（rich_text_role.rs:36、62、120、146）；rust 单文件多类布局与静态名冲突，机制随探针 |
| recursion limit reached while expanding `X`（format! 链） | 1 | 未判定；inline_object_decision_info.rs:78 超长 format! 链；随探针 |
| expected one of `X`, `X`…, or an operator, found `X`（unexpected token 尾） | 1 | 未判定；记号 `i`；随探针 |
| expected one of `X`, `X`…, or an operator, found `X`（消息两段重复形） | 1 | 未判定；layout_debug_assembly.rs:176；随探针 |
| expected identifier, found reserved keyword `X` | 1 | 修复面＝保留字转义缺失（同 keyword 行）：字段名 `virtual`（justifier.rs:140 实测） |
| expected expression, found reserved keyword `X` | 1 | 修复面＝保留字转义缺失（同 keyword 行）：`virtual`（justifier.rs:145） |
| [E] file not found for module `X` | 1 | 未判定；runtime/mod.rs:4 声明 `pub mod u_string;` 但无对应文件；随探针 |
| comparison operators cannot be chained | 1 | 未判定；punctuation_geometry_ledger.rs:293；随探针 |
| 合计（求和校验） | 180 | 与错误总数相等 |

判定进度小结：已判定 2 个修复面（浮点字面量生成 124 条；保留字标识符转义
缺失 12 条，跨上表 3 行），未判定 13 类共 44 条。两个修复面的修复项在
F4c 判定探针补齐生成函数定位后开列；派发顺序遵循目标优先级裁定
（kotlin、rust、dart、ts、swift）。

## 7 TypeScript 首次编译普查（2026-09-06）

基线为 boring `7606ff85`、tiqian `f2517918`（工作树 /tmp/tiqian-audit，
重生成日志 /tmp/audit-gen.log，编译普查日志 /tmp/audit-tsc.log，逐类表
/tmp/audit-tsc-families.txt，类内分解 /tmp/audit-tsc-subfamilies.txt，产出
命令见第 2.2 节）。重生成退出码为 0，是 ts 目标对 tiqian 源的首次全量
生成；tsc 5.9.3 报 1127 条错误，按下表 19 个消息骨架分类，求和校验相等。
其中测量环境条目合计 308 条：TS2307 的 bun:test 与 @tiqian 三个模块名
295 条（tsc 未配置 bun 类型）、TS2304 的 TestCore 8 条（测试支撑名字，
由运行环境提供）、TS2580 的 process 3 条与 TS2307 的 node:fs、node:path
2 条（tsc 未配置 node 类型）；引擎侧错误为 1127 减 308 等于 819 条。

| 错误码：错误消息类（骨架） | 计数 | 判定与处置 |
|---|---:|---|
| TS2307：Cannot find module 'X' or its corresponding type declarations. | 303 | 模块分布见 7.2；295 条为测量环境；其余 8 条中相对路径 5 条与 haxe/Exception 1 条是引擎侧导入路径问题，未判定，node:path 与 node:fs 2 条为测量环境；随 T-ts |
| TS2448：Block-scoped variable 'X' used before its declaration. | 215 | 假设：ts 顶层声明生成顺序未按依赖排序（LayoutDumpFormat.ts 单文件 214 条、ShapingEvidenceJson.ts 1 条，分布见 7.2）；待探针 |
| TS2304：Cannot find name 'X'. | 183 | 名称分布见 7.2（22 个名字全列）；Ic 103 条与 TS2693 同一原因的假设（Ic 声明只生成类型，未生成值侧声明）；compare 前缀 6 条与 TS2724、TS2305 的比较器未导出假设同源；其余未判定；随 T-ts |
| TS2554：Expected N arguments, but got N. | 133 | 未判定；与区间形 54 条疑为同一原因：可选参数与默认参数的调用实参数生成；随 T-ts |
| TS2345：Argument of type 'X' is not assignable to parameter of type 'X'. | 87 | 假设：枚举载荷的对象字面量不能赋给声明的枚举类型（tsc 按类型名匹配，字面量没有该名字；KinsokuLevelTest.test.ts:113 实测样本 {kind: string; hangBelowEm: number; …} 对 KinsokuMode）；与 TS2322、TS2420 疑为同一原因；待探针 |
| TS2554：Expected N-N arguments, but got N. | 54 | 未判定；与上一行疑为同一原因（CoreBoundaryTest.test.ts:139 实测样本 Expected 24-30 arguments, but got 12）；随 T-ts |
| TS2724：'X' has no exported member named 'X'. Did you mean 'X'? | 35 | 名称分布见 7.2（35 个比较器名全列）；假设：有序表键比较函数（名字以 compare 开头）未从声明模块导出；与 TS2305、TS2304 的 compare 前缀 6 条疑为同一原因；待探针 |
| TS2551：Property 'X' does not exist on type 'X'. Did you mean 'X'? | 28 | 修复面＝ts 目标 getter-only 属性调用点：28 条全部是 get_strategyName（建议列给 strategyName，分布见 7.2）；判定来源＝boring docs/specs/features/27-class-members-and-records.md 规则 5 与 dart、kotlin、swift、rust 四目标已合并实现（boring `5628b4d`）；修复项 F3e |
| TS2451：Cannot redeclare block-scoped variable 'X'. | 23 | 名称分布见 7.2（7 个名字全列）；假设：跨文件顶层绑定同名且无 import 隔离（PreparedParagraphJfTest.test.ts:101 实测样本 _g）；与 dart 的 F0l 都是顶层重名，机制位置不同，不并项；待探针 |
| TS2341：Property 'X' is private and only accessible within class 'X'. | 14 | 名称与类分布见 7.2（10 对全列）；get_ 前缀 10 条属修复面＝ts 目标 getter-only 属性调用点（F3e）；其余 4 条未判定；随 T-ts |
| TS2339：Property 'X' does not exist on type 'X'. | 14 | 名称分布见 7.2（kind 6、copy 6、push 1、insert 1）；未判定；随 T-ts |
| TS2322：Type 'X' is not assignable to type 'X'. | 8 | 假设：同 TS2345 的枚举载荷字面量原因（LineOptimizationCoverageTest.test.ts:26 实测样本 {kind: string; penalty: number; …} 对 RepairOption）；待探针 |
| TS2305：Module 'X' has no exported member 'X'. | 7 | 模块与名称分布见 7.2（6 对全列）；有序表键比较函数未导出假设（同 TS2724）；待探针 |
| TS2420：Class 'X' incorrectly implements interface 'X'. | 6 | 假设：同 TS2345 的原因（LineBreaker.ts:22 的 GreedyLineBreaker 实测样本）；待探针 |
| TS2367：This comparison appears to be unintentional because the types 'X' and 'X' have no overlap. | 6 | 假设：枚举跨构造器相等比较的降级缺陷（Haxe 允许比较不同构造器并返回 false；PushInLineWideCapacityTestSupport.ts:30 实测样本 'Hang' 对 'LeaveRagged'）；待探针 |
| TS2693：'X' only refers to a type, but is being used as a value here. | 3 | Ic 值位使用（ParagraphStyle.ts:24 实测样本）；与 TS2304 的 Ic 103 条同一原因的假设；待探针 |
| TS2869：Right operand of ?? is unreachable because the left operand is never nullish. | 3 | 未判定；左操作数已被判为非空时仍生成 null 合并运算 ??（LineRepair.ts:456 实测样本）；随 T-ts |
| TS2580：Cannot find name 'X'. Do you need to install type definitions for node? | 3 | 测量环境（process 引用，tsc 未配置 node 类型）；不派修复 |
| TS2540：Cannot assign to 'X' because it is a read-only property. | 2 | 未判定；TestTraceStore.ts:53 与 :58 的 lines 字段只读属性赋值的生成；随 T-ts |
| 合计（求和校验） | 1127 | 与错误总数相等 |

判定进度小结：修复面已判定覆盖 1 个整类（TS2551，28 条）加 TS2341 类内
get_ 前缀的 10 条，合计 38 条对准修复项 F3e；测量环境 2 处（TS2307 的三个
模块名、TS2580 全类）；其余 16 类未判定或仅有假设，假设与类内条目的对应
见上表判定列，全部随 T-ts 探针。

### 7.2 大类内部分解（2026-09-06 实测，产出命令见第 2.2 节）

TS2307 的模块分布（求和 303）：

| 计数 | 模块名 | 判定 |
|---:|---|---|
| 108 | bun:test | 测量环境（测试运行器导入，tsc 未配置 bun 类型） |
| 108 | @tiqian/runtime/test | 测量环境（同上） |
| 79 | @tiqian/runtime | 测量环境（同上） |
| 3 | ./../../../runtime/SortedTable.ts | 未判定；相对路径导入 |
| 1 | ../../../../ts-gen/runtime/SortedTable.ts | 未判定；跨目录相对路径导入 |
| 1 | ../../../../ts-gen/org/tiqian/linebreak/LiangHyphenatorTest.ts | 未判定；测试树跨目录导入 |
| 1 | ./../../../../haxe/Exception.ts | 未判定；std 模块导入路径 |
| 1 | node:path | 测量环境（tsc 未配置 node 类型） |
| 1 | node:fs | 测量环境（同上） |

TS2304 的名称分布（求和 183）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 103 | Ic | 与 TS2693 同一原因的假设：Ic 声明只生成类型，未生成值侧声明 |
| 33 | kind | 未判定 |
| 8 | TestCore | 测量环境（测试支撑名字，由运行环境提供） |
| 5 | region | 未判定 |
| 4 | pi | 未判定 |
| 4 | bi | 未判定 |
| 3 | text | 未判定 |
| 3 | __functional_shim | 未判定 |
| 2 | SortedMap | 未判定 |
| 2 | org | 未判定 |
| 2 | NodeFileSystem | 未判定 |
| 2 | count26 | 未判定 |
| 2 | count25 | 未判定 |
| 2 | count11 | 未判定 |
| 1 | count | 未判定 |
| 1 | cornerRadius | 未判定 |
| 1 | compareShapingEvidenceKey | 有序表键比较函数未导出假设（同 TS2724） |
| 1 | compareRecordedShapingResult | 有序表键比较函数未导出假设（同 TS2724） |
| 1 | compareRecordedFontMetrics | 有序表键比较函数未导出假设（同 TS2724） |
| 1 | compareMetricsEvidenceKey | 有序表键比较函数未导出假设（同 TS2724） |
| 1 | compareGlue | 有序表键比较函数未导出假设（同 TS2724） |
| 1 | compareFontMetricsRequest | 有序表键比较函数未导出假设（同 TS2724） |

TS2448 的文件分布（求和 215）：LayoutDumpFormat.ts 214 条（行 90 至 398
间）、ShapingEvidenceJson.ts 1 条（:546）。

TS2451 的名称分布（求和 23）：index 6、_g 5、row 4、rubyIndex 2、
parseHexCode 2、inkTop 2、inkBottom 2。

TS2341 的名称与类分布（求和 14）：

| 计数 | 属性（所属类） | 判定 |
|---:|---|---|
| 5 | get_canReplayFromControlledBytes（FontBackendCapabilityReport） | 修复面＝ts getter-only 属性调用点（F3e） |
| 2 | get_isMixed（ScriptEvidence） | 同上 |
| 1 | get_strategyName（LineBreakerCoverage2TestCustomBreaker） | 同上 |
| 1 | get_strategyName（CustomBreaker） | 同上 |
| 1 | get_capabilityReport（CatalogImpl） | 同上 |
| 1 | strongScriptRole（ContextualQuoteRoleResolver） | 未判定 |
| 1 | pairByOpen（ContextualQuoteRoleResolver） | 未判定 |
| 1 | emptyHanging（LineCandidate） | 未判定 |
| 1 | codePointLengthAt（ContextualQuoteRoleResolver） | 未判定 |

TS2724 的名称分布（求和 35）：compareRawFontMetrics 2 条，其余 34 个名字
各 1 条：compareSpacingDecisionInfo、compareShapingDecisionInfo、
compareRubyLineHeightDecisionInfo、compareRubyDecisionInfo、
compareRepairCandidate、comparePunctuationWidthPolicy、
comparePunctuationDecisionInfo、compareParagraphStyle、
compareMetricDecisionInfo、compareLineSpacingDecisionInfo、
compareLineRepairDecisionInfo、compareLineRepairCandidateInfo、
compareLineLengthGridDecisionInfo、compareLineEdgeTrimDecisionInfo、
compareLineCandidate、compareLayoutFontMetrics、compareLayoutConstraints、
compareKinsokuDecisionInfo、compareJustificationDecisionInfo、
compareInlineObjectSpan、compareInlineObjectPunctuationAttachmentDecisionInfo、
compareInlineObjectLineHeightDecisionInfo、compareInlineObjectDecisionInfo、
compareInlineBoxDecisionInfo、compareFontMetricsRequest、
compareFirstLineIndentDecisionInfo、compareDecorationSegmentInfo、
compareDecorationDecisionInfo、compareClusterGeometryDecisionInfo、
compareBopomofoGlyphPlacement、compareAutoSpacePolicy、
compareAutoSpaceDecisionInfo、compareAdjustmentStylePolicy。

TS2305 的模块与名称分布（求和 7）：./TextStyle.ts 的 compareTextStyle 2
条，./Size.ts 的 compareSize、./LineBox.ts 的 compareLineBox、
./InlineBoxSpan.ts 的 compareInlineBoxSpan、./GlyphRun.ts 的
compareGlyphRun、./Cluster.ts 的 compareCluster 各 1 条。

TS2339 的名称分布（求和 14）：kind 6、copy 6、push 1、insert 1。

TS2551 的名称分布（求和 28）：get_strategyName 28 条（分布在读取
strategyName 属性的测试与支撑文件）。

## 8 Dart 首次编译普查（2026-09-06）

基线为 boring `31627b5c`（F0l 修复并入 main 的合并提交）、tiqian `17a646da`
（工作树 /tmp/tiqian-dartic，重生成退出码 0，普查日志
/tmp/dartic-census-gen.log 与 /tmp/dartic-census-tests.log，逐类表
/tmp/dartic-code-combined.txt，类内分解 /tmp/dartic-undef-name.txt 等，产出
命令见第 2.2 节）。这是 dart 目标对 tiqian 源的首次全量生成与首次编译
普查；dart analyze（SDK 3.13.0，boring 的 nix develop 提供）在 dart-gen
目录报 1748 条 ERROR、在 dart-gen-tests 目录报 1183 条 ERROR，合计 2931
条，按下表 35 个错误码分类，求和校验相等。dart 普查没有测量环境条目：
运行时与测试运行器都以产物内相对路径引用，analyzer 在生成目录自带的
pubspec.yaml 上运行，不依赖外部类型配置。

判定来源：T-dart r1 报告 /tmp/dispatch-state/tiqian-tdart-r1.report.md（基线
boring `31627b5c`，35 个错误码里抽了 33 类各 3 处，另两类已有修复面）。
本文新用一档「探针定位待因果验证」：探针引用的生成器位置经派发方在
31627b5c 检出复核确认代码存在且与抽样形状相邻，但从源构造到错误输出的
因果链还没有逐环走通；它的可信度高于形状证实、低于修复面，不单独构成
派发依据。该报告的引用有两处经复核降级：REFERENCED_BEFORE_DECLARATION
引用的 Compiler.hx:216-220 实为测试函数排序，与样本不吻合；
MISSING_DEFAULT_VALUE_FOR_PARAMETER 引用的 DartDecl.hx:260-300 落在比较
函数合成代码内，拟合存疑。因果链闭合的两类开列为修复项 F3l 与 F3m。

| 错误码 | gen | tests | 合计 | 判定与处置 |
|---|---:|---:|---:|---|
| `UNDEFINED_IDENTIFIER` | 444 | 581 | 1025 | 名称分布见 8.2（79 个名字全列）；类内 8 个类型名条目合计 705 条（WritingMode 157、LastLineAlignment 155、InlineAttachment 147、Ic 106、RubyLineHeightMode 77、RubyKind 35、LineEndReason 16、FontRole 12）已判修复面＝类型名与枚举名值位引用缺导入前缀（adjustment_style_policy.dart:14 值位不带前缀直接使用 `LineEndPunctuationStyle` 实测，同文件类型位用带前缀形；机制位置 DartExpr.hx:1466-1485 的枚举引用分支与 DartImports.hx:186-215 的前缀登记，派发方在 31627b5c 复核）；F3l；其余名字未判定 |
| `UNCHECKED_USE_OF_NULLABLE_VALUE` | 231 | 189 | 420 | 修复面＝dart 可空接收者守卫缺失（clreq_punctuation_advance_policy.dart:27 的 int? 接收者直接比较实测；机制位置 DartExpr.hx:1315-1341 的 binop 守卫，派发方在 31627b5c 复核；与 kotlin 修复面 A 同构造）；形状分布见 8.2；F3m |
| `REFERENCED_BEFORE_DECLARATION` | 314 | 96 | 410 | 形状证实：抽样含导入前缀与局部名同名冲突（cluster_role_resolution.dart:55 生成 `final cluster = cluster.Cluster(...)`）与不带前缀的类名（:64 的 `ResolvedClusterRange`）两形；探针引用的 Compiler.hx:216-220 经派发方复核是测试函数排序，与样本不吻合，已否证；layout_dump_format.dart 215 条与 ts TS2448 同源的假设保留；文件分布见 8.2；机制位置待定位；随 T-dart 第二轮 |
| `ARGUMENT_TYPE_NOT_ASSIGNABLE` | 176 | 123 | 299 | 假设：T-dart 抽样为可空 int? 给 int（codeUnitAt 闭包位），连可空守卫（F3m 同构造）；目标类型分布里 double 74 条是否数值转换待抽样；分布见 8.2（23 种全列）；随 T-dart 第二轮 |
| `NOT_ENOUGH_POSITIONAL_ARGUMENTS` | 71 | 34 | 105 | 探针定位待因果验证：生成调用发零参而 Haxe 源构造有参（样本 PunctuationAtomBuilder.new 实参 0 个）；机制位置 DartExpr.hx:2550-2563 的 constructorArgTexts，派发方在 31627b5c 复核存在；与 ts TS2554 同源的假设保留；随 T-dart 第二轮 |
| `PREFIX_SHADOWED_BY_LOCAL_DECLARATION` | 32 | 42 | 74 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_METHOD` | 53 | 11 | 64 | 形状证实（T-dart r1 抽样读过生成代码）；接收类型为 List 的 23 条保持 Haxe 数组方法名生成到 dart 的 List 接收者的假设；方法与接收类型分布见 8.2（23 对全列）；机制位置待定位；随 T-dart 第二轮 |
| `EXPECTED_TOKEN` | 56 | 0 | 56 | 形状证实：非法 `int??` 双问号类型渲染（cjk_font_role_classifier.dart:23-24 生成 `final int?? l` 实测）；与 MISSING_ASSIGNABLE_SELECTOR、ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE、MISSING_IDENTIFIER、DOT_SHORTHAND_MISSING_CONTEXT 四码共享同一形状，五码文件分布重叠；期待符号分布：缺分号 49、缺右括号 4、缺冒号 2、缺右花括号 1；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_FUNCTION` | 55 | 0 | 55 | 探针定位待因果验证：有序表键比较函数被调用但未在目标库生成（clreq_profile.dart:79-83 调用 compareAutoSpacePolicy 等实测）；机制位置 DartDecl.hx:221-333 的数据类比较函数合成只在数据类路径，派发方在 31627b5c 复核存在；与 ts TS2724 同源假设保留；名称分布见 8.2（42 个名字全列）；随 T-dart 第二轮 |
| `MISSING_ASSIGNABLE_SELECTOR` | 49 | 0 | 49 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；机制位置待定位；随 T-dart 第二轮 |
| `ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE` | 49 | 0 | 49 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_PREFIXED_NAME` | 20 | 22 | 42 | 探针定位待因果验证：前缀引用的名字不在目标库（clreq_profile.dart:35 经前缀引用 PunctuationGluePlacements 实测）；机制位置 DartImports.hx:186-215 的前缀登记只按模块名记录，派发方在 31627b5c 复核存在；随 T-dart 第二轮 |
| `URI_DOES_NOT_EXIST` | 25 | 11 | 36 | 已判定：运行时文件、std 影子文件与 test_host.dart 未随消费方配置写出，路径明细见 8.2；修复项 F3i |
| `READ_POTENTIALLY_UNASSIGNED_FINAL` | 36 | 0 | 36 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `MISSING_IDENTIFIER` | 34 | 1 | 35 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_GETTER` | 1 | 31 | 32 | 已判定：32 条全部为 The getter 'strategyName' isn't defined for the type 'LineBreaker'（gen 1 条、tests 31 条）；修复项 F3h |
| `INVOCATION_OF_NON_FUNCTION_EXPRESSION` | 0 | 31 | 31 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `DOT_SHORTHAND_MISSING_CONTEXT` | 27 | 0 | 27 | 形状证实：非法 `??` 双问号类型渲染（annotation_geometry_stage.dart:165 生成 `ClusterGeometryDecisionInfo?? g` 实测；与 EXPECTED_TOKEN 共享形状）；机制位置待定位；随 T-dart 第二轮 |
| `DUPLICATE_DEFINITION` | 17 | 1 | 18 | 探针定位待因果验证：同库内重复名字（ic.dart:5 的 count、layout_queries.dart:641 与 :671 的 rubyIndex 实测）；机制位置 DartDecl.hx:39-40 的顶层名登记与 :625-626，派发方在 31627b5c 复核存在；与 ts TS2451 顶层重名的机制位置关系待证；随 T-dart 第二轮 |
| `PREFIX_COLLIDES_WITH_TOP_LEVEL_MEMBER` | 5 | 6 | 11 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `MISSING_DEFAULT_VALUE_FOR_PARAMETER` | 11 | 0 | 11 | 形状证实：非空参数的隐式默认值为 null（ClreqProfile 可选参数实测）；探针引用的 DartDecl.hx:260-300 经派发方复核落在比较函数合成代码内，与参数签名不吻合，定位存疑；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_ENUM_CONSTANT` | 8 | 0 | 8 | 形状证实：枚举构造器名空串或保留字（unicode_punctuation_boundary_resolver.dart:208-219 生成 `Dir.final` 实测，final 是 dart 保留字）；机制位置待定位；随 T-dart 第二轮 |
| `INVALID_ASSIGNMENT` | 7 | 0 | 7 | 形状证实：dart 侧赋值位没有 int 到 double 的转换（line_adjustment_stage.dart:148、:151、:159 生成 `visualWidth = (visualWidth).round()` 实测，与 kotlin F3j 的赋值位同构造）；机制位置待定位；随 T-dart 第二轮 |
| `NON_ABSTRACT_CLASS_INHERITS_ABSTRACT_MEMBER` | 4 | 2 | 6 | 探针定位待因果验证：实现类缺接口成员实现（line_breaker.dart:19 的 GreedyLineBreaker 缺 get_strategyName 实测，与 F3h 的接口侧缺陷同构造，F3h 修复后可能随之消除）；机制位置 DartDecl.hx:77-85 的接口转抽象类与 :161-174 的实现类路径，派发方在 31627b5c 复核存在；随 T-dart 第二轮 |
| `RETURN_OF_INVALID_TYPE` | 4 | 0 | 4 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `NOT_INITIALIZED_NON_NULLABLE_INSTANCE_FIELD` | 4 | 0 | 4 | 探针定位待因果验证：非空实例字段在构造器外初始化（line_breaker.dart:28 的 _kinsoku 等实测）；机制位置 DartDecl.hx:598-621 的字段默认值路径，派发方在 31627b5c 复核存在；随 T-dart 第二轮 |
| `NON_EXHAUSTIVE_SWITCH_STATEMENT` | 4 | 0 | 4 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_OPERATOR` | 3 | 0 | 3 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `IMPLICIT_THIS_REFERENCE_IN_INITIALIZER` | 3 | 0 | 3 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `LIST_ELEMENT_TYPE_NOT_ASSIGNABLE` | 0 | 2 | 2 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `RETURN_OF_INVALID_TYPE_FROM_CLOSURE` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `NON_TYPE_AS_TYPE_ARGUMENT` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `INSTANCE_MEMBER_ACCESS_FROM_STATIC` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `EXTRA_POSITIONAL_ARGUMENTS` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `CONFLICTING_METHOD_AND_FIELD` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| 合计（求和校验） | 1748 | 1183 | 2931 | 与错误总数相等 |

判定进度小结（2026-09-06 T-dart r1 抽样并入后）：修复面 3 个整类加 1 个
类内部条目：UNCHECKED_USE_OF_NULLABLE_VALUE 全类 420 条（F3m）、
UNDEFINED_GETTER 32 条（F3h）、URI_DOES_NOT_EXIST 36 条（F3i）、
UNDEFINED_IDENTIFIER 类内 8 个类型名条目 705 条（F3l）；探针定位待因果
验证 6 类（NOT_ENOUGH_POSITIONAL_ARGUMENTS、UNDEFINED_FUNCTION、
UNDEFINED_PREFIXED_NAME、DUPLICATE_DEFINITION、
NON_ABSTRACT_CLASS_INHERITS_ABSTRACT_MEMBER、
NOT_INITIALIZED_NON_NULLABLE_INSTANCE_FIELD）；其余 25 类为形状证实或
假设，其中 EXPECTED_TOKEN、MISSING_ASSIGNABLE_SELECTOR、
ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE、MISSING_IDENTIFIER、
DOT_SHORTHAND_MISSING_CONTEXT 五码合计 216 条共享非法 `??` 双问号类型
渲染形状，是形状证实里计数最大的一组错误码。T-dart 第二轮的剩余工作＝给 6 类
探针定位待因果验证补齐因果链、给形状证实类定位机制位置、证实或否证跨
目标假设（ARGUMENT_TYPE_NOT_ASSIGNABLE 的 double 74 条是否数值转换也在
其列）。

### 8.2 大类与中类内部分解（2026-09-06 实测，产出命令见第 2.2 节）

UNDEFINED_IDENTIFIER 的名称分布（求和 1025；判定列写 F3l 的名字在 tiqian
源内实测为 enum 或 abstract 声明的类型名）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 157 | `WritingMode` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 155 | `LastLineAlignment` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 147 | `InlineAttachment` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 106 | `Ic` | 修复面＝类型名值位引用缺导入前缀（F3l）；与 ts TS2304 的 Ic 103 条同一原因的假设保留 |
| 77 | `RubyLineHeightMode` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 35 | `RubyKind` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 33 | `kind` | 未判定 |
| 16 | `LineEndReason` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 15 | `PunctuationGeometryStageCoverageSupport` | 未判定 |
| 13 | `JustifierTestSupport` | 未判定 |
| 12 | `plan` | 未判定 |
| 12 | `FontRole` | 修复面＝类型名值位引用缺导入前缀（F3l） |
| 12 | `FontMetricSource` | 未判定 |
| 11 | `ink` | 未判定 |
| 11 | `cls` | 未判定 |
| 10 | `item` | 未判定 |
| 9 | `x` | 未判定 |
| 8 | `previousBudget` | 未判定 |
| 8 | `nextBudget` | 未判定 |
| 8 | `g` | 未判定 |
| 6 | `r` | 未判定 |
| 6 | `n` | 未判定 |
| 5 | `prev` | 未判定 |
| 5 | `nextChar` | 未判定 |
| 5 | `mandatory` | 未判定 |
| 5 | `InteriorPunctuationStyle` | 未判定 |
| 5 | `halt` | 未判定 |
| 5 | `CjkPunctuationGlyphPolicy` | 未判定（T-dart 抽样里有值位不带前缀直接使用的形状，源侧声明核实随第二轮） |
| 4 | `shaped` | 未判定 |
| 4 | `selectedTechnicalBreak` | 未判定 |
| 4 | `previousSpacing` | 未判定 |
| 4 | `preferredTrackingSpan` | 未判定 |
| 4 | `pi` | 未判定 |
| 4 | `pairs` | 未判定 |
| 4 | `nextSpacing` | 未判定 |
| 4 | `io` | 未判定 |
| 4 | `cp` | 未判定 |
| 4 | `candidate` | 未判定 |
| 4 | `bi` | 未判定 |
| 4 | `AutoSpaceMode` | T-dart 抽样同形状（auto_space_policy.dart:14 值位不带前缀直接使用 `AutoSpaceMode.insert` 实测）；源侧声明核实与并入 F3l 随第二轮 |
| 3 | `text` | 未判定 |
| 3 | `strongReason` | 未判定 |
| 3 | `startPrior` | 未判定 |
| 3 | `role` | 未判定 |
| 3 | `prevKind` | 未判定 |
| 3 | `naturalPrior` | 未判定 |
| 3 | `LineEndPunctuationStyle` | T-dart 抽样同形状（adjustment_style_policy.dart:14 值位不带前缀直接使用实测）；源侧声明核实与并入 F3l 随第二轮 |
| 3 | `KinsokuLevel` | 未判定 |
| 3 | `fromRepair` | 未判定 |
| 3 | `firstHanging` | 未判定 |
| 3 | `endPrior` | 未判定 |
| 3 | `boundKind` | 未判定 |
| 2 | `twoPowers` | 未判定 |
| 2 | `repairStr` | 未判定 |
| 2 | `repairName` | 未判定 |
| 2 | `repairedCurrent` | 未判定 |
| 2 | `repairDecision` | 未判定 |
| 2 | `region` | 未判定 |
| 2 | `rd` | 未判定 |
| 2 | `org` | 未判定 |
| 2 | `maxLinesDecision` | 未判定 |
| 2 | `last` | 未判定 |
| 2 | `l` | 未判定 |
| 2 | `issue` | 未判定 |
| 2 | `iod` | 未判定 |
| 2 | `inkWidth` | 未判定 |
| 2 | `HangingPunctuationStyle` | 未判定 |
| 2 | `fivePowers` | 未判定 |
| 2 | `center` | 未判定 |
| 1 | `twoPowersBuilder` | 未判定 |
| 1 | `ShrinkChannel` | 未判定 |
| 1 | `RichTextBackgroundMetricPolicy` | 未判定 |
| 1 | `MetricBox` | 未判定 |
| 1 | `LineAdjustmentStrategy` | T-dart 抽样同形状（adjustment_style_policy.dart:17 值位不带前缀直接使用 `LineAdjustmentStrategy.pushInFirst` 实测）；源侧声明核实与并入 F3l 随第二轮 |
| 1 | `InlineBoxOuterSpacing` | 未判定 |
| 1 | `fivePowersBuilder` | 未判定 |
| 1 | `enUsCache` | 未判定 |
| 1 | `count` | 未判定 |
| 1 | `BaselineClass` | 未判定 |

UNCHECKED_USE_OF_NULLABLE_VALUE 的形状分布（求和 420；消息里的名字以 X
代替；全类已判修复面＝dart 可空接收者守卫缺失，F3m）：

| 计数 | 形状 | 判定 |
|---:|---|---|
| 314 | The property 'X' can't be unconditionally accessed because the receiver can be 'null'. | 修复面＝dart 可空接收者守卫缺失（F3m；与 kotlin 修复面 A 同构造） |
| 82 | The method 'X' can't be unconditionally invoked because the receiver can be 'null'. | 同上 |
| 18 | The operator 'X' can't be unconditionally invoked because the receiver can be 'null'. | 同上 |
| 6 | A nullable expression can't be used as a condition. | 同上 |

REFERENCED_BEFORE_DECLARATION 的文件分布（求和 410）：

| 计数 | 文件 | 判定 |
|---:|---|---|
| 215 | `layout_dump_format.dart` | 与 ts TS2448 的 LayoutDumpFormat.ts 214 条同一原因的假设（同一源文件的两个目标侧产物，顶层声明顺序未按依赖排序） |
| 78 | `justifier_jf_test.dart` | 未判定 |
| 64 | `justifier_coverage_test.dart` | 未判定 |
| 23 | `punctuation_geometry_stage_coverage_test.dart` | 未判定 |
| 6 | `layout_queries_test.dart` | 未判定 |
| 5 | `line_repair.dart` | 未判定 |
| 4 | `paragraph_shaping_stage.dart` | 未判定 |
| 3 | `cluster_role_resolution.dart` | 未判定 |
| 2 | `punctuation_model.dart` | 未判定 |
| 2 | `justifier_compression_test.dart` | 未判定 |
| 1 | `width_independent_annotation_cache_coverage_test_support.dart` | 未判定 |
| 1 | `unicode_emoji17_rgi_role_audit_test_support.dart` | 未判定 |
| 1 | `text_shaper.dart` | 未判定 |
| 1 | `shaping_evidence_json.dart` | 未判定 |
| 1 | `shaping_evidence.dart` | 未判定 |
| 1 | `punctuation_geometry_stage.dart` | 未判定 |
| 1 | `line_optimization_coverage_test.dart` | 未判定 |
| 1 | `annotation_geometry_stage_coverage_test_support.dart` | 未判定 |

ARGUMENT_TYPE_NOT_ASSIGNABLE 的目标类型分布（求和 299；消息形如 The
argument type 'X' can't be assigned to the parameter type 'Y'，本表按 Y
计；T-dart 抽样为可空 int? 给 int，连可空守卫 F3m；double 74 条是否数值
转换待第二轮抽样）：

| 计数 | 目标类型 | 判定 |
|---:|---|---|
| 74 | `double` | 未判定 |
| 70 | `List<Cluster>` | 未判定 |
| 40 | `List<EastAsianSpacingEdges>` | 未判定 |
| 37 | `int` | 未判定 |
| 24 | `String` | 未判定 |
| 18 | `num` | 未判定 |
| 8 | `List<String>?` | 未判定 |
| 6 | `Cluster` | 未判定 |
| 5 | `SortedSetTable<int>` | 未判定 |
| 3 | `SortedMapTable<String, double>` | 未判定 |
| 2 | `KinsokuLevel` | 未判定 |
| 1 | `UnbreakableRanges` | 未判定 |
| 1 | `SortedMapTable<TextRange, SortedSetTable<int>>` | 未判定 |
| 1 | `SortedMapTable<TextRange, ClusterMetricDecision>` | 未判定 |
| 1 | `SortedMapTable<String, String>` | 未判定 |
| 1 | `SortedMapTable<int, ProgressiveBreakOpportunity>` | 未判定 |
| 1 | `SortedMapTable<int, InlineObjectSpan>` | 未判定 |
| 1 | `SortedMapTable<int, InlineObjectPreferredStretch>` | 未判定 |
| 1 | `List<ShrinkOpportunity>` | 未判定 |
| 1 | `List<int>` | 未判定 |
| 1 | `List<Glyph>` | 未判定 |
| 1 | `Iterable<int>` | 未判定 |
| 1 | `HangingPunctuationStyle` | 未判定 |

UNDEFINED_METHOD 的方法与接收类型分布（求和 64，记法为方法 @ 接收类型）：

| 计数 | 方法与接收类型 | 判定 |
|---:|---|---|
| 13 | `Cluster` @ `Function` | 未判定 |
| 10 | `emptyF` @ `PunctuationGeometryLedger` | 未判定 |
| 6 | `copy` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 5 | `concat` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 4 | `splice` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 4 | `pop` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 3 | `Cluster` @ `Cluster` | 未判定 |
| 2 | `shift` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 2 | `Ic` @ `Function` | 未判定 |
| 2 | `emptyHanging` @ `LineCandidate` | 未判定 |
| 1 | `unshift` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 1 | `reverse` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 1 | `Rect` @ `Rect` | 未判定 |
| 1 | `Glyph` @ `Glyph` | 未判定 |
| 1 | `compareTo` @ `RubyLineHeightDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `MaxLinesDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `LineSpacingDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `LineRepairDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `LineLengthGridDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `LineCandidate` | 未判定 |
| 1 | `compareTo` @ `KinsokuDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `InlineObjectLineHeightDecisionInfo` | 未判定 |
| 1 | `compareTo` @ `FirstLineIndentDecisionInfo` | 未判定 |

UNDEFINED_FUNCTION 的名称分布（求和 55，消息全部为 The function 'X'
isn't defined.）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 7 | `floatToI32` | 未判定（Haxe 浮点位转换函数名，tiqian 源 org/tiqian/test/TestHelpers.hx 等处使用） |
| 5 | `i32ToFloat` | 未判定（Haxe 浮点位转换函数名，tiqian 源 org/tiqian/test/TestHelpers.hx 等处使用） |
| 2 | `compareTextStyle` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 2 | `compareFontMetricsRequest` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 2 | `compareRawFontMetrics` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareAutoSpacePolicy` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareAdjustmentStylePolicy` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `comparePunctuationWidthPolicy` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareBopomofoGlyphPlacement` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareMetricDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareClusterGeometryDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareAutoSpaceDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareRubyDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareShapingDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `comparePunctuationDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareSpacingDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareJustificationDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLineEdgeTrimDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareDecorationDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareDecorationSegmentInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareInlineBoxDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareInlineObjectDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareInlineObjectPunctuationAttachmentDecisionInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareParagraphStyle` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLayoutConstraints` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareInlineBoxSpan` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareInlineObjectSpan` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareSize` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareCluster` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareGlyphRun` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLineBox` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLineRepairCandidateInfo` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLayoutFontMetrics` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareLineCandidate` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareRepairCandidate` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareGlue` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareShapingEvidenceKey` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareRecordedShapingResult` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareMetricsEvidenceKey` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `compareRecordedFontMetrics` | 有序表键比较函数未导出假设（同 ts TS2724） |
| 1 | `mkdirSync` | 未判定 |
| 1 | `writeFileSync` | 未判定 |

EXPECTED_TOKEN 的期待符号分布（求和 56）：';' 49 条、')' 4 条、':' 2 条、
'}' 1 条（全部未判定）。

URI_DOES_NOT_EXIST 的引用路径分布（求和 36；目录列 gen 指 dart-gen 内
的文件、tests 指 dart-gen-tests 内的文件；已判定 F3i）：

| 计数 | 引用路径 | 目录 |
|---:|---|---|
| 5 | `../../../std/u_string_fault.dart` | gen |
| 5 | `../../../std/u_string_exception.dart` | gen |
| 4 | `../../../../std/u_string_fault.dart` | gen |
| 4 | `../../../../std/u_string_exception.dart` | gen |
| 4 | `../../../../dart-gen/lib/std/u_string_fault.dart` | tests |
| 4 | `../../../../dart-gen/lib/std/u_string_exception.dart` | tests |
| 3 | `../../../runtime/sorted_table.dart` | gen |
| 2 | `../../../std/sorted_map.dart` | gen |
| 1 | `test_host.dart` | tests |
| 1 | `../../../std/functional.dart` | gen |
| 1 | `../../../../haxe/exception.dart` | gen |
| 1 | `../../../../dart-gen/lib/runtime/sorted_table.dart` | tests |
| 1 | `../../../../dart-gen/lib/org/tiqian/linebreak/liang_hyphenator_test.dart` | tests |

## 9 分级标尺

复杂度（C）：C1 单点修复，一个生成器分支或一处源文件，改动预计不超过一百行；
C2 跨文件或跨目标，同一缺陷出现在多个目标，或需要 tiqian 源与 boring 生成器
配合；C3 新机制，需要新增降级能力。

优先级（P）：P0 阻塞项，阻塞后续测量或行为对齐验收；P1 大错误种类或已在修复
计划内的排队项；P2 影响总数但不阻塞测量；P3 单例且暂无复现路径。

严重性（S）：S0 错误出在语法层，使整个生成目录无法编译或无法生成；S1 两百条
以上；S2 二十到一百九十九条；S3 二十条以下。流程类条目不适用 S，记为 S-。

## 10 KPI

工作量检验的方式（2026-09-06 用户裁定）：进度以各目标逐类表的行计数变化
为准，每类可单独复测；不设覆盖多类的「其余」聚合指标，聚合数只保留合计
一个完整性数字（各类求和必须等于合计）。修复项只对修复面开，不对消息类
主题开；每条修复项写明覆盖的错误类、类内条目与计数，KPI 现值写各目标
逐类表的实测计数，切分反映修复工作量，不合并修复面。

| KPI | 指标 | 现值 | 目标 | 对应 |
|---|---|---|---|---|
| K1 | 修复面 A：only safe 类计数 | f32 75 / f64 75 | 0 | #22 执行中 |
| K2 | 各目标逐类判定完成度 | kotlin 修复面 10 / 36 个 f32 类加 argument 类内 2 形状（另测量环境 1 类、形状证实 14 类、假设 10 类）；swift 2 / 2 类；rust 2 / 15 类；ts 修复面 1 / 19 类（另有 TS2341 类内 10 条）；dart 修复面 3 / 35 类加 UNDEFINED_IDENTIFIER 类内 705 条（另探针定位待因果验证 6 类） | 五目标全部类有判定结论 | T-attr、F4c、T-ts、T-dart |
| K3 | 各目标错误总数 | kotlin f32 1183 / f64 1201；rust 180（boring `75b08ed2` 复测）；swift 8；ts 1127（引擎侧 819）；dart 2931 | 全部 0 | 各节逐类表求和（完整性数字，非派发单位） |
| K4 | kotlin 两个目录 warning 计数 | 0 / 0 | 保持 0 | 每次复测 |
| K5 | 各目标重生成退出码 | kotlin 0、kotlin-f64 0、rust 0、swift 0（自 boring `2c9257d`）、ts 0（自 boring `de11c06a`）、dart 0（自 boring `31627b5c`） | 全部 0 | F0l 与逐处重跑（已完成） |
| K6 | boring 验收命令 | 全部通过（2026-09-06 合并 `f9f26726` 与 `31627b5c` 后 19 项检查退出码全部为 0；合并后 boring main 的 bun test 为 672 pass / 3 fail，三个既有名目） | 每次合并后保持 | 不适用 |
| K7 | 五目标普查覆盖 | kotlin、swift、rust、ts、dart 的逐类表已建（第 3、5、6、7、8 节） | 五目标各有逐类表 | F4b（已完成） |

## 11 修复项清单

### 第 0 组：nullargs 收尾（已完成合入，保留记录）

- [x] F0a-F0d nullargs 验收、样本修复、字段类型补齐、合入复测：随 nullargs-r4
      并入 boring `8d17b59` 完成；19 项验收检查全部通过，r3 普查 f32 1535 /
      f64 1553 记录了复测值。原四条子项（F0a 退出码 127 诊断、F0b RustExpr
      样本修复、F0c Dart 与 Rust 字段类型、F0d 合入复测）不再单列。

### 第 0.5 组：各目标的生成阻断（K5 的前置修复）

- [x] F0e 三个生成器补 `Math.abs` 生成规则：2026-09-05 并入 boring
      `7f2bced`。
- [x] F0f `Std.string` 违规调用点定位与第一轮修复：2026-09-05 完成，tiqian
      `e0e1172d` 加 `ec285e24`。
- [x] F0g 变体 switch 赋值位生成规则：r4 实测 ts 与 swift 两个目标都已越过
      该构造；提交号已核对（见 F0k-核）：ts 为 boring `73c076d8`，swift 为
      boring `ab1d7882`，同一缺陷的样本为 boring `2b0189c9`。
- [x] F0h 表达式位块 features/43 五目标生成规则：2026-09-05 并入 boring
      `6251842`。
- [x] F0j 整型容量上界生成规则：2026-09-05 并入 boring `012ab59`。
- [x] F0k rust 目录 Std.string 参数域剩余四处：随裁定二 A 解除（tiqian
      `04777e8b`，`ParagraphLayoutPrep` 移除 `@:dataClass`、
      `ProgressiveBreakTier` 改为真枚举；合并后六个生成命令实测，rust
      退出码为 0）。此前三普通类的修复见 tiqian `26d89566`。
- [x] F0i TypeScript extern 错误类：`std/Type.hx:32` 的 extern class Type 缺少
      `@:native`/`@:jsRequire`。boring `47d6cea`（fix(ts): resolve stdlib Type
      references through the enum query expander，合并 `a0b7416e`）完成。其后
      ts 逐处重跑暴露的 UStringException 值引用错误类由 boring `f270c670`
      （合并 `de11c06a`）完成，ts 生成命令自此退出码为 0。
- [x] F0i-逐处重跑 每消除一处当前第一位的报错后，重跑对应目标的生成命令并
      记录新出现的第一处报错，循环到 ts、dart 两个目标的生成命令退出码为
      0。ts 已于 boring `de11c06a` 后达成，首次编译普查见第 7 节；swift 已
      完成，逐类表见第 5 节；dart 已于 boring `189e01ad`（合并 `31627b5c`）
      后达成，首次编译普查见第 8 节。四个目标的重生成退出码均为 0，本项
      完成。C1，P1，S-。
- [x] F0k-核 变体 switch 赋值位的修复提交号核对（见 F0g 条）：ts
      `73c076d8`、swift `ab1d7882`（2026-09-06 用 git merge-base
      --is-ancestor 验证两者都在 boring main）。C1，P3，S-。
- [x] F0l dart 静态成员顶层重名：`engine-haxe/src/org/tiqian/core/Units.hx:25`
      起 FloatIc 与 IntIc 两个类各有一个静态函数 `ic`，dart 目标把类静态
      降级为库文件内的顶层名字，同名 `ic` 在 org.tiqian.core.Units 库内
      冲突（生成错误原文：top-level name ic is claimed twice in
      org.tiqian.core.Units；2026-09-06 于 boring `7606ff85` 实测）。修复
      面＝boring dart 目标静态成员的顶层命名。ts 侧 TS2451 是跨文件顶层
      重名，机制位置不同，不并项。2026-09-06 由修复任务 dartic 完成：
      boring `189e01ad` 在静态成员重名时保留类形，不再把类静态降级为
      顶层函数（生成开始前扫描整个模块，登记 statics-only 类的静态成员
      名单，重名的类走 DartDecl.hx 居民模块的既有做法），合并 `31627b5c`
      已推送；新增样本 StaticCollisionOps 与测试，一致性检查六列全 pass；
      生成文件逐字节对照实测（sha256，基线 `0a57b83e` 对修复后生成树）：
      非 dart 树只新增样本文件与测试登记行，dart 树既有文件零变化。
      C2，P0，S0。

### 第 1 组：判定探针（K2，先于其余修复任务的派发）

- [ ] T-attr 逐类判定探针：对第 3.2 节判定列为「未判定」或「假设」的每个
      错误类，按类内计数降序抽样错误点（每类 3 至 5 处），读对应生成代码，
      把错误类归到修复面（boring 生成器的机制位置，写明文件与分支；或
      tiqian 源的一类写法）。产出＝3.2 节判定列填全，每个新修复面在此开
      一条修复项（附错误类清单与计数）。方法与 #22 上半的探针相同（参照
      boring-onlysafe-probe.report.md）。抽样顺序：argument 可空形状 261、
      unresolved 336 / 329、operator call prohibited 60、cannot infer 42、
      argument 数值形状 113 / 122、return 28、cannot access 27，其余按表
      降序。r1 已于 2026-09-06 交付（报告
      /tmp/dispatch-state/tiqian-tattr-r1.report.md，34 节全量）：抽样形状
      已并入 3.2 与 3.3 节，其逐类「修复面位置」段是同一份七条引用的
      重复粘贴，不采信；数值转换面与 getter 降级可见性两处机制由派发方在
      4b1fec9 复核后开列 F3j、F3k。第二轮范围＝把 14 类形状证实定位到
      文件与分支、证实或否证 10 类假设、对 3.4 节符号逐个定位所属机制。C2，P1，S-。
- [ ] F1a 修复面 A 计数降为 0（#22）：only safe 类两个目录；执行中的
      派发任务现为第三轮（boring-onlysafe-r3，前两轮已并入），判据与
      任务书见 /tmp/dispatch-state/ 下 boring-onlysafe 各轮 brief。C2，P1，S1。
- [ ] T-ts ts 逐类判定探针：对第 7 节判定列为「未判定」或「假设」的每个
      错误类，按类内计数降序抽样错误点（每类 3 至 5 处），读对应生成代码，
      把错误类归到修复面；产出＝第 7 节判定列填全，每个新修复面在第 3 组
      开一条修复项。抽样顺序：TS2448 的 214 条、TS2304 的 Ic 103 条、
      TS2554 两形合计 187 条、TS2345 的 87 条、TS2724 的 35 条、TS2451 的
      23 条、TS2339 的 14 条、TS2341 未判定的 4 条，其余按表降序。方法与
      T-attr 相同。C2，P1，S-。
- [ ] T-dart dart 逐类判定探针：对第 8 节判定列为「未判定」或「假设」的
      每个错误类，按类内计数降序抽样错误点（每类 3 至 5 处），读对应生成
      代码，把错误类归到修复面；产出＝第 8 节判定列填全，每个新修复面在
      第 3 组开一条修复项。抽样顺序：UNDEFINED_IDENTIFIER 的 1025 条、
      UNCHECKED_USE_OF_NULLABLE_VALUE 的 420 条、REFERENCED_BEFORE_
      DECLARATION 的 410 条、ARGUMENT_TYPE_NOT_ASSIGNABLE 的 299 条、
      EXPECTED_TOKEN、MISSING_IDENTIFIER、MISSING_ASSIGNABLE_SELECTOR、
      ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE、DOT_SHORTHAND_MISSING_CONTEXT
      五码合计 216 条、NOT_ENOUGH_POSITIONAL_ARGUMENTS 的 105 条，其余按
      表降序。方法与 T-attr 相同。r1 已于 2026-09-06 交付（报告
      /tmp/dispatch-state/tiqian-tdart-r1.report.md，33 类全量）：抽样与
      生成器引用经派发方在 31627b5c 复核后并入第 8 节，F3l、F3m 随之
      开列，两处不吻合的引用已降级并记录在第 8 节判定来源段。第二轮
      范围＝给 6 类探针定位待因果验证补齐因果链、给形状证实类定位机制
      位置、证实或否证跨目标假设。C2，P1，S-。

### 第 2 组：已排定位任务

- [ ] F2b f64 独有三类错误定位（#25）：`Expecting an element` 9 条、
      `'X' must have both main and 'X' branches` 2 条、`the expression
      cannot be a selector` 1 条，共 12 条（2026-09-06 现值；旧记 13 条含
      infix 一条，该条 r4 里两目录各 1 已不独有）。先取 `Expecting an
      element` 的文件与行号，定位 f64 生成路径独有分支。C1，P0，S0。

### 第 3 组：按判定结果立项

本组条目按修复面开列：一条修复项对应一个修复面，附它覆盖的错误类与
类内条目清单、计数、判据（对应计数降为 0 且其余类计数不上升）。条目的
判定来源写明：kotlin 侧由 T-attr 产出；swift 与 ts 侧的下列三条来自各
目标首次编译普查时已可定性的错误类。2026-09-06 撤销原第 3 组 F3a（修饰符
主题）、F3b（语句位置主题）、F3c（推断与重载主题）、F3d（桶 4 可空形状）
四条按消息主题合并的条目；各错误类已在 3.2 节逐行可见，其中可空形状与
数值形状的疑议随 T-attr 判定。撤销理由：按主题把多个修复面合并成一个
任务后，进度勾选无法与任何一个错误类的计数核对。2026-09-06 T-attr r1
与 T-dart r1 的判定并入后，本组新增 F3j 至 F3m 四条：F3j、F3k 来自
kotlin 侧（机制由派发方在 boring `4b1fec9` 复核后开列），F3l、F3m 来自
dart 侧（引用由派发方在 boring `31627b5c` 复核后开列）。

- [ ] F3e ts 目标 getter-only 属性调用点：覆盖 TS2551 全类 28 条（全部
      get_strategyName）加 TS2341 的 get_ 前缀 10 条，合计 38 条。修复
      面＝ts 生成器实例成员读取与零参调用两条路径上补 getter-only 属性
      判定，参照 dart 的 DartExpr.hx:1516 与 :2267 两处及 boring `5628b4d`
      在 kotlin、swift、rust 的对应实现（boring 仓库
      docs/specs/features/27-class-members-and-records.md 规则 5）。判据＝
      TS2551 计数与 TS2341 的 get_ 前缀条目计数降为 0，其余类计数不上升。
      C1，P1，S2。
- [ ] F3f swift 浮点字面量渲染：覆盖第 5 节 `expected member name
      following '.'` 全类 7 条（PunctuationGeometryStage.swift:139 等 7
      处，Haxe 源的 `0.` 形浮点字面量）。修复面＝swift 目标浮点字面量
      渲染函数。rust 侧同症状 124 条（第 6 节）是另一个目标上的修复面，
      生成函数定位随 F4c，定位后单独开列。C1，P1，S3。
- [ ] F3g swift 字符串控制字符转义：覆盖第 5 节 `unprintable ASCII
      character found in source file` 全类 1 条（ShapingEvidenceJson.swift:445，
      Haxe 源 `buf.addChar(8)` 被生成为源文件内的控制字符）。修复面＝
      swift 目标字符串字面量的转义。C1，P2，S3。
- [ ] F3h dart 目标 getter-only 属性调用点：覆盖 UNDEFINED_GETTER 全类
      32 条（全部为 The getter 'strategyName' isn't defined for the type
      'LineBreaker'，gen 1 条加 tests 31 条）。修复面＝dart 生成器实例
      成员读取路径上 getter-only 判定规则缺失（boring `5628b4d` 已在
      kotlin、swift、rust 实现对应规则，dart 侧此形状漏过，机制位置随
      探针定位；规格为 docs/specs/features/27-class-members-and-records.md
      规则 5）。判据＝UNDEFINED_GETTER 计数降为 0，其余类计数不上升。
      C1，P1，S2。
- [ ] F3i dart 目标运行时与 std 影子文件的写出：覆盖 URI_DOES_NOT_EXIST
      全类 36 条（路径明细见第 8.2 节：runtime/sorted_table、
      std/sorted_map、std/functional、std/u_string_exception、
      std/u_string_fault、haxe/exception、tests 侧的 test_host 与跨目录
      测试引用）。判定来源＝2026-09-06 磁盘对照：boring 自身样本生成树
      含 lib/std、lib/haxe 与 test_host.dart，tiqian 消费树 out/ 下这些
      文件均不存在而生成代码以相对路径引用它们。修复面＝dart 目标这些
      文件在消费方配置下的写出条件。判据＝URI_DOES_NOT_EXIST 计数降为
      0，其余类计数不上升。C2，P1，S2。
- [ ] F3j kotlin 数值转换位扩展：覆盖 operator applied 全类（f32 35 /
      f64 32）、return 全类（28 / 28）、initializer 全类（15 / 17）、
      assignment 类内数值形状（19 / 23 中数值部分）与 3.3 节 Int 给浮点
      （80 / 88）、Long 给浮点（0 / 2）两形状。修复面＝KotlinExpr.hx
      的 renderCallArgs（boring `4b1fec9` 时位于 2806-2820，派发方复核）
      只在实参位对 isIntType 的接收值插入 `(x).toFloat()/.toDouble()`
      转换，运算、return、默认值、赋值四个位置没有同等转换，isIntType
      也不覆盖 Long；修复＝把这四个位置与 Long 纳入同一转换机制。判据＝
      operator applied、return、initializer 三类与 Int 给浮点、Long 给
      浮点两形状计数降为 0，assignment 剩余条目全部为可空形状，其余类
      计数不上升。C2，P1，S1。
- [ ] F3k kotlin getter 降级可见性：覆盖 modifier incompatible 全类
      （14 / 14）、cannot weaken 全类（7 / 7）、cannot access 类内 get_
      前缀条目（get_strategyName、get_isMixed；27 / 27 中的 getter 部分）。
      修复面＝boring `5628b4d`（getprop 修复任务）在 kotlin 实现类生成
      `private override fun get_X()`，Kotlin 语法禁止 private 与
      override 并用，实现成员可见性也不得低于接口成员（LineBreaker.kt:42
      与 LineBreakerCoverage2Test.kt:138 实测）。判据＝modifier
      incompatible 与 cannot weaken 两类降为 0，cannot access 降至私有
      静态跨类调用条目（emptyHanging 一类）的基数，其余类计数不上升。
      C2，P1，S2。
- [ ] F3l dart 类型名与枚举名值位引用缺导入前缀：覆盖 UNDEFINED_IDENTIFIER
      类内 8 个类型名条目合计 705 条（WritingMode 157、LastLineAlignment
      155、InlineAttachment 147、Ic 106、RubyLineHeightMode 77、RubyKind
      35、LineEndReason 16、FontRole 12，分布见 8.2）。修复面＝
      DartExpr.hx:1466-1485 的枚举引用分支对值位引用输出不带前缀的名字、
      DartImports.hx:186-215 的前缀登记没有覆盖这类引用
      （adjustment_style_policy.dart:14 值位不带前缀直接使用 `LineEndPunctuationStyle`
      实测，同文件类型位用带前缀形；两处位置派发方在 31627b5c 复核）。
      判据＝上述 8 个名字的计数降为 0，其余名字计数不上升。C2，P1，S1。
- [ ] F3m dart 可空接收者守卫缺失：覆盖 UNCHECKED_USE_OF_NULLABLE_VALUE
      全类 420 条（property 314、method 82、operator 18、condition 6，
      分布见 8.2）。修复面＝dart 生成器对可空接收者的成员访问、调用、
      运算与条件位没有发守卫（clreq_punctuation_advance_policy.dart:27
      的 int? 接收者直接比较实测；DartExpr.hx:1315-1341 的 binop 守卫位
      派发方在 31627b5c 复核），与 kotlin 修复面 A（#22）同构造。判据＝
      该错误码计数降为 0，其余类计数不上升。C2，P1，S1。

### 第 4 组：五目标普查（K7）

- [x] F4a rust 首次编译普查：2026-09-06 完成（工作树 /tmp/tiqian-census4，
      基线同第 3.1 节）；`cargo check` 报 181 条错误、15 个消息骨架，逐类表
      与产出命令见第 2.2、6 节。同时判定 kotlin 表 `'X' cannot be a callee`
      类（IllegalStateException.kt:5:5，异常子类第二代的生成缺陷）。
- [x] F4b dart 目标的逐类表：swift 的逐类表在第 5 节，ts 的逐类表在第
      7 节，dart 的逐类表在第 8 节（三者均 2026-09-06 完成；dart 为 35
      类、2931 条，求和校验相等，无测量环境条目）。cross-target-alignment
      的最终对照待各目标判定列填全后补。C2，P1，S-。
- [ ] F4c rust 逐类判定探针：对第 6 节未判定的 13 类按类内计数降序抽样
      错误点，读生成代码，把错误类归到修复面，并补齐两个已判定修复面
      （浮点字面量生成、保留字转义缺失）的生成函数定位；产出＝第 6 节
      判定列填全，修复项随后按修复面开列。C2，P1，S-。

## 12 进度记录

| 日期 | 修复项 | 合入位置 | 复测计数 | 验收 |
|---|---|---|---|---|
| 2026-09-05 | Kotlin 基线建立 | boring `a75601a` | f32 3338 / f64 3358（分桶脚本有条件类错分） | 不适用 |
| 2026-09-05 | 基线迁移到 `5d7417e` 并修正分桶脚本 | boring `5d7417e` | f32 3335 / f64 3355，分桶合计与总数一致 | 不适用 |
| 2026-09-05 | 四目标第一处报错实测记录 | 本文档第 4 节 | ts、swift、rust、dart 均无法生成 | 不适用 |
| 2026-09-05 | F0e 三生成器补 `Math.abs` 规则 | boring `7f2bced`（vendored 已推进） | dart 生成目录该报错不再出现，dart 第一处改为 variant switch | 十条套件全部退出码 0 |
| 2026-09-05 | F0f `Std.string` 违规调用定位与修复（第一轮） | tiqian `e0e1172d`＋`ec285e24` | 当时 rust 生成目录该报错不再出现（当轮枚举两类），rust 第一处改为 fallible capacity | 移植树 gates.sh 三项全过；engine jvmTest 通过 |
| 2026-09-05 | F0j 整型容量上界生成规则 | boring `012ab59`（vendored 已推进） | rust 生成目录该报错不再出现，rust 第一处改为 F0k 的 `Std.string` 第二批（放宽实测确认是最后一类） | 十条套件＋test:consistency 全部退出码 0 |
| 2026-09-06 | 基线迁移到 tiqian `105dfb30` 加 boring `4b1fec9`（r4） | 本文档第 3 节 | f32 1183 / f64 1201，warnings 0；ts、swift、dart 首处更新为第 4 节现值 | G4-RC=0、bun pass=121 fail=0、COMPARE-RC=0（sbuf-bind 条目） |
| 2026-09-06 | 桶表改逐类表，修两条测量错误（续行计数、消息文本过期） | 本文档第 2.3、3.2 节 | f32 36 类 / f64 39 类，求和各等于 total | 不适用 |
| 2026-09-06 | KPI 重切：按修复面与判定覆盖取代主题合并，撤销 F3a-d | 本文档第 9、10 节 | 判定进度见 3.2 节小结 | 不适用 |
| 2026-09-06 | rust 首次编译普查（F4a）与 kotlin `'X' cannot be a callee` 类判定 | 本文档第 2.2、3.2、6 节 | rust 181 条、15 类，求和校验相等；kotlin 该类 f32/f64 各 1＝异常子类第二代 super 误入 init 块 | 不适用 |
| 2026-09-06 | ts 第二处生成阻断 UStringException 值引用修复（修复任务 ustr） | boring `f270c670`（合并 `de11c06a`，已推送） | ts 生成退出码 0，首次全量生成 | 19 项验收检查退出码全部为 0；合并后 boring main 的 bun test 670 pass / 3 fail（三个既有名目） |
| 2026-09-06 | getter 属性读四目标调用点修复（修复任务 getprop） | boring `5628b4d`（合并 `f9f26726`，已推送） | 一致性检查 342 个测试六目标一致（含新增的 PublicGetterPropertyTests） | 19 项验收检查退出码全部为 0 |
| 2026-09-06 | ts 首次编译普查（F4b 的 ts 半项）；swift 与 ts 并入 KPI；文档条目全量列举与格式统一 | 本文档第 1、2.2、3.4、4、7 至 11 节 | ts 1127 条、19 类，求和校验相等；测量环境 308 条、引擎侧 819 条；dart 第一处更新为 Units.hx 静态重名（F0l） | 不适用 |
| 2026-09-06 | F0l dart 静态成员顶层重名修复（修复任务 dartic）与 dart 首次编译普查（F4b dart 半项）；dart 并入 KPI | boring `189e01ad`（合并 `31627b5c`，已推送） | dart 生成退出码 0；dart analyze 报 2931 条、35 类，求和校验相等；无测量环境条目 | 19 项验收检查在修复工树与合并工树各全部退出码 0；合并后 bun test 672 pass / 3 fail（三个既有名目） |
| 2026-09-06 | rust 普查复测（基线推进到 boring `75b08ed2`）；补两条 rust 测量错误记录 | 本文档第 2.2、2.3、6 节 | rust 180 条、15 类，求和校验相等；相对 4b1fec9 首测的 181 条少一条保留字转义类（`type` 6 处降 5 处）；浮点字面量类 124 条不变 | 不适用 |
| 2026-09-06 | T-attr r1 与 T-dart r1 判定并入普查文档；新增修复项 F3j、F3k、F3l、F3m | 本文档第 3.2、3.3、3.4、8、8.2、10、11 节 | 判定进度见 3.2 与第 8 节小结；错误计数未复测，基线不变 | 不适用 |

## 13 已完成并合入的修复（背景）

以下修复在 r4 基线之前已合入，其效果已包含在基线数字里：names-r2 名称解析
第一批（unresolved 从 347 降到 290）、单变体异常折叠回归修复（boring
`a75601a`）、record 接口字段打印与 Rust derive 修复（boring `5d7417e`）、
Dart 的 Math.min 与 Math.max 调用点降级补臂、nullargs 五目标 null 实参的
默认值直接生成（boring `8d17b59`，null 字面量错误 2122 条降为 0）、knarrow
null 初始化位的空值处理（boring `4b1fec9`，null 残余 52 条降为 0）、
onlysafe 上半 assertFailsWith 尾端 throw 化（tiqian `3ce6f511`，only safe
95 降 75）、sbuf-bind StringBuf.toString 四站绑局部（tiqian `0b152313`，
stringbuffer 表达位错误降为 0，使 ts、swift、dart 三个目标越过该构造）。
