package ink.duo3.tiqian.compose

import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.RubySpan
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.layout.ParagraphLayoutEngine

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
    ): LayoutResult =
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(text, spans),
                textStyle = textStyle,
                paragraphStyle = paragraphStyle,
                constraints = constraints,
                decorations = decorations,
                rubySpans = rubySpans,
            ),
        )
}
