@file:Suppress("DEPRECATION")

package org.tiqian.compose

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextRange
import org.tiqian.core.sourceGraphemeBoundaries
import kotlin.math.abs

/** Observable state for one [CjkSelectionContainer]. */
@Stable
class CjkSelectionState internal constructor() {
    private var selectionProjection by mutableStateOf(CjkSelectionProjection())

    /** The source text and separators in the current selection, or null when nothing is selected. */
    val selectedText: AnnotatedString?
        get() = selectionProjection.text

    /**
     * A snapshot of every touched fragment in document order, including fragments not currently
     * composed. Offsets are UTF-16 and half-open. Empty ranges preserve both touched boundaries
     * and empty intervening fragments; separators are present only in [selectedText]. Each range
     * includes the original fragment text. Returns null without a [CjkSelectionDocument] or when
     * [selectedText] is null, including selections containing no source or separator characters.
     * Reading the list copies its entries without copying fragment text, and cannot modify state.
     */
    val selectedRanges: List<CjkSelectionDocumentRange>?
        get() = selectionProjection.ranges?.toList()

    /** Owners retained only while their pointer coroutine is actively dragging. */
    var activeGestureOwnerKeys: Set<Any> by mutableStateOf(emptySet())
        private set

    private val selectables = mutableListOf<CjkSelectable>()
    private val selectableScopes = mutableMapOf<CjkSelectable, CjkSelectionScopeInfo?>()
    private var orderedSelectablesCache: List<CjkSelectable>? = null
    private var selectionRanges: Map<CjkSelectable, TextRange> = emptyMap()
    private var selection: CjkSelection? = null
    private var clipboardManager: ClipboardManager? = null
    private var textToolbar: TextToolbar? = null
    private var systemContextMenu: CjkSystemContextMenu? = null
    private var hapticFeedback: HapticFeedback? = null
    private var containerCoordinates: LayoutCoordinates? = null
    private var gestureInitialSelection: CjkSelection? = null
    private var handleFixedAnchor: CjkSelectionAnchor? = null
    private var handleDragPosition: Offset = Offset.Zero
    private var activeDragIsStart: Boolean? = null
    private var activeGestureAdjustment: CjkSelectionAdjustment = CjkSelectionAdjustment.None
    internal val focusRequester = FocusRequester()
    internal var isTouchSelection by mutableStateOf(false)
        private set
    internal var hasSelection by mutableStateOf(false)
        private set
    internal var startHandlePosition by mutableStateOf<Offset?>(null)
        private set
    internal var endHandlePosition by mutableStateOf<Offset?>(null)
        private set
    internal var startHandleLineHeight by mutableStateOf(0f)
        private set
    internal var endHandleLineHeight by mutableStateOf(0f)
        private set
    internal var handlesCrossed by mutableStateOf(false)
        private set
    internal var currentDragPosition by mutableStateOf(Offset.Unspecified)
        private set
    internal var selectionBackgroundArgb: Int by mutableStateOf(0)
        private set
    internal var selectionViewportHeightPx by mutableStateOf(0f)
        private set
    private var selectionToolbarHandleClearancePx = 0f
    internal var isSelectionAutoScrollArmed by mutableStateOf(false)
        private set
    private var contextMenuPositionEpoch by mutableStateOf(0)
    private var contextMenuToolbarRequested = false
    private var document: CjkSelectionDocument? = null
    internal val isSelectionGestureInProgress: Boolean
        get() = gestureInitialSelection != null || handleFixedAnchor != null

    /** Clears the active selection and hides its toolbar/handles. */
    fun clearSelection() {
        val ownedSelectionOrGesture =
            selection != null || gestureInitialSelection != null || handleFixedAnchor != null
        val previouslySelected = selectionRanges.keys.toList()
        // Finish ActionMode before publishing an empty selection. Otherwise Android can rebuild the
        // still-visible menu from the intermediate state and briefly show only "Select all".
        if (ownedSelectionOrGesture) hideContextMenuToolbar()
        selection = null
        selectionRanges = emptyMap()
        selectionProjection = CjkSelectionProjection()
        hasSelection = false
        startHandlePosition = null
        endHandlePosition = null
        startHandleLineHeight = 0f
        endHandleLineHeight = 0f
        handlesCrossed = false
        gestureInitialSelection = null
        handleFixedAnchor = null
        activeDragIsStart = null
        activeGestureAdjustment = CjkSelectionAdjustment.None
        currentDragPosition = Offset.Unspecified
        isSelectionAutoScrollArmed = false
        isTouchSelection = false
        activeGestureOwnerKeys = emptySet()
        previouslySelected.forEach(CjkSelectable::invalidateSelection)
    }

