package org.tiqian.android.view

import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.RubySpan
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextRange
import org.tiqian.core.coerceTextSelectionOffset
import org.tiqian.core.projectTextForCopy

/** One stable, independently virtualizable fragment in a selectable Android View document. */
data class CjkSelectionDocumentFragment(
    val key: Any,
    val text: String,
    val rubySpans: List<RubySpan> = emptyList(),
    val inlineObjects: List<InlineObjectSpan> = emptyList(),
    val separatorAfter: String = "\n",
) {
    constructor(
        key: Any,
        content: CjkTextContent,
        separatorAfter: String = "\n",
    ) : this(
        key = key,
        text = content.content.text,
        rubySpans = content.rubySpans,
        inlineObjects = content.inlineObjects,
        separatorAfter = separatorAfter,
    )

    internal fun textForCopy(range: TextRange): String =
        projectTextForCopy(text, range, rubySpans.toMutableList())

    internal fun coerceSelectionOffset(offset: Int, bias: SourceBoundaryBias): Int =
        coerceTextSelectionOffset(text, inlineObjects, offset, bias)
}

/**
 * Logical reading order and clipboard projection for a virtualized Android View document.
 *
 * Fragments exist independently of attached Views. A visible [CjkTextView] contributes only its
 * current geometry under a matching [CjkTextView.selectionDocumentKey], so logical endpoints and
 * copying survive RecyclerView recycling without retaining or measuring the full document.
 */
class CjkSelectionDocument(fragments: List<CjkSelectionDocumentFragment>) {
    val fragments: List<CjkSelectionDocumentFragment> = fragments.toList()

    internal val indexByKey: Map<Any, Int> = this.fragments.mapIndexed { index, fragment ->
        fragment.key to index
    }.toMap().also { index ->
        require(index.size == this.fragments.size) {
            "CjkSelectionDocument fragment keys must be unique"
        }
    }
}

internal data class CjkDocumentSelectionAnchor(
    val key: Any,
    val offset: Int,
)

internal data class CjkDocumentSelection(
    val anchor: CjkDocumentSelectionAnchor,
    val extent: CjkDocumentSelectionAnchor,
)

internal fun List<CjkSelectionDocumentFragment>.projectSelectionText(
    start: CjkDocumentSelectionAnchor,
    end: CjkDocumentSelectionAnchor,
    copyProjection: Boolean,
): String? {
    val slice = selectionSlice(start, end) ?: return null
    return buildString {
        for (index in slice.startIndex..slice.endIndex) {
            val fragment = this@projectSelectionText[index]
            val lower = if (index == slice.startIndex) slice.startOffset else 0
            val upper = if (index == slice.endIndex) slice.endOffset else fragment.text.length
            if (upper > lower) {
                if (copyProjection) {
                    append(fragment.textForCopy(TextRange(lower, upper)))
                } else {
                    append(fragment.text, lower, upper)
                }
            }
            if (index < slice.endIndex) append(fragment.separatorAfter)
        }
    }.takeIf { it.isNotEmpty() }
}
