package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals

class DecideHyphenBreakTest {
    private fun cluster(start: Int, advance: Float) =
        Cluster(range = TextRange(start, start + 1), text = "x", fontKey = "k", advance = advance)

    // [CJK16][CJK16][Latin32] | word(syll32, syll32). Whole-word line = first 3
    // clusters (width 64); at lineLimit 74 the deficit is 10 over a single CJK
    // gap (idx 1).
    private val clusters =
        listOf(cluster(0, 16f), cluster(1, 16f), cluster(2, 32f), cluster(3, 32f), cluster(4, 32f))

    @Test
    fun chargesAllDeficitToCjkWhenNoSinoWesternCapacityIsKnown() {
        // 10 / 1 gap = 10 > 8 ⇒ too loose ⇒ hyphenate (break at the overflow, 4).
        assertEquals(
            4,
            decideHyphenBreak(
                lineStart = 0, overflowAt = 4, adjustedClusters = clusters, lineLimit = 74f,
                hyphenBreakClusters = setOf(4), cjkInterCharBoundaries = setOf(1), maxCjkStretchPerGap = 8f,
            ),
        )
    }

    @Test
    fun discountsSinoWesternCapacityBeforeChargingCjkLooseness() {
        // The CJK↔Latin gap (idx 2) absorbs 4 first ⇒ cjkDeficit 6 ≤ 8 ⇒ not too
        // loose ⇒ wrap the word whole (break at the whole-word end, 3).
        assertEquals(
            3,
            decideHyphenBreak(
                lineStart = 0, overflowAt = 4, adjustedClusters = clusters, lineLimit = 74f,
                hyphenBreakClusters = setOf(4), cjkInterCharBoundaries = setOf(1), maxCjkStretchPerGap = 8f,
                sinoWesternBoundaries = setOf(2), sinoWesternStretchCap = 4f,
            ),
        )
    }
}
