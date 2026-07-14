package org.tiqian.layout

import kotlin.math.abs
import org.tiqian.clreq.ClreqPunctuationPolicies
import org.tiqian.clreq.GlueSide
import org.tiqian.clreq.PunctuationClass
import org.tiqian.clreq.PunctuationGluePlacement
import org.tiqian.clreq.glueSideFor
import org.tiqian.core.Rect
import org.tiqian.core.TextRange

data class PunctuationAtom(
    val range: TextRange,
    val char: Char,
    val punctuationClass: PunctuationClass,
    val advance: Float,
    val inkBounds: Rect?,
    val bodyWidth: Float,
    /** Font-measured `halt` advance backing [bodyWidth]; null = policy body. */
    val haltAdvance: Float? = null,
    /**
     * `HaltPlacementProfileCrossCheck` warning: non-null when the side the
     * FONT trims under `halt` contradicts the profile's glue side for this
     * class (e.g. a Traditional-centred profile against a Mainland-designed
     * font). Diagnostic only — geometry keeps the profile decision.
     */
    val haltValidation: String? = null,
    val leadingGlue: Glue,
    val trailingGlue: Glue,
    val anchor: PunctuationAnchor,
    val geometrySource: String,
    val policyBodyFloor: Float,
    val inkWidth: Float?,
    val inkCenter: Float?,
    /** Minimum body that keeps the default glyph ink inside its compressed box. */
    val inkContainmentBodyFloor: Float?,
    /** Named `InkContainmentBodyFloor` decision; false when policy/halt already suffices. */
    val inkContainmentApplied: Boolean,
    /** `MissingInkBoundsFallback` reason; see [PunctuationInkInput.boundsFallbackReason]. */
    val inkBoundsFallback: String?,
    /**
     * `UnderwidthPunctuationAdvanceExpansion`: layout advance added when the
     * shaped glyph is narrower than the CLREQ-required punctuation box.
     */
    val advanceExpansion: Float,
    /** Glyph-origin shift that places the underwidth glyph inside its profile body. */
    val glyphInlineShift: Float,
    /** Named placement heuristic, null when [glyphInlineShift] is zero. */
    val glyphPlacementReason: String?,
)

data class PunctuationInkInput(
    val advance: Float,
    val inkBounds: Rect? = null,
    /**
     * Font-measured OpenType `halt` advance — the font designer's own
     * half-width body for this mark. When present (and smaller than the
     * full advance) it REPLACES the policy body width; the glue direction
     * still comes from the profile per ADR 0014.
     */
    val haltAdvance: Float? = null,
    /**
     * The x placement shift the font applies under `halt` (-0.5em for
     * opening brackets, -0.25em for centred marks, 0 for closing/stop).
     * Input to `HaltPlacementProfileCrossCheck` — diagnostic only.
     */
    val haltPlacementX: Float? = null,
    /**
     * Named heuristic: `MissingInkBoundsFallback`.
     *
     * Non-null exactly when shaping ran but [inkBounds] is absent; explains
     * why so the dump can distinguish "shaper gave no ink" from "no shaping
     * at all". Known reason codes:
     *
     * - `shaper-no-ink-bounds` — the shaper resolved a glyph but reported
     *   empty visual bounds (blank glyph, or font without outlines).
     * - `glyph-cluster-mapping-ambiguous` — glyph count does not match the
     *   cluster's display characters, so per-character ink cannot be
     *   attributed; geometry falls back to pure policy ([advance] is unset).
     *
     * Per ADR 0014 missing ink disables `InkContainmentBodyFloor`; profile
     * glue direction and the policy/halt body remain the explicit fallback.
     */
    val boundsFallbackReason: String? = null,
)

enum class PunctuationAnchor {
    Leading,
    Center,
    Trailing,
}

data class Glue(
    val kind: GlueKind,
    val min: Float,
    val natural: Float,
    val max: Float,
    val priority: Int,
    val penalty: Int,
) {
    init {
        require(min <= natural) { "Glue min must not exceed natural." }
        require(natural <= max) { "Glue natural must not exceed max." }
    }
}

