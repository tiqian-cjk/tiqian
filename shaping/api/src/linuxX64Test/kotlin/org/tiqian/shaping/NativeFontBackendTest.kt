@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.experimental.ExperimentalNativeApi::class)

package org.tiqian.shaping

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.DoubleVar
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.get
import kotlinx.cinterop.nativeHeap
import kotlinx.cinterop.pointed
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.set
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.staticCFunction
import kotlinx.cinterop.value
import org.tiqian.core.Rect
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontRole
import org.tiqian.shaping.backend.tiqian_font_backend_vtable_t
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Fake font backend behind the real vtable protocol: the callbacks write the
 * same packed buffer the Rust session will produce, so these tests pin the
 * buffer contract and the `ShapingResult` mapping without linking Rust.
 * staticCFunction callbacks cannot capture state, so the fake reads the
 * top-level knobs below.
 */
private var fakeMode = 0 // 0 fill, 1 named error, 2 bad magic
private var fakeGlyphCount = 2
private var shapeCalls = 0
private var fakeMetricsValues = doubleArrayOf(1.16, 0.288, 0.0, 0.88, 0.12)

class NativeFontBackendTest {
    private val shaper = NativeFontBackendTextShaper("tq-font-test-1")
    private val metricsResolver = NativeFontBackendFontMetricsResolver("tq-font-test-1")

    @AfterTest
    fun tearDown() {
        NativeFontBackendRegistry.resetForTests()
        fakeMode = 0
        fakeGlyphCount = 2
        shapeCalls = 0
        fakeMetricsValues = doubleArrayOf(1.16, 0.288, 0.0, 0.88, 0.12)
    }

    @Test
    fun installValidatesRevision() {
        assertEquals(3, tiqianInstallFontBackend(null))
        assertEquals(0, installFakeBackend())
        assertEquals(0, installFakeBackend()) // same revision reinstalls are a no-op
        NativeFontBackendRegistry.resetForTests()
        assertEquals(2, tiqianInstallFontBackend(fakeVtable(revision = 9u)))
    }

    @Test
    fun shapeWithoutBackendReportsNamedError() {
        val failure = assertFailsWith<IllegalStateException> { shaper.shape(shapingInput()) }
        assertEquals("FontBackendNotInstalled", failure.message)
    }

    @Test
    fun shapeMapsPackedBufferToShapingResult() {
        installFakeBackend()
        val result = shaper.shape(shapingInput())
        val run = result.glyphRuns.single()
        assertEquals(listOf("fwid", "palt"), run.openTypeFeatures)
        assertEquals(18.5f, run.advance)
        val first = run.glyphs[0]
        assertEquals(111u, first.id)
        assertEquals(10.5f, first.advance)
        assertEquals(0f, first.x)
        assertEquals(0.25f, first.y)
        assertEquals(Rect(1f, 2f, 3f, 4f), first.bounds)
        val second = run.glyphs[1]
        assertNull(second.bounds)
        val decision = result.decisions.single()
        assertEquals("hani", decision.script)
        assertEquals("Source Han Sans CN|normal|400-400|abcd0123456789ab|0", decision.resolvedFace)
        assertEquals(1, decision.glyphsWithoutInkBounds)
        assertEquals(1, decision.missingGlyphs)
        assertTrue(decision.reason.startsWith("SharedHarfBuzzSession:face=Source Han Sans CN"))
    }

    @Test
    fun shapeRetriesOnceWithReportedCapacity() {
        installFakeBackend()
        fakeGlyphCount = 40 // exceeds the segment-length estimate, forces one retry
        val result = shaper.shape(shapingInput())
        assertEquals(40, result.glyphRuns.single().glyphs.size)
        assertEquals(2, shapeCalls)
    }

    @Test
    fun shapeSurfacesNamedBackendError() {
        installFakeBackend()
        fakeMode = 1
        val failure = assertFailsWith<IllegalStateException> { shaper.shape(shapingInput()) }
        assertEquals("MissingGlyph:face=Source Han Sans CN", failure.message)
    }

