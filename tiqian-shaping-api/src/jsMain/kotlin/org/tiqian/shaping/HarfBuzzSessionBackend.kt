@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.shaping

import kotlin.JsFun
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontMetricSource
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics

/**
 * Synchronous Kotlin view of an immutable JavaScript HarfBuzz font session.
 *
 * Node build-time precomputation and browser Kotlin/JS fallback both install the
 * same `__TiqianFontBackend`, created from the same published font bytes. The
 * layout engine therefore receives identical glyph, advance, ink and OpenType
 * metric evidence on both sides of the snapshot boundary.
 */
class HarfBuzzSessionTextShaper(
    private val sessionId: String,
) : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        val source = input.text.substring(input.range.start, input.range.end)
        val handle = sessionShape(
            sessionId = sessionId,
            displayText = input.displayText,
            fontFamilies = input.style.fontFamilies.joinToString(FAMILY_SEPARATOR),
            fontSize = input.style.fontSize.toDouble(),
            fontWeight = input.style.fontWeight,
            italic = input.style.italic,
            locale = input.style.locale,
            role = input.fontDecision.role.name,
        )
        try {
            val openTypeFeatures = buildList {
                for (index in 0 until shapeFeatureCount(handle)) {
                    shapeFeature(handle, index).takeIf(String::isNotBlank)?.let(::add)
                }
            }
            val glyphs = buildList {
                for (index in 0 until shapeGlyphCount(handle)) {
                    add(
                        Glyph(
                            id = shapeGlyphId(handle, index).toUInt(),
                            clusterRange = input.range,
                            advance = shapeGlyphAdvance(handle, index).toFloat(),
                            x = shapeGlyphX(handle, index).toFloat(),
                            y = shapeGlyphY(handle, index).toFloat(),
                            bounds = shapeGlyphBounds(handle, index),
                        ),
                    )
                }
            }
            val advance = shapeAdvance(handle).toFloat()
            val faceId = shapeFaceId(handle)
            return ShapingResult(
                clusters = listOf(
                    Cluster(
                        range = input.range,
                        text = source,
                        displayText = input.displayText,
                        fontKey = input.fontDecision.candidate.key,
                        advance = advance,
                    ),
                ),
                glyphRuns = listOf(
                    GlyphRun(
                        range = input.range,
                        fontKey = input.fontDecision.candidate.key,
                        glyphs = glyphs,
                        advance = advance,
                        openTypeFeatures = openTypeFeatures,
                    ),
                ),
                decisions = listOf(
                    ShapingDecisionInfo(
                        range = input.range,
                        sourceText = source,
                        displayText = input.displayText,
                        fontKey = input.fontDecision.candidate.key,
                        glyphCount = glyphs.size,
                        advance = advance,
                        source = ShapingSource.HarfBuzz.name,
                        reason = "SharedHarfBuzzSession:face=$faceId; " +
                            "instance=${shapeFontInstanceId(handle)}; current-segment-context; " +
                            "features=${openTypeFeatures.joinToString(",").ifEmpty { "default" }}; " +
                            "unsafeToBreakGlyphs=${shapeUnsafeBreakCount(handle)}",
                        glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
                        missingGlyphs = glyphs.count { it.id == 0u },
                        resolvedFace = faceId,
                        script = shapeScript(handle),
                        language = input.style.locale,
                        featureEvidence = openTypeFeatures
                            .takeIf { it.isNotEmpty() }
                            ?.joinToString(","),
                    ),
                ),
            )
        } finally {
            releaseSessionShape(handle)
        }
    }

    private fun shapeGlyphBounds(handle: Int, index: Int): Rect? {
        val left = shapeGlyphBound(handle, index, 0)
        if (!left.isFinite()) return null
        return Rect(
            left = left.toFloat(),
            top = shapeGlyphBound(handle, index, 1).toFloat(),
            right = shapeGlyphBound(handle, index, 2).toFloat(),
            bottom = shapeGlyphBound(handle, index, 3).toFloat(),
        )
    }
}
class HarfBuzzSessionFontMetricsResolver(
    private val sessionId: String,
) : FontMetricsResolver {
    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        val handle = sessionMetrics(
            sessionId = sessionId,
            fontFamilies = request.fontFamilies.joinToString(FAMILY_SEPARATOR),
            fontSize = request.fontSize.toDouble(),
            fontWeight = request.fontWeight,
            italic = request.italic,
            role = request.role.name,
            faceSelectionText = request.faceSelectionText,
        )
        try {
            return RawFontMetrics(
                ascent = metricValue(handle, 0).toFloat(),
                descent = metricValue(handle, 1).toFloat(),
                leading = metricValue(handle, 2).toFloat(),
                source = FontMetricSource.RawTables,
                typoAscent = metricValue(handle, 3).takeIf(Double::isFinite)?.toFloat(),
                typoDescent = metricValue(handle, 4).takeIf(Double::isFinite)?.toFloat(),
            )
        } finally {
            releaseSessionMetrics(handle)
        }
    }
}

