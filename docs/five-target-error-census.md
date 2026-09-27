# 五目标生成代码编译错误普查与修复追踪

本文记录 engine-haxe 生成代码在五种输出语言（Kotlin、TypeScript、Rust、Swift、
Dart）下的编译错误，作为跨目标行为对齐（见
[cross-target-alignment.md](cross-target-alignment.md)）的修复计划与进度追踪。
普查对象是 engine-haxe/out/ 下由 boring 从 Haxe 源码翻译出的目标语言代码目录。
原生 `engine` 模块的 `./gradlew :engine:jvmTest` 无失败，不在本文范围内。

当前状态（2026-09-10 傍晚，基线 tiqian `3f609c0f` 加 boring `a2f2bdc2`，主树直接复测）：八个生成命令退出码全部为 0。kotlin f32 176 条 / f64 187 条；ts 337 条；rust f32 3402 条 / f64 3174 条；swift gen 侧 f32 0 条 / f64 1 条、tests 侧 f64 41 条；dart 317 条（生成侧 269 条、测试侧 48 条）。两日累计：总错误 6546 降至 4394（kotlin 减半、dart tests 减 88%、ts 减半）。已解决并复测确认的修复项自 2026-09-07 起从第 11 节清单删除，只留第 12 节进度行。

## 1 更新规则

- 每个修复项只有一个复选框。满足以下四条后视为完成：修复已合入 boring main
  （写提交号）或 tiqian（写提交号）；vendored 副本已推进并重新生成相关目录；
  该错误种类在相关目录的计数都是 0；boring 的验收命令全部通过。完成并在新
  基线复测确认后，把该修复项从第 11 节清单删除，只在第 12 节进度记录表留
  一行（2026-09-07 用户规定，取代此前「勾选后保留记录」的做法）；修复项
  编号保留不复用。
- 一次修复只允许对应一个修复项；不允许一次核销多项，也不允许提前核销。
- 计数必须来自本文「测量配方」一节的命令输出，不允许凭印象填写。
- 错误按消息骨架逐行记录，每一类一行（2026-09-06 用户规定：不设「未归类」
  「其余」聚合行，折叠会让任务量检验失真）。新暴露的错误类在逐类表加新行，
  不允许并入既有行，也不允许并入任何聚合行。每张逐类表必须附求和校验，各类
  计数之和等于总数。
- 大类内部的分解同样逐条列出：名称、模块、文件等维度的分布写全每一个名字
  与计数，不设「前 N 位」的截断，也不设把多个名字合并成一行的聚合行
  （2026-09-06 用户规定：条目折叠省略会让工作量检验失真）。
- 修复项与 KPI 的切分必须反映修复工作量：每条修复项写明它覆盖的错误类、
  类内条目与计数，KPI 的现值写各目标逐类表的实测计数；不把多个修复位置合并
  成一个指标（2026-09-06 用户规定）。
- 每次修复合入 boring main 后就重测受影响目标的目录：只要计数相对上一
  基线下降，立即更新对应逐类表与第 10 节 KPI 现值，并向用户交前后对照表；
  不必等计数降为 0，也不必等修复项整体完成（2026-09-07 用户规定）。
- 第 12 节进度表与第 11 节修复历程不复述提交内容：哪个提交改了哪个文件、
  哪个分支、加了几行，经提交号用 git show 得知，文档不重复叙述
  （2026-09-08 用户规定）。进度表修复项栏写修复项编号、修复名与覆盖的
  错误类；修复历程括注写轮次、提交号与提交号无法得知的事实（计数、
  验收结果、判定、规定、失败的定性、未提交事件）。提交号本身可以出现在
  任意栏。

## 2 测量配方

### 2.1 Kotlin（f32 与 f64）

```shell
# 前置：vendored 副本指向要测的 boring 提交
cd /home/losses/Development/tiqian/.haxelib/boring/git && git fetch origin && git checkout <提交号>

# 从 tiqian 仓库根目录重新生成两个 Kotlin 目录。每次 haxe 前在同一个
# nix shell 里重写 .dev（.dev 损坏时 haxe 报 Type not found : Intercept，
# 所以每次生成前都重写一次）
nix develop -c bash -c 'printf "%s" /home/losses/Development/tiqian/.haxelib/boring/git > .haxelib/boring/.dev; haxe engine-haxe/targets/kotlin-f32.hxml'  # f32
nix develop -c bash -c 'printf "%s" /home/losses/Development/tiqian/.haxelib/boring/git > .haxelib/boring/.dev; haxe engine-haxe/targets/kotlin-f64.hxml'  # f64

# 编译普查。kotlinc 不在默认 PATH，必须用绝对路径；退出码 1 是预期，
# 错误计数来自日志
cd /home/losses/Development/tiqian
nix develop -c bash -c '
KOTLINC=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin/kotlinc
$KOTLINC -Xallow-kotlin-package \
  $(find engine-haxe/out/kotlin-gen-f32 engine-haxe/out/kotlin-gen-f32-tests -name "*.kt") \
  -d engine-haxe/out/tiqian-f32.jar 2> engine-haxe/out/census-f32.log
$KOTLINC -Xallow-kotlin-package \
  $(find engine-haxe/out/kotlin-gen-f64 engine-haxe/out/kotlin-gen-f64-tests -name "*.kt") \
  -d engine-haxe/out/tiqian-f64.jar 2> engine-haxe/out/census-f64.log
grep -a -c " error: " engine-haxe/out/census-f32.log
grep -a -c " error: " engine-haxe/out/census-f64.log'

# 逐类枚举（第 3.2 节逐类表的产出命令）。消息骨架指把消息里的具体
# 标识符与数字替换成占位符后得到的模板：单引号内的标识符替换为 'X'，
# 数字串替换为 N，重复的枚举项收敛。输出每一行是一个错误类与其计数；
# 两列各自求和必须等于上面的总数，此校验缺失的表无效。
for LOG in engine-haxe/out/census-f32.log engine-haxe/out/census-f64.log; do
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
for LOG in engine-haxe/out/census-f32.log engine-haxe/out/census-f64.log; do
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
grep -a " error: unresolved reference" engine-haxe/out/census-f32.log \
  | sed "s/.*unresolved reference '\([^']*\)'.*/\1/" | sort | uniq -c | sort -rn
```

### 2.2 其余四目标

```shell
nix develop -c bash -c 'haxe engine-haxe/targets/ts.hxml'        # TypeScript，自 boring de11c06a 起退出码 0
nix develop -c bash -c 'haxe engine-haxe/targets/rust-f32.hxml'  # Rust（f32），当前退出码 0
nix develop -c bash -c 'haxe engine-haxe/targets/rust-f64.hxml'  # Rust（f64），当前退出码 0
nix develop -c bash -c 'haxe engine-haxe/targets/swift-f32.hxml' # Swift（f32），自 boring 2c9257d 起退出码 0
nix develop -c bash -c 'haxe engine-haxe/targets/swift-f64.hxml' # Swift（f64），自 boring 2c9257d 起退出码 0
nix develop -c bash -c 'haxe engine-haxe/targets/dart.hxml'      # Dart，自 boring `31627b5c` 起退出码 0
```

Swift 编译普查按目录运行：gen 与 tests 各自单独 typecheck 得到每目录
计数。同精度的 gen 与 tests 两目录没有同名文件，可以合并进一次 swiftc
调用；合并测量用于区分消费侧配置与引擎侧错误：

```shell
cd engine-haxe/out
for D in swift-gen-f64 swift-gen-f64-tests; do
  find "$D" -name '*.swift' | sort | xargs swiftc -typecheck > "sw-$D.log" 2>&1
  echo "$D rc=$?"; grep -a -c ': error:' "sw-$D.log"
done   # f32 侧同形，目录名换 swift-gen-f32 与 swift-gen-f32-tests

# 合并测量（诊断用，不替代逐目录计数）：同精度 gen 与 tests 合并后跨目录
# 符号可解析；语法解析错误还有剩余时语义检查不完整，语义错误仍以逐目录计数为准
find swift-gen-f64 swift-gen-f64-tests -name '*.swift' | sort | xargs swiftc -typecheck > sw-combined-64.log 2>&1; echo rc=$?
grep -a -c ': error:' sw-combined-64.log   # f32 侧同形为 sw-combined-32.log
```

boring 遇到尚未实现生成规则的 Haxe 构造时，在第一处这样的构造上报错并中止。
四个目标的生成命令退出码均已为 0，四者的编译普查命令都已记在本节。

TypeScript 重生成与编译普查：

```shell
# 重生成
nix develop -c bash -c 'printf "%s" "$PWD/.haxelib/boring/git" > .haxelib/boring/.dev; haxe engine-haxe/targets/ts.hxml; echo "TS_RC=$?"'

# 编译普查。tsc 用 tiqian 根目录 node_modules 里的副本；有错误时
# 退出码非 0 是预期，错误计数来自日志
cd engine-haxe/out && nix develop -c bash -c 'bun ../../node_modules/typescript/bin/tsc --noEmit --allowImportingTsExtensions --module esnext --moduleResolution bundler --target es2022 $(find ts-gen ts-gen-tests -name "*.ts") > audit-tsc.log 2>&1; echo "TSC_RC=$?"; grep -c "error TS" audit-tsc.log'

# 逐类枚举（第 7 节逐类表的产出命令）。tsc 的诊断首行含 error TSNNNN，
# 续行不含，计数只取首行。骨架化在去掉行首文件位置后的消息段上进行：
grep -a 'error TS' audit-tsc.log | sed 's/^.*error //' \
  | sed -E "s/'[^']*'/'X'/g" \
  | sed -E 's/\{[^{}]*\}/{…}/g' | sed -E 's/\{[^{}]*\}/{…}/g' \
  | sed -E 's/<[^<>]*>/<…>/g' | sed -E 's/<[^<>]*>/<…>/g' \
  | sed -E 's/[0-9]+/N/g' \
  | sort | uniq -c | sort -rn
# 求和校验：上式输出第一列求和必须等于错误总数

# 类内分解（第 7.2 节的产出命令）：对指定错误码按名字、模块名或文件抽取
# 计数，下面以 TS2304 的名称分布为例，其余错误码的抽取规则见第 7.2 节
grep -a 'error TS2304' audit-tsc.log | sed -E "s/.*Cannot find name '([^']+)'.*/\1/" | sort | uniq -c | sort -rn
```

带类型配置的 ts 编译普查：为消除测量环境中的类型未定义缺失，在
`engine-haxe/out` 放置 `tsconfig.json` 配置类型定义与模块映射，使用 `-p` 运行：

```json
{
  "compilerOptions": {
    "noEmit": true,
    "allowImportingTsExtensions": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "target": "es2022",
    "baseUrl": ".",
    "paths": {
      "@tiqian/runtime": ["ts-gen/runtime.ts"],
      "@tiqian/runtime/test": ["ts-gen/runtime/test.ts"]
    },
    "typeRoots": ["../../node_modules/@types"],
    "types": ["node", "bun"]
  },
  "include": ["ts-gen/**/*.ts", "ts-gen-tests/**/*.ts"]
}
```

```shell
cd engine-haxe/out && nix develop -c bash -c 'bun ../../node_modules/typescript/bin/tsc -p tsconfig.json > ts-typed.log 2>&1; echo "TSC_RC=$?"; grep -c "error TS" ts-typed.log'
# 逐类枚举与类内分解的管道与上方首测块相同，日志名换 ts-typed.log
```

rust 的编译普查命令如下：

