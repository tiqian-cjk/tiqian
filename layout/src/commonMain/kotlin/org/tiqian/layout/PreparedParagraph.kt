package org.tiqian.layout

import kotlin.math.abs
import org.tiqian.core.LayoutResult
import org.tiqian.core.TextRange
import org.tiqian.core.positionedClusters

/**
 * Canonical plain-paragraph render plan shared by build-time snapshots and the
 * browser exact-font fallback. Keeping this lowering beside [LayoutResult]
 * prevents the two Web entry points from growing independent DOM geometry.
 */
fun LayoutResult.toPreparedParagraphJson(): String {
    val naturalWidth = mutableMapOf<TextRange, Float>()
    val openTypeFeatures = mutableMapOf<TextRange, LinkedHashSet<String>>()
    for (run in glyphRuns) {
        for (glyph in run.glyphs) {
            naturalWidth[glyph.clusterRange] =
                (naturalWidth[glyph.clusterRange] ?: 0f) + glyph.advance
            if (run.openTypeFeatures.isNotEmpty()) {
                openTypeFeatures.getOrPut(glyph.clusterRange) { linkedSetOf() }
                    .addAll(run.openTypeFeatures)
            }
        }
    }
    val zeroWidthBreaks = debug.zeroWidthBreakDecisions.mapTo(mutableSetOf()) { it.range }
    return buildString {
        append('{')
        append("\"schema\":1,")
        append("\"layoutRevision\":\"tiqian-layout-v2\",")
        append("\"width\":").appendJsonNumber(input.constraints.maxWidth).append(',')
        append("\"height\":").appendJsonNumber(size.height).append(',')
        append("\"lines\":[")
        lines.forEachIndexed { lineIndex, line ->
            if (lineIndex > 0) append(',')
            val cells = positionedClusters(line).filter { positioned ->
                val cluster = clusters[positioned.clusterIndex]
                cluster.displayText.isNotEmpty() || cluster.range in zeroWidthBreaks
            }
            append('{')
            append("\"rangeStart\":").append(line.range.start).append(',')
            append("\"rangeEnd\":").append(line.range.end).append(',')
            append("\"top\":").appendJsonNumber(line.top).append(',')
            append("\"bottom\":").appendJsonNumber(line.bottom).append(',')
            append("\"baseline\":").appendJsonNumber(line.baseline).append(',')
            append("\"indent\":").appendJsonNumber(line.indent).append(',')
            append("\"visualWidth\":").appendJsonNumber(line.visualWidth).append(',')
            append("\"hyphenAdvance\":").appendJsonNumber(line.hyphenAdvance).append(',')
            append("\"endReason\":").appendJsonString(line.endReason.name).append(',')
            append("\"cells\":[")
            cells.forEachIndexed { cellIndex, positioned ->
                if (cellIndex > 0) append(',')
                val cluster = clusters[positioned.clusterIndex]
                append('{')
                append("\"rangeStart\":").append(cluster.range.start).append(',')
                append("\"rangeEnd\":").append(cluster.range.end).append(',')
                append("\"source\":").appendJsonString(cluster.text).append(',')
                append("\"display\":").appendJsonString(cluster.displayText).append(',')
                append("\"drawX\":").appendJsonNumber(positioned.drawX).append(',')
                append("\"naturalWidth\":")
                    .appendJsonNumber(naturalWidth[cluster.range] ?: cluster.advance).append(',')
                append("\"leadingLayoutAdvance\":")
                    .appendJsonNumber(cluster.leadingLayoutAdvance)
                // MultiCodeUnitShapingBoundary: Latin words, URLs, emoji, and
                // other multi-unit clusters are already independently shaped
                // by the core. DOM text must not merge adjacent clusters and
                // ask the browser to shape a different, wider run.
                if (cluster.range.end - cluster.range.start > 1) {
                    append(",\"shapingBoundary\":true")
                }
                openTypeFeatures[cluster.range]?.takeIf { it.isNotEmpty() }?.let { features ->
                    append(",\"openTypeFeatures\":[")
                    features.forEachIndexed { featureIndex, feature ->
                        if (featureIndex > 0) append(',')
                        appendJsonString(feature)
                    }
                    append(']')
                }
                append('}')
            }
            append("]}")
        }
        append("]}")
    }
}

/**
 * Plan JSON numbers use ECMAScript `Number::toString` layout on every Kotlin
 * backend. `Float.toString` differs per platform: Kotlin/JS prints the f64
 * widening, JVM and Native print the f32 shortest form with a forced fraction.
 * Without normalization the same LayoutResult yields different plan bytes per
 * host. Digits come from `Double.toString`; the last digit is normalized from
 * the exact Float expansion; only the layout is normalized here.
 */
private fun StringBuilder.appendJsonNumber(value: Float): StringBuilder =
    append(if (value == -0f) "0" else ecmaJsonNumber(value))

