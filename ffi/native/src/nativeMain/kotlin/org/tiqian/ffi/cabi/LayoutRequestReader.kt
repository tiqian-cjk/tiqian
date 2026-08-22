package org.tiqian.ffi.cabi

import org.tiqian.core.Ic
import org.tiqian.core.InlineBoxOuterSpacing
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.LineBreakSpan
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent

/**
 * Request reader for the engine layout ABI (`tiqian_layout_abi.h`, ADR 0050
 * amendment). The Rust caller packs a LayoutInput; this file is the only
 * Kotlin code that knows the byte layout. Structural damage reports named
 * protocol errors. Domain validation stays with the caller.
 */

// Must equal TIQIAN_LAYOUT_ABI_PROTOCOL_REVISION in tiqian_layout_abi.h.
internal const val PROTOCOL_REVISION: UInt = 1u

// Must equal TIQIAN_LAYOUT_REQUEST_MAGIC in tiqian_layout_abi.h; "TQLR".
private const val REQUEST_MAGIC: UInt = 0x54514C52u

internal class LayoutRequestFormatException internal constructor(
    internal val issueName: String,
) : Exception(issueName)

internal class ParsedLayoutRequest(
    val input: LayoutInput,
    val fontSessionId: String,
)

internal fun readLayoutRequest(bytes: ByteArray): ParsedLayoutRequest {
    if (bytes.isEmpty()) throw LayoutRequestFormatException("InvalidLayoutRequest")
    val cursor = RequestCursor(bytes)
    if (cursor.u32() != REQUEST_MAGIC) throw LayoutRequestFormatException("InvalidLayoutRequestMagic")
    if (cursor.u32() != PROTOCOL_REVISION) throw LayoutRequestFormatException("InvalidLayoutRequestVersion")
    val maxWidthPx = cursor.f32Finite()
    val fontSizePx = cursor.f32Finite()
    val lineHeightPx = cursor.f32Finite()
    val firstLineIndentIc = cursor.f32Finite()
    val fontWeight = cursor.i32()
    val italic = cursor.boolean()
    val lineLengthGridEnabled = cursor.boolean()
    cursor.u16() // reserved; layout-neutral by contract
    val locale = cursor.string()
    val families = cursor.stringArray()
    val text = cursor.string()
    val textLength = text.length

    val spanCount = cursor.count()
    val spans = ArrayList<TextSpan>(spanCount.coerceAtMost(1024))
    repeat(spanCount) {
        val start = cursor.i32()
        val end = cursor.i32()
        val spanFontSize = cursor.f32Finite()
        val spanFontWeight = cursor.i32()
        val spanItalic = cursor.boolean()
        val baselineShift = cursor.f32Finite()
        val spanFamilies = cursor.stringArray()
        requireRange(start, end, textLength)
        spans += TextSpan(
            range = TextRange(start, end),
            style = TextStyle(
                fontFamilies = spanFamilies,
                fontSize = spanFontSize,
                locale = locale,
                fontWeight = spanFontWeight,
                italic = spanItalic,
                baselineShift = baselineShift,
            ),
        )
    }

    val boundaryCount = cursor.count()
    val boundaries = HashSet<Int>(boundaryCount.coerceAtMost(1024))
    repeat(boundaryCount) {
        val boundary = cursor.i32()
        if (boundary < 0 || boundary > textLength) {
            throw LayoutRequestFormatException("InvalidLayoutRequestIndex")
        }
        boundaries += boundary
    }

    val lineBreakSpanCount = cursor.count()
    val lineBreakSpans = ArrayList<LineBreakSpan>(lineBreakSpanCount.coerceAtMost(1024))
    repeat(lineBreakSpanCount) {
        val start = cursor.i32()
        val end = cursor.i32()
        val policyCode = cursor.i32()
        requireRange(start, end, textLength)
        val policy = when (policyCode) {
            0 -> LineBreakPolicy.ProgressiveTechnical
            else -> throw LayoutRequestFormatException("InvalidLayoutRequestCode")
        }
        lineBreakSpans += LineBreakSpan(TextRange(start, end), policy)
    }

    val inlineBoxCount = cursor.count()
    val inlineBoxes = ArrayList<InlineBoxSpan>(inlineBoxCount.coerceAtMost(1024))
    repeat(inlineBoxCount) {
        val start = cursor.i32()
        val end = cursor.i32()
        val inlineStart = cursor.f32Finite()
        val inlineEnd = cursor.f32Finite()
        val outerSpacingCode = cursor.i32()
        requireRange(start, end, textLength)
        val outerSpacing = when (outerSpacingCode) {
            0 -> InlineBoxOuterSpacing.Narrow
            1 -> InlineBoxOuterSpacing.Source
            else -> throw LayoutRequestFormatException("InvalidLayoutRequestCode")
        }
        inlineBoxes += InlineBoxSpan(TextRange(start, end), inlineStart, inlineEnd, outerSpacing)
    }

    val fontSessionId = cursor.string()
    cursor.requireEnd()

    val input = LayoutInput(
        content = TiqianTextContent(
            text = text,
            spans = spans,
            sourceBoundaries = boundaries,
            lineBreakSpans = lineBreakSpans,
        ),
        textStyle = TextStyle(
            fontFamilies = families,
            fontSize = fontSizePx,
            locale = locale,
            fontWeight = fontWeight,
            italic = italic,
        ),
        paragraphStyle = ParagraphStyle(
            lineHeight = lineHeightPx,
            firstLineIndent = Ic(firstLineIndentIc),
            lineLengthGrid = LineLengthGrid(enabled = lineLengthGridEnabled),
        ),
        constraints = LayoutConstraints(maxWidth = maxWidthPx),
        inlineBoxes = inlineBoxes,
    )
    return ParsedLayoutRequest(input, fontSessionId)
}

