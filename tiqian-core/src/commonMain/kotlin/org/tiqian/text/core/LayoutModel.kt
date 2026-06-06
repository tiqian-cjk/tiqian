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
    val metricDecisions: List<MetricDecisionInfo> = emptyList(),
    val punctuationDecisions: List<PunctuationDecisionInfo> = emptyList(),
    val spacingDecisions: List<SpacingDecisionInfo> = emptyList(),
    val roleOverrides: List<RoleOverrideInfo> = emptyList(),
    val lineDecisions: List<LineDecisionInfo> = emptyList(),
    val justificationDecisions: List<JustificationDecisionInfo> = emptyList(),
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
    val notes: List<String> = emptyList(),
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
