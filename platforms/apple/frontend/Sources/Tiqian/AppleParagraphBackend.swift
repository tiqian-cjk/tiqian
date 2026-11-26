import TiqianCoreText
import TiqianEngine

/// Apple paragraph backend, the Core Text peer of `DesktopParagraphBackend`: a layout engine wired
/// to the Core Text shaper and font-metrics resolver so `layout(_:)` measures real Apple fonts. The
/// other engine seams (CLREQ profile, justifier, hyphenator, role classifier, fallback) keep their
/// built-in defaults.
///
/// `cjkFamily` / `latinFamily` must equal the families the renderer draws with, otherwise measure
/// and draw diverge (AGENTS.md implementation constraint 5).
func appleParagraphEngine(
    cjkFamily: String = CoreTextSupport.defaultCJKFamily,
    latinFamily: String = CoreTextSupport.defaultLatinFamily,
) -> ParagraphLayoutEngine {
    // boring's Swift backend emits unlabeled parameters, so replacing the eleventh argument
    // (textShaper) requires spelling out the ten before it. Every argument other than the metrics
    // resolver, the line breaker and the shaper is the default-constructed value that
    // engine-haxe/src/org/tiqian/layout/ParagraphLayoutEngine.hx substitutes for null.
    EngineInvariant.call("ExplainableStubParagraphLayoutEngine.init") {
        try ExplainableStubParagraphLayoutEngine(
            CjkFontRoleClassifier(),
            ParagraphLayoutFallbackResolver(),
            BuiltInClreqProfileResolver(),
            // Bounded caches: a reflow reuses width-independent shaping and metrics.
            CachingFontMetricsResolver(CoreTextFontMetricsResolver(cjkFamily: cjkFamily, latinFamily: latinFamily)),
            ScriptAwareFontMetricsNormalizer(),
            PunctuationAtomBuilder(),
            PunctuationSpacingCompressor(),
            QuotePairAnalyzer(),
            LookaheadLineBreaker(),
            Justifier(),
            CachingTextShaper(CoreTextShaper(cjkFamily: cjkFamily, latinFamily: latinFamily)),
        )
    }
}
