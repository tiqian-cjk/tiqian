package org.tiqian.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutResult
import org.tiqian.core.LayoutResultReplayIndex
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubySpan
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import kotlin.math.ceil
import kotlin.math.floor

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
    linkText: AnnotatedString = semanticsText,
    inlineOffsetMapping: CjkInlineObjectOffsetMapping = remember(linkText) { CjkInlineObjectOffsetMapping(linkText) },
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    color: Int = DEFAULT_TEXT_COLOR,
    decorations: List<DecorationSpan> = emptyList(),
    colorSpans: List<ColorSpan> = emptyList(),
    richTextSpans: List<RichTextSpan> = emptyList(),
    spans: List<TextSpan> = emptyList(),
    rubySpans: List<RubySpan> = emptyList(),
    inlineObjects: List<InlineObjectSpan> = emptyList(),
    inlineObjectContent: List<CjkInlineObject> = emptyList(),
    softWrap: Boolean = true,
    overflow: TextOverflow = TextOverflow.Visible,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    precomputedLayout: LayoutResult? = null,
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    validateTextControls(maxLines, minLines, overflow)
    require(inlineObjects.size == inlineObjectContent.size) {
        "Every InlineObjectSpan must have one Compose presentation"
    }
    require(inlineObjects.indices.all { index ->
        val presentation = inlineObjectContent[index]
        val span = inlineObjects[index]
        span.range.start == presentation.range.start && span.range.end == presentation.range.end
    }) {
        "Inline object layout and presentation ranges must match"
    }
    // CjkTextLinkClicks: Compose-Text-parity link handling. A tap is hit-tested
    // against the ENGINE's own geometry (getOffsetForPosition + bounding boxes —
    // no hidden Compose Text layout, ADR 0036), then dispatched to the link's
    // LinkInteractionListener, falling back to LocalUriHandler for plain Urls.
    val latestResult = remember { arrayOfNulls<LayoutResult>(1) }
    val latestOnTextLayout = rememberUpdatedState(onTextLayout)
    val reportLayout: (LayoutResult) -> Unit = remember {
        { result ->
            latestResult[0] = result
            latestOnTextLayout.value(result)
        }
    }
    val uriHandler = LocalUriHandler.current
    val selectionState = LocalCjkSelectionState.current
    val selectionScope = LocalCjkSelectionScope.current
    val selectionBridge = remember { CjkTextSelectionBridge() }
    val hoveringLink = remember { mutableStateOf(false) }
    val inlineObjectPlacements = remember(inlineObjects) {
        inlineObjects.map { CjkInlineObjectPlacement() }
    }
    // Keep the pointer node installed even while the text has no links. Replacing an empty
    // modifier with a pointer node after an annotation-only update can otherwise leave the new
    // node without hit-test bounds until a later relayout; updating a stable node also avoids
    // changing the modifier topology when links appear or disappear.
    val linkModifier = CjkTextLinkElement(linkText, latestResult, uriHandler, hoveringLink)
    val selectionModifier = if (selectionState != null) {
        Modifier.foundationSelectionGestures(selectionState, selectionBridge)
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
            .then(selectionModifier)
            .pointerHoverIcon(
                if (hoveringLink.value) {
                    PointerIcon.Hand
                } else if (selectionState != null) {
                    PointerIcon.Text
                } else {
                    PointerIcon.Default
                },
            )
            .then(
                CjkTextLayoutElement(
                    text, semanticsText, textStyle, paragraphStyle, color,
                    decorations, colorSpans, richTextSpans, spans, rubySpans, inlineObjects,
                    softWrap, overflow, maxLines, minLines, measurer, reportLayout,
                    precomputedLayout,
                    selectionState, selectionScope, selectionBridge, inlineObjectPlacements, inlineOffsetMapping,
                ),
            ),
    ) {
        inlineObjectContent.forEachIndexed { index, inlineObject ->
            key(inlineObject.range.start, inlineObject.range.end) {
                CjkInlineObjectContent(inlineObject, inlineObjectPlacements[index])
            }
        }
    }
}

internal class CjkInlineObjectPlacement {
    var left: Float = 0f
    var top: Float = 0f
    var visible: Boolean = false
}

@Composable
private fun CjkInlineObjectContent(
    inlineObject: CjkInlineObject,
    placement: CjkInlineObjectPlacement,
) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val widthPx = with(density) { inlineObject.advance.toPx() }
    val heightPx = with(density) { inlineObject.ascent.toPx() + inlineObject.descent.toPx() }
    Layout(
        content = { Box { inlineObject.content() } },
    ) { measurables, _ ->
        val width = ceil(widthPx).toInt().coerceAtLeast(1)
        val height = ceil(heightPx).toInt().coerceAtLeast(1)
        val placeable = measurables.single().measure(Constraints.fixed(width, height))
        // This zero-size layout is an overlay: the paragraph node owns the actual measured box.
        layout(0, 0) {
            if (placement.visible) {
                val x = floor(placement.left).toInt()
                val y = floor(placement.top).toInt()
                placeable.placeWithLayer(x, y) {
                    translationX = placement.left - x
                    translationY = placement.top - y
                }
            }
        }
    }
}

/**
 * The selection pointer modifier must sit outside the layout modifier so Compose hit-tests it
 * against the paragraph's measured bounds. Both nodes share this narrow bridge; geometry and
 * source offsets still come exclusively from [CjkTextLayoutNode]'s [LayoutResult].
 */
internal class CjkTextSelectionBridge {
    var selectable: CjkSelectable? = null
    var coordinates: androidx.compose.ui.layout.LayoutCoordinates? = null
}

internal fun validateTextControls(maxLines: Int, minLines: Int, overflow: TextOverflow) {
    require(maxLines > 0) { "maxLines must be greater than zero." }
    require(minLines > 0) { "minLines must be greater than zero." }
    require(minLines <= maxLines) { "minLines must be less than or equal to maxLines." }
    require(overflow == TextOverflow.Clip || overflow == TextOverflow.Visible) {
        "Only TextOverflow.Clip and TextOverflow.Visible are implemented. Ellipsis needs a Tiqian overflow marker model."
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
    session: ParagraphMeasurementSession? = null,
): ParagraphMeasurer = rememberPlatformParagraphMeasurer(profile, session)

/**
 * Creates an independent platform measurer for pre-layout work. Confine each instance to one
 * worker; do not share it concurrently with a Compose node or another worker.
 */
expect fun createPlatformParagraphMeasurer(
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    session: ParagraphMeasurementSession? = null,
): ParagraphMeasurer

@Composable
internal expect fun rememberPlatformParagraphMeasurer(
    profile: ClreqProfile,
    session: ParagraphMeasurementSession?,
): ParagraphMeasurer

internal expect fun ContentDrawScope.drawParagraph(
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    selectionBoxes: List<org.tiqian.core.Rect>,
    selectionColor: Int?,
    drawCache: ParagraphDrawCache,
)

/** Platform-owned mutable drawing resources retained for one attached `CjkText` node. */
internal interface ParagraphDrawCache {
    fun invalidateGeometry()
    fun dispose()
}

internal expect fun createParagraphDrawCache(): ParagraphDrawCache

internal const val DEFAULT_TEXT_COLOR: Int = 0xFF000000.toInt()
