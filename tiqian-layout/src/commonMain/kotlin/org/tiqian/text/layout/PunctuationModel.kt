package org.tiqian.text.layout

import org.tiqian.text.clreq.ClreqPunctuationPolicies
import org.tiqian.text.clreq.GlueSide
import org.tiqian.text.clreq.PunctuationClass
import org.tiqian.text.clreq.PunctuationGluePlacement
import org.tiqian.text.clreq.glueSideFor
import org.tiqian.text.core.Rect
import org.tiqian.text.core.TextRange

data class PunctuationAtom(
    val range: TextRange,
    val char: Char,
    val punctuationClass: PunctuationClass,
    val advance: Float,
    val inkBounds: Rect?,
    val bodyWidth: Float,
    val leadingGlue: Glue,
    val trailingGlue: Glue,
    val anchor: PunctuationAnchor,
    val geometrySource: String,
    val policyBodyFloor: Float,
    val inkWidth: Float?,
    val inkCenter: Float?,
    /** `MissingInkBoundsFallback` reason; see [PunctuationInkInput.boundsFallbackReason]. */
    val inkBoundsFallback: String?,
)

data class PunctuationInkInput(
    val advance: Float,
    val inkBounds: Rect? = null,
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
     * Per ADR 0014 ink bounds are diagnostic-only, so this fallback never
     * changes glue placement — only the recorded geometry source.
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
}

class PunctuationAtomBuilder(
    private val gluePlacement: PunctuationGluePlacement = PunctuationGluePlacement.MainlandSimplified,
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
     * advance when available) and glyph ink bounds (retained as diagnostic
     * fields — `inkBounds`, `inkWidth`, `inkCenter` — but **not** used to
     * redistribute glue or expand body).
     *
     * When `halt` or equivalent OpenType features become available, they
     * will replace the policy body/advance directly, and ink bounds will
     * serve as a validation check.
     *
     * Named heuristic: `ClassDerivedGlueDirection`.
     */
    fun build(
        char: Char,
        range: TextRange,
        em: Float,
        inkInput: PunctuationInkInput? = null,
        gluePlacement: PunctuationGluePlacement = this.gluePlacement,
    ): PunctuationAtom? {
        val policy = ClreqPunctuationPolicies.policyFor(char)
        if (policy.punctuationClass == PunctuationClass.Other) return null

        val policyAdvance = policy.defaultAdvanceEm * em
        val shapedAdvance = inkInput?.advance?.takeIf { it > 0f }
        val advance = shapedAdvance ?: policyAdvance
        val bodyWidth = (policy.defaultBodyEm * em).coerceAtMost(advance)

        // Diagnostic ink fields — not used for glue calculation.
        val inkBounds = inkInput?.inkBounds
        val inkWidth = inkBounds?.width?.coerceAtLeast(0f)
        val inkCenter = inkBounds?.let { ((it.left + it.right) / 2f).coerceIn(0f, advance) }

        // Glue direction is determined by profile + punctuation class, not by
        // ink position.
        val totalGlue = (advance - bodyWidth).coerceAtLeast(0f)
        val (leadingGlueNatural, trailingGlueNatural) = classBasedGlue(
            punctuationClass = policy.punctuationClass,
            totalGlue = totalGlue,
            gluePlacement = gluePlacement,
        )

        val anchor = when (gluePlacement.glueSideFor(policy.punctuationClass)) {
            GlueSide.LeadingOnly -> PunctuationAnchor.Trailing
            GlueSide.TrailingOnly -> PunctuationAnchor.Leading
            GlueSide.BothSides -> PunctuationAnchor.Center
        }

        return PunctuationAtom(
            range = range,
            char = char,
            punctuationClass = policy.punctuationClass,
            advance = advance,
            inkBounds = inkBounds,
            bodyWidth = bodyWidth,
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
                inkBounds != null -> "ClassDerivedWithInkDiagnostics"
                shapedAdvance != null -> "ClassDerivedWithShapedAdvance"
                else -> "PolicyDerived"
            },
            policyBodyFloor = bodyWidth,
            inkWidth = inkWidth,
            inkCenter = inkCenter,
            // MissingInkBoundsFallback: only meaningful when shaping ran but
            // produced no usable ink bounds for this character.
            inkBoundsFallback = if (inkBounds == null) inkInput?.boundsFallbackReason else null,
        )
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
}