    /**
     * Copies the Web-compatible plain-text projection of the current selection. Selection state
     * and accessibility semantics stay source-faithful; only fully selected ruby / 注音 readings
     * are appended to the clipboard text.
     */
    fun copySelection(): Boolean {
        if (!hasSelection) return false
        val selected = buildClipboardText()?.takeIf { it.isNotEmpty() } ?: return false
        @Suppress("DEPRECATION")
        clipboardManager?.setText(selected) ?: return false
        return true
    }
    /** Selects a non-empty half-open UTF-16 range in the attached logical document. Invalid input leaves selection unchanged. */
    fun selectRange(fragmentKey: Any, start: Int, end: Int): Boolean {
        val currentDocument = document ?: return false
        val fragment = currentDocument.fragments[currentDocument.indexByKey[fragmentKey] ?: return false]
        if (start < 0 || start >= end || end > fragment.text.length) return false
        val boundaries = fragment.text.text.sourceGraphemeBoundaries(TextRange(0, fragment.text.length))
        val range = TextRange(boundaries.last { it <= start }, boundaries.first { it >= end })
        gestureInitialSelection = null
        handleFixedAnchor = null
        setSelection(CjkSelectionAnchor(fragment.key, range.start), CjkSelectionAnchor(fragment.key, range.end), touch = isTouchSelection)
        finishSelection()
        return true
    }

    /** Selects the logical document without composing or measuring off-screen fragments. */
    fun selectAll(): Boolean {
        document?.fragments?.takeIf { it.isNotEmpty() }?.let { fragments ->
            val first = fragments.first()
            val last = fragments.last()
            setSelection(
                CjkSelectionAnchor(first.key, 0),
                CjkSelectionAnchor(last.key, last.text.length),
                touch = isTouchSelection,
            )
            showContextMenuToolbarIfTouch()
            return true
        }
        val ordered = orderedSelectables()
        val first = ordered.firstOrNull() ?: return false
        val last = ordered.last()
        setSelection(
            CjkSelectionAnchor(keyFor(first), 0),
            CjkSelectionAnchor(keyFor(last), last.selectionText.length),
            touch = isTouchSelection,
        )
        showContextMenuToolbarIfTouch()
        return true
    }

    internal fun attach(
        clipboardManager: ClipboardManager,
        textToolbar: TextToolbar,
        hapticFeedback: HapticFeedback,
        selectionBackgroundArgb: Int,
        selectionToolbarHandleClearancePx: Float,
        document: CjkSelectionDocument?,
    ) {
        this.clipboardManager = clipboardManager
        this.textToolbar = textToolbar
        this.hapticFeedback = hapticFeedback
        this.selectionBackgroundArgb = selectionBackgroundArgb
        this.selectionToolbarHandleClearancePx = selectionToolbarHandleClearancePx
        if (this.document !== document) {
            this.document = document
            if (selection != null) clearSelection()
            orderedSelectablesCache = null
        }
    }

    internal fun detach() {
        clearSelection()
        containerCoordinates = null
        clipboardManager = null
        textToolbar = null
        hapticFeedback = null
        document = null
    }

    internal fun attachSystemContextMenu(menu: CjkSystemContextMenu) {
        systemContextMenu = menu
        if (contextMenuToolbarRequested) menu.show()
    }

    internal fun detachSystemContextMenu(menu: CjkSystemContextMenu) {
        if (systemContextMenu === menu) {
            menu.hide()
            systemContextMenu = null
            contextMenuToolbarRequested = false
        }
    }

    internal fun updateContainerCoordinates(coordinates: LayoutCoordinates) {
        containerCoordinates = coordinates
        selectionViewportHeightPx = coordinates.size.height.toFloat()
        orderedSelectablesCache = null
        contextMenuPositionEpoch++
        updateDerivedSelection()
    }

    internal fun register(
        selectable: CjkSelectable,
        scope: CjkSelectionScopeInfo?,
    ) {
        if (selectable !in selectables) {
            selectables += selectable
        }
        selectableScopes[selectable] = scope
        orderedSelectablesCache = null
        validateDocumentRegistration(selectable, scope)
        if (selection != null) updateDerivedSelection()
    }

    internal fun unregister(selectable: CjkSelectable) {
        selectables -= selectable
        selectableScopes -= selectable
        orderedSelectablesCache = null
        val current = selection
        if (document == null && (current?.anchor?.key === selectable || current?.extent?.key === selectable)) {
            clearSelection()
        } else if (current != null) {
            updateDerivedSelection()
        }
    }

    internal fun selectableChanged(selectable: CjkSelectable, textChanged: Boolean = false) {
        orderedSelectablesCache = null
        contextMenuPositionEpoch++
        val current = selection
        if (
            textChanged && document == null &&
            (current?.anchor?.key === selectable || current?.extent?.key === selectable)
        ) {
            clearSelection()
        } else if (current != null) {
            updateDerivedSelection()
        }
    }

    private fun validateDocumentRegistration(
        selectable: CjkSelectable,
        scope: CjkSelectionScopeInfo?,
    ) {
        val logicalDocument = document ?: return
        val key = scope?.ownerKey ?: return
        val index = logicalDocument.indexByKey[key]
            ?: error("CjkSelectionScope key is absent from CjkSelectionDocument: $key")
        require(logicalDocument.fragments[index].text.text == selectable.selectionText.text) {
            "CjkSelectionScope text differs from CjkSelectionDocument fragment: $key"
        }
        require(selectables.none { other ->
            other !== selectable && selectableScopes[other]?.ownerKey == key
        }) { "Only one visible CjkText may register a document fragment: $key" }
    }

