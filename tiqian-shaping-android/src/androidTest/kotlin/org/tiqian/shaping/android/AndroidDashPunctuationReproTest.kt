package org.tiqian.shaping.android

import android.graphics.Paint
import android.text.TextPaint
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidDashPunctuationReproTest {
    private val typefaces = SystemAndroidTypefaceResolver()
    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = AndroidPaintTextShaper(typefaceResolver = typefaces),
        fontMetricsResolver = AndroidFontMetricsResolver(typefaceResolver = typefaces),
    )

    @Test
    fun zhihuDashUsesClreqDisplayGlyphWithoutGeneratedTrailingBlank() {
        val text = "在所谓中文语境下——不如说"
        val fontSize = 48f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = fontSize
            textLocale = java.util.Locale.forLanguageTag("zh-Hans")
            typeface = typefaces.resolve(
                org.tiqian.font.FontRole.CjkPunctuation,
                emptyList(),
                400,
                false,
            )
        }
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                constraints = LayoutConstraints(maxWidth = 1000f),
            ),
        )
        val dash = result.clusters.single { it.text == "——" }
        val dashDecision = result.debug.fontDecisions.single { it.sourceText == "——" }
        val dashGeometry = result.debug.geometryDecisions.single { it.sourceText == "——" }
        // Font-agnostic contract: the display form is either the kept `⸺`
        // (full-ink fonts) or the rolled-back source `——` (deficient-ink fonts
        // like Pixel's Noto CJK — DashSubstitutionInkCoverageRollback). Either
        // way the geometry stays a closed two-em body with no generated blanks.
        assertTrue(
            dash.displayText == "⸺" || dash.displayText == "——",
            "hasGlyph(⸺)=${paint.hasGlyph("⸺")} decision=$dashDecision geometry=$dashGeometry",
        )
        if (dash.displayText == "——") {
            assertTrue(
                dashDecision.substitutionReason.contains("Rollback"),
                "rolled-back dash must record its cause: $dashDecision",
            )
        }
        assertEquals(0f, dashGeometry.trailingGlueNatural, 0.5f)
        assertEquals(0f, dashGeometry.leadingGlueNatural, 0.5f)
        assertTrue(result.clusters.none { it.text == " " }, "source has no spaces: ${result.clusters}")
    }

    @Test
    fun justifiedZhihuDashDoesNotOpenBoundaryAfterDash() {
        val text = "在所谓中文语境下——不如说中文中文中文中文"
        val fontSize = 48f
        val attempts = mutableListOf<String>()
        val candidate = (420..760 step 12).firstNotNullOfOrNull { width ->
            val result = engine.layout(
                LayoutInput(
                    content = TiqianTextContent(text),
                    textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                    paragraphStyle = ParagraphStyle(
                        firstLineIndent = 0.ic,
                        lineLengthGrid = LineLengthGrid(enabled = false),
                    ),
                    constraints = LayoutConstraints(maxWidth = width.toFloat()),
                ),
            )
            val dash = result.clusters.single { it.text == "——" }
            val decision = result.debug.justificationDecisions.firstOrNull {
                dash.range.start >= it.lineRange.start && dash.range.end <= it.lineRange.end
            }
            attempts += "width=$width lines=${result.lines.map { it.clusterRange }} decisions=${
                result.debug.justificationDecisions.map { it.lineRange }
            }"
            if (decision == null) null else Triple(width, result, decision)
        } ?: error("No tested width produced a justified non-last line containing the dash. $attempts")

        val result = candidate.second
        val decision = candidate.third
        assertTrue(result.lines.size >= 2)
        val dash = result.clusters.single { it.text == "——" }
        val dashIndex = result.clusters.indexOf(dash)
        val beforeDash = result.clusters[dashIndex - 1]
        val allocations = decision.allocations
        assertTrue(
            allocations.none { it.kind == "CjkInterChar" && it.clusterRange == beforeDash.range },
            "boundary before dash must stay closed: $allocations",
        )
        assertTrue(
            allocations.none { it.kind == "CjkInterChar" && it.clusterRange == dash.range },
            "boundary after dash must stay closed: $allocations",
        )
    }

    @Test
    fun currentZhihuParagraphDashHasClosedSourceAndBodyGeometry() {
        val text = "破折号主要是用在长难句里。在所谓中文语境下——不如说是互联网环境下——能看懂长难句的人已经降低到一个相当低的比例了，说话如果不是为了让人看懂就有点自找不痛快的意思了。"
        val fontSize = 48f
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                constraints = LayoutConstraints(maxWidth = 1248f),
            ),
        )
        val dashClusters = result.clusters.filter { it.text == "——" }
        assertEquals(2, dashClusters.size)
        assertTrue(result.clusters.none { it.text == " " }, "source has no spaces: ${result.clusters}")
        dashClusters.forEach { dash ->
            assertTrue(dash.displayText == "⸺" || dash.displayText == "——", "display=$dash")
            assertEquals(fontSize * 2f, dash.advance, 0.5f)
        }
        val dashGeometry = result.debug.geometryDecisions.filter { it.sourceText == "——" }
        assertEquals(2, dashGeometry.size)
        dashGeometry.forEach { geometry ->
            assertEquals(0f, geometry.leadingGlueNatural, 0.5f)
            assertEquals(0f, geometry.trailingGlueNatural, 0.5f)
            assertEquals(0f, geometry.justificationDelta, 0.5f)
            assertEquals(fontSize * 2f, geometry.bodyWidth, 0.5f)
        }
    }

    @Test
    fun androidLayoutKeepsGlyphFontAndPlacementForDashRendering() {
        val text = "中文——中文"
        val fontSize = 48f
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                constraints = LayoutConstraints(maxWidth = 1000f),
            ),
        )
        val dash = result.clusters.single { it.text == "——" }
        val glyph = result.glyphRuns.flatMap { it.glyphs }.single { it.clusterRange == dash.range }
        val fontKey = glyph.renderFontKey
        assertTrue(dash.displayText == "⸺" || dash.displayText == "——", "display=$dash")
        assertEquals(fontSize * 2f, dash.advance, 0.5f)
        // DashInkCentering: when the font's rule ink underfills the two-em body,
        // the glyph draw origin shifts so the ink sits centred — left and right
        // side gaps must match (within 1px). x==0 only for full-ink fonts.
        val ink = glyph.bounds
        if (ink != null) {
            val leftGap = glyph.x + ink.left
            val rightGap = dash.advance - (glyph.x + ink.right)
            assertTrue(
                kotlin.math.abs(leftGap - rightGap) <= 1f,
                "dash ink must be centred: leftGap=$leftGap rightGap=$rightGap glyph=$glyph",
            )
        } else {
            assertEquals(0f, glyph.x, 0.5f)
        }
        assertEquals(0f, glyph.y, 0.5f)
        // ContextConsistentGlyphCapture: a kept single-glyph substitution must be
        // the Han-context glyph — its advance matches the cluster (no mixing a
        // context-free narrow glyph into a full-width body).
        if (dash.displayText == "⸺") {
            assertEquals(dash.advance, glyph.advance, 0.5f)
        }
        assertTrue(fontKey != null, "Android glyph must keep the shaper Font key: $glyph")
        assertTrue(
            AndroidPositionedGlyphFontRegistry.fontFor(fontKey) != null,
            "Android glyph Font key must resolve during rendering: $glyph",
        )
    }
}
