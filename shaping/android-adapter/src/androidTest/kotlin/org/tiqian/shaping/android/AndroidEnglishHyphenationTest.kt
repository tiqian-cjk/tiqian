package org.tiqian.shaping.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.linebreak.EnglishHyphenation
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidEnglishHyphenationTest {
    @Test
    fun bundledEnglishHyphenationLoadsOnAndroid() {
        assertEquals("hy-phen-ation", hyphenated("hyphenation"))
        assertEquals("com-puter", hyphenated("computer"))

        val international = EnglishHyphenation.enUs.hyphenate("internationalization")
        assertTrue(international.size > 1, "expected enumerable hyphenation points: $international")
        assertTrue(2 in international, "expected in-ter... break: $international")
    }

    private fun hyphenated(word: String): String {
        val offsets = EnglishHyphenation.enUs.hyphenate(word)
        return buildString {
            for (i in word.indices) {
                if (i in offsets) append('-')
                append(word[i])
            }
        }
    }
}
