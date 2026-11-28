package org.tiqian.compose

import androidx.compose.runtime.MutableState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEvent
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.PointerInputModifierNode
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.unit.IntSize
import org.tiqian.core.LayoutResult
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.getOffsetForPosition

internal class CjkTextLinkElement(
    private val text: AnnotatedString,
    private val latestResult: Array<LayoutResult?>,
    private val uriHandler: UriHandler,
    private val hoveringLink: MutableState<Boolean>,
) : ModifierNodeElement<CjkTextLinkNode>() {
    override fun create() = CjkTextLinkNode(text, latestResult, uriHandler, hoveringLink)

    override fun update(node: CjkTextLinkNode) {
        node.update(text, latestResult, uriHandler, hoveringLink)
    }

    override fun equals(other: Any?): Boolean =
        other is CjkTextLinkElement && text == other.text &&
            latestResult === other.latestResult && uriHandler === other.uriHandler &&
            hoveringLink === other.hoveringLink

    override fun hashCode(): Int {
        var result = text.hashCode()
        result = 31 * result + latestResult.hashCode()
        result = 31 * result + uriHandler.hashCode()
        result = 31 * result + hoveringLink.hashCode()
        return result
    }
}

internal class CjkTextLinkNode(
    private var text: AnnotatedString,
    private var latestResult: Array<LayoutResult?>,
    private var uriHandler: UriHandler,
    private var hoveringLink: MutableState<Boolean>,
) : Modifier.Node(), PointerInputModifierNode {
    private var pressedLink: LinkHit? = null
    private var pressedPointerId: PointerId? = null

    fun update(
        text: AnnotatedString,
        latestResult: Array<LayoutResult?>,
        uriHandler: UriHandler,
        hoveringLink: MutableState<Boolean>,
    ) {
        if (text != this.text) {
            pressedLink = null
            this.hoveringLink.value = false
        }
        this.text = text
        this.latestResult = latestResult
        this.uriHandler = uriHandler
        this.hoveringLink = hoveringLink
    }

    override fun onPointerEvent(pointerEvent: PointerEvent, pass: PointerEventPass, bounds: IntSize) {
        val isPointerMove = pointerEvent.type == PointerEventType.Enter ||
            pointerEvent.type == PointerEventType.Move
        if (pass == PointerEventPass.Final && isPointerMove) {
            val pointerId = pressedPointerId ?: return
            if (pointerEvent.changes.firstOrNull { it.id == pointerId }?.isConsumed == true) {
                clearPressedLink()
            }
            return
        }
        if (pass != PointerEventPass.Main) return
        when (pointerEvent.type) {
            PointerEventType.Press -> {
                val change = pointerEvent.changes.firstOrNull { it.pressed && !it.previousPressed } ?: return
                if (change.isConsumed) return
                pressedLink = latestResult[0]?.let { linkHitAt(text, it, change.position) }
                if (pressedLink != null) {
                    pressedPointerId = change.id
                }
            }

            PointerEventType.Enter,
            PointerEventType.Move,
            -> {
                val hoverChange = pointerEvent.changes.firstOrNull()
                hoveringLink.value = hoverChange != null && latestResult[0]?.let { result ->
                    linkHitAt(text, result, hoverChange.position)
                } != null
                val pointerId = pressedPointerId ?: return
                val change = pointerEvent.changes.firstOrNull { it.id == pointerId } ?: return
                val currentHit = latestResult[0]?.let { linkHitAt(text, it, change.position) }
                if (change.isConsumed || currentHit != pressedLink) clearPressedLink()
            }

            PointerEventType.Release -> {
                val downHit = pressedLink ?: return
                val pointerId = pressedPointerId ?: return
                val change = pointerEvent.changes.firstOrNull { it.id == pointerId } ?: return
                clearPressedLink()
                if (change.isConsumed) return
                val upHit = latestResult[0]?.let { linkHitAt(text, it, change.position) }
                if (upHit != downHit) return
                change.consume()
                val link = upHit.link
                when {
                    link?.linkInteractionListener != null ->
                        link.linkInteractionListener?.onClick(link)
                    link is LinkAnnotation.Url -> uriHandler.openUri(link.url)
                    upHit.legacyUrl != null -> uriHandler.openUri(upHit.legacyUrl)
                }
            }

            PointerEventType.Exit -> {
                hoveringLink.value = false
                clearPressedLink()
            }
        }
    }

    override fun onCancelPointerInput() {
        hoveringLink.value = false
        clearPressedLink()
    }

    override fun onDetach() {
        hoveringLink.value = false
        super.onDetach()
    }

    private fun clearPressedLink() {
        pressedLink = null
        pressedPointerId = null
    }
}

private data class LinkHit(
    val link: LinkAnnotation? = null,
    val legacyUrl: String? = null,
    val start: Int,
    val end: Int,
)

@OptIn(ExperimentalTextApi::class)
@Suppress("DEPRECATION")
private fun linkHitAt(text: AnnotatedString, result: LayoutResult, position: Offset): LinkHit? {
    if (text.length == 0) return null
    val offset = result.getOffsetForPosition(position.x, position.y)
    // The nearest caret can be after the linked glyph; inspect both sides before checking its boxes.
    val queryStart = (offset - 1).coerceIn(0, text.length - 1)
    val queryEnd = (offset + 1).coerceIn(queryStart + 1, text.length)
    val composeLink = text.getLinkAnnotations(queryStart, queryEnd)
        .firstOrNull { range ->
            result.getBoundingBoxes(range.start, range.end).any { box ->
                position.x >= box.left && position.x <= box.right &&
                    position.y >= box.top && position.y <= box.bottom
            }
        }
        ?.let { LinkHit(link = it.item, start = it.start, end = it.end) }
    if (composeLink != null) return composeLink
    return text.getUrlAnnotations(queryStart, queryEnd)
        .firstOrNull { range ->
            result.getBoundingBoxes(range.start, range.end).any { box ->
                position.x >= box.left && position.x <= box.right &&
                    position.y >= box.top && position.y <= box.bottom
            }
        }
        ?.let { LinkHit(legacyUrl = it.item.url, start = it.start, end = it.end) }
}
