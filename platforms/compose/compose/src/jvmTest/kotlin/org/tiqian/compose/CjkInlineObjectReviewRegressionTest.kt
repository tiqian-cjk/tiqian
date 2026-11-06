@file:Suppress("DEPRECATION")
@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class, androidx.compose.ui.text.ExperimentalTextApi::class)

package org.tiqian.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getAllSemanticsNodes
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.VerbatimTtsAnnotation
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
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
        val link = LinkAnnotation.Clickable("review-link") {}
        val tts = VerbatimTtsAnnotation("ab")
        val text =
            AnnotatedString
                .Builder(marked("a\uFFFCb"))
                .apply {
                    addLink(link, 0, 3)
                    addTtsAnnotation(tts, 0, 3)
                }.toAnnotatedString()
        withText(text) { scene, _, _ ->
            val visible = textNode(scene).config[SemanticsProperties.Text].single()
            assertEquals("ab", visible.text)
            assertEquals(
                listOf(AnnotatedString.Range<LinkAnnotation>(link, 0, 2)) to
                    listOf(AnnotatedString.Range<androidx.compose.ui.text.TtsAnnotation>(tts, 0, 2)),
                visible.getLinkAnnotations(0, visible.length) to visible.getTtsAnnotations(0, visible.length),
            )
            assertTrue(visible.getStringAnnotations(0, visible.length).isEmpty(), "public text must not contain private offset records")
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

    private fun textNode(scene: ImageComposeScene) =
        scene.semanticsOwners
            .flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single {
                it.config.getOrNull(SemanticsProperties.TestTag) == "review-text" && SemanticsActions.SetSelection in it.config
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
