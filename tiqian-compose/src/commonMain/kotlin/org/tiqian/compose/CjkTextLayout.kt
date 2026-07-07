package org.tiqian.compose

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.LayoutModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.SemanticsModifierNode
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.node.invalidateMeasurement
import androidx.compose.ui.node.invalidateSemantics
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubySpan
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.glyphInkBounds
import org.tiqian.core.getOffsetForPosition
import org.tiqian.core.positionedClusters
import kotlin.math.ceil

/**
 * Internal renderer node used by the public `CjkText` facades. It takes fully lowered core
 * style/span lists and only measures/draws the resulting Tiqian [LayoutResult].
 *
 * The composable makes NO layout decisions: measure runs the injected [measurer]
 * against the width constraint and reports `LayoutResult.size`; draw delegates
 * to the target renderer. [onTextLayout] surfaces the
 * (explainable) [LayoutResult] for baseline/hit-test/debug consumers.
 *
 * Engine units are pixels; map density at the [textStyle]/`ic` boundary until DPI
 * handling lands.
 */
@Composable
internal fun CjkTextLayout(
    text: String,
    semanticsText: AnnotatedString = AnnotatedString(text),
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    color: Int = DEFAULT_TEXT_COLOR,
    decorations: List<DecorationSpan> = emptyList(),
    colorSpans: List<ColorSpan> = emptyList(),
    richTextSpans: List<RichTextSpan> = emptyList(),
    spans: List<TextSpan> = emptyList(),
    rubySpans: List<RubySpan> = emptyList(),
    softWrap: Boolean = true,
    overflow: TextOverflow = TextOverflow.Visible,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    validateTextControls(maxLines, minLines, overflow)
    // CjkTextLinkClicks: Compose-Text-parity link handling. A tap is hit-tested
    // against the ENGINE's own geometry (getOffsetForPosition + bounding boxes —
    // no hidden Compose Text layout, ADR 0036), then dispatched to the link's
    // LinkInteractionListener, falling back to LocalUriHandler for plain Urls.
    val hasLinks = semanticsText.hasLinkAnnotations(0, semanticsText.length)
    val latestResult = remember { arrayOfNulls<LayoutResult>(1) }
    val latestOnTextLayout = rememberUpdatedState(onTextLayout)
    val reportLayout: (LayoutResult) -> Unit = remember(hasLinks) {
        { result ->
            if (hasLinks) latestResult[0] = result
            latestOnTextLayout.value(result)
        }
    }
    val uriHandler = LocalUriHandler.current
    val linkModifier = if (hasLinks) {
        Modifier.pointerInput(semanticsText, uriHandler) {
            detectTapGestures { position ->
                val result = latestResult[0] ?: return@detectTapGestures
                val offset = result.getOffsetForPosition(position.x, position.y)
                if (semanticsText.length == 0) return@detectTapGestures
                val queryStart = offset.coerceIn(0, semanticsText.length - 1)
                val hit = semanticsText
                    .getLinkAnnotations(queryStart, queryStart + 1)
                    .firstOrNull { range ->
                        result.getBoundingBoxes(range.start, range.end).any { box ->
                            position.x >= box.left && position.x <= box.right &&
                                position.y >= box.top && position.y <= box.bottom
                        }
                    } ?: return@detectTapGestures
                val link = hit.item
                val listener = link.linkInteractionListener
                when {
                    listener != null -> listener.onClick(link)
                    link is LinkAnnotation.Url -> uriHandler.openUri(link.url)
                }
            }
        }
    } else {
        Modifier
    }
    // Backed by a single Modifier.Node (like BasicText): it owns BOTH measure and draw,
    // so update() can request measurement+draw for layout changes and draw only for
    // paint changes. That's what makes editing repaint even when the new content lays
    // out to the SAME size — routing a measure-phase result through snapshot state +
    // drawBehind only repaints on relayout, leaving stale glyphs while typing.
    Box(
        modifier
            .then(linkModifier)
            .then(
                CjkTextLayoutElement(
                    text, semanticsText, textStyle, paragraphStyle, color,
                    decorations, colorSpans, richTextSpans, spans, rubySpans,
                    softWrap, overflow, maxLines, minLines, measurer, reportLayout,
                ),
            ),
    )
}

