package org.tiqian.text.core

data class Cluster(
    val range: TextRange,
    val text: String,
    val displayText: String = text,
    val fontKey: String,
    val advance: Float,
)

data class GlyphRun(
    val range: TextRange,
    val fontKey: String,
    val glyphs: List<Glyph>,
    val advance: Float,
)

data class Glyph(
    val id: UInt,
    val clusterRange: TextRange,
    val advance: Float,
    val bounds: Rect? = null,
)

data class LineBox(
    val range: TextRange,
    val baseline: Float,
    val top: Float,
    val bottom: Float,
    val naturalWidth: Float,
    val adjustedWidth: Float,
    val visualWidth: Float,
    val debug: LineDebugInfo = LineDebugInfo(),
)

data class LineDebugInfo(
    val repair: String? = null,
    val notes: List<String> = emptyList(),
)

data class LayoutResult(
    val input: LayoutInput,
    val size: Size,
    val clusters: List<Cluster>,
    val glyphRuns: List<GlyphRun>,
    val lines: List<LineBox>,
    val debug: LayoutDebugInfo = LayoutDebugInfo(),
)

data class LayoutDebugInfo(
    val fontDecisions: List<FontDecisionInfo> = emptyList(),
    val shapingDecisions: List<ShapingDecisionInfo> = emptyList(),
    val metricDecisions: List<MetricDecisionInfo> = emptyList(),
    val punctuationDecisions: List<PunctuationDecisionInfo> = emptyList(),
    val geometryDecisions: List<ClusterGeometryDecisionInfo> = emptyList(),
    val spacingDecisions: List<SpacingDecisionInfo> = emptyList(),
    val roleOverrides: List<RoleOverrideInfo> = emptyList(),
    val lineDecisions: List<LineDecisionInfo> = emptyList(),
    val justificationDecisions: List<JustificationDecisionInfo> = emptyList(),
    val autoSpaceDecisions: List<AutoSpaceDecisionInfo> = emptyList(),
    val lineEdgeTrimDecisions: List<LineEdgeTrimDecisionInfo> = emptyList(),
)

data class LineEdgeTrimDecisionInfo(
    val lineRange: TextRange,
    val clusterRange: TextRange,
    val side: String,
    val trimAmount: Float,
    val consumedBefore: Float,
    val naturalGlue: Float,
    val reason: String,
)

data class AutoSpaceDecisionInfo(
    val clusterRange: TextRange,
    val side: String,
    val boundaryRole: String,
    val mode: String,
    val charactersAffected: Int,
    val reductionPerChar: Float,
    val totalReduction: Float,
    val reason: String,
)

data class FontDecisionInfo(
    val range: TextRange,
    val sourceText: String,
    val displayText: String,
    val role: String,
    val fontKey: String,
    val reason: String,
    val substitutionReason: String,
)

data class ShapingDecisionInfo(
    val range: TextRange,
    val sourceText: String,
    val displayText: String,
    val fontKey: String,
    val glyphCount: Int,
    val advance: Float,
    val source: String,
    val reason: String,
    /**
     * How many of [glyphCount] glyphs came back without ink bounds from the
     * shaper. Non-zero values feed the `MissingInkBoundsFallback` heuristic
     * downstream — punctuation geometry falls back to shaped-advance-only.
     */
    val glyphsWithoutInkBounds: Int = 0,
    /**
     * How many of [glyphCount] glyphs resolved to the font's .notdef glyph.
     * Non-zero values on a CLREQ-substituted cluster trigger
     * `SubstitutionRollbackOnMissingGlyph` — the engine re-shapes with the
     * source text instead of showing tofu (e.g. `⸺` is absent from
     * PingFang SC / Hiragino / Heiti).
     */
    val missingGlyphs: Int = 0,
)

data class MetricDecisionInfo(
    val range: TextRange,
    val sourceText: String,
    val role: String,
    val fontKey: String,
    val rawAscent: Float,
    val rawDescent: Float,
    val rawLeading: Float,
    val rawSource: String,
    val layoutAscent: Float,
    val layoutDescent: Float,
    val baselineClass: String,
    val metricBox: String,
    val layoutSource: String,
    val reason: String,
)

