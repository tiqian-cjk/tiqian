package org.tiqian.compose

import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.text.AnnotatedString
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextRange

/** One stable, independently virtualizable fragment in a selectable document. */
@Immutable
data class CjkSelectionDocumentFragment(
    val key: Any,
    val text: AnnotatedString,
    val textForCopy: AnnotatedString = text,
    val separatorAfter: String = "\n",
)

/**
 * Logical reading order and text projection for a virtualized document.
 *
 * Fragments exist independently of composition. Visible [CjkText] surfaces register only geometry
 * under the matching [CjkSelectionScope] key, so selection endpoints survive disposal.
 */
@Immutable
class CjkSelectionDocument(fragments: List<CjkSelectionDocumentFragment>) {
    val fragments: List<CjkSelectionDocumentFragment> = fragments.toList()
    internal val indexByKey: Map<Any, Int> = this.fragments.mapIndexed { index, fragment ->
        fragment.key to index
    }.toMap().also { index ->
        require(index.size == this.fragments.size) { "CjkSelectionDocument fragment keys must be unique" }
    }
}

/**
 * A half-open UTF-16 source range in a [CjkSelectionDocumentFragment]. [fragmentText] is the
 * fragment's original annotated source, independent of its copy projection. A range may be empty
 * when the selection touches a fragment boundary or crosses an empty fragment.
 */
@Immutable
data class CjkSelectionDocumentRange(
    val fragmentKey: Any,
    val start: Int,
    val end: Int,
    val fragmentText: AnnotatedString,
)

internal data class CjkSelectionProjection(
    val text: AnnotatedString? = null,
    val ranges: List<CjkSelectionDocumentRange>? = null,
)

internal data class CjkSelectionScopeInfo(
    val ownerKey: Any,
    val retentionKey: Any,
)

internal interface CjkSelectable {
    val selectionText: AnnotatedString
    val selectionCoordinates: LayoutCoordinates?
    fun selectionTextForCopy(range: TextRange): String
    fun updateSelectionCoordinates(coordinates: LayoutCoordinates)
    fun selectionOffsetAt(localPosition: Offset): Int?
    fun selectionWordRangeAt(localPosition: Offset): TextRange?
    fun selectionParagraphRangeAt(localPosition: Offset): TextRange?
    fun coerceSelectionOffset(offset: Int, bias: SourceBoundaryBias): Int
    fun selectionCursorPosition(offset: Int, isEnd: Boolean = false): Offset?
    fun selectionLineRange(offset: Int, isEnd: Boolean = false): TextRange?
    fun selectionLineLeft(offset: Int): Float
    fun selectionLineRight(offset: Int): Float
    fun selectionLineCenterY(offset: Int, isEnd: Boolean = false): Float
    fun selectionLineHeight(offset: Int, isEnd: Boolean = false): Float
    fun selectionBoxes(range: TextRange): List<org.tiqian.core.Rect>
    fun invalidateSelection()
}

internal class CjkSystemContextMenu(
    val show: () -> Unit,
    val hide: () -> Unit,
)

internal data class CjkSelectionAnchor(
    val key: Any,
    val offset: Int,
)

internal data class CjkSelection(
    val anchor: CjkSelectionAnchor,
    val extent: CjkSelectionAnchor,
)