/** Backs [CjkTextLayout] — a measure+draw [Modifier.Node] that repaints on update. */
private class CjkTextLayoutElement(
    private val text: String,
    private val semanticsText: AnnotatedString,
    private val textStyle: TextStyle,
    private val paragraphStyle: ParagraphStyle,
    private val color: Int,
    private val decorations: List<DecorationSpan>,
    private val colorSpans: List<ColorSpan>,
    private val richTextSpans: List<RichTextSpan>,
    private val spans: List<TextSpan>,
    private val rubySpans: List<RubySpan>,
    private val softWrap: Boolean,
    private val overflow: TextOverflow,
    private val maxLines: Int,
    private val minLines: Int,
    private val measurer: ParagraphMeasurer,
    private val onTextLayout: (LayoutResult) -> Unit,
) : ModifierNodeElement<CjkTextLayoutNode>() {
    override fun create() = CjkTextLayoutNode(
        text, semanticsText, textStyle, paragraphStyle, color,
        decorations, colorSpans, richTextSpans, spans, rubySpans,
        softWrap, overflow, maxLines, minLines, measurer, onTextLayout,
    )

    override fun update(node: CjkTextLayoutNode) = node.update(
        text, semanticsText, textStyle, paragraphStyle, color,
        decorations, colorSpans, richTextSpans, spans, rubySpans,
        softWrap, overflow, maxLines, minLines, measurer, onTextLayout,
    )

    override fun equals(other: Any?): Boolean =
        other is CjkTextLayoutElement && text == other.text && textStyle == other.textStyle &&
            semanticsText == other.semanticsText && paragraphStyle == other.paragraphStyle && color == other.color &&
            decorations == other.decorations && colorSpans == other.colorSpans &&
            richTextSpans == other.richTextSpans && spans == other.spans &&
            rubySpans == other.rubySpans && softWrap == other.softWrap &&
            overflow == other.overflow && maxLines == other.maxLines &&
            minLines == other.minLines && measurer === other.measurer &&
            onTextLayout === other.onTextLayout

    override fun hashCode(): Int {
        var r = text.hashCode()
        r = 31 * r + semanticsText.hashCode()
        r = 31 * r + textStyle.hashCode()
        r = 31 * r + paragraphStyle.hashCode()
        r = 31 * r + color
        r = 31 * r + decorations.hashCode()
        r = 31 * r + colorSpans.hashCode()
        r = 31 * r + richTextSpans.hashCode()
        r = 31 * r + spans.hashCode()
        r = 31 * r + rubySpans.hashCode()
        r = 31 * r + softWrap.hashCode()
        r = 31 * r + overflow.hashCode()
        r = 31 * r + maxLines
        r = 31 * r + minLines
        r = 31 * r + measurer.hashCode()
        r = 31 * r + onTextLayout.hashCode()
        return r
    }
}

