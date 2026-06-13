package ink.duo3.tiqian.shaping

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.Glyph
import ink.duo3.tiqian.core.GlyphRun
import ink.duo3.tiqian.core.ShapingDecisionInfo
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.font.FontDecision

data class ShapingInput(
    val text: String,
    val range: TextRange,
    val style: TextStyle,
    val fontDecision: FontDecision,
    val displayText: String = text.substring(range.start, range.end),
)

data class ShapingResult(
    val clusters: List<Cluster>,
    val glyphRuns: List<GlyphRun>,
    val decisions: List<ShapingDecisionInfo> = emptyList(),
)

interface TextShaper {
    fun shape(input: ShapingInput): ShapingResult
}

enum class ShapingSource {
    Stub,
    JvmAwt,
    AndroidPaint,
    Skia,
    HarfBuzz,
}

class ExplainableStubTextShaper : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val glyphCount = input.displayText.codePointCount().coerceAtLeast(1)
        val advance = input.style.fontSize * sourceText.nominalAdvanceEm(input.displayText)
        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            displayText = input.displayText,
            fontKey = input.fontDecision.candidate.key,
            advance = advance,
        )
        val glyphAdvance = advance / glyphCount
        val glyphs = (0 until glyphCount).map { glyphId ->
            Glyph(
                id = glyphId.toUInt(),
                clusterRange = input.range,
                advance = glyphAdvance,
            )
        }
        val run = GlyphRun(
            range = input.range,
            fontKey = input.fontDecision.candidate.key,
            glyphs = glyphs,
            advance = advance,
        )
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = sourceText,
            displayText = input.displayText,
            fontKey = input.fontDecision.candidate.key,
            glyphCount = glyphCount,
            advance = advance,
            source = ShapingSource.Stub.name,
            reason = "ExplainableStubTextShaper:nominal-em-advance",
            // The stub never measures ink; report all glyphs as boundless so
            // the dump honestly shows this path provides no ink diagnostics.
            glyphsWithoutInkBounds = glyphCount,
        )
        return ShapingResult(
            clusters = listOf(cluster),
            glyphRuns = listOf(run),
            decisions = listOf(decision),
        )
    }

    private fun String.nominalAdvanceEm(displayText: String): Float =
        when {
            this == "⸺" || displayText == "⸺" -> 2f
            // U+0020 in a Simplified-Chinese grid is 二分空 (half-em), not a
            // full-width blank. The deterministic stub models each space as
            // 0.5em so word spaces and sino-western gaps sit at realistic
            // sub-/at-em widths instead of an artificial 1em.
            isNotEmpty() && all { it == ' ' } -> 0.5f * length
            else -> maxOf(codePointCount(), displayText.codePointCount()).toFloat()
        }

    private fun String.codePointCount(): Int {
        var count = 0
        var index = 0
        while (index < length) {
            val char = this[index]
            index += if (char.isHighSurrogate() && index + 1 < length && this[index + 1].isLowSurrogate()) {
                2
            } else {
                1
            }
            count += 1
        }
        return count
    }
}

class UnimplementedTextShaper : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        error("Text shaping is platform-specific and has not been wired for this target yet.")
    }
}
