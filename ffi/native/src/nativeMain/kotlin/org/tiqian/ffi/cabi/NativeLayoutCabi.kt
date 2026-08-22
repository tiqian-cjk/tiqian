@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.experimental.ExperimentalNativeApi::class)

package org.tiqian.ffi.cabi

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.nativeHeap
import kotlinx.cinterop.pointed
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.set
import kotlinx.cinterop.value
import org.tiqian.shaping.NativeFontBackendFontMetricsResolver
import org.tiqian.shaping.NativeFontBackendTextShaper
import org.tiqian.shaping.tiqianInstallFontBackend as installFontBackend
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.layout.toPreparedParagraphJson

/**
 * Engine layout C ABI (ADR 0050 amendment). The static library only exports
 * `@CName` symbols of this module, so the font backend install entry is
 * re-exported beside the layout entry. Signature and buffer layout:
 * `tiqian_layout_abi.h`.
 */
@CName("tiqian_layout_paragraph")
fun tiqianLayoutParagraph(
    request: CPointer<ByteVar>?,
    requestLen: ULong,
    planOut: CPointer<CPointerVar<ByteVar>>?,
    errorOut: CPointer<CPointerVar<ByteVar>>?,
): Int {
    val plan: String = try {
        if (request == null || requestLen == 0uL) {
            throw LayoutRequestFormatException("InvalidLayoutRequest")
        }
        runLayoutRequest(request.readBytes(requestLen.toInt()))
    } catch (error: Throwable) {
        val name = (error as? LayoutRequestFormatException)?.issueName
            ?: error.message?.takeIf(String::isNotBlank)
            ?: error::class.simpleName
            ?: "UnknownLayoutError"
        planOut?.pointed?.value = null
        errorOut?.pointed?.value = name.copyToNativeCString()
        return 1
    }
    errorOut?.pointed?.value = null
    planOut?.pointed?.value = plan.copyToNativeCString()
    return 0
}

/** Runs the engine over one packed request and returns the Kotlin-produced plan JSON. */
internal fun runLayoutRequest(bytes: ByteArray): String {
    val parsed = readLayoutRequest(bytes)
    val result = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        fontMetricsResolver = NativeFontBackendFontMetricsResolver(parsed.fontSessionId),
        textShaper = NativeFontBackendTextShaper(parsed.fontSessionId),
    ).layout(parsed.input)
    return result.toPreparedParagraphJson()
}

@CName("tiqian_release_buffer")
fun tiqianReleaseBuffer(buffer: CPointer<ByteVar>?) {
    if (buffer != null) nativeHeap.free(buffer.rawValue)
}

/** Result codes and protocol: `tiqian_font_backend.h` in shaping/api. */
@CName("tiqian_install_font_backend")
fun tiqianInstallFontBackendCabi(vtable: CPointer<org.tiqian.shaping.backend.tiqian_font_backend_vtable_t>?): Int =
    installFontBackend(vtable)

private fun String.copyToNativeCString(): CPointer<ByteVar> {
    val bytes = encodeToByteArray()
    val buffer = nativeHeap.allocArray<ByteVar>(bytes.size + 1)
    for (index in bytes.indices) buffer[index] = bytes[index]
    buffer[bytes.size] = 0
    return buffer
}
