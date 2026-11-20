package org.tiqian.android.view

import android.app.Instrumentation
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.ActionMode
import android.view.InputDevice
import android.view.KeyEvent
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.Magnifier
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.android.rendering.AndroidParagraphMeasurer
import org.tiqian.android.rendering.AndroidParagraphMeasurementSession
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.cursorRect
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.selectionWordRangeForPosition
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.android.AndroidTypefaceResolver
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class CjkTextViewInstrumentedTest {
    @Test
    fun viewMeasuresAndPaintsFromOneLayoutResult() {
        launchView("提椠的 Android View 前端会复用同一份排版结果。") { view ->
            assertNotNull(view.layoutResult)
            assertEquals(280f, view.layoutResult?.input?.constraints?.maxWidth)

            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))

            var painted = 0
            for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                if (Color.alpha(bitmap.getPixel(x, y)) > 0) painted++
            }
            assertTrue(painted > 100, "expected native Canvas glyph pixels, got $painted")
        }
    }

    @Test
    fun measurementSessionTypefaceResolverDrivesMeasureAndReplay() {
        val resolver = RecordingTypefaceResolver()
        val session = AndroidParagraphMeasurementSession(typefaceResolver = resolver)
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val view = CjkTextView(activity).apply {
                    setMeasurementSession(session)
                    content = CjkTextContent(
                        text = "宿主字体 Host font",
                        textStyle = TextStyle(
                            fontFamilies = listOf("host-reader-font"),
                            fontSize = 32f,
                        ),
                    )
                }
                activity.setContentView(view)
                measureAndLayout(view, 280)

                assertTrue(resolver.shapingCalls > 0)
                assertTrue(resolver.requestedFamilies.all { it == listOf("host-reader-font") })
                val roleCallsAfterMeasure = resolver.roleCalls
                view.draw(Canvas(Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)))
                assertTrue(resolver.roleCalls > roleCallsAfterMeasure)
            }
        }
    }

    @Test
    fun paintOnlyUpdateKeepsLayoutIdentityButFontUpdateInvalidatesIt() {
        launchView("甲乙丙丁") { view ->
            val first = assertNotNull(view.layoutResult)

            view.content = view.content.copy(textColor = Color.RED)
            assertSame(first, view.layoutResult)

            view.content = view.content.copy(
                textStyle = view.content.textStyle.copy(fontSize = view.content.textStyle.fontSize + 2f),
            )
            assertEquals(null, view.layoutResult)
            measureAndLayout(view, 280)
            assertTrue(first !== view.layoutResult)
        }
    }

    @Test
    fun precomputedLayoutRequiresExactProfileAndConstraints() {
        val content = CjkTextContent("简繁区域策略不能靠字形猜测", TextStyle(fontSize = 32f))
        val input = content.layoutInput(maxWidth = 280f)
        val mainland = AndroidParagraphMeasurer(ClreqProfile.MainlandHorizontal).precompute(input)
        val taiwan = AndroidParagraphMeasurer(ClreqProfile.TaiwanHorizontal).precompute(input)
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val view = CjkTextView(activity).apply { this.content = content }

                assertTrue(view.submitPrecomputedLayout(mainland))
                view.clreqProfile = ClreqProfile.TaiwanHorizontal
                assertFalse(view.submitPrecomputedLayout(mainland))
                assertTrue(view.submitPrecomputedLayout(taiwan))
                activity.setContentView(view)
                measureAndLayout(view, 280)
                assertSame(taiwan.result, view.layoutResult)
            }
        }
    }

    @Test
    fun accessibilityUsesSourceTextSelectionAndCharacterGeometry() {
        launchView("提椠原文") { view ->
            measureAndLayout(view.parent as FrameLayout, 300)
            assertTrue(view.requestFocus())
            assertTrue(view.setSelection(0, 2))
            val node = view.createAccessibilityNodeInfo()
            assertEquals("提椠原文", node.text.toString())
            assertEquals(0, node.textSelectionStart)
            assertEquals(2, node.textSelectionEnd)
            assertTrue(
                node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_COPY },
                "non-empty source selection must publish copy",
            )

            if (Build.VERSION.SDK_INT >= 26) {
                val arguments = Bundle().apply {
                    putInt(AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_ARG_START_INDEX, 0)
                    putInt(AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_ARG_LENGTH, 2)
                }
                view.addExtraDataToAccessibilityNodeInfo(
                    node,
                    AccessibilityNodeInfo.EXTRA_DATA_TEXT_CHARACTER_LOCATION_KEY,
                    arguments,
                )
                val locations = characterLocations(node.extras)
                assertEquals(2, locations?.size)
                assertTrue(locations?.all { it is RectF } == true)
            }
        }
    }

    @Test
    fun hostsCannotInjectChildrenPastTheInlineAdapter() {
        launchView("段落子树只属于行内对象") { view ->
            assertFailsWith<IllegalStateException> { view.addView(View(view.context)) }
        }
    }

    @Test
    fun linksAndInlineChildrenUseEngineOccupiedGeometry() {
        val source = "前链后\uFFFC"
        val linkRange = TextRange(1, 2)
        val objectRange = TextRange(3, 4)
        val content = CjkTextContent(
            content = org.tiqian.core.TiqianTextContent(source),
            textStyle = TextStyle(fontSize = 32f),
            richTextSpans = listOf(RichTextSpan(linkRange, Link("tiqian://link"))),
            inlineObjects = listOf(InlineObjectSpan(objectRange, advance = 24f, ascent = 18f, descent = 6f)),
        )
        launchView(content) { view ->
            var target: String? = null
            view.onLinkClickListener = CjkLinkClickListener { _, value, _, _ ->
                target = value
                true
            }
            val link = view.layoutResult?.getBoundingBoxes(linkRange)?.firstOrNull()
            assertNotNull(link)
            val hit = view.linkAt(view.toVisibleX(link.left + 1f), view.toVisibleY(link.top + 1f))
            assertNotNull(hit)
            assertTrue(view.activateLink(hit))
            assertEquals("tiqian://link", target)

            assertEquals(1, view.childCount)
            val child = view.getChildAt(0)
            assertEquals(24, child.measuredWidth)
            assertEquals(24, child.measuredHeight)
            assertEquals(View.VISIBLE, child.visibility)
        }
    }

    @Test
    fun longPressUsesEngineWordBoundaryAndStartsTouchSelection() {
        lateinit var view: CjkTextView
        lateinit var point: Pair<Float, Float>
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent("提椠原生选择", TextStyle(fontSize = 42f))
                }
                activity.setContentView(view)
                measureAndLayout(view, 360)
                val box = assertNotNull(view.layoutResult?.getBoundingBoxes(TextRange(0, 1))?.firstOrNull())
                point = view.toVisibleX((box.left + box.right) / 2f) to
                    view.toVisibleY((box.top + box.bottom) / 2f)
            }
            val (x, y) = point
            val downTime = SystemClock.uptimeMillis()
            scenario.onActivity {
                assertTrue(view.dispatchTouchEvent(pointerEvent(downTime, downTime, MotionEvent.ACTION_DOWN, x, y)))
            }
            SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 150L)
            scenario.onActivity {
                assertTrue(
                    view.dispatchTouchEvent(
                        pointerEvent(downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y),
                    ),
                )
                assertEquals(TextRange(0, 1), view.selection)
                assertTrue(view.selectionHandlesShowing, "touch selection must float window-level handles")
            }
        }
    }

    @Test
    fun siblingCjkSelectionsFollowNativeFocusOwnership() {
        val native = runSiblingNativeSelectionScenario()
        assertNotNull(native.secondSelection, "native TextView sibling must retain its selection")
        assertFalse(native.firstFocused, "the first native TextView must lose focus")
        assertTrue(native.secondFocused, "the second native TextView must own focus")

        val cjk = runSiblingCjkSelectionScenario()
        assertEquals(native.secondSelection, cjk.secondSelection, "native=$native cjk=$cjk")
        assertEquals(native.firstFocused, cjk.firstFocused, "native=$native cjk=$cjk")
        assertEquals(native.secondFocused, cjk.secondFocused, "native=$native cjk=$cjk")

        assertFalse(cjk.firstHandlesShowing, "the first CjkTextView must dismiss its handles")
        assertNotNull(cjk.secondSelection, "the second CjkTextView must expose its selected word")
        assertTrue(cjk.secondHandlesShowing, "the focused CjkTextView must expose its handles")
        assertTrue(
            cjk.firstSelectionColorPixelsAfterFirst > 0,
            "the first CjkTextView must paint its selection while focused",
        )
        assertEquals(
            0,
            cjk.firstSelectionColorPixelsAfterSecond,
            "the first CjkTextView must stop painting selection when focus moves to its sibling",
        )
    }

    @Test
    fun longPressMoveExtendsByWordBeforeUpAndRestoresHandlesAfterRelease() {
        lateinit var view: CjkTextView
        lateinit var down: Pair<Float, Float>
        lateinit var target: Pair<Float, Float>
        val source = "alpha beta gamma"
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 42f))
                }
                activity.setContentView(FrameLayout(activity).apply {
                    addView(
                        view,
                        FrameLayout.LayoutParams(360, FrameLayout.LayoutParams.WRAP_CONTENT),
                    )
                })
                measureAndLayout(view, 360)
                down = visibleCenter(view, TextRange(0, 1))
                target = visibleCenter(view, TextRange(11, 12))
                val snapshot = assertNotNull(view.layoutSnapshot)
                assertEquals(
                    TextRange(11, source.length),
                    snapshot.replayIndex.selectionWordRangeForPosition(
                        snapshot.result,
                        view.toContentX(target.first),
                        view.toContentY(target.second),
                    ),
                )
            }

            val downTime = SystemClock.uptimeMillis()
            scenario.onActivity {
                assertTrue(view.dispatchTouchEvent(pointerEvent(downTime, downTime, MotionEvent.ACTION_DOWN, down)))
            }
            SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 150L)
            scenario.onActivity {
                // AOSP's long-press accelerator selects the word first, then keeps the same
                // gesture alive so a subsequent move expands by whole words.
                assertEquals(TextRange(0, 5), view.selection)
                assertFalse(view.selectionHandlesShowing, "handles stay hidden after long-press ownership")
                val moveTime = SystemClock.uptimeMillis()
                assertTrue(view.dispatchTouchEvent(pointerEvent(downTime, moveTime, MotionEvent.ACTION_MOVE, target)))
                assertEquals(TextRange(0, source.length), view.selection)
                assertFalse(view.selectionHandlesShowing, "handles stay hidden while word-dragging")

                val upTime = SystemClock.uptimeMillis()
                assertTrue(view.dispatchTouchEvent(pointerEvent(downTime, upTime, MotionEvent.ACTION_UP, target)))
                assertEquals(TextRange(0, source.length), view.selection)
                assertTrue(view.selectionHandlesShowing, "handles return after the gesture ends")
            }
        }
    }

    @Test
    fun cancellingWordDragPreservesSelectionAndDoesNotShowToolbar() {
        lateinit var view: CjkTextView
        lateinit var point: Pair<Float, Float>
        val source = "alpha beta gamma"
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 42f))
                }
                activity.setContentView(view)
                measureAndLayout(view, 360)
                point = visibleCenter(view, TextRange(0, 1))
            }

            val downTime = SystemClock.uptimeMillis()
            scenario.onActivity {
                assertTrue(view.dispatchTouchEvent(pointerEvent(downTime, downTime, MotionEvent.ACTION_DOWN, point)))
            }
            SystemClock.sleep(ViewConfiguration.getLongPressTimeout().toLong() + 150L)
            scenario.onActivity {
                assertEquals(TextRange(0, 5), view.selection)
                val cancelTime = SystemClock.uptimeMillis()
                assertTrue(
                    view.dispatchTouchEvent(
                        pointerEvent(downTime, cancelTime, MotionEvent.ACTION_CANCEL, point),
                    ),
                )
                assertEquals(TextRange(0, 5), view.selection)
                assertTrue(view.selectionHandlesShowing, "handles return after a cancelled gesture")
                assertNull(actionModeForTesting(view), "a cancelled gesture must not show the toolbar")
            }
        }
    }

    @Test
    fun programmaticSelectionRemainsOrderedAndRejectsCollapsedRange() {
        launchView("甲乙丙") { view ->
            assertTrue(view.setSelection(3, 1))
            assertEquals(TextRange(1, 3), view.selection)

            assertFalse(view.setSelection(2, 2))
            assertEquals(null, view.selection)
        }
    }

    @Test
    fun selectionHandlePopupIsTouchableAndDeliversWindowPointerEvents() {
        lateinit var view: CjkTextView
        lateinit var popup: CjkSelectionHandlePopup
        val started = AtomicBoolean(false)
        val moved = AtomicInteger(0)
        val finished = AtomicBoolean(false)
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent("popup handle", TextStyle(fontSize = 32f))
                }
                activity.setContentView(view)
                measureAndLayout(view, 300)
                val drawable = GradientDrawable().apply {
                    setColor(Color.BLUE)
                    setSize(24, 24)
                }
                popup = CjkSelectionHandlePopup(
                    host = view,
                    handle = CjkSelectionHandle.Start,
                    drawable = drawable,
                    listener = object : CjkSelectionHandleListener {
                        private val position = object : CjkSelectionHandlePosition {}

                        override fun currentPosition(handle: CjkSelectionHandle): CjkSelectionHandlePosition =
                            position

                        override fun onHandleDragStarted(handle: CjkSelectionHandle) {
                            started.set(true)
                        }

                        override fun onHandleDragMoved(
                            handle: CjkSelectionHandle,
                            viewX: Float,
                            viewY: Float,
                            rawX: Float,
                            rawY: Float,
                            fromTouchScreen: Boolean,
                        ): CjkSelectionHandlePosition {
                            moved.incrementAndGet()
                            assertTrue(fromTouchScreen)
                            return position
                        }

                        override fun onHandleDragFinished(
                            handle: CjkSelectionHandle,
                            filteredPosition: CjkSelectionHandlePosition?,
                            cancelled: Boolean,
                        ) {
                            finished.set(!cancelled)
                        }
                    },
                )
                // Keep the 40dp minimum touch target fully on-screen. A start handle intentionally
                // extends mostly to the left of its caret, just like Editor.HandleView.
                popup.showAtCaret(view.toVisibleX(200f), view.toVisibleY(32f))
            }

            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync()
            val bounds = Rect()
            scenario.onActivity {
                assertTrue(popup.boundsOnScreen(bounds))
                assertTrue(bounds.width() > 0)
                assertTrue(bounds.height() > 0)
            }
            val x = bounds.exactCenterX()
            val y = bounds.exactCenterY()
            val downTime = SystemClock.uptimeMillis()
            sendPointerSync(instrumentation, downTime, downTime, MotionEvent.ACTION_DOWN, x, y)
            sendPointerSync(instrumentation, downTime, downTime + 32L, MotionEvent.ACTION_MOVE, x + 8f, y + 8f)
            sendPointerSync(instrumentation, downTime, downTime + 64L, MotionEvent.ACTION_UP, x + 8f, y + 8f)
            instrumentation.waitForIdleSync()

            assertTrue(started.get(), "a touchable popup must receive ACTION_DOWN")
            assertTrue(moved.get() > 0, "a touchable popup must receive ACTION_MOVE")
            assertTrue(finished.get(), "a touchable popup must receive ACTION_UP")
            scenario.onActivity { popup.dismiss() }
        }
    }

    @Test
    fun integratedEndHandleDragCannotCrossTheStartByMoreThanOneUnit() {
        lateinit var view: CjkTextView
        val source = "甲乙丙丁"
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent(source, TextStyle(fontSize = 42f))
                }
                activity.setContentView(view)
                measureAndLayout(view, 300)
                assertTrue(view.requestFocus())
                assertTrue(view.setSelection(1, 3))
            }

            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync()
            val startBounds = Rect()
            val endBounds = Rect()
            scenario.onActivity {
                assertTrue(view.selectionHandleBoundsOnScreen(CjkSelectionHandle.Start, startBounds))
                assertTrue(view.selectionHandleBoundsOnScreen(CjkSelectionHandle.End, endBounds))
            }

            // Drag the end handle onto the start handle. TextView keeps one interaction unit
            // selected and clamps the dragged endpoint instead of allowing the handles to cross.
            val downTime = SystemClock.uptimeMillis()
            sendPointerSync(
                instrumentation,
                downTime,
                downTime,
                MotionEvent.ACTION_DOWN,
                endBounds.exactCenterX(),
                endBounds.exactCenterY(),
            )
            sendPointerSync(
                instrumentation,
                downTime,
                downTime + 32L,
                MotionEvent.ACTION_MOVE,
                startBounds.exactCenterX(),
                startBounds.exactCenterY(),
            )
            sendPointerSync(
                instrumentation,
                downTime,
                downTime + 64L,
                MotionEvent.ACTION_UP,
                startBounds.exactCenterX(),
                startBounds.exactCenterY(),
            )
            instrumentation.waitForIdleSync()

            scenario.onActivity {
                val selection = assertNotNull(view.selection)
                assertEquals(TextRange(1, 2), selection)
            }
        }
    }

    @Test
    fun crossedEndHandleKeepsTrackingXOnTheFixedEndpointsLine() {
        lateinit var view: CjkTextView
        lateinit var listener: CjkSelectionHandleListener
        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                view = CjkTextView(activity).apply {
                    content = CjkTextContent(
                        "甲乙丙丁戊己庚辛壬癸子丑寅卯",
                        TextStyle(fontSize = 42f),
                    )
                }
                activity.setContentView(view)
                measureAndLayout(view, 180)
                val snapshot = assertNotNull(view.layoutSnapshot)
                assertTrue(snapshot.result.lines.size >= 3)
                val fixedLine = snapshot.result.lines[1]
                val laterLine = snapshot.result.lines[2]
                val start = fixedLine.range.start
                val projected = (fixedLine.range.end - 1).coerceAtLeast(start + 2)
                val end = laterLine.range.end
                assertTrue(projected in (start + 2) until end)
                assertTrue(view.requestFocus())
                assertTrue(view.setSelection(start, end))
                listener = assertNotNull(
                    readPrivateField(view, "selectionController") as? CjkSelectionHandleListener,
                )

                val targetX = view.toVisibleX(
                    snapshot.replayIndex.cursorRect(snapshot.result, projected).left,
                )
                val crossedLine = snapshot.result.lines.first()
                val targetY = view.toVisibleY((crossedLine.top + crossedLine.bottom) / 2f)
                listener.onHandleDragStarted(CjkSelectionHandle.End)
                listener.onHandleDragMoved(
                    CjkSelectionHandle.End,
                    targetX,
                    targetY,
                    Float.NaN,
                    Float.NaN,
                    false,
                )
                listener.onHandleDragFinished(CjkSelectionHandle.End, null, cancelled = true)
                val accepted = assertNotNull(view.selection).end

                assertTrue(
                    accepted > start + 1,
                    "crossed-line x must remain responsive instead of freezing at the minimum range",
                )
                assertTrue(accepted <= fixedLine.range.end)
                assertEquals(TextRange(start, accepted), view.selection)
            }
        }
    }

    @Test
    fun magnifierFactoryUsesThePublicTextDefaultConfiguration() {
        if (Build.VERSION.SDK_INT < 28) return

        ActivityScenario.launch(CjkTextViewTestActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val view = CjkTextView(activity).apply {
                    content = CjkTextContent("甲乙丙丁", TextStyle(fontSize = 42f))
                }
                activity.setContentView(view)
                measureAndLayout(view, 300)
                val actual = createTextDefaultMagnifier(view)
                @Suppress("DEPRECATION")
                val expected = Magnifier(view)
                try {
                    // Magnifier(View) is the public TextView-compatible default path. In
                    // particular it carries the themed overlay and clipping policy that a bare
                    // Magnifier.Builder(view).build() does not provide.
                    assertEquals(expected.width, actual.width)
                    assertEquals(expected.height, actual.height)
                    assertEquals(expected.sourceWidth, actual.sourceWidth)
                    assertEquals(expected.sourceHeight, actual.sourceHeight)
                    assertEquals(expected.zoom, actual.zoom)
                    assertEquals(expected.elevation, actual.elevation)
                    assertEquals(expected.cornerRadius, actual.cornerRadius)
                    assertEquals(
                        expected.isClippingEnabled(),
                        actual.isClippingEnabled(),
                    )
                    assertEquals(
                        expected.defaultHorizontalSourceToMagnifierOffset,
                        actual.defaultHorizontalSourceToMagnifierOffset,
                    )
                    assertEquals(
                        expected.defaultVerticalSourceToMagnifierOffset,
                        actual.defaultVerticalSourceToMagnifierOffset,
                    )
                    assertNotNull(actual.overlay, "text-default magnifier must preserve overlay")
                } finally {
                    actual.dismiss()
                    expected.dismiss()
                }
            }
        }
    }

    @Test
    fun keyboardShortcutsSelectAllAndCopyUseEngineSelection() {
        launchView("硬键盘复制") { view ->
            assertTrue(view.requestFocus())
            assertTrue(view.dispatchKeyShortcutEvent(ctrlKey(KeyEvent.KEYCODE_A)))
            assertEquals(TextRange(0, 5), view.selection)
            assertTrue(view.dispatchKeyShortcutEvent(ctrlKey(KeyEvent.KEYCODE_C)))

            view.textIsSelectable = false
            assertFalse(view.dispatchKeyShortcutEvent(ctrlKey(KeyEvent.KEYCODE_A)))
        }
    }

    @Test
    fun scrollAppliesOnceAcrossDrawLayoutAndHitTesting() {
        val source = "滚动回归\uFFFC"
        val linkRange = TextRange(0, 2)
        val objectRange = TextRange(4, 5)
        val content = CjkTextContent(
            content = org.tiqian.core.TiqianTextContent(source),
            textStyle = TextStyle(fontSize = 32f),
            richTextSpans = listOf(RichTextSpan(linkRange, Link("tiqian://scroll"))),
            inlineObjects = listOf(InlineObjectSpan(objectRange, advance = 24f, ascent = 18f, descent = 6f)),
        )
        launchView(content) { view ->
            val scrollY = -40
            val baseline = view.baseline
            val childTop = view.getChildAt(0).top
            val restingInkTop = scrollContractInkTop(view)

            view.scrollTo(0, scrollY)
            view.requestLayout()
            measureAndLayout(view, 300)

            assertEquals(baseline, view.baseline)
            assertEquals(childTop, view.getChildAt(0).top)
            assertEquals(restingInkTop - scrollY, scrollContractInkTop(view))

            val link = assertNotNull(view.layoutResult?.getBoundingBoxes(linkRange)?.firstOrNull())
            val hit = view.linkAt(
                link.left + 1f + view.paddingLeft,
                link.top + 1f + view.paddingTop - scrollY,
            )
            assertEquals(linkRange, assertNotNull(hit).range)
        }
    }

}
