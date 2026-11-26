import Foundation
import TiqianCoreText
import TiqianEngine

/// Apple paragraph backend, the Core Text peer of `DesktopParagraphBackend`: layout engines wired
/// to the Core Text shaper and font-metrics resolver so `layout(_:)` measures real Apple fonts. The
/// other engine seams (CLREQ profile, justifier, hyphenator, role classifier, fallback) keep their
/// built-in defaults.
///
/// `cjkFamily` / `latinFamily` must equal the families the renderer draws with, otherwise measure
/// and draw diverge (AGENTS.md implementation constraint 5). `recordsDebugInfo` is the engine's
/// `recordsDebugInfo` (ADR 0065): false skips the explanation record, which the renderer never reads.
func appleParagraphEngine(
    cjkFamily: String = CoreTextSupport.defaultCJKFamily,
    latinFamily: String = CoreTextSupport.defaultLatinFamily,
    recordsDebugInfo: Bool = false,
) -> ParagraphLayoutEngine {
    AppleParagraphEngines(cjkFamily: cjkFamily, latinFamily: latinFamily, count: 1, recordsDebugInfo: recordsDebugInfo).engines[0]
}

/// `AppleParallelParagraphLayout`: several engines, each with its own shaping, metrics and
/// annotation caches, so independent paragraphs can be laid out on different threads.
///
/// Thread confinement: an engine writes only its own caches while laying out; every other engine
/// component is immutable after construction. Each engine therefore serves one thread at a time.
/// Job `i` always runs on engine `i % count`, so a paragraph meets its own cache entries again on
/// every relayout, and no cache lock is contended across threads. The Core Text font and line
/// cache (`CoreTextSupport`) stays process-wide and locked.
final class AppleParagraphEngines {
    /// `AppleParallelLayoutWidth`: at most this many engines, bounded by the active processor count.
    /// Measured with `DocBuilder.layout(width:)` on the 引擎自述 demo sample (18 pt, median over 20 to
    /// 40 columns, 12-core Apple silicon, three runs each): 4 engines take about 11.4 ms in a debug
    /// build and 1.25 ms in a release build, 8 engines about 10.45 ms and 1.0 ms.
    static let maxParallelEngines = 8

    let engines: [ParagraphLayoutEngine]

    init(
        cjkFamily: String = CoreTextSupport.defaultCJKFamily,
        latinFamily: String = CoreTextSupport.defaultLatinFamily,
        count: Int = min(ProcessInfo.processInfo.activeProcessorCount, AppleParagraphEngines.maxParallelEngines),
        recordsDebugInfo: Bool = false,
    ) {
        engines = (0..<max(count, 1)).map { _ in
            // Bounded caches: a reflow reuses width-independent shaping and metrics.
            Self.makeEngine(
                metrics: CachingFontMetricsResolver(CoreTextFontMetricsResolver(cjkFamily: cjkFamily, latinFamily: latinFamily)),
                shaper: CachingTextShaper(CoreTextShaper(cjkFamily: cjkFamily, latinFamily: latinFamily)),
                recordsDebugInfo: recordsDebugInfo,
            )
        }
    }

    /// Lays out every input and returns the results in input order. Inputs run concurrently, job
    /// `i` on engine `i % engines.count`; the first error any job throws is rethrown after all
    /// jobs finish.
    func layout(_ inputs: [LayoutInput]) throws -> [LayoutResult] {
        let shards = min(engines.count, inputs.count)
        guard shards > 1 else {
            return try inputs.enumerated().map { try engines[$0.offset % engines.count].layout($0.element) }
        }
        let engineCount = engines.count
        let results = UnsafeMutableBufferPointer<Result<LayoutResult, Error>?>.allocate(capacity: inputs.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: shards) { shard in
            // Shard `shard` owns every job whose index is congruent to it modulo the engine count
            // among the first `shards` engines; each job writes only its own result slot.
            var index = shard
            while index < inputs.count {
                let engine = engines[index % engineCount]
                results[index] = Result { try engine.layout(inputs[index]) }
                index += shards
            }
        }
        return try results.map { try $0!.get() }
    }

    // boring's Swift backend emits unlabeled parameters, so replacing the eleventh argument
    // (textShaper) and the fourteenth (recordsDebugInfo) requires spelling out the ones before them.
    // Every argument other than the metrics resolver, the line breaker, the shaper and
    // recordsDebugInfo is the default-constructed value that
    // engine-haxe/src/org/tiqian/layout/ParagraphLayoutEngine.hx substitutes for null.
    private static func makeEngine(metrics: FontMetricsResolver, shaper: TextShaper, recordsDebugInfo: Bool) -> ParagraphLayoutEngine {
        EngineInvariant.call("ExplainableStubParagraphLayoutEngine.init") {
            try ExplainableStubParagraphLayoutEngine(
                CjkFontRoleClassifier(),
                ParagraphLayoutFallbackResolver(),
                BuiltInClreqProfileResolver(),
                metrics,
                ScriptAwareFontMetricsNormalizer(),
                PunctuationAtomBuilder(),
                PunctuationSpacingCompressor(),
                QuotePairAnalyzer(),
                LookaheadLineBreaker(),
                Justifier(),
                shaper,
                nil,
                LruWidthIndependentAnnotationCache(),
                recordsDebugInfo,
            )
        }
    }
}
