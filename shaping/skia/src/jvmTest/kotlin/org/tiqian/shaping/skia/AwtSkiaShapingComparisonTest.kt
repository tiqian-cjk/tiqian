package org.tiqian.shaping.skia

import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.jvm.AwtTextShaper
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Cross-adapter golden comparison (ADR 0014 follow-up: 「Android / Skia
 * adapter 接入后复核同一批标点的 body/glue 差异」).
 *
 * Shapes every CLREQ punctuation character with both `AwtTextShaper` and
 * `SkiaTextShaper`. Both resolvers probe the same font candidate lists, so
 * on a machine where a shared CJK family exists the two engines measure the
 * SAME physical font and advances must agree closely. Ink bounds may differ
 * slightly (hinting/scaler differences) — those are printed for diagnosis
 * and only sanity-checked for side agreement.
 *
 * Hard assertions:
 * - per-character advance delta ≤ [ADVANCE_TOLERANCE_PX] at 16px;
 * - ink presence agrees (a glyph blank in one engine must be blank in the
 *   other);
 * - for SIDE-ANCHORED classes (Opening / Closing / PauseOrStop) where both
 *   engines report ink, the ink CENTRE falls on the same half of the advance
 *   box (the side is what punctuation geometry consumes per ADR 0014 — exact
 *   pixels are diagnostic only). Centre-anchored marks (`-` `—` `·`…) sit at
 *   advance/2 where sub-pixel rounding flips the half arbitrarily, so they
 *   are excluded from the side check.
 */
class AwtSkiaShapingComparisonTest {

    private val awt = AwtTextShaper()
    private val skia = SkiaTextShaper()

    private val clreqPunctuationChars: List<Pair<Char, String>> = listOf(
        '“' to "Opening", '‘' to "Opening", '（' to "Opening",
        '《' to "Opening", '〈' to "Opening", '「' to "Opening", '『' to "Opening",
        '”' to "Closing", '’' to "Closing", '）' to "Closing",
        '》' to "Closing", '〉' to "Closing", '」' to "Closing", '』' to "Closing",
        '，' to "PauseOrStop", '、' to "PauseOrStop", '。' to "PauseOrStop",
        '；' to "PauseOrStop", '：' to "PauseOrStop", '！' to "PauseOrStop", '？' to "PauseOrStop",
        '·' to "MiddleDot",
        '・' to "Interpunct", '‧' to "Interpunct", '•' to "Interpunct",
        '～' to "Connector", '~' to "Connector", '-' to "Connector", '–' to "Connector",
        '/' to "Solidus", '／' to "Solidus",
        '…' to "Ellipsis", '⋯' to "Ellipsis",
        '—' to "Dash", '⸺' to "Dash",
    )

