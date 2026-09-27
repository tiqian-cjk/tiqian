package org.tiqian.core

import kotlin.test.Test
import org.tiqian.test.trace.assertEquals
import org.tiqian.test.trace.assertFailsWith
import kotlin.test.AfterTest
import org.tiqian.test.trace.TestTraceRecorder

class TextRangeTest {
    private val testTrace = TestTraceRecorder("TextRangeTest")

    @Test
    fun exposesLength() {
        testTrace.section("exposesLength")
        assertEquals(3, TextRange(2, 5).length)
    }

    @Test
    fun rejectsNegativeStart() {
        testTrace.section("rejectsNegativeStart")
        assertFailsWith<TiqianIllegalArgumentException> {
            TextRange(-1, 1)
        }
    }

    @AfterTest
    fun flushTestTrace() {
        testTrace.flush()
    }
}

