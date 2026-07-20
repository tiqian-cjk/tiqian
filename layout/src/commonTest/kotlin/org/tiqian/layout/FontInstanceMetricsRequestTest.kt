package org.tiqian.layout

import kotlin.test.Test
import kotlin.test.assertTrue
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.FontRole
import org.tiqian.font.RawFontMetrics
import org.tiqian.font.StubFontMetricsResolver

class FontInstanceMetricsRequestTest {
    @Test
    fun perSpanWeightAndItalicReachTheMetricsResolver() {
        val requests = mutableListOf<FontMetricsRequest>()
        val stub = StubFontMetricsResolver()
        val resolver = object : FontMetricsResolver {
            override fun resolve(request: FontMetricsRequest): RawFontMetrics {
                requests += request
                return stub.resolve(request)
            }
        }
        val base = TextStyle(
            fontFamilies = listOf("Fixture Sans"),
            fontSize = 18f,
            fontWeight = 400,
            italic = false,
        )
        ExplainableStubParagraphLayoutEngine(fontMetricsResolver = resolver).layout(
            LayoutInput(
                content = TiqianTextContent(
                    text = "中A",
                    spans = listOf(
                        TextSpan(
                            range = TextRange(1, 2),
                            style = base.copy(fontWeight = 700, italic = true),
                        ),
                    ),
                ),
                textStyle = base,
                constraints = LayoutConstraints(maxWidth = 180f),
            ),
        )

        assertTrue(requests.any {
            it.role == FontRole.CjkText && it.fontWeight == 400 && !it.italic &&
                it.faceSelectionText == "中"
        })
        assertTrue(requests.any {
            it.role == FontRole.LatinText && it.fontWeight == 700 && it.italic &&
                it.faceSelectionText == "A"
        })
    }

    @Test
    fun faceSelectionUsesTheDisplayTextThatWasActuallyShaped() {
        val requests = mutableListOf<FontMetricsRequest>()
        val stub = StubFontMetricsResolver()
        val resolver = object : FontMetricsResolver {
            override fun resolve(request: FontMetricsRequest): RawFontMetrics {
                requests += request
                return stub.resolve(request)
            }
        }

        ExplainableStubParagraphLayoutEngine(fontMetricsResolver = resolver).layout(
            LayoutInput(
                content = TiqianTextContent("——"),
                textStyle = TextStyle(fontFamilies = listOf("Fixture Sans"), fontSize = 18f),
                constraints = LayoutConstraints(maxWidth = 180f),
            ),
        )

        assertTrue(requests.any { it.faceSelectionText == "⸺" })
    }

    @Test
    fun rubyMetricsUseTheSameItalicInstanceAsRubyShaping() {
        val requests = mutableListOf<FontMetricsRequest>()
        val stub = StubFontMetricsResolver()
        val resolver = object : FontMetricsResolver {
            override fun resolve(request: FontMetricsRequest): RawFontMetrics {
                requests += request
                return stub.resolve(request)
            }
        }

        ExplainableStubParagraphLayoutEngine(fontMetricsResolver = resolver).layout(
            LayoutInput(
                content = TiqianTextContent("中"),
                textStyle = TextStyle(
                    fontFamilies = listOf("Fixture Sans"),
                    fontSize = 18f,
                    italic = true,
                ),
                constraints = LayoutConstraints(maxWidth = 180f),
                rubySpans = listOf(RubySpan(TextRange(0, 1), "zhōng")),
            ),
        )

        assertTrue(requests.any {
            it.role == FontRole.LatinText && it.faceSelectionText == "zhōng" && it.italic
        })
    }
}
