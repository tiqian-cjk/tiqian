# 跨平台一致性修复经验（2026-09-20）

本文记录 tiqian engine-haxe 生成到多语言目标（TypeScript/Kotlin/Rust/Swift/Dart）时，
跨平台行为一致性调查与修复的经验。这些经验来自一次完整的调查：ts 测试束 499 个 fail
按根因分类、派发子 Agent 并行修复、验证效果。

## 背景

tiqian 的排版引擎用 Haxe 编写（engine-haxe/），通过 boring 编译器生成到
Kotlin/TypeScript/Rust/Swift/Dart 五种目标。跨平台一致性的金标准是 Legacy Kotlin 引擎
（engine/）生成的 golden 轨迹。boring 的 test-consistency 机制：每个目标运行同一套
`@:test` 测试束，写 jsonl，manager 以 kotlin 为 baseline 比对 verdict 一致性。

## 核心经验

### 1. 跨平台不一致的根因大多在 boring 生成器，不在引擎

ts 测试束 499 个 fail 中，95%（476 个）来自 boring ts 生成器的 3 个缺陷，不是引擎行为差异。
修复位置都在 boring 的 `packages/compiler/reflaxe/ts/`。这印证了"金标准是 golden"——
引擎行为正确，是生成器没正确翻译。

### 2. 三个典型生成器缺陷（R1/R2/R3）

- **R1: `Std.isOfType` 降级成常量 `true`**（`TypeCheckHelper.hx` 的 `knownIsOfType`）
  - 只看静态类型就返回 true/false，没考虑 null。Haxe 语义 `Std.isOfType(null, T)` 是 false。
  - 修复：对可空类型返回 null，让生成器保留运行时 `instanceof` 检查。
  - 教训：**静态类型不能决定 null 检查**。可空类型（`Null<T>`）或字面量 null 必须走运行时检查。

- **R2: `while`+内部 `i++` 被误识别为计数 for**（`PolicyQueries.hx` 的 `intervalCore`）
  - `i=0; while (i<n) { c=arr[i]; i++; ix=i-1; ... }` 被识别成计数循环转成 for，
    但 `ix=i-1` 依赖自增后的 i，转 for 后语义破坏。
  - 修复：循环体读取 counter 就保留 while（不降级成 for）。
  - 教训：**计数 for 降级只对"纯索引遍历"安全**。任何对 counter 的额外读取都可能依赖自增后值。

- **R3: 可空枚举 `==` 降级成 `.kind` 访问**（`TsExpr.hx` 的 `binop`）
  - `t == EnumValue`（t 可空）降级成 `t.kind === "Name"`，丢失 null 守卫。
  - 修复：可空侧生成 `(t !== null && t.kind === "Name")`。
  - 教训：**可空值的字段访问必须保留 null 守卫**。Haxe 的 `null == EnumValue` 是 false，不是崩溃。

### 3. 修复一个缺陷会暴露新的缺陷

R1 修复后，ts fail 从 499 降到 496（288 个 annotation.text 消除），但**暴露了 118 个新的
`input.fontDecision.candidate.key` 错误**——R1 让缓存守卫正确工作后，原本被短路跳过的
路径现在执行，暴露了测试辅助类里 `input.fontDecision` 为 null 的问题。

教训：**修复生成器缺陷是迭代过程**。每个修复可能暴露下一层问题，需要反复跑测试验证。

### 4. 其他语言的一致性状态（2026-09-20 基线）

| 目标 | 状态 |
|---|---|
| kotlin-f32 | 除 EnglishHyphenationPatterns 的 Method too large 外无编译错误 |
| dart | 1199 测试，694 pass / 505 fail（Null check 377、RangeError 117、surrogate 8） |
| rust-f32 | 523 编译错误（E0308 类型不匹配 283、E0609 可空字段 71 等） |
| swift | 生成成功，但沙箱无法编译验证（bwrap 权限） |

dart 的 fail 与 ts 有相似根因（null 处理、surrogate 守卫），说明 boring 生成器的
null 处理缺陷是跨目标的。rust 有大量类型系统处理问题。

### 5. EnglishHyphenationPatterns 的 Method too large

kotlin 生成 `intArrayOf(...)` 4266 个元素超过 JVM 64KB 单方法限制。修复：把超大数组
拆分成 `buildXxx()` + 多个 `fillXxxN(a)` 方法（每个 <8000 元素），避免单个 `<clinit>`
超限。教训：**超大静态数据初始化要拆分**，不能塞进单个方法。

## 工作流经验

### 6. 用独立工作树实现并行修复

6 个任务都改 boring 生成器（`.haxelib/boring/git/packages/compiler/`），是独立 git 仓库，
WB 分支不隔离。解决方案：**每个子 Agent 一个独立工作树**（/tmp/wt-rN，复制 engine-haxe +
.haxelib + tools/unicode-data），各自改各自的 boring 生成器，互不冲突。完成后合并回主工作树。

### 7. 任务描述要包含完整上下文，子 Agent 不猜测

每个任务描述包含：现象（具体错误消息）、根因（boring 源码函数+行号）、修复方案、
验证步骤、完成标准。子 Agent 拿到就能直接改，不用重新调查。这符合"任务委托必须包含
完整项目上下文"的要求。

## 建议

1. 继续修复 R1 暴露的 118 个 `input.fontDecision` 问题（已建任务）。
2. 建立 f32/f64 各自的跨平台一致性测试（复用 boring 的 jsonl + manager 机制），
   让 ts/kotlin/rust/swift/dart 的 fail 数可追踪。
3. 修复 boring 生成器的 null 处理缺陷（跨目标，ts/dart 都有）。