private fun ecmaJsonNumber(floatValue: Float): String {
    val raw = floatValue.toDouble().toString()
    val negative = raw.startsWith("-")
    val body = if (negative) raw.substring(1) else raw
    val exponentAt = body.indexOfFirst { it == 'e' || it == 'E' }
    val mantissa = if (exponentAt >= 0) body.substring(0, exponentAt) else body
    val exponent = if (exponentAt >= 0) body.substring(exponentAt + 1).toInt() else 0
    val dotAt = mantissa.indexOf('.')
    val integerPart = if (dotAt >= 0) mantissa.substring(0, dotAt) else mantissa
    val fractionPart = if (dotAt >= 0) mantissa.substring(dotAt + 1) else ""

    // digits × 10^(n - digits.length) == value, digits without leading or
    // trailing zeros.
    var digits = if (integerPart.any { it != '0' }) integerPart + fractionPart else fractionPart
    var decimalExponent = if (integerPart.any { it != '0' }) integerPart.length else 0
    decimalExponent += exponent
    val firstSignificant = digits.indexOfFirst { it != '0' }
    if (firstSignificant < 0) return "0"
    if (firstSignificant > 0) {
        digits = digits.substring(firstSignificant)
        decimalExponent -= firstSignificant
    }
    val lastSignificant = digits.indexOfLast { it != '0' }
    if (lastSignificant < digits.length - 1) {
        digits = digits.substring(0, lastSignificant + 1)
    }

    val k = digits.length
    val n = decimalExponent
    digits = canonicalTieBreak(digits, floatValue)
    val magnitude = if (negative) "-" else ""
    return when {
        k <= n && n <= 21 -> magnitude + digits + "0".repeat(n - k)
        0 < n && n <= 21 -> magnitude + digits.substring(0, n) + "." + digits.substring(n)
        -6 < n && n <= 0 -> magnitude + "0." + "0".repeat(-n) + digits
        else -> {
            val mantissaText = if (k > 1) digits[0] + "." + digits.substring(1) else digits[0].toString()
            val exponentValue = n - 1
            val exponentSign = if (exponentValue < 0) "-" else "+"
            magnitude + mantissaText + "e" + exponentSign + abs(exponentValue).toString()
        }
    }
}

/**
 * dtoa libraries disagree only in the last digit of their shortest strings:
 * on exact decimal ties ECMAScript rounds half to even while some dtoa round
 * half up. Every number here is a Float, so the exact decimal expansion
 * (mantissa × 2^exponent with a 24-bit mantissa) is finite and small; rounding
 * that expansion to the platform digit count with half to even reproduces the
 * ECMAScript choice on every backend.
 */
private fun canonicalTieBreak(digits: String, value: Float): String {
    val bits = value.toRawBits() and 0x7FFFFFFF
    val biasedExponent = (bits ushr 23) and 0xFF
    var mantissa = bits and 0x7FFFFF
    if (mantissa == 0 && biasedExponent == 0) return digits
    val exponent = if (biasedExponent == 0) {
        -149
    } else {
        mantissa = mantissa or 0x800000
        biasedExponent - 150
    }

    var exact = mantissa.toString()
    if (exponent >= 0) {
        repeat(exponent) { exact = timesSmall(exact, 2) }
    } else {
        // value = mantissa × 5^k × 10^-k; only the digits matter here, the
        // caller keeps the decimal scale.
        repeat(-exponent) { exact = timesSmall(exact, 5) }
    }
    val stripped = exact.trimEnd('0')
    if (stripped.length <= digits.length) return digits

    val keep = stripped.substring(0, digits.length)
    val remainder = stripped.substring(digits.length)
    val pastHalf = remainder.length > 1 && remainder.substring(1).any { it != '0' }
    val roundUp = when {
        remainder[0] > '5' -> true
        remainder[0] < '5' -> false
        // Exact half rounds to even.
        else -> pastHalf || (keep.last() - '0') % 2 != 0
    }
    val canonical = if (roundUp) incrementDecimal(keep) else keep
    // A shorter result means the platform string was not shortest; a longer
    // one means a carry changed the digit count. Either way the platform
    // string is the safer answer.
    return if (canonical.trimEnd('0').length == digits.length) canonical else digits
}

private fun timesSmall(digits: String, factor: Int): String {
    val out = StringBuilder()
    var carry = 0
    for (index in digits.length - 1 downTo 0) {
        val product = (digits[index] - '0') * factor + carry
        out.append('0' + product % 10)
        carry = product / 10
    }
    while (carry > 0) {
        out.append('0' + carry % 10)
        carry /= 10
    }
    return out.reverse().toString()
}

private fun incrementDecimal(digits: String): String {
    val chars = StringBuilder(digits)
    var index = chars.length - 1
    while (true) {
        if (chars[index] < '9') {
            chars[index] = chars[index] + 1
            return chars.toString()
        }
        chars[index] = '0'
        if (index == 0) return "1" + chars
        index -= 1
    }
}

private fun StringBuilder.appendJsonString(value: String): StringBuilder {
    append('"')
    for (char in value) {
        when (char) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000c' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (char.code < 0x20) {
                append("\\u").append(char.code.toString(16).padStart(4, '0'))
            } else {
                append(char)
            }
        }
    }
    return append('"')
}
