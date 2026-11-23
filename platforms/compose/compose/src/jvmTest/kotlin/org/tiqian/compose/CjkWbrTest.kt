@file:Suppress("DEPRECATION")

package org.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.width
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getAllSemanticsNodes
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange as ComposeTextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.LayoutConstraints
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `wbr()` appends a tagged U+200B: layout keeps the zero-width break opportunity, while clipboard
 * text and accessibility text leave the tagged character out. An untagged U+200B stays content.
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkWbrTest {

    // Offsets: 0 '#', 1 '甲', 2 '#', 3 wbr, 4 '#', 5 '乙', 6 '#', 7 plain U+200B, 8 '丙'.
    private val topics = buildAnnotatedString {
        append("#甲#")
        wbr()
        append("#乙#")
        append("\u200B")
        append("丙")
    }
    private val topicsWithoutWbr = "#甲##乙#\u200B丙"

    @Test
    fun wbrAppendsTaggedZeroWidthSpace() {
        assertEquals("#甲#\u200B#乙#\u200B丙", topics.text)
        assertEquals(listOf(3), topics.cjkWbrOffsets().toList())
        assertEquals(topicsWithoutWbr, topics.withoutCjkWbr().text)
        assertEquals("甲##乙", topics.withoutCjkWbr(1, 6).text)
        assertTrue(topics.cjkSourceBoundaries().containsAll(listOf(3, 4)))
        assertTrue(topics.cjkTextCompatibility().canPreserveAllKnownSemantics)
    }

    @Test
    fun wbrKeepsTheZeroWidthBreakOpportunity() {
        val measurer = ParagraphMeasurer(ExplainableStubParagraphLayoutEngine(lineBreaker = LookaheadLineBreaker()))
        fun layout(text: AnnotatedString, maxWidth: Float) = measurer.measure(
            text = text,
            constraints = LayoutConstraints(maxWidth = maxWidth),
            density = Density(1f),
            textStyle = CjkTextStyle(fontSize = 16.sp),
        )
        val taggedText = buildAnnotatedString { append("abcdefgh"); wbr(); append("ijklmnop") }
        // One pixel narrower than the unbroken line, whatever the platform font: the line must
        // break, and U+200B is the only break opportunity inside the Latin text.
        val maxWidth = layout(taggedText, maxWidth = 10_000f).lines.single().naturalWidth - 1f
        fun lineStarts(text: AnnotatedString): List<Int> = layout(text, maxWidth).lines.map { it.range.start }

        val tagged = lineStarts(taggedText)
        val plain = lineStarts(AnnotatedString("abcdefgh\u200Bijklmnop"))
        val none = lineStarts(AnnotatedString("abcdefghijklmnop"))

        assertEquals(listOf(0, 9), tagged)
        assertEquals(plain, tagged)
        assertTrue(9 !in none && 8 !in none, "without U+200B the Latin word has no break at offset 8")
    }

    @Test
    fun removingWbrKeepsCoveringSpansAndLinksWhole() {
        val text = buildAnnotatedString {
            withLink(LinkAnnotation.Url("https://example.com/a/b")) {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                    emphasis { append("example.com/a/"); wbr(); append("b") }
                }
            }
        }

        val projected = text.withoutCjkWbr()

        assertEquals("example.com/a/b", projected.text)
        assertEquals(listOf(0 to 15), projected.getLinkAnnotations(0, projected.length).map { it.start to it.end })
        assertEquals(listOf(0 to 15), projected.spanStyles.map { it.start to it.end })
        assertEquals(listOf(0 to 15), projected.cjkDecorations().map { it.range.start to it.range.end })
        assertTrue(projected.getStringAnnotations(CjkWbrTag, 0, projected.length).isEmpty())
        assertEquals(listOf(0 to 5), text.withoutCjkWbr(10, 16).spanStyles.map { it.start to it.end })
    }

    @Test
    fun fullAndPartialCopyOmitWbrButKeepPlainZeroWidthSpace() {
        val clipboard = RecordingClipboard()
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 360, height = 140) {
            state = selectionHost(clipboard, document = null) {
                CjkText(topics, modifier = Modifier.width(340.dp), style = TextStyle(fontSize = 24.sp))
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")

            assertTrue(selectionState.selectAll())
            assertEquals(topics.text, selectionState.selectedText?.text) // selection stays source
            assertTrue(selectionState.copySelection())
            assertEquals(topicsWithoutWbr, clipboard.recordedText?.text)

            val node = topicsSemanticsNode(scene)
            val setSelection = node.config[SemanticsActions.SetSelection].action
                ?: error("set-selection semantics action missing")
            // Accessibility offsets [1, 7) of "#甲##乙#\u200B丙" map to source [1, 8).
            assertTrue(setSelection(1, 7, true))
            assertEquals("甲#\u200B#乙#\u200B", selectionState.selectedText?.text)
            scene.render()
            assertEquals(
                ComposeTextRange(1, 7),
                topicsSemanticsNode(scene).config[SemanticsProperties.TextSelectionRange],
            )
            assertTrue(selectionState.copySelection())
            assertEquals("甲##乙#\u200B", clipboard.recordedText?.text)
        }
    }

    @Test
    fun documentFullAndPartialCopyOmitWbrButKeepPlainZeroWidthSpace() {
        val clipboard = RecordingClipboard()
        var state: CjkSelectionState? = null
        val document = CjkSelectionDocument(listOf(CjkSelectionDocumentFragment("topics", topics)))
        ImageComposeScene(width = 360, height = 140) {
            state = selectionHost(clipboard, document) {
                CjkSelectionScope("topics") {
                    CjkText(topics, modifier = Modifier.width(340.dp), style = TextStyle(fontSize = 24.sp))
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")

            assertTrue(selectionState.selectAll())
            assertTrue(selectionState.copySelection())
            assertEquals(topicsWithoutWbr, clipboard.recordedText?.text)

            val setSelection = topicsSemanticsNode(scene).config[SemanticsActions.SetSelection].action
                ?: error("set-selection semantics action missing")
            assertTrue(setSelection(1, 7, true))
            assertTrue(selectionState.copySelection())
            assertEquals("甲##乙#\u200B", clipboard.recordedText?.text)
        }
    }

    @Composable
    private fun selectionHost(
        clipboard: ClipboardManager,
        document: CjkSelectionDocument?,
        content: @Composable () -> Unit,
    ): CjkSelectionState {
        val selectionState = rememberCjkSelectionState()
        CompositionLocalProvider(LocalClipboardManager provides clipboard) {
            if (document == null) {
                CjkSelectionContainer(state = selectionState) { content() }
            } else {
                CjkSelectionContainer(state = selectionState, document = document) { content() }
            }
        }
        return selectionState
    }

    private fun topicsSemanticsNode(scene: ImageComposeScene): SemanticsNode =
        scene.semanticsOwners.flatMap { it.getAllSemanticsNodes(mergingEnabled = false) }
            .single { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == topicsWithoutWbr &&
                    SemanticsActions.SetSelection in node.config
            }

    private class RecordingClipboard : ClipboardManager {
        var recordedText: AnnotatedString? = null

        override fun setText(annotatedString: AnnotatedString) {
            recordedText = annotatedString
        }

        override fun getText(): AnnotatedString? = recordedText
    }
}