    @Test
    fun shapeRejectsBadBufferMagic() {
        installFakeBackend()
        fakeMode = 2
        val failure = assertFailsWith<IllegalStateException> { shaper.shape(shapingInput()) }
        assertEquals("FontBackendBufferMismatch", failure.message)
    }

    @Test
    fun metricsMapsPackedRecord() {
        installFakeBackend()
        val metrics = metricsResolver.resolve(metricsRequest())
        assertEquals(18.56f, metrics.ascent)
        assertEquals(4.608f, metrics.descent)
        assertEquals(0f, metrics.leading)
        assertEquals(14.08f, metrics.typoAscent)
        assertEquals(1.92f, metrics.typoDescent)
    }

    @Test
    fun metricsTreatsNaNAsMissingTypoValue() {
        installFakeBackend()
        fakeMetricsValues = doubleArrayOf(1.0, 0.2, 0.0, Double.NaN, Double.NaN)
        val metrics = metricsResolver.resolve(metricsRequest())
        assertEquals(16f, metrics.ascent)
        assertNull(metrics.typoAscent)
        assertNull(metrics.typoDescent)
    }

    private fun installFakeBackend(): Int = tiqianInstallFontBackend(fakeVtable(revision = 1u))

    private fun fakeVtable(revision: UInt): CPointer<tiqian_font_backend_vtable_t> {
        val layout = nativeHeap.alloc<tiqian_font_backend_vtable_t>()
        layout.size = sizeOf<tiqian_font_backend_vtable_t>().toUInt()
        layout.protocol_revision = revision
        layout.shape = staticCFunction(::fakeShape)
        layout.metrics = staticCFunction(::fakeMetrics)
        layout.release_string = staticCFunction(::fakeReleaseString)
        return layout.ptr
    }

    private fun shapingInput(): ShapingInput = ShapingInput(
        text = "AB",
        range = TextRange(0, 2),
        style = TextStyle(fontFamilies = listOf("Source Han Sans CN"), fontSize = 16f),
        fontDecision = FontDecision(
            range = TextRange(0, 2),
            candidate = FontCandidate(
                key = "test-cjk",
                family = "Source Han Sans CN",
                role = FontRole.CjkText,
            ),
            role = FontRole.CjkText,
            reason = "test",
        ),
    )

    private fun metricsRequest(): FontMetricsRequest = FontMetricsRequest(
        fontKey = "test-cjk",
        fontSize = 16f,
        role = FontRole.CjkText,
        locale = "zh-Hans",
        fontFamilies = listOf("Source Han Sans CN"),
    )
}

private fun fakeShape(
    sessionId: CPointer<ByteVar>?,
    displayText: CPointer<ByteVar>?,
    serializedFamilies: CPointer<ByteVar>?,
    fontSize: Double,
    fontWeight: Int,
    italic: Int,
    locale: CPointer<ByteVar>?,
    role: CPointer<ByteVar>?,
    sourceText: CPointer<ByteVar>?,
    buffer: CPointer<UByteVar>?,
    capacity: ULong,
    errorOut: CPointer<CPointerVar<ByteVar>>?,
): Long {
    shapeCalls += 1
    if (fakeMode == 1) {
        writeError(errorOut, "MissingGlyph:face=Source Han Sans CN")
        return -1
    }
    val payload = fakeShapeBuffer()
    val needed = payload.size.toLong()
    if (buffer == null || capacity.toLong() < needed) return needed
    val native = buffer.reinterpret<ByteVar>()
    for (index in payload.indices) native[index] = payload[index]
    return needed
}

private fun fakeMetrics(
    sessionId: CPointer<ByteVar>?,
    serializedFamilies: CPointer<ByteVar>?,
    fontSize: Double,
    fontWeight: Int,
    italic: Int,
    role: CPointer<ByteVar>?,
    faceSelectionText: CPointer<ByteVar>?,
    outMetrics: CPointer<DoubleVar>?,
    errorOut: CPointer<CPointerVar<ByteVar>>?,
): Long {
    if (outMetrics == null) return -1
    for (index in 0 until 5) outMetrics[index] = fakeMetricsValues[index] * fontSize
    return 0
}

private fun fakeReleaseString(string: CPointer<ByteVar>?) = Unit