    internal fun beginGestureSelectionAtContainerPosition(
        containerPosition: Offset,
        adjustment: CjkSelectionAdjustment,
        touch: Boolean,
    ): Boolean {
        val hit = selectableAndLocalPositionAt(containerPosition) ?: return false
        hideContextMenuToolbar()
        focusRequester.requestFocus()
        val initial = selectionAt(hit.first, hit.second, adjustment) ?: return false
        gestureInitialSelection = initial
        activeGestureOwnerKeys = selectableScopes[hit.first]?.retentionKey?.let(::setOf).orEmpty()
        activeGestureAdjustment = adjustment
        activeDragIsStart = if (touch) false else null
        currentDragPosition = containerPosition
        setSelection(initial.anchor, initial.extent, touch)
        return true
    }

    internal fun beginGestureSelection(
        selectable: CjkSelectable,
        localPosition: Offset,
        adjustment: CjkSelectionAdjustment,
        touch: Boolean,
    ): Boolean {
        if (!isSelectableEligible(selectable)) return false
        val position = toContainerPosition(selectable, localPosition) ?: return false
        return beginGestureSelectionAtContainerPosition(position, adjustment, touch)
    }

    internal fun extendGestureSelectionAtContainerPosition(containerPosition: Offset): Boolean {
        val current = selection ?: return false
        val target = anchorAtContainerPosition(containerPosition) ?: return false
        hideContextMenuToolbar()
        focusRequester.requestFocus()
        gestureInitialSelection = CjkSelection(current.anchor, current.anchor)
        currentDragPosition = containerPosition
        setSelection(current.anchor, target, touch = false)
        return true
    }

    internal fun extendGestureSelection(
        selectable: CjkSelectable,
        localPosition: Offset,
    ): Boolean {
        if (!isSelectableEligible(selectable)) return false
        val position = toContainerPosition(selectable, localPosition) ?: return false
        return extendGestureSelectionAtContainerPosition(position)
    }

    internal fun updateGestureSelectionAtContainerPosition(
        containerPosition: Offset,
        adjustment: CjkSelectionAdjustment,
    ): Boolean {
        currentDragPosition = containerPosition
        activeGestureAdjustment = adjustment
        val initial = gestureInitialSelection ?: selection ?: return false
        val hit = selectableAndLocalPositionAt(containerPosition) ?: return false
        val targetSelection = selectionAt(hit.first, hit.second, adjustment) ?: return false
        val next = when (adjustment) {
            CjkSelectionAdjustment.Word,
            CjkSelectionAdjustment.Paragraph,
            -> adjustedDragSelection(initial, targetSelection)
            CjkSelectionAdjustment.None,
            CjkSelectionAdjustment.CharacterWithWordAccelerate,
            -> CjkSelection(initial.anchor, targetSelection.extent)
        }
        setSelection(next.anchor, next.extent, isTouchSelection)
        return true
    }

    internal fun updateGestureSelection(
        selectable: CjkSelectable,
        localPosition: Offset,
        adjustment: CjkSelectionAdjustment,
    ): Boolean {
        if (!isSelectableEligible(selectable)) return false
        val position = toContainerPosition(selectable, localPosition) ?: return false
        return updateGestureSelectionAtContainerPosition(position, adjustment)
    }

    private fun toContainerPosition(selectable: CjkSelectable, localPosition: Offset): Offset? {
        val container = containerCoordinates ?: return null
        val coordinates = selectable.selectionCoordinates ?: return null
        if (!container.isAttached || !coordinates.isAttached) return null
        return container.localPositionOf(coordinates, localPosition)
    }

    internal fun armSelectionAutoScroll() {
        if (gestureInitialSelection != null || handleFixedAnchor != null) {
            isSelectionAutoScrollArmed = true
        }
    }

    internal fun refreshSelectionAfterAutoScroll() {
        if (!isSelectionAutoScrollArmed || !currentDragPosition.isSpecified) return
        val handleIsStart = activeDragIsStart
        if (handleFixedAnchor != null && handleIsStart != null) {
            updateHandleSelectionAtContainerPosition(handleIsStart, currentDragPosition)
        } else if (gestureInitialSelection != null) {
            updateGestureSelectionAtContainerPosition(currentDragPosition, activeGestureAdjustment)
        }
    }

    internal fun finishSelection() {
        gestureInitialSelection = null
        activeGestureOwnerKeys = emptySet()
        activeGestureAdjustment = CjkSelectionAdjustment.None
        activeDragIsStart = null
        currentDragPosition = Offset.Unspecified
        isSelectionAutoScrollArmed = false
        updateHandlePositions()
        showContextMenuToolbarIfTouch()
    }

