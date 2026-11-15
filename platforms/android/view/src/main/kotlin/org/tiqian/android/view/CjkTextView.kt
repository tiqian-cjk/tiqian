package org.tiqian.android.view

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.AttributeSet
import android.util.TypedValue
import android.view.ActionMode
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewParent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import org.tiqian.android.rendering.AndroidParagraphMeasurementSession
import org.tiqian.android.rendering.AndroidParagraphMeasurer
import org.tiqian.android.rendering.AndroidParagraphRenderer
import org.tiqian.android.rendering.AndroidPrecomputedParagraph
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LayoutResultReplayIndex
import org.tiqian.core.Link
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.legalHangingPunctuationClipEdge
import org.tiqian.core.toReplayIndex
import org.tiqian.core.visiblePaintOverhang
import org.tiqian.shaping.android.AndroidTypefaceResolver
import org.tiqian.shaping.android.SystemAndroidTypefaceResolver
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

/**
 * First-class Android View frontend for one Tiqian paragraph.
 *
 * This View measures through the Tiqian engine and replays the returned [LayoutResult] on a native
 * Canvas. Android never performs a second text layout. Layout-affecting updates call
 * [requestLayout]; paint-only updates keep the existing result and only invalidate replay state.
 */
class CjkTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
    defStyleRes: Int = 0,
) : ViewGroup(context, attrs, defStyleAttr, defStyleRes) {
    internal data class LayoutSnapshot(
        val result: LayoutResult,
        val replayIndex: LayoutResultReplayIndex,
    )

    internal data class LinkHit(
        val target: String,
        val range: TextRange,
    )

    internal data class SelectionFragmentBindingChange(
        val contentChanged: Boolean,
        val textChanged: Boolean,
        val geometryChanged: Boolean,
        val identityChanged: Boolean,
    )

    private data class InlineChild(
        val id: Any,
        val spanIndex: Int,
        val view: View,
    )

    private var measurementSession: AndroidParagraphMeasurementSession? = null
    private var typefaceResolver: AndroidTypefaceResolver = SystemAndroidTypefaceResolver()
    private var measurer = AndroidParagraphMeasurer(typefaceResolver = typefaceResolver)

    /** Follows the attach/detach window; null whenever the View is detached. */
    private var renderer: AndroidParagraphRenderer? = null
    private var submittedPrecomputedLayout: AndroidPrecomputedParagraph? = null
    private var inlineChildren: List<InlineChild> = emptyList()
    private var clipLeft = 0f
    private var clipTop = 0f
    private var clipRight = 0f
    private var clipBottom = 0f
    private val overhangPaintBounds = RectF()
    private val overhangExcludedBounds = RectF()
    private val selectionController = CjkTextSelectionController(this)
    private val accessibilityDelegate = CjkTextAccessibilityDelegate(this)
    private var documentSelectionOwner: CjkTextSurface? = null
    private var localCustomSelectionActionModeCallback: ActionMode.Callback? = null
    private var overhangHost: CjkTextSurface? = null
    private var applyingSelectionFragmentBinding = false

    internal var layoutSnapshot: LayoutSnapshot? = null
        private set

    internal val selectionHandlesShowing: Boolean
        get() = selectionController.handlesShowing

    /** Immutable content revision displayed by this View. */
    var content: CjkTextContent = CjkTextContent(
        text = "",
        textStyle = TextStyle(
            fontSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                16f,
                resources.displayMetrics,
            ),
        ),
    )
        set(value) {
            if (field == value) return
            if (!applyingSelectionFragmentBinding) {
                documentSelectionOwner?.validateSelectableContent(this, value)
            }
            val layoutChanged = !field.hasSameLayoutContract(value, maxLines)
            val oldText = field.content.text
            val textChanged = oldText != value.content.text
            val publishAccessibilityRevision = !applyingSelectionFragmentBinding
            if (publishAccessibilityRevision) {
                accessibilityDelegate.onContentRevisionStarted(textChanged)
            }
            try {
                field = value
                submittedPrecomputedLayout = null
                syncInlineChildren()
                if (layoutChanged) {
                    clearLayout()
                    requestLayout()
                } else {
                    layoutSnapshot = layoutSnapshot?.let { snapshot ->
                        LayoutSnapshot(snapshot.result, snapshot.result.toReplayIndex(value.richTextSpans))
                    }
                    renderer?.invalidateGeometry()
                    invalidate()
                }
                if (!applyingSelectionFragmentBinding && (textChanged || layoutChanged)) {
                    selectionController.onTextOrGeometryChanged(textChanged = textChanged)
                }
                notifyOverhangHost()
            } finally {
                if (publishAccessibilityRevision) {
                    accessibilityDelegate.onContentRevisionFinished(textChanged)
                }
            }
        }

    /** Maximum emitted line count. */
    var maxLines: Int = Int.MAX_VALUE
        set(value) {
            require(value > 0) { "maxLines must be positive" }
            if (field == value) return
            field = value
            submittedPrecomputedLayout = null
            clearLayout()
            requestLayout()
            notifyOverhangHost()
        }

    /** Minimum line-height reservation. It never invents hidden layout lines. */
    var minLines: Int = 1
        set(value) {
            require(value > 0) { "minLines must be positive" }
            if (field == value) return
            field = value
            requestLayout()
            notifyOverhangHost()
        }

    var overflow: CjkTextOverflow = CjkTextOverflow.Clip
        set(value) {
            if (field == value) return
            field = value
            clipChildren = value == CjkTextOverflow.Clip
            invalidate()
            notifyOverhangHost()
        }

    var textIsSelectable: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            isLongClickable = value
            isFocusableInTouchMode = value
            documentSelectionOwner?.onSelectableEligibilityChanged(this)
            // Unregister first. A registered paragraph delegates clearSelection() to the logical
            // document, while disabling one paragraph must only remove that paragraph's geometry.
            // Unregistered descendants (for example an independent preview inside a surface) still
            // clear their standalone selection below.
            if (!value) selectionController.clearSelection()
            accessibilityDelegate.invalidateRoot()
        }

    /**
     * Stable logical fragment key used by an ancestor [CjkTextSurface].
     *
     * RecyclerView holders bind this key and the matching [content] atomically with
     * [bindSelectionFragment]. A container with a logical [CjkSelectionDocument] ignores
     * selectable children without a key instead of silently deriving identity from a recycled
     * View instance.
     */
    var selectionDocumentKey: Any? = null
        private set

    internal var selectionRetentionKey: Any? = null
        private set

    /**
     * Atomically binds the stable document identity and matching paragraph content.
     *
     * RecyclerView holders should use this instead of assigning [selectionDocumentKey] and
     * [content] separately. An attached [CjkTextSurface] validates the prospective key,
     * source text and duplicate-key constraint before it commits either value, then publishes one
     * new visible projection of the existing logical selection.
     */
    @JvmOverloads
    fun bindSelectionFragment(
        key: Any,
        content: CjkTextContent,
        retentionKey: Any = key,
    ) {
        val owner = documentSelectionOwner
        if (owner == null) {
            val change = try {
                applySelectionFragmentBinding(key, retentionKey, content)
            } catch (failure: Throwable) {
                cancelSelectionFragmentBinding()
                throw failure
            }
            completeStandaloneSelectionFragmentBinding(change)
        } else {
            owner.rebindSelectable(this, key, retentionKey, content)
        }
    }

    /** Removes this View from a logical document without changing its displayed paragraph. */
    fun unbindSelectionFragment() {
        val owner = documentSelectionOwner
        if (owner == null) {
            val identityChanged = clearSelectionFragmentBinding()
            completeStandaloneSelectionFragmentBinding(
                SelectionFragmentBindingChange(
                    contentChanged = false,
                    textChanged = false,
                    geometryChanged = false,
                    identityChanged = identityChanged,
                ),
            )
        } else {
            owner.unbindSelectable(this)
        }
    }

    internal fun applySelectionFragmentBinding(
        key: Any,
        retentionKey: Any,
        content: CjkTextContent,
    ): SelectionFragmentBindingChange {
        accessibilityDelegate.onDocumentBindingStarted()
        val identityChanged = selectionDocumentKey != key
        val contentChanged = this.content != content
        val textChanged = this.content.content.text != content.content.text
        val geometryChanged = !this.content.hasSameLayoutContract(content, maxLines)
        applyingSelectionFragmentBinding = true
        try {
            selectionDocumentKey = key
            selectionRetentionKey = retentionKey
            this.content = content
        } finally {
            applyingSelectionFragmentBinding = false
        }
        return SelectionFragmentBindingChange(
            contentChanged = contentChanged,
            textChanged = textChanged,
            geometryChanged = geometryChanged,
            identityChanged = identityChanged,
        )
    }

    internal fun clearSelectionFragmentBinding(): Boolean {
        accessibilityDelegate.onDocumentBindingStarted()
        val identityChanged = selectionDocumentKey != null
        selectionDocumentKey = null
        selectionRetentionKey = null
        return identityChanged
    }

    internal fun completeSelectionFragmentBinding(change: SelectionFragmentBindingChange) {
        accessibilityDelegate.onDocumentBindingFinished(
            contentChanged = change.contentChanged,
            textChanged = change.textChanged,
            identityChanged = change.identityChanged,
        )
    }

    private fun completeStandaloneSelectionFragmentBinding(
        change: SelectionFragmentBindingChange,
    ) {
        if (change.identityChanged) {
            selectionController.clearSelection()
        } else if (change.textChanged || change.geometryChanged) {
            selectionController.onTextOrGeometryChanged(textChanged = change.textChanged)
        }
        completeSelectionFragmentBinding(change)
    }

    internal fun cancelSelectionFragmentBinding() {
        accessibilityDelegate.onDocumentBindingCancelled()
    }

    /** Optional state-list override; null uses [CjkTextContent.textColor]. */
    var textColors: ColorStateList? = null
        set(value) {
            if (field == value) return
            field = value
            invalidate()
            notifyOverhangHost()
        }

    var selectionColor: Int = context.resolveCjkThemeColor(
        android.R.attr.textColorHighlight,
        0x6633B5E5,
    )
        set(value) {
            if (field == value) return
            field = value
            invalidate()
            notifyOverhangHost()
        }

    var clreqProfile: ClreqProfile = ClreqProfile.MainlandHorizontal
        set(value) {
            if (field == value) return
            field = value
            rebuildMeasurer()
            notifyOverhangHost()
        }

    var inlineViewAdapter: CjkInlineViewAdapter? = null
        set(value) {
            if (field === value) return
            recycleInlineChildren()
            field = value
            syncInlineChildren()
            requestLayout()
            notifyOverhangHost()
        }

    /**
     * Optional callback for extending the native-compatible floating selection ActionMode.
     *
     * Tiqian always supplies the read-only Copy, Share and Select All actions and forwards this
     * callback with the same lifecycle and menu ordering as [android.widget.TextView]. A callback
     * may add or remove menu items, handle clicks, or return false from creation to reject the
     * mode. Null keeps the default menu enabled. When this View is registered with a
     * [CjkTextSurface], that surface owns the document selection and this property delegates to
     * the surface's callback.
     */
    var customSelectionActionModeCallback: ActionMode.Callback?
        get() = if (selectionController.hasDocumentOwner) {
            selectionController.documentCustomSelectionActionModeCallback
        } else {
            localCustomSelectionActionModeCallback
        }
        set(value) {
            if (selectionController.hasDocumentOwner) {
                if (localCustomSelectionActionModeCallback === value &&
                    selectionController.documentCustomSelectionActionModeCallback === value
                ) {
                    return
                }
                // Preserve the value if this View later leaves the surface, while the attached
                // surface remains the sole source of truth for its document ActionMode.
                localCustomSelectionActionModeCallback = value
                selectionController.setDocumentCustomSelectionActionModeCallback(value)
            } else {
                if (localCustomSelectionActionModeCallback === value) return
                localCustomSelectionActionModeCallback = value
                selectionController.onCustomSelectionActionModeCallbackChanged()
            }
        }

    var onLinkClickListener: CjkLinkClickListener? = null
    var onTextLayout: ((LayoutResult) -> Unit)? = null

    val layoutResult: LayoutResult? get() = layoutSnapshot?.result
    val selection: TextRange? get() = selectionController.range
    val selectedText: String? get() = selectionController.selectedText()
    internal val selectionOwnerHasFocus: Boolean get() = selectionController.selectionOwnerHasFocus

    init {
        setWillNotDraw(false)
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isLongClickable = textIsSelectable
        isFocusableInTouchMode = textIsSelectable
        clipToPadding = false
        clipChildren = true
        accessibilityDelegate.install()
        readAttributes(attrs, defStyleAttr, defStyleRes)
    }

    /** Shares width-independent shaping and metrics across a document's View surfaces. */
    fun setMeasurementSession(session: AndroidParagraphMeasurementSession?) {
        if (measurementSession === session) return
        measurementSession = session
        typefaceResolver = session?.typefaceResolver ?: SystemAndroidTypefaceResolver()
        renderer?.close()
        renderer = if (isAttachedToWindow) AndroidParagraphRenderer(typefaceResolver) else null
        rebuildMeasurer()
    }

    /**
     * Submits a background-computed result. Its content/style contract is checked immediately and
     * its exact width/max-lines constraints are checked in [onMeasure]; a mismatch falls back to a
     * normal foreground measurement rather than displaying stale geometry.
     */
    fun submitPrecomputedLayout(precomputed: AndroidPrecomputedParagraph): Boolean {
        if (precomputed.profile != clreqProfile) return false
        val result = precomputed.result
        val expected = content.layoutInput(
            maxWidth = result.input.constraints.maxWidth,
            maxHeight = result.input.constraints.maxHeight,
            maxLines = maxLines,
        )
        if (expected != result.input) return false
        submittedPrecomputedLayout = precomputed
        requestLayout()
        // A same-size content revision can keep identical measured bounds. Explicit invalidation
        // prevents Android from replaying the old hardware display list after the new layout is
        // accepted.
        invalidate()
        return true
    }

    fun setSelection(start: Int, end: Int): Boolean =
        selectionController.setSelection(start, end, showToolbar = false)

    fun selectAll(): Boolean = selectionController.selectAll(showToolbar = false)

    fun clearSelection() = selectionController.clearSelection()

    fun copySelection(): Boolean = selectionController.copySelection()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)
        val horizontalPadding = paddingLeft + paddingRight
        val layoutWidth = when (widthMode) {
            MeasureSpec.EXACTLY, MeasureSpec.AT_MOST -> (widthSize - horizontalPadding).coerceAtLeast(1).toFloat()
            else -> DEFAULT_UNBOUNDED_WIDTH
        }
        val input = content.layoutInput(layoutWidth, Float.POSITIVE_INFINITY, maxLines)
        val snapshot = obtainLayout(input)

        val lineHeight = snapshot.result.debug.lineSpacingDecision?.resolvedHeight
            ?: snapshot.result.lines.firstOrNull()?.let { it.bottom - it.top }
            ?: content.textStyle.fontSize * EMPTY_PARAGRAPH_LINE_HEIGHT_FACTOR
        val desiredWidth = ceil(snapshot.result.size.width).toInt() + horizontalPadding
        val desiredHeight = ceil(max(snapshot.result.size.height, lineHeight * minLines)).toInt() +
            paddingTop + paddingBottom
        val measuredWidth = resolveSizeAndState(max(desiredWidth, suggestedMinimumWidth), widthMeasureSpec, 0)
        val measuredHeight = resolveSizeAndState(max(desiredHeight, suggestedMinimumHeight), heightMeasureSpec, 0)
        setMeasuredDimension(measuredWidth, measuredHeight)
        updateLegalPaintBounds(snapshot)
        measureInlineChildren()
        notifyOverhangHost()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        bindOverhangHost()
        val positions = layoutSnapshot?.replayIndex?.positionedClusters
            ?.associateBy { it.range }
            .orEmpty()
        for (child in inlineChildren) {
            val span = content.inlineObjects.getOrNull(child.spanIndex)
            val positioned = span?.let { positions[it.range] }
            if (span == null || positioned == null) {
                child.view.visibility = INVISIBLE
                continue
            }
            child.view.visibility = VISIBLE
            val childLeft = floor(toDrawX(positioned.drawX)).toInt()
            val childTop = floor(toDrawY(positioned.baseline - span.ascent)).toInt()
            child.view.layout(
                childLeft,
                childTop,
                childLeft + child.view.measuredWidth,
                childTop + child.view.measuredHeight,
            )
        }
        if (changed) selectionController.onHostLayoutChanged()
        notifyOverhangHost()
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        selectionController.onViewportSizeChanged()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val snapshot = layoutSnapshot ?: return
        val renderer = renderer ?: return
        val save = canvas.save()
        canvas.translate(paddingLeft.toFloat(), paddingTop.toFloat())
        if (overflow == CjkTextOverflow.Clip) {
            canvas.clipRect(clipLeft, clipTop, clipRight, clipBottom)
        }
        renderer.draw(
            canvas = canvas,
            result = snapshot.result,
            replayIndex = snapshot.replayIndex,
            color = currentTextColor(),
            colorSpans = content.colorSpans,
            // TextView draws its selection path only while it owns View focus (or is pressed).
            // The logical range may legitimately survive a programmatic, ActionMode-free focus
            // transfer, but it must not become a second visible selection in the same window.
            selectionBoxes = selectionController.boxes
                .takeIf { selectionController.shouldDrawSelection }
                .orEmpty(),
            selectionColor = selectionColor.takeIf {
                selectionController.shouldDrawSelection && selectionController.boxes.isNotEmpty()
            },
        )
        canvas.restoreToCount(save)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean =
        selectionController.onTouchEvent(event) || super.onTouchEvent(event)

    override fun onKeyShortcut(keyCode: Int, event: KeyEvent): Boolean {
        if (event.hasModifiers(KeyEvent.META_CTRL_ON)) {
            val handled = when (keyCode) {
                KeyEvent.KEYCODE_A -> textIsSelectable && selectAll()
                KeyEvent.KEYCODE_C -> copySelection()
                else -> false
            }
            if (handled) return true
        }
        return super.onKeyShortcut(keyCode, event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    override fun drawableStateChanged() {
        super.drawableStateChanged()
        if (textColors?.isStateful == true) {
            invalidate()
            notifyOverhangHost()
        }
    }

    override fun getBaseline(): Int =
        layoutSnapshot?.result?.lines?.firstOrNull()?.baseline?.let {
            ceil(it).toInt() + paddingTop
        } ?: super.getBaseline()

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        accessibilityDelegate.populateHostNode(info)
    }

    override fun onInitializeAccessibilityEvent(event: AccessibilityEvent) {
        super.onInitializeAccessibilityEvent(event)
        accessibilityDelegate.populateHostEvent(event)
    }

    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean =
        accessibilityDelegate.performHostAction(action, arguments) ||
            super.performAccessibilityAction(action, arguments)

    override fun addExtraDataToAccessibilityNodeInfo(
        info: AccessibilityNodeInfo,
        extraDataKey: String,
        arguments: Bundle?,
    ) {
        super.addExtraDataToAccessibilityNodeInfo(info, extraDataKey, arguments)
        accessibilityDelegate.addExtraData(info, extraDataKey, arguments)
    }

    override fun onDetachedFromWindow() {
        unbindOverhangHost()
        documentSelectionOwner?.let { owner ->
            // A callback configured through a document child belongs to the surface while
            // attached; retain the effective value for standalone use after detachment.
            if (selectionController.hasDocumentOwner) {
                localCustomSelectionActionModeCallback = owner.customSelectionActionModeCallback
            }
            owner.unregisterSelectable(this)
        }
        documentSelectionOwner = null
        selectionController.dispose()
        renderer?.close()
        renderer = null
        super.onDetachedFromWindow()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (renderer == null) renderer = AndroidParagraphRenderer(typefaceResolver)
        bindOverhangHost()
        findSelectionContainer()?.let { owner ->
            documentSelectionOwner = owner
            owner.registerSelectable(this)
            if (
                localCustomSelectionActionModeCallback != null &&
                owner.customSelectionActionModeCallback == null
            ) {
                // Recycler-style holders often configure the callback before attachment. Adopt
                // that existing value once, unless the surface already configured its owner.
                owner.customSelectionActionModeCallback = localCustomSelectionActionModeCallback
            }
        }
        selectionController.onHostVisibilityOrFocusChanged()
    }

    override fun onFocusChanged(
        gainFocus: Boolean,
        direction: Int,
        previouslyFocusedRect: Rect?,
    ) {
        selectionController.onHostFocusChanged(gainFocus)
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        selectionController.onHostVisibilityOrFocusChanged()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        selectionController.onHostVisibilityOrFocusChanged()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        selectionController.onHostVisibilityOrFocusChanged()
        notifyOverhangHost()
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        notifyOverhangHost()
    }

    override fun onRtlPropertiesChanged(layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        accessibilityDelegate.invalidateRoot()
    }

    internal fun toContentX(viewX: Float): Float = viewX - paddingLeft + scrollX
    internal fun toContentY(viewY: Float): Float = viewY - paddingTop + scrollY

    /** Content → canvas/child-layout coordinates. The framework applies the scroll translation. */
    internal fun toDrawX(contentX: Float): Float = contentX + paddingLeft
    internal fun toDrawY(contentY: Float): Float = contentY + paddingTop

    /** Content → scroll-adjusted visible position, for touch comparison and reported geometry. */
    internal fun toVisibleX(contentX: Float): Float = contentX + paddingLeft - scrollX
    internal fun toVisibleY(contentY: Float): Float = contentY + paddingTop - scrollY

    /** True when this View has an engine result that can be replayed by a host overlay pass. */
    internal fun canDrawLegalPaintOverhang(): Boolean =
        overflow == CjkTextOverflow.Visible &&
            layoutSnapshot != null &&
            renderer != null &&
            isAttachedToWindow &&
            hasLegalPaintOutsideViewport()

    private fun hasLegalPaintOutsideViewport(): Boolean {
        val viewportLeft = scrollX.toFloat()
        val viewportTop = scrollY.toFloat()
        val viewportRight = viewportLeft + width
        val viewportBottom = viewportTop + height
        return paddingLeft + clipLeft < viewportLeft ||
            paddingTop + clipTop < viewportTop ||
            paddingLeft + clipRight > viewportRight ||
            paddingTop + clipBottom > viewportBottom
    }

    /** Legal paint bounds in the same unscrolled local coordinates used by [onDraw]. */
    internal fun legalPaintBounds(outBounds: RectF) {
        outBounds.set(
            paddingLeft + clipLeft,
            paddingTop + clipTop,
            paddingLeft + clipRight,
            paddingTop + clipBottom,
        )
    }

    /** Replays the renderer's retained overhang recording; the registry owns ancestor transforms. */
    internal fun drawLegalPaintOverhang(canvas: Canvas) {
        val snapshot = layoutSnapshot ?: return
        val renderer = renderer ?: return
        val save = canvas.save()
        canvas.translate(paddingLeft.toFloat(), paddingTop.toFloat())
        overhangPaintBounds.set(clipLeft, clipTop, clipRight, clipBottom)
        overhangExcludedBounds.set(
            scrollX - paddingLeft.toFloat(),
            scrollY - paddingTop.toFloat(),
            scrollX + width - paddingLeft.toFloat(),
            scrollY + height - paddingTop.toFloat(),
        )
        renderer.drawPaintOverhang(
            canvas = canvas,
            result = snapshot.result,
            replayIndex = snapshot.replayIndex,
            color = currentTextColor(),
            colorSpans = content.colorSpans,
            paintBounds = overhangPaintBounds,
            excludedBounds = overhangExcludedBounds,
        )
        canvas.restoreToCount(save)
    }

    internal fun isSelectionHotspotVisible(viewX: Float, viewY: Float): Boolean {
        val visible = Rect()
        return getLocalVisibleRect(visible) &&
            viewX >= visible.left && viewX <= visible.right &&
            viewY >= visible.top && viewY <= visible.bottom
    }

    internal fun attachDocumentSelection(owner: CjkDocumentSelectionController) {
        selectionController.attachDocumentOwner(owner)
    }

    internal fun detachDocumentSelection(owner: CjkDocumentSelectionController) {
        selectionController.detachDocumentOwner(owner)
    }

    internal val currentSelectionBoxes: List<org.tiqian.core.Rect>
        get() = selectionController.boxes

    internal fun applyDocumentSelection(projection: CjkDocumentSelectionProjection?) {
        selectionController.applyDocumentSelection(projection)
    }

    private fun findSelectionContainer(): CjkTextSurface? {
        var current = parent
        while (current is View) {
            if (current is CjkTextSurface) return current
            current = current.parent
        }
        return null
    }

    internal fun selectionHandleBoundsOnScreen(
        handle: CjkSelectionHandle,
        outBounds: Rect,
    ): Boolean = selectionController.handleBoundsOnScreen(handle, outBounds)

    internal fun linkAt(viewX: Float, viewY: Float): LinkHit? {
        val snapshot = layoutSnapshot ?: return null
        val x = toContentX(viewX)
        val y = toContentY(viewY)
        return content.richTextSpans.asSequence()
            .mapNotNull { span ->
                val link = span.role as? Link ?: return@mapNotNull null
                val hit = snapshot.replayIndex.richTextSegments.any { segment ->
                    segment.span.range == span.range &&
                        x >= segment.left && x <= segment.right &&
                        y >= segment.top && y <= segment.bottom
                }
                if (hit) LinkHit(link.target, span.range) else null
            }
            .firstOrNull()
    }

    internal fun activateLink(link: LinkHit): Boolean {
        if (onLinkClickListener?.onLinkClick(this, link.target, link.range.start, link.range.end) == true) {
            return true
        }
        return runCatching {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(link.target)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }.isSuccess
    }

    internal fun onSelectionGeometryChanged() {
        accessibilityDelegate.onHostSelectionChanged()
        invalidate()
        notifyOverhangHost()
        selectionController.updateHandles()
        if (accessibilityDelegate.ownsSelectionTransition) return
        sendAccessibilityEventIfEnabled(AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED)
    }

    internal fun sendAccessibilityEventIfEnabled(eventType: Int) {
        if (canSendAccessibilityEvents) sendAccessibilityEvent(eventType)
    }

    internal fun sendAccessibilityContentChangedIfEnabled(changeTypes: Int) {
        if (!canSendAccessibilityEvents) return
        @Suppress("DEPRECATION")
        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
        onInitializeAccessibilityEvent(event)
        event.contentChangeTypes = changeTypes
        sendAccessibilityEventUnchecked(event)
    }

    internal fun links(): List<LinkHit> = content.richTextSpans.mapNotNull { span ->
        (span.role as? Link)?.let { LinkHit(it.target, span.range) }
    }

    private fun obtainLayout(input: LayoutInput): LayoutSnapshot {
        layoutSnapshot?.takeIf { it.result.input == input }?.let { return it }
        val result = submittedPrecomputedLayout?.result?.takeIf { it.input == input }
            ?: measurer.measure(input)
        if (submittedPrecomputedLayout != null && submittedPrecomputedLayout?.result !== result) {
            submittedPrecomputedLayout = null
        }
        return LayoutSnapshot(result, result.toReplayIndex(content.richTextSpans)).also { snapshot ->
            layoutSnapshot = snapshot
            renderer?.invalidateGeometry()
            selectionController.onTextOrGeometryChanged()
            accessibilityDelegate.invalidateRoot()
            onTextLayout?.invoke(result)
        }
    }

    private fun clearLayout() {
        layoutSnapshot = null
        renderer?.invalidateGeometry()
        if (!applyingSelectionFragmentBinding) accessibilityDelegate.invalidateRoot()
        // requestLayout alone does not guarantee a View's display list is re-recorded when the
        // replacement paragraph resolves to the same dimensions.
        invalidate()
    }

    private fun rebuildMeasurer() {
        measurer = AndroidParagraphMeasurer(clreqProfile, measurementSession, typefaceResolver)
        submittedPrecomputedLayout = null
        clearLayout()
        requestLayout()
    }

    private fun updateLegalPaintBounds(snapshot: LayoutSnapshot) {
        val viewportWidth = (measuredWidth - paddingLeft - paddingRight).coerceAtLeast(0).toFloat()
        val viewportHeight = (measuredHeight - paddingTop - paddingBottom).coerceAtLeast(0).toFloat()
        val positions = snapshot.replayIndex.positionedClusters
        val overhang = snapshot.result.visiblePaintOverhang(viewportWidth, viewportHeight, positions)
        val legalRight = snapshot.result.lines.maxOfOrNull { line ->
            val punctuation = line.legalHangingPunctuationClipEdge(viewportWidth)
            val hyphen = minOf(viewportWidth, line.indent + line.visualWidth) + line.hyphenAdvance
            maxOf(viewportWidth, punctuation, hyphen)
        } ?: viewportWidth
        val legalLeft = positions.minOfOrNull { it.drawX } ?: 0f
        clipLeft = minOf(0f, legalLeft, -overhang.left)
        clipTop = -overhang.top
        clipRight = maxOf(viewportWidth, legalRight, viewportWidth + overhang.right)
        clipBottom = viewportHeight + overhang.bottom
    }

    private fun measureInlineChildren() {
        inlineChildren.forEach { child ->
            val span = content.inlineObjects[child.spanIndex]
            child.view.measure(
                MeasureSpec.makeMeasureSpec(ceil(span.advance).toInt().coerceAtLeast(1), MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(
                    ceil(span.ascent + span.descent).toInt().coerceAtLeast(1),
                    MeasureSpec.EXACTLY,
                ),
            )
        }
    }

    /** Children are inline objects managed by [CjkInlineViewAdapter]; hosts may not add views. */
    override fun addView(child: View, index: Int, params: LayoutParams?) {
        check(mutatingInlineChildren) {
            "CjkTextView children are managed by CjkInlineViewAdapter; addView is not supported"
        }
        super.addView(child, index, params)
    }

    override fun removeView(view: View) {
        check(mutatingInlineChildren) {
            "CjkTextView children are managed by CjkInlineViewAdapter; removeView is not supported"
        }
        super.removeView(view)
    }

    private var mutatingInlineChildren = false

    private inline fun mutateInlineChildren(block: () -> Unit) {
        mutatingInlineChildren = true
        try {
            block()
        } finally {
            mutatingInlineChildren = false
        }
    }

    private fun syncInlineChildren() {
        val adapter = inlineViewAdapter ?: run {
            recycleInlineChildren()
            return
        }
        val oldById = inlineChildren.associateBy { it.id }.toMutableMap()
        val ids = HashSet<Any>()
        mutateInlineChildren {
            val updated = content.inlineObjects.mapIndexed { index, span ->
                val id = adapter.getItemId(content, span)
                require(ids.add(id)) { "CjkInlineViewAdapter item ids must be unique: $id" }
                val existing = oldById.remove(id)
                val child = existing?.view ?: adapter.createView(this, content, span).also(::addView)
                adapter.bindView(child, content, span)
                InlineChild(id, index, child)
            }
            oldById.values.forEach { child ->
                adapter.recycleView(child.view)
                removeView(child.view)
            }
            inlineChildren = updated
        }
    }

    private fun recycleInlineChildren() {
        val adapter = inlineViewAdapter
        mutateInlineChildren {
            inlineChildren.forEach { child ->
                adapter?.recycleView(child.view)
                removeView(child.view)
            }
        }
        inlineChildren = emptyList()
    }

    private fun currentTextColor(): Int =
        textColors?.getColorForState(drawableState, textColors?.defaultColor ?: content.textColor)
            ?: content.textColor

    internal val canSendAccessibilityEvents: Boolean
        get() = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
            .let { it as? AccessibilityManager }
            ?.isEnabled == true && isAttachedToWindow

    private fun bindOverhangHost() {
        val next = findOverhangHost()
        if (next === overhangHost) {
            next?.onPaintOverhangChanged(this)
            return
        }
        overhangHost?.unregisterPaintOverhang(this)
        overhangHost = next
        next?.registerPaintOverhang(this)
    }

    private fun unbindOverhangHost() {
        overhangHost?.unregisterPaintOverhang(this)
        overhangHost = null
    }

    private fun notifyOverhangHost() {
        overhangHost?.onPaintOverhangChanged(this)
    }

    private fun findOverhangHost(): CjkTextSurface? {
        var current: ViewParent? = parent
        while (current != null) {
            if (current is CjkTextSurface) return current
            current = current.parent
        }
        return null
    }

    private fun CjkTextContent.hasSameLayoutContract(
        other: CjkTextContent,
        maxLines: Int,
    ): Boolean = layoutInput(1f, Float.POSITIVE_INFINITY, maxLines) ==
        other.layoutInput(1f, Float.POSITIVE_INFINITY, maxLines)

    private companion object {
        const val DEFAULT_UNBOUNDED_WIDTH = 65_536f

        /** Last-resort minLines row height when the engine reports no lines and no spacing decision. */
        const val EMPTY_PARAGRAPH_LINE_HEIGHT_FACTOR = 1.5f
    }
}
