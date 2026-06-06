package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.LayoutDebugInfo
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.LineDebugInfo
import org.tiqian.text.core.Size
import org.tiqian.text.core.TextRange

interface ParagraphLayoutEngine {
    fun layout(input: LayoutInput): LayoutResult
}

class ExplainableStubParagraphLayoutEngine : ParagraphLayoutEngine {
    override fun layout(input: LayoutInput): LayoutResult {
        val text = input.content.text
        val fontKey = "unshaped-placeholder"
        val fontSize = input.textStyle.fontSize
        val advance = fontSize

        val clusters = text.mapIndexed { index, char ->
            Cluster(
                range = TextRange(index, index + 1),
                text = char.toString(),
                fontKey = fontKey,
                advance = advance,
            )
        }

        val glyphRun = GlyphRun(
            range = TextRange(0, text.length),
            fontKey = fontKey,
            glyphs = clusters.mapIndexed { glyphId, cluster ->
                Glyph(
                    id = glyphId.toUInt(),
                    clusterRange = cluster.range,
                    advance = cluster.advance,
                )
            },
            advance = clusters.sumOf { it.advance.toDouble() }.toFloat(),
        )

        val naturalWidth = glyphRun.advance.coerceAtMost(input.constraints.maxWidth)
        val lineHeight = input.paragraphStyle.lineHeight ?: fontSize * 1.4f
        val line = LineBox(
            range = TextRange(0, text.length),
            baseline = fontSize,
            top = 0f,
            bottom = lineHeight,
            naturalWidth = naturalWidth,
            adjustedWidth = naturalWidth,
            visualWidth = naturalWidth,
            debug = LineDebugInfo(
                repair = null,
                notes = listOf("ExplainableStubParagraphLayoutEngine emits one unoptimized line."),
            ),
        )

        return LayoutResult(
            input = input,
            size = Size(
                width = naturalWidth,
                height = lineHeight,
            ),
            clusters = clusters,
            glyphRuns = if (text.isEmpty()) emptyList() else listOf(glyphRun),
            lines = listOf(line),
            debug = LayoutDebugInfo(
                fontDecisions = listOf("font:$fontKey:placeholder"),
                metricDecisions = listOf("metrics:raw-placeholder"),
                lineDecisions = listOf("line:single-placeholder"),
            ),
        )
    }
}