enum class GlueKind {
    PunctuationLeading,
    PunctuationTrailing,
    CjkLatinSpace,
    WordSpace,
    CjkInterChar,
}

data class AdjustmentOpportunity(
    val range: TextRange,
    val glue: Glue,
)

data class PunctuationSpacingAdjustment(
    val range: TextRange,
    val reductionTargetRange: TextRange,
    val leftChar: Char,
    val rightChar: Char,
    val naturalInnerGlue: Float,
    val adjustedInnerGlue: Float,
    val reduction: Float,
    val reason: String,
)

data class PunctuationSpacingCompressionResult(
    val adjustments: List<PunctuationSpacingAdjustment>,
) {
    val totalReduction: Float =
        adjustments.sumOf { it.reduction.toDouble() }.toFloat()
}

class PunctuationSpacingCompressor {
    /**
     * Named heuristic: `CollapseAdjacentPunctuationInnerGlue`.
     *
     * CLREQ rule for two adjacent half-width punctuation marks: the visible
     * inner gap is collapsed by **one half-em** (capped at zero, never
     * negative). The previous halving implementation (`natural / 2`) was
     * wrong for several common pairs — see ADR 0014 amendment notes.
     *
     * Walking through the class-derived glue cases at fontSize=16:
     * - `」。` closing+closing → natural inner = trailing(8) + leading(0) = 8.
     *   Halving says adjusted=4; CLREQ says **0** (bodies touch). The
     *   half-em subtraction gives `max(0, 8 - 8) = 0` ✓.
     * - `「（` opening+opening → natural inner = trailing(0) + leading(8) = 8.
     *   Same as above → 0 ✓.
     * - `。「` closing+opening → natural inner = 8 + 8 = 16. CLREQ says **8**
     *   (half-em gap remains). `max(0, 16 - 8) = 8` ✓.
     * - `。「」` chain handled per pair via `zipWithNext`.
     *
     * The collapse amount (`emHalf`) is supplied by the caller because the
     * atom alone doesn't know its design em — `atom.advance` reflects the
     * shaped advance, not the design em box.
     *
     * Consecutive PauseOrStop marks (`！！` `？！`…) compress like any other
     * adjacent pair — this is expected MainlandSimplified horizontal
     * behaviour. The audit doc's deferred item is only the dedicated
     * two-em-width strategy for `！！！`/`？？？` runs, not the per-pair
     * collapse itself.
     */
    fun compress(atoms: List<PunctuationAtom>, em: Float): PunctuationSpacingCompressionResult {
        if (atoms.size < 2) return PunctuationSpacingCompressionResult(emptyList())
        val emHalf = em / 2f

        val adjustments = atoms.zipWithNext().mapNotNull { (left, right) ->
            if (left.range.end != right.range.start) return@mapNotNull null

            val naturalInnerGlue = left.trailingGlue.natural + right.leadingGlue.natural
            if (naturalInnerGlue <= 0f) return@mapNotNull null

            val adjustedInnerGlue = (naturalInnerGlue - emHalf).coerceAtLeast(0f)
            val reduction = naturalInnerGlue - adjustedInnerGlue
            if (reduction <= 0f) return@mapNotNull null

            PunctuationSpacingAdjustment(
                range = TextRange(left.range.start, right.range.end),
                reductionTargetRange = if (left.trailingGlue.natural >= right.leadingGlue.natural) {
                    left.range
                } else {
                    right.range
                },
                leftChar = left.char,
                rightChar = right.char,
                naturalInnerGlue = naturalInnerGlue,
                adjustedInnerGlue = adjustedInnerGlue,
                reduction = reduction,
                reason = "collapse-adjacent-punctuation-inner-glue",
            )
        }

        return PunctuationSpacingCompressionResult(adjustments)
    }

