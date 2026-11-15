package org.tiqian.apple

import kotlinx.cinterop.ExperimentalForeignApi
import org.tiqian.core.ColorSpan
import org.tiqian.core.LayoutResult
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.coerceSelectionOffset
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.getCursorRect
import org.tiqian.core.getSelectionOffsetForPosition
import org.tiqian.core.getSelectionWordBoundaryForPosition
import org.tiqian.core.getTextForCopy
import org.tiqian.apple.coretext.CoreTextLayoutRenderer
import platform.CoreGraphics.CGContextRef
import platform.CoreGraphics.CGContextRestoreGState
import platform.CoreGraphics.CGContextSaveGState
import platform.CoreGraphics.CGContextTranslateCTM
import kotlin.math.abs

/** One laid-out block placed at ([x], [yTop]) within a [Document] (layout px, y-down from doc top). */
internal class PlacedBlock(
    val result: LayoutResult,
    val spans: List<TextSpan>,
    val colorSpans: List<ColorSpan>,
    val richTextSpans: List<RichTextSpan>,
    val x: Double,
    val yTop: Double,
    /** Logical source separator before this visual block; list bodies continue their marker row. */
    val sourceSeparatorBefore: String = "\n",
)

/** A UTF-16 source range exported to Swift without exposing the engine's internal text model. */
class SelectionRange(
    val start: Int,
    val end: Int,
) {
    val isEmpty: Boolean get() = start == end
}

/** One line-local occupied selection box in document coordinates (top-left origin, y-down). */
class SelectionBox(
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
)

/** One visual fragment of a native link, in document coordinates (top-left origin, y-down). */
class LinkBox(
    val target: String,
    val start: Int,
    val end: Int,
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
)

private class IndexedBlock(
    val placed: PlacedBlock,
    val sourceStart: Int,
    val sourceEnd: Int,
)

/**
 * A laid-out, drawable multi-block document (paragraphs, lists, section breaks) — the result of
 * `DocBuilder.layout(width:)`. Each block is a real engine [LayoutResult]; the document only
 * stacks them (uniform cross-paragraph line spacing) and offsets list bodies into their marker
 * column. Read [height] to size the view, then [draw]. Content is authored by the app, not here.
 */
