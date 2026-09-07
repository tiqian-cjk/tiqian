package org.tiqian.core

import org.tiqian.core.TiqianIllegalArgumentException

import kotlin.test.Test
import org.tiqian.test.trace.assertEquals
import org.tiqian.test.trace.assertFailsWith
import org.tiqian.test.trace.assertTrue
import kotlin.test.AfterTest
import org.tiqian.test.trace.TestTraceRecorder

class CoreUnitsGeometryTest {
    private val testTrace = TestTraceRecorder("CoreUnitsGeometryTest")


    // === Units.kt ===

    @Test
    fun icPlusReturnsSum() {
        testTrace.section("icPlusReturnsSum")
        assertEquals(Ic(5.0f), Ic(2.0f) + Ic(3.0f))
    }

    @Test
    fun icUnaryMinusReturnsNegated() {
        testTrace.section("icUnaryMinusReturnsNegated")
        assertEquals(Ic(-3.0f), -Ic(3.0f))
    }

    @Test
    fun floatIcExtensionCreatesIc() {
        testTrace.section("floatIcExtensionCreatesIc")
        assertEquals(Ic(2f), 2f.ic)
    }

    @Test
    fun intIcExtensionCreatesIc() {
        testTrace.section("intIcExtensionCreatesIc")
        assertEquals(Ic(5.0f), 5.ic)
    }

    @Test
    fun icToPxMultipliesByEmSize() {
        testTrace.section("icToPxMultipliesByEmSize")
        assertEquals(24.0f, Ic(3.0f).toPx(8.0f))
    }

    // === Geometry.kt ===

    @Test
    fun rectHeightReturnsDifference() {
        testTrace.section("rectHeightReturnsDifference")
        assertEquals(20.0f, Rect(0.0f, 0.0f, 10.0f, 20.0f).height)
    }

    @Test
    fun rectWidthReturnsDifference() {
        testTrace.section("rectWidthReturnsDifference")
        assertEquals(10.0f, Rect(0.0f, 0.0f, 10.0f, 20.0f).width)
    }

    @Test
    fun textRangeRejectsStartGreaterThanEnd() {
        testTrace.section("textRangeRejectsStartGreaterThanEnd")
        assertFailsWith<TiqianIllegalArgumentException> {
            TextRange(5, 2)
        }
    }

    @Test
    fun textRangeRejectsNegativeStart() {
        testTrace.section("textRangeRejectsNegativeStart")
        assertFailsWith<TiqianIllegalArgumentException> {
            TextRange(-1, 1)
        }
    }

    @Test
    fun layoutConstraintsRejectsNonPositiveMaxWidth() {
        testTrace.section("layoutConstraintsRejectsNonPositiveMaxWidth")
        assertFailsWith<TiqianIllegalArgumentException> {
            LayoutConstraints(maxWidth = -1.0f)
        }
    }

    @Test
    fun layoutConstraintsRejectsNonPositiveMaxHeight() {
        testTrace.section("layoutConstraintsRejectsNonPositiveMaxHeight")
        assertFailsWith<TiqianIllegalArgumentException> {
            LayoutConstraints(maxWidth = 100.0f, maxHeight = -1.0f)
        }
    }

    @Test
    fun layoutConstraintsRejectsNonPositiveMaxLines() {
        testTrace.section("layoutConstraintsRejectsNonPositiveMaxLines")
        assertFailsWith<TiqianIllegalArgumentException> {
            LayoutConstraints(maxWidth = 100.0f, maxHeight = 100.0f, maxLines = 0)
        }
    }

    // === LayoutModel.kt ===

    @Test
    fun maxLinesDecisionInfoRecordsTruncationDetails() {
        testTrace.section("maxLinesDecisionInfoRecordsTruncationDetails")
        val info = MaxLinesDecisionInfo(
            laidOutLines = 5,
            visibleLines = 3,
            reason = "MaxLinesLineTruncation",
        )
        assertEquals(5, info.laidOutLines)
        assertEquals(3, info.visibleLines)
        assertEquals("MaxLinesLineTruncation", info.reason)
    }

    @Test
    fun layoutDebugInfoAcceptsMaxLinesDecision() {
        testTrace.section("layoutDebugInfoAcceptsMaxLinesDecision")
        val debug = LayoutDebugInfo(
            maxLinesDecision = MaxLinesDecisionInfo(
                laidOutLines = 5,
                visibleLines = 3,
            ),
        )
        assertEquals(5, debug.maxLinesDecision?.laidOutLines)
        assertEquals(3, debug.maxLinesDecision?.visibleLines)
    }

    @AfterTest
    fun flushTestTrace() {
        testTrace.flush()
    }
}