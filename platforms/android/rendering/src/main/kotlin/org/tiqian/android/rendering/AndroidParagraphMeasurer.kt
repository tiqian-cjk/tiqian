package org.tiqian.android.rendering

import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.ClreqProfileResolver
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutProfileId
import org.tiqian.core.LayoutResult
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
import org.tiqian.shaping.android.AndroidFontMetricsResolver
import org.tiqian.shaping.android.AndroidTypefaceResolver
import org.tiqian.shaping.android.AndroidTypefaceResolverRegistry
import org.tiqian.shaping.android.createAndroidTextShaper

/**
 * Width-independent Android shaping and font-metrics caches shared by paragraph measurers.
 *
 * Keep one session at a document or rendering-surface lifetime. Each [AndroidParagraphMeasurer]
 * still owns its platform backend and may be confined to a worker, while completed immutable
 * shaping and metrics results are reused across foreground and pre-layout work.
 */
class AndroidParagraphMeasurementSession @JvmOverloads constructor(
    shapingCacheEntries: Int = DEFAULT_SHARED_ANDROID_SHAPING_CACHE_ENTRIES,
    metricsCacheEntries: Int = DEFAULT_SHARED_ANDROID_METRICS_CACHE_ENTRIES,
    val typefaceResolver: AndroidTypefaceResolver = AndroidTypefaceResolverRegistry.current,
) {
    internal val shapingCache = SynchronizedBoundedCache<ShapingInput, ShapingResult>(shapingCacheEntries)
    internal val metricsCache = SynchronizedBoundedCache<FontMetricsRequest, RawFontMetrics>(metricsCacheEntries)

    /** Clears cached platform evidence, for example after a host-observed font environment change. */
    fun clear() {
        shapingCache.clear()
        metricsCache.clear()
    }
}

/**
 * Android paragraph measurer backed by the platform text stack and the Tiqian engine.
 *
 * An instance is intentionally not synchronized; confine it to one UI surface or one pre-layout
 * worker. Use [AndroidParagraphMeasurementSession] to share immutable backend results safely.
 */
class AndroidParagraphMeasurer @JvmOverloads constructor(
    private val profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    session: AndroidParagraphMeasurementSession? = null,
    private val typefaceResolver: AndroidTypefaceResolver =
        session?.typefaceResolver ?: AndroidTypefaceResolverRegistry.current,
) {
    init {
        require(session == null || typefaceResolver === session.typefaceResolver) {
            "AndroidParagraphMeasurer and its measurement session must share one " +
                "AndroidTypefaceResolver"
        }
    }

    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = CachedAndroidTextShaper(
            delegate = createAndroidTextShaper(typefaceResolver),
            cache = session?.shapingCache
                ?: SynchronizedBoundedCache(DEFAULT_ANDROID_SHAPING_CACHE_ENTRIES),
        ),
        fontMetricsResolver = CachedAndroidFontMetricsResolver(
            delegate = AndroidFontMetricsResolver(typefaceResolver),
            cache = session?.metricsCache
                ?: SynchronizedBoundedCache(DEFAULT_ANDROID_METRICS_CACHE_ENTRIES),
        ),
        clreqProfileResolver = object : ClreqProfileResolver {
            override fun resolve(profileId: LayoutProfileId): ClreqProfile = profile
        },
    )

    fun measure(input: LayoutInput): LayoutResult = engine.layout(input)

    /** Measures with provenance retained for safe handoff to an Android UI surface. */
    fun precompute(input: LayoutInput): AndroidPrecomputedParagraph =
        AndroidPrecomputedParagraph(engine.layout(input), profile)
}

/** A layout result paired with the concrete regional profile used by the Android backend. */
class AndroidPrecomputedParagraph internal constructor(
    val result: LayoutResult,
    val profile: ClreqProfile,
)

private class CachedAndroidTextShaper(
    private val delegate: TextShaper,
    private val cache: SynchronizedBoundedCache<ShapingInput, ShapingResult>,
) : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult =
        cache.getOrPut(input) { delegate.shape(input) }
}

private class CachedAndroidFontMetricsResolver(
    private val delegate: FontMetricsResolver,
    private val cache: SynchronizedBoundedCache<FontMetricsRequest, RawFontMetrics>,
) : FontMetricsResolver {
    override fun resolve(request: FontMetricsRequest): RawFontMetrics =
        cache.getOrPut(request) { delegate.resolve(request) }
}

internal class SynchronizedBoundedCache<K, V>(maxEntries: Int) {
    private val maxEntries = maxEntries.also { require(it > 0) { "maxEntries must be positive" } }
    private val values = LinkedHashMap<K, V>()

    fun getOrPut(key: K, create: () -> V): V {
        synchronized(values) { values[key] }?.let { return it }
        val created = create()
        return synchronized(values) {
            values[key] ?: created.also { value ->
                if (values.size >= maxEntries) values.remove(values.keys.first())
                values[key] = value
            }
        }
    }

    fun clear() {
        synchronized(values) { values.clear() }
    }
}

private const val DEFAULT_ANDROID_SHAPING_CACHE_ENTRIES = 512
private const val DEFAULT_ANDROID_METRICS_CACHE_ENTRIES = 256
private const val DEFAULT_SHARED_ANDROID_SHAPING_CACHE_ENTRIES = 4096
private const val DEFAULT_SHARED_ANDROID_METRICS_CACHE_ENTRIES = 512
