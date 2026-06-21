package ink.duo3.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.ColorSpan
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.RubySpan
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.LookaheadLineBreaker
import ink.duo3.tiqian.shaping.skia.SkiaFontMetricsResolver
import ink.duo3.tiqian.shaping.skia.SkiaTextShaper
import kotlin.math.ceil

/**
 * Renders [text] as a CJK paragraph with the Tiqian engine (Slice 7, ADR 0017).
 *
 * The composable makes NO layout decisions: measure runs the injected [measurer]
 * against the incoming width constraint and reports `LayoutResult.size`; draw walks
 * the result and paints language-tagged Skia TextBlobs — the same glyph forms the
 * engine measured.
 *
 * [textStyle] is the Compose-facing [CjkTextStyle] (`.sp`/`Color`/`FontFamily`),
 * lowered to engine px via `LocalDensity` here — callers no longer hand-multiply
 * density. The component reports its FULL content height (no vertical truncation —
 * that's a `maxLines` feature we don't have yet); [onTextLayout] reports that same
 * [LayoutResult]. We deliberately do NOT `clipToBounds`: 行间装饰 (ruby overhang,
 * 注音 right zone, 着重号/示亡号 in the line gap) legitimately paint outside the
 * content box and must not be cut.
 */
@Composable
fun CjkParagraph(
    text: String,
    modifier: Modifier = Modifier,
    textStyle: CjkTextStyle = CjkTextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    val density = LocalDensity.current
    CjkParagraphImpl(
        text = text,
        modifier = modifier,
        textStyle = textStyle.toCoreTextStyle(density),
        paragraphStyle = paragraphStyle.copy(
            lineHeight = textStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight,
        ),
        color = textStyle.colorArgbOrNull() ?: DEFAULT_TEXT_COLOR,
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Advanced/bridge entry: explicit parallel span lists (装饰/颜色/样式/ruby) the
 * author-facing `CjkParagraph(AnnotatedString)` derives. Kept `internal` so normal
 * callers don't hand-align four range lists (Codex #6).
 *
 * The composable makes NO layout decisions: measure runs the injected [measurer]
 * against the width constraint and reports `LayoutResult.size`; draw walks the
 * result and paints language-tagged Skia TextBlobs. [onTextLayout] surfaces the
 * (explainable) [LayoutResult] for baseline/hit-test/debug consumers.
 *
 * Engine units are pixels; map density at the [textStyle]/`ic` boundary until DPI
 * handling lands.
 */
@Composable
internal fun CjkParagraphImpl(
    text: String,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    color: Int = DEFAULT_TEXT_COLOR,
    decorations: List<DecorationSpan> = emptyList(),
    colorSpans: List<ColorSpan> = emptyList(),
    spans: List<TextSpan> = emptyList(),
    rubySpans: List<RubySpan> = emptyList(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    // The measure-produced result is read back during the DRAW phase. A plain
    // remembered holder (not snapshot state) avoids writing observable state
    // inside the measure lambda; a re-measure always schedules the re-draw that
    // reads it, so draw never sees a stale result.
    val holder = remember { ParagraphLayoutHolder() }
    Layout(
        // No clipToBounds: 行间装饰 (ruby overhang, 注音 right zone, 着重号/示亡号 in the
        // line gap) paint outside the engine-reported content box on purpose; clipping to
        // `size` would cut them. The component reports its full height (below) so the
        // reported box matches what's drawn — vertical truncation is a maxLines feature.
        modifier = modifier.drawBehind {
            holder.result?.let { drawParagraph(it, color = color, colorSpans = colorSpans, spans = spans) }
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
        onTextLayout(laidOut)
        layout(
            width = ceil(laidOut.size.width).toInt().coerceIn(constraints.minWidth, constraints.maxWidth),
            // Report the FULL content height (only floored to minHeight) — no clamp to
            // maxHeight: with no clip, clamping would report a box shorter than what we
            // draw. A height-bounded parent decides whether to scroll/clip itself.
            height = ceil(laidOut.size.height).toInt().coerceAtLeast(constraints.minHeight),
        ) {}
    }
}

/** Non-snapshot holder for the measure→draw handoff (see [CjkParagraph]). */
private class ParagraphLayoutHolder {
    var result: LayoutResult? = null
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
internal const val DEFAULT_TEXT_COLOR: Int = 0xFF000000.toInt()
