@file:Suppress("DEPRECATION")
@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class, androidx.compose.ui.text.ExperimentalTextApi::class)

package org.tiqian.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerButton
import androidx.compose.ui.input.pointer.PointerButtons
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getAllSemanticsNodes
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.VerbatimTtsAnnotation
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.getCursorRect
import org.tiqian.core.ic
import org.tiqian.core.positionedClusters
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Review cases for the public render-only marker and its source-text selection contract. */
class CjkInlineObjectReviewRegressionTest {
    @Test
    fun modeledRenderOnlySlotPassesCompatibilityWithoutAllowingUnknownTags() {
        val text = marked("a\uFFFCb")
        val modeled = text.cjkTextCompatibility(inlineObjects = listOf(objectAt(1)))
        assertTrue(modeled.canPreserveAllKnownSemantics, modeled.issues.toString())
        assertTrue(CjkTextCapabilityIssue.InlinePlaceholders in text.cjkTextCompatibility().issues)
        val unknown =
            AnnotatedString
                .Builder(text)
                .apply {
                    addStringAnnotation("host:unhandled", "value", 0, 1)
                }.toAnnotatedString()
        assertTrue(
            CjkTextCapabilityIssue.UnknownStringAnnotations in unknown.cjkTextCompatibility(inlineObjects = listOf(objectAt(1))).issues,
        )
    }

    @Test
    fun textSemanticsPreserveOneCrossSlotLinkAndTtsRange() {
        val link = LinkAnnotation.Clickable("review-link", styles = TextLinkStyles(style = SpanStyle(color = Color.Red))) {}
        val tts = VerbatimTtsAnnotation("ab")
        val text =
            AnnotatedString
                .Builder(marked("a\uFFFCb"))
                .apply {
                    addLink(link, 0, 3)
                    addTtsAnnotation(tts, 0, 3)
                }.toAnnotatedString()
        withText(text) { scene, state, _ ->
            val visible = textNode(scene).config[SemanticsProperties.Text].single()
            val expected = buildAnnotatedString {
                append("ab")
                addLink(link, 0, 2)
                addTtsAnnotation(tts, 0, 2)
            }
            assertEquals(expected, visible, "public text must preserve authored annotations without adding drawing styles")
            assertTrue(state.selectAll())
            assertEquals(expected, state.selectedText)
        }
    }

