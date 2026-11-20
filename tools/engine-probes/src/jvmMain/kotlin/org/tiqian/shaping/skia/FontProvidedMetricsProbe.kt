package org.tiqian.shaping.skia

import org.jetbrains.skia.Font
import org.jetbrains.skia.Typeface
import kotlin.test.Test

/**
 * Diagnostic probe (no assertions): what vertical metrics does the REAL
 * system CJK font actually PROVIDE? Compares, in per-em fractions:
 *
 * - hhea-derived `FontMetrics` (Skia's ascent/descent/top/bottom) — the box
 *   ADR 0002 rejected as「偏大/偏下」;
 * - OS/2 sTypoAscender/Descender/LineGap + the USE_TYPO_METRICS flag — the
 *   font's declared typographic box;
 * - the OpenType `BASE` table `ideo` baseline (if present);
 * - real hanzi ink extents (一中国口日言語) — the bad-font fallback signal.
 *
 * Drives the ADR 0002 amendment: which font-provided datum becomes the CJK
 * layout box.
 */
class FontProvidedMetricsProbe {

    @Test
    fun reportFontProvidedMetrics() {
        val cjk = SkiaSystemTypefaces.cjk
        val latin = SkiaSystemTypefaces.latin
        println()
        println("=== Font-provided vertical metrics (per-em fractions; +down) ===")
        dump("CJK", cjk)
        dump("Latin", latin)
    }

    private fun dump(label: String, tf: Typeface?) {
        println()
        if (tf == null) {
            println("$label: <no system typeface resolved>")
            return
        }
        val upm = tf.unitsPerEm
        println("$label: ${tf.familyName}  unitsPerEm=$upm")
        val tags = tf.tableTags.toList()
        println("  tables: ${tags.filter { it in setOf("BASE", "OS/2", "hhea", "head", "vhea", "vmtx") }}")

        // hhea-derived FontMetrics, measured at size = upm so values are FUnits.
        val font = Font(tf, upm.toFloat())
        val m = font.metrics
        fun em(v: Float) = "%.3f".format(v / upm)
        // Skia: ascent negative (up), descent positive (down).
        println("  hhea/FontMetrics: top=${em(m.top)} ascent=${em(m.ascent)} descent=${em(m.descent)} bottom=${em(m.bottom)} leading=${em(m.leading)}")
        println("                    capHeight=${em(m.capHeight)} xHeight=${em(m.xHeight)}")

        // OS/2 typo metrics.
        val os2 = tableBytes(tf, "OS/2")
        if (os2 != null && os2.size >= 78) {
            val fsSelection = u16(os2, 62)
            val typoAsc = s16(os2, 68)
            val typoDesc = s16(os2, 70)
            val typoGap = s16(os2, 72)
            val winAsc = u16(os2, 74)
            val winDesc = u16(os2, 76)
            val useTypo = (fsSelection and 0x80) != 0
            println("  OS/2: sTypoAscender=${emi(typoAsc, upm)} sTypoDescender=${emi(typoDesc, upm)} sTypoLineGap=${emi(typoGap, upm)}")
            println("        usWinAscent=${emi(winAsc, upm)} usWinDescent=${emi(winDesc, upm)} USE_TYPO_METRICS=$useTypo")
        } else {
            println("  OS/2: <absent or short>")
        }

        // OpenType BASE ideographic baseline.
        println("  BASE: " + baseIdeo(tf, upm))

        // Real hanzi / Latin ink extents (per-em, +down) from glyph bounds.
        val unit = Font(tf, 1f)
        val samples = if (label == "CJK") "一中国口日言語" else "xHnpd"
        val sb = StringBuilder()
        for (ch in samples) {
            val g = tf.getUTF32Glyph(ch.code)
            if (g.toInt() == 0) continue
            val b = unit.getBounds(shortArrayOf(g)).first()
            sb.append("$ch[%.3f..%.3f] ".format(b.top, b.bottom))
        }
        println("  ink (top..bottom, +down): $sb")
        font.close(); unit.close()
    }

    private fun emi(v: Int, upm: Int) = "%.3f".format(v.toFloat() / upm)

    private fun tableBytes(tf: Typeface, tag: String): ByteArray? =
        if (tf.tableTags.contains(tag)) tf.getTableData(tag)?.bytes else null

    private fun u16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)
    private fun s16(b: ByteArray, o: Int) = u16(b, o).toShort().toInt()
    private fun tag(b: ByteArray, o: Int) = String(b, o, 4, Charsets.US_ASCII)

    /** Minimal BASE-table walk for the horizontal axis 'ideo' baseline coord. */
    private fun baseIdeo(tf: Typeface, upm: Int): String {
        val b = tableBytes(tf, "BASE") ?: return "<absent>"
        return try {
            val horizAxisOff = u16(b, 4)
            if (horizAxisOff == 0) return "<no horizontal axis>"
            val axis = horizAxisOff
            val tagListOff = u16(b, axis + 0)
            val scriptListOff = u16(b, axis + 2)
            // baseline tag list -> index of 'ideo'
            val btl = axis + tagListOff
            val tagCount = u16(b, btl)
            val tagsList = (0 until tagCount).map { tag(b, btl + 2 + it * 4) }
            val ideoIdx = tagsList.indexOf("ideo")
            // first script record -> BaseValues -> coords
            val bsl = axis + scriptListOff
            val scriptCount = u16(b, bsl)
            if (scriptCount == 0) return "tags=$tagsList <no scripts>"
            val firstScriptTag = tag(b, bsl + 2)
            val scriptOff = u16(b, bsl + 2 + 4)
            val script = bsl + scriptOff
            val baseValuesOff = u16(b, script + 0)
            if (baseValuesOff == 0) return "tags=$tagsList script=$firstScriptTag <no BaseValues>"
            val bv = script + baseValuesOff
            val defaultIdx = u16(b, bv)
            val coordCount = u16(b, bv + 2)
            val coords = (0 until coordCount).map {
                val co = bv + u16(b, bv + 4 + it * 2)
                s16(b, co + 2) // format1: [format u16][coordinate s16]
            }
            val ideoVal = if (ideoIdx in 0 until coordCount) coords[ideoIdx] else null
            "tags=$tagsList script=$firstScriptTag defaultIdx=$defaultIdx " +
                "coords(em)=${coords.map { "%.3f".format(it.toFloat() / upm) }} " +
                "ideo=${ideoVal?.let { "%.3f".format(it.toFloat() / upm) } ?: "n/a"}"
        } catch (e: Exception) {
            "<parse error: ${e.message}>"
        }
    }
}
