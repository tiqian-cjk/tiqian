package org.tiqian.compose

import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubySpan
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ParagraphLayoutEngine

/**
 * Lays out a CJK paragraph with the Tiqian engine and returns the measured
 * [LayoutResult]. A thin Compose-side wrapper over [ParagraphLayoutEngine] —
 * it makes no layout decisions of its own. The [engine] is required (no default)
 * so a caller never accidentally measures with the stub shaper on a real canvas;
 * use [rememberParagraphMeasurer] for the platform default.
 */
class ParagraphMeasurer(
    private val engine: ParagraphLayoutEngine,
) {
    fun measure(
        text: String,
        constraints: LayoutConstraints,
        textStyle: TextStyle = TextStyle(),
        paragraphStyle: ParagraphStyle = ParagraphStyle(),
        decorations: List<DecorationSpan> = emptyList(),
        spans: List<TextSpan> = emptyList(),
        rubySpans: List<RubySpan> = emptyList(),
        sourceBoundaries: Set<Int> = emptySet(),
    ): LayoutResult =
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(text, spans, sourceBoundaries),
                textStyle = textStyle,
                paragraphStyle = paragraphStyle,
                constraints = constraints,
                decorations = decorations,
                rubySpans = rubySpans,
            ),
        )
}
