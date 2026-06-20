package ink.duo3.tiqian.shaping.skia

import ink.duo3.tiqian.font.FontMetricSource
import ink.duo3.tiqian.font.FontMetricsRequest
import ink.duo3.tiqian.font.FontMetricsResolver
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.font.RawFontMetrics
import org.jetbrains.skia.Font
import org.jetbrains.skia.Typeface

/**
 * Real Skia metrics resolver (ADR 0002 amendment). Reads the resolved
 * typeface's DECLARED metrics instead of synthesizing a box:
 *
 * - hhea-derived ascent/descent/leading from [Font.metrics] (the inflated box,
 *   kept for the no-`OS/2` fallback and overflow clamping);
 * - the CJK 字面框 → [RawFontMetrics.typoAscent] / [typoDescent], measured by
 *   PREFERRING the `BASE`-table ideographic em box (`ideo` bottom / `idtp` top)
 *   per edge, and falling back to `OS/2` sTypo when a BASE value is absent
 *   (ADR 0033 account). Source Han: `ideo`=−0.120, `idtp` absent → sTypoAsc
 *   0.880, so the box is 0.88/0.12 either way. The `ScriptAwareFontMetricsNormalizer`
 *   lays the CJK line box on THIS; ruby + 注音 reference the same box.
 *
 * Ink-bounds sampling stays a separate bad-font fallback; it is not consulted here.
 */
class SkiaFontMetricsResolver(
    private val cjkTypeface: Typeface? = SkiaSystemTypefaces.cjk,
    private val latinTypeface: Typeface? = SkiaSystemTypefaces.latin,
) : FontMetricsResolver {

    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        val typeface = when (request.role) {
            FontRole.CjkText, FontRole.CjkPunctuation -> cjkTypeface
            FontRole.LatinText -> latinTypeface ?: cjkTypeface
            FontRole.Symbol, FontRole.Emoji, FontRole.Unknown -> cjkTypeface ?: latinTypeface
        } ?: return fallback(request)

        val size = request.fontSize
        val font = Font(typeface, size)
        try {
            val m = font.metrics
            val upm = typeface.unitsPerEm.takeIf { it > 0 } ?: 1000
            val scale = size / upm
            // 字面框 (ADR 0002 amendment / ADR 0033 account): the CJK box used for the
            // line box + ruby + 注音 PREFERS the OpenType BASE ideographic em box
            // (`ideo` bottom / `idtp` top), per edge, and falls back to OS/2 sTypo when
            // a BASE value is absent. On Source Han `ideo`=−0.120 (=sTypoDesc) and
            // `idtp` is absent (→ sTypoAsc 0.880), so this matches the prior values.
            val os2 = if (typeface.tableTags.contains("OS/2")) typeface.getTableData("OS/2")?.bytes else null
            val sTypoAsc = if (os2 != null && os2.size >= 72) s16(os2, 68) else null
            val sTypoDesc = if (os2 != null && os2.size >= 72) s16(os2, 70) else null // FUnits, -down
            val (ideo, idtp) = baseIdeoIdtp(typeface) // FUnits: em-box bottom / top, nullable
            val faceTop = idtp ?: sTypoAsc            // above baseline (+)
            val faceBottom = ideo ?: sTypoDesc        // below baseline (-)
            val typoAscent: Float? = faceTop?.let { it * scale }
            val typoDescent: Float? = faceBottom?.let { -it * scale } // -> +magnitude
            return RawFontMetrics(
                ascent = -m.ascent,   // Skia ascent is negative (above baseline) -> +mag
                descent = m.descent,  // already positive (below baseline)
                leading = m.leading,
                source = FontMetricSource.RawTables,
                typoAscent = typoAscent,
                typoDescent = typoDescent,
            )
        } finally {
            font.close()
        }
    }

    /** Mirrors `StubFontMetricsResolver` so a missing system font still lays out. */
    private fun fallback(request: FontMetricsRequest): RawFontMetrics = when (request.role) {
        FontRole.CjkText, FontRole.CjkPunctuation -> RawFontMetrics(
            ascent = request.fontSize * 1.16f,
            descent = request.fontSize * 0.288f,
            typoAscent = request.fontSize * 0.88f,
            typoDescent = request.fontSize * 0.12f,
        )
        FontRole.LatinText -> RawFontMetrics(request.fontSize * 0.8f, request.fontSize * 0.2f)
        else -> RawFontMetrics(request.fontSize * 0.9f, request.fontSize * 0.25f)
    }

    private fun u16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)
    private fun s16(b: ByteArray, o: Int) = u16(b, o).toShort().toInt()

    /**
     * OpenType `BASE` table ideographic em-box edges for the horizontal axis:
     * (`ideo` = em-box bottom, `idtp` = em-box top), in FUnits, nullable per tag
     * (Source Han carries `ideo` but not `idtp`). The 字面框 source of record;
     * OS/2 sTypo is the fallback (handled by the caller).
     */
    private fun baseIdeoIdtp(tf: Typeface): Pair<Int?, Int?> {
        val base = if (tf.tableTags.contains("BASE")) tf.getTableData("BASE")?.bytes else null
        if (base == null || base.size < 6) return null to null
        return try {
            val axis = u16(base, 4) // HorizAxis offset
            if (axis == 0) return null to null
            val tagList = axis + u16(base, axis)
            val scriptList = axis + u16(base, axis + 2)
            val tagCount = u16(base, tagList)
            val tags = (0 until tagCount).map { String(base, tagList + 2 + it * 4, 4, Charsets.US_ASCII) }
            if (u16(base, scriptList) == 0) return null to null // no script records
            val script = scriptList + u16(base, scriptList + 2 + 4) // first BaseScript
            val bvOff = u16(base, script)
            if (bvOff == 0) return null to null
            val bv = script + bvOff // BaseValues
            val coordCount = u16(base, bv + 2)
            fun coord(tag: String): Int? {
                val i = tags.indexOf(tag)
                if (i !in 0 until coordCount) return null
                return s16(base, bv + u16(base, bv + 4 + i * 2) + 2) // BaseCoord format1: [fmt][coord]
            }
            coord("ideo") to coord("idtp")
        } catch (e: Exception) {
            null to null
        }
    }
}
