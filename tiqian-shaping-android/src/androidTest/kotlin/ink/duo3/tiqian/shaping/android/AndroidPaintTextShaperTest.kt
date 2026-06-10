package ink.duo3.tiqian.shaping.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.font.FontCandidate
import ink.duo3.tiqian.font.FontDecision
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.shaping.ShapingInput
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * On-device counterpart of the AWT↔Skia cross-check (ADR 0015/0016): the
 * Android text stack (Noto Sans CJK on the emulator) must reproduce the same
 * CLREQ punctuation geometry the desktop adapters measured — full-width
 * marks at 1em, `halt` bodies at 0.5em with the side-correct placement, and
 * the `locl` zh-Hans dash at a full em.
 */
@RunWith(AndroidJUnit4::class)
class AndroidPaintTextShaperTest {

    private val shaper = AndroidPaintTextShaper()

    @Test
    fun fullWidthPunctuationMeasuresOneEm() {
        for (ch in listOf("。", "，", "、", "（", "）", "「", "」")) {
            val cluster = shaper.shape(input(ch, FontRole.CjkPunctuation)).clusters.single()
            assertEquals(16f, cluster.advance, 0.51f)
        }
    }

    @Test
    fun haltProvidesHalfWidthBodyWithSideCorrectPlacement() {
        // Trailing-trimmed stop: halt advance 0.5em, placement 0.
        val stop = shaper.shape(input("。", FontRole.CjkPunctuation))
            .glyphRuns.single().glyphs.single()
        assertNotNull(stop.haltAdvance)
        assertEquals(8f, stop.haltAdvance!!, 0.51f)
        assertEquals(0f, stop.haltPlacementX!!, 0.51f)

        // Leading-trimmed opening bracket: placement shifts by -0.5em.
        val open = shaper.shape(input("（", FontRole.CjkPunctuation))
            .glyphRuns.single().glyphs.single()
        assertNotNull(open.haltAdvance)
        assertEquals(8f, open.haltAdvance!!, 0.51f)
        assertEquals(-8f, open.haltPlacementX!!, 0.51f)
    }

    @Test
    fun hanContextShapingPicksFullWidthCjkDash() {
        // Noto Sans CJK registers the `locl` dash rule under hani/latn but
        // NOT under DFLT; a context-free lone `—` resolves to DFLT and keeps
        // the 0.89em Western form (14.3px). HanContextShaping must recover
        // the full-width CJK form. (Ink bounds for the dash still measure
        // the context-free glyph — Paint.getTextBounds has no context
        // parameters — which is a documented diagnostic limitation.)
        val dash = shaper.shape(input("—", FontRole.CjkPunctuation))
            .glyphRuns.single().glyphs.single()
        assertEquals(16f, dash.advance, 0.51f)
    }

    @Test
    fun inkBoundsSitOnTheProfileGlueSide() {
        // PauseOrStop ink in the LEFT half, Opening ink in the RIGHT half —
        // the same invariant the desktop adapters verified (ADR 0014).
        val stop = shaper.shape(input("。", FontRole.CjkPunctuation))
            .glyphRuns.single().glyphs.single()
        val stopCentre = stop.bounds!!.let { (it.left + it.right) / 2f }
        assertTrue(stopCentre < 8f, "。 ink centre $stopCentre should be in the left half")

        val open = shaper.shape(input("（", FontRole.CjkPunctuation))
            .glyphRuns.single().glyphs.single()
        val openCentre = open.bounds!!.let { (it.left + it.right) / 2f }
        assertTrue(openCentre > 8f, "（ ink centre $openCentre should be in the right half")
    }

    @Test
    fun missingGlyphIsReported() {
        // A private-use codepoint no system font covers.
        val decision = shaper.shape(input("", FontRole.CjkPunctuation))
            .decisions.single()
        assertTrue(decision.missingGlyphs > 0, "expected missing glyph report")
    }

    private fun input(text: String, role: FontRole): ShapingInput =
        ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(fontSize = 16f),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate(
                    key = "test-${role.name}",
                    family = "test-${role.name}",
                    role = role,
                ),
                role = role,
                reason = "android-cross-check",
            ),
            displayText = text,
        )
}
