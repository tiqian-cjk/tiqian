package org.tiqian.compose

import androidx.compose.ui.text.AnnotatedString
import org.tiqian.core.TextRange

private const val RenderOnlyInlineObjectTag = "tiqian:render-only-inline-object"
private const val InlineProjectionOffsetTag = "tiqian:inline-projection-offset"

/** Marks one internal U+FFFC layout slot as having no logical, copy or selection characters. */
fun AnnotatedString.Builder.addCjkRenderOnlyInlineObject(start: Int, end: Int) {
    require(start >= 0 && end == start + 1) { "A render-only slot must cover one layout character" }
    addStringAnnotation(RenderOnlyInlineObjectTag, "", start, end)
}

/** Removes only explicitly annotated layout slots; authored U+FFFC characters remain intact. */
internal fun AnnotatedString.cjkInlineLogicalText(): AnnotatedString {
    val slots = getStringAnnotations(RenderOnlyInlineObjectTag, 0, Int.MAX_VALUE).sortedBy { it.start }
    if (slots.isEmpty()) return this
    val builder = AnnotatedString.Builder()
    var cursor = 0
    for (slot in slots) {
        require(slot.start >= cursor && slot.end == slot.start + 1 && slot.end <= length && this[slot.start] == '\uFFFC') {
            "Render-only slots must be non-overlapping U+FFFC characters"
        }
        builder.append(subSequence(cursor, slot.start))
        builder.addStringAnnotation(InlineProjectionOffsetTag, "1", builder.length, builder.length)
        cursor = slot.end
    }
    builder.append(subSequence(cursor, length))
    return builder.toAnnotatedString()
}

/** Logical semantics carry zero-length offset annotations, never artificial copy characters. */
internal class CjkInlineObjectOffsetMapping(private val logicalText: AnnotatedString) {
    private val slots = logicalText.getStringAnnotations(InlineProjectionOffsetTag, 0, Int.MAX_VALUE)
        .sortedBy { it.start }

    fun toLayout(offset: Int, after: Boolean = true): Int {
        val logical = offset.coerceIn(0, logicalText.length)
        return logical + slots.filter { it.start < logical || after && it.start == logical }.sumOf { it.item.toInt() }
    }

    fun toLogical(offset: Int): Int {
        var removed = 0
        for (slot in slots) {
            val start = slot.start + removed
            if (offset <= start) return (offset - removed).coerceIn(0, logicalText.length)
            if (offset < start + slot.item.toInt()) return slot.start
            removed += slot.item.toInt()
        }
        return (offset - removed).coerceIn(0, logicalText.length)
    }

    fun toLogical(range: TextRange): TextRange = TextRange(toLogical(range.start), toLogical(range.end))

    /** Exclude every internal object from selection paint and copy, including objects inside a range. */
    fun layoutRanges(range: TextRange): List<TextRange> {
        if (range.isEmpty) return emptyList()
        var cursor = toLayout(range.start)
        val end = toLayout(range.end, after = false)
        val ranges = mutableListOf<TextRange>()
        var removed = 0
        for (slot in slots) {
            val start = slot.start + removed
            val slotEnd = start + slot.item.toInt()
            removed += slot.item.toInt()
            if (start >= end) break
            if (slotEnd <= cursor) continue
            if (start > cursor) ranges += TextRange(cursor, start)
            cursor = maxOf(cursor, slotEnd)
        }
        if (cursor < end) ranges += TextRange(cursor, end)
        return ranges
    }
}
