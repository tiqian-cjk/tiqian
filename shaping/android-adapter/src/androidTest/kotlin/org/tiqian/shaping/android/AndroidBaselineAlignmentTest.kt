package org.tiqian.shaping.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.test.assertEquals

@RunWith(AndroidJUnit4::class)
class AndroidBaselineAlignmentTest {
    private val typefaces = SystemAndroidTypefaceResolver()
    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = AndroidPaintTextShaper(typefaceResolver = typefaces),
        fontMetricsResolver = AndroidFontMetricsResolver(typefaceResolver = typefaces),
    )

    @Test
    fun cjkPunctuationAfterLatinUsesSharedRomanBaseline() {
        val fontSize = 48f
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("MacBook。"),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = 0.ic,
                    lineHeight = fontSize * 1.6f,
                ),
                constraints = LayoutConstraints(maxWidth = fontSize * 26f),
            ),
        )

        val punctuation = result.clusters.single { it.text == "。" }
        assertEquals(
            0f,
            punctuation.baselineShift,
            0.01f,
            "CJK punctuation has an IdeographicEmBox and must not be aligned to Latin raw descent",
        )
    }
}
