package org.tiqian.shaping.android.nativefont

import java.nio.ByteBuffer
import java.util.LinkedHashMap

internal object NativeFontBridge {
    init {
        System.loadLibrary("tiqian_native_font")
    }

    external fun nativeRegisterFileSource(path: String): Long
    external fun nativeRegisterBufferSource(buffer: ByteBuffer, size: Long): Long
    external fun nativeRegisterDescriptorRegionSource(fd: Int, offset: Long, length: Long): Long
    external fun nativeReleaseSource(handle: Long)
    external fun nativeCreateFace(
        sourceHandle: Long,
        collectionIndex: Int,
        variationTags: IntArray,
        variationValues: FloatArray,
    ): Long
    external fun nativeReleaseFace(handle: Long)
    external fun nativeResourceStats(): LongArray
    external fun nativeUnitsPerEm(handle: Long): Int
    external fun nativeVariationAxisRange(handle: Long, tag: Int): FloatArray?
    external fun nativeHasGlyphs(handle: Long, text: String): Boolean

    external fun nativeShape(
        handle: Long,
        text: String,
        fontSize: Float,
        locale: String,
        scriptCode: Int,
        featuresCsv: String,
    ): Long

    external fun nativeShapeGlyphIds(handle: Long): IntArray
    external fun nativeShapeClusters(handle: Long): IntArray
    external fun nativeShapePositions(handle: Long): FloatArray
    external fun nativeShapeBounds(handle: Long): FloatArray
    external fun nativeShapeAdvance(handle: Long): Float
    external fun nativeShapeMissingGlyphs(handle: Long): Int
    external fun nativeReleaseShape(handle: Long)

    external fun nativeMetrics(handle: Long, fontSize: Float): FloatArray?
    external fun nativeOutline(handle: Long, glyphId: Int): FloatArray?
    external fun nativeVersions(): String
}

internal data class NativeFontResourceStats(
    val sourceCount: Long,
    /** Bytes owned by direct buffers or covered by read-only file mappings; this is not RSS. */
    val sourceBytes: Long,
    val faceCount: Long,
)

internal fun nativeFontResourceStats(): NativeFontResourceStats {
    val values = NativeFontBridge.nativeResourceStats()
    check(values.size == 3) { "Native font resource stats have an unexpected shape" }
    return NativeFontResourceStats(
        sourceCount = values[0],
        sourceBytes = values[1],
        faceCount = values[2],
    )
}

internal class NativeFontFace(
    val handle: Long,
    val unitsPerEm: Int,
) {
    private val cacheLock = Any()
    private val coverageCache = object : LinkedHashMap<String, Boolean>(128, 0.75f, true) {}
    private val shapeCache = object : LinkedHashMap<ShapeKey, NativeShapeResult>(256, 0.75f, true) {}
    private val metricsCache = object : LinkedHashMap<Int, FloatArray>(8, 0.75f, true) {}

    init {
        require(handle != 0L) { "Native font handle must not be zero" }
        require(unitsPerEm > 0) { "Font unitsPerEm must be positive" }
    }

    fun hasGlyphs(text: String): Boolean {
        if (text.isEmpty()) return true
        synchronized(cacheLock) {
            coverageCache[text]?.let { return it }
        }
        val covered = NativeFontBridge.nativeHasGlyphs(handle, text)
        synchronized(cacheLock) {
            coverageCache.putBounded(text, covered, MaxCoverageEntries)
        }
        return covered
    }

    fun shape(
        text: String,
        fontSize: Float,
        locale: String,
        scriptCode: Int,
        features: List<String>,
    ): NativeShapeResult {
        val featuresCsv = features.joinToString(",")
        val key = ShapeKey(text, fontSize.toRawBits(), locale, scriptCode, featuresCsv)
        synchronized(cacheLock) {
            shapeCache[key]?.let { return it }
        }
        val shapeHandle = NativeFontBridge.nativeShape(
            handle = handle,
            text = text,
            fontSize = fontSize,
            locale = locale,
            scriptCode = scriptCode,
            featuresCsv = featuresCsv,
        )
        check(shapeHandle != 0L) { "Native HarfBuzz shaping did not return a result" }
        val result = try {
            NativeShapeResult(
                glyphIds = NativeFontBridge.nativeShapeGlyphIds(shapeHandle),
                clusters = NativeFontBridge.nativeShapeClusters(shapeHandle),
                positions = NativeFontBridge.nativeShapePositions(shapeHandle),
                bounds = NativeFontBridge.nativeShapeBounds(shapeHandle),
                advance = NativeFontBridge.nativeShapeAdvance(shapeHandle),
                missingGlyphs = NativeFontBridge.nativeShapeMissingGlyphs(shapeHandle),
            ).also { result ->
                require(result.positions.size == result.glyphIds.size * 4) {
                    "Native shape positions do not match glyph count"
                }
                require(result.bounds.size == result.glyphIds.size * 4) {
                    "Native shape bounds do not match glyph count"
                }
                require(result.clusters.size == result.glyphIds.size) {
                    "Native shape clusters do not match glyph count"
                }
            }
        } finally {
            NativeFontBridge.nativeReleaseShape(shapeHandle)
        }
        synchronized(cacheLock) {
            shapeCache.putBounded(key, result, MaxShapeEntries)
        }
        return result
    }

    fun metrics(fontSize: Float): FloatArray {
        val key = fontSize.toRawBits()
        synchronized(cacheLock) {
            metricsCache[key]?.let { return it }
        }
        val result = checkNotNull(NativeFontBridge.nativeMetrics(handle, fontSize)) {
            "FreeType metrics are unavailable for this face"
        }
        synchronized(cacheLock) {
            metricsCache.putBounded(key, result, MaxMetricsEntries)
        }
        return result
    }

    fun outline(glyphId: Int): FloatArray? = NativeFontBridge.nativeOutline(handle, glyphId)

    /** Declared min..max of a variation axis, or null when the face lacks it. */
    fun axisRange(tag: String): ClosedFloatingPointRange<Float>? {
        val values = NativeFontBridge.nativeVariationAxisRange(handle, variationTag(tag)) ?: return null
        if (values[0] > values[2]) return null
        return values[0]..values[2]
    }

    private data class ShapeKey(
        val text: String,
        val fontSizeBits: Int,
        val locale: String,
        val scriptCode: Int,
        val featuresCsv: String,
    )

    private companion object {
        const val MaxCoverageEntries = 4096
        const val MaxShapeEntries = 4096
        const val MaxMetricsEntries = 64
    }
}

private fun <K, V> LinkedHashMap<K, V>.putBounded(key: K, value: V, maxEntries: Int) {
    this[key] = value
    while (size > maxEntries) {
        val iterator = entries.iterator()
        if (!iterator.hasNext()) return
        iterator.next()
        iterator.remove()
    }
}

internal data class NativeShapeResult(
    val glyphIds: IntArray,
    val clusters: IntArray,
    /** x, y, xAdvance, yAdvance per glyph, in px and Android/core coordinates. */
    val positions: FloatArray,
    /** left, top, right, bottom per glyph; NaN quartet means unavailable. */
    val bounds: FloatArray,
    val advance: Float,
    val missingGlyphs: Int,
)
