package org.tiqian.text.shaping.skia

import org.tiqian.text.core.TextRange
import org.tiqian.text.core.TextStyle
import org.tiqian.text.font.FontCandidate
import org.tiqian.text.font.FontDecision
import org.tiqian.text.font.FontRole
import org.tiqian.text.shaping.ShapingInput
import org.tiqian.text.shaping.jvm.AwtTextShaper
import kotlin.test.Test

/**
 * Diagnostic probe: vertical ink position of dash/ellipsis codepoints vs the
 * CJK visual centre (measured from 一 and 中). Investigates whether the font
 * draws U+2014 / U+2E3A at the Western baseline-aligned height or at the CJK
 * centred height, and whether dedicated CJK variants exist.
 */
class DashVerticalPositionProbe {

    private val skia = SkiaTextShaper()
    private val awt = AwtTextShaper()

    @Test
    fun reportVerticalInkPositions() {
        val samples = listOf(
            "一" to "CJK reference (horizontal stroke)",
            "中" to "CJK reference (full glyph)",
            "。" to "PauseOrStop",
            "—" to "U+2014 em dash",
            "⸺" to "U+2E3A two-em dash",
            "…" to "U+2026 ellipsis",
            "⋯" to "U+22EF midline ellipsis",
            "-" to "U+002D hyphen (Latin)",
        )

        println()
        println("=== Vertical ink position @16px (top/bottom relative to baseline, negative=up) ===")
        println("%-4s  %-32s  %18s  %18s".format("Char", "Role", "skia ink[t..b] ctr", "awt ink[t..b] ctr"))
        println("-".repeat(86))
        for ((ch, label) in samples) {
            val s = skia.shape(input(ch)).glyphRuns.single().glyphs.single().bounds
            val a = awt.shape(input(ch)).glyphRuns.single().glyphs.single().bounds
            fun fmt(b: org.tiqian.text.core.Rect?): String =
                if (b == null) "-" else "[%.1f..%.1f] %.1f".format(b.top, b.bottom, (b.top + b.bottom) / 2f)
            println("%-4s  %-32s  %18s  %18s".format(ch, label, fmt(s), fmt(a)))
        }
        println("-".repeat(86))
        println()
    }

    @Test
    fun reportLanguageTaggedDashVariantsAcrossFonts() {
        val fontMgr = org.jetbrains.skia.FontMgr.default
        val shaper = org.jetbrains.skia.shaper.Shaper.makeShaperDrivenWrapper()
        val families = listOf("Source Han Sans CN", "PingFang SC", "Hiragino Sans GB", "Heiti SC")
        val chars = listOf("—", "⸺", "…")

        println()
        println("=== Language-tagged dash/ellipsis variants @16px ===")
        for (family in families) {
            val typeface = fontMgr.matchFamilyStyle(family, org.jetbrains.skia.FontStyle.NORMAL) ?: continue
            val font = org.jetbrains.skia.Font(typeface, 16f)
            for (ch in chars) {
                for (lang in listOf("en", "zh-Hans")) {
                    val handler = org.jetbrains.skia.shaper.TextBlobBuilderRunHandler(ch)
                    shaper.shape(
                        ch,
                        org.jetbrains.skia.shaper.TrivialFontRunIterator(ch, font),
                        org.jetbrains.skia.shaper.TrivialBidiRunIterator(ch, 0),
                        org.jetbrains.skia.shaper.TrivialScriptRunIterator(ch, "Hani"),
                        org.jetbrains.skia.shaper.TrivialLanguageRunIterator(ch, lang),
                        org.jetbrains.skia.shaper.ShapingOptions.DEFAULT,
                        Float.MAX_VALUE,
                        handler,
                    )
                    val blob = handler.makeBlob() ?: continue
                    val glyphs = blob.glyphs
                    val bounds = font.getBounds(glyphs)
                    val inkV = bounds.joinToString(" ") { "%.1f..%.1f".format(it.top, it.bottom) }
                    println(
                        "%-20s %-3s lang=%-8s glyph=%-8s inkV=%s".format(
                            family, ch, lang, glyphs.toList().toString(), inkV,
                        ),
                    )
                }
            }
        }
        println()
    }

    private fun input(ch: String): ShapingInput =
        ShapingInput(
            text = ch,
            range = TextRange(0, ch.length),
            style = TextStyle(fontSize = 16f),
            fontDecision = FontDecision(
                range = TextRange(0, ch.length),
                candidate = FontCandidate(
                    key = "test-CjkPunctuation",
                    family = "test-CjkPunctuation",
                    role = FontRole.CjkPunctuation,
                ),
                role = FontRole.CjkPunctuation,
                reason = "dash-vertical-probe",
            ),
            displayText = ch,
        )
}
