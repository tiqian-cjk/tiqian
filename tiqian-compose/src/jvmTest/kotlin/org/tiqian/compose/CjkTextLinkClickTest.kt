package org.tiqian.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.LayoutResult
import org.tiqian.core.getBoundingBoxes
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `CjkTextLinkClicks`: taps are hit-tested against Tiqian's own geometry and
 * dispatched to the link's [LinkInteractionListener] (Compose Text parity).
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkTextLinkClickTest {

    @Test
    fun tapOnLinkFiresListenerAndTapOutsideDoesNot() {
        var clicks = 0
        val listener = LinkInteractionListener { clicks++ }
        val text = buildAnnotatedString {
            append("前文说明")
            withLink(LinkAnnotation.Clickable("tag", linkInteractionListener = listener)) {
                append("这是链接")
            }
            append("后文继续,补齐足够长度。")
        }
        var layout: LayoutResult? = null

        ImageComposeScene(width = 480, height = 240) {
            Box(Modifier.fillMaxSize()) {
                CjkText(
                    text = text,
                    modifier = Modifier.width(460.dp),
                    style = TextStyle(fontSize = 20.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene ->
            scene.render()
            val result = layout ?: error("onTextLayout not called")
            val linkStart = "前文说明".length
            val box = result.getBoundingBoxes(linkStart, linkStart + "这是链接".length).first()
            val inside = Offset((box.left + box.right) / 2f, (box.top + box.bottom) / 2f)

            scene.sendPointerEvent(PointerEventType.Press, inside)
            scene.sendPointerEvent(PointerEventType.Release, inside)
            assertEquals(1, clicks, "tap inside the link must fire the listener")

            val outside = Offset((box.left + box.right) / 2f, box.bottom + 80f)
            scene.sendPointerEvent(PointerEventType.Press, outside)
            scene.sendPointerEvent(PointerEventType.Release, outside)
            assertEquals(1, clicks, "tap outside the link must not fire")
        }
    }

    @Test
    fun tapOnUrlLinkUsesLocalUriHandler() {
        var opened: String? = null
        val url = "https://example.com/path"
        val text = buildAnnotatedString {
            append("前文")
            withLink(LinkAnnotation.Url(url)) {
                append("链接")
            }
            append("后文。")
        }
        var layout: LayoutResult? = null

        ImageComposeScene(width = 360, height = 180) {
            CompositionLocalProvider(
                LocalUriHandler provides object : UriHandler {
                    override fun openUri(uri: String) {
                        opened = uri
                    }
                },
            ) {
                CjkText(
                    text = text,
                    modifier = Modifier.width(340.dp),
                    style = TextStyle(fontSize = 20.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene ->
            scene.render()
            val result = layout ?: error("onTextLayout not called")
            val box = result.getBoundingBoxes("前文".length, "前文链接".length).first()
            tap(scene, box.center)

            assertEquals(url, opened)
        }
    }

    @Test
    fun linkAddedWithoutTextChangeCanReuseCurrentLayoutForHitTesting() {
        var clicks = 0
        val listener = LinkInteractionListener { clicks++ }
        val plain = AnnotatedString("链接正文后续。")
        val linked = buildAnnotatedString {
            withLink(LinkAnnotation.Clickable("tag", linkInteractionListener = listener)) {
                append("链接")
            }
            append("正文后续。")
        }
        val enabled = mutableStateOf(false)
        var layout: LayoutResult? = null

        ImageComposeScene(width = 360, height = 180) {
            CjkText(
                text = if (enabled.value) linked else plain,
                modifier = Modifier.width(340.dp),
                style = TextStyle(fontSize = 20.sp),
                onTextLayout = { layout = it },
            )
        }.use { scene ->
            scene.render()
            val result = layout ?: error("onTextLayout not called")
            val box = result.getBoundingBoxes(0, "链接".length).first()

            enabled.value = true
            scene.render()
            tap(scene, box.center)

            assertEquals(1, clicks, "link annotations added without text changes must still hit-test")
        }
    }

    private fun tap(scene: ImageComposeScene, position: Offset) {
        scene.sendPointerEvent(PointerEventType.Press, position)
        scene.sendPointerEvent(PointerEventType.Release, position)
    }

    private val org.tiqian.core.Rect.center: Offset
        get() = Offset((left + right) / 2f, (top + bottom) / 2f)
}
