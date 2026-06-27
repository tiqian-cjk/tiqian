package org.tiqian.shaping.android

import android.text.TextPaint
import org.tiqian.font.FontMetricSource
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.font.usesLatinFace
import java.util.Locale

/**
 * Android metrics resolver paired with [AndroidPaintTextShaper].
 *
 * The public Android text stack exposes paint font metrics, but not the same
 * OpenType BASE/OS2 table access used by the Skia resolver. For CJK roles we
 * therefore keep the project's established ideographic box fallback explicit
 * (`0.88/0.12em`) while still recording raw platform metrics from [TextPaint].
 */
class AndroidFontMetricsResolver(
    private val typefaceResolver: AndroidTypefaceResolver = SystemAndroidTypefaceResolver(),
) : FontMetricsResolver {

    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        val paint = TextPaint().apply {
            isAntiAlias = true
            textSize = request.fontSize
            textLocale = Locale.forLanguageTag(request.locale)
            typeface = typefaceResolver.resolve(
                role = request.role,
                fontFamilies = request.fontFamilies,
                fontWeight = 400,
                italic = false,
            )
        }
        val metrics = paint.fontMetrics
        // LatinVsCjkFaceSelection: anything drawn in the CJK face (incl. Symbol /
        // Emoji / Unknown) gets the project's 字身框 fallback box, matching the Skia
        // resolver — otherwise a missing-glyph line would inflate to hhea height.
        val cjkBox = !request.role.usesLatinFace()
        val raw = RawFontMetrics(
            ascent = -metrics.ascent,
            descent = metrics.descent,
            leading = metrics.leading,
            source = FontMetricSource.GlyphSampling,
            typoAscent = if (cjkBox) request.fontSize * 0.88f else null,
            typoDescent = if (cjkBox) request.fontSize * 0.12f else null,
        )
        return raw
    }
}
