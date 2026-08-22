@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.experimental.ExperimentalNativeApi::class)

package org.tiqian.ffi.cabi

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.DoubleVar
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.nativeHeap
import kotlinx.cinterop.pointed
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.set
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.staticCFunction
import kotlinx.cinterop.toKString
import kotlinx.cinterop.value
import org.tiqian.shaping.backend.tiqian_font_backend_vtable_t
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The fake backend writes the same packed buffers the Rust session produces,
 * so these tests pin the request byte layout and the plan JSON return without
 * linking Rust. staticCFunction callbacks cannot capture state; the fake reads
 * its inputs from the call arguments only.
 */
class LayoutAbiTest {
    @BeforeTest
    fun installBackend() {
        assertEquals(0, tiqianInstallFontBackendCabi(fakeVtable()))
    }

    @Test
    fun layoutWrapsPlainTextIntoTwoLines() {
        val plan = runLayoutRequest(request(text = "字字字字字字字字字字"))
        assertTrue(plan.startsWith("{\"schema\":1,\"layoutRevision\":\"tiqian-layout-v2\""), plan)
        assertEquals(2, plan.split("\"endReason\":").size - 1, plan)
        assertTrue(plan.contains("\"rangeStart\":0,"), plan)
        assertTrue(plan.contains("\"rangeStart\":5,"), plan)
    }

    @Test
    fun entryReturnsPlanAndReleasesBuffers() {
        val plan = callEntryWith(request(text = "正文一段"))
        assertTrue(plan.startsWith("{\"schema\":1"), plan)
    }

    @Test
    fun entryRejectsBadMagicThroughErrorOut() {
        val bytes = request(text = "正文").copyOf().also { it[0] = 0 }
        val memory = nativeHeap.allocArray<ByteVar>(bytes.size)
        for (index in bytes.indices) memory[index] = bytes[index]
        val planSlot = nativeHeap.alloc<CPointerVar<ByteVar>>()
        val errorSlot = nativeHeap.alloc<CPointerVar<ByteVar>>()
        val status = tiqianLayoutParagraph(memory, bytes.size.toULong(), planSlot.ptr, errorSlot.ptr)
        assertEquals(1, status)
        assertNull(planSlot.ptr.pointed.value)
        assertEquals("InvalidLayoutRequestMagic", errorSlot.ptr.pointed.value?.toKString())
        tiqianReleaseBuffer(errorSlot.ptr.pointed.value)
    }

    @Test
    fun readerRejectsStructuralDamage() {
        val valid = request(text = "正文")
        assertIssue("InvalidLayoutRequestTruncated", valid.copyOf(valid.size - 1))
        assertIssue("InvalidLayoutRequestTrailing", valid + byteArrayOf(0))
        assertIssue("InvalidLayoutRequestVersion", valid.copyOf().also { it[4] = 9 })
        assertIssue("InvalidLayoutRequestValue", request(text = "正文", italicByte = 2))
        assertIssue("InvalidLayoutRequestIndex", request(text = "正文", spanEnd = 3))
        assertIssue("InvalidLayoutRequestCode", request(text = "正文", policyCode = 5))
    }

    private fun assertIssue(expected: String, bytes: ByteArray) {
        val failure = assertFailsWith<LayoutRequestFormatException> { readLayoutRequest(bytes) }
        assertEquals(expected, failure.issueName)
    }

    private fun callEntryWith(bytes: ByteArray): String {
        val memory = nativeHeap.allocArray<ByteVar>(bytes.size)
        for (index in bytes.indices) memory[index] = bytes[index]
        val planSlot = nativeHeap.alloc<CPointerVar<ByteVar>>()
        val errorSlot = nativeHeap.alloc<CPointerVar<ByteVar>>()
        val status = tiqianLayoutParagraph(memory, bytes.size.toULong(), planSlot.ptr, errorSlot.ptr)
        assertEquals(0, status, errorSlot.ptr.pointed.value?.toKString() ?: "")
        assertNull(errorSlot.ptr.pointed.value)
        val plan = planSlot.ptr.pointed.value!!.toKString()
        tiqianReleaseBuffer(planSlot.ptr.pointed.value)
        return plan
    }
}

private fun fakeVtable(): CPointer<tiqian_font_backend_vtable_t> {
    val layout = nativeHeap.alloc<tiqian_font_backend_vtable_t>()
    layout.size = sizeOf<tiqian_font_backend_vtable_t>().toUInt()
    layout.protocol_revision = 1u
    layout.shape = staticCFunction(::fakeShape)
    layout.metrics = staticCFunction(::fakeMetrics)
    layout.release_string = staticCFunction(::fakeReleaseString)
    return layout.ptr
}