private const val FAMILY_SEPARATOR = "\u001f"
@JsFun("(sessionId, displayText, fontFamilies, fontSize, fontWeight, italic, locale, role) => globalThis.__TiqianFontBackend.shape(sessionId, displayText, fontFamilies, fontSize, fontWeight, italic, locale, role)")
private external fun sessionShape(
    sessionId: String,
    displayText: String,
    fontFamilies: String,
    fontSize: Double,
    fontWeight: Int,
    italic: Boolean,
    locale: String,
    role: String,
): Int
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeGlyphCount(handle)")
private external fun shapeGlyphCount(handle: Int): Int
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.shapeGlyphId(handle, index)")
private external fun shapeGlyphId(handle: Int, index: Int): Int
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.shapeGlyphAdvance(handle, index)")
private external fun shapeGlyphAdvance(handle: Int, index: Int): Double
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.shapeGlyphX(handle, index)")
private external fun shapeGlyphX(handle: Int, index: Int): Double
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.shapeGlyphY(handle, index)")
private external fun shapeGlyphY(handle: Int, index: Int): Double
@JsFun("(handle, index, edge) => globalThis.__TiqianFontBackend.shapeGlyphBound(handle, index, edge)")
private external fun shapeGlyphBound(handle: Int, index: Int, edge: Int): Double
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeAdvance(handle)")
private external fun shapeAdvance(handle: Int): Double
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeFaceId(handle)")
private external fun shapeFaceId(handle: Int): String
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeFontInstanceId(handle)")
private external fun shapeFontInstanceId(handle: Int): String
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeScript(handle)")
private external fun shapeScript(handle: Int): String
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeFeatureCount(handle)")
private external fun shapeFeatureCount(handle: Int): Int
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.shapeFeature(handle, index)")
private external fun shapeFeature(handle: Int, index: Int): String
@JsFun("(handle) => globalThis.__TiqianFontBackend.shapeUnsafeBreakCount(handle)")
private external fun shapeUnsafeBreakCount(handle: Int): Int
@JsFun("(handle) => globalThis.__TiqianFontBackend.releaseShape(handle)")
private external fun releaseSessionShape(handle: Int)
@JsFun("(sessionId, fontFamilies, fontSize, fontWeight, italic, role, faceSelectionText) => globalThis.__TiqianFontBackend.metrics(sessionId, fontFamilies, fontSize, fontWeight, italic, role, faceSelectionText)")
private external fun sessionMetrics(
    sessionId: String,
    fontFamilies: String,
    fontSize: Double,
    fontWeight: Int,
    italic: Boolean,
    role: String,
    faceSelectionText: String,
): Int
@JsFun("(handle, index) => globalThis.__TiqianFontBackend.metricValue(handle, index)")
private external fun metricValue(handle: Int, index: Int): Double
@JsFun("(handle) => globalThis.__TiqianFontBackend.releaseMetrics(handle)")
private external fun releaseSessionMetrics(handle: Int)
