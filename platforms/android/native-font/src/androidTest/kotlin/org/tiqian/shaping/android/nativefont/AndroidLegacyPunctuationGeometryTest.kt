package org.tiqian.shaping.android.nativefont

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import org.tiqian.layout.PunctuationAtomBuilder
import org.tiqian.layout.PunctuationAnchor
import org.tiqian.layout.PunctuationInkInput
import org.tiqian.shaping.ShapingInput
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidLegacyPunctuationGeometryTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun systemCjkPunctuationGeometryIsInspectable() {
        val shaper = AndroidNativeTextShaper(context)
        val builder = PunctuationAtomBuilder()
        for (character in "，。；：！？、（）「」《》") {
            val shaped = shaper.shape(input(character.toString()))
            val cluster = shaped.clusters.single()
            val glyph = shaped.glyphRuns.single().glyphs.single()
            val atom = builder.build(
                char = character.toString(),
                range = TextRange(0, 1),
                em = 32f,
                inkInput = PunctuationInkInput(
                    advance = cluster.advance,
                    inkBounds = glyph.bounds,
                    haltAdvance = glyph.haltAdvance,
                    haltPlacementX = glyph.haltPlacementX,
                ),
            )!!
            android.util.Log.i(
                "TiqianPunctuation",
                "char=$character advance=${cluster.advance} ink=${glyph.bounds} " +
                    "haltAdvance=${glyph.haltAdvance} haltPlacement=${glyph.haltPlacementX} " +
                    "leading=${atom.leadingGlue.natural} body=${atom.bodyWidth} " +
                    "trailing=${atom.trailingGlue.natural} anchor=${atom.anchor} " +
                    "source=${atom.geometrySource} " +
                    "validation=${atom.haltValidation}",
            )
            assertTrue(atom.bodyWidth > 0f)
            assertEquals(
                atom.advance,
                atom.leadingGlue.natural + atom.bodyWidth + atom.trailingGlue.natural,
                0.01f,
            )
            if (atom.anchor == PunctuationAnchor.Center) {
                assertEquals(atom.leadingGlue.natural, atom.trailingGlue.natural, 0.01f)
            }
        }
    }

    private fun input(text: String) = ShapingInput(
        text = text,
        range = TextRange(0, text.length),
        style = TextStyle(fontSize = 32f, locale = "zh-Hans"),
        fontDecision = FontDecision(
            range = TextRange(0, text.length),
            candidate = FontCandidate("legacy-punctuation", "sans-serif", FontRole.CjkPunctuation),
            role = FontRole.CjkPunctuation,
            reason = "LegacyPunctuationInstrumentationFixture",
        ),
    )
}