private fun writeError(errorOut: CPointer<CPointerVar<ByteVar>>?, message: String) {
    if (errorOut == null) return
    val bytes = message.encodeToByteArray()
    val memory = nativeHeap.allocArray<ByteVar>(bytes.size + 1)
    for (index in bytes.indices) memory[index] = bytes[index]
    memory[bytes.size] = 0
    errorOut.pointed.value = memory
}

/** Builds the packed buffer exactly as tiqian_font_backend.h documents it. */
private fun fakeShapeBuffer(): ByteArray {
    val glyphs = if (fakeMode == 2) {
        listOf(fakeGlyph(111, 10.5, 0.0, 0.25, doubleArrayOf(1.0, 2.0, 3.0, 4.0)))
    } else {
        (0 until fakeGlyphCount).map { index ->
            when (index) {
                0 -> fakeGlyph(111, 10.5, 0.0, 0.25, doubleArrayOf(1.0, 2.0, 3.0, 4.0))
                1 -> fakeGlyph(0, 8.0, 10.5, -0.25, null)
                else -> fakeGlyph(200 + index, 1.0, index.toDouble(), 0.0, doubleArrayOf(0.0, 0.0, 1.0, 1.0))
            }
        }
    }
    val faceId = "Source Han Sans CN|normal|400-400|abcd0123456789ab|0"
    val instanceId = "abcd0123456789ab:0:wght=400"
    val script = "hani"
    val featureSeparator = 0x1F.toChar()
    val joinedFeatures = "fwid" + featureSeparator + "palt"
    val faceIdBytes = faceId.encodeToByteArray()
    val instanceIdBytes = instanceId.encodeToByteArray()
    val scriptBytes = script.encodeToByteArray()
    val featuresBytes = joinedFeatures.encodeToByteArray()
    val total = 64 + glyphs.size * 64 +
        faceIdBytes.size + instanceIdBytes.size + scriptBytes.size + featuresBytes.size
    val bytes = ByteArray(total)
    fun u32(offset: Int, value: Int) {
        bytes[offset] = (value and 0xFF).toByte()
        bytes[offset + 1] = ((value ushr 8) and 0xFF).toByte()
        bytes[offset + 2] = ((value ushr 16) and 0xFF).toByte()
        bytes[offset + 3] = ((value ushr 24) and 0xFF).toByte()
    }
    fun f64(offset: Int, value: Double) {
        val bits = value.toRawBits()
        for (index in 0 until 8) {
            bytes[offset + index] = ((bits ushr (index * 8)) and 0xFF).toByte()
        }
    }
    u32(0, if (fakeMode == 2) 0x00515053 else 0x54515053)
    u32(4, 1)
    u32(8, glyphs.size)
    u32(12, 2)
    u32(16, 1)
    u32(20, 0)
    f64(24, 18.5)
    var cursor = 64 + glyphs.size * 64
    fun putBytes(payload: ByteArray): Int {
        payload.copyInto(bytes, cursor)
        val start = cursor
        cursor += payload.size
        return start
    }
    u32(32, putBytes(faceIdBytes)); u32(36, faceIdBytes.size)
    u32(40, putBytes(instanceIdBytes)); u32(44, instanceIdBytes.size)
    u32(48, putBytes(scriptBytes)); u32(52, scriptBytes.size)
    u32(56, putBytes(featuresBytes)); u32(60, featuresBytes.size)
    glyphs.forEachIndexed { index, glyph ->
        val base = 64 + index * 64
        f64(base, glyph.id.toDouble())
        f64(base + 8, glyph.advance)
        f64(base + 16, glyph.x)
        f64(base + 24, glyph.y)
        val bounds = glyph.bounds
        for (edge in 0 until 4) {
            f64(base + 32 + edge * 8, bounds?.get(edge) ?: Double.NaN)
        }
    }
    return bytes
}

private class FakeGlyph(
    val id: Int,
    val advance: Double,
    val x: Double,
    val y: Double,
    val bounds: DoubleArray?,
)

private fun fakeGlyph(
    id: Int,
    advance: Double,
    x: Double,
    y: Double,
    bounds: DoubleArray?,
) = FakeGlyph(id, advance, x, y, bounds)