    /**
     * Named heuristic: `CollapseCjkClosingBeforeAsciiPointMark`.
     *
     * ASCII point marks are deliberately shaped by the Latin face and therefore
     * do not become [PunctuationAtom]s. They still form a punctuation boundary
     * with an immediately preceding CJK closing mark: in `」,` the closing
     * mark's trailing half-em must be consumed instead of appearing as a blank
     * between the two glyph bodies. Only the CJK mark's own glue is reduced;
     * the ASCII point mark keeps its source character, role, glyph and advance.
     */
    fun compressCjkClosingBeforeAsciiPointMark(
        atoms: List<PunctuationAtom>,
        text: String,
        em: Float,
    ): PunctuationSpacingCompressionResult {
        val emHalf = em / 2f
        val adjustments = atoms.mapNotNull { left ->
            if (left.punctuationClass != PunctuationClass.Closing) return@mapNotNull null
            val rightChar = text.getOrNull(left.range.end) ?: return@mapNotNull null
            if (!ClreqPunctuationPolicies.isAsciiPointMark(rightChar)) return@mapNotNull null

            val naturalInnerGlue = left.trailingGlue.natural
            if (naturalInnerGlue <= 0f) return@mapNotNull null
            val adjustedInnerGlue = (naturalInnerGlue - emHalf).coerceAtLeast(0f)
            val reduction = naturalInnerGlue - adjustedInnerGlue
            if (reduction <= 0f) return@mapNotNull null

            PunctuationSpacingAdjustment(
                range = TextRange(left.range.start, left.range.end + 1),
                reductionTargetRange = left.range,
                leftChar = left.char,
                rightChar = rightChar,
                naturalInnerGlue = naturalInnerGlue,
                adjustedInnerGlue = adjustedInnerGlue,
                reduction = reduction,
                reason = "collapse-cjk-closing-before-ascii-point-mark",
            )
        }
        return PunctuationSpacingCompressionResult(adjustments)
    }
}

