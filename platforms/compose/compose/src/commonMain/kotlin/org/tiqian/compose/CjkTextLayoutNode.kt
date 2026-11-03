package org.tiqian.compose

import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
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
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.copyText
import androidx.compose.ui.semantics.setSelection
import androidx.compose.ui.semantics.text
import androidx.compose.ui.semantics.textSelectionRange
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange as ComposeTextRange
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LayoutResultReplayIndex
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubySpan
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.coerceSelectionOffset
import org.tiqian.core.getLineForOffset
import org.tiqian.core.getTextForCopy
import org.tiqian.core.layoutAutoSpaceSuppressedRanges
import org.tiqian.core.layoutInlineBoxes
import org.tiqian.core.layoutLineBreakSpans
import org.tiqian.core.legalHangingPunctuationClipEdge
import org.tiqian.core.sourceBoundariesForPresentation
import org.tiqian.core.cursorRect
import org.tiqian.core.selectionBoxes
import org.tiqian.core.selectionOffsetForPosition
import org.tiqian.core.selectionWordRangeForPosition
import org.tiqian.core.toReplayIndex
import org.tiqian.core.visiblePaintOverhang
import kotlin.math.ceil

/** Backs [CjkTextLayout] — a measure+draw [Modifier.Node] that repaints on update. */
internal class CjkTextLayoutElement(
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
    private val inlineObjects: List<InlineObjectSpan>,
    private val softWrap: Boolean,
    private val overflow: TextOverflow,
    private val maxLines: Int,
    private val minLines: Int,
    private val measurer: ParagraphMeasurer,
    private val onTextLayout: (LayoutResult) -> Unit,
    private val precomputedLayout: LayoutResult?,
    private val selectionState: CjkSelectionState?,
    private val selectionScope: CjkSelectionScopeInfo?,
    private val selectionBridge: CjkTextSelectionBridge,
    private val inlineObjectPlacements: List<CjkInlineObjectPlacement>,
) : ModifierNodeElement<CjkTextLayoutNode>() {
    override fun create() = CjkTextLayoutNode(
        text, semanticsText, textStyle, paragraphStyle, color,
        decorations, colorSpans, richTextSpans, spans, rubySpans, inlineObjects,
        softWrap, overflow, maxLines, minLines, measurer, onTextLayout,
        precomputedLayout,
        selectionState, selectionScope, selectionBridge, inlineObjectPlacements,
    )

    override fun update(node: CjkTextLayoutNode) = node.update(
        text, semanticsText, textStyle, paragraphStyle, color,
        decorations, colorSpans, richTextSpans, spans, rubySpans, inlineObjects,
        softWrap, overflow, maxLines, minLines, measurer, onTextLayout,
        precomputedLayout,
        selectionState, selectionScope, selectionBridge, inlineObjectPlacements,
    )

    override fun equals(other: Any?): Boolean =
        other is CjkTextLayoutElement && text == other.text && textStyle == other.textStyle &&
            semanticsText == other.semanticsText && paragraphStyle == other.paragraphStyle && color == other.color &&
            decorations == other.decorations && colorSpans == other.colorSpans &&
            richTextSpans == other.richTextSpans && spans == other.spans &&
            rubySpans == other.rubySpans && inlineObjects == other.inlineObjects &&
            softWrap == other.softWrap &&
            overflow == other.overflow && maxLines == other.maxLines &&
            minLines == other.minLines && measurer === other.measurer &&
            precomputedLayout === other.precomputedLayout &&
            onTextLayout === other.onTextLayout && selectionState === other.selectionState &&
            selectionScope == other.selectionScope &&
            selectionBridge === other.selectionBridge &&
            inlineObjectPlacements === other.inlineObjectPlacements

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
        r = 31 * r + inlineObjects.hashCode()
        r = 31 * r + softWrap.hashCode()
        r = 31 * r + overflow.hashCode()
        r = 31 * r + maxLines
        r = 31 * r + minLines
        r = 31 * r + measurer.hashCode()
        // Equality is referential; avoid recursively hashing a full paragraph result on every
        // modifier comparison and accept the harmless nullable-state collision here.
        r = 31 * r + if (precomputedLayout == null) 0 else 1
        r = 31 * r + onTextLayout.hashCode()
        r = 31 * r + (selectionState?.hashCode() ?: 0)
        r = 31 * r + (selectionScope?.hashCode() ?: 0)
        r = 31 * r + selectionBridge.hashCode()
        r = 31 * r + inlineObjectPlacements.hashCode()
        return r
    }
}

