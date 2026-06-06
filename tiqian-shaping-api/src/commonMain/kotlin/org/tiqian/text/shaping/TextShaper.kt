package org.tiqian.text.shaping

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.TextRange
import org.tiqian.text.core.TextStyle
import org.tiqian.text.font.FontDecision

data class ShapingInput(
    val text: String,
    val range: TextRange,
    val style: TextStyle,
    val fontDecision: FontDecision,
)

data class ShapingResult(
    val clusters: List<Cluster>,
    val glyphRuns: List<GlyphRun>,
)

interface TextShaper {
    fun shape(input: ShapingInput): ShapingResult
}

class UnimplementedTextShaper : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        error("Text shaping is platform-specific and has not been wired for this target yet.")
    }
}

