@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package org.tiqian.shaping

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.DoubleVar
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.allocPointerTo
import kotlinx.cinterop.cstr
import kotlinx.cinterop.get
import kotlinx.cinterop.invoke
import kotlinx.cinterop.ptr
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.pointed
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.toKString
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontMetricSource
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.shaping.backend.tiqian_font_backend_vtable_t

/**
 * Vtable consumer for native hosts (ADR 0050 PackedFfiCalls). The Rust font
 * session installs its callbacks through `tiqian_install_font_backend`; this
 * shaper maps one packed segment buffer onto the same `ShapingResult` the JS
 * lane builds from `__TiqianFontBackend`, so the engine sees identical
 * evidence on both sides of the snapshot boundary.
 */
class NativeFontBackendTextShaper(
    private val sessionId: String,
) : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult {
        val source = input.text.substring(input.range.start, input.range.end)
        val families = input.style.fontFamilies.joinToString(FAMILY_SEPARATOR)
        val backend = NativeFontBackendRegistry.require()
        val buffer = backend.shapePacked(
            sessionId = sessionId,
            displayText = input.displayText,
            serializedFamilies = families,
            fontSize = input.style.fontSize.toDouble(),
            fontWeight = input.style.fontWeight,
            italic = input.style.italic,
            locale = input.style.locale,
            role = input.fontDecision.role.name,
            sourceText = source,
        )
        val reader = ShapeBufferReader(buffer)
        val openTypeFeatures = reader.features()
        val glyphs = (0 until reader.glyphCount).map { index ->
            Glyph(
                id = reader.glyphId(index).toUInt(),
                clusterRange = input.range,
                advance = reader.glyphAdvance(index).toFloat(),
                x = reader.glyphX(index).toFloat(),
                y = reader.glyphY(index).toFloat(),
                bounds = reader.glyphBounds(index),
            )
        }
        val advance = reader.totalAdvance.toFloat()
        val faceId = reader.faceId()
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
                    // Byte-identical to the JS lane's reason so engine dumps
                    // can be diffed across lanes while parity is proven.
                    reason = "SharedHarfBuzzSession:face=$faceId; " +
                        "instance=${reader.instanceId()}; current-segment-context; " +
                        "features=${openTypeFeatures.joinToString(",").ifEmpty { "default" }}; " +
                        "unsafeToBreakGlyphs=${reader.unsafeBreakCount}",
                    glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
                    missingGlyphs = glyphs.count { it.id == 0u },
                    resolvedFace = faceId,
                    script = reader.script(),
                    language = input.style.locale,
                    featureEvidence = openTypeFeatures
                        .takeIf { it.isNotEmpty() }
                        ?.joinToString(","),
                ),
            ),
        )
    }
}

class NativeFontBackendFontMetricsResolver(
    private val sessionId: String,
) : FontMetricsResolver {
    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        val backend = NativeFontBackendRegistry.require()
        val values = backend.metricsPacked(
            sessionId = sessionId,
            serializedFamilies = request.fontFamilies.joinToString(FAMILY_SEPARATOR),
            fontSize = request.fontSize.toDouble(),
            fontWeight = request.fontWeight,
            italic = request.italic,
            role = request.role.name,
            faceSelectionText = request.faceSelectionText,
        )
        return RawFontMetrics(
            ascent = values[0].toFloat(),
            descent = values[1].toFloat(),
            leading = values[2].toFloat(),
            source = FontMetricSource.RawTables,
            typoAscent = values[3].takeIf(Double::isFinite)?.toFloat(),
            typoDescent = values[4].takeIf(Double::isFinite)?.toFloat(),
        )
    }
}

/** Offsets and sizes from tiqian_font_backend.h; all targets are LE. */
private const val FAMILY_SEPARATOR = "\u001F"
private const val SHAPE_HEADER_BYTES = 64
private const val SHAPE_RECORD_BYTES = 64
private const val SHAPE_BUFFER_MAGIC = 0x54515053

/** GSUB can emit more glyphs than code points; double the length plus slack. */
private fun estimatedShapeBufferSize(displayTextLength: Int, serializedFamilies: String): Int {
    val glyphSlots = maxOf(16, displayTextLength * 2)
    val stringArea = 384 + serializedFamilies.encodeToByteArray().size
    return SHAPE_HEADER_BYTES + glyphSlots * SHAPE_RECORD_BYTES + stringArea
}

private fun tiqian_font_backend_vtable_t.shapePacked(
    sessionId: String,
    displayText: String,
    serializedFamilies: String,
    fontSize: Double,
    fontWeight: Int,
    italic: Boolean,
    locale: String,
    role: String,
    sourceText: String,
): ByteArray = memScoped {
    val errorSlot = allocPointerTo<ByteVar>()
    errorSlot.value = null
    var buffer = ByteArray(estimatedShapeBufferSize(displayText.length, serializedFamilies))
    var needed = invokeShape(
        displayText, serializedFamilies, fontSize, fontWeight, italic, locale, role, sourceText,
        sessionId, buffer, errorSlot,
    )
    if (needed > buffer.size) {
        // Capacity contract from the ADR: one retry after the backend reports
        // the required size; a second shortfall is a backend contract break.
        checkError(errorSlot, needed)
        buffer = ByteArray(needed.toInt())
        needed = invokeShape(
            displayText, serializedFamilies, fontSize, fontWeight, italic, locale, role, sourceText,
            sessionId, buffer, errorSlot,
        )
        if (needed > buffer.size) error("FontBackendBufferOverflow")
    }
    checkError(errorSlot, needed)
    buffer
}