private fun requireRange(start: Int, end: Int, textLength: Int) {
    if (start < 0 || start >= end || end > textLength) {
        throw LayoutRequestFormatException("InvalidLayoutRequestIndex")
    }
}

private class RequestCursor(private val bytes: ByteArray) {
    private var offset = 0

    private fun need(count: Int) {
        if (count < 0 || bytes.size - offset < count) {
            throw LayoutRequestFormatException("InvalidLayoutRequestTruncated")
        }
    }

    fun u32(): UInt {
        need(4)
        var value = 0u
        for (index in 3 downTo 0) {
            value = (value shl 8) or (bytes[offset + index].toUInt() and 0xFFu)
        }
        offset += 4
        return value
    }

    fun i32(): Int = u32().toInt()

    fun f32(): Float = Float.fromBits(i32())

    fun f32Finite(): Float {
        val value = f32()
        if (!value.isFinite()) throw LayoutRequestFormatException("InvalidLayoutRequestValue")
        return value
    }

    fun u16(): UInt {
        need(2)
        val value = (bytes[offset].toUInt() and 0xFFu) or
            ((bytes[offset + 1].toUInt() and 0xFFu) shl 8)
        offset += 2
        return value
    }

    fun u8(): Int {
        need(1)
        val value = bytes[offset].toInt() and 0xFF
        offset += 1
        return value
    }

    fun boolean(): Boolean = when (u8()) {
        0 -> false
        1 -> true
        else -> throw LayoutRequestFormatException("InvalidLayoutRequestValue")
    }

    fun string(): String {
        val length = count()
        need(length)
        val value = bytes.decodeToString(offset, offset + length)
        offset += length
        return value
    }

    fun stringArray(): List<String> {
        val count = this.count()
        val values = ArrayList<String>(count.coerceAtMost(1024))
        repeat(count) { values += string() }
        return values
    }

    fun count(): Int {
        val raw = u32()
        if (raw > 1_000_000_000u) throw LayoutRequestFormatException("InvalidLayoutRequestTruncated")
        return raw.toInt()
    }

    fun requireEnd() {
        if (offset != bytes.size) throw LayoutRequestFormatException("InvalidLayoutRequestTrailing")
    }
}
