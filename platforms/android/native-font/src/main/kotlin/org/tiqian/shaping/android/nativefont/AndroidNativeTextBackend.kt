package org.tiqian.shaping.android.nativefont

import android.content.Context
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontMetricSource
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.FontRole
import org.tiqian.font.RawFontMetrics
import org.tiqian.shaping.ReplayableFontFaceRequest
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingIssue
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.ShapingSource
import org.tiqian.shaping.TextShaper
import kotlin.math.abs

/** No controlled face covers the segment; the platform text stack measures and draws it. */
const val NO_COVERING_FACE_STRING_DRAW_ISSUE = "NoCoveringFaceStringDraw"

/** API 23+ correctness backend: one controlled byte face feeds HB shape, FT metrics/ink and outline replay. */
class AndroidNativeTextShaper(
    context: Context,
) : TextShaper {
    private val applicationContext = context.applicationContext

    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val scriptCode = input.fontDecision.role.nativeScriptCode()
        val scriptName = input.fontDecision.role.nativeScriptName()
        val features = buildList {
            // HarfBuzz enables locl by default; spelling it out pins the evidence
            // and keeps custom feature runs replayable across backends.
            if (scriptCode == SCRIPT_HANI) add("locl=1")
            addAll(input.openTypeFeatures)
        }.distinct()
        val face = resolveFace(
            role = input.fontDecision.role,
            families = input.style.fontFamilies,
            fontSize = input.style.fontSize,
            weight = input.style.fontWeight,
            italic = input.style.italic,
            locale = input.style.locale,
            selectionText = displayText,
        )
        if (!face.replayable) {
            return when (face.stringDrawCause) {
                PlatformStringDrawCause.NoCoveringFace ->
                    platformStringDrawResult(input, sourceText, displayText, face, "NoCoveringFacePlatformDegrade", NO_COVERING_FACE_STRING_DRAW_ISSUE)
                else ->
                    platformStringDrawResult(input, sourceText, displayText, face, "PlatformMultiFaceStringDrawDegrade", ShapingIssue.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE)
            }
        }
        val shaped = face.nativeFace.shape(
            text = displayText,
            fontSize = input.style.fontSize,
            locale = input.style.locale,
            scriptCode = scriptCode,
            features = features,
        )
        val halt = measureHalt(input, face, shaped)
        val glyphs = shaped.glyphIds.indices.map { index ->
            val p = index * 4
            val bound = shaped.bounds.copyOfRange(p, p + 4).let { values ->
                if (values.any(Float::isNaN)) {
                    null
                } else {
                    AndroidNativeGlyphReplay.transformInkBounds(
                        bounds = Rect(values[0], values[1], values[2], values[3]),
                        syntheticItalic = TiqianAndroidFontBackend.isSyntheticItalicFace(face.descriptor.id.value),
                    )
                }
            }
            Glyph(
                id = shaped.glyphIds[index],
                clusterRange = input.range,
                advance = shaped.positions[p + 2],
                x = shaped.positions[p],
                y = shaped.positions[p + 1],
                renderFontKey = face.descriptor.id.value,
                bounds = bound,
                haltAdvance = halt?.first,
                haltPlacementX = halt?.second,
            )
        }
        val physicalFontKey = face.descriptor.id.value
        return ShapingResult(
            clusters = listOf(
                Cluster(
                    range = input.range,
                    text = sourceText,
                    displayText = displayText,
                    fontKey = physicalFontKey,
                    advance = shaped.advance,
                ),
            ),
            glyphRuns = listOf(
                GlyphRun(
                    range = input.range,
                    fontKey = physicalFontKey,
                    glyphs = glyphs,
                    advance = shaped.advance,
                    openTypeFeatures = features,
                ),
            ),
            decisions = listOf(
                ShapingDecisionInfo(
                    range = input.range,
                    sourceText = sourceText,
                    displayText = displayText,
                    fontKey = physicalFontKey,
                    glyphCount = glyphs.size,
                    advance = shaped.advance,
                    source = ShapingSource.HarfBuzz.name,
                    reason = buildString {
                        append("ControlledFontBytesShapeOnce")
                        if (input.fontDecision.role == FontRole.CjkPunctuation) {
                            append(":CjkPunctuationHanFaceAnchor")
                        }
                        if (!face.exactFamily) append(":RequestedFamilyUnavailable")
                        if (!face.exactStyle) append(":RequestedStyleFaceUnavailable")
                        if (face.syntheticBold) append(":FakeBoldWhenNoBoldFace")
                    },
                    glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
                    missingGlyphs = shaped.missingGlyphs,
                    resolvedFace = physicalFontKey,
                    script = scriptName,
                    language = input.style.locale,
                    strategy = "StableFontFaceIdFreeTypeOutlineReplay",
                    featureEvidence = "${TiqianAndroidFontBackend.nativeVersions};features=${features.joinToString()}",
                ),
            ),
        )
    }

    /**
     * PlatformMultiFaceStringDrawDegrade: the platform selected more than one physical face for
     * this segment (a CJK base plus a combining mark its face lacks, a non-CJK script run, or a
     * Latin word crossing a fallback boundary), so no single controlled-byte face can replay it.
     * Emit a non-replayable run — one glyph with a null `renderFontKey` carrying the
     * platform-measured advance — which the Android renderer already draws with
     * `Canvas.drawTextRun` through the same platform text stack that produced the advance. The
     * base face resolved for metrics stays correct for line height; only glyph-granular ink is
     * given up, reported as [ShapingIssue.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE].
     */
    private fun platformStringDrawResult(
        input: ShapingInput,
        sourceText: String,
        displayText: String,
        face: ResolvedNativeFontFace,
        reason: String,
        capabilityIssue: String,
    ): ShapingResult {
        val advance = face.degradedRunAdvance
        val faceKey = face.descriptor.id.value
        val glyph = Glyph(
            id = 0,
            clusterRange = input.range,
            advance = advance,
            renderFontKey = null,
        )
        return ShapingResult(
            clusters = listOf(
                Cluster(
                    range = input.range,
                    text = sourceText,
                    displayText = displayText,
                    fontKey = faceKey,
                    advance = advance,
                ),
            ),
            glyphRuns = listOf(
                GlyphRun(
                    range = input.range,
                    fontKey = faceKey,
                    glyphs = listOf(glyph),
                    advance = advance,
                ),
            ),
            decisions = listOf(
                ShapingDecisionInfo(
                    range = input.range,
                    sourceText = sourceText,
                    displayText = displayText,
                    fontKey = faceKey,
                    glyphCount = 1,
                    advance = advance,
                    source = ShapingSource.AndroidPaint.name,
                    reason = reason,
                    glyphsWithoutInkBounds = 1,
                    missingGlyphs = 0,
                    resolvedFace = faceKey,
                    script = input.fontDecision.role.nativeScriptName(),
                    language = input.style.locale,
                    strategy = "PlatformDrawTextRunStringFallback",
                    capabilityIssue = capabilityIssue,
                ),
            ),
        )
    }

    private fun measureHalt(
        input: ShapingInput,
        face: ResolvedNativeFontFace,
        regular: NativeShapeResult,
    ): Pair<Float, Float>? {
        if (input.fontDecision.role != FontRole.CjkPunctuation || regular.glyphIds.size != 1) return null
        val halt = face.nativeFace.shape(
            text = input.displayText,
            fontSize = input.style.fontSize,
            locale = input.style.locale,
            scriptCode = SCRIPT_HANI,
            features = (input.openTypeFeatures + "locl=1" + "halt=1").distinct(),
        )
        if (halt.glyphIds.size != 1 || halt.advance <= 0f || halt.advance >= regular.advance - 0.01f) return null
        return halt.advance to halt.positions[0]
    }

    private fun resolveFace(
        role: FontRole,
        families: List<String>,
        fontSize: Float,
        weight: Int,
        italic: Boolean,
        locale: String,
        selectionText: String,
    ): ResolvedNativeFontFace = TiqianAndroidFontBackend.resolveFace(
        applicationContext,
        ReplayableFontFaceRequest(
            role = role,
            preferredFamilies = families.toMutableList(),
            fontSize = fontSize,
            weight = weight,
            italic = italic,
            locale = locale,
            selectionText = selectionText,
        ),
    )
}