internal class CjkTextLayoutNode(
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
    private var inlineObjects: List<InlineObjectSpan>,
    private var softWrap: Boolean,
    private var overflow: TextOverflow,
    private var maxLines: Int,
    private var minLines: Int,
    private var measurer: ParagraphMeasurer,
    private var onTextLayout: (LayoutResult) -> Unit,
    private var precomputedLayout: LayoutResult?,
    private var selectionState: CjkSelectionState?,
    private var selectionScope: CjkSelectionScopeInfo?,
    private var selectionBridge: CjkTextSelectionBridge,
    private var inlineObjectPlacements: List<CjkInlineObjectPlacement>,
) : Modifier.Node(), LayoutModifierNode, DrawModifierNode, SemanticsModifierNode,
    CjkSelectable {

    /**
     * `ExactComposeMeasureReuse`: Compose can ask a node to measure again even when the engine input
     * is unchanged (for example when only `minLines` changes the outer box). Keep exactly one result
     * at the node that owns it; this avoids a second full shaping/layout pass without introducing a
     * cross-paragraph cache or weakening any layout/font invalidation boundary.
     */
    private data class CachedLayout(
        val measurer: ParagraphMeasurer,
        val input: LayoutInput,
        val inputHash: Int,
        val result: LayoutResult,
    ) {
        fun matches(measurer: ParagraphMeasurer, input: LayoutInput): Boolean =
            this.measurer === measurer && inputHash == input.hashCode() && this.input == input
    }

    private var result: LayoutResult? = null
    private var cachedLayout: CachedLayout? = null
    private var replayIndex: LayoutResultReplayIndex? = null
    private var drawCache: ParagraphDrawCache? = null
    private var drawClipWidth: Float = 0f
    private var drawClipHeight: Float = 0f
    private var drawClipLeft: Float = 0f
    private var drawClipTop: Float = 0f
    private var drawClipRight: Float = 0f
    private var drawClipBottom: Float = 0f
    override var selectionCoordinates: androidx.compose.ui.layout.LayoutCoordinates? = null
        private set
    private var inlineOffsetMapping = CjkInlineObjectOffsetMapping(semanticsText)
    override val selectionText: AnnotatedString
        get() = semanticsText

    override fun selectionTextForCopy(range: org.tiqian.core.TextRange): String {
        val layout = result
        return if (layout == null) {
            semanticsText.text.substring(range.start.coerceIn(0, semanticsText.length), range.end.coerceIn(range.start.coerceIn(0, semanticsText.length), semanticsText.length))
        } else {
            inlineOffsetMapping.layoutRanges(range).joinToString("") { layout.getTextForCopy(it) }
        }
    }

    override fun onAttach() {
        drawCache = createParagraphDrawCache()
        selectionBridge.selectable = this
        selectionBridge.coordinates?.let(::updateSelectionCoordinates)
        selectionState?.register(this, selectionScope)
    }

    override fun onDetach() {
        selectionState?.unregister(this)
        if (selectionBridge.selectable === this) selectionBridge.selectable = null
        selectionCoordinates = null
        drawCache?.dispose()
        drawCache = null
    }

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
        inlineObjects: List<InlineObjectSpan>,
        softWrap: Boolean,
        overflow: TextOverflow,
        maxLines: Int,
        minLines: Int,
        measurer: ParagraphMeasurer,
        onTextLayout: (LayoutResult) -> Unit,
        precomputedLayout: LayoutResult?,
        selectionState: CjkSelectionState?,
        selectionScope: CjkSelectionScopeInfo?,
        selectionBridge: CjkTextSelectionBridge,
        inlineObjectPlacements: List<CjkInlineObjectPlacement>,
    ) {
        validateTextControls(maxLines, minLines, overflow)
        // Split invalidation like BasicText: layout-affecting params re-measure
        // (and must ALSO repaint — same-size relayout does not imply redraw).
        // Render-only paint changes only request redraw; render-only range
        // boundary changes also request measurement so the engine can expose
        // exact occupied geometry for source ranges.
        val oldSourceBoundaries = sourceBoundariesForPresentation(
            textLength = this.text.length,
            decorations = this.decorations,
            colorSpans = this.colorSpans,
            richTextSpans = this.richTextSpans,
            textSpans = this.spans,
            rubySpans = this.rubySpans,
        )
        val newSourceBoundaries = sourceBoundariesForPresentation(
            textLength = text.length,
            decorations = decorations,
            colorSpans = colorSpans,
            richTextSpans = richTextSpans,
            textSpans = spans,
            rubySpans = rubySpans,
        )
        val inlineBoxesChanged = richTextSpans.layoutInlineBoxes() !=
            this.richTextSpans.layoutInlineBoxes()
        val lineBreakSpansChanged = richTextSpans.layoutLineBreakSpans(text) !=
            this.richTextSpans.layoutLineBreakSpans(this.text)
        val autoSpaceSuppressionChanged = richTextSpans.layoutAutoSpaceSuppressedRanges() !=
            this.richTextSpans.layoutAutoSpaceSuppressedRanges()
        val layoutChanged = text != this.text || textStyle != this.textStyle ||
            paragraphStyle != this.paragraphStyle || decorations != this.decorations ||
            spans != this.spans || rubySpans != this.rubySpans ||
            inlineObjects != this.inlineObjects ||
            softWrap != this.softWrap || maxLines != this.maxLines ||
            minLines != this.minLines || measurer !== this.measurer ||
            oldSourceBoundaries != newSourceBoundaries ||
            inlineBoxesChanged ||
            lineBreakSpansChanged ||
            autoSpaceSuppressionChanged ||
            inlineObjectPlacements !== this.inlineObjectPlacements
        val richTextChanged = richTextSpans != this.richTextSpans
        val drawChanged = color != this.color || colorSpans != this.colorSpans ||
            richTextChanged || overflow != this.overflow
        val semanticsChanged = semanticsText != this.semanticsText
        val oldSelectionState = this.selectionState
        val oldSelectionScope = this.selectionScope
        val callbackChanged = onTextLayout !== this.onTextLayout
        val precomputedChanged = precomputedLayout !== this.precomputedLayout
        this.text = text
        this.semanticsText = semanticsText
        this.inlineOffsetMapping = CjkInlineObjectOffsetMapping(semanticsText)
        this.textStyle = textStyle
        this.paragraphStyle = paragraphStyle
        this.color = color
        this.decorations = decorations
        this.colorSpans = colorSpans
        this.richTextSpans = richTextSpans
        this.spans = spans
        this.rubySpans = rubySpans
        this.inlineObjects = inlineObjects
        this.softWrap = softWrap
        this.overflow = overflow
        this.maxLines = maxLines
        this.minLines = minLines
        this.measurer = measurer
        this.onTextLayout = onTextLayout
        this.precomputedLayout = precomputedLayout
        this.selectionState = selectionState
        this.selectionScope = selectionScope
        this.inlineObjectPlacements = inlineObjectPlacements
        if (this.selectionBridge !== selectionBridge) {
            if (this.selectionBridge.selectable === this) this.selectionBridge.selectable = null
            this.selectionBridge = selectionBridge
            if (isAttached) {
                selectionBridge.selectable = this
                selectionBridge.coordinates?.let(::updateSelectionCoordinates)
            }
        }
        if (oldSelectionState !== selectionState || oldSelectionScope != selectionScope) {
            oldSelectionState?.unregister(this)
            if (isAttached) selectionState?.register(this, selectionScope)
            invalidateDraw()
            invalidateSemantics()
        } else if (semanticsChanged) {
            selectionState?.selectableChanged(this, textChanged = true)
        }
        if (layoutChanged || precomputedChanged) {
            invalidateMeasurement()
            invalidateDraw()
        } else if (drawChanged) {
            if (richTextChanged) {
                replayIndex = result?.toReplayIndex(richTextSpans)
                drawCache?.invalidateGeometry()
            }
            invalidateDraw()
        }
        if (semanticsChanged) invalidateSemantics()
        // Link hit-testing stores the latest LayoutResult through onTextLayout. When only
        // annotations/callback wiring change, layout geometry is still valid but measure may not
        // rerun, so hand the current result to the new callback.
        if (callbackChanged && !layoutChanged && !precomputedChanged) result?.let(onTextLayout)
    }

    override fun SemanticsPropertyReceiver.applySemantics() {
        text = this@CjkTextLayoutNode.semanticsText
        val state = selectionState ?: return
        val range = state.rangeFor(this@CjkTextLayoutNode)
        textSelectionRange = ComposeTextRange(range?.start ?: 0, range?.end ?: 0)
        setSelection { start, end, _ ->
            state.setSelectionFromSemantics(this@CjkTextLayoutNode, start, end)
        }
        if (range != null && !range.isEmpty) {
            copyText { state.copySelection() }
        }
    }

    override fun updateSelectionCoordinates(coordinates: androidx.compose.ui.layout.LayoutCoordinates) {
        selectionCoordinates = coordinates
        selectionState?.selectableChanged(this)
    }

    override fun selectionOffsetAt(localPosition: Offset): Int? {
        val layout = result ?: return null
        val index = replayIndex ?: return null
        return inlineOffsetMapping.toLogical(index.selectionOffsetForPosition(layout, localPosition.x, localPosition.y))
    }

    override fun selectionWordRangeAt(localPosition: Offset): org.tiqian.core.TextRange? {
        val layout = result ?: return null
        val index = replayIndex ?: return null
        return index.selectionWordRangeForPosition(layout, localPosition.x, localPosition.y)?.let(inlineOffsetMapping::toLogical)
    }

    override fun selectionParagraphRangeAt(localPosition: Offset): org.tiqian.core.TextRange? {
        val layout = result ?: return null
        val index = replayIndex ?: return null
        val source = semanticsText.text
        if (source.isEmpty()) return org.tiqian.core.TextRange(0, 0)
        val rawOffset = inlineOffsetMapping.toLogical(index.selectionOffsetForPosition(layout, localPosition.x, localPosition.y))
        var start = rawOffset
        while (start > 0 && source[start - 1] != '\n') start--
        var end = rawOffset
        while (end < source.length && source[end] != '\n') end++
        return org.tiqian.core.TextRange(start, end)
    }

    override fun coerceSelectionOffset(offset: Int, bias: SourceBoundaryBias): Int =
        result?.let { inlineOffsetMapping.toLogical(it.coerceSelectionOffset(inlineOffsetMapping.toLayout(offset), bias)) } ?: offset.coerceIn(0, semanticsText.length)

    override fun selectionCursorPosition(offset: Int): Offset? {
        val layout = result ?: return null
        val cursor = replayIndex?.cursorRect(layout, inlineOffsetMapping.toLayout(offset)) ?: return null
        return Offset(cursor.left, cursor.bottom)
    }

    override fun selectionLineRange(offset: Int): org.tiqian.core.TextRange? {
        val layout = result ?: return null
        val lineIndex = layout.getLineForOffset(inlineOffsetMapping.toLayout(offset))
        return layout.lines.getOrNull(lineIndex)?.range?.let(inlineOffsetMapping::toLogical)
    }

    override fun selectionLineLeft(offset: Int): Float {
        val layout = result ?: return -1f
        val lineIndex = layout.getLineForOffset(inlineOffsetMapping.toLayout(offset))
        val line = layout.lines.getOrNull(lineIndex) ?: return -1f
        return replayIndex?.positionedClustersByLine?.getOrNull(lineIndex)
            ?.firstOrNull()?.left ?: line.indent
    }

    override fun selectionLineRight(offset: Int): Float {
        val layout = result ?: return -1f
        val lineIndex = layout.getLineForOffset(inlineOffsetMapping.toLayout(offset))
        val line = layout.lines.getOrNull(lineIndex) ?: return -1f
        return replayIndex?.positionedClustersByLine?.getOrNull(lineIndex)
            ?.lastOrNull()?.right ?: line.indent
    }

    override fun selectionLineCenterY(offset: Int): Float {
        val layout = result ?: return -1f
        val lineIndex = layout.getLineForOffset(inlineOffsetMapping.toLayout(offset))
        val line = layout.lines.getOrNull(lineIndex) ?: return -1f
        return (line.top + line.bottom) / 2f
    }

    override fun selectionLineHeight(offset: Int): Float {
        val layout = result ?: return 0f
        val lineIndex = layout.getLineForOffset(inlineOffsetMapping.toLayout(offset))
        val line = layout.lines.getOrNull(lineIndex) ?: return 0f
        return line.bottom - line.top
    }

    override fun selectionBoxes(range: org.tiqian.core.TextRange): List<org.tiqian.core.Rect> =
        result?.let { layout -> inlineOffsetMapping.layoutRanges(range).flatMap { replayIndex?.selectionBoxes(layout, it).orEmpty() } }.orEmpty()

    override fun invalidateSelection() {
        invalidateDraw()
        invalidateSemantics()
    }

    override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints): MeasureResult {
        val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth.toFloat() else DEFAULT_UNBOUNDED_WIDTH
        val layoutWidth = if (softWrap) maxWidth else DEFAULT_UNBOUNDED_WIDTH
        // softWrap changes the measurement width; maxLines is an ENGINE constraint
        // (`MaxLinesLineTruncation`, recorded in debug) so [onTextLayout] receives the
        // engine's own explainable result, not a frontend-doctored copy.
        val laidOut = precomputedLayout ?: run {
            val sourceBoundaries = sourceBoundariesForPresentation(
                textLength = text.length,
                decorations = decorations,
                colorSpans = colorSpans,
                richTextSpans = richTextSpans,
                textSpans = spans,
                rubySpans = rubySpans,
            )
            val layoutInput = LayoutInput(
                content = org.tiqian.core.TiqianTextContent(
                    text = text,
                    spans = spans,
                    sourceBoundaries = sourceBoundaries,
                    lineBreakSpans = richTextSpans.layoutLineBreakSpans(text),
                    autoSpaceSuppressedRanges = richTextSpans.layoutAutoSpaceSuppressedRanges(),
                ),
                textStyle = textStyle,
                paragraphStyle = paragraphStyle,
                constraints = LayoutConstraints(maxWidth = layoutWidth, maxLines = maxLines),
                decorations = decorations,
                rubySpans = rubySpans,
                inlineBoxes = richTextSpans.layoutInlineBoxes(),
                inlineObjects = inlineObjects,
            )
            val cached = cachedLayout
            when {
                cached != null && cached.matches(measurer, layoutInput) -> cached.result
                else -> tiqianTraceSection("TiqianParagraph.layout") {
                    measurer.measure(layoutInput)
                }.also { measured ->
                    cachedLayout = CachedLayout(measurer, layoutInput, layoutInput.hashCode(), measured)
                }
            }
        }
        // `UnchangedLayoutKeepsDisplayList`: SubcomposeLayout hosts re-measure every composed
        // block each pass; when the (cached or precomputed) result is the SAME instance the
        // geometry cannot have changed, so keep the replay index, the recorded display list AND
        // the NaturalRunCoalescedDraw plan (ADR 0050) — invalidating here rebuilt the plan with
        // its per-cluster advance validation on every draw (P50 3.9→8.2ms, worst record 256ms).
        if (result !== laidOut) {
            result = laidOut
            replayIndex = laidOut.toReplayIndex(richTextSpans)
            drawCache?.invalidateGeometry()
        }
        // Placement objects and the callback may be fresh instances after recomposition even
        // when the layout result is unchanged, so these always re-wire.
        updateInlineObjectPlacements(laidOut, replayIndex, inlineObjects, inlineObjectPlacements)
        onTextLayout(laidOut)
        // The drawn content (incl. 行间装饰 overhang) paints from draw(); the empty inner
        // content is placed at 0. MinLinesHeightReservation: minLines only reserves
        // vertical space (one resolved line height per missing line) — no hidden
        // layout state is invented.
        val lineHeight = laidOut.debug.lineSpacingDecision?.resolvedHeight
            ?: laidOut.lines.firstOrNull()?.let { it.bottom - it.top }
            ?: textStyle.fontSize * 1.5f
        val w = ceil(laidOut.size.width).toInt().coerceIn(constraints.minWidth, constraints.maxWidth)
        val h = ceil(maxOf(laidOut.size.height, lineHeight * minLines))
            .toInt().coerceIn(constraints.minHeight, constraints.maxHeight)
        val placeable = measurable.measure(Constraints.fixed(w, h))
        drawClipWidth = w.toFloat()
        drawClipHeight = h.toFloat()
        // LegalHangingInkClip: TextOverflow.Clip should still paint CJK hanging
        // punctuation and hanging hyphens because the engine emitted them as part
        // of the line, not as overflow text. `visualWidth` is legal only when the
        // explicit punctuation-hang field is present: it includes justification
        // before the mark and also covers the impossible-measure case where the
        // preceding cluster itself exceeds the node. Ordinary over-long unwrapped
        // runs still stay clipped.
        val legalClipRight = laidOut.lines.maxOfOrNull { line ->
            val punctuationEdge = line.legalHangingPunctuationClipEdge(drawClipWidth)
            val hyphenEdge = minOf(drawClipWidth, line.indent + line.visualWidth) +
                line.hyphenAdvance
            maxOf(drawClipWidth, punctuationEdge, hyphenEdge)
        } ?: drawClipWidth
        val positionedClusters = replayIndex?.positionedClusters.orEmpty()
        val legalClipLeft = positionedClusters.minOfOrNull { it.drawX } ?: 0f
        val paintOverhang = laidOut.visiblePaintOverhang(drawClipWidth, drawClipHeight, positionedClusters)
        drawClipLeft = minOf(0f, legalClipLeft, -paintOverhang.left)
        drawClipTop = -paintOverhang.top
        drawClipRight = maxOf(drawClipWidth, legalClipRight, drawClipWidth + paintOverhang.right)
        drawClipBottom = drawClipHeight + paintOverhang.bottom
        // Expose the first line's resolved base-text baseline. Ruby leaves it
        // unchanged when the existing inter-line space is sufficient; a selected
        // line-height expansion strategy is already reflected in the LayoutResult.
        val firstBaseline = laidOut.lines.firstOrNull()?.baseline?.let { ceil(it).toInt() } ?: AlignmentLine.Unspecified
        return layout(w, h, alignmentLines = mapOf(FirstBaseline to firstBaseline)) { placeable.place(0, 0) }
    }

    override fun ContentDrawScope.draw() {
        val result = result
        val replayIndex = replayIndex
        if (result != null && replayIndex != null) {
            val drawCache = drawCache ?: return
            val drawScope = this
            val selectionRange = selectionState?.rangeFor(this@CjkTextLayoutNode)
            val selectionBoxes = selectionRange?.let { range -> inlineOffsetMapping.layoutRanges(range).flatMap { replayIndex.selectionBoxes(result, it) } }.orEmpty()
            val selectionColor = selectionRange?.let { selectionState?.selectionBackgroundArgb }
            if (overflow == TextOverflow.Visible) {
                tiqianTraceSection("TiqianParagraph.paint") {
                    drawParagraph(
                        result, replayIndex, color, colorSpans, spans, selectionBoxes, selectionColor, drawCache,
                    )
                }
                drawContent()
            } else {
                clipRect(left = drawClipLeft, top = drawClipTop, right = drawClipRight, bottom = drawClipBottom) {
                    tiqianTraceSection("TiqianParagraph.paint") {
                        drawScope.drawParagraph(
                            result, replayIndex, color, colorSpans, spans, selectionBoxes, selectionColor, drawCache,
                        )
                    }
                    drawScope.drawContent()
                }
            }
        } else {
            drawContent()
        }
    }
}

private fun updateInlineObjectPlacements(
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex?,
    inlineObjects: List<InlineObjectSpan>,
    placements: List<CjkInlineObjectPlacement>,
) {
    require(inlineObjects.size == placements.size)
    val positionedByRange = replayIndex?.positionedClusters?.associateBy { it.range }.orEmpty()
    inlineObjects.forEachIndexed { index, inlineObject ->
        val placement = placements[index]
        val positioned = positionedByRange[inlineObject.range]
        placement.visible = positioned != null
        if (positioned != null) {
            // InlineObjectPaintOrigin: [left] is the cluster's occupied selection box and can
            // include leading autospace/glue. The opaque child replaces glyph paint, so it must
            // start at the same final draw origin a glyph run would use.
            placement.left = positioned.drawX
            placement.top = positioned.baseline - inlineObject.ascent
        }
    }
}

/**
 * Right clip edge authorized by an engine-selected punctuation hang. Using
 * [LineBox.visualWidth] is essential because it is the mark's actual final x:
 * it includes justification before the mark and an over-wide predecessor in
 * the impossible-measure fallback. Without an explicit hang, ordinary visual
 * overflow remains clipped to [drawClipWidth].
 */
private const val DEFAULT_UNBOUNDED_WIDTH = 65_536f
