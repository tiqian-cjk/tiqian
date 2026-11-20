# ADR 0059: Glyph.id 由 UInt 改为 Int

- Status: Accepted
- Date: 2026-11-11
- Relates: [ADR 0056](0056-engine-module-and-platform-reorg.md)（引擎模块重组）、
  [ADR 0050](0050-font-backend-vtable-protocol.md)（字体后端 vtable）

本文记录 Kotlin 割接中三类公开 API 差异的处理。第 ① 类是 `Glyph.id` 的整数类型，
判据是修正选错的公开类型；第 ② 类是 `Char` 到 `String` 的类型映射，判据是跨目标
一致性；第 ③ 类是集合与对象默认值的可空化，判据是语言能力差异。以下 Context /
Decision / Consequences 三节属于第 ① 类。

## Context

`Glyph.id` 是 OpenType 字形编号，规范定义为 uint16（0–65535）。手写引擎把它声明为
`UInt`（`engine/src/commonMain/kotlin/org/tiqian/core/LayoutModel.kt:45`）。四个平台
塑造器为构造它各写了一次 `.toUInt()`，另有一处用 `.toUInt()` 做缺失字形比较。

Haxe 移植把该字段声明为 `Int`。最小探针（一个 `UInt` 字段、一个 `UInt` 参数与返回、
一处 `UInt` 与 `Int` 比较）显示 boring 把 Haxe `UInt` 在三条路径上统一降为 Kotlin
`Int`，移植源无法表达 `UInt`。

## Decision

`Glyph.id` 的类型改为 `Int`。

字形编号的取值范围由规范限定为 0–65535，`Int` 完整容纳，不丢信息。`UInt` 的实际效果
是要求每个消费方写 `.toUInt()`，换来的是类型上不能为负，而字形编号本来就不会为负。
因此这是修正一个选错的公开类型。

## Consequences

- 源码不兼容：给 `Glyph.id` 赋 `UInt` 的调用方要去掉 `.toUInt()`。
- 二进制兼容：JVM 上 `UInt` 与 `Int` 都是 32 位有符号整数，方法签名不变。
- 迁移：四个平台塑造器去掉 `.toUInt()`；缺失字形比较改用 `font.missingGlyphCode`。
- 不变量：字形编号必须落在 [0, 65535]。`Glyph` 构造函数在越界时抛
  `IllegalStateException`，全量测试覆盖该断言。

## 决定 2: `Char` 改为 `String`（跨目标一致性）

手写引擎的公开 API 把单个字符声明为 `Char`，例如 `PunctuationAtomBuilder.build` 的
`char` 参数与 `GlyphRun` 的相关字段。Haxe 没有 `Char` 类型；移植源把同一位置声明为
`String`，生成物因此是 `String`。

给移植源增加 `std.Char` 会让同一份源在 Kotlin 目标映射为 `Char`，在 Dart 与 TS 目标
映射为 `String`：Dart 与 TS 没有 char 类型，单字符就是长度 1 的字符串。同一份源产生
两种公开类型，跨目标一致性被破坏。因此统一用 `String`，把 `Char` 视为 Kotlin 目标的
类型细节，不进入移植源。

后果：Kotlin 消费方把 `Char` 实参改成 `String`。割接清单里这一类共 12 处。

## 决定 3: 集合与对象默认值改为可空（语言能力差异）

手写引擎的公开函数给集合与对象参数声明了非空的 Kotlin 默认值，例如 `emptyList()`、
`UnbreakableRanges.Empty`、`Float.POSITIVE_INFINITY`、`PunctuationWidthPolicy()`。
Haxe 的默认参数值必须是编译期常量，这些表达式都不是；移植源只能把参数声明为可空
（`?x`），生成物因此是 `X? = null`。

这条按类型类别划分，不按函数划分：

- 基本类型与常量（`Int`、`Float`、`Bool`、枚举值）可以表达成编译期常量，移植源使用
  非空默认值。`breakLines` 的 4 个基本类型参数属于这一类：`firstLineIndent: Float = 0.0`、
  `sinoWesternStretchCap: Float = 0.0`、`lineAdjustmentPushIn: Boolean = false`、
  `lineAdjustmentCompressBias: Float = 1.0`。
- 集合与对象构造不能表达成编译期常量，移植源使用可空参数。`breakLines` 的 11 个
  集合/对象参数原本有非空默认值，移植源改为可空：`shrinkOpportunities`、
  `unbreakableRanges`、`hangableClusters`、`extendableHangRanges`、
  `forbiddenLineEndClusters`、`hyphenBreakClusters`、`cjkInterCharBoundaries`、
  `sinoWesternBoundaries`、`hardBreakAfterClusters`、`nonRenderingControlClusters`、
  `progressiveBreakOpportunities`。
- `maxCjkStretchPerGap` 是基本类型，但默认值 `Float.POSITIVE_INFINITY` 不是编译期
  常量，因此保持可空。`forbiddenLineStartClusters` 在已发布 API 中本来就是可空
  （`Set<Int>? = null`），不属于本类改动。

后果：Kotlin 消费方省略这些参数时得到 `null`，需要按函数语义回退到原来的默认值。