private class CjkTextLayoutNode(
    private var text: String,
    private var semanticsText: AnnotatedString,
    private var textStyle: TextStyle,
    private var paragraphStyle: ParagraphStyle,
    private var color: Int,
    private var decorations: List<DecorationSpan>,
    private var colorSpans: List<ColorSpan>,
    private var richTextSpans: List<RichTextSpan>,
    private var spans: List<TextSpan>,
    private var rubySpans: List<RubySpan>,
    private var softWrap: Boolean,
    private var overflow: TextOverflow,
    private var maxLines: Int,
    private var minLines: Int,
    private var measurer: ParagraphMeasurer,
    private var onTextLayout: (LayoutResult) -> Unit,
) : Modifier.Node(), LayoutModifierNode, DrawModifierNode, SemanticsModifierNode {

    private var result: LayoutResult? = null
    private var drawClipWidth: Float = 0f
    private var drawClipHeight: Float = 0f
    private var drawClipLeft: Float = 0f
    private var drawClipTop: Float = 0f
    private var drawClipRight: Float = 0f
    private var drawClipBottom: Float = 0f

    fun update(
        text: String,
        semanticsText: AnnotatedString,
        textStyle: TextStyle,
        paragraphStyle: ParagraphStyle,
        color: Int,
        decorations: List<DecorationSpan>,
        colorSpans: List<ColorSpan>,
        richTextSpans: List<RichTextSpan>,
        spans: List<TextSpan>,
        rubySpans: List<RubySpan>,
        softWrap: Boolean,
        overflow: TextOverflow,
        maxLines: Int,
        minLines: Int,
        measurer: ParagraphMeasurer,
        onTextLayout: (LayoutResult) -> Unit,
    ) {
        validateTextControls(maxLines, minLines, overflow)
        // Split invalidation like BasicText: layout-affecting params re-measure
        // (and must ALSO repaint — same-size relayout does not imply redraw).
        // Render-only paint changes only request redraw; render-only range
        // boundary changes also request measurement so the engine can expose
        // exact occupied geometry for source ranges.
        val oldSourceBoundaries = sourceBoundariesFor(
            textLength = this.text.length,
            decorations = this.decorations,
            colorSpans = this.colorSpans,
            richTextSpans = this.richTextSpans,
            spans = this.spans,
            rubySpans = this.rubySpans,
        )
        val newSourceBoundaries = sourceBoundariesFor(
            textLength = text.length,
            decorations = decorations,
            colorSpans = colorSpans,
            richTextSpans = richTextSpans,
            spans = spans,
            rubySpans = rubySpans,
        )
        val layoutChanged = text != this.text || textStyle != this.textStyle ||
            paragraphStyle != this.paragraphStyle || decorations != this.decorations ||
            spans != this.spans || rubySpans != this.rubySpans ||
            softWrap != this.softWrap || maxLines != this.maxLines ||
            minLines != this.minLines || measurer !== this.measurer ||
            oldSourceBoundaries != newSourceBoundaries
        val drawChanged = color != this.color || colorSpans != this.colorSpans ||
            richTextSpans != this.richTextSpans || overflow != this.overflow
        val semanticsChanged = semanticsText != this.semanticsText
        val callbackChanged = onTextLayout !== this.onTextLayout
        this.text = text
        this.semanticsText = semanticsText
        this.textStyle = textStyle
        this.paragraphStyle = paragraphStyle
        this.color = color
        this.decorations = decorations
        this.colorSpans = colorSpans
        this.richTextSpans = richTextSpans
        this.spans = spans
        this.rubySpans = rubySpans
        this.softWrap = softWrap
        this.overflow = overflow
        this.maxLines = maxLines
        this.minLines = minLines
        this.measurer = measurer
        this.onTextLayout = onTextLayout
        if (layoutChanged) {
            invalidateMeasurement()
            invalidateDraw()
        } else if (drawChanged) {
            invalidateDraw()
        }
        if (semanticsChanged) invalidateSemantics()
        // Link hit-testing stores the latest LayoutResult through onTextLayout. When only
        // annotations/callback wiring change, layout geometry is still valid but measure may not
        // rerun, so hand the current result to the new callback.
        if (callbackChanged && !layoutChanged) result?.let(onTextLayout)
    }

    override fun SemanticsPropertyReceiver.applySemantics() {
        text = this@CjkTextLayoutNode.semanticsText
    }

    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): MeasureResult {
        val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth.toFloat() else DEFAULT_UNBOUNDED_WIDTH
        val layoutWidth = if (softWrap) maxWidth else DEFAULT_UNBOUNDED_WIDTH
        // softWrap changes the measurement width; maxLines is an ENGINE constraint
        // (`MaxLinesLineTruncation`, recorded in debug) so [onTextLayout] receives the
        // engine's own explainable result, not a frontend-doctored copy.
        val laidOut = measurer.measure(
            text = text,
            constraints = LayoutConstraints(maxWidth = layoutWidth, maxLines = maxLines),
            textStyle = textStyle,
            paragraphStyle = paragraphStyle,
            decorations = decorations,
            spans = spans,
            rubySpans = rubySpans,
            sourceBoundaries = sourceBoundariesFor(
                textLength = text.length,
                decorations = decorations,
                colorSpans = colorSpans,
                richTextSpans = richTextSpans,
                spans = spans,
                rubySpans = rubySpans,
            ),
        )
        result = laidOut
        onTextLayout(laidOut)
        // The drawn content (incl. 行间装饰 overhang) paints from draw(); the empty inner
        // content is placed at 0. MinLinesHeightReservation: minLines only reserves
        // vertical space (one resolved line height per missing line) — no hidden
        // layout state is invented.
        val lineHeight = laidOut.debug.lineSpacingDecision?.resolvedHeight
            ?: laidOut.lines.firstOrNull()?.let { it.bottom - it.top }
            ?: textStyle.fontSize * 1.5f
        val placeable = measurable.measure(Constraints.fixed(0, 0))
        val w = ceil(laidOut.size.width).toInt().coerceIn(constraints.minWidth, constraints.maxWidth)
        val h = ceil(maxOf(laidOut.size.height, lineHeight * minLines))
            .toInt().coerceIn(constraints.minHeight, constraints.maxHeight)
        drawClipWidth = w.toFloat()
        drawClipHeight = h.toFloat()
        val ink = laidOut.glyphInkBounds()
        // LegalHangingInkClip: TextOverflow.Clip should still paint CJK hanging
        // punctuation and hanging hyphens because the engine emitted them as part
        // of the line, not as overflow text. Do not use raw visualWidth here:
        // an over-long unwrapped run may also be wider than the node and should
        // stay clipped. Only the explicit hanging fields are allowed past the edge.
        val legalClipRight = laidOut.lines.maxOfOrNull { line ->
            val punctuationEdge = minOf(drawClipWidth, line.indent + line.adjustedWidth) +
                line.hangingPunctuationAdvance
            val hyphenEdge = minOf(drawClipWidth, line.indent + line.visualWidth) +
                line.hyphenAdvance
            maxOf(drawClipWidth, punctuationEdge, hyphenEdge)
        } ?: drawClipWidth
        val legalClipLeft = laidOut.positionedClusters().minOfOrNull { it.drawX } ?: 0f
        drawClipLeft = minOf(0f, legalClipLeft, ink?.left ?: 0f)
        drawClipTop = minOf(0f, ink?.top ?: 0f)
        drawClipRight = maxOf(drawClipWidth, legalClipRight, ink?.right ?: drawClipWidth)
        drawClipBottom = maxOf(drawClipHeight, ink?.bottom ?: drawClipHeight)
        // Expose the first line's baseline so Row.alignByBaseline can line a 拼音 list
        // body (first line pushed down by its ruby band) up with its marker.
        val firstBaseline = laidOut.lines.firstOrNull()?.baseline?.let { ceil(it).toInt() } ?: AlignmentLine.Unspecified
        return layout(w, h, alignmentLines = mapOf(FirstBaseline to firstBaseline)) { placeable.place(0, 0) }
    }

    override fun ContentDrawScope.draw() {
        result?.let {
            val drawScope = this
            if (overflow == TextOverflow.Visible) {
                drawParagraph(it, color, colorSpans, richTextSpans, spans)
            } else {
                clipRect(left = drawClipLeft, top = drawClipTop, right = drawClipRight, bottom = drawClipBottom) {
                    drawScope.drawParagraph(it, color, colorSpans, richTextSpans, spans)
                }
            }
        }
        drawContent()
    }
}

