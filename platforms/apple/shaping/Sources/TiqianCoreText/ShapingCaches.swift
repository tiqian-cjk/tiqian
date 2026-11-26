import Foundation
import TiqianEngine

/// `CoreTextShapingCache`: caches width-independent shaping results across relayouts. A reflow at
/// a new width keeps the same clusters and only re-breaks lines, so the cache turns per-cluster
/// Core Text shaping into a lookup. Width is not part of `ShapingInput`; text, range, style, font
/// decision and display substitution are, so they form the key.
public final class CachingTextShaper: TextShaper {
    public static let defaultMaxEntries = 512

    private let delegate: TextShaper
    private let lock = NSLock()
    private var cache: InsertionOrderedCache<ShapingInput, ShapingResult>

    public init(_ delegate: TextShaper, maxEntries: Int = CachingTextShaper.defaultMaxEntries) {
        self.delegate = delegate
        cache = InsertionOrderedCache(maxEntries: maxEntries)
    }

    public func shape(_ input: ShapingInput) throws -> ShapingResult {
        if let cached = lock.withLock({ cache.value(for: input) }) { return cached }
        let shaped = try delegate.shape(input)
        lock.withLock { cache.insert(shaped, for: input) }
        return shaped
    }
}

/// `CoreTextMetricsCache`: caches font metrics (face, style and size data) across relayouts.
/// `faceSelectionText` stays in the key so a custom-family fallback cannot reuse another resolved
/// face's metrics.
public final class CachingFontMetricsResolver: FontMetricsResolver {
    public static let defaultMaxEntries = 256

    private let delegate: FontMetricsResolver
    private let lock = NSLock()
    private var cache: InsertionOrderedCache<FontMetricsRequest, RawFontMetrics>

    public init(_ delegate: FontMetricsResolver, maxEntries: Int = CachingFontMetricsResolver.defaultMaxEntries) {
        self.delegate = delegate
        cache = InsertionOrderedCache(maxEntries: maxEntries)
    }

    public func resolve(_ request: FontMetricsRequest) -> RawFontMetrics {
        if let cached = lock.withLock({ cache.value(for: request) }) { return cached }
        let metrics = delegate.resolve(request)
        lock.withLock { cache.insert(metrics, for: request) }
        return metrics
    }
}
