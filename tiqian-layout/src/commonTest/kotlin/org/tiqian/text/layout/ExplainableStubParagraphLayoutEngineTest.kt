package org.tiqian.text.layout

import org.tiqian.text.clreq.CjkPunctuationGlyphPolicy
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
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
    fun honorsProfilePunctuationGlyphPolicy() {
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    punctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreserveInput,
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("……——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("……", result.clusters.first { it.text == "……" }.displayText)
        assertEquals("——", result.clusters.first { it.text == "——" }.displayText)
    }

    @Test
    fun usesTwoEmAdvanceForRecommendedDashCodepoint() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("⸺"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals(32f, result.clusters.single().advance)
        assertEquals(32f, result.size.width)
    }

    @Test
    fun keepsLatinTechnicalPunctuationInLatinRun() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("well-known/path"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("well-known/path", result.clusters.single().text)
        assertEquals("latin-primary", result.clusters.single().fontKey)
    }

    @Test
    fun buildsTwoEmPunctuationAtomForRecommendedDashCodepoint() {
        val atom = PunctuationAtomBuilder().build("⸺", index = 0, em = 16f)

        requireNotNull(atom)
        assertEquals(32f, atom.advance)
        assertEquals(32f, atom.bodyWidth)
    }

    @Test
    fun recordsPunctuationAtomsInLayoutDebug() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，世界。——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertTrue(
            result.debug.punctuationDecisions.any {
                it == "punct:2-3:，:PauseOrStop:advance=16.0,body=8.0,leading=4.0,trailing=4.0,anchor=Center"
            },
        )
        assertTrue(
            result.debug.punctuationDecisions.any {
                it == "punct:5-6:。:PauseOrStop:advance=16.0,body=8.0,leading=4.0,trailing=4.0,anchor=Center"
            },
        )
        assertTrue(
            result.debug.punctuationDecisions.any {
                it == "punct:6-8:⸺:Dash:advance=32.0,body=32.0,leading=0.0,trailing=0.0,anchor=Center"
            },
        )
        assertTrue(result.lines.single().debug.notes.contains("punctuation-atoms:3"))
    }

    @Test
    fun compressesAdjacentPunctuationInnerGlue() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val line = result.lines.single()
        val stop = result.clusters.first { it.text == "。" }

        assertEquals(64f, line.naturalWidth)
        assertEquals(60f, line.adjustedWidth)
        assertEquals(60f, line.visualWidth)
        assertEquals(60f, result.size.width)
        assertEquals(12f, stop.advance)
        assertTrue(line.debug.notes.contains("punctuation-spacing-reduction:4.0"))
        assertTrue(
            result.debug.punctuationSpacingDecisions.any {
                it == "spacing:2-4:，。:naturalInner=8.0,adjustedInner=4.0,reduction=4.0,target=3-4:collapse-adjacent-punctuation-inner-glue"
            },
        )
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
