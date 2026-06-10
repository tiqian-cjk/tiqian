package ink.duo3.tiqian.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class TextRangeTest {
    @Test
    fun exposesLength() {
        assertEquals(3, TextRange(2, 5).length)
    }

    @Test
    fun rejectsNegativeStart() {
        assertFailsWith<IllegalArgumentException> {
            TextRange(-1, 1)
        }
    }
}

