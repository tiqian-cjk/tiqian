package org.tiqian.text.layout

import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ExplainableStubParagraphLayoutEngineTest {
    @Test
    fun returnsDebuggableSingleLineResult() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        assertEquals(2, result.clusters.size)
        assertEquals(1, result.lines.size)
        assertTrue(result.debug.lineDecisions.contains("line:single-placeholder"))
    }

    @Test
    fun recordsFallbackDecisionsPerCluster() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠……English——世界。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertTrue(
            result.debug.fontDecisions.any {
                it.contains("……->⋯⋯") && it.contains(FontRole.CjkPunctuation.name) && it.contains("cjk-primary")
            },
        )
        assertTrue(
            result.debug.fontDecisions.any {
                it.contains("——->⸺") && it.contains(FontRole.CjkPunctuation.name) && it.contains("cjk-primary")
            },
        )
        assertTrue(
            result.debug.fontDecisions.any { it.contains("English") && it.contains(FontRole.LatinText.name) && it.contains("latin-primary") },
        )
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
    }

    @Test
    fun preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("……——・／"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val ellipsis = result.clusters.first { it.text == "……" }
        val dash = result.clusters.first { it.text == "——" }
        val interpunct = result.clusters.first { it.text == "・" }
        val solidus = result.clusters.first { it.text == "／" }

        assertEquals("……", ellipsis.text)
        assertEquals("⋯⋯", ellipsis.displayText)
        assertEquals("——", dash.text)
        assertEquals("⸺", dash.displayText)
        assertEquals("・", interpunct.text)
        assertEquals("·", interpunct.displayText)
        assertEquals("／", solidus.text)
        assertEquals("／", solidus.displayText)
        assertEquals("cjk-primary", ellipsis.fontKey)
        assertEquals("cjk-primary", dash.fontKey)
        assertEquals("cjk-primary", interpunct.fontKey)
        assertEquals("cjk-primary", solidus.fontKey)
    }

    @Test
    fun usesNormalizedIdeographicMetricsForCjkLineBox() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        val line = result.lines.single()
        assertEquals(8f, line.baseline)
        assertEquals(16f, line.bottom)
        assertTrue(
            result.debug.metricDecisions.any {
                it.contains("CjkText") &&
                    it.contains("raw(a=18.4") &&
                    it.contains("layout(a=8.0,d=8.0") &&
                    it.contains("baseline=IdeographicCentered") &&
                    it.contains("box=IdeographicEmBox")
            },
        )
    }
}
