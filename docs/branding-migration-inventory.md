# Tiqian 前缀迁移清单（SW09）

本文件记录 boring-docs-archive 架构轮次 SW09 的迁移清单：带 `Tiqian` 前缀的数组与异常公开 API 名，逐项列出定义、Tiqian 仓内依赖分布与处置。本文件在 Tiqian 仓内记录 boring-docs-archive 清单原文，不改动 boring 仓。

## branding 指公开 API 名中的 `Tiqian` 前缀

branding 一词在本文件中指公开 API 名中的 `Tiqian` 前缀。该前缀标记合成类型名或异常类名的来源。

## 本清单引用以下三个来源

SW09 原文位于 boring-docs-archive 仓库 `investigations/architecture-round-1/swift-checkpoint-todo.md` L53-L54：

> Keep existing `TiqianArray` and exception branding in the migration inventory with public API dependencies. The new view is named `ReadOnlyArray`.

round-2 E 复核位于 boring-docs-archive 仓库 `investigations/architecture-round-2/e-swift-runtime-closure-review.md`，确认 `TiqianArray` 与 `ReadOnlyArray` 位于 `ARRAY_SOURCE`，并记录「Existing branded mutable-array and exception names remain separate recorded migration work」。

异常改名的决定（2026-08-30）保存在本文「异常名迁移保留 `Tiqian` 前缀」一节；当初记录该决定的迁移期进度文件已随 `4edb2ac7c` 从本仓库删除，决定条文以本文为准。

## 清点表逐项列出带 `Tiqian` 前缀的公开 API 名及其处置

下表逐项列出带 `Tiqian` 前缀的公开 API 名、定义、Tiqian 仓内依赖分布与处置。依赖计数来自 Tiqian worktree 的 `grep -rIn`，排除 `.jj`、`.git`、`.haxelib`、`node_modules`、`.scratch`。

| 项 | 定义 | Tiqian 仓依赖分布 | 处置 |
|---|---|---|---|
| `TiqianArray` | boring Swift 后端为可变 Haxe `Array` 合成的运行时类型名 | 源码 0 处；`bundle-logs/swift-f32.test.log` 与 `bundle-logs/swift-f64.test.log` 各 11 处 | 记录；boring 侧改名，Tiqian 仓不改代码 |
| `TiqianIllegalArgumentException` | 移植侧（Haxe）非法参数异常类，继承 `haxe.Exception`，携带 `TextRangeError` | 301 处 | 保留（决定） |
| `TiqianNoSuchElementException` | 移植侧（Haxe）无此元素异常类，继承 `haxe.Exception`，携带 `NoSuchElementError` | 26 处 | 保留（决定） |
| `IllegalStateException` | 移植侧（Haxe）状态异常类，继承 `TiqianIllegalArgumentException`，名中无前缀 | 377 处 / 59 文件 | 保留现状 |
| `ReadOnlyArray` | 新视图名，即 Haxe `std.ReadOnlyArray`，名中无前缀 | 214 处 | 该名已在使用 |

异常类的依赖分布如下：`TiqianIllegalArgumentException` 的 301 处分布在 `engine-haxe/src/org` 的 Haxe 源 129 处、`ffi/js/npm` 的生成 TypeScript 104 处、`engine/src/commonTest` 30 处、`engine/src/commonMain` 14 处、文档与工具 24 处；`TiqianNoSuchElementException` 的 26 处分布在 Haxe 源 9 处、生成 TypeScript 5 处、文档与工具 12 处。

## `TiqianArray` 由 boring Swift 后端合成，Tiqian 仓不含该名

boring Swift 后端在 `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` 合成 `TiqianArray`：

- L236 通过 `imports.runtime("TiqianArray")` 引入运行时类型。
- L2810 注释记录 Swift 类型统一检查区分 `TiqianArray` 与 `ReadOnlyArray` 视图。
- L2829-L2830 注释记录「Mutable Array lowers to TiqianArray while ReadOnlyArray lowers to a reference view over TiqianArray」。
- L3031 注释记录可变 Haxe `Array` 编译为 `TiqianArray`。

boring 架构文档 `docs/architecture/INTERFACE-REQUIREMENTS.md` L219 记录 `storage: Representation` 的目标侧存储形态为 `TiqianArray` 与 `[T]`；L235 记录 Storage axis 中 `TiqianArray` 与 `[T]` 对应。