    internal fun rangeFor(selectable: CjkSelectable): TextRange? {
        return selectionRanges[selectable]
    }

    internal fun setSelectionFromSemantics(
        selectable: CjkSelectable,
        start: Int,
        end: Int,
    ): Boolean {
        if (!isSelectableEligible(selectable)) return false
        val safeStart = selectable.coerceSelectionOffset(start, SourceBoundaryBias.Backward)
        val safeEnd = selectable.coerceSelectionOffset(end, SourceBoundaryBias.Forward)
        setSelection(
            CjkSelectionAnchor(keyFor(selectable), safeStart),
            CjkSelectionAnchor(keyFor(selectable), safeEnd),
            touch = false,
        )
        return true
    }

    internal fun beginHandleDrag(isStart: Boolean) {
        val current = selection ?: return
        handleFixedAnchor = if (isStart) current.extent else current.anchor
        val draggedAnchor = if (isStart) current.anchor else current.extent
        activeGestureOwnerKeys = selectableForKey(draggedAnchor.key)
            ?.let(selectableScopes::get)
            ?.retentionKey
            ?.let(::setOf)
            .orEmpty()
        handleDragPosition = (if (isStart) startHandlePosition else endHandlePosition) ?: return
        handleDragPosition += Offset(0f, -1f)
        activeDragIsStart = isStart
        currentDragPosition = handleDragPosition
        hideContextMenuToolbar()
    }

    internal fun dragHandle(isStart: Boolean, delta: Offset) {
        val fixed = handleFixedAnchor ?: return
        handleDragPosition += delta
        currentDragPosition = handleDragPosition
        updateHandleSelectionAtContainerPosition(isStart, handleDragPosition, fixed)
    }

    private fun updateHandleSelectionAtContainerPosition(
        isStart: Boolean,
        position: Offset,
        fixed: CjkSelectionAnchor? = handleFixedAnchor,
    ) {
        val fixedAnchor = fixed ?: return
        val target = anchorAtContainerPosition(position) ?: return
        if (isStart) {
            setSelection(target, fixedAnchor, touch = true)
        } else {
            setSelection(fixedAnchor, target, touch = true)
        }
    }

    internal fun endHandleDrag() {
        handleFixedAnchor = null
        activeGestureOwnerKeys = emptySet()
        activeDragIsStart = null
        currentDragPosition = Offset.Unspecified
        isSelectionAutoScrollArmed = false
        showContextMenuToolbarIfTouch()
    }

    internal fun handleCopyKeyEvent(event: KeyEvent): Boolean {
        if (
            event.type == KeyEventType.KeyDown && event.key == Key.C &&
            (event.isCtrlPressed || event.isMetaPressed)
        ) {
            return copySelection()
        }
        if (event.type == KeyEventType.KeyDown && event.key == Key.Escape && hasSelection) {
            clearSelection()
            return true
        }
        return false
    }

    private fun setSelection(
        anchor: CjkSelectionAnchor,
        extent: CjkSelectionAnchor,
        touch: Boolean,
    ) {
        val next = CjkSelection(anchor, extent)
        val changed = selection != next
        val touchModeChanged = isTouchSelection != touch
        if (!changed && !touchModeChanged) return
        selection = next
        isTouchSelection = touch
        if (changed && touch) {
            hapticFeedback?.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        }
        if (changed) updateDerivedSelection(selectionChanged = true)
    }

    private fun selectionAt(
        selectable: CjkSelectable,
        localPosition: Offset,
        adjustment: CjkSelectionAdjustment,
    ): CjkSelection? = when (adjustment) {
        CjkSelectionAdjustment.Word ->
            selectable.selectionWordRangeAt(localPosition)?.let { range ->
                CjkSelection(
                    CjkSelectionAnchor(keyFor(selectable), range.start),
                    CjkSelectionAnchor(keyFor(selectable), range.end),
                )
            }
        CjkSelectionAdjustment.Paragraph ->
            selectable.selectionParagraphRangeAt(localPosition)?.let { range ->
                CjkSelection(
                    CjkSelectionAnchor(keyFor(selectable), range.start),
                    CjkSelectionAnchor(keyFor(selectable), range.end),
                )
            }
        CjkSelectionAdjustment.None,
        CjkSelectionAdjustment.CharacterWithWordAccelerate,
        -> anchorAt(selectable, localPosition)?.let { CjkSelection(it, it) }
    }

    /**
     * Foundation keeps the originally adjusted word/paragraph selected while the moving endpoint
     * crosses it, then expands from the correct outer boundary in either direction.
     */
    private fun adjustedDragSelection(
        initial: CjkSelection,
        target: CjkSelection,
    ): CjkSelection = when {
        compareAnchors(target.extent, initial.anchor) < 0 ->
            CjkSelection(initial.extent, target.anchor)
        compareAnchors(target.anchor, initial.extent) > 0 ->
            CjkSelection(initial.anchor, target.extent)
        else -> initial
    }

