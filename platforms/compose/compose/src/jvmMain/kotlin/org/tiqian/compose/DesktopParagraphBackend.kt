package org.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.ClreqProfileResolver
import org.tiqian.core.LayoutProfileId
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper

@Composable
internal actual fun rememberPlatformParagraphMeasurer(
    profile: ClreqProfile,
    session: ParagraphMeasurementSession?,
): ParagraphMeasurer = remember(profile, session) { createPlatformParagraphMeasurer(profile, session) }

actual fun createPlatformParagraphMeasurer(
    profile: ClreqProfile,
    session: ParagraphMeasurementSession?,
): ParagraphMeasurer =
    ParagraphMeasurer(
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = BoundedComposeTextShaperCache(
                delegate = SkiaTextShaper(),
                sharedCache = session?.shapingCache,
            ),
            fontMetricsResolver = BoundedComposeFontMetricsCache(
                delegate = SkiaFontMetricsResolver(),
                sharedCache = session?.metricsCache,
            ),
            clreqProfileResolver = object : ClreqProfileResolver {
                override fun resolve(profileId: LayoutProfileId): ClreqProfile = profile
            },
        ),
    )

internal actual fun <K, V> createSharedComposeBackendCache(
    maxEntries: Int,
): SharedComposeBackendCache<K, V> = SynchronizedBoundedComposeBackendCache(maxEntries)

private class SynchronizedBoundedComposeBackendCache<K, V>(maxEntries: Int) :
    SharedComposeBackendCache<K, V> {
    private val maxEntries = maxEntries.also { require(it > 0) { "maxEntries must be positive" } }
    private val values = LinkedHashMap<K, V>()

    override fun getOrPut(key: K, create: () -> V): V {
        synchronized(values) { values[key] }?.let { return it }
        val created = create()
        return synchronized(values) {
            values[key] ?: created.also { value ->
                if (values.size >= maxEntries) values.remove(values.keys.first())
                values[key] = value
            }
        }
    }
}