Tiqian 仓源码不含 `TiqianArray`。该名仅出现在 `bundle-logs/swift-f32.test.log` 与 `bundle-logs/swift-f64.test.log`，二者记录 boring 生成的 Swift 测试输出。

处置：记录本清单。`TiqianArray` 的改名发生在 boring 仓；本任务不改 boring 仓，见任务「非目标」。

## 异常名迁移保留 `Tiqian` 前缀

异常改名的决定规定：engine 侧不改名，移植侧全部抛出位置使用 `Tiqian` 开头的类名；不带前缀的 `IllegalArgumentException` 与 `NoSuchElementException` 两个移植类已删除，`engine-haxe/src/org/tiqian/core/` 下现在只有 `TiqianIllegalArgumentException.hx`、`TiqianNoSuchElementException.hx` 与 `IllegalStateException.hx` 三个异常类；engine 侧 Kotlin 内建异常名与移植侧 `Tiqian` 名的差异由 `engine-haxe/tools/compare-traces.py` 的 `EXCEPTION_NAME_ALIASES` 字典处理，跨目标 f64 比对以 L1 判据共用该字典（`engine-haxe/tools/compare-f64-traces.py`）。

`EXCEPTION_NAME_ALIASES` 字典只在 `raises exception=` 行把 `IllegalArgumentException` 与 `TiqianIllegalArgumentException`、`NoSuchElementException` 与 `TiqianNoSuchElementException` 当作同一个名字，其余名字差异与消息差异仍判失败。每次比对输出 `exception-alias=` 计数。

engine 侧的收敛状态按 2026-08-30 的记录如下；`engine/` 目录已在 Kotlin 割接中解散，下列 `engine/src/` 路径现在都不存在，Kotlin 引擎源码现由 boring 从 `engine-haxe/src` 生成：

- `engine/src/commonMain/kotlin/org/tiqian/core/` 下 `TiqianIllegalArgumentException.kt`、`TextRange.kt`、`UnicodeNumber.kt`、`UnicodeWordCharacter.kt`、`EastAsianSpacingData.kt`、`LayoutConstraints.kt` 使用 `TiqianIllegalArgumentException`，这六处是生成代码替换已完成的部分。
- `engine/src/commonTest` 有 6 个文件使用 `TiqianIllegalArgumentException`（对应已替换类的测试），28 个文件使用 Kotlin 内建 `IllegalArgumentException`（对应未替换类的测试）。
- `engine/src/jvmMain/kotlin/org/tiqian/layout/PlanLowering.kt` 使用 Kotlin 内建 `IllegalArgumentException`。
- engine 侧无 `TiqianNoSuchElementException`；`engine/src/commonTest/kotlin/org/tiqian/core/LayoutQueriesResidualCoverageTest.kt` 使用 Kotlin 内建 `NoSuchElementException`。

`IllegalStateException`（`engine-haxe/src/org/tiqian/core/IllegalStateException.hx`）继承 `TiqianIllegalArgumentException`，名中无前缀。异常改名的决定未改此类名，保留现状。

处置：保留 `Tiqian` 前缀（决定），本清单记录依赖分布与收敛过程，不执行去前缀改名。

## 共存窗口的结束条件如下

1. boring 侧保持 `TiqianArray`（可变存储）直到公开视图为 `ReadOnlyArray`。Tiqian 仓记录本窗口判断，不改 boring 仓。
2. `EXCEPTION_NAME_ALIASES` 字典的删除条件原本是「engine 手写 Kotlin 文件被生成代码逐个替换、golden 不再出现 Kotlin 内建异常名」；这两个前提随 Kotlin 割接消失（`engine/` 解散、基准轨迹删除），字典仍在 `engine-haxe/tools/compare-traces.py`，跨目标 f64 比对的 L1 判据继续调用它。
3. `ReadOnlyArray`（`std.ReadOnlyArray`）已作为新视图名使用，无改动。

## 本清单的 boring 观测修订如下

boring 观测修订为 `3f74fbddf8467f9f7e9479aca1edb5a4de0f8c0a`（`flake.nix` L11、`flake.lock`、`.haxelib/boring/git/.boring-flake-revision`）。