    private fun updateDerivedSelection(selectionChanged: Boolean = false) {
        contextMenuPositionEpoch++
        val previousRanges = selectionRanges
        val ordered = orderedSelectables()
        val normalized = normalizedSelection()
        selectionRanges = buildSelectionRanges(ordered, normalized)
        // Logical document text does not change when only visible geometry changes.
        if (selectionChanged || document == null) {
            selectionProjection = buildSelectionProjection(normalized, ordered)
        }
        hasSelection = selectionProjection.text != null
        updateHandlePositions()
        if (contextMenuToolbarRequested && systemContextMenu == null) {
            showLegacyTextToolbar()
        }
        val affected = LinkedHashSet<CjkSelectable>()
        affected += previousRanges.keys
        affected += selectionRanges.keys
        affected.forEach { selectable ->
            if (previousRanges[selectable] != selectionRanges[selectable]) {
                selectable.invalidateSelection()
            }
        }
    }

    private fun buildSelectionRanges(
        ordered: List<CjkSelectable>,
        normalized: Pair<CjkSelectionAnchor, CjkSelectionAnchor>?,
    ): Map<CjkSelectable, TextRange> {
        normalized ?: return emptyMap()
        if (normalized.first == normalized.second) return emptyMap()
        val ranges = LinkedHashMap<CjkSelectable, TextRange>()
        val startIndex = orderOf(normalized.first.key)
        val endIndex = orderOf(normalized.second.key)
        if (startIndex < 0 || endIndex < startIndex) return emptyMap()
        for (selectable in ordered) {
            val key = keyFor(selectable)
            val index = orderOf(key)
            if (index !in startIndex..endIndex) continue
            val start = if (key == normalized.first.key) normalized.first.offset else 0
            val end = if (key == normalized.second.key) normalized.second.offset else selectable.selectionText.length
            TextRange(start.coerceAtMost(end), end.coerceAtLeast(start))
                .takeUnless { it.isEmpty }
                ?.let { ranges[selectable] = it }
        }
        return ranges
    }

    private fun buildSelectionProjection(
        normalized: Pair<CjkSelectionAnchor, CjkSelectionAnchor>?,
        ordered: List<CjkSelectable>,
    ): CjkSelectionProjection {
        normalized ?: return CjkSelectionProjection()
        if (normalized.first == normalized.second) return CjkSelectionProjection()
        val logicalDocument = document
        if (logicalDocument == null) {
            val text = buildAnnotatedString {
                var first = true
                for (selectable in ordered) {
                    val range = selectionRanges[selectable] ?: continue
                    if (!first) append('\n')
                    first = false
                    append(selectable.selectionText, range.start, range.end)
                }
            }.takeIf { it.isNotEmpty() }
            return CjkSelectionProjection(text)
        }
        val startIndex = logicalDocument.indexByKey.getValue(normalized.first.key)
        val endIndex = logicalDocument.indexByKey.getValue(normalized.second.key)
        val ranges = mutableListOf<CjkSelectionDocumentRange>()
        val text = buildAnnotatedString {
            for (index in startIndex..endIndex) {
                val fragment = logicalDocument.fragments[index]
                val start = (if (index == startIndex) normalized.first.offset else 0)
                    .coerceIn(0, fragment.text.length)
                val end = (if (index == endIndex) normalized.second.offset else fragment.text.length)
                    .coerceIn(0, fragment.text.length)
                ranges += CjkSelectionDocumentRange(fragment.key, start, end, fragment.text)
                if (end > start) append(fragment.text, start, end)
                if (index < endIndex) append(fragment.separatorAfter)
            }
        }.takeIf { it.isNotEmpty() }
        return CjkSelectionProjection(text, if (text == null) null else ranges.toList())
    }

    private fun buildClipboardText(): AnnotatedString? {
        val normalized = normalizedSelection() ?: return null
        if (normalized.first == normalized.second) return null
        val logicalDocument = document
        if (logicalDocument == null) {
            val ordered = orderedSelectables()
            return buildAnnotatedString {
                var first = true
                for (selectable in ordered) {
                    val range = selectionRanges[selectable] ?: continue
                    if (!first) append('\n')
                    first = false
                    append(selectable.selectionTextForCopy(range))
                }
            }.takeIf { it.isNotEmpty() }
        }
        val startIndex = logicalDocument.indexByKey.getValue(normalized.first.key)
        val endIndex = logicalDocument.indexByKey.getValue(normalized.second.key)
        return buildAnnotatedString {
            for (index in startIndex..endIndex) {
                val fragment = logicalDocument.fragments[index]
                val start = if (index == startIndex) normalized.first.offset else 0
                val end = if (index == endIndex) normalized.second.offset else fragment.text.length
                if (end > start) {
                    if (start == 0 && end == fragment.text.length) {
                        append(fragment.textForCopy)
                    } else {
                        append(fragment.text, start, end)
                    }
                }
                if (index < endIndex) append(fragment.separatorAfter)
            }
        }.takeIf { it.isNotEmpty() }
    }

