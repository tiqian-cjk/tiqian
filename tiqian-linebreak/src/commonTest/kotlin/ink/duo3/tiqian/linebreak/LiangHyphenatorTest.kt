package ink.duo3.tiqian.linebreak

import kotlin.test.Test
import kotlin.test.assertEquals

class LiangHyphenatorTest {
    @Test
    fun noHyphenatorYieldsNoOpportunities() {
        assertEquals(emptyList(), NoHyphenator.hyphenate("international"))
    }

    @Test
    fun oddLevelGapBecomesABreakOutsideTheMargins() {
        // Pattern "1c": level 1 (odd) in the gap before any 'c'. With
        // leftMin/rightMin = 1, "abc" breaks before the final c (ab-c); a 'c'
        // at the very start is excluded by the left margin.
        val h = LiangHyphenator(mapOf("c" to intArrayOf(1, 0)), leftMin = 1, rightMin = 1)
        assertEquals(listOf(2), h.hyphenate("abc"))
        assertEquals(emptyList(), h.hyphenate("cab"))
    }

    @Test
    fun maxLevelWinsAndEvenForbidsTheBreak() {
        // "ab" puts an odd level (1) in the a|b gap ⇒ "ab" breaks there. A longer
        // "zab" pattern raises that same gap to an even level (2); the max wins
        // and even parity forbids the break ⇒ "zab" has no opportunity.
        val h = LiangHyphenator(
            mapOf("ab" to intArrayOf(0, 1, 0), "zab" to intArrayOf(0, 0, 2, 0)),
            leftMin = 1,
            rightMin = 1,
        )
        assertEquals(listOf(1), h.hyphenate("ab"))
        assertEquals(emptyList(), h.hyphenate("zab"))
    }

    @Test
    fun marginsAndShortWordsAreRespected() {
        val h = LiangHyphenator(mapOf("a" to intArrayOf(1, 0)), leftMin = 2, rightMin = 3)
        assertEquals(emptyList(), h.hyphenate("the")) // shorter than leftMin+rightMin
    }

    @Test
    fun exceptionsOverridePatternsAndAreCaseInsensitive() {
        val h = LiangHyphenator(
            patterns = emptyMap(),
            exceptions = mapOf("table" to listOf(2)),
            leftMin = 1,
            rightMin = 1,
        )
        assertEquals(listOf(2), h.hyphenate("table"))
        assertEquals(listOf(2), h.hyphenate("Table"))
    }

    @Test
    fun parsesPatternsAndExceptionBlocksStrippingComments() {
        val (patterns, exceptions) = parseTexHyphenationPatterns(
            """
            % a comment line
            \patterns{ % inline comment
            .ach4
            a5bal
            }
            \hyphenation{
            ta-ble
            present
            }
            """.trimIndent(),
        )
        assertEquals(listOf(0, 0, 0, 0, 4), patterns[".ach"]!!.toList())
        assertEquals(listOf(0, 5, 0, 0, 0), patterns["abal"]!!.toList())
        assertEquals(listOf(2), exceptions["table"])
        assertEquals(emptyList(), exceptions["present"]) // listed = never hyphenate
    }
}