class AndroidNativeFontMetricsResolver(
    context: Context,
) : FontMetricsResolver {
    private val applicationContext = context.applicationContext

    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        val face = TiqianAndroidFontBackend.resolveFace(
            applicationContext,
            ReplayableFontFaceRequest(
                role = request.role,
                preferredFamilies = request.fontFamilies.toMutableList(),
                fontSize = request.fontSize,
                weight = request.fontWeight,
                italic = request.italic,
                locale = request.locale,
                selectionText = request.faceSelectionText,
            ),
        )
        val metrics = face.nativeFace.metrics(request.fontSize)
        require(metrics.size >= 5) { "FreeType metric result is incomplete" }
        return RawFontMetrics(
            ascent = metrics[0],
            descent = metrics[1],
            leading = metrics[2],
            source = FontMetricSource.RawTables,
            typoAscent = metrics[3].takeUnless(Float::isNaN),
            typoDescent = metrics[4].takeUnless(Float::isNaN),
        )
    }
}

private fun FontRole.nativeScriptCode(): Int = when (this) {
    FontRole.CjkText,
    FontRole.CjkPunctuation,
    -> SCRIPT_HANI

    FontRole.LatinText -> SCRIPT_LATIN
    else -> SCRIPT_GUESS
}

private fun FontRole.nativeScriptName(): String = when (nativeScriptCode()) {
    SCRIPT_HANI -> "Hani"
    SCRIPT_LATIN -> "Latn"
    else -> "auto"
}

private const val SCRIPT_GUESS = 0
private const val SCRIPT_HANI = 1
private const val SCRIPT_LATIN = 2
