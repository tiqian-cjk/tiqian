package ink.duo3.tiqian.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.LayoutModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.node.invalidateMeasurement
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
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
    // Backed by a single Modifier.Node (like BasicText): it owns BOTH measure and draw,
    // and its update() explicitly invalidates measurement AND draw on any param change.
    // That's what makes editing repaint even when the new content lays out to the SAME
    // size — routing a measure-phase result through snapshot state + drawBehind only
    // repaints on relayout, leaving stale glyphs while typing.
    Box(
        modifier.then(
            CjkParagraphElement(
                text, textStyle, paragraphStyle, color,
                decorations, colorSpans, spans, rubySpans, measurer, onTextLayout,
            ),
        ),
    )
}

/** Backs [CjkParagraphImpl] — a measure+draw [Modifier.Node] that repaints on update. */
private class CjkParagraphElement(
    private val text: String,
    private val textStyle: TextStyle,
    private val paragraphStyle: ParagraphStyle,
    private val color: Int,
    private val decorations: List<DecorationSpan>,
    private val colorSpans: List<ColorSpan>,
    private val spans: List<TextSpan>,
    private val rubySpans: List<RubySpan>,
    private val measurer: ParagraphMeasurer,
    private val onTextLayout: (LayoutResult) -> Unit,
) : ModifierNodeElement<CjkParagraphNode>() {
    override fun create() = CjkParagraphNode(
        text, textStyle, paragraphStyle, color, decorations, colorSpans, spans, rubySpans, measurer, onTextLayout,
    )

    override fun update(node: CjkParagraphNode) = node.update(
        text, textStyle, paragraphStyle, color, decorations, colorSpans, spans, rubySpans, measurer, onTextLayout,
    )

    override fun equals(other: Any?): Boolean =
        other is CjkParagraphElement && text == other.text && textStyle == other.textStyle &&
            paragraphStyle == other.paragraphStyle && color == other.color &&
            decorations == other.decorations && colorSpans == other.colorSpans &&
            spans == other.spans && rubySpans == other.rubySpans && measurer === other.measurer &&
            onTextLayout === other.onTextLayout

    override fun hashCode(): Int {
        var r = text.hashCode()
        r = 31 * r + textStyle.hashCode()
        r = 31 * r + paragraphStyle.hashCode()
        r = 31 * r + color
        r = 31 * r + decorations.hashCode()
        r = 31 * r + colorSpans.hashCode()
        r = 31 * r + spans.hashCode()
        r = 31 * r + rubySpans.hashCode()
        r = 31 * r + measurer.hashCode()
        r = 31 * r + onTextLayout.hashCode()
        return r
    }
}

private class CjkParagraphNode(
    private var text: String,
    private var textStyle: TextStyle,
    private var paragraphStyle: ParagraphStyle,
    private var color: Int,
    private var decorations: List<DecorationSpan>,
    private var colorSpans: List<ColorSpan>,
    private var spans: List<TextSpan>,
    private var rubySpans: List<RubySpan>,
    private var measurer: ParagraphMeasurer,
    private var onTextLayout: (LayoutResult) -> Unit,
) : Modifier.Node(), LayoutModifierNode, DrawModifierNode {

    private var result: LayoutResult? = null

    fun update(
        text: String,
        textStyle: TextStyle,
        paragraphStyle: ParagraphStyle,
        color: Int,
        decorations: List<DecorationSpan>,
        colorSpans: List<ColorSpan>,
        spans: List<TextSpan>,
        rubySpans: List<RubySpan>,
        measurer: ParagraphMeasurer,
        onTextLayout: (LayoutResult) -> Unit,
    ) {
        this.text = text
        this.textStyle = textStyle
        this.paragraphStyle = paragraphStyle
        this.color = color
        this.decorations = decorations
        this.colorSpans = colorSpans
        this.spans = spans
        this.rubySpans = rubySpans
        this.measurer = measurer
        this.onTextLayout = onTextLayout
        invalidateMeasurement() // re-measure (size/result may change)
        invalidateDraw()        // AND repaint even when the new content is the same size
    }

    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): MeasureResult {
        val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth.toFloat() else DEFAULT_UNBOUNDED_WIDTH
        val laidOut = measurer.measure(
            text = text,
            constraints = LayoutConstraints(maxWidth = maxWidth),
            textStyle = textStyle,
            paragraphStyle = paragraphStyle,
            decorations = decorations,
            spans = spans,
            rubySpans = rubySpans,
        )
        result = laidOut
        onTextLayout(laidOut)
        // The drawn content (incl. 行间装饰 overhang) paints from draw(); the empty inner
        // content is placed at 0. Report FULL content height (floored to minHeight) — no
        // maxHeight clamp (no clip): a height-bounded parent decides to scroll/clip.
        val placeable = measurable.measure(Constraints.fixed(0, 0))
        val w = ceil(laidOut.size.width).toInt().coerceIn(constraints.minWidth, constraints.maxWidth)
        val h = ceil(laidOut.size.height).toInt().coerceAtLeast(constraints.minHeight)
        return layout(w, h) { placeable.place(0, 0) }
    }

    override fun ContentDrawScope.draw() {
        result?.let { drawParagraph(it, color = color, colorSpans = colorSpans, spans = spans) }
        drawContent()
    }
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