    @Test
    fun awtAndSkiaAgreeOnClreqPunctuationAdvancesAndInkSides() {
        data class Row(
            val char: Char,
            val punctuationClass: String,
            val awtAdvance: Float,
            val skiaAdvance: Float,
            val awtInkCenter: Float?,
            val skiaInkCenter: Float?,
            val awtFont: String,
            val skiaFont: String,
        )

        val rows = clreqPunctuationChars.map { (ch, cls) ->
            val awtResult = awt.shape(punctuationInput(ch))
            val skiaResult = skia.shape(punctuationInput(ch))
            val awtGlyph = awtResult.glyphRuns.single().glyphs.single()
            val skiaGlyph = skiaResult.glyphRuns.single().glyphs.single()
            Row(
                char = ch,
                punctuationClass = cls,
                awtAdvance = awtGlyph.advance,
                skiaAdvance = skiaGlyph.advance,
                awtInkCenter = awtGlyph.bounds?.let { (it.left + it.right) / 2f },
                skiaInkCenter = skiaGlyph.bounds?.let { (it.left + it.right) / 2f },
                awtFont = awtResult.decisions.single().reason.substringAfter(':'),
                skiaFont = skiaResult.decisions.single().reason.substringAfter(':'),
            )
        }

        println()
        println("=== AWT vs Skia CLREQ Punctuation Comparison (16px) ===")
        println(
            "%-4s  %-13s  %8s  %8s  %7s  %8s  %8s".format(
                "Char", "Class", "awtAdv", "skiaAdv", "delta", "awtInkC", "skiaInkC",
            ),
        )
        println("-".repeat(72))
        for (r in rows) {
            println(
                "%-4s  %-13s  %8.2f  %8.2f  %7.2f  %8s  %8s".format(
                    r.char, r.punctuationClass, r.awtAdvance, r.skiaAdvance,
                    abs(r.awtAdvance - r.skiaAdvance),
                    r.awtInkCenter?.let { "%.2f".format(it) } ?: "-",
                    r.skiaInkCenter?.let { "%.2f".format(it) } ?: "-",
                ),
            )
        }
        println("-".repeat(72))
        println("AWT font: ${rows.first().awtFont} / Skia font: ${rows.first().skiaFont}")
        println()

        val failures = mutableListOf<String>()
        for (r in rows) {
            if (r.char in LOCL_DIVERGENT_CHARS) {
                // LocaleTaggedShaping: Skia shapes with lang=zh-Hans and gets
                // the OpenType `locl` CJK variants — `—` at a full 1em and
                // `⸺` at a full 2em, vertically centred. AWT has no language
                // tagging, stays on the Western forms (14.3 / 26.8), and is
                // expected to diverge here. Assert the Skia side is the
                // full-width CJK form instead of advance equality.
                val em = 16f
                if (r.skiaAdvance % em != 0f) {
                    failures += "'${r.char}' expected full-width locl form from Skia, got ${r.skiaAdvance}"
                }
                continue
            }
            if (abs(r.awtAdvance - r.skiaAdvance) > ADVANCE_TOLERANCE_PX) {
                failures += "'${r.char}' advance mismatch: awt=${r.awtAdvance} skia=${r.skiaAdvance}"
            }
            if ((r.awtInkCenter == null) != (r.skiaInkCenter == null)) {
                failures += "'${r.char}' ink presence mismatch: awt=${r.awtInkCenter} skia=${r.skiaInkCenter}"
            }
            val sideAnchored = r.punctuationClass in setOf("Opening", "Closing", "PauseOrStop")
            if (sideAnchored && r.awtInkCenter != null && r.skiaInkCenter != null) {
                val awtLeftHalf = r.awtInkCenter < r.awtAdvance / 2f
                val skiaLeftHalf = r.skiaInkCenter < r.skiaAdvance / 2f
                if (awtLeftHalf != skiaLeftHalf) {
                    failures += "'${r.char}' ink side mismatch: " +
                        "awt centre=${r.awtInkCenter}/${r.awtAdvance} skia centre=${r.skiaInkCenter}/${r.skiaAdvance}"
                }
            }
        }
        assertTrue(
            failures.isEmpty(),
            "AWT/Skia divergence:\n" + failures.joinToString("\n"),
        )
    }

    private fun punctuationInput(ch: Char): ShapingInput {
        val text = ch.toString()
        return ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(fontSize = 16f),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate(
                    key = "test-CjkPunctuation",
                    family = "test-CjkPunctuation",
                    role = FontRole.CjkPunctuation,
                ),
                role = FontRole.CjkPunctuation,
                reason = "awt-skia-comparison",
            ),
            displayText = text,
        )
    }

    companion object {
        /**
         * Both engines measure the same physical font; remaining deltas come
         * from scaler/rounding differences. Half a pixel at 16px is generous
         * but still tight enough to catch a wrong-font or wrong-feature path.
         */
        private const val ADVANCE_TOLERANCE_PX = 0.5f

        /**
         * Characters whose Skia measurement intentionally diverges from AWT:
         * `LocaleTaggedShaping` activates the `locl` zh-Hans variants that
         * AWT cannot reach. See ADR 0015 amendment.
         */
        private val LOCL_DIVERGENT_CHARS = setOf('—', '⸺')
    }
}
