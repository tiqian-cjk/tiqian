package ink.duo3.tiqian.clreq

/**
 * `NumberSymbolCohesion` — CLREQ §符号分离禁则（数字及其相应的前后缀单位符号）:
 * an Arabic-number run and the symbols bound to it must not split across two
 * lines.
 *
 * 1. 阿拉伯数字应作为一个整体（含内部小数点/千分位 `.` `,`）。
 * 2. 后缀 `%` `‰` `°` `℃` `℉` 与其**前面**的数字之间不能拆行。
 * 3. 前缀正号 `+`、负号 `-`、正负号 `±` 与其**后面**的数字之间不能拆行。
 * 4. 货币符号与相关数字不能拆行（前置如 `¥`、后置如 `₫`）。
 *
 * Returns SOURCE-text ranges (inclusive `start..end`) the line breaker must
 * keep unbroken. Cases that already shape into one cluster (e.g. `-3`, `100`,
 * `100km`) yield a range with no interior break point — harmless; the cases
 * this actually protects are the ones that split into separate clusters
 * (`50%`, `¥100`, `+5`, `37℃`, `±2`).
 */
object NumberSymbolCohesion {
    private val PREFIX_SIGN = setOf('+', '-', '±')
    private val SUFFIX_UNIT = setOf('%', '‰', '°', '℃', '℉', '′', '″')
    private val FRONT_CURRENCY = setOf('¥', '￥', '$', '＄', '€', '£', '₩', '₽', '₹', '฿')
    private val BACK_CURRENCY = setOf('₫')

    fun unbreakableRanges(text: String): List<IntRange> {
        val result = mutableListOf<IntRange>()
        var i = 0
        while (i < text.length) {
            if (!text[i].isDigit()) {
                i++
                continue
            }
            // Maximal digit run, absorbing an interior '.' / ',' only when it
            // sits between two digits (decimal point / thousands separator, not
            // a sentence-final 句号 or a list comma).
            var end = i
            while (end + 1 < text.length) {
                val c = text[end + 1]
                if (c.isDigit()) {
                    end++
                } else if ((c == '.' || c == ',') && end + 2 < text.length && text[end + 2].isDigit()) {
                    end += 2
                } else {
                    break
                }
            }
            var start = i
            // Prefix: one sign or front currency symbol immediately before.
            if (start > 0 && (text[start - 1] in PREFIX_SIGN || text[start - 1] in FRONT_CURRENCY)) {
                start--
            }
            // Suffix: a run of unit symbols, then optionally one back currency.
            while (end + 1 < text.length && text[end + 1] in SUFFIX_UNIT) end++
            if (end + 1 < text.length && text[end + 1] in BACK_CURRENCY) end++

            result += start..end
            i = end + 1
        }
        return result
    }
}
