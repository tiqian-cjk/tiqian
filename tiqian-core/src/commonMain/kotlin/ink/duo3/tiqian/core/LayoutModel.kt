package ink.duo3.tiqian.core

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
    /**
     * The advance this glyph takes under OpenType `halt` (alternate
     * half-width metrics), measured by a separate feature-tagged shaping
     * pass. Null when the shaper cannot measure features (AWT, stub) or the
     * font provides no alternate (`halt` advance == default advance).
     * Punctuation geometry consumes it as the font-defined body width.
     */
    val haltAdvance: Float? = null,
    /**
     * The x placement shift `halt` applies (e.g. -0.5em for opening
     * brackets whose leading blank is trimmed). Diagnostic: tells which
     * side the FONT trims, for future validation against the profile's
     * glue side. Null whenever [haltAdvance] is null.
     */
    val haltPlacementX: Float? = null,
)

data class LineBox(
    val range: TextRange,
    val baseline: Float,
    val top: Float,
    val bottom: Float,
    val naturalWidth: Float,
    val adjustedWidth: Float,
    val visualWidth: Float,
    /**
     * Start-edge inset of this line along the inline axis (段首缩进 on a
     * paragraph's first line; 0 elsewhere). Renderers must begin the pen at
     * this offset; width fields above exclude it.
     */
    val indent: Float = 0f,
    /**
     * Width of a hyphen hanging at this line's end (`LineEndHangingHyphen`,
     * ADR 0029): non-zero when the line ends mid-word at a Western hyphenation
     * point. The hyphen sits just past [visualWidth] (it is NOT included in the
     * width fields, mirroring 行尾点号悬挂) — renderers draw a '-' at
     * `indent + visualWidth`. 0 elsewhere.
     */
    val hyphenAdvance: Float = 0f,
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
    val decorationDecisions: List<DecorationDecisionInfo> = emptyList(),
    val decorationSegments: List<DecorationSegmentInfo> = emptyList(),
    val rubyDecisions: List<RubyDecisionInfo> = emptyList(),
    val zhuyinDecisions: List<ZhuyinDecisionInfo> = emptyList(),
    val lineSpacingDecision: LineSpacingDecisionInfo? = null,
    val kinsokuDecision: KinsokuDecisionInfo? = null,
    val lineLengthGridDecision: LineLengthGridDecisionInfo? = null,
    val firstLineIndentDecision: FirstLineIndentDecisionInfo? = null,
)

/**
 * 段首缩进的解析：[source] = "MeasureAdaptiveFirstLineIndent"（按 [measureEm]
 * 字数自适应，< [thresholdEm] 字缩窄）或 "Explicit"（`firstLineIndent`
 * 显式覆盖）；[resolvedEm] 是最终缩进字数。
 */
data class FirstLineIndentDecisionInfo(
    val source: String,
    val measureEm: Float,
    val thresholdEm: Float,
    val resolvedEm: Float,
)

/**
 * `LineLengthGridQuantization` (grid-first, ADR 0007/0028): how the container
 * [containerWidth] was floored to an integer number of [cells] (字) of
 * [fontSize] to get the layout measure, and how the leftover [slack] placed
 * the whole body within the container ([bodyOffset] by [bodyAlignment]).
 * `enabled = false` records the bypass (measure == container, offset 0).
 */
data class LineLengthGridDecisionInfo(
    val enabled: Boolean,
    val containerWidth: Float,
    val fontSize: Float,
    val cells: Int,
    val measure: Float,
    val slack: Float,
    val bodyAlignment: String,
    val bodyOffset: Float,
    val reason: String,
)

/**
 * Which kinsoku level + hanging style the paragraph resolved to, and why
 * (`MeasureAdaptiveKinsoku` keys on the measure in 字; `Fixed` pins it).
 */
data class KinsokuDecisionInfo(
    val measureEm: Float,
    val level: String,
    val hanging: String,
    val reason: String,
)

/**
 * `InterlinearMarkLineSpacingFloor` (CLREQ 5.6.1.1): with interlinear marks
 * (着重号、示亡号 etc.) present, line spacing must not drop below 1/2 of the
 * font size, so a tight line height can't collide the marks with the next line.
 * Recorded whenever the paragraph carries such marks; `floorApplied` tells
 * whether the floor actually raised (auto) or clamped (explicit) the line height.
 * (CLREQ's 双面装 5/8 floor is print-only — show-through has no screen analogue —
 * and returns with a print backend.)
 */
