package org.tiqian.shaping.skia

import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontRole
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The resolver must surface the font's DECLARED typographic box (OS/2 sTypo),
 * not just the inflated hhea metrics (ADR 0002 amendment). Holds whether or not
 * a system CJK font is present: a missing font hits the fallback, which also
 * provides a typo box.
 */
class SkiaFontMetricsResolverTest {

    @Test
    fun cjkExposesTypoBoxTighterThanHhea() {
        val r = SkiaFontMetricsResolver().resolve(
            FontMetricsRequest(fontKey = "cjk", fontSize = 16f, role = FontRole.CjkText, locale = "zh-Hans"),
        )
        val typoAscent = assertNotNull(r.typoAscent)
        val typoDescent = assertNotNull(r.typoDescent)
        // The ideographic em box is ~1em and asymmetric (ascent ≫ descent).
        assertTrue(typoAscent + typoDescent in 12f..18f, "typo box ≈ 1em, got ${typoAscent + typoDescent}")
        assertTrue(typoAscent > typoDescent, "CJK face is top-heavy")
        // …and never larger than the inflated hhea box it replaces.
        assertTrue(typoAscent <= r.ascent && typoDescent <= r.descent, "typo box must be tighter than hhea")
    }
}
