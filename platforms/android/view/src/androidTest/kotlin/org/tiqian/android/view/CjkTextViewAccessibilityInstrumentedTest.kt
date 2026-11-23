package org.tiqian.android.view

import android.graphics.RectF
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.getBoundingBoxes
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
@Suppress("DEPRECATION")
class CjkTextViewAccessibilityInstrumentedTest {
    @Before
    fun enableAccessibilityService() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.serviceInfo
    }

    @Test
    fun aLinkDoesNotMakeTheWholeReadOnlyParagraphClickable() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val source = "打开链接"
                val nativeText = SpannableString(source).apply {
                    setSpan(
                        object : ClickableSpan() {
                            override fun onClick(widget: View) = Unit
                        },
                        0,
                        source.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
                val native = TextView(activity).apply {
                    text = nativeText
                    setTextIsSelectable(true)
                    movementMethod = LinkMovementMethod.getInstance()
                }
                val cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(
                        content = TiqianTextContent(source),
                        textStyle = TextStyle(fontSize = 32f),
                        richTextSpans = listOf(
                            RichTextSpan(TextRange(0, source.length), Link("https://example.com")),
                        ),
                    )
                }
                activity.setContentView(
                    LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(native)
                        addView(cjk)
                    },
                )

                val nativeNode = native.createAccessibilityNodeInfo()
                val cjkNode = cjk.createAccessibilityNodeInfo()
                assertFalse(nativeNode.isClickable)
                assertEquals(nativeNode.isClickable, cjkNode.isClickable)
                assertFalse(cjkNode.hasAction(AccessibilityNodeInfo.ACTION_CLICK))
                assertEquals(1, clickableSpans(cjkNode.text).size)
            }
        }
    }

    @Test
    fun traversalContractAndSelectionStateMatchReadOnlyTextView() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val source = "甲乙 丙丁"
                val native = TextView(activity).apply {
                    text = source
                    textSize = 32f
                    setTextIsSelectable(true)
                }
                val cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 32f))
                }
                val root = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(native)
                    addView(cjk)
                }
                activity.setContentView(root)
                native.measure(exactly(320), atMost(1_000))
                native.layout(0, 0, native.measuredWidth, native.measuredHeight)
                cjk.measure(exactly(320), atMost(1_000))
                cjk.layout(0, native.measuredHeight, cjk.measuredWidth, native.measuredHeight + cjk.measuredHeight)

                val nativeNode = native.createAccessibilityNodeInfo()
                val cjkNode = cjk.createAccessibilityNodeInfo()
                assertEquals(nativeNode.movementGranularities, cjkNode.movementGranularities)
                listOf(
                    AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                    AccessibilityNodeInfo.ACTION_PREVIOUS_AT_MOVEMENT_GRANULARITY,
                    AccessibilityNodeInfo.ACTION_SET_SELECTION,
                ).forEach { action ->
                    assertTrue(nativeNode.hasAction(action), "native TextView baseline lacks $action")
                    assertTrue(cjkNode.hasAction(action), "CjkTextView must expose native action $action")
                }

                val cursorAtStart = selectionArguments(1, 1)
                assertTrue(native.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursorAtStart))
                assertTrue(cjk.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursorAtStart))
                assertSelection(native, cjk, expectedStart = 1, expectedEnd = 1)

                val nextCharacter = movementArguments(
                    AccessibilityNodeInfo.MOVEMENT_GRANULARITY_CHARACTER,
                    extend = false,
                )
                assertTrue(
                    native.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                        nextCharacter,
                    ),
                )
                assertTrue(
                    cjk.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                        nextCharacter,
                    ),
                )
                assertSelection(native, cjk, expectedStart = 2, expectedEnd = 2)

                val extendCharacter = movementArguments(
                    AccessibilityNodeInfo.MOVEMENT_GRANULARITY_CHARACTER,
                    extend = true,
                )
                assertTrue(
                    native.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                        extendCharacter,
                    ),
                )
                assertTrue(
                    cjk.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                        extendCharacter,
                    ),
                )
                assertSelection(native, cjk, expectedStart = 2, expectedEnd = 3)
                assertEquals(TextRange(2, 3), cjk.selection)

                val cursorAtThree = selectionArguments(3, 3)
                assertTrue(native.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursorAtThree))
                assertTrue(cjk.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursorAtThree))
                val extendBackward = movementArguments(
                    AccessibilityNodeInfo.MOVEMENT_GRANULARITY_CHARACTER,
                    extend = true,
                )
                assertTrue(
                    native.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_PREVIOUS_AT_MOVEMENT_GRANULARITY,
                        extendBackward,
                    ),
                )
                assertTrue(
                    cjk.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_PREVIOUS_AT_MOVEMENT_GRANULARITY,
                        extendBackward,
                    ),
                )
                assertSelection(native, cjk, expectedStart = 3, expectedEnd = 2)
                assertEquals(TextRange(2, 3), cjk.selection)

                val event = AccessibilityEvent.obtain(
                    AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED,
                )
                try {
                    cjk.onInitializeAccessibilityEvent(event)
                    assertEquals(source.length, event.itemCount)
                    assertEquals(3, event.fromIndex)
                    assertEquals(2, event.toIndex)
                } finally {
                    event.recycle()
                }
            }
        }
    }

    @Test
    fun wordLineParagraphAndPageTraversalMatchReadOnlyTextView() {
        val fixtures = listOf(
            GranularityFixture("甲乙丙丁", AccessibilityNodeInfo.MOVEMENT_GRANULARITY_PAGE),
            GranularityFixture("one two", AccessibilityNodeInfo.MOVEMENT_GRANULARITY_WORD),
            GranularityFixture(
                "甲乙\n丙丁",
                AccessibilityNodeInfo.MOVEMENT_GRANULARITY_LINE,
                initialCursor = 5,
            ),
            GranularityFixture("甲乙\n丙丁", AccessibilityNodeInfo.MOVEMENT_GRANULARITY_PARAGRAPH),
        )
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val pairs = fixtures.map { fixture ->
                    val native = TextView(activity).apply {
                        text = fixture.source
                        textSize = 32f
                        setTextIsSelectable(true)
                    }
                    val cjk = CjkTextView(activity).apply {
                        content = CjkTextContent(fixture.source, TextStyle(fontSize = 32f))
                    }
                    fixture to (native to cjk)
                }
                val root = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    pairs.forEach { (_, pair) ->
                        addView(pair.first)
                        addView(pair.second)
                    }
                }
                activity.setContentView(root)
                root.measure(exactly(320), atMost(3_000))
                root.layout(0, 0, root.measuredWidth, root.measuredHeight)

                pairs.forEach { (fixture, pair) ->
                    val (native, cjk) = pair
                    val cursor = selectionArguments(fixture.initialCursor, fixture.initialCursor)
                    assertEquals(
                        native.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursor),
                        cjk.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cursor),
                        "set-selection mismatch for granularity ${fixture.granularity}",
                    )
                    val previous = movementArguments(fixture.granularity, extend = false)
                    assertTrue(
                        native.performAccessibilityAction(
                            AccessibilityNodeInfo.ACTION_PREVIOUS_AT_MOVEMENT_GRANULARITY,
                            previous,
                        ),
                        "native previous failed for granularity ${fixture.granularity}",
                    )
                    assertTrue(
                        cjk.performAccessibilityAction(
                            AccessibilityNodeInfo.ACTION_PREVIOUS_AT_MOVEMENT_GRANULARITY,
                            previous,
                        ),
                        "CjkTextView previous failed for granularity ${fixture.granularity}",
                    )
                    assertSameAccessibilitySelection(native, cjk, fixture.granularity, "previous")

                    val next = movementArguments(fixture.granularity, extend = false)
                    assertTrue(
                        native.performAccessibilityAction(
                            AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                            next,
                        ),
                        "native next failed for granularity ${fixture.granularity}",
                    )
                    assertTrue(
                        cjk.performAccessibilityAction(
                            AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY,
                            next,
                        ),
                        "CjkTextView next failed for granularity ${fixture.granularity}",
                    )
                    assertSameAccessibilitySelection(native, cjk, fixture.granularity, "next")
                }
            }
        }
    }

    @Test
    fun characterLocationRequestsUseNativeValidationAndVisibleRegionRules() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val source = "甲乙丙丁戊己庚辛壬癸"
                val view = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 32f))
                }
                val root = FrameLayout(activity).apply {
                    clipChildren = true
                    addView(view, FrameLayout.LayoutParams(96, 48))
                }
                activity.setContentView(root)
                root.measure(exactly(96), exactly(48))
                root.layout(0, 0, 96, 48)

                val zeroLengthNode = view.createAccessibilityNodeInfo()
                view.addExtraDataToAccessibilityNodeInfo(
                    zeroLengthNode,
                    AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    characterLocationArguments(start = 0, length = 0),
                )
                assertFalse(
                    zeroLengthNode.extras.containsKey(
                        AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    ),
                )

                val pastEndNode = view.createAccessibilityNodeInfo()
                view.addExtraDataToAccessibilityNodeInfo(
                    pastEndNode,
                    AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    characterLocationArguments(start = source.length, length = 1),
                )
                assertFalse(
                    pastEndNode.extras.containsKey(
                        AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    ),
                )

                val clippedNode = view.createAccessibilityNodeInfo()
                view.addExtraDataToAccessibilityNodeInfo(
                    clippedNode,
                    AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    characterLocationArguments(start = source.lastIndex, length = 1),
                )
                val clipped = characterLocations(clippedNode.extras)
                assertEquals(1, clipped?.size)
                assertNull(clipped?.single(), "a fully clipped character must not expose a screen rect")

                view.pivotX = 0f
                view.pivotY = 0f
                view.scaleX = 1.25f
                view.translationX = 4f
                val visibleNode = view.createAccessibilityNodeInfo()
                view.addExtraDataToAccessibilityNodeInfo(
                    visibleNode,
                    AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    characterLocationArguments(start = 0, length = 1),
                )
                val visibleBounds = assertNotNull(
                    characterLocations(visibleNode.extras)?.single() as? RectF,
                )
                val localBounds = assertNotNull(
                    view.layoutResult?.getBoundingBoxes(TextRange(0, 1))?.firstOrNull(),
                )
                assertEquals(
                    (localBounds.right - localBounds.left) * view.scaleX,
                    visibleBounds.width(),
                    absoluteTolerance = 0.5f,
                )
            }
        }
    }

    @Test
    fun sameLengthTextReplacementResetsAccessibilitySelectionLikeReadOnlyTextView() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val original = "甲乙丙丁"
                val replacement = "春夏秋冬"
                val native = TextView(activity).apply {
                    text = original
                    textSize = 32f
                    setTextIsSelectable(true)
                }
                val cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(original, TextStyle(fontSize = 32f))
                }
                val root = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(native)
                    addView(cjk)
                }
                activity.setContentView(root)
                root.measure(exactly(320), atMost(1_000))
                root.layout(0, 0, root.measuredWidth, root.measuredHeight)

                assertTrue(native.requestFocus())
                assertTrue(
                    native.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_SET_SELECTION,
                        selectionArguments(1, 3),
                    ),
                )
                native.text = replacement
                val nativeNode = native.createAccessibilityNodeInfo()

                assertTrue(cjk.requestFocus())
                assertTrue(
                    cjk.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_SET_SELECTION,
                        selectionArguments(1, 3),
                    ),
                )
                cjk.content = CjkTextContent(replacement, TextStyle(fontSize = 32f))
                val cjkNode = cjk.createAccessibilityNodeInfo()

                assertEquals(
                    nativeNode.textSelectionStart,
                    cjkNode.textSelectionStart,
                    "selection start must follow TextView after a same-length replacement",
                )
                assertEquals(
                    nativeNode.textSelectionEnd,
                    cjkNode.textSelectionEnd,
                    "selection end must follow TextView after a same-length replacement",
                )

                native.text = ""
                cjk.content = CjkTextContent("", TextStyle(fontSize = 32f))
                assertSelection(native, cjk, expectedStart = -1, expectedEnd = -1)
            }
        }
    }

    @Test
    fun nonSelectableAccessibilityContractMatchesReadOnlyTextView() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val source = "甲乙丙丁"
                val native = TextView(activity).apply {
                    text = source
                    setTextIsSelectable(false)
                }
                val cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 32f))
                    textIsSelectable = false
                }
                val root = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(native)
                    addView(cjk)
                }
                activity.setContentView(root)
                root.measure(exactly(320), atMost(1_000))
                root.layout(0, 0, root.measuredWidth, root.measuredHeight)

                val nativeNode = native.createAccessibilityNodeInfo()
                val cjkNode = cjk.createAccessibilityNodeInfo()
                assertEquals(nativeNode.textSelectionStart, cjkNode.textSelectionStart)
                assertEquals(nativeNode.textSelectionEnd, cjkNode.textSelectionEnd)
                assertEquals(nativeNode.movementGranularities, cjkNode.movementGranularities)
                assertEquals(
                    nativeNode.hasAction(AccessibilityNodeInfo.ACTION_SET_SELECTION),
                    cjkNode.hasAction(AccessibilityNodeInfo.ACTION_SET_SELECTION),
                )
                assertEquals(
                    native.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_SET_SELECTION,
                        selectionArguments(1, 2),
                    ),
                    cjk.performAccessibilityAction(
                        AccessibilityNodeInfo.ACTION_SET_SELECTION,
                        selectionArguments(1, 2),
                    ),
                )
                assertSelection(native, cjk, expectedStart = 1, expectedEnd = 2)
                assertNull(cjk.selection, "an accessibility-only range must not create visual selection")
            }
        }
    }

    @Test
    fun clearingAccessibilitySelectionMatchesReadOnlyTextView() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val source = "甲乙丙丁"
                val native = TextView(activity).apply {
                    text = source
                    setTextIsSelectable(true)
                }
                val cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 32f))
                }
                val root = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(native)
                    addView(cjk)
                }
                activity.setContentView(root)
                root.measure(exactly(320), atMost(1_000))
                root.layout(0, 0, root.measuredWidth, root.measuredHeight)
                val selected = selectionArguments(1, 3)
                assertTrue(native.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selected))
                assertTrue(cjk.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selected))

                val cleared = selectionArguments(-1, -1)
                assertEquals(
                    native.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cleared),
                    cjk.performAccessibilityAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, cleared),
                )
                val nativeNode = native.createAccessibilityNodeInfo()
                val cjkNode = cjk.createAccessibilityNodeInfo()
                assertEquals(nativeNode.textSelectionStart, cjkNode.textSelectionStart)
                assertEquals(nativeNode.textSelectionEnd, cjkNode.textSelectionEnd)
            }
        }
    }

    @Test
    fun textReplacementEventMatchesReadOnlyTextView() {
        lateinit var native: TextView
        lateinit var cjk: CjkTextView
        val original = "旧的正文"
        val nativeReplacement = "原生新正文"
        val cjkReplacement = "提椠新正文"
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                native = TextView(activity).apply {
                    text = original
                    setTextIsSelectable(true)
                }
                cjk = CjkTextView(activity).apply {
                    content = CjkTextContent(original, TextStyle(fontSize = 32f))
                }
                activity.setContentView(
                    LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(native)
                        addView(cjk)
                    },
                )
            }
            waitForIdle()

            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            val nativeEvent = automation.executeAndWaitForEvent(
                { scenario.onActivity { native.text = nativeReplacement } },
                { event ->
                    event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
                        event.contentChangeTypes and AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT != 0 &&
                        event.className == TextView::class.java.name
                },
                3_000,
            )
            val cjkEvent = automation.executeAndWaitForEvent(
                {
                    scenario.onActivity {
                        cjk.content = CjkTextContent(cjkReplacement, TextStyle(fontSize = 32f))
                    }
                },
                { event ->
                    event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
                        event.contentChangeTypes and AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT != 0 &&
                        event.className == TextView::class.java.name
                },
                3_000,
            )
            try {
                assertEquals(nativeEvent.className, cjkEvent.className)
                assertEquals(nativeEvent.contentChangeTypes, cjkEvent.contentChangeTypes)
            } finally {
                nativeEvent.recycle()
                cjkEvent.recycle()
            }
        }
    }

    @Test
    fun clickableSpanIdentityIsStableOnlyWithinOneContentRevision() {
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val activated = mutableListOf<String>()
                val registry = CjkAccessibilityLinkSpans { activated += it.target }
                val oldLink = CjkTextView.LinkHit("https://old.example", TextRange(0, 4))
                val first = clickableSpans(registry.applyTo("打开链接", listOf(oldLink))).single()
                val repeated = clickableSpans(registry.applyTo("打开链接", listOf(oldLink))).single()
                assertSame(first, repeated, "the framework span id must remain stable within a revision")
                first.onClick(View(activity))
                assertEquals(listOf("https://old.example"), activated)

                registry.reset()
                val newLink = CjkTextView.LinkHit("https://new.example", TextRange(0, 4))
                val current = clickableSpans(registry.applyTo("打开链接", listOf(newLink))).single()
                assertNotSame(first, current, "a replacement revision must not reuse the stale span id")
                current.onClick(View(activity))
                assertEquals(
                    listOf("https://old.example", "https://new.example"),
                    activated,
                )
            }
        }
    }

    @Test
    fun documentRebindPublishesSelectionOnlyAfterTheNewProjectionIsCommitted() {
        lateinit var view: CjkTextView
        lateinit var surface: CjkTextSurface
        val content = CjkTextContent("相同段落", TextStyle(fontSize = 32f))
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    bindSelectionFragment(0L, content)
                }
                activity.setContentView(
                    CjkTextSurface(activity).apply {
                        surface = this
                        document = CjkSelectionDocument(
                            listOf(
                                CjkSelectionDocumentFragment(0L, content),
                                CjkSelectionDocumentFragment(1L, content),
                            ),
                        )
                        addView(view)
                    },
                )
            }
            waitForIdle()
            scenario.onActivity {
                assertNotNull(view.layoutResult, "the paragraph must be laid out before selection")
                assertTrue(surface.requestFocus(), "the document surface must accept selection focus")
                assertTrue(view.setSelection(1, 3), "the bound paragraph must belong to the document")
                assertEquals(TextRange(1, 3), view.selection)
            }
            waitForIdle()

            val event = InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeAndWaitForEvent(
                    { scenario.onActivity { view.bindSelectionFragment(1L, content) } },
                    { candidate ->
                        candidate.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED &&
                            candidate.className == TextView::class.java.name
                    },
                    3_000,
                )
            try {
                val node = view.createAccessibilityNodeInfo()
                assertNull(view.selection)
                assertEquals(node.textSelectionStart, event.fromIndex)
                assertEquals(node.textSelectionEnd, event.toIndex)
                assertEquals(0, event.fromIndex)
                assertEquals(0, event.toIndex)
            } finally {
                event.recycle()
            }
        }
    }

    @Test
    fun standaloneFragmentIdentityDoesNotRetainThePreviousVisualSelection() {
        val content = CjkTextContent("相同段落", TextStyle(fontSize = 32f))
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            lateinit var view: CjkTextView
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    bindSelectionFragment(0L, content)
                }
                activity.setContentView(view)
            }
            waitForIdle()
            scenario.onActivity {
                assertTrue(view.setSelection(1, 3))
                assertEquals(TextRange(1, 3), view.selection)

                view.bindSelectionFragment(1L, content)

                assertNull(view.selection)
                val node = view.createAccessibilityNodeInfo()
                assertEquals(0, node.textSelectionStart)
                assertEquals(0, node.textSelectionEnd)
            }
        }
    }

    @Test
    fun recycledHolderIdentityResetsAccessibilityCursorEvenWhenTextIsIdentical() {
        lateinit var recycler: RecyclerView
        lateinit var adapter: SameTextParagraphAdapter
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val content = CjkTextContent("相同段落", TextStyle(fontSize = 32f))
                adapter = SameTextParagraphAdapter(List(48) { content })
                recycler = RecyclerView(activity).apply {
                    layoutManager = LinearLayoutManager(activity)
                    this.adapter = adapter
                    setItemViewCacheSize(0)
                }
                val surface = CjkTextSurface(activity).apply {
                    document = CjkSelectionDocument(
                        List(48) { index -> CjkSelectionDocumentFragment(index.toLong(), content) },
                    )
                    addView(
                        recycler,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            160,
                        ),
                    )
                }
                activity.setContentView(surface)
            }
            waitForIdle()

            listOf(10, 20, 30, 40).forEach { position ->
                scenario.onActivity {
                    val visible = recycler.visibleTextViews()
                    assertTrue(visible.isNotEmpty())
                    visible.forEach { view ->
                        adapter.markAccessibilityCursor(view)
                        assertTrue(
                            view.performAccessibilityAction(
                                AccessibilityNodeInfo.ACTION_SET_SELECTION,
                                selectionArguments(2, 2),
                            ),
                        )
                        assertEquals(2, view.createAccessibilityNodeInfo().textSelectionStart)
                    }
                    recycler.scrollToPosition(position)
                }
                waitForIdle()
            }

            scenario.onActivity {
                assertTrue(
                    adapter.reboundAccessibilitySelections.isNotEmpty(),
                    "the fixture must rebind at least one holder carrying an accessibility cursor",
                )
                adapter.reboundAccessibilitySelections.forEach { selection ->
                    assertEquals(0, selection.first)
                    assertEquals(0, selection.second)
                }
                recycler.visibleTextViews().forEach { view ->
                    assertTrue(
                        adapter.boundKeys(view).isNotEmpty(),
                        "every visible paragraph must retain a stable document identity",
                    )
                }
            }
        }
    }

    private fun assertSelection(
        native: TextView,
        cjk: CjkTextView,
        expectedStart: Int,
        expectedEnd: Int,
    ) {
        val nativeNode = native.createAccessibilityNodeInfo()
        val cjkNode = cjk.createAccessibilityNodeInfo()
        assertEquals(expectedStart, nativeNode.textSelectionStart)
        assertEquals(expectedEnd, nativeNode.textSelectionEnd)
        assertEquals(nativeNode.textSelectionStart, cjkNode.textSelectionStart)
        assertEquals(nativeNode.textSelectionEnd, cjkNode.textSelectionEnd)
    }

    private fun assertSameAccessibilitySelection(
        native: TextView,
        cjk: CjkTextView,
        granularity: Int,
        direction: String,
    ) {
        val nativeNode = native.createAccessibilityNodeInfo()
        val cjkNode = cjk.createAccessibilityNodeInfo()
        assertEquals(
            nativeNode.textSelectionStart,
            cjkNode.textSelectionStart,
            "$direction start mismatch for granularity $granularity",
        )
        assertEquals(
            nativeNode.textSelectionEnd,
            cjkNode.textSelectionEnd,
            "$direction end mismatch for granularity $granularity",
        )
    }

    private fun AccessibilityNodeInfo.hasAction(action: Int): Boolean =
        actionList.any { it.id == action }

    private fun clickableSpans(text: CharSequence): Array<ClickableSpan> =
        (text as Spanned).getSpans(0, text.length, ClickableSpan::class.java)

    private fun RecyclerView.visibleTextViews(): List<CjkTextView> =
        List(childCount) { index -> getChildAt(index) as CjkTextView }

    private fun waitForIdle() = InstrumentationRegistry.getInstrumentation().waitForIdleSync()

    private fun selectionArguments(start: Int, end: Int): Bundle = Bundle().apply {
        putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, start)
        putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, end)
    }

    private fun movementArguments(granularity: Int, extend: Boolean): Bundle = Bundle().apply {
        putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_MOVEMENT_GRANULARITY_INT, granularity)
        putBoolean(AccessibilityNodeInfo.ACTION_ARGUMENT_EXTEND_SELECTION_BOOLEAN, extend)
    }

    private fun characterLocationArguments(start: Int, length: Int): Bundle = Bundle().apply {
        putInt(AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_ARG_START_INDEX, start)
        putInt(AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_ARG_LENGTH, length)
    }

    private fun exactly(size: Int): Int =
        View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)

    private fun atMost(size: Int): Int =
        View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.AT_MOST)

    private data class GranularityFixture(
        val source: String,
        val granularity: Int,
        val initialCursor: Int = 1,
    )

    private class SameTextParagraphAdapter(
        private val contents: List<CjkTextContent>,
    ) : RecyclerView.Adapter<SameTextParagraphHolder>() {
        private val boundKeysByView = mutableMapOf<CjkTextView, MutableSet<Long>>()
        private val accessibilityCursorViews = mutableSetOf<CjkTextView>()
        val reboundAccessibilitySelections = mutableListOf<Pair<Int, Int>>()

        init {
            setHasStableIds(true)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SameTextParagraphHolder =
            SameTextParagraphHolder(
                CjkTextView(parent.context).apply {
                    layoutParams = RecyclerView.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    )
                },
            )

        override fun onBindViewHolder(holder: SameTextParagraphHolder, position: Int) {
            val key = getItemId(position)
            val recordsRebind = holder.view in accessibilityCursorViews &&
                boundKeysByView[holder.view]?.let { key !in it } == true
            boundKeysByView.getOrPut(holder.view) { mutableSetOf() } += key
            holder.view.bindSelectionFragment(key, contents[position])
            if (recordsRebind) {
                val node = holder.view.createAccessibilityNodeInfo()
                reboundAccessibilitySelections += node.textSelectionStart to node.textSelectionEnd
                accessibilityCursorViews -= holder.view
            }
        }

        override fun onViewRecycled(holder: SameTextParagraphHolder) {
            holder.view.unbindSelectionFragment()
        }

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getItemCount(): Int = contents.size

        fun markAccessibilityCursor(view: CjkTextView) {
            accessibilityCursorViews += view
        }

        fun boundKeys(view: CjkTextView): Set<Long> = boundKeysByView[view].orEmpty()
    }

    private class SameTextParagraphHolder(val view: CjkTextView) : RecyclerView.ViewHolder(view)
}
