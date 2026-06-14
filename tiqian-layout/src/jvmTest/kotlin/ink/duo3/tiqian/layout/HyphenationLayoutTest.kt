package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.linebreak.EnglishHyphenation
import ink.duo3.tiqian.linebreak.Hyphenator
import ink.duo3.tiqian.linebreak.NoHyphenator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HyphenationLayoutTest {
    private val text = "中文internationalization中文"

    private fun layoutWith(hyphenator: Hyphenator) =
        ExplainableStubParagraphLayoutEngine(hyphenator = hyphenator).layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = 160f),
            ),
        )

    private fun Char.isLatinLetter() = this in 'a'..'z' || this in 'A'..'Z'

    @Test
    fun longWesternWordWrapsAtHyphenationPointsWithAHangingHyphen() {
        val noHyphen = layoutWith(NoHyphenator)
        val hyphenated = layoutWith(EnglishHyphenation.enUs)

        // Default: the word stays a single unbreakable cluster, no hanging hyphen.
        assertTrue(noHyphen.clusters.any { it.text == "internationalization" })
        assertTrue(noHyphen.lines.none { it.hyphenAdvance > 0f })

        // With the hyphenator the word is split into syllable clusters and at
        // least one line ends with a hanging hyphen (LineEndHangingHyphen).
        assertTrue(hyphenated.clusters.size > noHyphen.clusters.size)
        assertTrue(hyphenated.lines.any { it.hyphenAdvance > 0f }, "no line hyphenated")
    }

    @Test
    fun syllableSplitMatchesTheHyphenatorExactly() {
        val hyphenated = layoutWith(EnglishHyphenation.enUs)
        val word = "internationalization"

        // The Latin syllable clusters reconstruct the word, split at exactly the
        // hyphenator's points.
        val rebuilt = hyphenated.clusters
            .filter { it.text.isNotEmpty() && it.text.all { c -> c.isLatinLetter() } }
            .joinToString("-") { it.text }

        val expected = buildString {
            var prev = 0
            for (p in EnglishHyphenation.enUs.hyphenate(word)) {
                append(word.substring(prev, p)).append('-')
                prev = p
            }
            append(word.substring(prev))
        }
        assertEquals(expected, rebuilt)
    }

    @Test
    fun hangingHyphenIsNotCountedInTheMeasureFill() {
        // The hyphen hangs past the content: a hyphenated line's visualWidth (the
        // content) still respects the measure; the hyphen sits beyond it.
        val hyphenated = layoutWith(EnglishHyphenation.enUs)
        val hyphenLine = hyphenated.lines.first { it.hyphenAdvance > 0f }
        assertTrue(
            hyphenLine.indent + hyphenLine.visualWidth <= 160f + 0.01f,
            "content overflowed the measure: ${hyphenLine.indent + hyphenLine.visualWidth}",
        )
        assertTrue(hyphenLine.hyphenAdvance > 0f)
    }
}
