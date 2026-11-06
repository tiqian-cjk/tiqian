package org.tiqian.compose

import androidx.compose.ui.text.AnnotatedString
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextRange
import org.tiqian.core.sourceGraphemeBoundaries

internal const val RenderOnlyInlineObjectTag = "tiqian:render-only-inline-object"
private const val LegacyInlineProjectionOffsetTag = "tiqian:inline-projection-offset"

/** Marks one internal U+FFFC layout slot as having no logical, copy or selection characters. */
fun AnnotatedString.Builder.addCjkRenderOnlyInlineObject(
    start: Int,
    end: Int,
) {
    require(start >= 0 && end == start + 1) { "A render-only slot must cover one layout character" }
    addStringAnnotation(RenderOnlyInlineObjectTag, "", start, end)
}

/** Offset records belong to the layout node and never enter public text or copied annotations. */
internal class CjkInlineObjectOffsetMapping(
    source: AnnotatedString,
) {
    private val sourceLength = source.length
    private val slots =
        source
            .getStringAnnotations(RenderOnlyInlineObjectTag, 0, Int.MAX_VALUE)
            .sortedBy { it.start }
            .also { ranges ->
                var end = 0
                ranges.forEach { slot ->
                    require(
                        slot.start >= end && slot.end == slot.start + 1 && slot.end <= source.length && source[slot.start] == '\uFFFC',
                    ) {
                        "Render-only slots must be non-overlapping U+FFFC characters"
                    }
                    end = slot.end
                }
            }.map { it.start }
            .toIntArray()
    private val logicalSlots = IntArray(slots.size) { slots[it] - it }
    private val logicalLength = sourceLength - slots.size
    val hasRenderOnlyObjects: Boolean get() = slots.isNotEmpty()

    val logicalText: AnnotatedString =
        if (slots.isEmpty() &&
            source.getStringAnnotations(LegacyInlineProjectionOffsetTag, 0, Int.MAX_VALUE).isEmpty()
        ) {
            source
        } else {
            val text =
                buildString(logicalLength) {
                    var cursor = 0
                    for (slot in slots) {
                        append(source.text, cursor, slot)
                        cursor = slot + 1
                    }
                    append(source.text, cursor, sourceLength)
                }
            val annotations = mutableListOf<AnnotatedString.Range<AnnotatedString.Annotation>>()
            source.flatMapAnnotations { annotation ->
                val start = toLogical(annotation.start)
                val end = toLogical(annotation.end)
                if (annotation.tag != RenderOnlyInlineObjectTag &&
                    annotation.tag != LegacyInlineProjectionOffsetTag &&
                    (start < end || annotation.start == annotation.end)
                ) {
                    annotations += AnnotatedString.Range(annotation.item, start, end, annotation.tag)
                }
                emptyList()
            }
            AnnotatedString(text, annotations)
        }
    private val logicalBoundaries by lazy {
        logicalText.text.sourceGraphemeBoundaries(TextRange(0, logicalLength))
    }

    fun toLayout(
        offset: Int,
        after: Boolean = true,
    ): Int {
        val logical = offset.coerceIn(0, logicalLength)
        var removed = 0
        for (slot in logicalSlots) {
            if (slot > logical || !after && slot == logical) break
            removed++
        }
        return logical + removed
    }

    fun toLogical(offset: Int): Int {
        val layout = offset.coerceIn(0, sourceLength)
        var removed = 0
        for (slot in slots) {
            if (slot >= layout) break
            removed++
        }
        return layout - removed
    }

    fun toLogical(range: TextRange): TextRange = TextRange(toLogical(range.start), toLogical(range.end))

    fun coerceLogicalOffset(
        offset: Int,
        bias: SourceBoundaryBias,
    ): Int {
        val target = offset.coerceIn(0, logicalLength)
        if (!hasRenderOnlyObjects) return target
        val index = logicalBoundaries.binarySearch(target)
        if (index >= 0) return target
        val next = -index - 1
        val previous = logicalBoundaries[next - 1]
        val following = logicalBoundaries[next]
        return when (bias) {
            SourceBoundaryBias.Backward -> previous
            SourceBoundaryBias.Forward -> following
            SourceBoundaryBias.Nearest -> if (target - previous < following - target) previous else following
        }
    }

    /** Exclude every internal object from selection paint, including objects inside a range. */
    fun layoutRanges(range: TextRange): List<TextRange> {
        if (range.isEmpty) return emptyList()
        var cursor = toLayout(range.start)
        val end = toLayout(range.end, after = false)
        val ranges = mutableListOf<TextRange>()
        for (slot in slots) {
            if (slot >= end) break
            if (slot + 1 <= cursor) continue
            if (slot > cursor) ranges += TextRange(cursor, slot)
            cursor = maxOf(cursor, slot + 1)
        }
        if (cursor < end) ranges += TextRange(cursor, end)
        return ranges
    }
}
