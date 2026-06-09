package org.tiqian.text.shaping.jvm

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.Rect
import org.tiqian.text.core.ShapingDecisionInfo
import org.tiqian.text.font.FontRole
import org.tiqian.text.shaping.ShapingInput
import org.tiqian.text.shaping.ShapingResult
import org.tiqian.text.shaping.ShapingSource
import org.tiqian.text.shaping.TextShaper
import java.awt.Font
import java.awt.font.FontRenderContext
import java.awt.geom.AffineTransform
import java.awt.geom.Rectangle2D
import kotlin.math.max

class AwtTextShaper(
    private val fontResolver: AwtFontResolver = SystemAwtFontResolver(),
    private val fontRenderContext: FontRenderContext = FontRenderContext(AffineTransform(), true, true),
) : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val font = fontResolver.resolve(input)
        val glyphVector = font.layoutGlyphVector(
            fontRenderContext,
            displayText.toCharArray(),
            0,
            displayText.length,
            Font.LAYOUT_LEFT_TO_RIGHT,
        )
        val glyphCount = glyphVector.numGlyphs
        val advance = if (glyphCount == 0) {
            0f
        } else {
            glyphVector.getGlyphPosition(glyphCount).x.toFloat()
        }

        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            displayText = displayText,
            fontKey = input.fontDecision.candidate.key,
            advance = advance,
        )
        val glyphs = (0 until glyphCount).map { glyphIndex ->
            val start = glyphVector.getGlyphPosition(glyphIndex)
            val end = glyphVector.getGlyphPosition(glyphIndex + 1)
            Glyph(
                id = glyphVector.getGlyphCode(glyphIndex).toUInt(),
                clusterRange = input.range,
                advance = max(0f, end.x.toFloat() - start.x.toFloat()),
                bounds = glyphVector.getGlyphVisualBounds(glyphIndex).bounds2D.toGlyphLocalRectOrNull(
                    originX = start.x.toFloat(),
                ),
            )
        }
        val run = GlyphRun(
            range = input.range,
            fontKey = input.fontDecision.candidate.key,
            glyphs = glyphs,
            advance = advance,
        )
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = sourceText,
            displayText = displayText,
            fontKey = input.fontDecision.candidate.key,
            glyphCount = glyphCount,
            advance = advance,
            source = ShapingSource.JvmAwt.name,
            reason = "AwtTextShaper:${font.family}:${font.fontName}",
            // AWT reports empty visual bounds for blank glyphs (spaces) and
            // for fonts without outlines; downstream punctuation geometry
            // records this as a MissingInkBoundsFallback.
            glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
        )
        return ShapingResult(
            clusters = listOf(cluster),
            glyphRuns = listOf(run),
            decisions = listOf(decision),
        )
    }
}

interface AwtFontResolver {
    fun resolve(input: ShapingInput): Font
}

/**
 * Probes the JVM's available font families at construction and picks
 * the first real CJK / Latin font it finds. Falls back to JVM logical
 * fonts (`Serif` / `SansSerif`) only when no better candidate exists.
 *
 * Named heuristic: `SystemAwtFontProbe`.
 */
class SystemAwtFontResolver : AwtFontResolver {
    private val cjkFamily: String
    private val latinFamily: String

    init {
        val available = java.awt.GraphicsEnvironment
            .getLocalGraphicsEnvironment()
            .availableFontFamilyNames
            .toSet()

        cjkFamily = CJK_CANDIDATES.firstOrNull { it in available } ?: Font.SERIF
        latinFamily = LATIN_CANDIDATES.firstOrNull { it in available } ?: Font.SANS_SERIF
    }

    override fun resolve(input: ShapingInput): Font {
        val family = input.style.fontFamilies.firstOrNull()
            ?: input.fontDecision.candidate.family.takeUnless { it == input.fontDecision.candidate.key }
            ?: input.fontDecision.role.resolvedFamily()
        return Font(family, Font.PLAIN, 1).deriveFont(input.style.fontSize)
    }

    private fun FontRole.resolvedFamily(): String =
        when (this) {
            FontRole.CjkText,
            FontRole.CjkPunctuation,
            -> cjkFamily

            FontRole.LatinText,
            FontRole.Symbol,
            FontRole.Emoji,
            FontRole.Unknown,
            -> latinFamily
        }

    companion object {
        /** Ordered by preference; first match wins. */
        private val CJK_CANDIDATES = listOf(
            "Source Han Sans CN",
            "Source Han Sans CN VF",
            "Noto Sans CJK SC",
            "PingFang SC",
            "Hiragino Sans GB",
            "Sarasa UI SC",
            "Heiti SC",
            "STHeiti",
        )

        private val LATIN_CANDIDATES = listOf(
            "Inter Variable",
            "Inter",
            "SF Pro Text",
            "SF Pro",
            "Roboto",
            "Helvetica Neue",
        )
    }
}

private fun Rectangle2D.toGlyphLocalRectOrNull(originX: Float): Rect? {
    if (isEmpty) return null
    return Rect(
        left = minX.toFloat() - originX,
        top = minY.toFloat(),
        right = maxX.toFloat() - originX,
        bottom = maxY.toFloat(),
    )
}
