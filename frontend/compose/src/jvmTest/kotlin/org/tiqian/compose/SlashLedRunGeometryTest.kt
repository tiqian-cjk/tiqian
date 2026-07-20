package org.tiqian.compose

import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.core.positionedClusters
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Desktop (Skia) guard for the slash-led-run fix (`mapToClusterRange`): a
 * technical run such as `/TERFism` next to 汉字 must (1) keep its NATURAL glyph
 * advances — no scaling smear that squeezes the letters — and (2) never overflow
 * its cluster box and overlap the next cluster, at any wrap width. The bug
 * repro'd on Compose Desktop too, but Codex only guarded it with an Android
 * instrumented test; this is the shared JVM coverage.
 */
class SlashLedRunGeometryTest {
    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = SkiaTextShaper(),
        fontMetricsResolver = SkiaFontMetricsResolver(),
        clreqProfileResolver = { ClreqProfile.MainlandHorizontal },
    )

    private val text = "支持生物本质主义/恐跨/TERFism，然后继续写中文把这一行凑满整整一整行的样子。"
    private val fontSize = 40f

    private fun layout(width: Float): LayoutResult = engine.layout(
        LayoutInput(
            content = TiqianTextContent(text),
            textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
            paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
            constraints = LayoutConstraints(maxWidth = width),
        ),
    )

    @Test
    fun slashLedRunKeepsNaturalGlyphAdvances() {
        val r = layout(9999f)
        val glyphs = r.glyphRuns.flatMap { it.glyphs }
        val run = r.clusters.single { it.text.contains("TERF") }
        val glyphSum = glyphs.filter { it.clusterRange == run.range }.sumOf { it.advance.toDouble() }.toFloat()
        // No advance smearing: the shaped letters sum to exactly the cluster advance.
        assertTrue(
            kotlin.math.abs(glyphSum - run.advance) < 0.5f,
            "slash-led run advances were distorted: cluster=${run.advance} glyphSum=$glyphSum",
        )
    }

    @Test
    fun slashLedRunNeverOverlapsNeighbourAtAnyWidth() {
        for (w in listOf(280f, 320f, 360f, 440f, 520f, 9999f)) {
            val r = layout(w)
            val glyphs = r.glyphRuns.flatMap { it.glyphs }
            for (line in r.lines) {
                val pos = r.positionedClusters(line)
                pos.zipWithNext().forEach { (cur, next) ->
                    val c = r.clusters[cur.clusterIndex]
                    if (!c.text.any { it.isLetter() || it == '/' }) return@forEach
                    val gsum = glyphs.filter { it.clusterRange == c.range }.sumOf { it.advance.toDouble() }.toFloat()
                    val overlap = (cur.drawX + gsum) - next.drawX
                    assertTrue(
                        overlap <= 0.5f,
                        "width=$w '${c.text}' overflows next by $overlap (drawX=${cur.drawX} gsum=$gsum next=${next.drawX})",
                    )
                }
            }
        }
    }

    @Test
    fun noLeadingAutospaceBeforeSlashLedRun() {
        val r = layout(9999f)
        val run = r.clusters.single { it.text.contains("TERF") }
        assertTrue(
            r.debug.autoSpaceDecisions.none { it.clusterRange == run.range && it.side == "leading" },
            "slash-led run must not get 中西间距: ${r.debug.autoSpaceDecisions}",
        )
    }
}
