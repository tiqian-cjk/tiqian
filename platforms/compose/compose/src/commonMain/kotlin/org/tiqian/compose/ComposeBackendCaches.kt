package org.tiqian.compose

import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.layout.ParagraphLayoutEngine
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper

/**
 * `BoundedComposeShapingReuse`: retain exact width-independent shaping results while one default
 * Compose measurer is alive. Width is deliberately absent because it is absent from [ShapingInput];
 * text, source range, resolved style, font decision, and display substitution all remain in the key.
 *
 * This cache is UI-thread confined, matching Compose measurement. It is bounded so a measurer shared
 * by a long document cannot retain every cluster it has ever seen.
 */
internal class BoundedComposeTextShaperCache(
    private val delegate: TextShaper,
    maxEntries: Int = DEFAULT_COMPOSE_SHAPING_CACHE_ENTRIES,
    sharedCache: SharedComposeBackendCache<ShapingInput, ShapingResult>? = null,
) : TextShaper {
    private val cache = sharedCache ?: BoundedInsertionCache(maxEntries)

    override fun shape(input: ShapingInput): ShapingResult =
        cache.getOrPut(input) { delegate.shape(input) }
}

/**
 * `BoundedComposeFontMetricsReuse`: font metrics are face/style/size data, not line-width data.
 * Keep exact requests across rebreaks; face-selection text remains part of the key so custom-family
 * fallback cannot accidentally reuse metrics from a different resolved face.
 */
internal class BoundedComposeFontMetricsCache(
    private val delegate: FontMetricsResolver,
    maxEntries: Int = DEFAULT_COMPOSE_METRICS_CACHE_ENTRIES,
    sharedCache: SharedComposeBackendCache<FontMetricsRequest, RawFontMetrics>? = null,
) : FontMetricsResolver {
    private val cache = sharedCache ?: BoundedInsertionCache(maxEntries)

    override fun resolve(request: FontMetricsRequest): RawFontMetrics =
        cache.getOrPut(request) { delegate.resolve(request) }
}

internal interface SharedComposeBackendCache<K, V> {
    fun getOrPut(key: K, create: () -> V): V
}

private class BoundedInsertionCache<K, V>(maxEntries: Int) : SharedComposeBackendCache<K, V> {
    private val maxEntries = maxEntries.also { require(it > 0) { "maxEntries must be positive" } }
    private val values = LinkedHashMap<K, V>()

    override fun getOrPut(key: K, create: () -> V): V {
        values[key]?.let { return it }
        return create().also { value ->
            if (values.size >= maxEntries) {
                values.remove(values.keys.first())
            }
            values[key] = value
        }
    }
}

/**
 * Shares completed measurements between the document's default platform measurers. Engines remain
 * confined to their callers: concurrent misses compute outside the lock and return the first
 * published result. Keep the session at the document/surface lifetime.
 */
class ParagraphMeasurementSession(
    shapingCacheEntries: Int = DEFAULT_SHARED_COMPOSE_SHAPING_CACHE_ENTRIES,
    metricsCacheEntries: Int = DEFAULT_SHARED_COMPOSE_METRICS_CACHE_ENTRIES,
) {
    internal val fontSource = currentPlatformFontSource()
    internal val shapingCache =
        createSharedComposeBackendCache<ShapingInput, ShapingResult>(shapingCacheEntries)
    internal val metricsCache =
        createSharedComposeBackendCache<FontMetricsRequest, RawFontMetrics>(metricsCacheEntries)
    internal val layoutCache =
        createSharedComposeBackendCache<Pair<ClreqProfile, LayoutInput>, LayoutResult>(16)
}

/** Only the platform factories have the same font backend across independently confined engines. */
internal fun ParagraphMeasurementSession?.defaultParagraphMeasurer(
    profile: ClreqProfile,
    engine: ParagraphLayoutEngine,
): ParagraphMeasurer {
    if (this == null) return ParagraphMeasurer(engine)
    return ParagraphMeasurer(object : ParagraphLayoutEngine {
        override fun layout(input: LayoutInput): LayoutResult {
            // A single long paragraph can retain thousands of clusters and their debug records.
            if (input.content.text.length > MAX_CACHED_LAYOUT_TEXT_LENGTH) return engine.layout(input)
            return layoutCache.getOrPut(profile to input) { engine.layout(input) }
        }
    })
}

internal expect fun currentPlatformFontSource(): Any

internal expect fun <K, V> createSharedComposeBackendCache(
    maxEntries: Int,
): SharedComposeBackendCache<K, V>

private const val MAX_CACHED_LAYOUT_TEXT_LENGTH = 1024
private const val DEFAULT_COMPOSE_SHAPING_CACHE_ENTRIES = 512
private const val DEFAULT_COMPOSE_METRICS_CACHE_ENTRIES = 256
private const val DEFAULT_SHARED_COMPOSE_SHAPING_CACHE_ENTRIES = 4096
private const val DEFAULT_SHARED_COMPOSE_METRICS_CACHE_ENTRIES = 512