private fun validateTextControls(maxLines: Int, minLines: Int, overflow: TextOverflow) {
    require(maxLines > 0) { "maxLines must be greater than zero." }
    require(minLines > 0) { "minLines must be greater than zero." }
    require(minLines <= maxLines) { "minLines must be less than or equal to maxLines." }
    require(overflow == TextOverflow.Clip || overflow == TextOverflow.Visible) {
        "Only TextOverflow.Clip and TextOverflow.Visible are implemented. Ellipsis needs a Tiqian overflow marker model."
    }
}

private fun sourceBoundariesFor(
    textLength: Int,
    decorations: List<DecorationSpan>,
    colorSpans: List<ColorSpan>,
    richTextSpans: List<RichTextSpan>,
    spans: List<TextSpan>,
    rubySpans: List<RubySpan>,
): Set<Int> = buildSet {
    fun addBoundary(offset: Int) {
        if (offset > 0 && offset < textLength) add(offset)
    }
    fun addRange(start: Int, end: Int) {
        addBoundary(start)
        addBoundary(end)
    }
    decorations.forEach { addRange(it.range.start, it.range.end) }
    colorSpans.forEach { addRange(it.start, it.end) }
    richTextSpans.forEach { addRange(it.range.start, it.range.end) }
    spans.forEach { addRange(it.range.start, it.range.end) }
    rubySpans.forEach { addRange(it.baseRange.start, it.baseRange.end) }
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
): ParagraphMeasurer = rememberPlatformParagraphMeasurer(profile)

@Composable
internal expect fun rememberPlatformParagraphMeasurer(profile: ClreqProfile): ParagraphMeasurer

internal expect fun ContentDrawScope.drawParagraph(
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    richTextSpans: List<RichTextSpan>,
    spans: List<TextSpan>,
)

private const val DEFAULT_UNBOUNDED_WIDTH = 65_536f
internal const val DEFAULT_TEXT_COLOR: Int = 0xFF000000.toInt()