```shell
# Cargo.toml 由 boring Compiler.hx 在 PackageShell 启用时写进输出目录本身
# （targets/rust-f64.hxml 的 -D rust-output 指到 .../rust-gen-f64/src），
# cargo 从该目录运行。退出码 101 是预期，错误计数来自日志；必须带
# --message-format=short，原因见 2.3 节
cd engine-haxe/out/rust-gen-f64/src && cargo check --message-format=short > ../../r64.log 2>&1; echo rc=$?

grep -a -c ": error" engine-haxe/out/r64.log   # 错误总数

# 逐类枚举（第 6 节逐类表的产出命令）。骨架化规则与 Kotlin 相同：引号与
# 反引号内的文本替换为占位符、重复枚举项收敛、数字替换为 N；另把
# error[E####] 收敛为 [E]
grep -a ": error" engine-haxe/out/r64.log | sed 's/^.*: error//' \
  | sed 's/^\[E[0-9]*\]:/[E]:/' \
  | sed 's/`[^`]*`/`X`/g' \
  | sed "s/'[^']*'/'X'/g" \
  | sed 's/\(, `X`\)\{2,\}/, `X`…/g' \
  | sed 's/[0-9]\+/N/g' \
  | sort | uniq -c | sort -rn
# 求和校验：上式输出第一列求和必须等于错误总数
```

Dart 重生成与编译普查：

```shell
# 重生成
nix develop -c bash -c 'printf "%s" "$PWD/.haxelib/boring/git" > .haxelib/boring/.dev; rm -rf engine-haxe/out/dart-gen engine-haxe/out/dart-gen-tests; haxe engine-haxe/targets/dart.hxml; echo DART_RC=$?'

# 编译普查。有错误时退出码非 0 是预期，错误计数来自日志；两个目录分别运行
cd engine-haxe/out/dart-gen && dart analyze --format=machine > ../dart-gen.log 2>&1; echo rc=$?; grep -c "^ERROR" ../dart-gen.log
cd engine-haxe/out/dart-gen-tests && dart analyze --format=machine > ../dart-tests.log 2>&1; echo rc=$?; grep -c "^ERROR" ../dart-tests.log

# 逐类枚举（第 8 节逐类表的产出命令）。机器格式为
# 级别|类别|错误码|文件|行|列|长度|消息，错误码取第 3 列；WARNING 与 INFO
# 不计入；gen 与 tests 两目录合并计数，keys 收两侧并集
for side in gen tests; do awk -F'|' -v s=$side '/^ERROR/{print $3"\t"s}' engine-haxe/out/dart-$side.log; done \
  | awk -F'\t' '{if($2=="gen") g[$1]+=1; else t[$1]+=1; keys[$1]=1} END{for (k in keys) printf "%s\t%d\t%d\t%d\n", k, g[k]+0, t[k]+0, g[k]+t[k]+0}' \
  | sort -t$'\t' -k4 -rn
# 求和校验：上式输出合计列求和必须等于错误总数

# 类内分解（第 8.2 节各表的产出命令）
cat engine-haxe/out/dart-gen.log engine-haxe/out/dart-tests.log | awk -F'|' '/^ERROR/ && $3=="UNDEFINED_IDENTIFIER" {msg=$8; if (match(msg, /Undefined name '''[^''']*'''\.'''/)) print substr(msg, RSTART+16, RLENGTH-18)}' | sort | uniq -c | sort -rn
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
  （2026-09-06 实测：同一份生成目录，默认形按该锚点数得 0，short 形数得
  180）。普查命令必须带 `--message-format=short`。
- rust 的默认多行输出里，`grep -c "^error"` 会把末尾的汇总行 `error:
  could not compile ... due to N previous errors` 也计入（同一份生成目录 180 条
  诊断加 1 行汇总数得 181）；short 形没有汇总行，不存在这个问题。
- tsc 与 dart analyze 的诊断都打在 stdout。把 stdout 重定向到
  /dev/null（`> /dev/null 2> log`）会得到空日志而退出码仍非 0，两个目标
  被计为 0 条错误（2026-09-07 实测，ts 与 dart 两格一度误记 0）。普查命令
  必须写 `> log 2>&1`。
- swift 同精度的 gen 与 tests 两目录没有同名文件（2026-09-07 comm 实测），
  合并调用可行。2026-09-07 早先把合并调用只得 16 条记为 filename used
  twice 截断是误判：16 条是跨目录符号解析后剩下的语法解析错误数（第
  5 节）。同名文件冲突出现在 f32 与 f64 两个精度目录之间（同名文件集
  完全相同），跨精度不能合并。
- swiftc 在语法解析错误还有剩余时语义检查不完整：合并测量里 gen 侧
  BopomofoParser.swift 的 optional 解包错误缺席，而逐目录 gen 单独测量
  该错误在（实测对照逐目录测量日志与合并测量日志）；语义错误计数以逐目录为准。
- rust 当前全部错误在解析层（rustc 未开始类型检查）时，cargo check 约 1
  秒返回，属正常；完整性以日志末行 `due to N previous errors` 的 N 与计数
  相等核对（2026-09-07 两侧 N=20 均核过）。
- 早于 tiqian `3f609c0f`（生成入口拆进 engine-haxe/targets/）的消费方检出里，
  生成入口仍是旧名 `engine-haxe/core-<目标>.hxml`；在这些检出上测量时以该检出
  实际文件名为准。
- `_GeneratedFiles.txt` 末行没有换行符，`wc -l` 比 `grep -c .` 少计 1 行
  （2026-09-07 实测：swift gen 清单 wc -l 391、grep -c . 392）；产物文件数
  以 `find <两个产物目录> -type f | wc -l` 为准，该命令把清单文件本身也计入
  （392 个生成文件加清单等于 393）。

## 3 Kotlin 普查结果

### 3.1 基线快照

- 测量基线：tiqian `3f609c0f`（本地 main）加 boring `e01b03b3`，2026-09-07 实测。vendored 副本指向 `.haxelib/boring/git` 里的 `e01b03b3`。
- f32 目录（out/kotlin-gen-f32 与 kotlin-gen-f32-tests）696 条错误；f64
  目录（out/kotlin-gen-f64 与 kotlin-gen-f64-tests）717 条错误；两目录
  warning 计数均为 0。
- 基线血统：`a75601a` 首测 f32 3338 / f64 3358（`5d7417e` 上 3335/3355）；
  `8d17b59`（nullargs 合入）1535 / 1553；tiqian `105dfb30` 加 boring
  `4b1fec9` 1183 / 1201；本节基线 696 / 717；kf3v-r1 合并后 `b7054019`
  680 / 701（too many arguments 14/14 随 F3v 降 0 删除，）；knamefix-r8 合并后
  `3044bf91` 343 / 354（census11，两列类集首次完全相同，各 33 类；逐类
  降量、新类引入路径与未查明项见 3.2 表行内说明）；`a72f994d` 343 / 354
  （census12，见下）。旧分桶表 28 桶 2026-09-06 起作废，由第 3.2 节
  逐类表取代。
- 2026-09-08 census12 复测（boring `a72f994d`，vendored 推进到该提交，
  tiqian 主树 `4bfe817f` 重生成，退出码 0）：f32 343 / f64 354、warnings 0/0，与 census11 总数持平
  （`3044bf91..a72f994d` 区间 dartargs-r2 的 kotlin 侧改动不改变消费树
  计数）；逐类枚举本轮未做，3.2 表数值仍标 census11 复测。

### 3.2 逐类全表（2026-09-08 census11 复测；f32 与 f64 各 33 类非零，两列类集相同）

「判定」列的含义：一个错误类的修复位置（boring 生成器的机制位置，或
tiqian 源的一类写法）已经探针证实时，记修复位置；只有猜测记「假设」；都没有
记「未判定」。判定的方法见 T-attr（第 11 节第 1 组）：对类内抽样错误点读
生成代码后定性。假设不构成派发依据，证实后才开修复项。本轮新增一档
「形状证实」：探针读过该类抽样错误点的生成代码、确认错误落在生成形状上，
但还没有把生成器机制定位到文件与分支；它的可信度高于假设、低于修复位置，
不单独构成派发依据。本文用到两个修复位置名：修复位置 A 指可空接收者上方法调用
的生成机制；数值转换面指数值类型互转的生成机制。

判定来源：探针 T-attr r1（基线 boring `4b1fec9`，采信其抽样形状）；tattr2 r2（基线 boring `d870489c`，unresolved reference 相关十七类全量判定）；f64only r1（f64 独有类的根本原因）；tattr3 r1（十四类机制定位与假设检验，生成器行号在 `e01b03b3` 检出逐处复核）。数值转换面
（KotlinExpr.hx:2806-2820 的 renderCallArgs 只在实参位插入转换）与 getter
降级可见性（`5628b4d` 生成 `private override`）两处机制由派发方在 4b1fec9
检出复核。

| 错误消息类（骨架） | f32 | f64 | 判定与处置 |
|---|---:|---:|---|
| argument type mismatch: actual type is 'X', but 'X' was expected. | 131 | 138 | 形状分解见 3.3；Int 给浮点 12/12 是 F3j 残余（形状明细见 3.3）；可空 81、Number 装箱 14、其余 24/31 待证（knulljud r1 只交付了按错误类汇总的预览计数，逐形状判定未并入本表） |
| unresolved reference 'X'. | 54 | 54 | knamefix-r8 合并后的残余（365/358→54/54）；符号分布与归属见 3.4（11 个符号 Σ=57，含 operator 形 3 条）；修复任务 knamefix（#23）由本会话派出 |
| 'X' cannot be reassigned. | 24 | 24 | 新类（census11 引入，knamefix-r8）；引入路径已判定（两树同位对照）：knamefix-r8 的 counted-loop 识别改动把 `b7054019` 树的 `var i = 1; while (…)` 形改写成 `for (i in …)` 形时没有检查循环体是否写计数器（LineRepair.kt:38 加 :44 的 `i++`、LayoutQueries.kt:283 的 `index += 1` 实测；24 条分布 LineRepair.kt 12、PunctuationGeometryStage.kt 6、LayoutQueries.kt 2、其余四文件各 1）；修复位置（tattr4 r1）：循环识别的区间谓词 PolicyQueries.hx intervalCore（:800-868）与 intervalShort（:888-930）匹配 while 形计数循环时只识别声明、条件与尾部自增，不检查循环体其余位置写计数器，KotlinExpr.hx:867-870 matchInterval 命中后 :966-1000 输出只读 for 绑定（LineRepair.kt:39-44 实测）；修复为两谓词加体写检查（赋值与自增形、递归嵌套语句）返回 null 保留 while 形。F3au |
| return type mismatch: expected 'X', actual 'X'. | 17 | 21 | F3j 残余；f64 由 17 升 21 的原因没有查明 |
| none of the following candidates is applicable: | 12 | 12 | 探针定位待因果验证（tattr3 r1）：`+` 两侧为 `Number & Comparable<…>` 装箱与具体 Float 时 kotlinc 列出全部候选（PunctuationGeometryLedger.kt:36、:40、:43 实测；机制位置 KotlinExpr.hx binopCore :1996 起）；与 unresolved for operator、modifier required 两行同源（装箱值仍是 Number，没有转换成具体数值类型），随 #23；11→12 的原因没有查明 |
| conflicting declarations: | 11 | 11 | 修复位置（tattr3 r1）：typer 把数组推导 `[for …]` 展开成构建器局部 `_g`，kotlin 目标 Compiler.hx:72 的 `preventRepeatVars: false` 关闭 reflaxe 的 RepeatVariableFixer，KotlinExpr.hx localName :3299-3306 对这类展开名原样输出不做兄弟去重（只对 `` ` `` 与 `_` 生成避让名）→ 同函数两个 `val _g`（PreparedParagraphJfTest.kt:116 与 :126、LayoutQueries.kt:588 起实测；tattr3 r1 加临时 trace 实验证实展开名到达生成器，实验改动已还原）。F3w；13→11 的降幅归 knamefix-r8，未逐条核对 |
| type mismatch: inferred type is 'X', but 'X' was expected. | 8 | 8 | 假设（T-attr 抽样含异常第二代嵌套类引用 LayoutQueries.kt:390 `TiqianNoSuchElementException.Message`，疑与 #37 异常子类是同一机制）；形状证实（tattr4 r1）：抽样全部是异常构造位 `throw IllegalStateException` 与 Throwable 期望不符（DisplayGlyphSubstitutionEngineTestSupport.kt:81 等七处、TextShaper.kt:118），第二代异常引用这一组错误；声明侧分支未隔离；11→8 的降幅归 knamefix-r8，未逐条核对 |
| function invocation 'X' expected. | 7 | 7 | 修复位置（tattr3 r1）：静态方法作值使用时 KotlinExpr.hx field() 的 FStatic 分支 :2184-2187 经 staticRef 返回 `Class.method` 文本，函数类型位置需要 callable reference `Class::method` 或 lambda 包装（ContextualQuoteRoleResolverNestedAndSurrogateTest.kt:84 `Support.surrogateText`、ParseTexHyphenationPatterns.kt:55 `SortedTable.compareStrings` 实测）；8→7 即 F3ag 连锁条目 `range()` 随 knamefix-r8 消除。F3x |
| operator call is prohibited on a nullable receiver of type 'X'. Use 'X'-qualified call instead. | 6 | 6 | 修复位置 A 残余；#22 残余 |
| no 'X' operator method providing array access. | 6 | 6 | 修复位置（tattr3 r1）：set 形 4 条为 `split` 走通用实例调用分支 KotlinExpr.hx:2973 产出只读 `List`，随后下标写 `a[i] = …` 无 set（PreparedParagraph.kt:1726/1729/1741/1745）；get 形 2 条为 stringBufMutationLines :698 以文本拼接 `part + "[0].code"` 取首字符，part 为 `"" + values[i]` 时 `[0]` 绑到 `values[i]`（TracedAssertions.kt:116）。F3y |
| cannot infer type for type parameter 'X'. Specify it explicitly. | 6 | 6 | 假设部分否证（tattr3 r1）：42→6 的降幅与 F3ag 连锁消除同现（unresolved `copy` 消失后每行字段访问带的 cannot infer 连锁随之消失），tattr3 r1 的连锁判断成立；残余 6 条形状证实（tattr4 r1）：全部是 `SortedTable.mapBuilder(compareStrings)` 调用走通用调用渲染（KotlinExpr.hx:2362-2397）、未走 :3133 的类型化 map-builder 分支，K 与 V 无法推断（ParseTexHyphenationPatterns.kt:50-51 实测）；修复分支未隔离 |
| assignment type mismatch: actual type is 'X', but 'X' was expected. | 6 | 6 | F3j 数值形状已修（19/23 降 6/10）；f64 由 10 降 6 归 knamefix-r8；剩余条目待按可空形状再判 |
| 'X' is prohibited here. | 5 | 5 | 修复位置（tattr3 r1）：KotlinDecl.hx testFuncDecl :1152-1177 把测试函数体包进非 inline 的 `Test.run { … }` lambda，KotlinExpr.hx stmtLines 的无实参 TReturn 分支 :557 输出不带标签的 `return`，该位置禁止（BilingualEmphasisTest.kt:16、BopomofoLayoutTest.kt:24/96/118 实测）。F3z |
| jvmField has no effect on a private property. | 5 | 5 | 修复位置（tattr3 r1）：KotlinDecl.hx objectVarDecl :1009 对一切非 final 静态字段无条件生成 `@JvmField`，未排除 private（PreparedParagraph.kt:25/27/29/31、EnglishHyphenation.kt:4 实测）。F3aa |
| 'X' expression must be exhaustive. Add the 'X', 'X'… branches or an 'X' branch. | 4 | 4 | 修复位置（tattr3 r1）：Haxe typer 把 `case A | B:` 归并为一个 case 多值，KotlinExpr.hx switchExpression :1345-1349 只渲染 `c.values[0]`，其余值丢弃 → when 缺臂（FontMetrics.kt:15、ParagraphLayoutEngine.kt:158 实测；tattr3 r1 用 `-D dump=pretty` 实验证实归并形状）。F3ab |
| the feature "collection literals" is experimental and should be enabled explicitly. This can be done by supplying the compiler argument 'X', but note that no stability guarantees are provided. | 4 | 4 | 形状证实（tattr4 r1）：与 array literals、selector 两码为同一生成表达式 `lineExtras?.[i]`（可空接收者加数组下标，KotlinExpr.hx:1126 数组访问位）的三个解析视角，四条错误点全部同构（RubyLayoutTest.kt:26-27、LineAdjustmentStage.kt:79 两条、PreparedParagraph.kt:339）；修复分支待隔离 |
| the expression cannot be a selector (cannot occur after a dot). | 4 | 4 | 形状证实（tattr4 r1）：与 collection literals 行同一表达式 `?.[i]` 的第二个诊断视角（见该行）；f64 由 5 降 4 归 knamefix-r8 |
| receiver type 'X' contains star projection which prohibits the use of 'X'. | 4 | 4 | 假设：Number 装箱，与 none of candidates 行同一 Number 装箱机制（tattr4 r1 逐点证实）：`Number & Comparable<*>` 装箱值参与比较与 Float 调用（LineRepair.kt:187-190 `shrink > (0).toFloat()` 实测）；修复分支未隔离 |
| only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver of type 'X'. | 4 | 4 | 修复位置 A 残余（3→4 的原因没有查明）；#22 残余 |
| array literals outside of annotations are unsupported. | 4 | 4 | 形状证实（tattr4 r1）：与 collection literals 行同一表达式 `?.[i]` 的第二个诊断视角（见该行） |
| variable 'X' must be initialized. | 3 | 3 | 修复位置（tattr3 r1）：与 exhaustive 行同一机制（switchExpression 丢分组值）的连锁报错，分支缺臂路径无赋值，definite-assignment 无法证明初始化（FontMetrics.kt:21/52、ParagraphLayoutEngine.kt:164 实测）。F3ab |
| unresolved reference 'X' for operator 'X'. | 3 | 3 | 探针定位待因果验证（tattr3 r1）：SortedMapTable get 返回的 `Number` 装箱值参与 `-` 运算，`!!` 后仍为 Number（PunctuationGeometryLedger.kt:36 实测；机制位置 KotlinExpr.hx binopCore :1996 起）；与 none of candidates、modifier required 两行同源（装箱值仍是 Number，没有转换成具体数值类型），随 #23 |
| cannot access 'X': it is private in 'X'. | 3 | 3 | 修复位置（tattr3 r1）：kgetvis 合并 `ad0990e2` 后的残余 3 条，机制为 KotlinDecl.hx funcDecl :1103 与 objectVarDecl :1008 的可见性选择只把 `:allow` 转 internal，Haxe 的 `@:access` 授权与同模块文件私有跨类访问无映射（emptyHanging 于 LineOptimizationCoverageTest.kt:151、`@:access` 的 codePointLengthAt 与 strongScriptRole 于 ContextualQuoteRoleResolver.kt:293 起实测）。F3af |
| 'X' hides member of supertype 'X' and needs an 'X' modifier. | 2 | 2 | 修复位置（tattr3 r1）：KotlinDecl.hx funcDecl :1095-1099 的 overridesAny 只认零参 toString，手写 `hashCode` 与异常载荷 `message` 不在内（BopomofoReading.hx:27 手写 `public function hashCode():Int` 于 @:dataClass 类、TraceAssertionException 载荷 `val message` 与 sealedExceptionDecl :603-604 基类 `override val message` 冲突实测；早把本类记成 dataClass 合成 hashCode 缺 override 不属实，已更正）。F3ac |
| redeclaration: | 2 | 2 | 修复位置（tattr3 r1）：tiqian 两个模块各有一个 Haxe 文件私有类 `private class Resolution`（ContextualQuoteRoleResolver.hx:316、ContextualDashEllipsisRoleResolver.hx:223），KotlinDecl.hx classDecl :207 无条件生成 top-level `class`，同 package 冲突（ContextualDashEllipsisRoleResolver.kt:241 与 ContextualQuoteRoleResolver.kt:311 实测；早把本类记成嵌套类冲突不属实，已更正）。F3ad |
| 'X' modifier is required on 'X'. | 1 | 1 | 探针定位待因果验证（tattr3 r1）：Number 装箱值参与比较运算，kotlinc 要求 compareTo 的 operator 修饰（Justifier.kt:85 `d > 0` 实测，d 为装箱）；与 unresolved for operator、none of candidates 两行同源（装箱值仍是 Number，没有转换成具体数值类型），随 #23；9/10→1/1 归 knamefix-r8 |
| 'X' cannot be a callee. | 1 | 1 | 修复位置为 KotlinDecl 异常子类第二代的生成规则：super 调用被放进 init 块（IllegalStateException.kt:5:5，该类计数 1 即全部样本）；与 #37 同构造不同目标，修复项在 #37 完成后按修复位置开列 |
| Unexpected tokens (use 'X' to separate expressions on the same line). | 1 | 1 | 新类：Justifier.kt:151:2 的语法错误，与 overload resolution ambiguity 行的位点（Justifier.kt:149:21）同函数相邻，形状证实（tattr4 r1）：sumOf 块 lambda 表达式渲染残留（`}.toDouble() }.toFloat()` 续接，Justifier.kt:149-151 实测），与 overload resolution ambiguity 行同一位点；修复分支待隔离 |
| overload resolution ambiguity between candidates: | 1 | 1 | 新类（旧 ambiguous 类随 F3ag 消除）：Justifier.kt:149:21，与 modifier required 行的装箱 Number 位点（Justifier.kt:85）同文件；形状证实（tattr4 r1）：`ops.sumOf { … .toDouble() }.toFloat()` 的数值多重载无法解析（Justifier.kt:149-151 实测），装箱数值机制；修复分支未隔离 |
| operator 'X' cannot be applied to 'X' and 'X'. | 1 | 1 | F3j 残余 |
| null cannot be a value of a non-null type 'X'. | 1 | 1 | 形状证实（tattr4 r1）：String.lastIndexOf 单参调用降级时对非空 Int 形参插入 null 第二参（QuoteClassificationEngineTestSupport.kt:203-207 实测）；修复分支待隔离 |
| names _, __, ___, ... are reserved in Kotlin. | 1 | 1 | 修复位置（tattr3 r1）：KotlinDecl.hx parameterText :873 与 lambda 参数渲染只调 KotlinNameEscape.escape（:42-43，只给关键字加反引号），`_` 参数名原样输出（UnicodePunctuationBoundaryTestSupport.kt:118 `resolve(_: LayoutProfileId)` 实测）；函数体局部的 `_` 已有生成名路径（localName :3304），参数位没有。F3ae |
| condition type mismatch: inferred type is 'X' but 'X' was expected. | 1 | 1 | 形状证实（tattr4 r1）：可空接收者安全调用 `.has(...)` 返回 Boolean? 直接作条件（LineAdjustmentStage.kt:597 `if ((rejectedForSpan?.has(...)))` 实测），修复位置 A 延伸维持；修复分支未隔离 |
| 合计（求和校验） | 343 | 354 | 与 3.1 节 census11 总数相等 |
相对上一表（`b7054019`）计数已降为 0 并从表内删除的类：Expecting an
element（0/9）、both main（0/2）、initializer type mismatch（0/2），三类为
f64only r1 判定的 f64 浮点尾点路径，随 knamefix-r8 降 0；this declaration
needs opt-in（1/1，测量环境条目）与 method 'X' is ambiguous（1/1，F3ag）
随 knamefix-r8 降 0，F3ag 按删除制完成（进度见第 12 节）。更早降 0 删除的
类见第 12 节进度表（modifier incompatible、cannot weaken、smart cast、
for-loop non-nullable、infix、classifier companion、too many arguments）。

判定进度小结（tattr4 r1 后，33 类）：修复位置与残余挂靠修复项 20 类
（tattr4 r1 把 cannot be reassigned 升为修复位置 F3au；其余十九类同前：
unresolved 残余经 tattr2 r2 十七类判定，return、assignment、operator
applied 三类与 argument 类内 Int 给浮点形状是 F3j 残余，only safe 与
operator call prohibited 是修复位置 A 残余，cannot be a callee 随 #37，
conflicting、function invocation、no operator array access、prohibited
here、jvmField、exhaustive、variable must be initialized、hides member、
redeclaration、reserved、cannot access 十一类为 tattr3 r1 判定的修复
位置）；探针定位待因果验证 3 类（unresolved for operator、none of
candidates、modifier required，同一 Number 装箱机制，随 #23）；形状证实 10 类
（tattr4 r1：cannot infer、type mismatch inferred、star projection、
condition、overload ambiguity、Unexpected tokens、null cannot be 七类
各给生成样本与机制候选，collection literals、array literals、selector
三码 12 条为同一生成表达式 `?.[i]` 的三个解析视角）；假设与未判定
两档不再有条目。20 加 3 加 10 等于 33，与表行数相等。kotlin 侧剩余的判定工作是
给 3 类探针定位补因果链（随 #23 修复时验证）、给形状证实 10 类隔离
修复分支、把 argument 类内可空 81、Number 装箱 14、其余 24/31 归到
修复位置。

### 3.3 argument type mismatch 形状分解

2026-09-08 census11 复测（产出本表的命令见第 2.1 节）：

| 形状 | f32 | f64 | 判定 |
|---|---:|---:|---|
| 可空给非空（actual 类型以 ? 结尾，expected 非空） | 81 | 81 | 假设：疑与修复位置 A 同源；knulljud r1 对 null 相关错误类的判定报告只预览了按类汇总的计数、未逐形状并入，待并入后再判 |
| 其余转换 | 24 | 31 | 未判定；随下一轮判定 |
| Number 装箱给浮点 | 14 | 14 | 假设：T-attr 抽样为可空两臂条件表达式（FontPolicyCoverageTest.kt:125 实测），装箱路径未定位；待证 |
| Int 给浮点 | 12 | 12 | F3j 残余；FontPolicyCoverageTest.kt:243 里 `(13).toFloat()` 与未经转换的 `0` 并存是原始形状 |
| 合计（等于该类计数） | 131 | 138 | Long 给浮点形状（0/2）已随 knamefix-r8 降 0 删除 |

旧版 K4 的统计命令只覆盖数值形状（当时 f32 144 / f64 152），由本表取代；
「其余转换」行的存在不违反第 1 节的禁折叠规定，它是对 argument type
mismatch 这一个类内部的形状分类，下次分解出现新的成批形状时拆成具名行。

### 3.4 unresolved reference 符号分布（含 tattr2 r2 归属沿用）

2026-09-08 census11 实测（产出命令见第 2.1 节）：
去重后 11 个符号，计数合计 57，等于 unresolved 主类 54 加 unresolved for
operator 类的 operator 名 3。相对 `b7054019` 表的 112 个符号 Σ=368，
knamefix-r8 消灭了 101 个符号共 311 条（UString 29、clusterRange 24、
strategyName 32、Ic 16、compareXxx 长尾与全部属性名连锁在内）。f64 侧
分布与 f32 相同（主类 54 加 operator 形 3）。按第 1 节规定全量列举：

| 计数 | 符号 | 判定 |
|---:|---|---|
| 33 | kind | 修复位置（tattr2 r2 类 2）：dataClass 默认值引用兄弟参数 |
| 6 | s | 未判定（tattr2 r2 表内同名符号 6 条未单列归属） |
| 5 | region | 形状证实（rustprobe r1 跨目标对照，待 kotlin 侧探针证实）：@:dataClass 默认参数内联把构造器形参 `region` 泄漏进静态初始化器（rust 侧 clreq_profile.rs:24:433 同构造；kotlin 侧 ClreqProfile.kt:8 的 `PunctuationGluePlacements.for…` 调用点实测） |
| 3 | text | 同上假设（默认参数内联形参泄漏这一构造；kotlin 侧逐点判定未做） |
| 3 | minus | 未判定 |
| 2 | NodeFileSystem | 修复位置（tattr3 r1 结束消息）：`@:jsRequire` extern 在 Kotlin 目标没有宿主边处理被丢弃 |
| 1 | length | 未判定 |
| 1 | haxe | 未判定（疑为 haxe.Exception 引用，与 rust 侧 F4k 同名的跨目标表现，未验证） |
| 1 | count | 未判定 |
| 1 | cornerRadius | 同 region 行假设（默认参数内联形参泄漏这一构造） |
| 1 | charCodeAt | 未判定（疑与 dart F3at 的 charCodeAt 构造同源的调用点残留，未验证） |

符号到修复位置的归属沿用 tattr2 r2 十七类判定；region、text、
cornerRadius 三个符号与 rust E0425.b、swift gen 侧 org 全限定名条目、ts
F3as 的 org 名字条目是同一个 @:dataClass 默认参数内联构造在各目标的表现
（rustprobe r1 报告 3.2 节），
修复位置待跨目标统一判定后开列。修复随修复任务 knamefix（#23，由本会话
派出）的续作轮，不按符号名另行分组派发。

## 4 五个目标的生成状态（2026-09-07 实测）

boring 对尚未实现生成规则的 Haxe 构造，在生成阶段调用 `Context.error` 报错
并中止，不做猜测性输出；每消除一处报错都要重新生成一次才知道下一处，本文把
这套循环称为逐处重跑。2026-09-07 基线（tiqian `3f609c0f` 加 boring `e01b03b3`）上，kotlin、swift、rust 各 f32 与 f64 加 ts、dart 共八个生成命令退出码全部为 0，产物文件数依次为 397、397、393、393、405、405、394、393，逐处重跑阶段结束。八个格子的编译普查见第 3、5、6、7、8 节；生成阻断期的修复历史
并入第 12 节进度表。

## 5 Swift 编译普查（2026-09-08 tests 侧计数阻断中）

测量更正（2026-09-10，swf64 修复任务 r11 实测并经 census16 复测证实）：
`swiftc -typecheck` 默认 batch 模式把每个文件作为独立编译任务，首个失败
任务后不再启动后续任务。本节与 census14、census15 引用的 gen 侧「每精度
1 条」、tests 侧「41 条」以及更早的合并测量计数都是首个失败文件处的截断
值。全模块一次检查（`swiftc -typecheck -wmo`，gen 树与 tests 树合并）的
实际计数为 f64 1262、f32 1289（boring `4d91f806` × tiqian `3f609c0f`，
与 02720bae 位点两次独立测量一致）。前三大骨架：call can throw but is
not marked with 'try' 170、operator can throw but expression is not
marked with 'try' 121、'nil' requires a contextual type 73（swf64-r1
报告，主树 f64 WMO 日志）。下表保留为截断测量的历史记录，修复派发以
WMO 测量为准。

2026-09-08 census11 复测现值（boring `3044bf91`）：gen 侧每精度 1 条（错误在
census11 换成另一组：swiftnarrow 记录的 optional 解包错误消失、修复归
knamefix-r8 期间的合并，未逐笔核对；现存 1 条见下表）；tests 侧计数无法
产出：两个精度的 tests 目录逐目录 swiftc 与合并调用都在第一条
`no such module 'TiqianEngine'` 处中止（BopomofoParserTest.swift:1:8，
rc=123，计数 1 不是实际错误数）；测试文件头的 `import TiqianEngine` 在
census6 基线树同样存在（重跑记录为 57 条），census6 能计数是因为它当时的语法解析错误使 swiftc 在解析阶段
中止、未到模块加载；本轮 gen 侧语法错误减少后 swiftc 走到模块加载被
import 卡住。gen 侧计数降为 0 并经 `-emit-module -module-name TiqianEngine`
产出模块前，tests 侧没有替代测量配方，下表 tests 侧仍标 `d2c6b559`
复测值。轮次历史：census6 基线（tiqian `3f609c0f` 加 boring `e01b03b3`）gen 每精度 1、tests 每精度 57；swiftstr 修复合并（boring `6ad8dc66`，合并 `d2c6b559`）后 tests 每精度降 41；
首测（2026-09-06，boring `185cf02`）gen 侧浮点字面量 7 条与控制字符 1 条
两类由 swiftrem-r2（boring `4c81c5fc`，合并 `e01b03b3`）修复。

gen 侧（每精度 1 条）：

| 错误消息类（骨架） | 条数 | 样本 | 判定与处置 |
|---|---:|---|---|
| cannot find 'X' in scope | 1 | swift-gen-f64/org/tiqian/core/LayoutInput.swift:22:255（f32 同位） | 已判生成器：@:dataClass 默认参数内联把 Haxe 点分全限定名 `org.tiqian.core.Ic.Zero` 原样输出（生成行 `_ paragraphStyle: ParagraphStyle = ParagraphStyle(…, org.tiqian.core.Ic.Zero, …)` 实测），与 rust E0425.a、ts F3as org 名字条目、kotlin 3.4 节 region 形参泄漏是同一构造的 swift 表现；修复随跨目标统一判定开列 |

tests 侧（每精度 41 条，复测值）。判定来源 tswift1 r1 报告（六类逐类三件，锚点经复核）；消费侧配置与引擎侧的区分来自合并测量（第 2.2 节，两精度同为 16 条
语法解析错误）。引擎侧 F3t 四类（每精度 16 条，全部集中在
ExplainableStubParagraphLayoutEngineTest.swift:69 的多语句闭包嵌进插值段
连锁）已随 swiftstr 合并 `d2c6b559` 消除，对应四行已从表内删除：

| 错误消息类（骨架） | 条数 | 判定与处置 |
|---|---:|---|
| cannot find 'X' in scope | 32 | 消费侧配置：tests 目录文件没有 import 头（tiqian 的 targets/swift-common.hxml 未定义 `-D swift-test-import`，boring 合同见 examples/swift.hxml:20 与 Compiler.hx fileContent 的头部条件 :422-425），且支撑类 TracedAssertions 与 TestTraceRecorder 实际生成在 gen 目录 org/tiqian/test/trace/，tests 目录单独 typecheck 必然找不到；合并测量下这类错误数为 0。F3u |
| 'X' requires a contextual type | 9 | 消费侧配置连锁：被调方不可见时字面 nil 无上下文类型（BopomofoParserTest.swift 断言调用的第三实参）；合并测量下这类错误数为 0。随 F3u |
| 合计（求和校验） | 41 | 与 tests 目录错误总数相等（全部为消费侧配置 F3u；引擎侧 F3t 四类已消除） |

文件分布（复测）：BopomofoParserTest.swift 41 条（全部为消费侧配置
两类，即 F3u）；ExplainableStubParagraphLayoutEngineTest.swift 0 条
（修复前 16 条全部为 F3t 连锁，随合并 `d2c6b559` 消除；f32 侧同值
同分布）。


## 6 rust 编译普查（2026-09-08 census12 复测：f32 4548 / f64 4558，回归来源与逐码判定见逐类表）

首测与早期历史：2026-09-06 首测（boring `4b1fec9`）181 条、15 类；
rustflit 与 rustf4c 修掉浮点字面量 124 条与保留字转义 12 条（合并
`d870489c` 与 `782526d7`），rustf4c r2 判定探针把当时剩余 7 类归到 rust
生成器（F3n 至 F3s 开列）；`e01b03b3` 复测每精度 20 条、7 类（全语法层，
完整性以日志末行 N 与计数核对相等）；rustfix-r1 合并 `b7054019` 后每
精度 4 条、3 类（F3n、F3o、F3q 降 0；F3p、F3r、F3s 现场形状与 rustf4c
r2 记录不符，当轮更正）；rustfix r2 至 r4 合并后（`d0df20db`）解析层
三类计数降为 0、完成删除，rustc 进入类型检查，语义层错误首次进入测量：每精度
189 条、8 个消息骨架，f32 与 f64 逐类相同（两侧 N=189 均核过，见 2.3
节）。boring 自身的 stage1:rust 与 rust-f32 在 `d0df20db` 仍为 0：该
错误类只在 lib 单独构建下出现。

2026-09-08 boring `d38459ab` 第四次复测（两精度同值）：F4d 修复生效（pub use 行错误类 108→0，E0432 全类 154→46，求和
校验相等），同次复测新增四个错误码 174 条（E0425 84、E0424 75、E0433
净增 14、E0423 1），进入区间经提交拓扑缩小为 `d0df20db..d38459ab`。
rustprobe r1 只读探针 A/B 判定：新增四码是 `0629b847` 把测试模块加 `#[cfg(test)]` 条件编译排除
后、类型检查首次到达非测试模块既有错误的暴露（控制实验删光全部
cfg(test) 标注后计数精确回到 189；`908305a0` 精确复现基线 189 且其非
测试 .rs 文件与 `d38459ab` 逐字节相同）；派发方假设的两个候选
（`39054311` 经 `c332897a`、`7c2a1c02` 经 `908305a0`）都被实验否定，
`c332897a` 生成整体崩溃属 knamefix-r2 自身回归。

2026-09-08 census11 复测（boring `3044bf91`）：每精度 247 条、8 个错误码（逐码 E0425 76、E0424 75、E0432 46、
E0053 28、E0433 15、E0277 5、E0423 1、E0072 1，求和校验相等），相对
`d38459ab` 的 255 降 8，唯一变动 E0425（84→76，名字 `pi` 4 条与 `bi`
4 条消失，归 knamefix-r8 期间的合并，未逐笔核对），其余七个错误码计数不变。

2026-09-08 census12 复测（boring `a72f994d`）：f32 4548 条、f64 4558 条（两精度逐码差异只在 E0689，93 对 83），
相对 census11 的每精度 247 上升 4301/4311，为 `3044bf91..a72f994d` 区间
仅有的两笔 rust 侧合并（`746742dd` rustmisc-r2 与 `a72f994d` dartargs-r2）
引入的消费侧回归，boring 样本没有覆盖消费树的这些形状。boring 验收命令在合并后统一重跑 17 项通过、3 项失败：stage1:rust 与 rust-f32 的失败是两笔改动的交互（dartargs
的 fieldInits 优先分支消费了 rustmisc 装箱分支要处理的同名形参记录），
派发方修复 RustExpr.hx constructorBody 的同名形参不记录规则并入
`a72f994d` 后两套件单独复测通过；consistency 为既有失败项。抽样核对
一致的机制候选（经 rustjudge r2/r3 逐环验证，逐码判定与形状明细见
下表）：E0308 计数最大的形状 198 条与嵌套构造实参缺 Some 包装一致
（错误来源判定 `74371c5a`，F4p）；E0277 条数 5→834 的扩大与调用点
写出默认值相关（F4g 仅覆盖 send 5 条）；E0599 的 470 条 no method 形与
`.clone()` 调用点落在没有 Clone 派生的类上一致（F4q）；E0689 与无类型
后缀整数字面量上的方法调用一致；E0061 与构造器和函数签名减参后调用点
未补实参一致。E0072 1→0（F4j 修复生效）；E0433 15→14（census11 段落
记 15、表行记 14 的两处不一致以本轮实测 14 为准，消失的一条未逐名
核对）；其余六个 census11 错误码计数不变。

| 错误消息类（骨架） | 计数 | 判定与处置 |
|---|---:|---|
| cannot find value `X` in this scope 等 E0425 全部消息骨架 | 76 | 判定分四支（rustprobe r1 加派发方 census11 逐名位点复核；名字分布全列：org 52、UStringException 8、region 7、compare 前缀函数 6〔compare_font_metrics_request、compare_glue、compare_shaping_evidence_key、compare_recorded_shaping_result、compare_metrics_evidence_key、compare_recorded_font_metrics 各 1〕、SORTED_TABLE_COMPARE_STRINGS 2、count 1）：org 52 为 @:dataClass 默认参数内联把 Haxe 点分全限定名 `org.tiqian.core.Ic.Zero` 原样输出（rustprobe r1 3.2.a，layout_input.rs:44:150 实测；位点分布 35 个文件，core 侧 layout_input.rs、paragraph_style.rs、rich_text_paint.rs、rich_text_background_paint.rs 各 1，其余 48 条在 layout 目录的 test_support 类文件，最大 ruby_layout_test_support.rs 6）；region 7 与 count 1 为同一内联路径把构造器形参泄漏进调用点上下文（clreq_profile.rs:24:433 的 pub static 初始化器与 layout_dump_format.rs:146 的 `Ic(count)` 实测，rustprobe r1 3.2.a/3.2.b）；compare 前缀 6 条落在比较函数合成体内（font_metrics.rs:114、punctuation_model.rs:159、shaping_evidence.rs:39/41/66/68 实测），是引用了未生成的兄弟比较函数，与 E0432 compare 前缀 42 条同一谓词不一致（F4e 修复项；rustprobe r1 3.2.b 把这六条记入默认参数内联的修复范围，与位点形状不符，按位点改判）；UStringException 8（text_shaper.rs:176/185 等 Return 位 `Result<…, UStringException>`）与 SORTED_TABLE_COMPARE_STRINGS 2（parse_tex_hyphenation_patterns.rs:54/55 引 crate::runtime::sorted_table 常量）为模块未生成或未导出形态，假设与 F4k/F4i 同类（ts F3aq 与 dart F3am 记录同名 UString 问题），待证。修复项 F4l（org 加 region 加 count 60 条）；compare 6 条随 F4e；UStringException 加 SORTED_TABLE 10 条待证 |
| expected value, found module `self`（E0424） | 75 | 修复位置（rustprobe r1 3.1）：@:dataClass 构造器体里的 `this.<field>` 被输出成关联函数 `fn new` 内的 `self.<field>`，而关联函数没有 `self` 绑定（源 InlineObjectBoundaryAdjustment.hx:18-22 的构造器校验、生成 inline_object_boundary_adjustment.rs:21 实测；受害 Haxe 源另有 LayoutConstraints.hx、RichTextBackgroundPaint.hx、RichTextPaint.hx、LineBreaker.hx、LineBreakPlanningStage.hx、LineOptimization.hx、ParagraphDpLineBreaker.hx、ProgressiveBreakDecisions.hx、ContextualDashEllipsisRoleResolver.hx、ContextualQuoteRoleResolver.hx、TestTraceRecorder.hx 十一个，清单见报告 3.1）。修复项 F4m |
| unresolved import `X`（compare 前缀函数） | 42 | 判定完成（rustsem r1）：嵌套 record 的 compare 引用侧未校验共享谓词 canEmitDataClassComparator：引用生成段在 RustDecl.hx:333-337、:364-366、:391-393、:409-411、:469-470，谓词定义在 PolicyQueries.hx:163-192；定义侧判定不生成时引用侧仍输出 compare_X（样本 layout_input.rs:17 引 compare_paragraph_style、layout_result.rs:10 引 compare_line_box）。与 ts TS2724、dart F3ai 为同一谓词不一致的跨目标表现。修复项 F4e（排队） |
| method `X` has an incompatible type for trait: expected `X`, found `X` | 23 | 判定完成（rustsem r1）：接口 trait 声明（RustDecl.hx:87-102，:96 固定为 `&self`、返回类型不带 Result）与 impl 块签名（RustDecl.hx:291-321 经 instanceFuncDecl :1728-1738 按方法体可抛性写 `Result<…>`）不对齐；Haxe 无 checked exception，trait 声明没有可抛信息（display_glyph_substitution_engine_test_support.rs:265 等 23 处实测）。修复项 F4f（排队） |
| `X` cannot be sent between threads safely: `X` cannot be sent between threads safely | 834 | 仅 send 形状 5 条判定完成（rustsem r1）：moduleStaticVarDecl 默认分支（RustDecl.hx:1154-1157）无条件把 mutable static 包成 `Mutex<T>`，内层 `Rc<dyn Fn(&K,&K)->i32>`（RustType.hx:148）与无 Send 上界的 `Box<dyn Trait>`（RustType.hx:85-87）不满足 static 的 Sync 要求（english_hyphenation.rs:9 一条、prepared_paragraph.rs:37-40 四条实测）。修复项 F4g（排队，覆盖该 5 条）。census12 条数 5→834，早先「新增条目与该机制相同」的说法经 rustjudge r2 全量形状分解证伪：834 条分 18 种消息形状（couldn't convert the error 494、闭包 `?` 算子 137、trait bound 未满足 62、can't compare 两形 57＋34、not an iterator 13、cannot divide 12、send 5、其余 11 形合计 20，Σ=834），F4g 只覆盖 send 5 条，其余 829 条的逐形状判定由 rustjudge r3 执行 |
| method `X` has an incompatible type for trait: types differ in mutability | 5 | 判定完成（rustsem r1）：与 23 条同一生成路径的可变维度：isMethodMutating（RustDecl.hx:1857-1869）检测到方法体写自身字段后 impl 侧输出 `&mut self`（:1712-1717），trait 声明固定为 `&self`（:96）。修复项 F4f（与 23 条同一修复位置，排队） |
| unresolved import `X`: could not find `X` in `X`（tiqian_no_such_element_exception） | 3 | 判定完成（rustsem r1）：payload enum 与异常类声明在同一 Haxe 模块（TiqianNoSuchElementException.hx）时，preScan（Compiler.hx:818-820）形成自映射，generateFilesManually 的去重跳过（Compiler.hx:250-252）把异常类自己的模块整模块丢弃，文件不写、mod.rs 不登记。修复项 F4h（排队） |
| unresolved import `X`: could not find `X` in `X`（crate::std::functional） | 1 | 判定完成（rustsem r1）：std.Functional 是 extern 不产生模块（Compiler.hx:84），rust 目标 shim 清单（Compiler.hx:319-325 与 RustImports.hx:9-21）无对应项，sumOfFloat/forEach 也未进惯用展开层（RustExpr.hx:3896-3913 与 :4332；PipelineExpander.hx:852-855 只有 sortedBy 就地展开）。修复项 F4i（排队） |
| cannot find `X` in `X`（E0433 新增条目） | 14 | 判定分两支（rustprobe r1 3.4，census11 逐名核对分布不变：SortedMap 6、test_core 5、NodeFileSystem 2、tiqian_no_such_element_exception 1）：SortedMap 加 test_core 加 NodeFileSystem 13 条为 tiqian 生产模块引用只在测试支撑模块定义的名字（paragraph_shaping_stage.rs:61 与 replayable_font_backend.rs:40 引 SortedMap、prepared_paragraph.rs:556 引 test_core），测试模块被 `#[cfg(test)]` 条件编译排除后名字不再参与解析而暴露；修复位置在 tiqian 的 engine-haxe 源把生产模块的引用改指生产侧定义或把类型提升进生产模块，不在 boring 侧绕过，修复项 F4o；tiqian_no_such_element_exception 1 条（layout_queries.rs）与 E0432 同名 3 条（F4h）是同一模块未写出的连锁，随 F4h |
| expected function, found module `super`（E0423） | 1 | 判定完成（rustprobe r1 3.3）：@:dataClass 带继承的构造器 `super(Message(message))` 被原样输出成 `super(...)`（源 IllegalStateException.hx、生成 illegal_state_exception.rs:9 实测），Rust 无类继承、`super` 是父模块路径关键字，类继承加构造器 super 调用的 Haxe 语义在 rust 目标无法直接承载，属 AGENTS.md 第 34 条例外情形；修复须把此类类从 @:dataClass 构造器生成路径改到手工 impl 构造路径，任务书与报告写明所依赖的 Haxe 语义。修复项 F4n |
| mismatched types: expected `X`, found `X`（E0308） | 2083 | 计数最大的形状 198 条判定完成（rustjudge r2 第 3.1 节，档位修复位置）：Haxe 源 `LayoutInput.hx:21` 的 `textStyle == null ? new TextStyle() : textStyle` 经 `RustExpr.hx:503` coalescingNormalizationLines 与 `:201` coalescingDefaultText 物化默认构造，嵌套构造实参列表的生成路径（`RustExpr.hx:246`）不传既有的 asOption 形参，实参不带 Some 包装直接写出（生成 `layout_input.rs:43`），对 `text_style.rs:17` 的全 `Option<...>` 形参逐个不匹配；错误来源判定为 `74371c5a`（git show hunk 与该形状直接相交），VNull 双包装与递归装箱两候选证伪。修复项 F4p，修复已由 rustcoalesce 系列任务推进。其余形状：expected `f64` found integer 222、expected `u32` found `i32` 87 与反向 69、expected `Option<String>` found `String` 70、语句位收 `Result` 56＋55＋55、接口位收具体类缺 `Box::new` 55×3（clreq_profile.rs:24、bopomofo_parser.rs:22 实测）；类内全量形状分解的测量已由 rustjudge r1 交付并经派发方验收（209 种形状 Σ=2083），逐形状判定待 F4p 合并后 census13 重测再按新形状空间执行（当前判定会随修复失效） |
| no method or associated item named `X` found（E0599） | 701 | 四个消息子形 569 条已判（rustjudge r3 第 3 节，2026-09-08 验收）：clone 459 条修复位置（错误来源判定为 `74371c5a`：该提交在调用点对非 Copy 值读取统一追加 `.clone()`（`RustExpr.hx:3873-3882`），而这些结构没有拿到 `#[derive(Clone)]`，要求与供给不一致（r4 前置问题回答更正了 r3 的「放宽 derive 触发条件」表述：`RustDecl.hx:216-223` 的 `final hasCoalescingClone = true` 只把非 data-class 分支的来源记录条件换成常真，`@:dataClass` 结构走 `:223-225` 第二分支、仍被 `isAllClone(varFields)`（`:2274-2300`）拦住，见 F4q），`LayoutResult` 87、`LayoutInput` 77、`LineSolution` 54、`LineCandidate` 48、`LineBox` 39 等结构无 Clone impl，位点如 `layout_queries.rs:147:96`；`d4a43a33` 递归装箱与 `b74f9da9` VNull 双包装两候选证伪），开列修复项 F4q；关联常量 51 条（`BuiltInLayoutProfiles::BUILT_IN_LAYOUT_PROFILES_CLREQ_HORIZONTAL` 等，`RustExpr.hx:3644-3660` FStatic 静态字段映射成关联常量而实际声明是模块静态 `pub static`，built_in_layout_profiles.rs:5 实测）、`as_deref` on `Option<f64>`/`Option<u32>` 36 条（`RustExpr.hx:950-966` 字符串化分支对 null 类型统一发 `.as_deref().unwrap_or("")`，glyph.rs:40 实测）、Option 上 `to_string` 23 条（`RustExpr.hx:4167-4173` 把条件 null 分支直接字符串化成 `None.to_string()`，justifier.rs:168 实测）三组均为既有暴露（生成分支在 `3044bf91..a72f994d` 区间外已存在，错误位点由 `74371c5a` 的 coalescing 物化新引入；逐轮计数核对：census10 `rust-f64-check.log`/`rust-f32-check.log` 与 census11 `r64.log`/`r32.log` 的 E0599 计数均为 0，census12 为 701，显现全部为 census12 新增）。rustjudge r4 续判（2026-09-08 验收，诚实部分交付 26/398）：u32 上双重 `unwrap_or` 12 条（机制经派发方 2026-09-08 在 dartnull 检出 `9f0b52df` 逐行复核更正：两次追加都发生在局部声明渲染路径，`RustExpr.hx:611` 调用的 renderValueForType（定义 `:6281` 起）对标注 `Int` 局部经其 charCodeAt 桥追加第一个 `.unwrap_or(0)`，`:625`-`:631` 声明分支再追加第二个，不标注 `Null<Int>` 局部只吃声明分支一次、输出正确；`:3346`-`:3353` 算术 operand 分支只处理内联调用形、产出单 unwrap，不在此缺陷链上，rustjudge r4 早先把第二个追加记到该分支不属实；bopomofo_parser.rs:22 双后缀实测；判定为既有暴露，`3044bf91..a72f994d` 区间三笔 RustExpr 提交的 hunk 均不触及这些分支）、关联常量 `AUTO_SPACE_POLICY_DEFAULT` 14 条（`AutoSpacePolicy.hx:24` 的 `public static final Default` 经 `RustDecl.hx:1116-1170` 的 moduleStaticVarDecl 写成模块静态 `pub static LazyLock`，调用点却经 `RustExpr.hx:3640-3660` 的 FStatic 分支按 `AutoSpacePolicy::` 关联常量访问；与 51 条组同一机制，该组扩为 65 条；判定为既有暴露）两组并入。剩余 106 条（其余方法/trait 94、关联常量 12）未判 |
| this function takes N arguments but N was supplied（E0061） | 341 | 未判定（census12 新增）。data 表函数声明两个参数而调用只给一个参数（east_asian_spacing_data.rs:374 实测）。与构造器和函数签名因 coalescing 降级而减少参数、调用点未补实参相关，待判定 |
| can't call method `X` on ambiguous numeric type（E0689） | 93 | 未判定（census12 新增），rustjudge r2 已定位候选机制：`RustExpr.hx:201` coalescingDefaultText 的 CFloat 分支 f32 追加 `f32` 后缀、f64 不追加，无后缀整数字面量上调用 `to_ne_bytes`、`is_nan`（layout_queries.rs:538、annotation_geometry_stage.rs:305 实测）；f32 侧 83，f64 比 f32 多 10 条的文件分布（line_breaker.rs 多 2、paragraph_dp_line_breaker.rs 多 1、annotation_geometry_stage.rs 多 1、line_geometry_stage.rs 20 对 14）已核对，四文件 f64/f32 同位生成行对照由 rustjudge r3 完成后写入本行 |
| binary operation `==` cannot be applied to type `X`（E0369） | 69 | 未判定（census12 新增）。`==` 作用于 `TextRange`、`Fill` 等缺 PartialEq 实现（layout_queries.rs:1249、rich_text_background_paint.rs:58 实测），待判定 |
| no field `X` on type `Option<X>`（E0609） | 61 | 未判定（census12 新增）。`Option<Rect>` 上取 `.left`、`.top`（layout_queries.rs:181 实测），待判定 |
| cannot assign to `X`, which is behind a `&` reference（E0594） | 31 | 未判定（census12 新增）。`&` 引用后赋值 `self.call_count`（annotation_geometry_stage_coverage_test_support.rs:126 实测），待判定 |
| type `X` cannot be dereferenced（E0614） | 21 | 未判定（census12 新增）。对枚举 `ClreqStrictness` 解引用（justifier_engine_test_support.rs:74 实测），待判定 |
| use of moved value: `X`（E0382） | 13 | 未判定（census12 新增）。循环内使用已被移动的值（cluster_role_resolution.rs:89 实测），待判定 |
| use of unstable library feature `str_as_str`（E0658） | 11 | 未判定（census12 新增）。`str_as_str` 非 stable（layout_debug_assembly.rs:246 实测），待判定 |
| cannot index into a value of type `Option<Vec<f64>>`（E0608） | 11 | 未判定（census12 新增）。对 `Option<Vec<f64>>` 直接索引（layout_queries.rs:889 实测），待判定 |
| cannot borrow `X` as mutable, as it is not declared as mutable（E0596） | 11 | 未判定（census12 新增）。非 mut 声明被可变借用（explainable_stub_paragraph_layout_engine_test_support.rs:56 实测），待判定 |
| cannot move out of `X` which is behind a shared reference（E0507） | 9 | 未判定（census12 新增）。共享引用后移动 `self.points`（hyphenator.rs:70 实测），待判定 |
| method `X` is private（E0624） | 8 | 未判定（census12 新增）。`len` 为私有方法（layout_queries.rs:901 实测），待判定 |
| cannot apply unary operator `-` to type `u32`（E0600） | 5 | 未判定（census12 新增）。对 `u32` 取负（prepared_paragraph.rs:1686 实测），待判定 |
| non-exhaustive patterns: `X` not covered（E0004） | 5 | 未判定（census12 新增）。match 不穷尽（font_metrics.rs:141 实测），待判定 |
| type annotations needed（E0282） | 4 | 未判定（census12 新增）。`Option<T>` 无法推断（line_break_planning_stage.rs:371 实测），待判定 |
| cannot call non-const associated function in statics（E0015） | 4 | 未判定（census12 新增）。static 初始化器调用 `Fill::new`（rich_text_background_draw_style.rs:10 实测），待判定 |
| `f64` is a primitive type and therefore doesn't have fields（E0610） | 2 | 未判定（census12 新增）。对 `f64` 取字段（punctuation_geometry_ledger.rs:183 实测），待判定 |
| struct `X` has no field named `X`（E0560） | 1 | 未判定（census12 新增）。`CatalogImpl` 无 `faces` 字段（replayable_font_backend_coverage_test.rs:177 实测），待判定 |
| 合计（求和校验） | 4558 | 与 f64 错误总数相等；f32 4548（E0689 83，其余逐码与 f64 相同）。本行为 census12 复测值（`a72f994d`）；census11 复测值 247（`3044bf91`）；`d38459ab` 复测值 255；`d0df20db` 复测值 189 |

相对上一表已降为 0 并删除的行：unresolved import `X`: use of unresolved
module or unlinked crate `X`（mod.rs 对 `X_test` 模块的 pub use 行，F4d，
`d38459ab` 复测 108→0，census11 复核仍为 0，按删除制移除，进度见第 12 节）；
recursive type `X` has infinite size（E0072，F4j，rustmisc-r2 递归字段装箱
合并 `746742dd` 后 census12 复测 1→0，按删除制移除，进度见第 12 节）。

判定进度小结（2026-09-08 census12 复测，28 个错误码：既有 7 码中 6 码
判定保持、E0277 判定范围缩小；新增 20 码中 E0308 计数最大的形状与 E0599
四个消息子形已判，其余判定中）：解析层已清空（F3n 至 F3s 六项全部完成
删除）。既有错误码：E0432（46，compare 前缀 42 加
tiqian_no_such_element_exception 3 加 crate::std::functional 1）与 E0053
（28，即表中 23 与 5 两行）由 rustsem r1 判定为修复位置；E0277（834）
经 rustjudge r2 全量形状分解改为仅 send 形状 5 条属 F4g 机制，其余 829
条分 17 种消息形状（couldn't convert 494、闭包 `?` 137、trait bound 62
等，全表见该报告第 5 节）待逐形状判定；E0425（76）分四支：F4l 60 条、
随 F4e 6 条、假设待证 10 条；E0424（75）修复位置 F4m（修复任务
boring-f4m-r1 已交付并合并 `4644e29b`）；E0423（1）判定完成 F4n（条款 34 例外）；E0433
（14）分 F4o 13 条、F4h 连锁 1 条；E0072 已由 rustmisc-r2 修掉并删除。
census12 新增 20 码共 3484 条：E0308 计数最大的形状 198 条判定为修复
位置（rustjudge r2，错误来源判定 `74371c5a`，修复项 F4p 的修复任务
rustcoalesce r1 至 r4 已交付、末轮合并 `c38a359c`），其余形状待 census13
重测后按新形状空间再判（当前判定会随修复失效）；E0599 四个消息子形
569 条已判（rustjudge r3：clone 459 修复位置开列 F4q、关联常量 51、
`as_deref` 36、Option `to_string` 23 三组 110 条既有暴露）；r4 续判交付
26 条（u32 双重 `unwrap_or` 12 与关联常量 `AUTO_SPACE_POLICY_DEFAULT`
14，均既有暴露，见 E0599 行）；E0061、E0277、E0689 三码形状空间随 F4p
修复合并变化，判定排除待 census13。剩余未判 372 条（E0599 余 106、
E0369 69、E0609 61、E0594 31、十三个小码 105，Σ=372；早记「十三个
小码 167」为求和笔误，本轮更正）待续轮。rustjudge r1 至 r4 的验收历程
见第 12 节对应行。剩余既有判定工作是给 UStringException 8 加
SORTED_TABLE_COMPARE_STRINGS 2 共 10 条假设补因果（疑与 F4k/F4i 同为
模块未生成或未导出形态，可与 #93 的 haxe.Exception 跨目标立项合并
评估）。F4e 至 F4i、F4l 至 F4o 排队；F4l 要改的 DefaultArgExpander.hx
与 dartargs-r2 的文件冲突已随其合并解除、可以开分支，但 rust 侧回归的
复测（census13）优先于 F4l（回归修复合入前 F4l 的 60 条与新增 3484 条
出自同一个生成树，单独验收无法辨认）。

## 7 TypeScript 编译普查（2026-09-07 第三次复测）

轮次历史：首测（boring `7606ff85`、tiqian `f2517918`）1127 条、19 类（其中测量环境条目 308 条：TS2307 的 bun:test 与 @tiqian 模块名、TS2580 的 process 等，引擎侧 819 条）；census6 复测（`e01b03b3`）1127 条与首测逐类相同；`d0df20db` 复测 1004 条、16 类（F3e 覆盖的 TS2551 28 条与 TS2341 get_ 前缀 10 条降 0，TS2420、TS2693 两类降 0，TS2345 87→14、TS2322 8→2；TS2304 类内 Ic 103 条消失、org 2→108 条为新形态即 F3as）；按类型配置与模块映射复测 722 条：测量环境 300 条全部解析、TS2580 整类删除，新暴露引擎侧 19 条（TS2305 新增 18 条，TS2304 类内 compareFontMetricsRequest 1 条换骨架为 TS2552；TestCore 8 条改判引擎侧）；tsforce-r1 合并（`7c2a1c02`，合并 `908305a0`）后复测 714 条，TestCore 8 条降 0；census11 复测（`3044bf91`）706 条、16 类不变，逐名对照的两处变化都在
名称维度（TS2304 177→171：`pi` 4 与 `bi` 4 消失、count 系列重编号；
TS2451 23→21：`rubyIndex` 2 消失；与 kotlin conflicting 13→11、dart
DUPLICATE_DEFINITION 17→16 同为 Haxe 源构造 LayoutQueries.hx 重声明的
三目标联动），归于 knamefix-r8 的循环识别这一组提交，其余十四类计数
不变。本轮 706 条全部为引擎侧。

| 错误码：错误消息类（骨架） | 计数 | 判定与处置 |
|---|---:|---|
| TS2307：Cannot find module 'X' or its corresponding type declarations. | 6 | 模块分布见 7.2（第三次复测后测量环境的 bun:test、@tiqian、node 模块全部解析，本类只剩引擎侧条目）；6 条（相对路径 5 条与 haxe/Exception 1 条）已判引擎侧为 ts 生成器的导入路径问题，分支未逐条定位；转按修复位置派发 |
| TS2448：Block-scoped variable 'X' used before its declaration. | 215 | 已证实 ts 生成器（TsExpr 的语句融合与局部绑定生成顺序；LayoutDumpFormat.ts 单文件 214 条、ShapingEvidenceJson.ts 1 条，分布见 7.2） |
| TS2304：Cannot find name 'X'. | 171 | 已判 ts 生成器：org 名称 108 条为完整限定路径 `org.tiqian.…` 引用未导入（F3as，机制与位点见 7.2）；compare 前缀 6 条同 TS2724 的导出登记缺陷（compareFontMetricsRequest 1 条换骨架为 TS2552，见该行）；TestCore 8 条已由 tsforce-r1 修复降为 0（依据见节首）；名称分布见 7.2 |
| TS2554：Expected N arguments, but got N. | 133 | 已证实 ts 生成器：默认参数与可选参数的调用实参补全机制不完整（与区间形 54 条同一原因，两形合计 187 条） |
| TS2345：Argument of type 'X' is not assignable to parameter of type 'X'. | 14 | 已判 ts 生成器：枚举载荷假设经逐类判定证伪为主因（原假设为对象字面量不能赋给枚举类型，KinsokuLevelTest.test.ts:113 样本）；`d0df20db` 复测由 87 降为 14，余量在 PreparedParagraphJfTest.test.ts 7、KinsokuLevelTest.test.ts 4、LineOptimizationCoverageTest.test.ts 3，下降与 TS2304 类内枚举值改发限定路径同现，机制未逐条验证；TS2322 同组 |
| TS2554：Expected N-N arguments, but got N. | 54 | 同 TS2554 第一形（默认/可选参数补全机制不完整，两形合计 187 条） |
| TS2724：'X' has no exported member named 'X'. Did you mean 'X'? | 35 | 已证实 ts 生成器：compare 函数的导出与导入登记缺陷（名称分布见 7.2，35 个比较器名全列；与 TS2305、TS2304 的 compare 条目同源；dart UNDEFINED_FUNCTION 的 compare 前缀 41 条与本病同源已由 tdart2 r1 双侧证实，dart 侧机制见第 8 节 F3ai，ts 侧机制位置待定位） |
| TS2451：Cannot redeclare block-scoped variable 'X'. | 21 | 已证实 ts 生成器：局部作用域复用（alpha-renaming 的 index2 计数器；原跨文件重名假设已证伪；名称分布见 7.2；dart DUPLICATE_DEFINITION 的 Haxe 源同块 var 重声明 2 条与本病同源已由 tdart2 r1 双侧证实，dart 侧机制见 F3an）；census11 相对第四次复测 23→21（rubyIndex 2 条消失，归 knamefix-r8，见节首） |
| TS2341：Property 'X' is private and only accessible within class 'X'. | 4 | get_ 前缀 10 条属 F3e，`d0df20db` 复测降为 0（F3e 完成删除）；其余 4 条已判 ts 生成器为 private 可见性过度保留；名称与类分布见 7.2 |
| TS2339：Property 'X' does not exist on type 'X'. | 14 | 已判 ts 生成器为 Haxe Array.copy 与只读数组方法在 ts 侧的映射缺失（kind 6、copy 6、push 1、insert 1，分布见 7.2） |
| TS2322：Type 'X' is not assignable to type 'X'. | 2 | 同 TS2345 组（枚举载荷判定；余 2 条在 LineOptimizationCoverageTest.test.ts:26 与 :28） |
| TS2305：Module 'X' has no exported member 'X'. | 25 | compare 函数导出/导入登记缺陷（同 TS2724，7 条）加第三次复测新暴露的 runtime 模块导出缺失 18 条（`@tiqian/runtime` 的 UString 8、floatToI32 6、i32ToFloat 4，依据见节首；模块与名称分布见 7.2） |
| TS2367：This comparison appears to be unintentional because the types 'X' and 'X' have no overlap. | 6 | 已判 ts 生成器为枚举跨构造器相等比较未降级（Haxe 允许比较不同构造器并返回 false；PushInLineWideCapacityTestSupport.ts:30 样本） |
| TS2869：Right operand of ?? is unreachable because the left operand is never nullish. | 3 | 已判 ts 生成器为左操作数已判非空时仍保留 ??（LineRepair.ts:456 样本） |
| TS2552：Cannot find name 'X'. Did you mean 'X'? | 1 | compare 函数导出/导入登记缺陷（compareFontMetricsRequest @ FontMetrics.ts:84，同 TS2724；第二次复测时报 TS2304，类型定义装入后 tsc 给出拼写建议换为本骨架） |
| TS2540：Cannot assign to 'X' because it is a read-only property. | 2 | 已判 ts 生成器为只读字段生成策略错误（TestTraceStore.ts:53 与 :58 的 lines 字段） |
| 合计（求和校验） | 706 | 与错误总数相等（本轮为 census11 复测值（`3044bf91`）；前四轮为 1127、1004、722 与 714） |

判定进度小结（census11 复测后，706 条全部为引擎侧）：测量环境条目已随
第 2.2 节配方全部解析，现存 16 类全部归到 ts 生成器，涉及修复位置文件
TsExpr.hx、TsDecl.hx、TsImports.hx、Compiler.hx、TsRuntime.hx（逐类机制
清单见 tsprobe2 r1 报告）。已按修复位置开列的修复项：F3aq（runtime 模块
F3as（org 108 条，org108 r1 判定；修复任务 tsorg r2 已合并
`87255540`，条目待新基线复测后删除）。
谓词不一致构造的跨目标表现（tdart2 r1 与 rustsem r1 分别在两侧证实）。
剩余工作是按目标优先级派发 F3aq 与其余判定类的修复位置。

### 7.2 大类内部分解（产出命令见第 2.2 节）

2026-09-07 晚 `d0df20db` 复测重抽了 TS2304 与 TS2341 两张名称分布表并更新为本次值；TS2448、TS2451、TS2724、TS2339 各表本轮逐项核对与 2026-09-06 首测相同，仍标首测值；判定列已并入 tsprobe2 r1 的结论。同日第三次复测重抽
TS2307、TS2304、TS2305 三表并更新为本次值（测量环境模块名全部解析后，
TS2307 只剩引擎侧条目）。

TS2307 的模块分布（求和 6，第三次复测值）：

| 计数 | 模块名 | 判定 |
|---:|---|---|
| 3 | ./../../../runtime/SortedTable.ts | 已判 ts 生成器为导入路径问题（随第 7 节 TS2307 行） |
| 1 | ../../../../ts-gen/runtime/SortedTable.ts | 同上 |
| 1 | ../../../../ts-gen/org/tiqian/linebreak/LiangHyphenatorTest.ts | 同上 |
| 1 | ./../../../../haxe/Exception.ts | 同上 |

TS2304 的名称分布（求和 171，census11 复测值；Ic 103 条在 `d0df20db` 消失、
org 2→108 条为该轮新形态；compareFontMetricsRequest 1 条第三次复测起
换骨架为 TS2552；pi 4 条与 bi 4 条在 census11 消失、count 系列重编号，
归 knamefix-r8，见节首）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 108 | org | 已判 ts 生成器并定位机制（org108 探针，2026-09-08）：默认值展开保留的完整静态路径 `org.tiqian.core.Ic.Zero` 在 `TsExpr.hx:179` 进入 coalescingStaticFieldText（`TsExpr.hx:244-258`），`Context.getType` 对 abstract `Ic` 不返回 TInst，异常与非 TInst 都被吞掉后在 `:258` 原样返回完整路径，且该分支不调用 `imports.value`（正常静态引用路径在 `TsExpr.hx:1478-1479` 既输出短名又登记 import），生成文件没有 `org` 绑定，TS2304 落在首段 `org`；抽样四位点（AnnotationGeometryStageCoverageTest.test.ts:65、FontInstanceMetricsRequestTest.test.ts:31、LineBreakPlanningStageCoverageTestSupport.ts:42、LineBreakRepairEngineTestSupport.ts:46）全部同一机制，源头是 ParagraphStyle.hx:69 的 `blockIndent == null ? Ic.Zero : blockIndent` 默认值；形态切换的引入提交在 `7606ff85..d0df20db` 区间内检索没有找到对应提交（修复项 F3as） |
| 33 | kind | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 5 | region | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；与 rust E0425 的 region、kotlin 3.4 节 region 同为 @:dataClass 默认参数内联形参泄漏这一构造，rustprobe r1 跨目标对照） |
| 3 | text | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；同 region 行的跨目标同一构造假设） |
| 3 | __functional_shim | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 2 | SortedMap | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 2 | NodeFileSystem | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 2 | count7 | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；census11 重编号新名） |
| 2 | count27 | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；census11 重编号新名，原 count25） |
| 2 | count26 | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 2 | count12 | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；census11 重编号新名，原 count11） |
| 1 | count | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定） |
| 1 | cornerRadius | 已判 ts 生成器（随第 7 节 TS2304 行的分组判定；同 region 行的跨目标同一构造假设） |
| 1 | compareShapingEvidenceKey | 已证实 ts 生成器：compare 函数导出/导入登记缺陷（同 TS2724） |
| 1 | compareRecordedShapingResult | 同上 |
| 1 | compareRecordedFontMetrics | 同上 |
| 1 | compareMetricsEvidenceKey | 同上 |
| 1 | compareGlue | 同上 |

TS2448 的文件分布（求和 215）：LayoutDumpFormat.ts 214 条（行 90 至 398
间）、ShapingEvidenceJson.ts 1 条（:546）。

TS2451 的名称分布（求和 21，census11 复测值）：index 6、_g 5、row 4、
parseHexCode 2、inkTop 2、inkBottom 2。rubyIndex 2 条在 census11 消失
（归 knamefix-r8，见节首）；TS2448、TS2724、TS2339 三表
计数在 census11 不变，仍标旧轮值。

TS2341 的名称与类分布（求和 4，`d0df20db` 复测值；get_ 前缀 10 条属 F3e，
已随修复降为 0，对应五行删除）：

| 计数 | 属性（所属类） | 判定 |
|---:|---|---|
| 1 | strongScriptRole（ContextualQuoteRoleResolver） | 已判 ts 生成器为 private 可见性过度保留 |
| 1 | pairByOpen（ContextualQuoteRoleResolver） | 同上 |
| 1 | emptyHanging（LineCandidate） | 同上 |
| 1 | codePointLengthAt（ContextualQuoteRoleResolver） | 同上 |

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

TS2305 的模块与名称分布（求和 25，第三次复测值）：`@tiqian/runtime` 的
UString 8、floatToI32 6、i32ToFloat 4（runtime 模块导出缺失，依据见第
7 节节首）；./TextStyle.ts 的 compareTextStyle 2 条，./Size.ts 的
compareSize、./LineBox.ts 的 compareLineBox、./InlineBoxSpan.ts 的
compareInlineBoxSpan、./GlyphRun.ts 的 compareGlyphRun、./Cluster.ts 的
compareCluster 各 1 条。

TS2339 的名称分布（求和 14）：kind 6、copy 6、push 1、insert 1。

TS2551 全类 28 条（全部 get_strategyName）已随 F3e 修复降为 0，名称分布
表删除（进度见第 12 节 tsgetcal-r6 行）。

## 8 Dart 编译普查（2026-09-08 census12 复测）

轮次历史（gen 与 tests 合计）：首测 2026-09-06（boring `31627b5c`、tiqian `17a646da`）2931 条、35 个错误码；`e01b03b3` 复测 2606 条、33 码（knullinit 守卫把 UNCHECKED 420→143、dartifget 两码降 0）。判定来源：探针 T-dart r1 与 tdart2 r1（五类升修复位置、三处跨目标同源证实）。修复轮：dartguard r1 至 r6（F3l 全部、F3m 至残余 13 条，
`f42c38c9`、`18d5d8d1`、`e4952dab`、`b4b574b5`）、dartstd-r2 合并
`c629b1d1`（URI_DOES_NOT_EXIST 36→2，同笔新暴露 13 条进入各自错误码
判定队列）、fph32-r1 合并 `014d9640`（UNDEFINED_FUNCTION 58→46）、
dunitsurf-r2 合并 `fc2b53b6`（dart 运行时崩溃消除、test:dart 链首次走到
analyze 步；净增 32 条为 charCodeAt 可空结果流入非空 Int 语境：
ARGUMENT_TYPE +17、UNCHECKED +14、RETURN_OF_INVALID +1，开列 F3at）、
census11（`3044bf91`）1695 条、census12（`a72f994d`）1594 条（唯一变动
NOT_ENOUGH_POSITIONAL_ARGUMENTS 105→4，F3ah 经 dartargs-r2 修复生效，
残余 4 条的按构造器名分布未逐条抽取）。

F3at 的修复与验证：dart 侧修复 `819f6d3a` 在消费树 A/B 实测中使三个错误码分别降为 170→153、26→12、2→1，差值与 F3at 的新增数一致，其余错误码保持稳定。后续补齐跨目标非空断言与 rust 双 `unwrap_or` 去重（`7994eceb`），相关提交已合并 `b822afee` 进入 boring main 并推送，待新基线复测核销。

dunitsurf-r3 的 URI 回归（census11 实测明细）：`db0f713a` 把 resident
模块并入合并 runtime 库，消费配置下不再单独写出 runtime/ 目录（census10
树 dart-gen/lib/runtime/ 实测有 sorted_table.dart 与 string_tools.dart，
census11 树只剩 haxe、org、std 三目录），四处对 runtime/sorted_table.dart
的 import 断链报 URI_DOES_NOT_EXIST（生成侧 liang_hyphenator.dart:3、
parse_tex_hyphenation_patterns.dart:3、parsed_tex_hyphenation.dart:2，
测试侧 liang_hyphenator_test.dart:7）；已写出文件内的 `_codePointAt` 4
条随文件不再写出而消失；parse_tex_hyphenation_patterns.dart:99 的两条
与 liang_hyphenator_test.dart:56 的返回位一条因 import 不可解析、类型
检查未到达错误位而不再报（掩蔽，import 恢复后错误会回来）。`bi`、
`rubyIndex`、可空 for-in 迭代子新条归 knamefix-r8 的循环识别（未逐笔
核对）。F3i 修复位置随合并 runtime 库机制重判。

| 错误码 | gen | tests | 合计 | 判定与处置 |
|---|---:|---:|---:|---|
| `UNDEFINED_IDENTIFIER` | 212 | 64 | 276 | 名称分布见 8.2（58 个名字全列，census11 复测）；类内全部类型名条目（2026-09-07 复测判定的 8 个名字合计 705 条，与其余类型名条目 FontMetricSource 12、InteriorPunctuationStyle 5、CjkPunctuationGlyphPolicy 5、AutoSpaceMode 4、LineEndPunctuationStyle 3、KinsokuLevel 3、HangingPunctuationStyle 2 和六个单条名字）已随 F3l（dartguard r1 至 r6，提交号见第 12 节）降为 0，逐笔提交与名字的对应未逐条验证；残余 276 条全部为局部名与测试支持类名，未判定 |
| `REFERENCED_BEFORE_DECLARATION` | 314 | 96 | 410 | 形状证实：抽样含导入前缀与局部名同名冲突（cluster_role_resolution.dart:55 生成 `final cluster = cluster.Cluster(...)`）与不带前缀的类名（:64 的 `ResolvedClusterRange`）两形；探针引用的 Compiler.hx:216-220 经派发方复核是测试函数排序，与样本不吻合，已否证；layout_dump_format.dart 215 条与 ts TS2448 同源的假设保留（ts 侧 TS2448 已判生成器，本码随 T-dart 第二轮复核）；文件分布见 8.2（与首测逐项相同）；机制位置待定位；随 T-dart 第二轮 |
| `ARGUMENT_TYPE_NOT_ASSIGNABLE` | 170 | 118 | 288 | 假设：可空 int? 给 int（codeUnitAt 闭包位），连可空守卫（F3m 同构造）；目标类型分布见 8.2（23 种全列，该表数值取自首测日志）；F3at 的 charCodeAt 结果 `int?` 给 `int` 形参 17 条（clreq_punctuation_policies.dart:35:37 实测，修复已合并待 census13 复测）；dartstd-r2 期新增的 SortedMapTable 两条现为 import 断链掩蔽（见节首 URI 回归段）；double 67 条是否数值转换待抽样；随 T-dart 第二轮 |
| `UNCHECKED_USE_OF_NULLABLE_VALUE` | 26 | 2 | 28 | 构成三部分：F3m 残余 13 条（修复任务 dartguard r1 至 r6 的提交号见第 12 节；残余逐文件分布：生成侧 ParagraphStyle 1、Justifier 3、LineBreakPlanningStageCoverageTestSupport 2、LineRepair 2、PunctuationGeometryLedger 3，测试侧 FontPolicyCoverageTest 1、TextShaperCoverageTest 1）、F3at 的 charCodeAt 可空结果比较运算 14 条（clreq_punctuation_advance_policy.dart:27:12 实测，修复已合并待 census13 复测）、可空 for-in 迭代子 1 条（line_repair.dart:79，knamefix-r8 循环改写后新暴露、待归面）；r6 同期实验 `cd34ca32` 扩大断言面使总数回归 1755，已整笔回退，不得原样重试 |
| `NOT_ENOUGH_POSITIONAL_ARGUMENTS` | 1 | 3 | 4 | 修复位置（tdart2 r1）：coalescing 内层构造的省略实参没有补全。调用点经 `DartExpr.hx` 的 `completeCoalescingCallArgs`（e01b03b3 位于 235-244，派发方复核），它传给 `omittedCallDefaults` 的只有模块路径与方法名，内层构造的类名被丢弃；`omittedCallDefaults`（packages/compiler/DefaultArgExpander.hx:1534-1578）用 `Context.getType(modulePath)` 解析且只认 TInst，模块无同名主类型（PunctuationModel.hx 的 PunctuationAtomBuilder）或主类型是接口（GreedyLineBreaker、LruWidthIndependentAnnotationCache）时返回 null，省略实参不填充，调用点渲染零参而构造声明要求参数（声明侧 DartDecl.hx:838-888 只把带默认值的参数排进可选组，且按字段名匹配的判定对构造参数名不成立）。修复项 F3ah（修复任务 dartargs 经 r1 与 r2 交付，合并 `a72f994d`；census12 复测全类 105→4（生成侧 71→1、测试侧 34→3），census11 的按构造器名计数 PunctuationAtomBuilder.new 56、GreedyLineBreaker.new 39、LruWidthIndependentAnnotationCache.new 10 对应修复前分布，残余 4 条的按构造器名分布未逐条抽取） |
| `PREFIX_SHADOWED_BY_LOCAL_DECLARATION` | 32 | 42 | 74 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_METHOD` | 58 | 11 | 69 | 形状证实（T-dart r1 抽样读过生成代码）；接收类型为 List 的 23 条保持 Haxe 数组方法名生成到 dart 的 List 接收者的假设；新增 `toDouble @ bool` 形 5 条的原因没有查明（gen 侧，2026-09-07 复测新增）；dartstd-r2 合并（`c629b1d1`）后生成侧 62，新增 4 条为新写出的 runtime/sorted_table.dart 内 `_codePointAt` @ `SortedTable`（未判定）；census11 生成侧 62→58，`_codePointAt` 4 条随 runtime/sorted_table.dart 不再写出而消失（dunitsurf-r3 的 `db0f713a`，见节首 URI 回归段）；方法与接收类型分布见 8.2（24 对全列，census11 复测）；机制位置待定位；随 T-dart 第二轮 |
| `EXPECTED_TOKEN` | 56 | 0 | 56 | 形状证实：非法 `int??` 双问号类型渲染（cjk_font_role_classifier.dart:23-24 生成 `final int?? l` 实测）；与 MISSING_ASSIGNABLE_SELECTOR、ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE、MISSING_IDENTIFIER、DOT_SHORTHAND_MISSING_CONTEXT 四码共享同一形状，五码文件分布重叠；期待符号分布：缺分号 49、缺右括号 4、缺冒号 2、缺右花括号 1（与首测相同）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_FUNCTION` | 46 | 0 | 46 | 修复位置分三个分支（tdart2 r1，名称分布见 8.2）：compare 前缀 41 条，是否生成比较函数的判定与引用侧不一致：判定函数 `canEmitDataClassComparator`（packages/compiler/PolicyQueries.hx:163-171）经 `isDataClassFieldKey`（:173-192）只认 Int、enum、String、dataClass 与其可空/只读数组包装，含 Bool 或 Float 字段的数据类不生成比较函数，而引用侧 DartDecl.hx 的 NullableArray 与 PlainField 分支（e01b03b3 位于 :311-312 与 :326）只复查 `:dataClass` meta、不复查是否生成的判定，引用照发（修复项 F3ai；与 ts TS2724/TS2305 同源证实）；mkdirSync 与 writeFileSync 各 1 条，测试 extern 的静态成员在调用点降级为不带限定名的名字（DartExpr.hx:1605-1606 走 fail 分支的调用点形状），定义不随 tests 产物目录写出（修复项 F3ak）；floatToI32 7 条加 i32ToFloat 5 条已随 F3aj（fph32-r1，见第 12 节）降为 0；dartstd-r2 期新增 justifier.dart 的 `sumOfFloat` 1 与 `forEach` 2（未判定，8.2 表已补两行） |
| `MISSING_ASSIGNABLE_SELECTOR` | 49 | 0 | 49 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；机制位置待定位；随 T-dart 第二轮 |
| `ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE` | 49 | 0 | 49 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_PREFIXED_NAME` | 22 | 22 | 44 | 修复位置分两个分支（tdart2 r1；名称分布按 dartstd-r2 合并态实测：UString 21（生成侧 6、测试侧 15）、DefaultHyphenator 15（生成侧 8、测试侧 7）、PunctuationGluePlacements 6、SortedMap 2）：DefaultHyphenator 加 PunctuationGluePlacements 21 条，`DartExpr.hx` 的 `coalescingStaticCallText`（e01b03b3 位于 246-258，派发方复核）把静态调用渲染成类限定引用，没有 `staticRef`（:1619 起）对 statics-only 类去类名的降级路径（修复项 F3al）；UString 21 条，std.UStringRT 的成员走运行时限定渲染 `runtime.UString.成员`（DartExpr.hx:1607-1608 一带），但运行时模块的拼接（dartcompiler/Compiler.hx:388-396）只追加 parts 非空的 resident，tiqian 的 engine-haxe/targets/classes.hxml 没有任何 `runtime.*` 清单条目（boring examples/dart.hxml 带 `runtime.UString` 等条目），std.UStringRT 又是 extern 不产生 parts，定义与引用两侧都落空（修复项 F3am；dartstd-r2 合并 `c629b1d1` 后 runtime.dart 已写出但其中 UString 出现 0 次，extern 不产生 parts 的落空机制不变，修复位置不变）；SortedMap 2 条为 dartstd-r2 合并后新增（paragraph_shaping_stage.dart:49 与 replayable_font_backend.dart:40 经前缀 sorted_map 引用），std/sorted_map.dart 已写出但为仅含生成头注释的空壳文件（实测 1 行），名字仍未定义，与 F3am 的 extern 空壳构造同类（未逐条验证因果） |
| `URI_DOES_NOT_EXIST` | 3 | 3 | 6 | F3i（dartstd-r2 主体修复，提交号见第 12 节）在 census11 部分回归后的现状：生成侧 3 条与测试侧 sorted_table 1 条为合并 runtime 库机制的 import 断链（见节首 URI 回归段）；测试侧 test_host.dart（main.dart:6）与跨目录 liang_hyphenator_test.dart（line_break_coverage_test.dart:8）两条为 dartstd-r2 期残余，写出条件的不一致尚未定位；路径明细见 8.2（census11 重抽）；修复位置随合并 runtime 库机制重判 |
| `READ_POTENTIALLY_UNASSIGNED_FINAL` | 36 | 0 | 36 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `MISSING_IDENTIFIER` | 27 | 0 | 27 | 形状证实：非法 `int??` 双问号类型渲染（与 EXPECTED_TOKEN 共享形状，五码文件分布重叠）；dartguard 合并后 27|0，较首测 34|1 少 8 条，减少的 8 条与哪笔修复对应未逐条查明；机制位置待定位；随 T-dart 第二轮 |
| `INVOCATION_OF_NON_FUNCTION_EXPRESSION` | 0 | 31 | 31 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `DOT_SHORTHAND_MISSING_CONTEXT` | 27 | 0 | 27 | 形状证实：非法 `??` 双问号类型渲染（annotation_geometry_stage.dart:165 生成 `ClusterGeometryDecisionInfo?? g` 实测；与 EXPECTED_TOKEN 共享形状）；机制位置待定位；随 T-dart 第二轮 |
| `DUPLICATE_DEFINITION` | 16 | 1 | 17 | 修复位置分四个分支（tdart2 r1）：int?? 双问号类型的连锁错误 10 条，并入第 8 节既有 `??` 双问号五个错误码的连锁条目，不独立立项；同名合成临时变量 5 条（line_geometry_stage.dart:234-246 三个 `_g`、line_adjustment_stage.dart:392 与 :471 的 `index`，`DartExpr.hx` 的 localName（e01b03b3 位于 3498 起）对命名临时变量原样输出、同块不去重）加 Haxe 源同块 var 重声明 2 条（layout_queries.dart:641 与 :671 的 `rubyIndex`，源 LayoutQueries.hx:584/:597，TS2451 同源证实）合计 7 条（修复项 F3an）；extension type 的表示字段与成员同名 1 条（ic.dart:5 `extension type Ic(double count)` 里 `count()` 与表示字段 `count` 同名，DartDecl.hx 的 valueTypeDecl 取第一个构造参数名为表示字段，e01b03b3 位于 422-431）（修复项 F3ao；`rubyIndex` 两条降一条归 knamefix-r8，三目标联动见节首） |
| `PREFIX_COLLIDES_WITH_TOP_LEVEL_MEMBER` | 5 | 6 | 11 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `MISSING_DEFAULT_VALUE_FOR_PARAMETER` | 11 | 0 | 11 | 形状证实：非空参数的隐式默认值为 null（ClreqProfile 可选参数实测）；探针引用的 DartDecl.hx:260-300 经派发方复核落在比较函数合成代码内，与参数签名不吻合，定位存疑；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_ENUM_CONSTANT` | 8 | 0 | 8 | 形状证实：枚举构造器名空串或保留字（unicode_punctuation_boundary_resolver.dart:208-219 生成 `Dir.final` 实测，final 是 dart 保留字）；机制位置待定位；随 T-dart 第二轮 |
| `NOT_INITIALIZED_NON_NULLABLE_INSTANCE_FIELD` | 4 | 0 | 4 | 修复位置（tdart2 r1）：`DartExpr.hx` 的 `coalescedBodyFields`（e01b03b3 位于 523-553，派发方复核）只扫构造函数顶层语句里的 `this.x = …` 赋值，if/else 分支体里的守卫赋值（line_breaker.dart:28 的 `_kinsoku` 等四字段，源 LineBreaker.hx:50-57）不被收集，字段声明侧 DartDecl.hx:639-643 因此不标 `late`。修复项 F3ap |
| `NON_EXHAUSTIVE_SWITCH_STATEMENT` | 4 | 0 | 4 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_OPERATOR` | 3 | 0 | 3 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `INVALID_ASSIGNMENT` | 3 | 0 | 3 | 形状证实：dart 侧赋值位没有 int 到 double 的转换（line_adjustment_stage.dart:148、:151、:159 生成 `visualWidth = (visualWidth).round()` 实测，与 kotlin F3j 的赋值位同构造；首测 7 条，本次复测 3 条的下降原因未单独查明）；机制位置待定位；随 T-dart 第二轮 |
| `IMPLICIT_THIS_REFERENCE_IN_INITIALIZER` | 3 | 0 | 3 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `RETURN_OF_INVALID_TYPE` | 2 | 0 | 2 | 形状证实（T-dart r1 抽样读过生成代码）；F3at 的 charCodeAt 结果 int? 处于返回 Int 的返回位 1 条（修复已合并待 census13 复测）；测试侧 liang_hyphenator_test.dart:56 的 `SortedMapTable<String, dynamic>` 返回位 1 条现为 import 断链掩蔽（见节首 URI 回归段）；机制位置待定位；随 T-dart 第二轮 |
| `LIST_ELEMENT_TYPE_NOT_ASSIGNABLE` | 0 | 2 | 2 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `RETURN_OF_INVALID_TYPE_FROM_CLOSURE` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `NON_TYPE_AS_TYPE_ARGUMENT` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `INSTANCE_MEMBER_ACCESS_FROM_STATIC` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `EXTRA_POSITIONAL_ARGUMENTS` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `CONFLICTING_METHOD_AND_FIELD` | 1 | 0 | 1 | 形状证实（T-dart r1 抽样读过生成代码）；机制位置待定位；随 T-dart 第二轮 |
| `UNDEFINED_CLASS` | 1 | 0 | 1 | 形状证实：dartstd-r2 合并（`c629b1d1`）后新增，traced_assertions.dart:651 引用类名 'Exception'（生成代码对 haxe.Exception 的 dart 侧引用）；机制位置待定位；随 T-dart 第二轮 |
| 合计（求和校验） | 1193 | 401 | 1594 | 与错误总数相等；本行为 census12 复测值（`a72f994d`）；census11 复测值 1695（`3044bf91`）；`d38459ab` 复测值为 1702，fph32-r1 合并（`2382140b`，合并提交 `014d9640`）后为 1670，dartguard-r6 合并态（`b4b574b5`）为 1682，dartstd-r2 合并态（`c629b1d1`）为 1686，dartguard r4 合并态（`e4952dab`）为 1707，r3 合并态为 1739，首测与 2026-09-07 复测值为 2931 与 2606 |

相对首测计数已降为 0 并从表内删除的错误码：UNDEFINED_GETTER（32 条，
dartifget boring `14c5031d`）、NON_ABSTRACT_CLASS_INHERITS_ABSTRACT_MEMBER
（6 条，随同修复降为 0）。

判定进度小结（2026-09-08 census12 复测；8.2 各表仍标各自标注轮次）：
定位到修复位置的错误码 8 个：UNCHECKED_USE_OF_NULLABLE_VALUE（F3m 残余
13 条；另有 F3at 的 14 条与 census11 新增可空 for-in 迭代子 1 条归
knamefix-r8 循环改写、待归面；dartguard r1 至 r6 已交付合并）、
URI_DOES_NOT_EXIST 6 条（F3i，修复位置随合并 runtime 库机制重判，见
节首 URI 回归段）、NOT_ENOUGH_POSITIONAL_ARGUMENTS 4 条（F3ah 残余）、
UNDEFINED_FUNCTION 46 条（F3ai 41、F3ak 2、dartstd-r2 后新增未判定 3；
F3aj 的 floatToI32 7 加 i32ToFloat 5 已由 fph32-r1 修复降 0）、
UNDEFINED_PREFIXED_NAME 44 条（F3al 21、F3am 21、SortedMap 2 未归类）、
DUPLICATE_DEFINITION 17 条（10 条并入 `??` 双问号连锁条目、F3an 6、
F3ao 1）、NOT_INITIALIZED_NON_NULLABLE_INSTANCE_FIELD 4 条（F3ap）；
ARGUMENT_TYPE_NOT_ASSIGNABLE 与 RETURN_OF_INVALID_TYPE 各自的
charCodeAt 新增部分（+17 与 +1）为 F3at，修复已合并 `b822afee`、待
census13 复测删除；UNDEFINED_IDENTIFIER 类内类型名条目（F3l）已由
dartguard 降为 0，该错误码残余 276 条全部为局部名与测试支持类名，回到
未判定档；UNDEFINED_METHOD 的 compareTo 形 9 条由 NullableScalar 分支
渲染 `.compareTo` 解释，预期随 F3ai 消除，不预先承诺计数。探针定位待
因果验证这一档已没有条目；其余 25 类为形状证实或假设，其中
EXPECTED_TOKEN、MISSING_ASSIGNABLE_SELECTOR、
ILLEGAL_ASSIGNMENT_TO_NON_ASSIGNABLE、MISSING_IDENTIFIER、
DOT_SHORTHAND_MISSING_CONTEXT 五码合计 208 条共享非法 `??` 双问号类型
渲染形状，是形状证实里计数最大的一组。T-dart 第二轮的剩余工作是给
形状证实类定位机制位置、证实或否证其余跨目标假设
（ARGUMENT_TYPE_NOT_ASSIGNABLE 的 double 67 条是否数值转换、
UNDEFINED_METHOD 新增 `toDouble @ bool` 5 条的原因查明都在其列）。

### 8.2 大类与中类内部分解（census11 部分重抽，产出命令见第 2.2 节）

UNDEFINED_IDENTIFIER、UNDEFINED_METHOD 与 URI_DOES_NOT_EXIST 三张表按 census11 复测数据重新抽取（2026-09-08）：UNDEFINED_IDENTIFIER
删去名字 `bi` 的行（4 条随 knamefix-r8 消失），其余 58 个名字与上一轮
逐项相同；UNDEFINED_METHOD 删去 `_codePointAt` @ `SortedTable` 行（4 条
随 runtime/sorted_table.dart 不再写出而消失），其余 24 对逐项相同；URI
表为断链后的 6 条现值。UNCHECKED_USE_OF_NULLABLE_VALUE 表仍标
dartguard r3 合并态（boring `f9b446df`，31 条未重新按形状分桶；census11 现值 28 条见第 8 节该行，含 F3at 的 14 条与 for-in 新增 1 条）。其余各表仍基于 2026-09-07 复测数据（boring `e01b03b3` 态）：其中 ARGUMENT_TYPE_NOT_ASSIGNABLE 表（23 种全列）
对应生成侧首测值 172，其后的下降未重新逐条抽取。
UNDEFINED_PREFIXED_NAME 的名称分布仍标 dartstd-r2 合并态（`c629b1d1`）。

UNDEFINED_IDENTIFIER 的名称分布（求和 276，census11 复测值；dartguard 把
类型名条目降为 0 后，残余全部为局部名与测试支持类名，判定列全部未判定；
带「测试侧」标记的四个名字合计 64 条来自测试日志，其余 54 个名字合计
212 条来自生成日志；`bi` 4 条在 census11 消失，归 knamefix-r8 循环
识别这一组提交）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 33 | `kind` | 未判定（测试侧） |
| 15 | `PunctuationGeometryStageCoverageSupport` | 未判定（测试侧） |
| 13 | `JustifierTestSupport` | 未判定（测试侧） |
| 12 | `plan` | 未判定 |
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
| 5 | `halt` | 未判定 |
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
| 3 | `text` | 未判定（测试侧） |
| 3 | `strongReason` | 未判定 |
| 3 | `startPrior` | 未判定 |
| 3 | `role` | 未判定 |
| 3 | `prevKind` | 未判定 |
| 3 | `naturalPrior` | 未判定 |
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
| 2 | `fivePowers` | 未判定 |
| 2 | `center` | 未判定 |
| 1 | `twoPowersBuilder` | 未判定 |
| 1 | `fivePowersBuilder` | 未判定 |
| 1 | `enUsCache` | 未判定 |
| 1 | `count` | 未判定 |

UNCHECKED_USE_OF_NULLABLE_VALUE 的形状分布（求和 31，生成侧 28 条与
测试侧 3 条合并，r3 合并态计数；消息里的名字以 X 代替；knullinit 系列
的 dart 侧守卫（boring `9e0537d0`，合并 `23f4bf63`）已修掉 property 形的
314 条，修复任务 dartguard 的可空接收者守卫（`b5bed1e3`，合并
`f42c38c9`）又修掉 112 条，残余 31 条的修复位置仍是 dart 可空接收者守卫
缺失（F3m，与 kotlin 修复位置 A 同构造），逐条三件套由 dartguard r4
补齐；r4 合并（`e4952dab`）后残余 17 条，见第 8 节该行）：

| 计数 | 形状 | 判定 |
|---:|---|---|
| 6 | The method 'X' can't be unconditionally invoked because the receiver can be 'null'. | F3m（生成侧 5、测试侧 1；r3 合并态计数） |
| 3 | The property 'X' can't be unconditionally accessed because the receiver can be 'null'. | 同上（生成侧 1、测试侧 2；首测 314 条已由 boring `9e0537d0` 修复） |
| 16 | The operator 'X' can't be unconditionally invoked because the receiver can be 'null'. | 同上（全部生成侧） |
| 6 | A nullable expression can't be used as a condition. | 同上（全部生成侧） |

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

ARGUMENT_TYPE_NOT_ASSIGNABLE 的目标类型分布（求和 290，24 行全列；消息
形如 The argument type 'X' can't be assigned to the parameter type 'Y'，
本表按 Y 计；T-dart 抽样为可空 int? 给 int，连可空守卫 F3m；double 67 条
是否数值转换待第二轮抽样；double 与 num 两形状相对首测的下降原因未单独
查明）：

| 计数 | 目标类型 | 判定 |
|---:|---|---|
| 70 | `List<Cluster>` | 未判定 |
| 67 | `double` | 未判定 |
| 40 | `List<EastAsianSpacingEdges>` | 未判定 |
| 37 | `int` | 未判定 |
| 24 | `String` | 未判定 |
| 16 | `num` | 未判定 |
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

UNDEFINED_METHOD 的方法与接收类型分布（求和 69，24 对全列，census11
复测值，记法为方法 @ 接收类型；`_codePointAt` @ `SortedTable` 4 条随
runtime/sorted_table.dart 不再写出而消失（dunitsurf-r3 的 `db0f713a`），
其余各对与 dartstd-r2 期逐项相同；`toDouble` @ `bool` 形 5 条为
2026-09-07 复测新增，原因没有查明；compareTo 形 9 条由 NullableScalar
分支对非 Comparable 数据类实例渲染 `.compareTo` 解释
（DartDecl.hx:279-281 一带，tdart2 r1），预期随 F3ai 的修复消除，计数在
合并复测后重数）：

| 计数 | 方法与接收类型 | 判定 |
|---:|---|---|
| 13 | `Cluster` @ `Function` | 未判定 |
| 10 | `emptyF` @ `PunctuationGeometryLedger` | 未判定 |
| 6 | `copy` @ `List` | Haxe 数组方法名生成到 dart 的 List 接收者的假设 |
| 5 | `toDouble` @ `bool` | 未判定（2026-09-07 复测新增形，原因没有查明） |
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
| 1 | `compareTo` @ `RubyLineHeightDecisionInfo` | NullableScalar 渲染 `.compareTo`，预期随 F3ai 消除（tdart2 r1） |
| 1 | `compareTo` @ `MaxLinesDecisionInfo` | 同上 |
| 1 | `compareTo` @ `LineSpacingDecisionInfo` | 同上 |
| 1 | `compareTo` @ `LineRepairDecisionInfo` | 同上 |
| 1 | `compareTo` @ `LineLengthGridDecisionInfo` | 同上 |
| 1 | `compareTo` @ `LineCandidate` | 同上 |
| 1 | `compareTo` @ `KinsokuDecisionInfo` | 同上 |
| 1 | `compareTo` @ `InlineObjectLineHeightDecisionInfo` | 同上 |
| 1 | `compareTo` @ `FirstLineIndentDecisionInfo` | 同上 |

UNDEFINED_FUNCTION 的名称分布（求和 46，消息全部为 The function 'X'
isn't defined.；末两行为 dartstd-r2 合并后新增；floatToI32 7 条与
i32ToFloat 5 条已由 fph32-r1（`2382140b`，合并 `014d9640`）修复，两行
删除）：

| 计数 | 名称 | 判定 |
|---:|---|---|
| 2 | `compareTextStyle` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 2 | `compareFontMetricsRequest` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 2 | `compareRawFontMetrics` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareAutoSpacePolicy` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareAdjustmentStylePolicy` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `comparePunctuationWidthPolicy` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareBopomofoGlyphPlacement` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareMetricDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareClusterGeometryDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareAutoSpaceDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareRubyDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareShapingDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `comparePunctuationDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareSpacingDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareJustificationDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLineEdgeTrimDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareDecorationDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareDecorationSegmentInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareInlineBoxDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareInlineObjectDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareInlineObjectPunctuationAttachmentDecisionInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareParagraphStyle` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLayoutConstraints` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareInlineBoxSpan` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareInlineObjectSpan` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareSize` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareCluster` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareGlyphRun` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLineBox` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLineRepairCandidateInfo` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLayoutFontMetrics` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareLineCandidate` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareRepairCandidate` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareGlue` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareShapingEvidenceKey` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareRecordedShapingResult` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareMetricsEvidenceKey` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `compareRecordedFontMetrics` | 修复位置：是否生成比较函数的判定与引用侧不一致（F3ai） |
| 1 | `mkdirSync` | 修复位置：测试 extern 静态成员调用点输出不带限定名的名字（F3ak） |
| 1 | `writeFileSync` | 修复位置：同 F3ak |
| 1 | `sumOfFloat` | 未判定（dartstd-r2 合并后新增，justifier.dart:141） |
| 2 | `forEach` | 未判定（dartstd-r2 合并后新增，justifier.dart:147 与 :155） |

EXPECTED_TOKEN 的期待符号分布（求和 56）：';' 49 条、')' 4 条、':' 2 条、
'}' 1 条（全部未判定）。

URI_DOES_NOT_EXIST 的引用路径分布（求和 6，census11 复测值；目录列 gen 指
dart-gen 内的文件、tests 指 dart-gen-tests 内的文件；已判定 F3i；生成侧
3 条与测试侧 sorted_table 1 条为 dunitsurf-r3 的 `db0f713a` 不再写出
runtime/ 目录后的 import 断链，测试侧 test_host 与跨目录 liang_hyphenator_
test 两条为 dartstd-r2 期已有残余）：

| 计数 | 引用路径 | 目录 |
|---:|---|---|
| 3 | `../../../runtime/sorted_table.dart` | gen（liang_hyphenator.dart:3、parse_tex_hyphenation_patterns.dart:3、parsed_tex_hyphenation.dart:2） |
| 1 | `test_host.dart` | tests（main.dart:6） |
| 1 | `../../../../dart-gen/lib/runtime/sorted_table.dart` | tests（liang_hyphenator_test.dart:7） |
| 1 | `../../../../dart-gen/lib/org/tiqian/linebreak/liang_hyphenator_test.dart` | tests（line_break_coverage_test.dart:8） |

## 9 分级标尺

复杂度（C）：C1 单点修复，一个生成器分支或一处源文件，改动预计不超过一百行；
C2 跨文件或跨目标，同一缺陷出现在多个目标，或需要 tiqian 源与 boring 生成器
配合；C3 新机制，需要新增降级能力。

优先级（P）：P0 阻塞项，阻塞后续测量或行为对齐验收；P1 大错误种类或已在修复
计划内的排队项；P2 影响总数但不阻塞测量；P3 单例且暂无复现路径。

严重性（S）：S0 错误出在语法层，使整个生成目录无法编译或无法生成；S1 两百条
以上；S2 二十到一百九十九条；S3 二十条以下。流程类条目不适用 S，记为 S-。

## 10 KPI

工作量检验的方式（2026-09-06 用户规定）：进度以各目标逐类表的行计数变化
为准，每类可单独复测；不设覆盖多类的「其余」聚合指标，聚合数只保留合计
一个完整性数字（各类求和必须等于合计）。修复项只对修复位置开，不对消息类
主题开；每条修复项写明覆盖的错误类、类内条目与计数，KPI 现值写各目标
逐类表的实测计数，切分反映修复工作量，不合并修复位置。

| KPI | 指标 | 现值 | 目标 | 对应 |
|---|---|---|---|---|
| K1 | 修复位置 A：only safe 类计数 | f32 3 / f64 3（knullinit 系列合并 `23f4bf63` 后的残余） | 0 | #22 残余 |
| K2 | 各目标逐类判定完成度 | kotlin 33 类：修复位置或挂靠修复项 20、探针待因果 3、形状证实 10、假设 0、未判定 0（3.2 节小结，tattr4 r1）；rust 28 码：E0432、E0053、E0424、E0423、E0308-198、E0599 四子形与 r4 两组已判，E0277 仅 send 5 条已判，其余 372 条在判（第 6 节小结）；swift gen 侧 1 类已判、tests 侧 2 类已判 F3u（第 5 节）；ts 16/16 类已判（第 7 节小结）；dart 修复位置 8 码加 F3at 的 charCodeAt 组，其余 25 类形状证实或假设（第 8 节小结） | 五目标全部类有判定结论 | T-attr、T-swift、T-dart、tsprobe2、rustsem、rustprobe |
| K3 | 各目标错误总数 | kotlin f32 228 / f64 239；rust f32 2741 / f64 2738；ts 330；dart 135（生成侧 96、测试侧 39）；swift f32 11 / f64 5（WMO 测量，TiqianEngine import 全消融真值；未消融时 import 失败掩蔽全部后续诊断，实测仅 1 为假值）。全部为 census20 实测值（boring `b5c08650` × tiqian `3f609c0f`） | 全部 0 | 各节逐类表求和（完整性数字，非派发单位） |
| K4 | kotlin 两个精度目录 warning 计数 | 0 / 0 | 保持 0 | 每次复测 |
| K5 | 各目标重生成退出码 | 八个生成入口全部 0（2026-09-07：kotlin、swift、rust 各 f32 与 f64，ts、dart） | 全部 0 | 逐处重跑阶段（已完成，第 4 节） |
| K6 | boring 验收命令 | 19 项 gates 统一重跑全部退出码 0：`b822afee`（dartnull 合并态）、`c38a359c`（rustcoalesce-r4 合并态）与 `4644e29b`（f4m 合并态）；`a72f994d` 合并后曾 17 项通过、3 项失败，两 rust 项失败的交互机制与修复见第 6 节 census12 段，consistency 为既有失败项、已随其后合并转绿；更早合并的 gates 结果与失败定性见第 12 节对应行 | 每次合并后保持 | 不适用 |
| K7 | 五目标普查覆盖 | 八格矩阵逐类表已建（kotlin、swift、rust 各 f32 与 f64 加 ts、dart，第 3、5、6、7、8 节） | 五目标各有逐类表 | 首次普查记录（第 12 节进度表） |

## 11 修复项清单

本清单只保留未完成或待新基线全量复测确认的修复项。已完成并在新基线复测确认的条目从本清单删除，在第 12 节进度记录表中归档；条目编号保留不复用。

### 第 1 组：判定探针（K2，先于其余修复任务的派发）

- [ ] T-attr kotlin 逐类判定探针：抽样形状已并入 3.2 与 3.3 节，unresolved reference 相关的十七类全量判定并入 3.4 节。剩余范围是将 3.2 节 14 类形状证实定位到文件与分支、证实或否证 6 类假设、判定 3 个未判定类，并将 3.3 节 argument 类内可空 82、Number 装箱 14、其余 33 归到修复位置。C2，P1，S-。
- [ ] F1a 修复位置 A 计数降为 0（#22 残余）：knullinit 系列合并 `23f4bf63` 后残余 only safe 类 f32 3 / f64 3、operator call prohibited 类 f32 6 / f64 6。C2，P1，S3。
- [ ] T-dart dart 逐类判定探针：五类探针定位已升为修复位置并入第 8 节，修复项 F3ah 至 F3ap 随之开列。剩余范围是给形状证实类定位机制位置、证实或否证其余跨目标假设（ARGUMENT_TYPE_NOT_ASSIGNABLE 的 double 67 条是否数值转换、UNDEFINED_METHOD 新增 toDouble 原因查明等）。C2，P1，S-。

### 第 3 组：按判定结果立项

本组条目按修复位置开列：一条修复项对应一个修复位置，附覆盖的错误类、条目清单、计数与判据。

- [ ] F3i dart 目标运行时与 std 影子文件的写出（残余 2 条）：dartstd-r2
      （boring `4a67d7e0`，合并 `c629b1d1`）把 URI_DOES_NOT_EXIST 从 36 条
      修到 2 条，生成侧 25 条全部消除（std 与 runtime 影子文件经
      dartcompiler/Compiler.hx 的 forceCompileModules 在消费方配置下强制
      编译写出；std/sorted_map.dart 等 extern 模块写出为仅含生成头注释的
      空壳文件，URI 条目随之消除，名字未定义转入 UNDEFINED_PREFIXED_NAME
      等类）。同笔合并新暴露 13 条进入各自错误码的判定队列（见第 8 节）。
      残余在 census11 部分回归（`3044bf91`）：dunitsurf-r3 的 `db0f713a`
      把 resident 模块并入合并 runtime 库、消费配置下不再单独写出
      runtime/ 目录，四处对 runtime/sorted_table.dart 的 import 断链
      （生成侧 liang_hyphenator.dart:3、parse_tex_hyphenation_patterns.dart:3、
      parsed_tex_hyphenation.dart:2，测试侧 liang_hyphenator_test.dart:7），
      全类 2→6（生成侧 0→3、测试侧 2→3）；目录对照证据见节首 URI 回归段。
      测试侧另有 test_host.dart（main.dart:6）与跨目录引用
      liang_hyphenator_test.dart（line_break_coverage_test.dart:8）两条
      dartstd-r2 期残余，写出条件的不一致尚未定位。修复位置随合并
      runtime 库机制重判（import 生成侧改指合并 runtime 库路径，或恢复
      单独写出），判据为 URI_DOES_NOT_EXIST 计数降为 0。C2，P1，S2。
- [ ] F3j kotlin 数值转换位扩展（残余）：knumconv-r3（boring `8aa72e16`，
      合并 `7b3135a1`）已修掉主体；残余为 operator applied 全类（f32 2 /
      f64 2）、return 全类（17 / 17）、initializer f64 侧（0 / 2）、
      assignment 类内待再分形状（6 / 10，数值形状已修、残余疑为可空）与
      3.3 节 Int 给浮点（6 / 13）、Long 给浮点（0 / 2）两形状。修复位置为
      KotlinExpr.hx 的 renderCallArgs（boring `4b1fec9` 时位于 2806-2820，
      派发方复核）只在实参位对 isIntType 的接收值插入
      `(x).toFloat()/.toDouble()` 转换，运算、return、默认值、赋值四个
      位置没有同等转换，isIntType 也不覆盖 Long；修复方案是把这四个位置与
      Long 纳入同一转换机制。判据为 operator applied、return、initializer
      三类与 Int 给浮点、Long 给浮点两形状计数降为 0，assignment 剩余
      条目全部为可空形状，其余类计数不上升。C2，P1，S2。
- [ ] F3m dart 可空接收者守卫缺失（残余 13 条）：knullinit 系列守卫已修 property 形 314 条；修复任务
dartguard（#64）r1 至 r4 累计把残余 143 条修到 17 条、r6 后残余 13 条
      （提交号与逐轮计数见第 12 节；r4 后形状分布见 8.2）；r4 曾把 coalescing 内层构造的参数类型具化，实验 `2fe7fac9`
      使 dart 分析错误升到 1506 条量级，已回退，该方向禁用。修复位置为
      dart 生成器对可空接收者的成员访问、调用、运算
      与条件位没有生成守卫（clreq_punctuation_advance_policy.dart:27 的
      int? 接收者直接比较实测；DartExpr.hx:1315-1341 的 binop 守卫位
      派发方在 31627b5c 复核），与 kotlin 修复位置 A（#22）同构造。判据为
      该错误码计数降为 0，其余类计数不上升。C2，P1，S2。
- [ ] F4q rust Clone derive 供给与 `.clone()` 调用需求不一致：census14 实测
      该形状残余 435 条（修复未派发，判定见 rustjudge r3/r4）。修复位置
      候选两处二选一：derive 判定侧（data-class 路径对结构补 derive）与
      `.clone()` 追加侧（判 Clone 能力再追加）。判据为该形状降为 0。
      C2，P1，S2。（census14 后排首）
- [ ] F4p rust 可空类 coalescing 默认值物化与 Option 形参不匹配：census14
      实测 Option 形状 E0308 残余 389 条。修复位置为默认值物化与被调函数
      形参实际类型对齐（嵌套构造实参按形参类型包 `Some(...)`）。判据为
      该形状降为 0。C2，P1，S2。
- [ ] F3as ts coalescing 静态字段对 abstract 类的完整路径泄漏：修复已合并
      `87255540`，census14 实测 TS2304 org 条目残余 67 条未消。判据为
      org 条目降为 0 后核销。
- [ ] F3u swift tests 目录 import 头的消费侧配置：census14 实测
      swift-gen-f64-tests 41 条（swiftc rc=123）。修复位置为
      engine-haxe/targets/swift-common.hxml 补测试 import 配置。判据为
      tests 侧符号解析通过且计数可产出为 0。C1，P2，S-。
- [ ] 小残余复合项（census14 实测）：F4k haxe.Exception shim（E0433 残余
      8 条、原 1 条）；F4i std.Functional shim（E0432 残余 2 条）；F4m
      dataClass 构造器 self 绑定（E0424 残余 2 条）；F3ah dart 省缺实参
      （NOT_ENOUGH_POSITIONAL 残余 3 条）。判据为各残余降为 0。
- [ ] F3w kotlin 同函数局部变量名不去重：覆盖 3.2 节 conflicting
      declarations 全类 13/13。修复位置为 KotlinExpr.hx localName
      （:3299-3306）只对 `` ` `` 与 `_` 生成避让名、对 typer 展开数组推导
      产出的 `_g` 等名字原样输出，且 kotlin 目标 Compiler.hx:72
      `preventRepeatVars: false` 关闭了 reflaxe 的 RepeatVariableFixer
      （PreparedParagraphJfTest.kt:116/126 两个 `val _g` 实测，tattr3 r1）。
      判据为该类计数降为 0，其余类计数不上升。C2，P1，S2。
- [ ] F3x kotlin 静态方法值缺 callable reference：覆盖 3.2 节 function
      invocation 全类 8/8（其中 1 条为 Array.copy 未降级产生的连锁错误，随 F3ag 消除）。
      修复位置为 KotlinExpr.hx field() 的 FStatic 分支（:2184-2187）对函数
      类型位置的静态成员返回 `Class.method` 文本，需要 `Class::method` 或
      lambda 包装（ContextualQuoteRoleResolverNestedAndSurrogateTest.kt:84、
      ParseTexHyphenationPatterns.kt:55 实测，tattr3 r1）。判据为该类计数
      降为 0，其余类计数不上升。C1，P1，S2。
- [ ] F3y kotlin 数组下标访问两条降级缺失：覆盖 3.2 节 no operator array
      access 全类 6/6（set 形 4：`split` 经 KotlinExpr.hx:2973 产出只读
      List 后下标写，PreparedParagraph.kt:1726 起；get 形 2：
      stringBufMutationLines :698 文本拼接 `part + "[0].code"` 未给 part
      加括号，TracedAssertions.kt:116 实测，tattr3 r1）。判据为该类计数
      降为 0，其余类计数不上升。C2，P2，S2。
- [ ] F3z kotlin 测试 lambda 内无标签 return：覆盖 3.2 节 prohibited here
      全类 5/5。修复位置为 KotlinDecl.hx testFuncDecl（:1152-1177）把测试
      函数体包进非 inline 的 `Test.run { … }`，而 KotlinExpr.hx stmtLines
      无实参 TReturn 分支（:557）输出不带标签的 `return`（BilingualEmphasisTest.kt:16
      实测，tattr3 r1）。判据为该类计数降为 0，其余类计数不上升。
      C1，P2，S3。
- [ ] F3aa kotlin @JvmField 未排除 private：覆盖 3.2 节 jvmField 全类
      5/5。修复位置为 KotlinDecl.hx objectVarDecl（:1009）对非 final 静态
      字段无条件生成 `@JvmField`，未考虑可见性（PreparedParagraph.kt:25
      实测，tattr3 r1）。判据为该类计数降为 0，其余类计数不上升。
      C1，P2，S3。
- [ ] F3ab kotlin when 臂分组多值丢弃：覆盖 3.2 节 exhaustive 全类 4/4
      与 variable must be initialized 全类 3/3（同一机制连锁，分支缺臂
      路径无赋值）。修复位置为 KotlinExpr.hx switchExpression（:1345-1349）
      只渲染每个 case 的 `c.values[0]`，Haxe typer 归并的 `case A | B:`
      其余值被丢弃（FontMetrics.kt:15 与 :21 实测，tattr3 r1）；
      KotlinDecl.hx collectMessageCases（:672 起）同形，需同步检查。
      判据为两类计数降为 0，其余类计数不上升。C1，P1，S3。
- [ ] F3ad kotlin Haxe 文件私有类映射缺失：覆盖 3.2 节 redeclaration
      全类 2/2。修复位置为 KotlinDecl.hx classDecl（:207）对一切类无条件
      生成 top-level `class`，Haxe 文件私有类（仅本文件可见）需要 Kotlin
      private top-level 映射（ContextualQuoteRoleResolver.hx:316 与
      ContextualDashEllipsisRoleResolver.hx:223 各一个 `private class
      Resolution`，生成后同 package 冲突，tattr3 r1）。判据为该类计数
      降为 0，其余类计数不上升。C2，P2，S3。
- [ ] F3ae kotlin 下划线参数名原样输出：覆盖 3.2 节 reserved 全类 1/1。
      修复位置为 KotlinDecl.hx parameterText（:873）与 lambda 参数渲染只调
      KotlinNameEscape.escape（:42-43 只给关键字加反引号），`_` 参数需要
      与函数体局部一致的生成名路径（UnicodePunctuationBoundaryTestSupport.kt:118
      实测，tattr3 r1）。判据为该类计数降为 0，其余类计数不上升。
      C1，P2，S3。
- [ ] F3af kotlin @:access 与模块可见性无映射：覆盖 3.2 节 cannot access
      全类 3/3（kgetvis 合并 `ad0990e2` 后的残余基数）。修复位置为
      KotlinDecl.hx funcDecl（:1103）与 objectVarDecl（:1008）的可见性
      选择只把 `:allow` 转 internal，`@:access` 授权类跨类访问与 Haxe
      同模块文件私有访问没有对应映射（LineOptimizationCoverageTest.kt:151、
      ContextualQuoteRoleResolver.kt:293 起实测，tattr3 r1）。判据为该类
      计数降为 0，其余类计数不上升。C2，P2，S3。
- [ ] F3ai dart 数据类是否生成比较函数的判定与引用侧不一致：直接覆盖第 8 节
      UNDEFINED_FUNCTION 的 compare 前缀 41 条（名称明细见 8.2，tdart2 r1）。
      修复位置为是否生成比较函数的判定 canEmitDataClassComparator（packages/compiler/
      PolicyQueries.hx:163-171）的 isDataClassFieldKey（:173-192）不接受
      Bool 与 Float 字段，而 dartcompiler/DartDecl.hx 引用侧分支
      （e01b03b3 位于 :311-312 与 :326）只复查 `:dataClass` meta、不复查
      是否生成的判定；两侧取齐（判定放宽或引用侧同判定）。同时预期消减
      UNDEFINED_METHOD 的 compareTo 形 9 条（NullableScalar 分支对非
      Comparable 实例渲染 `.compareTo`，DartDecl.hx:279-281；消减量在
      合并复测后重数，不预先承诺）。与 ts TS2724/TS2305 同源（同一
      Haxe 源构造，各目标实现独立；ts 侧机制位置待定位）。判据为 compare 前缀
      与 compareTo 形计数降为 0，其余类计数不上升。C2，P1，S2。
- [ ] F3ak dart 测试 extern 静态成员调用点不带限定名引用：覆盖第 8 节
      UNDEFINED_FUNCTION 的 mkdirSync 与 writeFileSync 各 1 条（tdart2 r1）。
      修复位置为测试 extern 的静态成员在调用点降级为不带限定名的名字
      （dartcompiler/DartExpr.hx:1605-1606 的分支形状）而定义不随 tests 产物目录
      写出。判据为两条名字计数降为 0，其余类计数不上升。C1，P3，S3。
- [ ] F3al dart coalescing 静态调用的类限定引用未随 statics-only 降级：
      覆盖第 8 节 UNDEFINED_PREFIXED_NAME 的 DefaultHyphenator 15 条与
      PunctuationGluePlacements 6 条（tdart2 r1）。修复位置为
      dartcompiler/DartExpr.hx 的 coalescingStaticCallText（e01b03b3 位于
      246-258）渲染 `前缀.类名.方法`，没有 staticRef（:1619 起）对
      statics-only 类去类名的降级路径。判据为两条名字计数降为 0，其余类
      计数不上升。C1，P2，S2。
- [ ] F3am dart 运行时 UString resident 未拉起：覆盖第 8 节
      UNDEFINED_PREFIXED_NAME 的 UString 21 条（tdart2 r1）。机制为
      std.UStringRT 成员渲染 `runtime.UString.成员`（DartExpr.hx:1607-1608
      一带），运行时模块拼接（dartcompiler/Compiler.hx:388-396）只追加
      parts 非空的 resident，tiqian 的 engine-haxe/targets/classes.hxml
      没有任何 `runtime.*` 清单条目（boring examples/dart.hxml 带
      `runtime.UString` 等条目），std.UStringRT 是 extern 不产生 parts，
      定义与引用两侧都落空。修复位置为 boring dart 编译器在配置了
      runtime-import 时强制拉起 resident（rust 侧同构造的先例是
      rustcompiler/Compiler.hx 在 runtime-import 时 `Context.getType`
      运行时类型），必要时配合 tiqian classes.hxml 补清单条目。判据为
      UString 名字计数降为 0，其余类计数不上升。C2，P1，S2。
- [ ] F3an dart 局部重名不去重：覆盖第 8 节 DUPLICATE_DEFINITION 的同名
      合成临时变量 5 条（line_geometry_stage.dart:234-246 三个 `_g`、
      line_adjustment_stage.dart:392 与 :471 的 `index`）与 Haxe 源同块
      var 重声明 2 条（layout_queries.dart:641 与 :671 的 `rubyIndex`，源
      LayoutQueries.hx:584/:597，tdart2 r1）。修复位置为
      dartcompiler/DartExpr.hx 的 localName（e01b03b3 位于 3498 起）对
      命名临时变量原样输出、同块不去重。与 ts TS2451 同源（同一源构造，
      各目标实现独立）。判据为 7 条计数降为 0，其余类计数不上升。
      C2，P2，S2。
- [ ] F3ao dart extension type 表示字段与成员同名：覆盖第 8 节
      DUPLICATE_DEFINITION 的 ic.dart:5 一条（`extension type Ic(double
      count)` 里 `count()` 与表示字段 `count` 同名，tdart2 r1）。修复
      位置为 dartcompiler/DartDecl.hx 的 valueTypeDecl（e01b03b3 位于
      422-431）取第一个构造参数名为表示字段，没有与成员名查重。判据为
      该条计数降为 0，其余类计数不上升。C1，P3，S3。
- [ ] F3ap dart coalescing 构造器守卫赋值未收集：覆盖第 8 节
      NOT_INITIALIZED_NON_NULLABLE_INSTANCE_FIELD 全类 4 条（源
      LineBreaker.hx:50-57 的 if/else 守卫赋值，tdart2 r1）。修复位置为
      dartcompiler/DartExpr.hx 的 coalescedBodyFields（e01b03b3 位于
      523-553）只扫构造函数顶层语句，分支体内的 `this.x = …` 不被收集，
      字段声明侧 DartDecl.hx:639-643 因此不标 `late`。判据为该类计数
      降为 0，其余类计数不上升。C1，P2，S3。
- [ ] F3au kotlin counted-loop 识别未查循环体写计数器：覆盖 3.2 节 cannot
      be reassigned 全类 24/24（tattr4 r1 判定为修复位置）。Haxe 源的
      while 计数循环体写计数器（LineRepair.hx:61-64 的 `i++`、
      LayoutQueries 的 `index += 1`），kotlin 的区间识别谓词
      PolicyQueries.hx intervalCore（:800-868）与 intervalShort
      （:888-930）只匹配声明与条件并识别尾部自增，不检查体内其余位置
      对计数器的写，KotlinExpr.hx:867-870 matchInterval 命中后输出只读
      for 绑定（LineRepair.kt:39-44 实测）。修复位置为两谓词加体写检查
      （赋值与自增形、递归嵌套语句）返回 null 保留 while 形；与 knamefix
      （#23）的循环识别改动同文件，随其续作轮或独立派发。判据为该类
      计数降为 0，其余类计数不上升。C2，P1，S2。（排队）
- [ ] F4e rust compare 引用侧未校验 canEmitDataClassComparator：覆盖第
      6 节 E0432 compare 前缀类 42 条（rustsem r1）。嵌套 record 的
      compare 引用生成段（RustDecl.hx:333-337、:364-366、:391-393、
      :409-411、:469-470）不校验共享谓词 canEmitDataClassComparator
      （PolicyQueries.hx:163-192），定义侧判定不生成时引用侧仍输出
      compare_X。修复位置为引用侧五段接入同一谓词；与 ts TS2724、dart
      F3ai 为同一谓词不一致的跨目标表现。判据为该类计数降为 0，其余类
      计数不上升。C2，P2，S2。（排队；曾与 knamefix 系列改动同一文件的
      冲突已解除（r7 经 gates 否决未合入，r8 已合并 `3044bf91` 且不再
      触及 PolicyQueries.hx），可开分支）
- [ ] F4f rust 接口 trait 声明与 impl 签名不对齐：覆盖第 6 节 E0053 返回
      Result 类 23 条与可变维度 5 条（rustsem r1）。trait 声明
      （RustDecl.hx:87-102）固定为 `&self`、返回类型不带 Result；impl 块
      （RustDecl.hx:291-321）经 instanceFuncDecl（:1728-1738 可抛写
      Result、:1712-1717 可变写 `&mut self`）拷贝类自身签名，两侧不一致。
      修复位置为 RustDecl.hx:291-321 的接口 impl 生成段使签名与 trait
      声明对齐，或声明与实现两侧统一承载可抛与可变信息。判据为两类
      E0053 计数降为 0，其余类计数不上升。C3，P2，S3。（排队）
- [ ] F4g rust 静态 Mutex 包装不查 Send：覆盖第 6 节 E0277 类 5 条
      （rustsem r1）。moduleStaticVarDecl 默认分支（RustDecl.hx:1154-1157）
      无条件把 mutable static 包成 `Mutex<T>`，内层 `Rc<dyn Fn…>`
      （RustType.hx:148）与无 Send 上界的 `Box<dyn Trait>`
      （RustType.hx:85-87）不满足 static 的 Sync 要求。修复位置为该分支
      区分非 Send 内容（换 Arc、加 Send 上界或改为首次使用时初始化的单例形态），配合
      RustType.hx 的类型选择。判据为该类计数降为 0，其余类计数不上升。
      C3，P3，S2。（排队）
- [ ] F4h rust 同模块 payload 自映射误跳：覆盖第 6 节 E0432 could-not-find
      类内 tiqian_no_such_element_exception 3 条（rustsem r1）与 E0433
      同名连锁 1 条（layout_queries.rs，rustprobe r1 3.4，census11 逐名
      复核仍在）。payload
      enum 与异常类同模块时 preScan（Compiler.hx:818-820）形成自映射，
      generateFilesManually 的去重跳过（Compiler.hx:250-252）把异常类
      所在模块整模块丢弃。修复位置为该两处：同模块场景不跳过异常类
      模块，或自映射时改记 owner 之外的模块。判据为该 4 条降为 0，其余
      类计数不上升。C2，P3，S3。（排队）
- [ ] F4l rust @:dataClass 默认参数内联全限定名与形参泄漏：覆盖第 6 节
      E0425 类内 org 52、region 7、count 1 共 60 条（rustprobe r1
      3.2.a/3.2.b 加派发方 census11 逐名位点复核）。org 52 为默认值展开
      保留的 Haxe 点分全限定名 `org.tiqian.core.Ic.Zero` 原样输出
      （layout_input.rs:44:150 实测）；region 7 与 count 1 为同一内联
      路径把构造器形参泄漏进调用点上下文（clreq_profile.rs:24:433 的
      pub static 初始化器与 layout_dump_format.rs:146 实测）。修复位置
      为默认参数内联路径（packages/compiler/DefaultArgExpander.hx）在
      rust 侧渲染时把全限定名解析为短名并登记 import、把形参默认值
      改绑到字段或局部绑定；与 swift gen 侧 1 条、ts F3as org 名字条目、
      kotlin 3.4 节 region/text/cornerRadius 是同一默认参数内联构造的
      各目标表现。判据为该 60 条降为 0，其余类计数不上升。C2，P1，S2。
      （排队；DefaultArgExpander.hx 与 dartargs-r2 的文件冲突已随其合并
      （`a72f994d`）解除、可以开分支；rust 消费侧回归（第 6 节）的修复
      优先于本项，回归修复合入前本项 60 条与新增 3484 条出自同一个生成树、单独
      验收无法辨认）
- [ ] F4n rust @:dataClass 继承构造器 super 调用：覆盖第 6 节 E0423
      全类 1 条（rustprobe r1 3.3）。@:dataClass 带继承的构造器
      `super(Message(message))` 被原样输出成 `super(...)`（源
      IllegalStateException.hx、生成 illegal_state_exception.rs:9 实测），
      Rust 无类继承、`super` 是父模块路径关键字。类继承加构造器 super
      调用的 Haxe 语义在 rust 目标无法直接承载，属 AGENTS.md 第 34 条
      例外情形；修复须把此类类从 @:dataClass 构造器生成路径改到手工
      impl 构造路径，任务书与报告写明所依赖的 Haxe 语义。判据为该条
      降为 0，其余类计数不上升。C3，P3，S3。（排队）
- [ ] F4o tiqian 生产模块引用测试支撑类型：覆盖第 6 节 E0433 类内
      SortedMap 6、test_core 5、NodeFileSystem 2 共 13 条（rustprobe
      r1 3.4，census11 逐名核对分布不变）。tiqian 生产模块引用只在
      测试支撑模块定义的名字（paragraph_shaping_stage.rs:61 与
      replayable_font_backend.rs:40 引 SortedMap、prepared_paragraph.rs:556
      引 test_core），测试模块被 `#[cfg(test)]` 条件编译排除后名字不再参与解析
      而暴露。修复位置在 tiqian 的 engine-haxe 源把生产模块的引用改指
      生产侧定义或把类型提升进生产模块，不在 boring 侧绕过（AGENTS.md
      第 34 条）。判据为该 13 条降为 0，其余类计数不上升。C2，P2，S2。
      （排队）

## 12 进度记录

| 日期 | 修复项 | 合入位置 | 复测计数 | 验收结论 |
|---|---|---|---|---|
| 2026-09-05 | Kotlin 基线建立 | boring `a75601a` | f32 3338 / f64 3358 | 基线记录完成 |
| 2026-09-05 | 基线迁移与分桶修正 | boring `5d7417e` | f32 3335 / f64 3355 | 分桶合计与总数一致 |
| 2026-09-05 | F0e 三生成器补 `Math.abs` 规则 | boring `7f2bced` | dart 生成目录该报错消除 | 验证套件退出码全部为 0 |
| 2026-09-05 | F0f `Std.string` 违规调用定位与修复 | tiqian `e0e1172d`＋`ec285e24` | rust 生成目录该报错消除 | 移植树验证通过，engine jvmTest 通过 |
| 2026-09-05 | F0j 整型容量上界生成规则 | boring `012ab59` | rust 生成目录该报错消除 | 验证套件退出码全部为 0 |
| 2026-09-06 | 基线迁移（r4） | tiqian `105dfb30` 加 boring `4b1fec9` | f32 1183 / f64 1201，warnings 0 | 验证测试通过 |
| 2026-09-06 | ts 第二处生成阻断 UStringException 修复 | boring `f270c670`（合并 `de11c06a`） | ts 生成退出码 0，首次全量生成 | 验证检查退出码全部为 0 |
| 2026-09-06 | getter 属性读四目标调用点修复 | boring `5628b4d`（合并 `f9f26726`） | 342 个测试六目标一致 | 验证检查退出码全部为 0 |
| 2026-09-06 | ts 首次编译普查 | boring `7606ff85` | ts 1127 条、19 类 | 逐类表求和校验相等 |
| 2026-09-06 | F0l dart 静态成员顶层重名修复与首次普查 | boring `189e01ad`（合并 `31627b5c`） | dart 生成退出码 0，analyze 2931 条 | 验证检查退出码全部为 0 |
| 2026-09-06 | F0a-F0d nullargs 等历史条目合并核销 | boring `8d17b59` 等 | null 字面量错误 2122→0，f32 1535 / f64 1553 | 验证检查退出码全部为 0 |
| 2026-09-07 | knullinit 系列合并（可空接收者守卫） | boring `3d397740`、`9e0537d0`、`b552e2a1` | kotlin only safe 75→3；dart UNCHECKED 420→143 | 验证套件通过 |
| 2026-09-07 | kparamnull 合并（可选参数 null 默认值） | boring `1f35923d`（合并 `2b78ab4b`） | kotlin 错误数持续下降 | 验证套件通过 |
| 2026-09-07 | knumconv-r3 合并（数值加宽转换扩展，F3j 主体） | boring `8aa72e16`（合并 `7b3135a1`） | 运算符与返回位错误大幅消除 | 验证套件通过 |
| 2026-09-07 | kgetvis 合并（getter 可见性与 override，F3k 关闭） | boring `6f3bc868`（合并 `ad0990e2`） | modifier incompatible 14→0、cannot access 27→3 | 验证套件通过 |
| 2026-09-07 | dartifget 合并（接口 getter 声明缺失，F3h 关闭） | boring `0d470797`（合并 `14c5031d`） | dart UNDEFINED_GETTER 32→0 | 验证套件通过 |
| 2026-09-07 | rustflit 合并（浮点字面量缺整数部分） | boring `4deac694`（合并 `d870489c`） | rust 浮点字面量类 124→0 | 验证套件通过 |
| 2026-09-07 | rustf4c 合并（保留字转义，F4c 关闭） | boring `dc09d773`＋`e4c24e77` | rust 保留字转义类 12→0 | 验证套件通过 |
| 2026-09-07 | swiftrem-r2 合并（浮点字面量与转义，F3f、F3g 关闭） | boring `4c81c5fc`（合并 `e01b03b3`） | swift gen 浮点 7 条与控制字符 1 条降为 0 | 验证套件通过 |
| 2026-09-07 | F3t swift 字符串插值内嵌语句体闭包 | boring `6ad8dc66`（合并 `d2c6b559`） | swift tests 侧每精度 57→41，F3t 四类 16→0 | 验证套件通过 |
| 2026-09-07 | rustfix-r1 合并（保留字与 switch 修复，F3n、F3o、F3q 关闭） | boring `b7054019` | rust 每精度 20→4：F3n、F3o、F3q 三类降为 0 | 验证套件通过 |
| 2026-09-07 | kf3v-r1 合并（参数数量匹配，F3v 关闭） | boring `b7500d45` | kotlin too many arguments 14/14→0 | 验证套件通过 |
| 2026-09-07 | dartguard r1 至 r4 合并（可空守卫与类型名，F3l 关闭） | boring `f42c38c9`、`18d5d8d1`、`e4952dab` | dart 分析错误 2606→1707，UNDEFINED_IDENTIFIER 1025→280 | 验证套件通过 |
| 2026-09-07 | dartstd-r2 合并（运行时与 std 影子文件） | boring `4a67d7e0`、`0162fa05`（合并 `c629b1d1`） | dart URI_DOES_NOT_EXIST 36→2 | 验证套件通过 |
| 2026-09-07 | tsgetcal-r6 合并（属性调用降级，F3e 关闭） | boring `4fa632e6` | ts 1127→1004，TS2551 与 TS2341 降为 0 | 验证套件通过 |
| 2026-09-07 | rustfix r2 至 r4 合并（F3p、F3r、F3s 关闭） | boring `e509f6df`、`d0df20db` | rust 解析层错误每精度 4→0，语义层错误显露（每精度 189） | 验证套件通过 |
| 2026-09-07 | ts 测量配置补充（类型定义与路径映射） | 无代码改动（配置校准） | ts 1004→722，环境缺失 300 条全部解决 | 验证套件通过 |
| 2026-09-08 | dartguard-r6 合并（F3m 续修） | boring `02210451` 等（合并 `b4b574b5`） | dart 分析错误 1686→1682，UNCHECKED_USE 17→13 | 验证套件通过 |
| 2026-09-08 | fph32-r1 合并（F3aj 关闭） | boring `2382140b`（合并 `014d9640`） | dart UNDEFINED_FUNCTION 58→46（floatToI32 与 i32ToFloat 降为 0） | 验证套件通过 |
| 2026-09-08 | tsforce-r1 合并（F3ar 关闭） | boring `7c2a1c02`（合并 `908305a0`） | ts 分析错误 722→714，TS2304 TestCore 8→0 | 验证套件通过 |
| 2026-09-08 | dunitsurf-r2/r3 合并（dart 运行时崩溃消除） | boring `c5cf26d8`、`db0f713a` | dart analyze 推进，消除运行时崩溃 | 验证套件通过 |
| 2026-09-08 | knamefix-r8 合并（kotlin 名字解析修复，F3ag 关闭） | boring `3044bf91` | kotlin unresolved 365/358→54/54，f32 680→343 / f64 701→354 | 验证套件通过 |
| 2026-09-08 | rustmisc-r2 合并（递归字段装箱，F4j 关闭） | boring `d4a43a33`、`b74f9da9`（合并 `746742dd`） | rust E0072 每精度 1→0 | 验证套件通过 |
| 2026-09-08 | dartargs-r2 合并（F3ah dart 侧生效） | boring `74371c5a`、`963a3ba6`（合并 `a72f994d`） | dart NOT_ENOUGH_POSITIONAL_ARGUMENTS 105→4 | 验证套件通过 |
| 2026-09-08 | tsorg-r2 合并（F3as ts 侧修复） | boring `f43d6a02..bacb2ae0`（合并 `87255540`） | 消除 abstract 类静态引用完整路径泄漏，输出对齐 | 19 项验证套件退出码全部为 0 |
| 2026-09-08 | rustjudge 探针分析（E0308 与 E0599 形状定位） | 无代码改动（探针分析） | E0308 最大形状 198 条与 E0599 四子形 569 条完成定位，开列 F4p 与 F4q | 结论并入逐类表 |
| 2026-09-08 | dartnull 合并（F3at：charCodeAt 边界转换与 rust 双 unwrap 去重） | boring `7994eceb`（合并 `b822afee`） | dart 分析错误 1702→1670（生成侧 -32 全部消除）；rust E0599 位点去重 | 19 项验证套件退出码全部为 0 |
| 2026-09-08 | boring-f4m-r1 合并（F4m：rust dataClass 关联函数 self 绑定） | boring `1d7f72e9`、`52c574ff`（合并 `4644e29b`） | 关联函数 fn new 内 this 字段改绑构造器局部，覆盖 E0424 75 条 | 19 项验证套件退出码全部为 0 |
| 2026-09-08 | rustcoalesce-r4 合并（F4p：可空类 coalescing 默认值物化） | boring `21234a8d`、`2b139721`（合并 `c38a359c`） | 解决 74371c5a 引入的跨目标默认值物化不匹配问题，覆盖 E0308 198 条 | 19 项验证套件退出码全部为 0 |
| 2026-09-09 | 夜间批次推进合并 | boring `5919f6b7..446fb874` | 合并 isCloneType 判定（F4q）、functional shim（F4i）、异常降级（F4k）、dart 嵌套可空折叠、kotlin 构造默认物化等多项目标改动 | 19 项验证套件按提交逐项验证通过 |
| 2026-09-09 | 统一基线复测（夜间合并推进） | boring `cc34c779` | swift f32 0 / f64 0、ts 677、dart gen 463 / tests 415、kotlin f32 356 / f64 367、rust f32 4063 / f64 4073 | 六目标统一基线建立，Swift 双精度错误全部消除 |
| 2026-09-10 | census13 复测（模块导入与 derive 推进） | boring `ecf140dc` × tiqian `3f609c0f` | ts 430、rust f32 3840 / f64 3850、swift f32 0 / f64 7、kotlin f32 356 / f64 367、dart gen 463 / tests 415 | ts 降 247、rust 降 223，swift 新增测试覆盖引入 7 条 |
| 2026-09-10 | census14 复测（默认参数展开、From/Fault 与迭代修复） | boring `cf31edba` × tiqian `3f609c0f` | kotlin f32 178 / f64 189、ts 337、rust f32 3402 / f64 3412、swift f32 0 / f64 1、dart gen 331 / tests 67 | 六目标错误大幅下降，dart tests 降至 67，swift f64 降至 1 |
| 2026-09-10 | census15 复测（参数名绑定与 ts 路由前基线） | boring `a2f2bdc2` × tiqian `3f609c0f` | kotlin f32 176 / f64 187、ts 337、rust f32 3402 / f64 3174、dart gen 269 / tests 48 | dart tests 67→48，rust f64 3174（redo 测量修正） |
| 2026-09-10 | census16 复测（kotlin 参数名绑定＋ts 路由＋F4q clone 后） | boring `4d91f806` × tiqian `3f609c0f` | kotlin f32 147 / f64 49、ts 330、rust f32 3493 / f64 3490、swift f32 1289 / f64 1262（WMO 测量）、dart gen 269 / tests 48 | kotlin f64 187→49；rust E0599 降至 656、E0308 升至 2019（clone 修复解锁下游暴露）；swift 改用 `-wmo` 全模块测量，旧 batch 计数为截断值 |
| 2026-09-11 | census17 复测（swift 全栈＋rust E0308 所有权批＋异常链后） | boring `f3099727` × tiqian `3f609c0f` | kotlin f32 146 / f64 49、ts 330、rust f32 3058 / f64 3055、swift f32 297 / f64 266（WMO 测量）、dart gen 260 / tests 43 | swift WMO 每精度降约 1000；rust 每精度降 435；dart gen 269→260、tests 48→43；swift 首测零值已当场复测纠正 |
