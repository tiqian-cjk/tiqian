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

    private fun layoutWith(
        hyphenator: Hyphenator,
        content: String = text,
        maxWidth: Float = 160f,
    ) = ExplainableStubParagraphLayoutEngine(hyphenator = hyphenator).layout(
        LayoutInput(
            paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
            content = TiqianTextContent(content),
            constraints = LayoutConstraints(maxWidth = maxWidth),
        ),
    )

    private fun Char.isLatinLetter() = this in 'a'..'z' || this in 'A'..'Z'

    @Test
    fun hyphenationIsOnByDefault() {
        // The default engine (no explicit hyphenator) uses the platform
        // hyphenator — en-US on JVM — so a fitting word hyphenates without
        // opting in: "coffee" → cof-fee with a hanging hyphen.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文中 coffee"),
                constraints = LayoutConstraints(maxWidth = 112f),
            ),
        )
        assertTrue(result.clusters.any { it.text == "cof" })
        assertTrue(result.clusters.any { it.text == "fee" })
        assertTrue(result.lines.any { it.hyphenAdvance > 0f })
    }

    @Test
    fun reservedHyphenSqueezesPunctuationGlueToPullItIn() {
        // A reserved hyphen that would overflow first squeezes the comma's
        // trailing glue (标点挤压) before hanging the residual.
        val result = ExplainableStubParagraphLayoutEngine(hyphenator = EnglishHyphenation.enUs).layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(
                    firstLineIndentEm = 0f,
                    lineLengthGrid = ink.duo3.tiqian.core.LineLengthGrid(enabled = false),
                ),
                content = TiqianTextContent("中文，internationalization"),
                constraints = LayoutConstraints(maxWidth = 128f),
            ),
        )
        val comma = result.clusters.first { it.text == "，" }
        assertTrue(comma.advance < 16f, "comma glue not compressed for the hyphen: ${comma.advance}")
    }

    @Test
    fun hyphenationIsSkippedWhenStretchingCjkStaysTight() {
        // Last resort (ADR 0029 amend): 8 hanzi (128) + " coffee" at maxWidth=180
        // (grid off). "cof" fits the line, but wrapping "coffee" whole leaves a
        // deficit of ~52 over 7 汉字间距 ≈ 7.4px/gap < 0.5em(8px) — tight enough,
        // so it does NOT hyphenate; "coffee" wraps whole and the CJK stretches.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(
                    firstLineIndentEm = 0f,
                    lineLengthGrid = ink.duo3.tiqian.core.LineLengthGrid(enabled = false),
                ),
                content = TiqianTextContent("中文中文中文中文 coffee"),
                constraints = LayoutConstraints(maxWidth = 180f),
            ),
        )
        assertTrue(result.lines.none { it.hyphenAdvance > 0f }, "should not hyphenate when tight")
    }

    @Test
    fun fittingWordHyphenatesOnlyWhenAHyphenatorIsInjected() {
        // "coffee" (96) fits the measure (112), so without a hyphenator it stays
        // whole and wraps as a unit; with one it splits cof-fee and a hyphen
        // hangs at the line end. (Over-long words hard-break regardless — see
        // overlongLatinWordHardBreaksWithAHangingHyphen.)
        val noHyphen = layoutWith(NoHyphenator, "中文中 coffee", 112f)
        val hyphenated = layoutWith(EnglishHyphenation.enUs, "中文中 coffee", 112f)

        assertTrue(noHyphen.clusters.any { it.text == "coffee" })
        assertTrue(noHyphen.lines.none { it.hyphenAdvance > 0f })

        assertTrue(hyphenated.clusters.none { it.text == "coffee" })
        assertTrue(hyphenated.clusters.any { it.text == "cof" })
        assertTrue(hyphenated.clusters.any { it.text == "fee" })
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
    fun hyphenIsReservedWithinTheMeasureNotHungPastIt() {
        // The hyphen takes real width inside the measure (like a line-end mark):
        // content fills only `measure − hyphen`, so content + hyphen lands at the
        // measure edge — the hyphen does not hang past it (the word fits here).
        val hyphenated = layoutWith(EnglishHyphenation.enUs, "请运行 internationalization 命令", 160f)
        val hyphenLine = hyphenated.lines.first { it.hyphenAdvance > 0f }
        assertTrue(
            hyphenLine.indent + hyphenLine.visualWidth + hyphenLine.hyphenAdvance <= 160f + 0.01f,
            "hyphen hung past the measure: ${hyphenLine.indent + hyphenLine.visualWidth + hyphenLine.hyphenAdvance}",
        )
    }
}
