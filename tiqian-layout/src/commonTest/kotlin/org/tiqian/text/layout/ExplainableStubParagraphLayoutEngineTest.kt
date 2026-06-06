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
                content = TiqianTextContent("……——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val ellipsis = result.clusters.first { it.text == "……" }
        val dash = result.clusters.first { it.text == "——" }

        assertEquals("……", ellipsis.text)
        assertEquals("⋯⋯", ellipsis.displayText)
        assertEquals("——", dash.text)
        assertEquals("⸺", dash.displayText)
        assertEquals("cjk-primary", ellipsis.fontKey)
        assertEquals("cjk-primary", dash.fontKey)
    }
}