data class LineSpacingDecisionInfo(
    val naturalHeight: Float,
    val requestedLineHeight: Float?,
    val resolvedHeight: Float,
    val spacingFloor: Float,
    val floorApplied: Boolean,
    val reason: String,
)

/**
 * 行间注 geometry (ruby, ADR 0032): annotation [text] placed over the base
 * [baseRange] on line [lineIndex]. [centerX] is the base range's horizontal
 * centre (the注文 centres on it, CLREQ「横排注音注文整体水平向基字居中」);
 * [baselineY] is the ruby text baseline (inside the reserved band above the
 * base ascent); [fontSize] is the ruby size (≤ base). [overhang] > 0 means the
 * 注文 is wider than the base and overhangs each side by that much (v1: allowed,
 * 避让 is a follow-up).
 */
data class RubyDecisionInfo(
    val baseRange: TextRange,
    val text: String,
    val lineIndex: Int,
    val centerX: Float,
    val baselineY: Float,
    val fontSize: Float,
    val overhang: Float,
    /** 注文专用字体（family 名优先列表）；空 = 渲染器默认。 */
    val fontFamilies: List<String> = emptyList(),
)

/**
 * 注音 geometry (ADR 0033): the ㄅㄆㄇ symbols + 调号 placed in the right-side zone
 * of [baseRange] on line [lineIndex]. Each [placement] is one glyph + its box
 * (absolute px) + role; the renderer draws [ZhuyinGlyphRole.Symbol] filling the
 * box and [ZhuyinGlyphRole.Tone] ink-detected (scale to box width, vertical-centre).
 */
data class ZhuyinDecisionInfo(
    val baseRange: TextRange,
    val lineIndex: Int,
    val placements: List<ZhuyinGlyphPlacement>,
    /** 注文 font (must carry ㄅㄆㄇ glyphs); empty = renderer's CJK default. */
    val fontFamilies: List<String> = emptyList(),
)

data class ZhuyinGlyphPlacement(
    val text: String,
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float,
    val role: ZhuyinGlyphRole,
)

enum class ZhuyinGlyphRole {
    /** ㄅㄆㄇ — fill the 9×9 box at the box font size (字身框). */
    Symbol,

    /** 平上去/入声 调号 — ink-detect, scale ink width to the box, vertical-centre. */
    Tone,

    /**
     * 轻声 ˙ — its vert-alt is FULL-WIDTH (verified). Draw at the box-WIDTH font
     * size (not scaled), h-centre by the vert advance, ink-position vertically so
     * the dot lands on the box (the neutral row). The box is the dot's target rect.
     */
    Neutral,
}

/**
 * Per-line rectangle segment of a box-style decoration (示亡号, ADR 0018).
 * Vertical bounds hug the CJK character face (字面) on the real baseline —
 * the same font-declared box the line metrics now use (ADR 0002 amendment).
 * `openStart`/`openEnd` mark segments that continue from/onto another line —
 * renderers leave that frame edge undrawn.
 */
data class DecorationSegmentInfo(
    val sourceRange: TextRange,
    val kind: String,
    val lineIndex: Int,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val openStart: Boolean,
    val openEnd: Boolean,
    val reason: String,
)

/**
 * Per-cluster decoration resolution (ADR 0018). For `Emphasis`, `applied`
 * clusters get a dot whose INK CENTRE must land on (`anchorX`, `anchorY`)
 * in layout canvas coordinates; skipped clusters record why (CLREQ:
 * punctuation never carries a dot; western text uses italics instead).
 */
data class DecorationDecisionInfo(
    val clusterRange: TextRange,
    val sourceText: String,
    val kind: String,
    val applied: Boolean,
    val reason: String,
    val anchorX: Float = 0f,
    val anchorY: Float = 0f,
    /**
     * 着重号 dot diameter (px), for the renderer to draw a filled circle of the
     * size the engine reserved clearance for. The dot is intentionally smaller
     * than the font's `•` glyph so it seats in the line gap without touching the
     * next line (ADR 0018). 0 for non-dot decorations.
     */
    val dotDiameter: Float = 0f,
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
    /**
     * Font-measured `halt` advance backing [bodyWidth] when
     * [geometrySource] is `FontHaltDerived*`; null = policy body.
     */
    val haltAdvance: Float? = null,
    /**
     * `HaltPlacementProfileCrossCheck` warning when the font's halt trim
     * side contradicts the profile's glue side; null = consistent or no
     * halt data.
     */
    val haltValidation: String? = null,
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
