package org.tiqian.text.layout

import org.tiqian.text.clreq.ClreqPunctuationPolicies
import org.tiqian.text.clreq.PunctuationClass
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
)

data class PunctuationInkInput(
    val advance: Float,
    val inkBounds: Rect? = null,
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
     * When two punctuation atoms are adjacent, the inner glue between
     * them (left's trailing + right's leading) should be halved to
     * achieve the CLREQ target of 1.5em for two adjacent half-width
     * punctuation marks.
     *
     * With class-based single-sided glue, the inner gap might be
     * entirely on one side (e.g. `，。` → trailing=8 + leading=0 = 8).
     * The compression target is half of the natural inner glue.
     */
    fun compress(atoms: List<PunctuationAtom>): PunctuationSpacingCompressionResult {
        if (atoms.size < 2) return PunctuationSpacingCompressionResult(emptyList())

        val adjustments = atoms.zipWithNext().mapNotNull { (left, right) ->
            if (left.range.end != right.range.start) return@mapNotNull null

            val naturalInnerGlue = left.trailingGlue.natural + right.leadingGlue.natural
            if (naturalInnerGlue <= 0f) return@mapNotNull null

            val adjustedInnerGlue = naturalInnerGlue / 2f
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

class PunctuationAtomBuilder {
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
     * Glue placement follows CLREQ class, not ink position:
     * - **Opening** (`「（《`): glue on the leading side (ink is trailing).
     * - **Closing / PauseOrStop** (`」）。，`): glue on the trailing side (ink is leading).
     * - **Symmetric** (middle dot, interpunct, etc.): glue split evenly.
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
    ): PunctuationAtom? {
        val policy = ClreqPunctuationPolicies.policyFor(char)
        if (policy.punctuationClass == PunctuationClass.Other) return null

        val policyAdvance = policy.defaultAdvanceEm * em
        val advance = inkInput?.advance?.takeIf { it > 0f } ?: policyAdvance
        val bodyWidth = (policy.defaultBodyEm * em).coerceAtMost(advance)

        // Diagnostic ink fields — not used for glue calculation.
        val inkBounds = inkInput?.inkBounds
        val inkWidth = inkBounds?.width?.coerceAtLeast(0f)
        val inkCenter = inkBounds?.let { ((it.left + it.right) / 2f).coerceIn(0f, advance) }

        // Glue direction is determined by punctuation class, not ink position.
        val totalGlue = (advance - bodyWidth).coerceAtLeast(0f)
        val (leadingGlueNatural, trailingGlueNatural) = classBasedGlue(
            punctuationClass = policy.punctuationClass,
            totalGlue = totalGlue,
        )

        val anchor = when (policy.punctuationClass) {
            PunctuationClass.Opening -> PunctuationAnchor.Trailing
            PunctuationClass.Closing,
            PunctuationClass.PauseOrStop,
            -> PunctuationAnchor.Leading
            else -> PunctuationAnchor.Center
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
                inkInput?.inkBounds != null -> "ClassDerivedWithInkDiagnostics"
                inkInput != null -> "ClassDerivedWithShapedAdvance"
                else -> "PolicyDerived"
            },
            policyBodyFloor = bodyWidth,
            inkWidth = inkWidth,
            inkCenter = inkCenter,
        )
    }

    /**
     * Named heuristic: `ClassDerivedGlueDirection`.
     *
     * Opening punctuation: all glue on the leading side (body anchored trailing).
     * Closing / PauseOrStop: all glue on the trailing side (body anchored leading).
     * Symmetric (MiddleDot, Interpunct, Connector, Solidus, Ellipsis, Dash, Quote):
     *   glue split evenly on both sides.
     */
    private fun classBasedGlue(
        punctuationClass: PunctuationClass,
        totalGlue: Float,
    ): Pair<Float, Float> =
        when (punctuationClass) {
            PunctuationClass.Opening ->
                totalGlue to 0f

            PunctuationClass.Closing,
            PunctuationClass.PauseOrStop,
            ->
                0f to totalGlue

            else -> {
                val sideGlue = totalGlue / 2f
                sideGlue to sideGlue
            }
        }
}

