package ink.duo3.tiqian.shaping.skia

import org.jetbrains.skia.Font
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.Point
import org.jetbrains.skia.shaper.RunHandler
import org.jetbrains.skia.shaper.RunInfo
import org.jetbrains.skia.shaper.Shaper
import org.jetbrains.skia.shaper.ShapingOptions
import org.jetbrains.skia.shaper.TrivialBidiRunIterator
import org.jetbrains.skia.shaper.TrivialFontRunIterator
import org.jetbrains.skia.shaper.TrivialLanguageRunIterator
import org.jetbrains.skia.shaper.TrivialScriptRunIterator
import kotlin.test.Test

/**
 * Diagnostic probe: what does the font actually report under OpenType `halt`
 * (alternate half-width metrics)? Prints advance + glyph placement + design
 * ink bounds for CLREQ punctuation, feature off vs on, to inform how
 * `PunctuationAtomBuilder` should consume font-derived body widths
 * (ADR 0014 follow-up).
 */
class SkiaHaltFeatureProbe {

    @Test
    fun reportHaltAdvancesForClreqPunctuation() {
        val fontMgr = FontMgr.default
        val typeface = fontMgr.matchFamilyStyle("Source Han Sans CN", FontStyle.NORMAL)
            ?: fontMgr.matchFamilyStyle("PingFang SC", FontStyle.NORMAL)
            ?: return
        val font = Font(typeface, 16f)
        val shaper = Shaper.makeShaperDrivenWrapper()
        val chars = listOf("。", "，", "、", "（", "）", "「", "」", "《", "》", "：", "！", "·", "—", "中")

        println()
        println("=== halt feature probe (${typeface.familyName} @16px) ===")
        println("%-4s  %18s  %18s".format("Char", "off adv/pos", "halt adv/pos"))
        println("-".repeat(60))
        for (ch in chars) {
            val off = shapeOne(shaper, ch, font, ShapingOptions.DEFAULT)
            val on = shapeOne(shaper, ch, font, ShapingOptions.DEFAULT.withFeatures("halt=1"))
            println(
                "%-4s  %18s  %18s".format(
                    ch,
                    "%.1f @%.1f".format(off.first, off.second),
                    "%.1f @%.1f".format(on.first, on.second),
                ),
            )
        }
        println("-".repeat(60))
        println()
    }

    /** Returns (run advance, first glyph placement x). */
    private fun shapeOne(
        shaper: Shaper,
        text: String,
        font: Font,
        options: ShapingOptions,
    ): Pair<Float, Float> {
        var advance = 0f
        var firstX = 0f
        shaper.shape(
            text,
            TrivialFontRunIterator(text, font),
            TrivialBidiRunIterator(text, 0),
            TrivialScriptRunIterator(text, "Hani"),
            TrivialLanguageRunIterator(text, "zh-Hans"),
            options,
            Float.MAX_VALUE,
            object : RunHandler {
                override fun beginLine() {}
                override fun runInfo(info: RunInfo?) {}
                override fun commitRunInfo() {}
                override fun runOffset(info: RunInfo?): Point = Point(0f, 0f)
                override fun commitRun(
                    info: RunInfo?,
                    glyphs: ShortArray?,
                    positions: Array<Point?>?,
                    clusters: IntArray?,
                ) {
                    advance = info?.advanceX ?: 0f
                    firstX = positions?.firstOrNull()?.x ?: 0f
                }
                override fun commitLine() {}
            },
        )
        return advance to firstX
    }
}