    @Test
    fun selectedTextCanBeRenderedAndCopiedAgainWithoutPrivateOffsets() {
        val clipboard = RecordingClipboard()
        var first: CjkSelectionState? = null
        var second: CjkSelectionState? = null
        var reusedLayout: LayoutResult? = null
        val reused = mutableStateOf<AnnotatedString?>(null)
        ImageComposeScene(width = 240, height = 160) {
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                Column {
                    val state = rememberCjkSelectionState()
                    first = state
                    CjkSelectionContainer(state = state) {
                        CjkText(marked("a\uFFFCb"), inlineObjects = listOf(objectAt(1)), textStyle = style())
                    }
                    reused.value?.let { text ->
                        val other = rememberCjkSelectionState()
                        second = other
                        CjkSelectionContainer(state = other) {
                            CjkText(text, textStyle = style(), onTextLayout = { reusedLayout = it })
                        }
                    }
                }
            }
        }.use { scene ->
            scene.render()
            assertTrue(assertNotNull(first).selectAll())
            val selected = assertNotNull(first?.selectedText)
            assertEquals("ab", selected.text)
            reused.value = selected
            scene.render()
            assertTrue(assertNotNull(second).selectAll())
            assertTrue(assertNotNull(second).copySelection())
            assertEquals("ab", clipboard.value?.text)
            assertTrue(selected.getStringAnnotations(0, selected.length).isEmpty(), "private offsets must not escape selectedText")
            scene.render()
            assertEquals(
                assertNotNull(reusedLayout).positionedClusters().last().right,
                assertNotNull(second?.endHandlePosition).x,
                0.01f,
                "the reused selection must include the final source character",
            )
        }
    }

    @Test
    fun semanticsSelectionKeepsGraphemesJoinedAfterSlotRemoval() {
        withText(marked("a\uFFFC\u0301")) { scene, state, _ ->
            assertTrue(assertNotNull(textNode(scene).config[SemanticsActions.SetSelection].action).invoke(1, 2, false))
            scene.render()
            assertEquals("a\u0301", state.selectedText?.text)
            assertEquals(
                androidx.compose.ui.text
                    .TextRange(0, 2),
                textNode(scene).config[SemanticsProperties.TextSelectionRange],
            )
            assertTrue(assertNotNull(textNode(scene).config[SemanticsActions.SetSelection].action).invoke(2, 1, false))
            scene.render()
            assertEquals("a\u0301", state.selectedText?.text)
            assertTrue(state.handlesCrossed)
        }
    }

    @Test
    fun terminalHandleStopsBeforeUnselectedSlotOnEitherLineAndWhenCrossed() {
        for (width in listOf(192, 36)) {
            withText(marked("ab\uFFFC", slot = 2), width = width, slot = 2) { scene, state, result ->
                val layout = result()
                val lastText = layout.positionedClusters().last { it.range.end == 2 }
                val line = layout.lines[lastText.lineIndex]
                if (width == 36) assertTrue(layout.lines.size > 1, "the trailing object must occupy the next line")
                assertTrue(state.selectAll())
                scene.render()
                val end = assertNotNull(state.endHandlePosition)
                assertEquals(lastText.right, end.x, 0.01f, "width=$width terminal x")
                assertEquals(line.bottom, end.y, 0.01f, "width=$width terminal line")
                assertEquals(line.bottom - line.top, state.endHandleLineHeight, 0.01f)
                assertTrue(assertNotNull(textNode(scene).config[SemanticsActions.SetSelection].action).invoke(2, 0, false))
                scene.render()
                assertTrue(state.handlesCrossed)
                val crossedEnd = assertNotNull(state.startHandlePosition)
                assertEquals(lastText.right, crossedEnd.x, 0.01f, "crossed width=$width terminal x")
                assertEquals(line.bottom, crossedEnd.y, 0.01f, "crossed width=$width terminal line")
            }
        }
    }

    @Test
    fun emptyDocumentEndpointUsesTheCursorBeforeUnselectedTextInEitherDirection() {
        for (slot in listOf(0, 1)) {
            val document = CjkSelectionDocument(listOf(
                CjkSelectionDocumentFragment("a", AnnotatedString("a"), separatorAfter = ""),
                CjkSelectionDocumentFragment("b", AnnotatedString("b"), separatorAfter = ""),
            ))
            var state: CjkSelectionState? = null
            var first: LayoutResult? = null
            var second: LayoutResult? = null
            ImageComposeScene(width = 360, height = 220) {
                val selection = rememberCjkSelectionState()
                state = selection
                CjkSelectionContainer(state = selection, document = document) {
                    Column {
                        CjkSelectionScope("a") {
                            CjkText(document.fragments[0].text, modifier = Modifier.width(340.dp).testTag("first-text"),
                                textStyle = style(), paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic), onTextLayout = { first = it })
                        }
                        CjkSelectionScope("b") {
                            CjkText(marked(if (slot == 0) "\uFFFCb" else "b\uFFFC", slot),
                                modifier = Modifier.width(24.dp).testTag("second-text"), textStyle = style(),
                                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic), inlineObjects = listOf(objectAt(slot)),
                                onTextLayout = { second = it })
                        }
                    }
                }
            }.use { scene ->
                scene.render()
                val firstLayout = assertNotNull(first)
                val secondLayout = assertNotNull(second)
                val a = firstLayout.positionedClusters().single { it.range == TextRange(0, 1) }
                val b = secondLayout.positionedClusters().single { it.range == TextRange(1 - slot, 2 - slot) }
                val firstBounds = textNode(scene, "first-text").boundsInRoot
                val secondBounds = textNode(scene, "second-text").boundsInRoot
                val aLine = firstLayout.lines[a.lineIndex]
                val bLine = secondLayout.lines[b.lineIndex]
                val aPoint = Offset(firstBounds.left + a.left + (a.right - a.left) * 0.1f,
                    firstBounds.top + (aLine.top + aLine.bottom) / 2f)
                val bPoint = Offset(secondBounds.left + b.left + (b.right - b.left) * 0.1f,
                    secondBounds.top + (bLine.top + bLine.bottom) / 2f)
                val expectedCursor = secondLayout.getCursorRect(0)
                for (crossed in listOf(false, true)) {
                    val selection = assertNotNull(state)
                    selection.clearSelection()
                    val pressed = PointerButtons(isPrimaryPressed = true)
                    val start = if (crossed) bPoint else aPoint
                    val end = if (crossed) aPoint else bPoint
                    val time = if (crossed) 5_000L else 4_000L
                    scene.sendPointerEvent(PointerEventType.Press, start, timeMillis = time,
                        buttons = pressed, button = PointerButton.Primary)
                    scene.sendPointerEvent(PointerEventType.Move, end, timeMillis = time + 50, buttons = pressed)
                    scene.sendPointerEvent(PointerEventType.Release, end, timeMillis = time + 100,
                        buttons = PointerButtons(), button = PointerButton.Primary)
                    scene.render()
                    assertEquals("a", selection.selectedText?.text)
                    assertEquals(listOf(
                        CjkSelectionDocumentRange("a", 0, 1, document.fragments[0].text),
                        CjkSelectionDocumentRange("b", 0, 0, document.fragments[1].text),
                    ), selection.selectedRanges)
                    assertEquals(crossed, selection.handlesCrossed)
                    val handle = assertNotNull(if (crossed) selection.startHandlePosition else selection.endHandlePosition)
                    assertEquals(secondBounds.left + expectedCursor.left, handle.x, 0.01f, "slot=$slot crossed=$crossed x")
                    assertEquals(secondBounds.top + expectedCursor.bottom, handle.y, 0.01f, "slot=$slot crossed=$crossed line")
                    val endpointLine = secondLayout.lines.first()
                    assertEquals(endpointLine.bottom - endpointLine.top,
                        if (crossed) selection.startHandleLineHeight else selection.endHandleLineHeight, 0.01f)
                }
            }
        }
    }

    @Test
    fun copyingCompleteRubyAcrossSlotKeepsReadingAndExcludesSlot() {
        val clipboard = RecordingClipboard()
        val text =
            buildAnnotatedString {
                ruby("提\uFFFC椠", "tíqiàn")
                addCjkRenderOnlyInlineObject(1, 2)
            }
        withText(text, clipboard = clipboard) { scene, state, result ->
            assertTrue(
                result().debug.rubyDecisions.any {
                    it.baseRange == TextRange(0, 3)
                },
                "the real engine must preserve the complete annotated base",
            )
            assertTrue(state.selectAll())
            scene.render()
            assertTrue(state.copySelection())
            assertEquals("提椠（tíqiàn）", clipboard.value?.text)
            assertTrue(assertNotNull(textNode(scene).config[SemanticsActions.SetSelection].action).invoke(0, 1, false))
            assertTrue(state.copySelection())
            assertEquals("提", clipboard.value?.text, "partial bases must not copy detached readings")
        }
    }

    private fun marked(
        source: String,
        slot: Int = 1,
    ): AnnotatedString =
        AnnotatedString
            .Builder(source)
            .apply {
                addCjkRenderOnlyInlineObject(slot, slot + 1)
            }.toAnnotatedString()

    private fun objectAt(offset: Int) =
        CjkInlineObject(
            range =
                androidx.compose.ui.text
                    .TextRange(offset, offset + 1),
            advance = 24.dp,
            ascent = 18.dp,
            descent = 4.dp,
        ) {}

    private fun style() = CjkTextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif)

    private fun textNode(scene: ImageComposeScene, tag: String = "review-text") =
        scene.semanticsOwners
            .flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single {
                it.config.getOrNull(SemanticsProperties.TestTag) == tag && SemanticsActions.SetSelection in it.config
            }

    private fun withText(
        text: AnnotatedString,
        width: Int = 192,
        slot: Int = 1,
        clipboard: RecordingClipboard = RecordingClipboard(),
        verify: (ImageComposeScene, CjkSelectionState, () -> LayoutResult) -> Unit,
    ) {
        var state: CjkSelectionState? = null
        var layout: LayoutResult? = null
        ImageComposeScene(width = width, height = 180) {
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                val selection = rememberCjkSelectionState()
                state = selection
                CjkSelectionContainer(state = selection) {
                    CjkText(
                        text,
                        modifier = Modifier.testTag("review-text"),
                        textStyle = style(),
                        paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                        inlineObjects = listOf(objectAt(slot)),
                        onTextLayout = { layout = it },
                    )
                }
            }
        }.use { scene ->
            scene.render()
            verify(scene, assertNotNull(state)) { assertNotNull(layout) }
        }
    }

    private class RecordingClipboard : ClipboardManager {
        var value: AnnotatedString? = null

        override fun getText(): AnnotatedString? = value

        override fun setText(annotatedString: AnnotatedString) {
            value = annotatedString
        }
    }
}