    private fun normalizedSelection(): Pair<CjkSelectionAnchor, CjkSelectionAnchor>? {
        val current = selection ?: return null
        return if (compareAnchors(current.anchor, current.extent) <= 0) {
            current.anchor to current.extent
        } else {
            current.extent to current.anchor
        }
    }

    private fun compareAnchors(left: CjkSelectionAnchor, right: CjkSelectionAnchor): Int {
        if (left.key == right.key) return left.offset.compareTo(right.offset)
        return orderOf(left.key).compareTo(orderOf(right.key))
    }

    private fun keyFor(selectable: CjkSelectable): Any =
        selectableScopes[selectable]?.ownerKey
            ?.takeIf { document?.indexByKey?.containsKey(it) == true }
            ?: selectable

    private fun isSelectableEligible(selectable: CjkSelectable): Boolean =
        document == null || selectableScopes[selectable]?.ownerKey?.let(document!!.indexByKey::containsKey) == true

    private fun orderOf(key: Any): Int = document?.indexByKey?.get(key)
        ?: selectables.indexOfFirst { it === key }.let { index ->
            if (index < 0) Int.MAX_VALUE else (document?.fragments?.size ?: 0) + index
        }

    private fun selectableForKey(key: Any): CjkSelectable? =
        selectables.firstOrNull { keyFor(it) == key && it.selectionCoordinates?.isAttached == true }

    private fun orderedSelectables(): List<CjkSelectable> {
        orderedSelectablesCache?.let { return it }
        val container = containerCoordinates ?: return selectables.toList().also {
            orderedSelectablesCache = it
        }
        return selectables.filter {
            isSelectableEligible(it) && it.selectionCoordinates?.isAttached == true
        }.sortedWith { a, b ->
            if (document != null) {
                return@sortedWith orderOf(keyFor(a)).compareTo(orderOf(keyFor(b)))
            }
            val aCoordinates = a.selectionCoordinates ?: return@sortedWith -1
            val bCoordinates = b.selectionCoordinates ?: return@sortedWith 1
            val aPosition = container.localPositionOf(aCoordinates, Offset.Zero)
            val bPosition = container.localPositionOf(bCoordinates, Offset.Zero)
            val verticalOverlap = minOf(
                aPosition.y + aCoordinates.size.height,
                bPosition.y + bCoordinates.size.height,
            ) - maxOf(aPosition.y, bPosition.y)
            if (verticalOverlap > minOf(aCoordinates.size.height, bCoordinates.size.height) / 2f) {
                aPosition.x.compareTo(bPosition.x)
            } else {
                aPosition.y.compareTo(bPosition.y)
            }
        }.also { orderedSelectablesCache = it }
    }

    private fun selectableAt(containerPosition: Offset): CjkSelectable? {
        val container = containerCoordinates ?: return null
        val ordered = orderedSelectables()
        if (ordered.isEmpty()) return null
        val containing = ordered.firstOrNull { selectable ->
            val coordinates = selectable.selectionCoordinates ?: return@firstOrNull false
            val topLeft = container.localPositionOf(coordinates, Offset.Zero)
            containerPosition.x >= topLeft.x && containerPosition.x <= topLeft.x + coordinates.size.width &&
                containerPosition.y >= topLeft.y && containerPosition.y <= topLeft.y + coordinates.size.height
        }
        if (containing != null) return containing
        return ordered.minBy { selectable ->
            val coordinates = selectable.selectionCoordinates ?: return@minBy Float.POSITIVE_INFINITY
            val topLeft = container.localPositionOf(coordinates, Offset.Zero)
            val right = topLeft.x + coordinates.size.width
            val bottom = topLeft.y + coordinates.size.height
            val dx = when {
                containerPosition.x < topLeft.x -> topLeft.x - containerPosition.x
                containerPosition.x > right -> containerPosition.x - right
                else -> 0f
            }
            val dy = when {
                containerPosition.y < topLeft.y -> topLeft.y - containerPosition.y
                containerPosition.y > bottom -> containerPosition.y - bottom
                else -> 0f
            }
            dx * dx + dy * dy
        }
    }

    private fun anchorAt(selectable: CjkSelectable, localPosition: Offset): CjkSelectionAnchor? =
        selectable.selectionOffsetAt(localPosition)?.let { CjkSelectionAnchor(keyFor(selectable), it) }

    private fun selectableAndLocalPositionAt(position: Offset): Pair<CjkSelectable, Offset>? {
        val container = containerCoordinates ?: return null
        val selectable = selectableAt(position) ?: return null
        val coordinates = selectable.selectionCoordinates ?: return null
        return selectable to coordinates.localPositionOf(container, position)
    }

    private fun anchorAtContainerPosition(position: Offset): CjkSelectionAnchor? {
        val container = containerCoordinates ?: return null
        val selectable = selectableAt(position) ?: return null
        val coordinates = selectable.selectionCoordinates ?: return null
        return anchorAt(selectable, coordinates.localPositionOf(container, position))
    }

