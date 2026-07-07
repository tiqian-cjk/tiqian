package org.tiqian.core

import kotlin.jvm.JvmInline

/**
 * `ic` —— 提椠的 CJK 原生长度单位（ADR 0034）：N 个**字身框**进格。直接采用 W3C CSS
 * Values L4 的 `ic` 单位（「表意字身的 advance」），即字身框宽。CSS 用探测 '水'(U+6C34)
 * 字形定义它；提椠用字体声明的字身框（ADR 0002 的 BASE `ideo/idtp`）解析它——同一单位，
 * 来源更稳。
 *
 * `ic` 只是个计数；解析成 px 时按上下文的字身框进格 [toPx]：段级锚段落基准字号、行内锚
 * 该 gap owner 的字号（与 ADR 0030 per-gap-owner 一致）。横排全宽 CJK 的字身框宽 = 1em
 * = 字号，故 `Ic(n).toPx(fontSize) = n × fontSize`——数值同旧「em」，价值在语义 + 类型
 * 安全 + 锚点明确。`fontSize` 自身**不**用 `ic`（它定义了一个字身框）。
 */
@JvmInline
value class Ic(val count: Float) {
    /** 解析成 px：[emPx] = 该上下文的字身框进格（横排全宽 CJK = 字号）。 */
    fun toPx(emPx: Float): Float = count * emPx

    operator fun plus(other: Ic): Ic = Ic(count + other.count)
    operator fun unaryMinus(): Ic = Ic(-count)

    companion object {
        val Zero: Ic = Ic(0f)
    }
}

/** 作者面字面量：`2f.ic` / `0.25f.ic`。 */
val Float.ic: Ic get() = Ic(this)

/** 作者面字面量：`40.ic` / `2.ic`。 */
val Int.ic: Ic get() = Ic(toFloat())