data class PunctuationDecisionInfo(
    val range: TextRange,
    val char: Char,
    val punctuationClass: String,
    val advance: Float,
    val bodyWidth: Float,
    val leadingGlueNatural: Float,
    val trailingGlueNatural: Float,
    val anchor: String,
    val inkBounds: Rect? = null,
    val geometrySource: String = "PolicyDerived",
    val policyBodyFloor: Float = bodyWidth,
    val inkWidth: Float? = null,
    val inkCenter: Float? = null,
    /**
     * `MissingInkBoundsFallback` reason code when shaping ran but ink bounds
     * could not be attributed to this punctuation character; null when bounds
     * are present or when no shaping information exists at all (pure policy
     * path). See ADR 0014 — ink bounds are diagnostic, so this fallback
     * changes explainability only, never glue placement.
     */
    val inkBoundsFallback: String? = null,
)

data class ClusterGeometryDecisionInfo(
    val range: TextRange,
    val sourceText: String,
    val displayText: String,
    val baseAdvance: Float,
    val bodyWidth: Float,
    val leadingGlueNatural: Float,
    val leadingGlueConsumed: Float,
    val trailingGlueNatural: Float,
    val trailingGlueConsumed: Float,
    val justificationDelta: Float,
    val resolvedAdvance: Float,
    val source: String,
    val reason: String,
)

data class SpacingDecisionInfo(
    val range: TextRange,
    val leftChar: Char,
    val rightChar: Char,
    val naturalInnerGlue: Float,
    val adjustedInnerGlue: Float,
    val reduction: Float,
    val reductionTargetRange: TextRange,
    val reason: String,
)

data class RoleOverrideInfo(
    val range: TextRange,
    val sourceText: String,
    val originalRole: String,
    val overriddenRole: String,
    val source: String,
    val reason: String,
)

data class LineDecisionInfo(
    val range: TextRange,
    val kind: String,
    val repair: String? = null,
    val repairPenalty: Int = 0,
    val repairDecision: LineRepairDecisionInfo? = null,
    val repairCandidates: List<LineRepairCandidateInfo> = emptyList(),
    val notes: List<String> = emptyList(),
)

data class LineRepairDecisionInfo(
    val kind: String,
    val reasonCode: String,
    val offenderRange: TextRange,
    val penalty: Int,
    val targetClusterIndex: Int? = null,
    val carriedClusterIndex: Int? = null,
    /** PushIn total shrink across all allocations; 0 for other repair kinds. */
    val shrink: Float = 0f,
    /** PushIn aggregated line-wide capacity at decision time. */
    val availableCapacity: Float = 0f,
    /**
     * Per-cluster PushIn distribution for CLREQ 推入. Empty for non-PushIn
     * repairs. Listed in cluster order; `shrink` values sum to [shrink].
     */
    val pushInAllocations: List<LineRepairAllocationInfo> = emptyList(),
)

data class LineRepairAllocationInfo(
    val clusterRange: TextRange,
    val shrink: Float,
    val availableCapacity: Float,
)

data class LineRepairCandidateInfo(
    val kind: String,
    val reasonCode: String,
    val offenderRange: TextRange,
    val penalty: Int,
    val accepted: Boolean,
    val rejectionReason: String? = null,
    val targetClusterIndex: Int? = null,
    val carriedClusterIndex: Int? = null,
    val shrink: Float = 0f,
    val requiredShrink: Float = 0f,
    val availableCapacity: Float = 0f,
)

data class JustificationDecisionInfo(
    val lineRange: TextRange,
    val deficitBefore: Float,
    val deficitAfter: Float,
    val allocations: List<JustificationAllocationInfo>,
)

data class JustificationAllocationInfo(
    val clusterRange: TextRange,
    val kind: String,
    val priority: Int,
    val delta: Float,
    val reason: String,
)