    private fun updateHandlePositions() {
        val container = containerCoordinates
        val current = selection
        if (container == null || current == null || !hasSelection) {
            startHandlePosition = null
            endHandlePosition = null
            startHandleLineHeight = 0f
            endHandleLineHeight = 0f
            handlesCrossed = false
            return
        }
        val visibleBounds = container.visibleBoundsForSelection()
        fun position(anchor: CjkSelectionAnchor): Offset? {
            val selectable = selectableForKey(anchor.key) ?: return null
            val coordinates = selectable.selectionCoordinates ?: return null
            val local = selectable.selectionCursorPosition(anchor.offset) ?: return null
            return container.localPositionOf(coordinates, local)
        }
        startHandlePosition = position(current.anchor)?.takeIf {
            activeDragIsStart == true || visibleBounds.containsInclusive(it)
        }
        endHandlePosition = position(current.extent)?.takeIf {
            activeDragIsStart == false || visibleBounds.containsInclusive(it)
        }
        startHandleLineHeight = selectableForKey(current.anchor.key)
            ?.selectionLineHeight(current.anchor.offset) ?: 0f
        endHandleLineHeight = selectableForKey(current.extent.key)
            ?.selectionLineHeight(current.extent.offset) ?: 0f
        handlesCrossed = compareAnchors(current.anchor, current.extent) > 0
    }

    /** Adaptation of Foundation's Android magnifier clamp using Tiqian line geometry. */
    internal fun magnifierCenter(magnifierWidthPx: Int): Offset {
        if (!isTouchSelection || !currentDragPosition.isSpecified || !hasSelection) {
            return Offset.Unspecified
        }
        val current = selection ?: return Offset.Unspecified
        val anchor = if (activeDragIsStart == true) current.anchor else current.extent
        val container = containerCoordinates ?: return Offset.Unspecified
        val selectable = selectableForKey(anchor.key) ?: return Offset.Unspecified
        val selectableCoordinates = selectable.selectionCoordinates ?: return Offset.Unspecified
        if (!container.isAttached || !selectableCoordinates.isAttached) return Offset.Unspecified

        val localDragPosition = selectableCoordinates.localPositionOf(container, currentDragPosition)
        val lineRange = selectable.selectionLineRange(anchor.offset)
            ?: return Offset.Unspecified
        val lineStartX = selectable.selectionLineLeft(lineRange.start)
        val lineEndX = selectable.selectionLineRight((lineRange.end - 1).coerceAtLeast(lineRange.start))
        val constrainedX = localDragPosition.x.coerceIn(
            minOf(lineStartX, lineEndX),
            maxOf(lineStartX, lineEndX),
        )
        if (
            magnifierWidthPx > 0 &&
            abs(localDragPosition.x - constrainedX) > magnifierWidthPx / 2f
        ) {
            return Offset.Unspecified
        }
        val centerY = selectable.selectionLineCenterY(anchor.offset)
        return container.localPositionOf(
            selectableCoordinates,
            Offset(constrainedX, centerY),
        )
    }

    private fun showContextMenuToolbarIfTouch() {
        if (!isTouchSelection || !hasSelection) return
        contextMenuToolbarRequested = true
        systemContextMenu?.show() ?: showLegacyTextToolbar()
    }

    private fun hideContextMenuToolbar() {
        val requested = contextMenuToolbarRequested
        contextMenuToolbarRequested = false
        systemContextMenu?.hide()
        if (requested && systemContextMenu == null) textToolbar?.hide()
    }

    private fun showLegacyTextToolbar() {
        val rect = selectionContentRectInWindow() ?: return
        textToolbar?.showMenu(
            rect = rect,
            onCopyRequested = {
                if (copySelection()) clearSelection()
            },
            onSelectAllRequested = { selectAll() },
        )
    }

    internal fun selectionContentRectInRoot(): Rect? {
        // Android's platform ActionMode observes snapshot reads made while computing its content
        // rect. LayoutCoordinates themselves are not snapshot state, so this named epoch makes
        // descendant movement during verticalScroll invalidate the system toolbar position.
        contextMenuPositionEpoch
        val container = containerCoordinates?.takeIf { it.isAttached } ?: return null
        val visible = container.visibleBoundsForSelection()
        val selected = selectionRectInContainer(container) ?: return null
        val clipped = visible.intersect(selected)
        if (clipped.width < 0f || clipped.height < 0f) return null
        val topLeft = container.localToRoot(clipped.topLeft)
        val bottomRight = container.localToRoot(clipped.bottomRight)
        return Rect(topLeft, bottomRight).copy(
            bottom = bottomRight.y + selectionToolbarHandleClearancePx,
        )
    }

    internal fun contextMenuContainerCoordinates(): LayoutCoordinates? =
        containerCoordinates?.takeIf { it.isAttached }