/** One full-width glyph per UTF-16 unit at the requested font size. */
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
    if (displayText == null) return -1
    val units = displayText.toKString().length
    val payload = fakeShapeBuffer(units, fontSize)
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
    outMetrics[0] = 0.88 * fontSize
    outMetrics[1] = 0.12 * fontSize
    outMetrics[2] = 0.0
    outMetrics[3] = 0.88 * fontSize
    outMetrics[4] = 0.12 * fontSize
    return 0
}

private fun fakeReleaseString(string: CPointer<ByteVar>?) = Unit

/** Builds the packed buffer exactly as tiqian_font_backend.h documents it. */
private fun fakeShapeBuffer(units: Int, fontSize: Double): ByteArray {
    val faceId = "fake-cjk|normal|400-400|0000000000000000|0"
    val instanceId = "0000000000000000:0:wght=400"
    val script = "hani"
    val faceIdBytes = faceId.encodeToByteArray()
    val instanceIdBytes = instanceId.encodeToByteArray()
    val scriptBytes = script.encodeToByteArray()
    val total = 64 + units * 64 + faceIdBytes.size + instanceIdBytes.size + scriptBytes.size
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
    u32(0, 0x54515053)
    u32(4, 1)
    u32(8, units)
    u32(12, 0) // featureCount
    u32(16, 0) // unsafeBreakCount
    u32(20, 0) // reserved
    f64(24, units * fontSize)
    var cursor = 64 + units * 64
    fun putBytes(payload: ByteArray): Int {
        payload.copyInto(bytes, cursor)
        val start = cursor
        cursor += payload.size
        return start
    }
    u32(32, putBytes(faceIdBytes)); u32(36, faceIdBytes.size)
    u32(40, putBytes(instanceIdBytes)); u32(44, instanceIdBytes.size)
    u32(48, putBytes(scriptBytes)); u32(52, scriptBytes.size)
    u32(56, cursor); u32(60, 0) // features: empty range
    repeat(units) { index ->
        val base = 64 + index * 64
        f64(base, (index + 1).toDouble())
        f64(base + 8, fontSize)
        f64(base + 16, 0.0)
        f64(base + 24, 0.0)
        for (edge in 0 until 4) f64(base + 32 + edge * 8, Double.NaN)
    }
    return bytes
}

/** Builds the request buffer exactly as tiqian_layout_abi.h documents it. */
internal fun request(
    text: String,
    maxWidthPx: Float = 80f,
    fontSizePx: Float = 16f,
    lineHeightPx: Float = 24f,
    firstLineIndentIc: Float = 0f,
    fontWeight: Int = 400,
    italicByte: Int = 0,
    lineLengthGridEnabled: Int = 0,
    locale: String = "zh-Hans",
    families: List<String> = listOf("Fake CJK"),
    spanEnd: Int = -1,
    policyCode: Int = 0,
    fontSessionId: String = "tq-font-test-1",
): ByteArray {
    val bytes = ArrayList<Byte>(256)
    fun u32(value: Int) {
        bytes += (value and 0xFF).toByte()
        bytes += ((value ushr 8) and 0xFF).toByte()
        bytes += ((value ushr 16) and 0xFF).toByte()
        bytes += ((value ushr 24) and 0xFF).toByte()
    }
    fun i32(value: Int) = u32(value)
    fun f32(value: Float) = i32(value.toRawBits())
    fun u8(value: Int) {
        bytes += value.toByte()
    }
    fun u16(value: Int) {
        bytes += (value and 0xFF).toByte()
        bytes += ((value ushr 8) and 0xFF).toByte()
    }
    fun string(value: String) {
        val payload = value.encodeToByteArray()
        u32(payload.size)
        payload.forEach { bytes += it }
    }
    u32(0x54514C52) // "TQLR"
    u32(1)
    f32(maxWidthPx)
    f32(fontSizePx)
    f32(lineHeightPx)
    f32(firstLineIndentIc)
    i32(fontWeight)
    u8(italicByte)
    u8(lineLengthGridEnabled)
    u16(0)
    string(locale)
    u32(families.size)
    families.forEach(::string)
    string(text)
    if (spanEnd >= 0) {
        u32(1) // one text span covering (0, spanEnd)
        i32(0)
        i32(spanEnd)
        f32(fontSizePx)
        i32(fontWeight)
        u8(0)
        f32(0f)
        u32(1)
        string(families.first())
    } else {
        u32(0)
    }
    u32(0) // sourceBoundaries
    if (policyCode != 0) {
        u32(1) // one line-break span covering the text
        i32(0)
        i32(text.length)
        i32(policyCode)
    } else {
        u32(0)
    }
    u32(0) // inlineBoxes
    string(fontSessionId)
    return bytes.toByteArray()
}