@OptIn(ExperimentalForeignApi::class)
class Document internal constructor(
    internal val blocks: List<PlacedBlock>,
    val width: Double,
    val height: Double,
    private val renderer: CoreTextLayoutRenderer,
) {
    private val indexedBlocks: List<IndexedBlock>
    private val sourceText: String

    init {
        val source = StringBuilder()
        indexedBlocks = blocks.mapIndexed { index, block ->
            if (index > 0) source.append(block.sourceSeparatorBefore)
            val start = source.length
            source.append(block.result.input.content.text)
            IndexedBlock(block, start, source.length)
        }
        sourceText = source.toString()
    }

    /** Number of laid-out blocks (paragraphs + list marker/body rows), for diagnostics/tests. */
    val blockCount: Int get() = blocks.size

    /**
     * The document's plain SOURCE text, joined with each block's logical separator. The renderer
     * only paints glyphs, so the host view exposes this as its accessibility value (VoiceOver) to
     * keep source and accessibility offsets faithful (AGENTS.md #4).
     */
    val text: String
        get() = sourceText

    /**
     * Hit-test a document point and return a safe UTF-16 insertion offset. The selected block is
     * chosen by its actual placed rectangle, so list markers and bodies sharing one visual row do
     * not need a Swift-side layout model.
     */
    fun selectionOffset(x: Double, y: Double): Int {
        val indexed = nearestBlock(x, y) ?: return 0
        val block = indexed.placed
        val local = block.result.getSelectionOffsetForPosition(
            x = (x - block.x).toFloat(),
            y = (y - block.yTop).toFloat(),
        )
        return indexed.sourceStart + local
    }

    /** Return the source word/unit visually under a point, using the core selection policy. */
    fun selectionWord(x: Double, y: Double): SelectionRange? {
        val indexed = nearestBlock(x, y) ?: return null
        val block = indexed.placed
        val local = block.result.getSelectionWordBoundaryForPosition(
            x = (x - block.x).toFloat(),
            y = (y - block.yTop).toFloat(),
        ) ?: return null
        return SelectionRange(
            start = indexed.sourceStart + local.start,
            end = indexed.sourceStart + local.end,
        )
    }

    /** Snap an external UTF-16 offset away from surrogate, combining and grapheme interiors. */
    fun selectionBoundary(offset: Int, forward: Boolean): Int {
        val clamped = offset.coerceIn(0, sourceText.length)
        val indexed = indexedBlocks.firstOrNull {
            clamped >= it.sourceStart && clamped <= it.sourceEnd
        } ?: return clamped // the separator newline between two blocks is already a safe boundary
        val local = (clamped - indexed.sourceStart).coerceIn(0, indexed.placed.result.input.content.text.length)
        return indexed.sourceStart + indexed.placed.result.coerceSelectionOffset(
            local,
            if (forward) SourceBoundaryBias.Forward else SourceBoundaryBias.Backward,
        )
    }

    /** Return a source-faithful substring for UIKit/AppKit text input and accessibility. */
    fun textInRange(start: Int, end: Int): String {
        val safeStart = start.coerceIn(0, sourceText.length)
        val safeEnd = end.coerceIn(safeStart, sourceText.length)
        return sourceText.substring(safeStart, safeEnd)
    }

    /**
     * Clipboard text for a source range. Selection/VoiceOver retain [textInRange]'s exact offsets;
     * only pasteboard export adds Web-compatible parenthesised ruby / 注音 readings.
     */
    fun clipboardTextInRange(start: Int, end: Int): String {
        val safeStart = start.coerceIn(0, sourceText.length)
        val safeEnd = end.coerceIn(safeStart, sourceText.length)
        if (safeStart == safeEnd) return ""

        return buildString {
            var cursor = safeStart
            for (indexed in indexedBlocks) {
                if (indexed.sourceEnd <= safeStart) continue
                if (indexed.sourceStart >= safeEnd) break

                val separatorEnd = minOf(safeEnd, indexed.sourceStart)
                if (cursor < separatorEnd) {
                    append(sourceText, cursor, separatorEnd)
                    cursor = separatorEnd
                }

                val overlapStart = maxOf(safeStart, indexed.sourceStart)
                val overlapEnd = minOf(safeEnd, indexed.sourceEnd)
                if (overlapStart < overlapEnd) {
                    append(
                        indexed.placed.result.getTextForCopy(
                            TextRange(
                                overlapStart - indexed.sourceStart,
                                overlapEnd - indexed.sourceStart,
                            ),
                        ),
                    )
                    cursor = overlapEnd
                }
            }
            if (cursor < safeEnd) append(sourceText, cursor, safeEnd)
        }
    }

    /** Link fragments derived from the same occupied source geometry as selection and hit testing. */
    fun linkBoxes(): List<LinkBox> = buildList {
        indexedBlocks.forEach { indexed ->
            val block = indexed.placed
            block.richTextSpans.forEach spanLoop@ { span ->
                val link = span.role as? Link ?: return@spanLoop
                block.result.getBoundingBoxes(span.range).forEach { rect ->
                    add(
                        LinkBox(
                            target = link.target,
                            start = indexed.sourceStart + span.range.start,
                            end = indexed.sourceStart + span.range.end,
                            left = block.x + rect.left,
                            top = block.yTop + rect.top,
                            right = block.x + rect.right,
                            bottom = block.yTop + rect.bottom,
                        ),
                    )
                }
            }
        }
    }

    /** Return the native link target under a document point, or null outside occupied link boxes. */
    fun linkAt(x: Double, y: Double): String? = linkBoxes().firstOrNull { box ->
        x >= box.left && x <= box.right && y >= box.top && y <= box.bottom
    }?.target

    /**
     * Return continuous, line-local selection boxes for a global UTF-16 source range. Geometry is
     * transformed from each block's real `LayoutResult`; adjacent cluster slices on one line are
     * merged so the native selection highlight does not acquire renderer-side seams.
     */
    fun selectionBoxes(start: Int, end: Int): List<SelectionBox> {
        val safeStart = minOf(start, end).coerceIn(0, sourceText.length)
        val safeEnd = maxOf(start, end).coerceIn(safeStart, sourceText.length)
        if (safeStart == safeEnd) return emptyList()

        val boxes = mutableListOf<SelectionBox>()
        indexedBlocks.forEach { indexed ->
            val localStart = (safeStart - indexed.sourceStart)
                .coerceIn(0, indexed.placed.result.input.content.text.length)
            val localEnd = (safeEnd - indexed.sourceStart)
                .coerceIn(localStart, indexed.placed.result.input.content.text.length)
            if (localStart == localEnd) return@forEach
            val block = indexed.placed
            block.result.getBoundingBoxes(TextRange(localStart, localEnd)).forEach { rect ->
                boxes += SelectionBox(
                    left = block.x + rect.left,
                    top = block.yTop + rect.top,
                    right = block.x + rect.right,
                    bottom = block.yTop + rect.bottom,
                )
            }
        }
        return boxes.mergeLineLocalBoxes()
    }

    /** Return the caret box for a global UTF-16 source offset. */
    fun caretBox(offset: Int): SelectionBox {
        val clamped = offset.coerceIn(0, sourceText.length)
        val indexed = indexedBlocks.lastOrNull { clamped >= it.sourceStart }
            ?: return SelectionBox(0.0, 0.0, 1.0, 0.0)
        val block = indexed.placed
        val local = (clamped - indexed.sourceStart)
            .coerceIn(0, block.result.input.content.text.length)
        val rect = block.result.getCursorRect(local)
        return SelectionBox(
            left = block.x + rect.left,
            top = block.yTop + rect.top,
            right = block.x + rect.right,
            bottom = block.yTop + rect.bottom,
        )
    }

    /**
     * Draw the whole document into [context]; [canvasHeight] is the CGContext pixel height with the
     * document's top mapped to it (the caller folds in any top inset, exactly as for a single
     * paragraph). Each block draws at its own `canvasHeight - yTop`, and list bodies translate the
     * context by their marker-column width.
     *
     * [context] crosses the Kotlin/Native boundary as an opaque pointer (`CGContextRef` cannot be a
     * typed Swift `CGContext`); Swift passes `Unmanaged.passUnretained(cgContext).toOpaque()`. The
     * renderer expects a y-up context and never sets a base fill color (it inherits the current one,
     * so light/dark text color is the caller's; colored spans override per cluster).
     */
    fun draw(context: CGContextRef, canvasHeight: Double) {
        for (b in blocks) {
            val blockCanvasHeight = canvasHeight - b.yTop
            if (blockCanvasHeight <= 0.0) continue
            if (b.x != 0.0) {
                CGContextSaveGState(context)
                CGContextTranslateCTM(context, b.x, 0.0)
                renderer.draw(b.result, context, blockCanvasHeight, b.spans, b.colorSpans, b.richTextSpans)
                CGContextRestoreGState(context)
            } else {
                renderer.draw(b.result, context, blockCanvasHeight, b.spans, b.colorSpans, b.richTextSpans)
            }
        }
    }

    private fun nearestBlock(x: Double, y: Double): IndexedBlock? = indexedBlocks.minByOrNull { indexed ->
        val block = indexed.placed
        val left = block.x
        val top = block.yTop
        val right = left + block.result.size.width
        val bottom = top + block.result.size.height
        val dx = when {
            x < left -> left - x
            x > right -> x - right
            else -> 0.0
        }
        val dy = when {
            y < top -> top - y
            y > bottom -> y - bottom
            else -> 0.0
        }
        dx * dx + dy * dy
    }
}

private fun List<SelectionBox>.mergeLineLocalBoxes(): List<SelectionBox> {
    if (isEmpty()) return this
    val merged = mutableListOf<SelectionBox>()
    for (next in this) {
        val previous = merged.lastOrNull()
        if (
            previous != null &&
            abs(previous.top - next.top) < 0.5 &&
            abs(previous.bottom - next.bottom) < 0.5
        ) {
            merged[merged.lastIndex] = SelectionBox(
                left = minOf(previous.left, next.left),
                top = minOf(previous.top, next.top),
                right = maxOf(previous.right, next.right),
                bottom = maxOf(previous.bottom, next.bottom),
            )
        } else {
            merged += next
        }
    }
    return merged
}
