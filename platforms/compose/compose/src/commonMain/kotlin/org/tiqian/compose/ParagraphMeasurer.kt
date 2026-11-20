package org.tiqian.compose

import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineBreakSpan
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
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
        inlineBoxes: List<InlineBoxSpan> = emptyList(),
        sourceBoundaries: Set<Int> = emptySet(),
        lineBreakSpans: List<LineBreakSpan> = emptyList(),
        autoSpaceSuppressedRanges: List<TextRange> = emptyList(),
    ): LayoutResult = measure(
        LayoutInput(
            content = TiqianTextContent(
                text = text,
                spans = spans,
                sourceBoundaries = sourceBoundaries.toList(),
                lineBreakSpans = lineBreakSpans,
                autoSpaceSuppressedRanges = autoSpaceSuppressedRanges,
            ),
            textStyle = textStyle,
            paragraphStyle = paragraphStyle,
            constraints = constraints,
            decorations = decorations,
            rubySpans = rubySpans,
            inlineBoxes = inlineBoxes,
        ),
    )

    /** Internal exact-input entry used by the Compose node's one-result cache. */
    internal fun measure(input: LayoutInput): LayoutResult = engine.layout(input)
}
