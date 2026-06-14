package ink.duo3.tiqian.linebreak

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class EnglishHyphenationTest {
    private fun hyphenated(word: String): String {
        val offsets = EnglishHyphenation.enUs.hyphenate(word)
        val sb = StringBuilder()
        for (i in word.indices) {
            if (i in offsets) sb.append('-')
            sb.append(word[i])
        }
        return sb.toString()
    }

    @Test
    fun hyphenatesCommonWordsAtSyllablePoints() {
        assertEquals("hy-phen-ation", hyphenated("hyphenation"))
        // "com-puter", not "com-put-er": rightMin=3 forbids leaving "er" (2).
        assertEquals("com-puter", hyphenated("computer"))
        // in|ter is a stable break; no spurious break inside the first syllable.
        assertTrue(hyphenated("international").startsWith("in-ter"), hyphenated("international"))
    }

    @Test
    fun respectsMarginsAndShortWords() {
        assertEquals(emptyList(), EnglishHyphenation.enUs.hyphenate("the"))
        assertEquals(emptyList(), EnglishHyphenation.enUs.hyphenate("a"))
        // No break in the first 2 / last 3 letters even for a long word.
        val offsets = EnglishHyphenation.enUs.hyphenate("supercalifragilistic")
        assertTrue(offsets.all { it in 2..("supercalifragilistic".length - 3) }, "offsets=$offsets")
    }

    @Test
    fun honoursTheExceptionList() {
        // "project"/"present" are in the file's \hyphenation exception block with
        // no break marks ⇒ must never hyphenate.
        assertEquals(emptyList(), EnglishHyphenation.enUs.hyphenate("project"))
        assertEquals(emptyList(), EnglishHyphenation.enUs.hyphenate("present"))
    }
}
