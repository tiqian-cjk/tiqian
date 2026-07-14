package org.tiqian.layout

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

private fun StringBuilder.appendJsonNumber(value: Float): StringBuilder =
    append(if (value == -0f) "0" else value.toString())

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
