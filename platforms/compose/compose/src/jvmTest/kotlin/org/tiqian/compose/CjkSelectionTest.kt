@file:Suppress("DEPRECATION")

package org.tiqian.compose

import androidx.compose.foundation.ContextMenuState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.LocalTextContextMenu
import androidx.compose.foundation.text.TextContextMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalTextToolbar
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.platform.TextToolbarStatus
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getAllSemanticsNodes
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.TextRange as ComposeTextRange
import androidx.compose.ui.text.UrlAnnotation
import androidx.compose.ui.text.VerbatimTtsAnnotation
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.LayoutResult
import org.tiqian.core.getBoundingBoxes
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalFoundationApi::class)
class CjkSelectionTest {
    @Test
    fun logicalSelectionSurvivesVisibleFragmentDisposal() {
        var state: CjkSelectionState? = null
        var showFirst by mutableStateOf(true)
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString("第一段")),
                CjkSelectionDocumentFragment("second", AnnotatedString("第二段")),
            ),
        )
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(
                state = selectionState,
                document = document,
            ) {
                if (showFirst) {
                    CjkSelectionScope("first") { CjkText("第一段") }
                } else {
                    CjkSelectionScope("second") { CjkText("第二段") }
                }
            }
        }.use { scene ->
            scene.render()
            assertEquals(null, state!!.selectedRanges)
            assertTrue(state!!.selectAll())
            val expectedRanges = listOf(
                CjkSelectionDocumentRange("first", 0, 3, document.fragments[0].text),
                CjkSelectionDocumentRange("second", 0, 3, document.fragments[1].text),
            )
            assertEquals("第一段\n第二段", state!!.selectedText?.text)
            assertEquals(expectedRanges, state!!.selectedRanges)
            (state!!.selectedRanges as MutableList<CjkSelectionDocumentRange>).clear()
            assertEquals(expectedRanges, state!!.selectedRanges)
            showFirst = false
            scene.render()
            assertEquals("第一段\n第二段", state!!.selectedText?.text)
            assertEquals(expectedRanges, state!!.selectedRanges)
            assertTrue(state!!.hasSelection)
            state!!.clearSelection()
            assertEquals(null, state!!.selectedText)
            assertEquals(null, state!!.selectedRanges)
            assertTrue(state!!.selectAll())
        }
        assertEquals(null, state!!.selectedText)
        assertEquals(null, state!!.selectedRanges)
    }

    @Test
    fun documentRangesIdentifyRepeatedTextAndUseSourceSafeUtf16Offsets() {
        val clipboard = RecordingClipboardManager()
        val source = "甲😀乙"
        val styledSource = buildAnnotatedString {
            append("甲")
            withStyle(SpanStyle(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)) { append("😀") }
            append("乙")
        }
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString(source)),
                CjkSelectionDocumentFragment("second", styledSource),
            ),
        )
        var state: CjkSelectionState? = null

        ImageComposeScene(width = 320, height = 180) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState, document = document) {
                    Column {
                        CjkSelectionScope("first") {
                            CjkText(
                                source,
                                modifier = Modifier.testTag("first"),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                            )
                        }
                        CjkSelectionScope("second") {
                            CjkText(
                                styledSource,
                                modifier = Modifier.testTag("second"),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                            )
                        }
                    }
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            fun setSelection(tag: String, start: Int, end: Int): Boolean {
                val node = scene.semanticsOwners.flatMap {
                    it.getAllSemanticsNodes(mergingEnabled = false)
                }.single { node ->
                    node.config.getOrNull(SemanticsProperties.TestTag) == tag &&
                        SemanticsActions.SetSelection in node.config
                }
                val action = node.config[SemanticsActions.SetSelection].action
                    ?: error("set-selection semantics action missing")
                return action(start, end, true)
            }

            assertTrue(setSelection("first", 2, 4))
            assertEquals("😀乙", selectionState.selectedText?.text)
            assertEquals(listOf(CjkSelectionDocumentRange("first", 1, 4, document.fragments[0].text)), selectionState.selectedRanges)
            assertTrue(setSelection("second", 2, 4))
            assertEquals("😀乙", selectionState.selectedText?.text)
            assertEquals(listOf(CjkSelectionDocumentRange("second", 1, 4, document.fragments[1].text)), selectionState.selectedRanges)
            assertTrue(selectionState.selectedRanges!!.single().fragmentText === styledSource)
            assertEquals(styledSource.spanStyles, selectionState.selectedRanges!!.single().fragmentText.spanStyles)
            assertTrue(selectionState.copySelection())
            assertEquals("😀乙", clipboard.recordedText?.text)

            assertTrue(selectionState.selectRange("second", 2, 4))
            scene.render()
            assertEquals(listOf(CjkSelectionDocumentRange("second", 1, 4, styledSource)), selectionState.selectedRanges)
            selectionState.beginHandleDrag(isStart = false)
            assertTrue(selectionState.isSelectionGestureInProgress)
            assertTrue(selectionState.selectRange("second", 0, 4))
            scene.render()
            assertFalse(selectionState.isSelectionGestureInProgress)
            assertFalse(selectionState.isSelectionAutoScrollArmed)
            assertTrue(selectionState.activeGestureOwnerKeys.isEmpty())
            assertEquals(source, selectionState.selectedText?.text)
            assertEquals(listOf(CjkSelectionDocumentRange("second", 0, 4, styledSource)), selectionState.selectedRanges)
            assertTrue(selectionState.startHandlePosition != null)
            assertTrue(selectionState.endHandlePosition != null)
            assertTrue(selectionState.copySelection())
            assertEquals(source, clipboard.recordedText?.text)
            assertFalse(selectionState.selectRange("foreign", 0, 4))
            assertFalse(selectionState.selectRange("second", -1, 4))
            assertFalse(selectionState.selectRange("second", 0, 5))
            assertFalse(selectionState.selectRange("second", 4, 1))
            assertFalse(selectionState.selectRange("second", 1, 1))
            assertEquals(listOf(CjkSelectionDocumentRange("second", 0, 4, styledSource)), selectionState.selectedRanges)
            assertTrue(selectionState.selectRange("first", 0, 4))
            assertEquals(listOf(CjkSelectionDocumentRange("first", 0, 4, document.fragments[0].text)), selectionState.selectedRanges)
            assertFalse(CjkSelectionState().selectRange("first", 0, 1))

            assertTrue(setSelection("second", 4, 1))
            assertEquals("😀乙", selectionState.selectedText?.text)
            assertEquals(listOf(CjkSelectionDocumentRange("second", 1, 4, document.fragments[1].text)), selectionState.selectedRanges)
            assertTrue(setSelection("second", -10, 100))
            assertEquals(source, selectionState.selectedText?.text)
            assertEquals(listOf(CjkSelectionDocumentRange("second", 0, 4, document.fragments[1].text)), selectionState.selectedRanges)
            assertTrue(setSelection("second", 1, 1))
            assertEquals(null, selectionState.selectedText)
            assertEquals(null, selectionState.selectedRanges)
        }
    }

    @Test
    fun backwardDocumentDragIncludesUncomposedFragmentsInReadingOrder() {
        val clipboard = RecordingClipboardManager()
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString("甲乙丙")),
                CjkSelectionDocumentFragment(
                    "middle", AnnotatedString("重复"), textForCopy = AnnotatedString("副本"),
                ),
                CjkSelectionDocumentFragment("last", AnnotatedString("丁戊己")),
            ),
        )
        var state: CjkSelectionState? = null
        var first: LayoutResult? = null
        var last: LayoutResult? = null

        ImageComposeScene(width = 360, height = 220) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState, document = document) {
                    Column {
                        CjkSelectionScope("first") {
                            CjkText(
                                "甲乙丙", modifier = Modifier.width(340.dp),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                                onTextLayout = { first = it },
                            )
                        }
                        CjkSelectionScope("last") {
                            CjkText(
                                "丁戊己", modifier = Modifier.width(340.dp),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                                onTextLayout = { last = it },
                            )
                        }
                    }
                }
            }
        }.use { scene ->
            scene.render()
            val firstResult = first ?: error("first layout missing")
            val lastResult = last ?: error("last layout missing")
            assertTrue(
                (0 until 3).all { cursor(firstResult, it).x < cursor(firstResult, it + 1).x },
                "first fragment must have distinct caret positions: ${firstResult.debug.shapingDecisions}",
            )
            assertTrue(
                (0 until 3).all { cursor(lastResult, it).x < cursor(lastResult, it + 1).x },
                "last fragment must have distinct caret positions: ${lastResult.debug.shapingDecisions}",
            )
            val lastPosition = cursor(lastResult, 2)
            drag(
                scene,
                Offset(lastPosition.x, firstResult.size.height + lastPosition.y),
                cursor(firstResult, 1),
                startTime = 3_000L,
            )
            val selectionState = state ?: error("selection state missing")
            assertEquals("乙丙\n重复\n丁戊", selectionState.selectedText?.text)
            assertEquals(
                listOf(
                    CjkSelectionDocumentRange("first", 1, 3, document.fragments[0].text),
                    CjkSelectionDocumentRange("middle", 0, 2, document.fragments[1].text),
                    CjkSelectionDocumentRange("last", 0, 2, document.fragments[2].text),
                ),
                selectionState.selectedRanges,
            )
            assertTrue(selectionState.handlesCrossed)
            assertTrue(selectionState.copySelection())
            assertEquals("乙丙\n副本\n丁戊", clipboard.recordedText?.text)
        }
    }

    @Test
    fun backwardDragAcrossEmptySeparatorRetainsZeroLengthEndpoint() {
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString("甲乙丙"), separatorAfter = ""),
                CjkSelectionDocumentFragment("second", AnnotatedString("丁戊己")),
            ),
        )
        var state: CjkSelectionState? = null
        var first: LayoutResult? = null
        var second: LayoutResult? = null

        ImageComposeScene(width = 360, height = 220) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {
                Column {
                    CjkSelectionScope("first") {
                        CjkText(
                            "甲乙丙", modifier = Modifier.width(340.dp),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                            onTextLayout = { first = it },
                        )
                    }
                    CjkSelectionScope("second") {
                        CjkText(
                            "丁戊己", modifier = Modifier.width(340.dp),
                                style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                            onTextLayout = { second = it },
                        )
                    }
                }
            }
        }.use { scene ->
            scene.render()
            val firstResult = first ?: error("first layout missing")
            val secondResult = second ?: error("second layout missing")
            assertTrue(
                (0 until 3).all { cursor(firstResult, it).x < cursor(firstResult, it + 1).x },
                "first fragment must have distinct caret positions: ${firstResult.debug.shapingDecisions}",
            )
            assertTrue(
                (0 until 3).all { cursor(secondResult, it).x < cursor(secondResult, it + 1).x },
                "second fragment must have distinct caret positions: ${secondResult.debug.shapingDecisions}",
            )
            val local = cursor(secondResult, 2)
            drag(
                scene,
                Offset(local.x, firstResult.size.height + local.y),
                cursor(firstResult, 3),
                startTime = 4_000L,
            )
            val selectionState = state ?: error("selection state missing")
            assertEquals("丁戊", selectionState.selectedText?.text)
            assertEquals(
                listOf(
                    CjkSelectionDocumentRange("first", 3, 3, document.fragments[0].text),
                    CjkSelectionDocumentRange("second", 0, 2, document.fragments[1].text),
                ),
                selectionState.selectedRanges,
            )
            assertTrue(selectionState.handlesCrossed)
        }
    }

    @Test
    fun documentRangesRetainEmptyFragmentsWithoutTreatingSeparatorsAsSource() {
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("empty-first", AnnotatedString(""), separatorAfter = "|"),
                CjkSelectionDocumentFragment("middle", AnnotatedString("甲"), separatorAfter = "|"),
                CjkSelectionDocumentFragment("empty-last", AnnotatedString("")),
            ),
        )
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {}
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertTrue(selectionState.selectAll())
            assertEquals("|甲|", selectionState.selectedText?.text)
            assertEquals(
                listOf(
                    CjkSelectionDocumentRange("empty-first", 0, 0, document.fragments[0].text),
                    CjkSelectionDocumentRange("middle", 0, 1, document.fragments[1].text),
                    CjkSelectionDocumentRange("empty-last", 0, 0, document.fragments[2].text),
                ),
                selectionState.selectedRanges,
            )
        }
    }

    @Test
    fun separatorOnlySelectionRetainsBothEmptyFragmentRanges() {
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString(""), separatorAfter = "|"),
                CjkSelectionDocumentFragment("second", AnnotatedString("")),
            ),
        )
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {}
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertTrue(selectionState.selectAll())
            assertEquals("|", selectionState.selectedText?.text)
            assertEquals(
                listOf(
                    CjkSelectionDocumentRange("first", 0, 0, document.fragments[0].text),
                    CjkSelectionDocumentRange("second", 0, 0, document.fragments[1].text),
                ),
                selectionState.selectedRanges,
            )
        }
    }

    @Test
    fun textAndRangesAreObservedTogetherWithoutRepeatedRecomposition() {
        val document = CjkSelectionDocument(
            listOf(CjkSelectionDocumentFragment("body", AnnotatedString("正文"))),
        )
        val observations = mutableListOf<Pair<String?, List<CjkSelectionDocumentRange>?>>()
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {
                val text = selectionState.selectedText?.text
                val ranges = selectionState.selectedRanges
                SideEffect { observations += text to ranges }
                CjkSelectionScope("body") { CjkText("正文") }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertTrue(selectionState.selectAll())
            repeat(3) { scene.render() }
            assertEquals("正文" to listOf(CjkSelectionDocumentRange("body", 0, 2, document.fragments[0].text)), observations.last())
            val stableCount = observations.size
            repeat(3) { scene.render() }
            assertEquals(stableCount, observations.size)
            selectionState.clearSelection()
            scene.render()
            assertEquals(null to null, observations.last())
            assertTrue(observations.all { (text, ranges) ->
                (text == null && ranges == null) ||
                    (text == "正文" && ranges == listOf(CjkSelectionDocumentRange("body", 0, 2, document.fragments[0].text)))
            })
        }
    }

    @Test
    fun selectionChangingKeysWithSameTextPublishesTheNewRange() {
        val document = CjkSelectionDocument(
            listOf(
                CjkSelectionDocumentFragment("first", AnnotatedString("重复")),
                CjkSelectionDocumentFragment("second", AnnotatedString("重复")),
            ),
        )
        val observations = mutableListOf<Pair<String?, List<CjkSelectionDocumentRange>?>>()
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {
                val text = selectionState.selectedText?.text
                val ranges = selectionState.selectedRanges
                SideEffect { observations += text to ranges }
                Column {
                    CjkSelectionScope("first") { CjkText("重复", modifier = Modifier.testTag("first")) }
                    CjkSelectionScope("second") { CjkText("重复", modifier = Modifier.testTag("second")) }
                }
            }
        }.use { scene ->
            scene.render()
            fun select(tag: String) {
                val node = scene.semanticsOwners.flatMap {
                    it.getAllSemanticsNodes(mergingEnabled = false)
                }.single { node ->
                    node.config.getOrNull(SemanticsProperties.TestTag) == tag &&
                        SemanticsActions.SetSelection in node.config
                }
                val action = node.config[SemanticsActions.SetSelection].action
                    ?: error("set-selection semantics action missing")
                assertTrue(action(0, 2, true))
            }
            select("first")
            repeat(3) { scene.render() }
            assertEquals(
                "重复" to listOf(CjkSelectionDocumentRange("first", 0, 2, document.fragments[0].text)),
                observations.last(),
            )
            select("second")
            repeat(3) { scene.render() }
            assertEquals(
                "重复" to listOf(CjkSelectionDocumentRange("second", 0, 2, document.fragments[1].text)),
                observations.last(),
            )
            assertEquals("重复", state!!.selectedText?.text)
        }
    }

    @Test
    fun selectionRangesClearWhenDocumentIsReplacedOrContainerIsDetached() {
        val firstDocument = CjkSelectionDocument(
            listOf(CjkSelectionDocumentFragment("body", AnnotatedString("正文"))),
        )
        val replacement = CjkSelectionDocument(
            listOf(CjkSelectionDocumentFragment("body", AnnotatedString("正文"))),
        )
        var document by mutableStateOf(firstDocument)
        var showContainer by mutableStateOf(true)
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            if (showContainer) {
                CjkSelectionContainer(state = selectionState, document = document) {
                    CjkSelectionScope("body") { CjkText("正文") }
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertTrue(selectionState.selectAll())
            assertEquals(listOf(CjkSelectionDocumentRange("body", 0, 2, document.fragments[0].text)), selectionState.selectedRanges)
            document = replacement
            scene.render()
            assertEquals(null, selectionState.selectedText)
            assertEquals(null, selectionState.selectedRanges)
            assertTrue(selectionState.selectAll())
            showContainer = false
            scene.render()
            assertEquals(null, selectionState.selectedText)
            assertEquals(null, selectionState.selectedRanges)
        }
    }

    @Test
    fun selectionWithoutDocumentReportsUnavailableRangesWithoutExposingScopeKeys() {
        var state: CjkSelectionState? = null
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState) {
                Column {
                    CjkSelectionScope("shared") { CjkText("正文") }
                    CjkSelectionScope("shared") { CjkText("正文") }
                    CjkText("无键")
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertEquals(null, selectionState.selectedRanges)
            assertTrue(selectionState.selectAll())
            assertEquals("正文\n正文\n无键", selectionState.selectedText?.text)
            assertEquals(null, selectionState.selectedRanges)
            selectionState.clearSelection()
            assertEquals(null, selectionState.selectedRanges)
        }
    }

    @Test
    fun logicalDocumentIgnoresUnmappedHostText() {
        var state: CjkSelectionState? = null
        val document = CjkSelectionDocument(
            listOf(CjkSelectionDocumentFragment("body", AnnotatedString("正文"))),
        )
        ImageComposeScene(width = 320, height = 160) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CjkSelectionContainer(state = selectionState, document = document) {
                Column {
                    CjkText("宿主标题")
                    CjkSelectionScope("body") { CjkText("正文") }
                }
            }
        }.use { scene ->
            scene.render()
            assertTrue(state!!.selectAll())
            assertEquals("正文", state!!.selectedText?.text)
        }
    }


    @Test
    fun toolbarHandleClearanceScalesWithDensity() {
        val oneX = foundationSelectionToolbarHandleClearancePx(Density(1f))
        val twoX = foundationSelectionToolbarHandleClearancePx(Density(2f))

        assertEquals(oneX * 2f, twoX, 0.001f)
    }

    @Test
    fun selectionCopiesOriginalAnnotatedSource() {
        val clipboard = RecordingClipboardManager()
        var state: CjkSelectionState? = null
        var layout: LayoutResult? = null
        val source = AnnotatedString("甲乙丙丁戊")

        ImageComposeScene(width = 320, height = 140) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState) {
                    CjkText(
                        text = source,
                        modifier = Modifier.width(300.dp),
                        style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                        onTextLayout = { layout = it },
                    )
                }
            }
        }.use { scene ->
            scene.render()
            val result = layout ?: error("layout missing")
            drag(scene, cursor(result, 1), cursor(result, 4), startTime = 2_000L)

            assertTrue(state?.copySelection() == true)
            assertEquals("乙丙丁", clipboard.recordedText?.text)
        }
    }

    @Test
    fun copyMatchesWebRubyProjectionWithoutChangingSelectionOrAccessibilityText() {
        val clipboard = RecordingClipboardManager()
        var state: CjkSelectionState? = null
        val firstSource = buildAnnotatedString {
            append("前")
            ruby("提椠", "tíqiàn")
        }
        val secondSource = buildAnnotatedString {
            bopomofo("您", "ㄋㄧㄣˊ")
            append("后")
        }

        ImageComposeScene(width = 360, height = 220) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState) {
                    Column {
                        CjkText(firstSource, modifier = Modifier.width(340.dp), style = TextStyle(fontSize = 24.sp))
                        CjkText(secondSource, modifier = Modifier.width(340.dp), style = TextStyle(fontSize = 24.sp))
                    }
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            assertTrue(selectionState.selectAll())
            scene.render()

            assertEquals("前提椠\n您后", selectionState.selectedText?.text)
            assertTrue(selectionState.copySelection())
            assertEquals("前提椠（tíqiàn）\n您（ㄋㄧㄣˊ）后", clipboard.recordedText?.text)

            val semanticTexts = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.mapNotNull { it.config.getOrNull(SemanticsProperties.Text)?.singleOrNull() }
            assertTrue(firstSource in semanticTexts)
            assertTrue(secondSource in semanticTexts)
        }
    }

    @Test
    fun partialRubyBaseSelectionDoesNotCopyDetachedReading() {
        val clipboard = RecordingClipboardManager()
        var state: CjkSelectionState? = null
        val source = buildAnnotatedString {
            ruby("提椠", "tíqiàn")
            append("之后")
        }

        ImageComposeScene(width = 320, height = 140) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState) {
                    CjkText(source, modifier = Modifier.width(300.dp), style = TextStyle(fontSize = 24.sp))
                }
            }
        }.use { scene ->
            scene.render()
            val semantics = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull() == source &&
                    SemanticsActions.SetSelection in node.config
            }
            val setSelection = semantics.config[SemanticsActions.SetSelection].action
                ?: error("set-selection semantics action missing")

            assertTrue(setSelection(0, 1, true))
            assertEquals("提", state?.selectedText?.text)
            assertTrue(state?.copySelection() == true)
            assertEquals("提", clipboard.recordedText?.text)
        }
    }

    @Test
    fun desktopContextMenuConsumesTheLiveTiqianSelectionAndActions() {
        val clipboard = RecordingClipboardManager()
        val contextMenu = RecordingTextContextMenu()
        var state: CjkSelectionState? = null
        var layout: LayoutResult? = null
        val source = "前 context 后"

        ImageComposeScene(width = 360, height = 140) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(
                LocalClipboardManager provides clipboard,
                LocalTextContextMenu provides contextMenu,
            ) {
                CjkSelectionContainer(state = selectionState) {
                    CjkText(
                        source,
                        modifier = Modifier.width(340.dp),
                        style = TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Serif),
                        onTextLayout = { layout = it },
                    )
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            val manager = contextMenu.manager ?: error("desktop text context menu was not installed")

            assertTrue(selectionState.selectAll())
            scene.render()
            assertEquals(source, manager.selectedText.text)
            assertTrue(manager.copy?.enabled == true)
            manager.copy?.execute?.invoke()
            assertEquals(source, clipboard.recordedText?.text)

            selectionState.clearSelection()
            manager.selectWordAtPositionIfNotAlreadySelected(
                cursor(layout ?: error("layout missing"), source.indexOf("context") + 2),
            )
            assertEquals("context", selectionState.selectedText?.text)
        }
    }

    @Test
    fun tapWithoutCjkSelectionDoesNotHideAnotherChildsTextToolbar() {
        val toolbar = RecordingTextToolbar()

        ImageComposeScene(width = 360, height = 220) {
            CompositionLocalProvider(LocalTextToolbar provides toolbar) {
                CjkSelectionContainer(
                    modifier = Modifier.width(360.dp).height(220.dp),
                ) {}
            }
        }.use { scene ->
            scene.render()

            tap(
                scene,
                position = Offset(300f, 180f),
                pressTime = 2_600L,
                releaseTime = 2_650L,
            )
            scene.render()

            assertEquals(0, toolbar.hideCalls)
        }
    }

    @Test
    fun clearingTouchSelectionHidesSystemMenuBeforePublishingEmptySelection() {
        var state: CjkSelectionState? = null
        var layout: LayoutResult? = null
        val shortLongPress = object : ViewConfiguration {
            override val longPressTimeoutMillis = 1L
            override val doubleTapTimeoutMillis = 300L
            override val doubleTapMinTimeMillis = 40L
            override val touchSlop = 8f
        }

        ImageComposeScene(width = 320, height = 140) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalViewConfiguration provides shortLongPress) {
                CjkSelectionContainer(state = selectionState) {
                    CjkText(
                        "甲中文乙",
                        modifier = Modifier.width(300.dp),
                        style = TextStyle(fontSize = 24.sp),
                        onTextLayout = { layout = it },
                    )
                }
            }
        }.use { scene ->
            scene.render()
            val selectionState = state ?: error("selection state missing")
            val menuEvents = mutableListOf<Pair<String, Boolean>>()
            val systemMenu = CjkSystemContextMenu(
                show = { menuEvents += "show" to selectionState.hasSelection },
                hide = { menuEvents += "hide" to selectionState.hasSelection },
            )
            selectionState.attachSystemContextMenu(systemMenu)

            val box = (layout ?: error("layout missing")).getBoundingBoxes(1, 2).single()
            val point = Offset((box.left + box.right) / 2f, (box.top + box.bottom) / 2f)
            scene.sendPointerEvent(
                PointerEventType.Press,
                point,
                timeMillis = 6_500L,
                type = PointerType.Touch,
            )
            Thread.sleep(20L)
            scene.render()
            scene.sendPointerEvent(
                PointerEventType.Release,
                point,
                timeMillis = 6_550L,
                type = PointerType.Touch,
            )
            assertEquals("show" to true, menuEvents.last())
            menuEvents.clear()

            selectionState.clearSelection()
            assertEquals(
                listOf("hide" to true),
                menuEvents,
                "ActionMode must close before the empty state can rebuild it as Select all only",
            )
            selectionState.detachSystemContextMenu(systemMenu)
        }
    }

    @Test
    fun semanticsCanSetAndCopyASourceSafeSelection() {
        val clipboard = RecordingClipboardManager()
        val source = "甲😀乙丁"
        var state: CjkSelectionState? = null

        ImageComposeScene(width = 320, height = 140) {
            val selectionState = rememberCjkSelectionState()
            state = selectionState
            CompositionLocalProvider(LocalClipboardManager provides clipboard) {
                CjkSelectionContainer(state = selectionState) {
                    CjkText(source, modifier = Modifier.width(300.dp), style = TextStyle(fontSize = 24.sp))
                }
            }
        }.use { scene ->
            scene.render()
            val semantics = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == source &&
                    SemanticsActions.SetSelection in node.config
            }
            val setSelection = semantics.config[SemanticsActions.SetSelection].action
                ?: error("set-selection semantics action missing")
            assertTrue(
                SemanticsActions.CopyText !in semantics.config,
                "static text must not advertise Android ACTION_COPY before it owns a selection",
            )

            assertTrue(setSelection(2, 4, true))
            assertEquals("😀乙", state?.selectedText?.text)
            scene.render()

            val updatedSemantics = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == source &&
                    SemanticsActions.SetSelection in node.config
            }
            assertEquals(
                ComposeTextRange(1, 4),
                updatedSemantics.config[SemanticsProperties.TextSelectionRange],
            )
            val copy = updatedSemantics.config[SemanticsActions.CopyText].action
                ?: error("copy semantics action missing")
            assertTrue(copy())
            assertEquals("😀乙", clipboard.recordedText?.text)
        }
    }

    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    @Suppress("DEPRECATION")
    @Test
    fun semanticsPreserveLinksAndTtsAnnotationsForPlatformAccessibility() {
        val source = buildAnnotatedString {
            withLink(LinkAnnotation.Url("https://example.com/modern")) {
                append("链接")
            }
            append("正文")
            addUrlAnnotation(UrlAnnotation("https://example.com"), 0, 2)
            addTtsAnnotation(VerbatimTtsAnnotation("正文"), 2, 4)
        }

        ImageComposeScene(width = 320, height = 140) {
            CjkText(source, modifier = Modifier.width(300.dp), style = TextStyle(fontSize = 24.sp))
        }.use { scene ->
            scene.render()
            val exposed = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }.single { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == source.text
            }.config[SemanticsProperties.Text].single()

            assertEquals(1, exposed.getLinkAnnotations(0, exposed.length).size)
            assertEquals(1, exposed.getUrlAnnotations(0, exposed.length).size)
            assertEquals(1, exposed.getTtsAnnotations(0, exposed.length).size)
        }
    }

    @Test
    fun selectionContainerDoesNotExposeAnEmptyAccessibilityFocusStop() {
        ImageComposeScene(width = 320, height = 140) {
            CjkSelectionContainer {
                CjkText("无障碍正文", modifier = Modifier.width(300.dp), style = TextStyle(fontSize = 24.sp))
            }
        }.use { scene ->
            scene.render()
            val semantics = scene.semanticsOwners.flatMap {
                it.getAllSemanticsNodes(mergingEnabled = false)
            }

            assertFalse(
                semantics.any { node ->
                    SemanticsProperties.Focused in node.config &&
                        node.config.getOrNull(SemanticsProperties.Text).isNullOrEmpty()
                },
                "keyboard selection ownership must not add an unnamed accessibility focus stop",
            )
        }
    }

    private class RecordingClipboardManager : ClipboardManager {
        var recordedText: AnnotatedString? = null

        override fun setText(annotatedString: AnnotatedString) {
            recordedText = annotatedString
        }

        override fun getText(): AnnotatedString? = recordedText
    }

    private class RecordingTextToolbar : TextToolbar {
        var hideCalls: Int = 0
        override var status: TextToolbarStatus = TextToolbarStatus.Shown

        override fun showMenu(
            rect: Rect,
            onCopyRequested: (() -> Unit)?,
            onPasteRequested: (() -> Unit)?,
            onCutRequested: (() -> Unit)?,
            onSelectAllRequested: (() -> Unit)?,
        ) {
            status = TextToolbarStatus.Shown
        }

        override fun hide() {
            hideCalls++
            status = TextToolbarStatus.Hidden
        }
    }

    private class RecordingTextContextMenu : TextContextMenu {
        var manager: TextContextMenu.TextManager? = null

        @Composable
        override fun Area(
            textManager: TextContextMenu.TextManager,
            state: ContextMenuState,
            content: @Composable () -> Unit,
        ) {
            manager = textManager
            content()
        }
    }
}