    private fun selectionContentRectInWindow(): Rect? {
        val container = containerCoordinates?.takeIf { it.isAttached } ?: return null
        val visible = container.visibleBoundsForSelection()
        val selected = selectionRectInContainer(container) ?: return null
        val clipped = visible.intersect(selected)
        if (clipped.width < 0f || clipped.height < 0f) return null
        val topLeft = container.localToWindow(clipped.topLeft)
        val bottomRight = container.localToWindow(clipped.bottomRight)
        return Rect(topLeft, bottomRight).copy(
            bottom = bottomRight.y + selectionToolbarHandleClearancePx,
        )
    }

    private fun selectionRectInContainer(container: LayoutCoordinates): Rect? {
        var union: Rect? = null
        for (selectable in orderedSelectables()) {
            val range = rangeFor(selectable) ?: continue
            val coordinates = selectable.selectionCoordinates ?: continue
            if (!coordinates.isAttached) continue
            for (box in selectable.selectionBoxes(range)) {
                val topLeft = container.localPositionOf(coordinates, Offset(box.left, box.top))
                val bottomRight = container.localPositionOf(coordinates, Offset(box.right, box.bottom))
                val current = Rect(topLeft, bottomRight)
                union = union?.let {
                    Rect(
                        minOf(it.left, current.left),
                        minOf(it.top, current.top),
                        maxOf(it.right, current.right),
                        maxOf(it.bottom, current.bottom),
                    )
                } ?: current
            }
        }
        return union
    }

    internal fun contextTextAndSelection(): Pair<AnnotatedString, androidx.compose.ui.text.TextRange>? {
        contextMenuPositionEpoch
        val logicalDocument = document
        if (logicalDocument != null) {
            val normalized = normalizedSelection() ?: return null
            val startIndex = logicalDocument.indexByKey.getValue(normalized.first.key)
            val endIndex = logicalDocument.indexByKey.getValue(normalized.second.key)
            var selectionStart = -1
            var selectionEnd = -1
            val context = buildAnnotatedString {
                for (index in startIndex..endIndex) {
                    val fragment = logicalDocument.fragments[index]
                    val start = if (index == startIndex) normalized.first.offset else 0
                    val end = if (index == endIndex) normalized.second.offset else fragment.text.length
                    if (index == startIndex) {
                        append(fragment.text, 0, start)
                        selectionStart = length
                    }
                    append(fragment.text, start, end)
                    if (index < endIndex) append(fragment.separatorAfter) else selectionEnd = length
                    if (index == endIndex) append(fragment.text, end, fragment.text.length)
                }
            }
            if (selectionStart < 0 || selectionEnd < selectionStart) return null
            return context to androidx.compose.ui.text.TextRange(selectionStart, selectionEnd)
        }
        val ordered = orderedSelectables().filter(selectionRanges::containsKey)
        if (ordered.isEmpty()) return null
        var selectionStart = -1
        var selectionEnd = -1
        val context = buildAnnotatedString {
            ordered.forEachIndexed { index, selectable ->
                val range = selectionRanges.getValue(selectable)
                if (index == 0) {
                    selectionStart = range.start
                    append(selectable.selectionText, 0, range.start)
                }
                append(selectable.selectionText, range.start, range.end)
                if (index < ordered.lastIndex) {
                    append('\n')
                } else {
                    selectionEnd = length
                    append(selectable.selectionText, range.end, selectable.selectionText.length)
                }
            }
        }
        if (selectionStart < 0 || selectionEnd < selectionStart) return null
        return context to androidx.compose.ui.text.TextRange(selectionStart, selectionEnd)
    }

    internal fun isEntireContainerSelected(): Boolean {
        contextMenuPositionEpoch
        document?.let { logicalDocument ->
            val normalized = normalizedSelection() ?: return false
            val first = logicalDocument.fragments.firstOrNull() ?: return true
            val last = logicalDocument.fragments.last()
            return normalized.first.key == first.key && normalized.first.offset == 0 &&
                normalized.second.key == last.key && normalized.second.offset == last.text.length
        }
        val ordered = orderedSelectables()
        if (ordered.isEmpty()) return true
        return ordered.all { selectable ->
            val range = selectionRanges[selectable]
            selectable.selectionText.isEmpty() ||
                (range?.start == 0 && range.end == selectable.selectionText.length)
        }
    }

    internal fun copyFromContextMenu() {
        if (copySelection() && isTouchSelection) clearSelection()
    }

    internal fun selectWordAtContainerPositionIfOutsideSelection(position: Offset) {
        val container = containerCoordinates?.takeIf { it.isAttached } ?: return
        val selectable = selectableAt(position) ?: return
        val coordinates = selectable.selectionCoordinates?.takeIf { it.isAttached } ?: return
        val local = coordinates.localPositionOf(container, position)
        val selectedRange = selectionRanges[selectable]
        val insideSelection = selectedRange != null && selectable.selectionBoxes(selectedRange).any { box ->
            local.x in box.left..box.right && local.y in box.top..box.bottom
        }
        if (insideSelection) return
        val containerPosition = container.localPositionOf(coordinates, local)
        if (beginGestureSelectionAtContainerPosition(
                containerPosition,
                CjkSelectionAdjustment.Word,
                touch = false,
            )
        ) {
            finishSelection()
        }
    }

}
