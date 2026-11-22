package org.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import org.tiqian.clreq.ClreqProfile
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.android.AndroidFontMetricsResolver
import org.tiqian.shaping.android.AndroidTypefaceResolverRegistry
import org.tiqian.shaping.android.createAndroidTextShaper

@Composable
internal actual fun rememberPlatformParagraphMeasurer(
    profile: ClreqProfile,
    session: ParagraphMeasurementSession?,
): ParagraphMeasurer {
    return remember(profile, session, AndroidTypefaceResolverRegistry.current) { createPlatformParagraphMeasurer(profile, session) }
}

actual fun createPlatformParagraphMeasurer(
    profile: ClreqProfile,
    session: ParagraphMeasurementSession?,
): ParagraphMeasurer {
    val typefaces = AndroidTypefaceResolverRegistry.current
    // A host can replace the registry after the document session was created.
    val matchingSession = session?.takeIf { it.fontSource === typefaces }
    return matchingSession.defaultParagraphMeasurer(
        profile,
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = BoundedComposeTextShaperCache(
                delegate = createAndroidTextShaper(typefaces),
                sharedCache = matchingSession?.shapingCache,
            ),
            fontMetricsResolver = BoundedComposeFontMetricsCache(
                delegate = AndroidFontMetricsResolver(typefaces),
                sharedCache = matchingSession?.metricsCache,
            ),
            clreqProfileResolver = object : org.tiqian.clreq.ClreqProfileResolver { override fun resolve(profileId: org.tiqian.core.LayoutProfileId): org.tiqian.clreq.ClreqProfile = profile },
        ),
    )
}

internal actual fun currentPlatformFontSource(): Any = AndroidTypefaceResolverRegistry.current

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
