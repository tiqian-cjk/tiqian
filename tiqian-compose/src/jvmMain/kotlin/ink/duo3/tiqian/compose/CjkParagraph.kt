package ink.duo3.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.Layout
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.LookaheadLineBreaker
import ink.duo3.tiqian.core.ColorSpan
import ink.duo3.tiqian.shaping.skia.SkiaFontMetricsResolver
import ink.duo3.tiqian.shaping.skia.SkiaTextShaper
import kotlin.math.ceil

/**
 * Renders [text] as a CJK paragraph with the Tiqian engine (Slice 7, ADR 0017).
 *
 * The composable makes NO layout decisions: measure runs the injected
 * [measurer] against the incoming width constraint and reports
 * `LayoutResult.size`; draw walks the result and paints language-tagged
 * Skia TextBlobs — the same glyph forms the engine measured.
 *
 * Engine units are pixels; map density at the [textStyle] boundary
 * (e.g. `fontSize = 16f * density`) until DPI handling lands.
 */
@Composable
fun CjkParagraph(
    text: String,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    decorations: List<ink.duo3.tiqian.core.DecorationSpan> = emptyList(),
    colorSpans: List<ColorSpan> = emptyList(),
    spans: List<TextSpan> = emptyList(),
    rubySpans: List<ink.duo3.tiqian.core.RubySpan> = emptyList(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(profile),
) {
    // The measure-produced result is read back during the DRAW phase. A plain
    // remembered holder (not snapshot state) avoids writing observable state
    // inside the measure lambda; a re-measure always schedules the re-draw that
    // reads it, so draw never sees a stale result.
    val holder = remember { ParagraphLayoutHolder() }
    Layout(
        modifier = modifier.drawBehind {
            holder.result?.let { drawParagraph(it, colorSpans = colorSpans, spans = spans) }
        },
        content = {},
    ) { _, constraints ->
        val maxWidth = if (constraints.hasBoundedWidth) {
            constraints.maxWidth.toFloat()
        } else {
            DEFAULT_UNBOUNDED_WIDTH
        }
        val laidOut = measurer.measure(
            text = text,
            constraints = LayoutConstraints(maxWidth = maxWidth),
            textStyle = textStyle,
            paragraphStyle = paragraphStyle,
            decorations = decorations,
            spans = spans,
            rubySpans = rubySpans,
        )
        holder.result = laidOut
        layout(
            width = ceil(laidOut.size.width).toInt().coerceIn(constraints.minWidth, constraints.maxWidth),
            // Clamp to the bounded height too (overflow is clipped, like Compose text);
            // maxHeight is Constraints.Infinity when unbounded → no effective clamp.
            height = ceil(laidOut.size.height).toInt().coerceIn(constraints.minHeight, constraints.maxHeight),
        ) {}
    }
}

/** Non-snapshot holder for the measure→draw handoff (see [CjkParagraph]). */
private class ParagraphLayoutHolder {
    var result: ink.duo3.tiqian.core.LayoutResult? = null
}

/**
 * Default measurer: Skia shaper (real advances + halt/locl) + lookahead breaker,
 * resolving every paragraph to [profile]. Customize CLREQ behaviour (禁则档、
 * 标点宽度、中西自动间距、挤压风格…) by passing e.g.
 * `ClreqProfile.MainlandHorizontal.copy(punctuationWidth = …)`.
 */
@Composable
fun rememberParagraphMeasurer(
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
): ParagraphMeasurer =
    remember(profile) {
        ParagraphMeasurer(
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                textShaper = SkiaTextShaper(),
                fontMetricsResolver = SkiaFontMetricsResolver(),
                clreqProfileResolver = { profile },
            ),
        )
    }

private const val DEFAULT_UNBOUNDED_WIDTH = 65_536f
