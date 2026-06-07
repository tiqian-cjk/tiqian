package org.tiqian.text.shaping.jvm

import org.tiqian.text.core.TextRange
import org.tiqian.text.core.TextStyle
import org.tiqian.text.font.FontCandidate
import org.tiqian.text.font.FontDecision
import org.tiqian.text.font.FontRole
import org.tiqian.text.shaping.ShapingInput
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Diagnostic test that shapes every CLREQ punctuation character individually
 * and reports which ones have glyph ink bounds from AWT.
 *
 * This is primarily observational: the only hard assertion is that at least one
 * character has bounds (sanity check that the AWT path works at all). The
 * printed table is the real output — useful for verifying font coverage.
 */
class InkBoundsCoverageTest {

    private val shaper = AwtTextShaper()

    /**
     * All punctuation characters that [ClreqPunctuationPolicies.classify] maps
     * to a non-Other class, paired with their CLREQ punctuation class label.
     * Inlined here so this module does not need a `tiqian-clreq` dependency.
     */
    private val clreqPunctuationChars: List<Pair<Char, String>> = listOf(
        // Opening
        '\u201C' to "Opening",      // "
        '\u2018' to "Opening",      // '
        '\uFF08' to "Opening",      // （
        '\u300A' to "Opening",      // 《
        '\u3008' to "Opening",      // 〈
        '\u300C' to "Opening",      // 「
        '\u300E' to "Opening",      // 『
        // Closing
        '\u201D' to "Closing",      // "
        '\u2019' to "Closing",      // '
        '\uFF09' to "Closing",      // ）
        '\u300B' to "Closing",      // 》
        '\u3009' to "Closing",      // 〉
        '\u300D' to "Closing",      // 」
        '\u300F' to "Closing",      // 』
        // PauseOrStop
        '\uFF0C' to "PauseOrStop",  // ，
        '\u3001' to "PauseOrStop",  // 、
        '\u3002' to "PauseOrStop",  // 。
        '\uFF1B' to "PauseOrStop",  // ；
        '\uFF1A' to "PauseOrStop",  // ：
        '\uFF01' to "PauseOrStop",  // ！
        '\uFF1F' to "PauseOrStop",  // ？
        // MiddleDot
        '\u00B7' to "MiddleDot",    // ·
        // Interpunct
        '\u30FB' to "Interpunct",   // ・
        '\u2027' to "Interpunct",   // ‧
        '\u2022' to "Interpunct",   // •
        // Connector
        '\uFF5E' to "Connector",    // ～
        '\u007E' to "Connector",    // ~
        '\u002D' to "Connector",    // -
        '\u2013' to "Connector",    // –
        // Solidus
        '\u002F' to "Solidus",      // /
        '\uFF0F' to "Solidus",      // ／
        // Ellipsis
        '\u2026' to "Ellipsis",     // …
        '\u22EF' to "Ellipsis",     // ⋯
        // Dash
        '\u2014' to "Dash",         // —
        '\u2E3A' to "Dash",         // ⸺
    )

    @Test
    fun reportInkBoundsCoverageForAllClreqPunctuation() {
        data class Row(
            val char: Char,
            val hex: String,
            val punctuationClass: String,
            val hasBounds: Boolean,
            val advance: Float,
        )

        val rows = clreqPunctuationChars.map { (ch, cls) ->
            val text = ch.toString()
            val result = shaper.shape(
                ShapingInput(
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
                        reason = "ink-bounds-coverage-test",
                    ),
                    displayText = text,
                ),
            )

            val glyph = result.glyphRuns.single().glyphs.single()
            Row(
                char = ch,
                hex = "U+${ch.code.toString(16).uppercase().padStart(4, '0')}",
                punctuationClass = cls,
                hasBounds = glyph.bounds != null,
                advance = glyph.advance,
            )
        }

        // Print coverage report table
        println()
        println("=== Ink Bounds Coverage Report ===")
        println("%-4s  %-8s  %-14s  %-10s  %s".format("Char", "Unicode", "Class", "HasBounds", "Advance"))
        println("-".repeat(60))
        for (row in rows) {
            println(
                "%-4s  %-8s  %-14s  %-10s  %.2f".format(
                    row.char,
                    row.hex,
                    row.punctuationClass,
                    row.hasBounds,
                    row.advance,
                ),
            )
        }
        println("-".repeat(60))

        val withBounds = rows.count { it.hasBounds }
        val total = rows.size
        println("Coverage: $withBounds / $total characters have ink bounds")
        println()

        // Sanity: at least one character should have bounds
        assertTrue(
            rows.any { it.hasBounds },
            "Expected at least one CLREQ punctuation character to have glyph bounds",
        )
    }
}