class PunctuationAtomBuilder(
    private val gluePlacement: PunctuationGluePlacement = PunctuationGluePlacement.MainlandSimplified,
    private val widthPolicy: org.tiqian.clreq.PunctuationWidthPolicy =
        org.tiqian.clreq.PunctuationWidthPolicy(),
) {
    fun build(text: String, index: Int, em: Float): PunctuationAtom? {
        val char = text.getOrNull(index) ?: return null
        return build(
            char = char,
            range = TextRange(index, index + 1),
            em = em,
        )
    }

    /**
     * Builds a [PunctuationAtom] whose body is always half-width (from policy).
     *
     * Glue placement is decided by [gluePlacement] + CLREQ class per ADR 0014
     * (and clarified by the regional split in CLREQ 3.1.3):
     *
     * - **MainlandSimplified + Opening** (`「（《`): all glue on leading side.
     * - **MainlandSimplified + Closing / PauseOrStop** (`」）。，`): all glue on trailing side.
     * - **Traditional + any of the above**: glue split evenly (Traditional convention
     *   centres `。 ，` etc. within the em box).
     * - **Symmetric punctuation** (middle dot, interpunct, ellipsis, dash, quote, etc.):
     *   glue split evenly in both placements.
     *
     * `inkInput` provides the real shaped advance (used instead of the policy
     * advance when available) and glyph ink bounds. Ink never redistributes
     * profile glue, but `InkContainmentBodyFloor` may reduce its compressible
     * amount so the default glyph cannot overlap the neighbouring cluster.
     *
     * When `halt` or equivalent OpenType features become available, they
     * will replace the policy body/advance directly, and ink bounds will
     * serve as a validation check.
     *
     * Named heuristic: `ProfileDerivedGlueDirection`.
     */
    fun build(
        char: Char,
        range: TextRange,
        em: Float,
        inkInput: PunctuationInkInput? = null,
        gluePlacement: PunctuationGluePlacement = this.gluePlacement,
        widthPolicy: org.tiqian.clreq.PunctuationWidthPolicy = this.widthPolicy,
    ): PunctuationAtom? {
        val policy = ClreqPunctuationPolicies.policyFor(char)
        if (policy.punctuationClass == PunctuationClass.Other) return null

        val policyAdvance = policy.defaultAdvanceEm * em
        val shapedAdvance = inkInput?.advance?.takeIf { it > 0f }
        val rawGlyphAdvance = shapedAdvance ?: policyAdvance
        // 标点宽度风格（开明式 / GB 固定半宽）：把该类标点的占宽强制为半字
        // （= body，glue 归零 → 半宽且不可调）。真实 ink 若装不进半字，
        // `InkContainmentBodyFloor` 会诚实扩大该 body，不能以重叠换取名义半宽。
        val forcedHalf = ClreqPunctuationPolicies.forcedHalfWidth(char, widthPolicy)
        // `UnderwidthPunctuationAdvanceExpansion`: CJK punctuation keeps the
        // profile's minimum box even when the selected face exposes a
        // proportional Western glyph (notably U+2018..U+201D). A wider shaped
        // glyph remains authoritative; fixed-half profiles still override both.
        val profileAdvance = if (forcedHalf) {
            0.5f * em
        } else {
            maxOf(shapedAdvance ?: policyAdvance, policyAdvance)
        }
        // FontHaltDerivedBody: when the font provides an alternate half-width
        // advance via `halt`, that is the designer-defined solid body — it
        // replaces the policy 0.5em. Glue direction stays profile-derived
        // (ADR 0014); only the body/glue SPLIT comes from the font.
        val haltBody = inkInput?.haltAdvance?.takeIf {
            it > 0f && it < maxOf(rawGlyphAdvance, policyAdvance)
        }
        val policyBodyFloor = policy.defaultBodyEm * em
        val nominalBodyWidth = if (forcedHalf) {
            minOf(haltBody ?: policyBodyFloor, profileAdvance)
        } else {
            haltBody ?: policyBodyFloor
        }

        // Ink never chooses the CLREQ glue SIDE. It only establishes a safety
        // floor for the non-compressible body: after all permitted glue has
        // been consumed, the default glyph's ink must still remain inside the
        // occupied cluster box instead of entering its neighbour.
        val inkBounds = inkInput?.inkBounds
        val inkWidth = inkBounds?.width?.coerceAtLeast(0f)
        val glueSide = gluePlacement.glueSideFor(policy.punctuationClass)
        val anchor = when (glueSide) {
            GlueSide.LeadingOnly -> PunctuationAnchor.Trailing
            GlueSide.TrailingOnly -> PunctuationAnchor.Leading
            GlueSide.BothSides -> PunctuationAnchor.Center
        }
        val inkContainmentBodyFloor = inkContainmentBodyFloor(
            glyphAdvance = rawGlyphAdvance,
            inkBounds = inkBounds,
            anchor = anchor,
        )
        val bodyWidth = maxOf(nominalBodyWidth, inkContainmentBodyFloor ?: 0f)
        val inkContainmentApplied = inkContainmentBodyFloor != null &&
            inkContainmentBodyFloor > nominalBodyWidth
        val advance = if (forcedHalf) {
            bodyWidth
        } else {
            maxOf(profileAdvance, bodyWidth)
        }
        val inkCenter = inkBounds?.let { (it.left + it.right) / 2f }

        // Glue direction remains profile-derived; only its safe capacity is
        // reduced when the real glyph needs more than the nominal half body.
        val totalGlue = (advance - bodyWidth).coerceAtLeast(0f)
        val (leadingGlueNatural, trailingGlueNatural) = classBasedGlue(
            punctuationClass = policy.punctuationClass,
            totalGlue = totalGlue,
            gluePlacement = gluePlacement,
        )

        val advanceExpansion = (advance - rawGlyphAdvance).coerceAtLeast(0f)
        val bodyStart = when (anchor) {
            PunctuationAnchor.Leading -> 0f
            PunctuationAnchor.Center -> (advance - bodyWidth) / 2f
            PunctuationAnchor.Trailing -> advance - bodyWidth
        }
        // `ProfileAnchoredUnderwidthGlyphShift`: centre the proportional glyph
        // in the non-compressible body, then place that body according to the
        // profile anchor. Clamping keeps the glyph inside the expanded box when
        // its own advance is slightly wider than the nominal half-em body.
        val forcedHalfTrimShift = if (forcedHalf && rawGlyphAdvance > advance) {
            when (anchor) {
                PunctuationAnchor.Leading -> 0f
                PunctuationAnchor.Center -> (advance - rawGlyphAdvance) / 2f
                PunctuationAnchor.Trailing -> advance - rawGlyphAdvance
            }
        } else {
            0f
        }
        val preferredGlyphInlineShift = if (forcedHalfTrimShift != 0f) {
            forcedHalfTrimShift
        } else if (advanceExpansion > 0f) {
            (bodyStart + (bodyWidth - rawGlyphAdvance) / 2f)
                .coerceIn(0f, advanceExpansion)
        } else {
            0f
        }
        // `InkContainmentGlyphShift`: a glyph may overhang its own advance
        // (italic/synthetic-slant punctuation is the common case). Body width
        // alone cannot contain that overhang on the anchored edge, so constrain
        // the preferred profile placement to the interval that keeps real ink
        // inside the final, fully-compressed body.
        val glyphInlineShift = inkBounds?.let { bounds ->
            val minimum = bodyStart - bounds.left
            val maximum = bodyStart + bodyWidth - bounds.right
            if (minimum <= maximum) {
                preferredGlyphInlineShift.coerceIn(minimum, maximum)
            } else {
                preferredGlyphInlineShift
            }
        } ?: preferredGlyphInlineShift
        val inkContainmentShiftApplied = abs(glyphInlineShift - preferredGlyphInlineShift) > PLACEMENT_EPSILON
        val glyphPlacementReason = when {
            inkContainmentShiftApplied -> "InkContainmentGlyphShift"
            forcedHalfTrimShift != 0f -> "ForcedHalfWidthGlyphAnchorShift"
            glyphInlineShift != 0f -> "ProfileAnchoredUnderwidthGlyphShift"
            else -> null
        }
        val haltValidation = crossCheckHaltPlacement(
            haltBody = haltBody,
            haltPlacementX = inkInput?.haltPlacementX,
            advance = advance,
            glueSide = glueSide,
        )

        return PunctuationAtom(
            range = range,
            char = char,
            punctuationClass = policy.punctuationClass,
            advance = advance,
            inkBounds = inkBounds,
            bodyWidth = bodyWidth,
            haltAdvance = haltBody,
            haltValidation = haltValidation,
            leadingGlue = Glue(
                kind = GlueKind.PunctuationLeading,
                min = 0f,
                natural = leadingGlueNatural,
                max = leadingGlueNatural,
                priority = 0,
                penalty = 0,
            ),
            trailingGlue = Glue(
                kind = GlueKind.PunctuationTrailing,
                min = 0f,
                natural = trailingGlueNatural,
                max = trailingGlueNatural,
                priority = 0,
                penalty = 0,
            ),
            anchor = anchor,
            geometrySource = when {
                haltBody != null && inkBounds != null -> "FontHaltDerivedWithInkDiagnostics"
                haltBody != null -> "FontHaltDerived"
                inkBounds != null -> "ProfileDerivedWithInkDiagnostics"
                shapedAdvance != null -> "ProfileDerivedWithShapedAdvance"
                else -> "PolicyDerived"
            },
            policyBodyFloor = policyBodyFloor,
            inkWidth = inkWidth,
            inkCenter = inkCenter,
            inkContainmentBodyFloor = inkContainmentBodyFloor,
            inkContainmentApplied = inkContainmentApplied,
            // MissingInkBoundsFallback: only meaningful when shaping ran but
            // produced no usable ink bounds for this character.
            inkBoundsFallback = if (inkBounds == null) inkInput?.boundsFallbackReason else null,
            advanceExpansion = advanceExpansion,
            glyphInlineShift = glyphInlineShift,
            glyphPlacementReason = glyphPlacementReason,
        )
    }

    /**
     * `InkContainmentBodyFloor`: calculate the smallest anchored body that can
     * contain the default glyph ink after all profile glue is consumed.
     */
    private fun inkContainmentBodyFloor(
        glyphAdvance: Float,
        inkBounds: Rect?,
        anchor: PunctuationAnchor,
    ): Float? {
        if (inkBounds == null || glyphAdvance <= 0f) return null
        val anchoredFloor = when (anchor) {
            PunctuationAnchor.Leading -> inkBounds.right
            PunctuationAnchor.Trailing -> glyphAdvance - inkBounds.left
            PunctuationAnchor.Center -> maxOf(
                glyphAdvance - 2f * inkBounds.left,
                2f * inkBounds.right - glyphAdvance,
            )
        }
        // An overhanging glyph can be wider than the anchor-derived floor.
        // No placement can fit ink into a body narrower than the ink itself.
        val floor = maxOf(anchoredFloor, inkBounds.width.coerceAtLeast(0f))
        return floor.takeIf { it.isFinite() }?.coerceAtLeast(0f)
    }

    /**
     * Named heuristic: `HaltPlacementProfileCrossCheck`.
     *
     * Under `halt` the font states which side it trims: placement -0.5em =
     * leading blank removed (opening brackets), 0 = trailing removed
     * (closing / stops), ≈ -0.25em = both (centred marks). The profile's
     * glue side must agree — glue is exactly the trimmable blank. A
     * mismatch (e.g. Traditional centred profile on a Mainland-designed
     * font) is recorded as a warning; geometry keeps the profile decision
     * per ADR 0014.
     */
    private fun crossCheckHaltPlacement(
        haltBody: Float?,
        haltPlacementX: Float?,
        advance: Float,
        glueSide: GlueSide,
    ): String? {
        if (haltBody == null || haltPlacementX == null) return null
        val tolerance = 0.5f
        val leadingTrim = (-haltPlacementX).coerceAtLeast(0f)
        val trailingTrim = (advance - haltBody - leadingTrim).coerceAtLeast(0f)
        val fontSide = when {
            leadingTrim > tolerance && trailingTrim > tolerance -> GlueSide.BothSides
            leadingTrim > tolerance -> GlueSide.LeadingOnly
            else -> GlueSide.TrailingOnly
        }
        if (fontSide == glueSide) return null
        return "halt-trims-${fontSide.dumpName()}-but-profile-glue-${glueSide.dumpName()}"
    }

    private fun GlueSide.dumpName(): String =
        when (this) {
            GlueSide.LeadingOnly -> "leading"
            GlueSide.TrailingOnly -> "trailing"
            GlueSide.BothSides -> "both"
        }

    /**
     * Named heuristic: `ProfileDerivedGlueDirection`.
     *
     * The profile's [PunctuationGluePlacement] picks one of three sides
     * per CLREQ class. Traditional Chinese centres all punctuation; only
     * Mainland Simplified anchors body to one side for Opening / Closing /
     * PauseOrStop.
     */
    private fun classBasedGlue(
        punctuationClass: PunctuationClass,
        totalGlue: Float,
        gluePlacement: PunctuationGluePlacement,
    ): Pair<Float, Float> =
        when (gluePlacement.glueSideFor(punctuationClass)) {
            GlueSide.LeadingOnly -> totalGlue to 0f
            GlueSide.TrailingOnly -> 0f to totalGlue
            GlueSide.BothSides -> {
                val sideGlue = totalGlue / 2f
                sideGlue to sideGlue
            }
        }

    private companion object {
        private const val PLACEMENT_EPSILON = 0.001f
    }
}