private fun tiqian_font_backend_vtable_t.invokeShape(
    displayText: String,
    serializedFamilies: String,
    fontSize: Double,
    fontWeight: Int,
    italic: Boolean,
    locale: String,
    role: String,
    sourceText: String,
    sessionId: String,
    buffer: ByteArray,
    errorSlot: kotlinx.cinterop.CPointerVar<ByteVar>,
): Long = memScoped {
    buffer.usePinned { pinned ->
        shape!!.invoke(
            sessionId.cstr.ptr,
            displayText.cstr.ptr,
            serializedFamilies.cstr.ptr,
            fontSize,
            fontWeight,
            if (italic) 1 else 0,
            locale.cstr.ptr,
            role.cstr.ptr,
            sourceText.cstr.ptr,
            pinned.addressOf(0).reinterpret<UByteVar>(),
            buffer.size.toULong(),
            errorSlot.ptr,
        )
    }
}

private fun tiqian_font_backend_vtable_t.metricsPacked(
    sessionId: String,
    serializedFamilies: String,
    fontSize: Double,
    fontWeight: Int,
    italic: Boolean,
    role: String,
    faceSelectionText: String,
): DoubleArray = memScoped {
    val errorSlot = allocPointerTo<ByteVar>()
    errorSlot.value = null
    val out = allocArray<DoubleVar>(5)
    val status = metrics!!.invoke(
        sessionId.cstr.ptr,
        serializedFamilies.cstr.ptr,
        fontSize,
        fontWeight,
        if (italic) 1 else 0,
        role.cstr.ptr,
        faceSelectionText.cstr.ptr,
        out,
        errorSlot.ptr,
    )
    if (status != 0L) throwNamedError(errorSlot.value)
    doubleArrayOf(out[0], out[1], out[2], out[3], out[4])
}

private fun tiqian_font_backend_vtable_t.checkError(
    errorSlot: kotlinx.cinterop.CPointerVar<ByteVar>,
    needed: Long,
) {
    if (needed < 0) throwNamedError(errorSlot.value)
}

private fun tiqian_font_backend_vtable_t.throwNamedError(message: CPointer<ByteVar>?): Nothing {
    val text = message?.toKString() ?: "UnknownFontBackendError"
    if (message != null) release_string!!.invoke(message)
    error(text)
}

/** Reads the packed shape buffer produced by the session. */
private class ShapeBufferReader(private val bytes: ByteArray) {
    init {
        if (u32At(0) != SHAPE_BUFFER_MAGIC) error("FontBackendBufferMismatch")
        if (u32At(4).toUInt() != NativeFontBackendRegistry.PROTOCOL_REVISION) {
            error("FontBackendBufferMismatch")
        }
    }

    val glyphCount: Int get() = u32At(8)
    val unsafeBreakCount: Int get() = u32At(16)
    val totalAdvance: Double get() = f64At(24)

    fun faceId(): String = utf8At(u32At(32), u32At(36))
    fun instanceId(): String = utf8At(u32At(40), u32At(44))
    fun script(): String = utf8At(u32At(48), u32At(52))

    fun features(): List<String> =
        utf8At(u32At(56), u32At(60)).split(FAMILY_SEPARATOR).filter(String::isNotBlank)

    fun glyphId(index: Int): Int = recordField(index, 0).toInt()
    fun glyphAdvance(index: Int): Double = recordField(index, 1)
    fun glyphX(index: Int): Double = recordField(index, 2)
    fun glyphY(index: Int): Double = recordField(index, 3)

    fun glyphBounds(index: Int): Rect? {
        val left = recordField(index, 4)
        if (!left.isFinite()) return null
        return Rect(
            left = left.toFloat(),
            top = recordField(index, 5).toFloat(),
            right = recordField(index, 6).toFloat(),
            bottom = recordField(index, 7).toFloat(),
        )
    }

    private fun recordField(index: Int, field: Int): Double =
        f64At(SHAPE_HEADER_BYTES + index * SHAPE_RECORD_BYTES + field * 8)

    private fun u32At(offset: Int): Int =
        (bytes[offset].toInt() and 0xFF) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
            ((bytes[offset + 2].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 3].toInt() and 0xFF) shl 24)

    private fun f64At(offset: Int): Double {
        var bits = 0L
        for (index in 7 downTo 0) {
            bits = (bits shl 8) or (bytes[offset + index].toLong() and 0xFF)
        }
        return Double.fromBits(bits)
    }

    private fun utf8At(offset: Int, length: Int): String {
        if (length == 0) return ""
        return bytes.decodeToString(offset, offset + length)
    }
}
