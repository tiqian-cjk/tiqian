package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.core.LineEndReason
import org.tiqian.core.TextRange

interface LineBreaker {
    val strategyName: String
        get() = "custom"

    fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        /**
         * Tiered in-line shrink resources for PushIn, ordered per CLREQ's
         * 挤压处理优先顺序 (ADR 0020). Lower tier = consumed first; the
         * offender's own trailing glue is promoted to tier 1 (行末标点
         * 调成半宽) at repair time.
         */
        shrinkOpportunities: List<ShrinkOpportunity> = emptyList(),
        /**
         * Cluster-index ranges that must stay on one line when they fit
         * (示亡号 spans, ADR 0018). `MourningSpanKeptUnbroken`: a break that
         * would land strictly inside a range moves to the range start
         * instead; a range wider than the measure falls back to splitting.
         */
        unbreakableRanges: List<IntRange> = emptyList(),
        /**
         * 段首缩进 in layout units: the line that starts at cluster 0 has
         * its usable measure reduced to `maxWidth - firstLineIndent`. All
         * other lines use the full [maxWidth].
         */
        firstLineIndent: Float = 0f,
        /**
         * `LineEndHangingPunctuation` (CLREQ 行尾点号悬挂, ADR 0006): cluster
         * indices of 顿/逗/句 that MAY hang past the measure when they would
         * otherwise land at line start. Empty = disabled (default). Tried
         * after PushIn, before CarryPrevious — the hung mark sits beyond
         * `maxWidth` instead of pulling a whole character down.
         */
        hangableClusters: Set<Int> = emptySet(),
        /**
         * Forbidden-at-line-start cluster indices, resolved by the caller
         * from the profile's [org.tiqian.clreq.KinsokuLevel]. When
         * non-null this overrides the breaker's own [KinsokuRule] (so the
         * paragraph engine can carry the profile level); null = fall back to
         * the injected rule (standalone breaker use / tests).
         */
        forbiddenLineStartClusters: Set<Int>? = null,
        /**
         * Forbidden-at-line-END cluster indices (开引号/开括号; GB·严格 的
         * 分隔号). A break that would end a line on one of these retreats
         * (`adjustBreakForLineEnd`), moving the mark to the next line's
         * start — recorded as [RepairOption.CarryNext]. Empty/null = no
         * line-end prohibition (e.g. KinsokuLevel.None).
         */
        forbiddenLineEndClusters: Set<Int> = emptySet(),
        /**
         * `LineEndHangingHyphen` (ADR 0029): cluster indices a break before which
         * is a Western syllable / hard-break continuation. The breaker prefers a
         * whole-word break and only takes one of these when the word is over-long
         * (mandatory) or the whole-word line would stretch 汉字间距 past
         * [maxCjkStretchPerGap] (last resort). Empty = no hyphenation.
         */
        hyphenBreakClusters: Set<Int> = emptySet(),
        /** CJK↔CJK boundary cluster indices — the stretchable gaps looseness is measured over. */
        cjkInterCharBoundaries: Set<Int> = emptySet(),
        /** Per-CJK-gap stretch above which a whole-word line counts as「太松」⇒ hyphenate. */
        maxCjkStretchPerGap: Float = Float.POSITIVE_INFINITY,
        /** CJK↔Latin boundary cluster indices — 中西间距 absorbs deficit before 汉字间距. */
        sinoWesternBoundaries: Set<Int> = emptySet(),
        /** Per-中西间距 stretch capacity (cap − natural); subtracted before the CJK looseness. */
        sinoWesternStretchCap: Float = 0f,
        /**
         * `LineAdjustmentPushIn` (ADR 0031): when true, a fill pass pulls an
         * over-the-edge cluster onto the previous line and compresses to fit
         * whenever 压缩 is the smaller (bias-weighted) deviation than stretching.
         * False (default) = 仅推出, the historical greedy-then-stretch behavior.
         */
        lineAdjustmentPushIn: Boolean = false,
        /** `Ws/Wc` — how much cheaper 压缩 is than 拉伸 (＞1 = 先挤压). See [applyFillPushIn]. */
        lineAdjustmentCompressBias: Float = 1f,
        /**
         * Cluster indices whose line must end immediately after that cluster
         * (ADR 0037 mandatory breaks). These boundaries are source-authored:
         * line breaking, kinsoku repair, fill PushIn, and justification must
         * not cross them.
         */
        hardBreakAfterClusters: Set<Int> = emptySet(),
    ): LineSolution
}

/**
 * Where to break given a greedy overflow at [overflowAt] (the first cluster that
 * does not fit). Prefers the last whole-word boundary; takes the hyphenation
 * break (returns [overflowAt]) only when the word is over-long (fills from
 * [lineStart]) or wrapping it whole would stretch the line's 汉字间距 past
 * [maxCjkStretchPerGap]. With no [hyphenBreakClusters] this is a no-op
 * (returns [overflowAt]).
 */
internal fun decideHyphenBreak(
    lineStart: Int,
    overflowAt: Int,
    adjustedClusters: List<Cluster>,
    lineLimit: Float,
    hyphenBreakClusters: Set<Int>,
    cjkInterCharBoundaries: Set<Int>,
    maxCjkStretchPerGap: Float,
    sinoWesternBoundaries: Set<Int> = emptySet(),
    sinoWesternStretchCap: Float = 0f,
): Int {
    if (overflowAt !in hyphenBreakClusters) return overflowAt // overflow at a word boundary
    var wholeWordEnd = overflowAt
    while (wholeWordEnd > lineStart && wholeWordEnd in hyphenBreakClusters) wholeWordEnd -= 1
    if (wholeWordEnd <= lineStart) return overflowAt // over-long word fills from lineStart: must hyphenate
    var width = 0f
    for (k in lineStart until wholeWordEnd) width += adjustedClusters[k].advance
    val deficit = lineLimit - width
    if (deficit <= 0f) return wholeWordEnd
    // CLREQ 拉伸顺序：中西间距先于汉字间距吸收 deficit。扣掉中西间距能吸收的
    // 部分，剩下的才是真正落到汉字间距上的增量（词距是二分空、已在 cap，不吸收）。
    val sinoWestern = (lineStart + 1 until wholeWordEnd).count { it in sinoWesternBoundaries }
    val cjkDeficit = (deficit - sinoWestern * sinoWesternStretchCap).coerceAtLeast(0f)
    if (cjkDeficit <= 0f) return wholeWordEnd
    val gaps = (lineStart + 1 until wholeWordEnd).count { it in cjkInterCharBoundaries }
    val tooLoose = gaps == 0 || cjkDeficit / gaps > maxCjkStretchPerGap
    return if (tooLoose) overflowAt else wholeWordEnd
}

/**
 * CLREQ 行尾禁则 break retreat: returns a break ≤ [breakAt] such that the
 * line `[lineStart, result)` does not end on a forbidden-at-line-end mark.
 * Retreats past consecutive trailing marks; never empties the line (keeps
 * ≥1 cluster), so the rare all-forbidden tail keeps the violation.
 */
internal fun adjustBreakForLineEnd(
    breakAt: Int,
    lineStart: Int,
    forbiddenLineEndClusters: Set<Int>,
): Int {
    var b = breakAt
    while (b - 1 > lineStart && (b - 1) in forbiddenLineEndClusters) b -= 1
    return b
}

/** Usable measure of a line starting at [lineStartCluster] (段首缩进). */
internal fun lineLimit(maxWidth: Float, firstLineIndent: Float, lineStartCluster: Int): Float =
    if (lineStartCluster == 0) maxWidth - firstLineIndent else maxWidth

/**
 * One shrinkable resource on a cluster (ADR 0020 + 2026-06-13 amendment,
 * CLREQ 挤压处理优先顺序七档):
 *
 * - tier 1 — 行末标点削半宽（offender 自身 trailing glue，repair 时晋升）
 * - tier 2 — 西文词距，最小压至 1/4em
 * - tier 3 — 间隔号/居中类，两侧同时等量，压至 0
 * - tier 4 — 夹注符号外侧：开括号/开引号前侧、闭括号/闭引号后侧
 * - tier 5 — 行内逗、顿、分号 trailing glue（冒号等未尽列者同档兜底）
 * - tier 6 — 中西间距，最小压至 1/8em（风格开关可禁）
 * - tier 7 — 行内句号/问号/感叹号 trailing glue（风格开关可禁）
 */
data class ShrinkOpportunity(
    val clusterIndex: Int,
    val tier: Int,
    val capacity: Float,
    val channel: ShrinkChannel,
    /**
     * Usable only when this cluster becomes the merged line's END (tier-1
     * promotion). Used when `allowInlineStopCompression` is off: 行内句问叹
     * keep full width, but 行末削半 (a different CLREQ rule) still applies.
     */
    val lineEndOnly: Boolean = false,
)

enum class ShrinkChannel {
    /** Consume the punctuation atom's trailing glue. */
    TrailingGlue,

    /**
     * Consume the punctuation atom's LEADING glue (开夹注符号前侧，CLREQ
     * 挤压④). Renderers shift the glyph origin left by the consumed amount
     * (ADR 0017 amendment).
     */
    LeadingGlue,

    /** Consume leading and trailing glue simultaneously, equal amounts. */
    LeadingAndTrailingGlue,

    /** Reduce the cluster's raw advance (word spaces, gap clusters). */
    RawAdvance,
}

/**
 * Moves [breakAt] out of any unbreakable range it falls strictly inside of
 * (to the range start), provided the line keeps at least one cluster.
 * Returns [breakAt] unchanged otherwise — including the give-up case where
 * the range itself is wider than the line (split fallback).
 */
internal fun adjustBreakForUnbreakables(
    breakAt: Int,
    lineStart: Int,
    unbreakableRanges: List<IntRange>,
): Int {
    val containing = unbreakableRanges.firstOrNull { breakAt > it.first && breakAt <= it.last }
        ?: return breakAt
    return if (containing.first > lineStart) containing.first else breakAt
}

/**
 * GreedyLineBreaker — fills each line until the next cluster would overflow,
 * then starts a new line. After the greedy pass, [kinsoku] is consulted to
 * detect breaks that would place a forbidden-at-line-start cluster at the
 * beginning of a line; such breaks try PushIn first, then CarryPrevious
 * (move the previous cluster onto the next line together with the offender).
 *
 * Repairs that cannot be applied without leaving a line empty fall back to
 * [RepairOption.LeaveRagged] — the unfortunate break is recorded but kept.
 *
 * Slice 4b scope: PushIn via punctuation glue, CarryPrevious, and LeaveRagged.
 * Hang remains profile opt-in and is not a default repair.
 */
class GreedyLineBreaker(
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val pushInPenalty: Int = 2,
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
) : LineBreaker {
    override val strategyName: String = "greedy"

    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        unbreakableRanges: List<IntRange>,
        firstLineIndent: Float,
        hangableClusters: Set<Int>,
        forbiddenLineStartClusters: Set<Int>?,
        forbiddenLineEndClusters: Set<Int>,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        lineAdjustmentPushIn: Boolean,
        lineAdjustmentCompressBias: Float,
        hardBreakAfterClusters: Set<Int>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }

        val greedy = greedyFill(
            naturalClusters, adjustedClusters, maxWidth, unbreakableRanges,
            firstLineIndent, forbiddenLineEndClusters,
            hyphenBreakClusters, cjkInterCharBoundaries, maxCjkStretchPerGap,
            sinoWesternBoundaries, sinoWesternStretchCap,
            hardBreakAfterClusters,
        )
        val repaired = applyKinsokuRepairs(
            initial = greedy,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
            unbreakableRanges = unbreakableRanges,
            firstLineIndent = firstLineIndent,
            hangableClusters = hangableClusters,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
        )
        return repaired.withFillPushIn(
            lineAdjustmentPushIn, naturalClusters, adjustedClusters, maxWidth,
            shrinkOpportunities, firstLineIndent, lineAdjustmentCompressBias,
            forbiddenLineStartClusters, forbiddenLineEndClusters, unbreakableRanges, pushInPenalty,
            gapBoundaries = cjkInterCharBoundaries + sinoWesternBoundaries,
        )
    }

    private fun greedyFill(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        unbreakableRanges: List<IntRange>,
        firstLineIndent: Float,
        forbiddenLineEndClusters: Set<Int>,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        hardBreakAfterClusters: Set<Int>,
    ): List<LineCandidate> {
        val lines = mutableListOf<LineCandidate>()
        var lineStart = 0
        var adjustedAccum = 0f
        var naturalAccum = 0f

        var i = 0
        while (i < adjustedClusters.size) {
            val nextAdjusted = adjustedAccum + adjustedClusters[i].advance
            val overflows = nextAdjusted > lineLimit(maxWidth, firstLineIndent, lineStart) && i > lineStart
            if (overflows) {
                val decided = decideHyphenBreak(
                    lineStart, i, adjustedClusters,
                    lineLimit(maxWidth, firstLineIndent, lineStart),
                    hyphenBreakClusters, cjkInterCharBoundaries, maxCjkStretchPerGap,
                    sinoWesternBoundaries, sinoWesternStretchCap,
                )
                val afterUnbreak = adjustBreakForUnbreakables(decided, lineStart, unbreakableRanges)
                val breakAt = adjustBreakForLineEnd(afterUnbreak, lineStart, forbiddenLineEndClusters)
                lines += closeFilledLine(
                    lineStart..(breakAt - 1), afterUnbreak, naturalClusters, adjustedClusters,
                )
                lineStart = breakAt
                adjustedAccum = adjustedClusters[breakAt].advance
                naturalAccum = naturalClusters[breakAt].advance
                i = breakAt + 1
            } else {
                adjustedAccum = nextAdjusted
                naturalAccum += naturalClusters[i].advance
                if (i in hardBreakAfterClusters) {
                    lines += rebuildLine(
                        clusterRange = lineStart..i,
                        naturalClusters = naturalClusters,
                        adjustedClusters = adjustedClusters,
                        endReason = LineEndReason.MandatoryBreak,
                    )
                    lineStart = i + 1
                    adjustedAccum = 0f
                    naturalAccum = 0f
                }
                i += 1
            }
        }

        if (lineStart < adjustedClusters.size) {
            lines += rebuildLine(
                clusterRange = lineStart..adjustedClusters.lastIndex,
                naturalClusters = naturalClusters,
                adjustedClusters = adjustedClusters,
                endReason = LineEndReason.ParagraphEnd,
            )
        } else if (adjustedClusters.lastIndex in hardBreakAfterClusters) {
            lines += emptyLineCandidate(
                sourceOffset = adjustedClusters.last().range.end,
                endReason = LineEndReason.ParagraphEnd,
            )
        }
        return lines
    }

}

/**
 * Builds a line for [range]; if the break retreated from [naturalBreakAt]
 * (line-end kinsoku), records [RepairOption.CarryNext] for the mark(s) moved
 * to the next line.
 */
internal fun closeFilledLine(
    range: IntRange,
    naturalBreakAt: Int,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
): LineCandidate {
    val line = rebuildLine(range, naturalClusters, adjustedClusters)
    if (range.last + 1 == naturalBreakAt) return line
    val moved = range.last + 1
    return line.copy(
        repair = RepairOption.CarryNext(
            penalty = 0,
            reason = "ForbiddenAtLineEnd:${adjustedClusters[moved].text}:moved-to-next-line",
            movedClusterIndex = moved,
        ),
    )
}

/**
 * LookaheadLineBreaker — runs greedy first, then for each line decision tries
 * shifting the break by [window] clusters on either side and scores each
 * candidate by simulating the next [futureLineHorizon] lines (greedy + kinsoku
 * applied to the splice). Picks the candidate with the lowest combined badness.
 *
 * Badness per line = raggedness * [raggednessWeight] + repair penalty.
 * Last line raggedness is not penalized (a short last line is expected).
 *
 * Defaults are tuned so that a single em of raggedness costs less than a
 * CarryPrevious repair (8 vs 10), and noticeably less than LeaveRagged (8 vs
 * 20), so kinsoku conflicts that can be sidestepped by a one-cluster shift are
 * preferred over leaving the conflict in place.
 *
 * Default [window] is 2 — a cost/benefit middle ground: window 1 already
 * captures most of the repair-avoidance value, larger windows occasionally
 * trade worst-line deficit at narrow measures, and window 3+ has not shown
 * consistent benefit. The numbers are corpus-dependent; re-evaluate with
 * `LookaheadWindowProbe` when the fixture corpus changes.
 */
class LookaheadLineBreaker(
    private val window: Int = 2,
    private val futureLineHorizon: Int = 2,
    private val raggednessWeight: Float = 0.5f,
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val pushInPenalty: Int = 2,
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
    private val consecutiveSyntheticHyphenPenalty: Float = 12f,
) : LineBreaker {
    override val strategyName: String = "lookahead"

    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        unbreakableRanges: List<IntRange>,
        firstLineIndent: Float,
        hangableClusters: Set<Int>,
        forbiddenLineStartClusters: Set<Int>?,
        forbiddenLineEndClusters: Set<Int>,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        lineAdjustmentPushIn: Boolean,
        lineAdjustmentCompressBias: Float,
        hardBreakAfterClusters: Set<Int>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }
        require(window >= 0) { "window must be non-negative." }
        require(futureLineHorizon >= 0) { "futureLineHorizon must be non-negative." }

        val committed = mutableListOf<LineCandidate>()
        var lineStart = 0
        // NeighborAmortizedAdjustment (ADR 0038): gaps that justification can
        // open — CJK 字距 + 中西间距 — price the per-line density; the last
        // committed line's density seeds the neighbor-difference term.
        val gapBoundaries = cjkInterCharBoundaries + sinoWesternBoundaries
        val dRef = maxCjkStretchPerGap
        var committedDensity = 0f
        var committedSyntheticHyphenRun = 0
        // Sorted once; `lineStart` only advances, so a monotonic cursor finds
        // the next mandatory break in amortized O(1) — newline-heavy text has
        // lines ≈ breaks, so a per-line set scan would be quadratic.
        val sortedBreaks = hardBreakAfterClusters.toIntArray().also { it.sort() }
        var breakCursor = 0
        while (lineStart < adjustedClusters.size) {
            while (breakCursor < sortedBreaks.size && sortedBreaks[breakCursor] < lineStart) breakCursor += 1
            val mandatoryEnd = if (breakCursor < sortedBreaks.size) sortedBreaks[breakCursor] else null
            val segmentEndExclusive = mandatoryEnd?.plus(1) ?: adjustedClusters.size
            // Line-end retreat is applied at commit (below), not here, so the
            // chosen break's pre-retreat position is known and CarryNext can
            // be labelled. decideHyphenBreak makes the greedy baseline obey the
            // last-resort hyphenation rule (whole-word unless over-long/太松).
            val greedyEnd = adjustBreakForUnbreakables(
                breakAt = decideHyphenBreak(
                    lineStart = lineStart,
                    overflowAt = findGreedyEnd(
                        adjustedClusters,
                        lineStart,
                        lineLimit(maxWidth, firstLineIndent, lineStart),
                        endExclusive = segmentEndExclusive,
                    ),
                    adjustedClusters = adjustedClusters,
                    lineLimit = lineLimit(maxWidth, firstLineIndent, lineStart),
                    hyphenBreakClusters = hyphenBreakClusters,
                    cjkInterCharBoundaries = cjkInterCharBoundaries,
                    maxCjkStretchPerGap = maxCjkStretchPerGap,
                    sinoWesternBoundaries = sinoWesternBoundaries,
                    sinoWesternStretchCap = sinoWesternStretchCap,
                ),
                lineStart = lineStart,
                unbreakableRanges = unbreakableRanges,
            )
            if (greedyEnd >= segmentEndExclusive) {
                if (mandatoryEnd != null) {
                    committed += rebuildLine(
                        lineStart..mandatoryEnd,
                        naturalClusters,
                        adjustedClusters,
                        endReason = LineEndReason.MandatoryBreak,
                    )
                    committedDensity = 0f
                    committedSyntheticHyphenRun = 0
                    lineStart = mandatoryEnd + 1
                    if (lineStart == adjustedClusters.size) {
                        committed += emptyLineCandidate(
                            sourceOffset = adjustedClusters.last().range.end,
                            endReason = LineEndReason.ParagraphEnd,
                        )
                    }
                    continue
                }
                committed += rebuildLine(
                    lineStart..adjustedClusters.lastIndex,
                    naturalClusters,
                    adjustedClusters,
                    endReason = LineEndReason.ParagraphEnd,
                )
                break
            }

            // Candidates only shift earlier than greedy. PushIn is evaluated
            // during the repair pass below, where punctuation glue capacity is
            // known and the shrink can be recorded on the chosen line.
            // Breaks inside an unbreakable span are never candidates.
            val candidates = ((greedyEnd - window)..greedyEnd)
                .filter { it in (lineStart + 1)..adjustedClusters.size }
                .filter { it <= segmentEndExclusive }
                .filter { e -> unbreakableRanges.none { e > it.first && e <= it.last } }
                .distinct()
                .ifEmpty { listOf(greedyEnd) }

            var bestEnd = greedyEnd
            var bestScore = Float.POSITIVE_INFINITY
            for (e in candidates) {
                val score = scoreCandidate(
                    s = lineStart,
                    e = e,
                    natural = naturalClusters,
                    adjusted = adjustedClusters,
                    maxWidth = maxWidth,
                    shrinkOpportunities = shrinkOpportunities,
                    firstLineIndent = firstLineIndent,
                    hangableClusters = hangableClusters,
                    forbiddenLineStartClusters = forbiddenLineStartClusters,
                    hyphenBreakClusters = hyphenBreakClusters,
                    cjkInterCharBoundaries = cjkInterCharBoundaries,
                    maxCjkStretchPerGap = maxCjkStretchPerGap,
                    sinoWesternBoundaries = sinoWesternBoundaries,
                    sinoWesternStretchCap = sinoWesternStretchCap,
                    segmentEndExclusive = segmentEndExclusive,
                    prevCommittedDensity = committedDensity,
                    prevSyntheticHyphenRun = committedSyntheticHyphenRun,
                    gapBoundaries = gapBoundaries,
                    dRef = dRef,
                    unbreakableRanges = unbreakableRanges,
                )
                if (score < bestScore) {
                    bestScore = score
                    bestEnd = e
                }
            }

            // Line-end kinsoku may retreat the chosen break further; the
            // mark moves to the next line (cascade-free shorten).
            val committedEnd = adjustBreakForLineEnd(bestEnd, lineStart, forbiddenLineEndClusters)
            if (committedEnd in hardBreakAfterClusters && lineStart < committedEnd) {
                // MandatoryBreakBindsPreviousLine: a zero-width authored break
                // must terminate the preceding visual line. Lookahead may
                // prefer the width-identical candidate just before the break;
                // committing it literally would leave "\n" as a standalone
                // line and create a bogus blank row.
                committed += rebuildLine(
                    lineStart..committedEnd,
                    naturalClusters,
                    adjustedClusters,
                    endReason = LineEndReason.MandatoryBreak,
                )
                committedDensity = 0f
                committedSyntheticHyphenRun = 0
                lineStart = committedEnd + 1
                if (lineStart == adjustedClusters.size) {
                    committed += emptyLineCandidate(
                        sourceOffset = adjustedClusters.last().range.end,
                        endReason = LineEndReason.ParagraphEnd,
                    )
                }
                continue
            }
            committed += closeFilledLine(
                lineStart..(committedEnd - 1), bestEnd, naturalClusters, adjustedClusters,
            )
            committed.last().let { line ->
                val limit = lineLimit(maxWidth, firstLineIndent, line.clusterRange.first)
                committedDensity = lineAdjustmentDensity(line, limit, isLast = false, gapBoundaries)
                committedSyntheticHyphenRun = if (line.endsWithSyntheticHyphen(hyphenBreakClusters)) {
                    committedSyntheticHyphenRun + 1
                } else {
                    0
                }
            }
            lineStart = committedEnd
        }

        return applyKinsokuRepairs(
            initial = committed,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
            unbreakableRanges = unbreakableRanges,
            firstLineIndent = firstLineIndent,
            hangableClusters = hangableClusters,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
        ).withFillPushIn(
            lineAdjustmentPushIn, naturalClusters, adjustedClusters, maxWidth,
            shrinkOpportunities, firstLineIndent, lineAdjustmentCompressBias,
            forbiddenLineStartClusters, forbiddenLineEndClusters, unbreakableRanges, pushInPenalty,
            gapBoundaries = gapBoundaries,
        )
    }

    private fun scoreCandidate(
        s: Int,
        e: Int,
        natural: List<Cluster>,
        adjusted: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        firstLineIndent: Float,
        hangableClusters: Set<Int>,
        forbiddenLineStartClusters: Set<Int>?,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        segmentEndExclusive: Int = adjusted.size,
        prevCommittedDensity: Float = 0f,
        prevSyntheticHyphenRun: Int = 0,
        gapBoundaries: Set<Int> = emptySet(),
        dRef: Float = 1f,
        unbreakableRanges: List<IntRange> = emptyList(),
    ): Float {
        val firstLine = rebuildLine(s..(e - 1), natural, adjusted)
        val future = rawGreedyLinesFrom(
            start = e,
            natural = natural,
            adjusted = adjusted,
            maxWidth = maxWidth,
            hyphenBreakClusters = hyphenBreakClusters,
            cjkInterCharBoundaries = cjkInterCharBoundaries,
            maxCjkStretchPerGap = maxCjkStretchPerGap,
            sinoWesternBoundaries = sinoWesternBoundaries,
            sinoWesternStretchCap = sinoWesternStretchCap,
            endExclusive = segmentEndExclusive,
            unbreakableRanges = unbreakableRanges,
        )
        // Apply kinsoku once across [firstLine] + future so both splice
        // conflicts and future-line conflicts are scored with the same PushIn
        // capacity map as the final repair pass.
        val spliced = applyKinsokuRepairs(
            initial = listOf(firstLine) + future,
            naturalClusters = natural,
            adjustedClusters = adjusted,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
            unbreakableRanges = unbreakableRanges,
            firstLineIndent = firstLineIndent,
            hangableClusters = hangableClusters,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
        ).lines

        val horizon = (1 + futureLineHorizon).coerceAtMost(spliced.size)
        var score = 0f
        var prevD = prevCommittedDensity
        var syntheticHyphenRun = prevSyntheticHyphenRun
        for (idx in 0 until horizon) {
            val line = spliced[idx]
            val isLast = (idx == spliced.lastIndex)
            score += badness(line, maxWidth, isLast, firstLineIndent, prevD, gapBoundaries, dRef)
            // AvoidConsecutiveSyntheticHyphenBreaks: consecutive generated
            // hyphens read choppy. This is only a soft lookahead demerit and
            // only applies to `hyphenBreakClusters`; clean breaks at existing
            // '-' or CamelCase boundaries are intentionally unaffected.
            if (line.endsWithSyntheticHyphen(hyphenBreakClusters)) {
                score += consecutiveSyntheticHyphenPenalty * syntheticHyphenRun
                syntheticHyphenRun += 1
            } else {
                syntheticHyphenRun = 0
            }
            val limit = lineLimit(maxWidth, firstLineIndent, line.clusterRange.first)
            prevD = lineAdjustmentDensity(line, limit, isLast, gapBoundaries)
        }
        return score
    }

    private fun rawGreedyLinesFrom(
        start: Int,
        natural: List<Cluster>,
        adjusted: List<Cluster>,
        maxWidth: Float,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        endExclusive: Int = adjusted.size,
        unbreakableRanges: List<IntRange> = emptyList(),
    ): List<LineCandidate> {
        if (start >= endExclusive) return emptyList()

        val lines = mutableListOf<LineCandidate>()
        var lineStart = start
        var adjustedAccum = 0f

        var i = start
        while (i < endExclusive) {
            val nextAdjusted = adjustedAccum + adjusted[i].advance
            val overflows = nextAdjusted > maxWidth && i > lineStart
            if (overflows) {
                // Honest futures (ADR 0038): simulated lines obey the same
                // unbreakable groups as committed ones — a candidate must not
                // win by pretending 示亡号/数字组 can split downstream.
                val breakAt = adjustBreakForUnbreakables(
                    breakAt = decideHyphenBreak(
                        lineStart, i, adjusted, maxWidth,
                        hyphenBreakClusters, cjkInterCharBoundaries, maxCjkStretchPerGap,
                        sinoWesternBoundaries, sinoWesternStretchCap,
                    ),
                    lineStart = lineStart,
                    unbreakableRanges = unbreakableRanges,
                )
                lines += rebuildLine(
                    clusterRange = lineStart..(breakAt - 1),
                    naturalClusters = natural,
                    adjustedClusters = adjusted,
                )
                lineStart = breakAt
                adjustedAccum = adjusted[breakAt].advance
                i = breakAt + 1
            } else {
                adjustedAccum = nextAdjusted
                i += 1
            }
        }

        lines += rebuildLine(
            clusterRange = lineStart..(endExclusive - 1),
            naturalClusters = natural,
            adjustedClusters = adjusted,
            endReason = LineEndReason.ParagraphEnd,
        )
        return lines
    }

    private fun badness(
        line: LineCandidate,
        maxWidth: Float,
        isLast: Boolean,
        firstLineIndent: Float,
        prevDensity: Float,
        gapBoundaries: Set<Int>,
        dRef: Float,
    ): Float {
        // NeighborAmortizedAdjustment (ADR 0038): price the POST-JUSTIFY state.
        // A deficit on a line WITH stretchable gaps becomes spacing — priced by
        // the convex density term (+ neighbor difference), so spreading small
        // amounts over many gaps is near-free and concentration is punished.
        // A deficit on a gapless line CANNOT fill — it stays a ragged edge and
        // keeps the linear price (which is also the exact pre-0038 contract for
        // standalone breaker use, where no gap sets are provided).
        val limit = lineLimit(maxWidth, firstLineIndent, line.clusterRange.first)
        val ragged = if (isLast) 0f else (limit - line.adjustedWidth).coerceAtLeast(0f)
        val gaps = lineGapCount(line.clusterRange, gapBoundaries)
        val residual = if (gaps == 0) ragged else 0f
        val d = lineAdjustmentDensity(line, limit, isLast, gapBoundaries)
        // SingleClusterLinePenalty: 孤字行(非末行单 cluster)是排版忌讳——在
        // 窄测下它可能只比「密拉伸」便宜几分,显式罚分让它只作最后手段。
        val orphan = if (!isLast && !line.clusterRange.isEmptyClusterRange() &&
            line.clusterRange.first == line.clusterRange.last
        ) {
            leaveRaggedPenalty.toFloat()
        } else {
            0f
        }
        return residual * raggednessWeight + orphan +
            amortizedAdjustmentCost(d, prevDensity, dRef) * raggednessWeight +
            (line.repair?.penalty ?: 0).toFloat()
    }
}

private fun LineCandidate.endsWithSyntheticHyphen(hyphenBreakClusters: Set<Int>): Boolean =
    endReason == LineEndReason.AutoWrap &&
        !clusterRange.isEmptyClusterRange() &&
        clusterRange.last + 1 in hyphenBreakClusters

internal fun applyKinsokuRepairs(
    initial: List<LineCandidate>,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    kinsoku: KinsokuRule,
    shrinkOpportunities: List<ShrinkOpportunity> = emptyList(),
    pushInPenalty: Int,
    carryPreviousPenalty: Int,
    leaveRaggedPenalty: Int,
    unbreakableRanges: List<IntRange> = emptyList(),
    firstLineIndent: Float = 0f,
    hangableClusters: Set<Int> = emptySet(),
    hangPenalty: Int = 5,
    forbiddenLineStartClusters: Set<Int>? = null,
): LineSolution {
    if (initial.size < 2) return LineSolution(initial)

    val mutable = initial.toMutableList()
    var i = 1
    while (i < mutable.size) {
        val curr = mutable[i]
        val firstIndex = curr.clusterRange.first
        val prev = mutable[i - 1]
        if (prev.endReason == LineEndReason.MandatoryBreak || curr.clusterRange.isEmptyClusterRange()) {
            i += 1
            continue
        }
        val firstCluster = adjustedClusters[firstIndex]
        // KinsokuLevel: the engine resolves the forbidden set from the
        // profile level; standalone breaker use falls back to the rule.
        val forbidden = forbiddenLineStartClusters?.contains(firstIndex)
            ?: kinsoku.forbiddenAtLineStart(firstCluster)
        if (!forbidden) {
            i += 1
            continue
        }

        val repairCandidates = mutableListOf<RepairCandidate>()
        val pushIn = tryPushIn(
            prev = prev,
            curr = curr,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            // The merged line keeps prev's start — a first-line PushIn must
            // fit inside the indented measure.
            maxWidth = lineLimit(maxWidth, firstLineIndent, prev.clusterRange.first),
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
        )
        repairCandidates += pushIn.candidate
        if (pushIn.candidate.accepted) {
            mutable[i - 1] = pushIn.previous
            if (pushIn.current == null) {
                mutable.removeAt(i)
            } else {
                mutable[i] = pushIn.current
                continue
            }
            continue
        }

        // LineEndHangingPunctuation (CLREQ 行尾点号悬挂, ADR 0006): when
        // PushIn cannot fit the 顿/逗/句 offender, hang it past the measure
        // on the previous line instead of carrying a whole character down.
        // 行尾只悬挂一个 — never chain onto a line that already hangs.
        val offenderIndex = curr.clusterRange.first
        if (offenderIndex in hangableClusters && prev.hangingClusterIndex == null) {
            val mergeEndIndex = mandatoryBreakTailEnd(curr, offenderIndex, adjustedClusters)
            val hangCandidate = RepairCandidate(
                kind = "Hang",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = offenderIndex,
                penalty = hangPenalty,
                accepted = true,
            )
            repairCandidates += hangCandidate
            val mergedRange = prev.clusterRange.first..mergeEndIndex
            mutable[i - 1] = LineCandidate(
                clusterRange = mergedRange,
                sourceRange = TextRange(
                    adjustedClusters[mergedRange.first].range.start,
                    adjustedClusters[mergeEndIndex].range.end,
                ),
                // The hung mark sits BEYOND the measure: it is excluded from
                // the line's measure-fill width (content fills to maxWidth,
                // the mark overflows).
                naturalWidth = prev.naturalWidth +
                    (prev.clusterRange.last + 1..mergeEndIndex)
                        .sumOf { naturalClusters[it].advance.toDouble() }
                        .toFloat(),
                adjustedWidth = prev.adjustedWidth,
                repair = RepairOption.Hang(
                    penalty = hangPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:hang",
                    offenderClusterIndex = offenderIndex,
                ),
                repairCandidates = prev.repairCandidates + pushIn.candidate + hangCandidate,
                hangingClusterIndex = offenderIndex,
                endReason = if (mergeEndIndex == curr.clusterRange.last) curr.endReason else prev.endReason,
            )
            if (mergeEndIndex == curr.clusterRange.last) {
                mutable.removeAt(i)
            } else {
                mutable[i] = rebuildLine(
                    (mergeEndIndex + 1)..curr.clusterRange.last,
                    naturalClusters,
                    adjustedClusters,
                    endReason = curr.endReason,
                )
                continue
            }
            continue
        }

        val canCarry = prev.clusterRange.first < prev.clusterRange.last
        if (!canCarry) {
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "no-room-to-carry",
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:no-room-to-carry",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }

        val carriedIndex = prev.clusterRange.last
        // CarryPrevious must not split an unbreakable span: carrying any
        // cluster other than the span's first would leave part of the span
        // behind on the previous line.
        val splitsUnbreakable = unbreakableRanges.any {
            carriedIndex > it.first && carriedIndex <= it.last
        }
        if (splitsUnbreakable) {
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "carry-would-split-mourning-span",
                carriedClusterIndex = carriedIndex,
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:carry-would-split-mourning-span",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }
        val newPrevRange = prev.clusterRange.first..(carriedIndex - 1)
        val newCurrRange = carriedIndex..curr.clusterRange.last
        val carriedCurrent = rebuildLine(
            newCurrRange,
            naturalClusters,
            adjustedClusters,
            endReason = curr.endReason,
        )
        if (carriedCurrent.adjustedWidth > maxWidth) {
            // CLREQ 推出 may not overflow maxWidth — that would be effectively
            // hanging punctuation, which is opt-in per ADR 0006. When the
            // receiving line is already at capacity, this fallback leaves
            // the offender at line start with a LeaveRagged marker. The
            // lookahead breaker is expected to avoid hitting this case by
            // picking a break that has room downstream.
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "carry-overflows",
                carriedClusterIndex = carriedIndex,
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:carry-overflows",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }

        repairCandidates += RepairCandidate(
            kind = "CarryPrevious",
            reasonCode = "ForbiddenAtLineStart",
            offenderClusterIndex = curr.clusterRange.first,
            penalty = carryPreviousPenalty,
            accepted = true,
            carriedClusterIndex = carriedIndex,
        )
        mutable[i - 1] = rebuildLine(
            newPrevRange,
            naturalClusters,
            adjustedClusters,
            endReason = prev.endReason,
        )
        mutable[i] = carriedCurrent.copy(
            repair = RepairOption.CarryPrevious(
                penalty = carryPreviousPenalty,
                reason = "ForbiddenAtLineStart:${firstCluster.text}:carried=${adjustedClusters[carriedIndex].text}",
                offenderClusterIndex = curr.clusterRange.first,
                carriedClusterIndex = carriedIndex,
            ),
            repairCandidates = repairCandidates,
        )
        i += 1
    }

    val totalBadness = mutable.sumOf { (it.repair?.penalty ?: 0).toDouble() }.toFloat()
    return LineSolution(mutable, totalBadness = totalBadness)
}

private data class PushInResult(
    val previous: LineCandidate,
    val current: LineCandidate?,
    val candidate: RepairCandidate,
)

/**
 * CLREQ 推入 — compress IN-LINE glue (across every cluster on the merged
 * line) to fit the offender. The offender's own trailing glue is one of
 * many possible contributors; the previous line's `、`, `，`, etc. all
 * count.
 *
 * Single-source contract:
 *   `totalShrink` is the canonical amount of glue this PushIn consumes
 *   across the whole line. `allocations` records per-cluster shrink so the
 *   engine can subtract from each cluster's advance independently.
 *   - [LineCandidate.adjustedWidth] is recomputed here as
 *     `expanded.adjustedWidth - totalShrink` to keep ADR 0005's drawable-
 *     cluster invariant: the line candidate already reflects the post-
 *     shrink geometry the breaker decided. The engine MUST NOT subtract
 *     allocation shrink from cluster advance and ALSO subtract it from
 *     `adjustedWidth` — pick one consumer per derived field.
 *   - Today `totalShrink == overflow`. If a future partial-PushIn lands
 *     (`totalShrink < overflow`), update it here and rely on it as the
 *     only knob; do not reintroduce a second `overflow`-based path.
 */
private fun tryPushIn(
    prev: LineCandidate,
    curr: LineCandidate,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    shrinkOpportunities: List<ShrinkOpportunity>,
    pushInPenalty: Int,
    mergeThroughClusterIndex: Int? = null,
    /**
     * Why this PushIn fired — `ForbiddenAtLineStart` for 避头尾 repair, or
     * `LineAdjustmentPushIn` for the `LineAdjustmentStrategy` fill pass
     * (ADR 0031). Surfaces in the dump so the two callers stay distinguishable.
     */
    reasonCode: String = "ForbiddenAtLineStart",
): PushInResult {
    val offenderIndex = mergeThroughClusterIndex ?: curr.clusterRange.first
    require(offenderIndex in curr.clusterRange) { "PushIn merge-through cluster must belong to the current line." }
    val mergeEndIndex = mandatoryBreakTailEnd(curr, offenderIndex, adjustedClusters)
    val expandedRange = prev.clusterRange.first..mergeEndIndex
    val expanded = rebuildLine(expandedRange, naturalClusters, adjustedClusters)
    val overflow = expanded.adjustedWidth - maxWidth

    // Tiered shrink resources across the merged line (CLREQ 挤压处理优先
    // 顺序, ADR 0020). The offender will sit at the merged line's END, so
    // its trailing glue IS the 行末标点削半宽 step — promote it to tier 1.
    val inLine = shrinkOpportunities
        .filter { it.clusterIndex in expandedRange && it.capacity > 0f }
        .filter { !it.lineEndOnly || it.clusterIndex == offenderIndex }
        .map { opp ->
            if (opp.clusterIndex == offenderIndex && opp.channel == ShrinkChannel.TrailingGlue) {
                opp.copy(tier = 1)
            } else {
                opp
            }
        }
    val totalCapacity = inLine.sumOf { it.capacity.toDouble() }.toFloat()

    if (overflow > totalCapacity) {
        return PushInResult(
            previous = prev,
            current = curr,
            candidate = RepairCandidate(
                kind = "PushIn",
                reasonCode = reasonCode,
                offenderClusterIndex = offenderIndex,
                penalty = pushInPenalty,
                accepted = false,
                rejectionReason = "insufficient-capacity",
                targetClusterIndex = offenderIndex,
                requiredShrink = overflow.coerceAtLeast(0f),
                availableCapacity = totalCapacity,
            ),
        )
    }

    // `overflow <= 0` is NOT a rejection: upstream repairs in the chain
    // (a PushIn / CarryPrevious on earlier lines) can shorten the previous
    // line after the break was placed, so the offender simply fits now.
    // That is a zero-shrink merge. Refusing it cascaded into
    // carry-overflows → LeaveRagged and left `、` / `」` at line start.
    val shrink = overflow.coerceAtLeast(0f)
    val allocations = if (shrink > 0f) distributePushInShrink(inLine, shrink) else emptyList()
    val offender = adjustedClusters[offenderIndex]
    val candidate = RepairCandidate(
        kind = "PushIn",
        reasonCode = reasonCode,
        offenderClusterIndex = offenderIndex,
        penalty = pushInPenalty,
        accepted = true,
        targetClusterIndex = offenderIndex,
        shrink = shrink,
        requiredShrink = shrink,
        availableCapacity = totalCapacity,
    )
    val repairedPrevious = expanded.copy(
        adjustedWidth = expanded.adjustedWidth - shrink,
        endReason = if (mergeEndIndex == curr.clusterRange.last) curr.endReason else prev.endReason,
        repair = RepairOption.PushIn(
            penalty = pushInPenalty,
            reason = if (shrink > 0f) {
                "$reasonCode:${offender.text}:pushed-in=$shrink/$totalCapacity"
            } else {
                "$reasonCode:${offender.text}:fits-no-shrink"
            },
            offenderClusterIndex = offenderIndex,
            allocations = allocations,
            totalShrink = shrink,
            totalAvailableCapacity = totalCapacity,
        ),
        // Preserve any repair history the receiving line already carries
        // (e.g. its own start was repaired earlier in the chain) — the
        // PushIn marker for the absorbed offender must not erase it.
        repairCandidates = prev.repairCandidates + candidate,
    )
    val repairedCurrent = if (mergeEndIndex == curr.clusterRange.last) {
        null
    } else {
        rebuildLine(
            (mergeEndIndex + 1)..curr.clusterRange.last,
            naturalClusters,
            adjustedClusters,
            endReason = curr.endReason,
        )
    }
    return PushInResult(repairedPrevious, repairedCurrent, candidate)
}

private fun mandatoryBreakTailEnd(
    curr: LineCandidate,
    mergeThroughClusterIndex: Int,
    adjustedClusters: List<Cluster>,
): Int {
    if (curr.endReason != LineEndReason.MandatoryBreak) return mergeThroughClusterIndex
    if (mergeThroughClusterIndex >= curr.clusterRange.last) return mergeThroughClusterIndex
    val tail = (mergeThroughClusterIndex + 1)..curr.clusterRange.last
    val tailIsZeroWidthBreak = tail.all { idx ->
        adjustedClusters[idx].displayText.isEmpty() && adjustedClusters[idx].advance == 0f
    }
    return if (tailIsZeroWidthBreak) curr.clusterRange.last else mergeThroughClusterIndex
}

/**
 * `LineAdjustmentPushIn` (ADR 0031) — the fill counterpart of 避头尾 PushIn.
 * After greedy/lookahead + 避头尾 repair, every non-last line is otherwise
 * STRETCHED to 行长; this pass instead pulls the next line's leading cluster UP
 * and COMPRESSES the line to fit, whenever压缩 is the smaller deviation from
 * 自然密排 (CLREQ §6.2.2「先挤进、后推出」+「先挤压、后拉伸」).
 *
 * Per boundary: leaving the next safe cluster/group stretches the line by
 * `deficit` (cost `Ws·deficit`); pulling it in compresses by
 * `overflow = groupAdvance − deficit` (cost `Wc·overflow`). Pull iff
 * `Wc·overflow < Ws·deficit`, i.e. `overflow < deficit × [compressBias]`
 * (= `Ws/Wc`), AND [tryPushIn] finds the room. `compressBias`大 → 先推入；
 * 小 → 先推出；`PushOutOnly` never calls this.
 *
 * Reuses [tryPushIn] so line-end 削半 / glue-pool / capacity reconcile exactly
 * as 避头尾 PushIn does. To avoid double-consuming glue it skips lines already
 * carrying a non-fill repair (避头尾 PushIn/Hang/CarryNext). A zero-shrink fill
 * PushIn may continue cascading: it has not consumed glue yet, and stopping
 * there leaves the repaired line visibly loose for no model reason.
 */
internal fun applyFillPushIn(
    lines: List<LineCandidate>,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    shrinkOpportunities: List<ShrinkOpportunity>,
    firstLineIndent: Float,
    compressBias: Float,
    forbiddenLineStartClusters: Set<Int>?,
    forbiddenLineEndClusters: Set<Int>,
    unbreakableRanges: List<IntRange>,
    pushInPenalty: Int,
    gapBoundaries: Set<Int> = emptySet(),
): List<LineCandidate> {
    if (lines.size < 2 || compressBias <= 0f) return lines
    val out = lines.toMutableList()
    var i = 0
    while (i < out.size - 1) {
        val prev = out[i]
        val curr = out[i + 1]
        val canExtendZeroShrinkFill = prev.repair.isContinuableZeroShrinkFillPushIn()
        if ((prev.repair != null && !canExtendZeroShrinkFill) ||
            prev.hangingClusterIndex != null ||
            prev.endReason != LineEndReason.AutoWrap
        ) {
            i += 1
            continue
        }
        val limit = lineLimit(maxWidth, firstLineIndent, prev.clusterRange.first)
        val deficit = limit - prev.adjustedWidth
        if (deficit <= 0f) {
            i += 1
            continue
        }
        val curr0 = curr.clusterRange.first
        val groupEnd = fillPushInGroupEnd(
            curr = curr,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
            forbiddenLineEndClusters = forbiddenLineEndClusters,
            unbreakableRanges = unbreakableRanges,
        )
        if (groupEnd == null) {
            i += 1
            continue
        }
        val addedAdvance = (curr0..groupEnd).sumOf { adjustedClusters[it].advance.toDouble() }.toFloat()
        val overflow = addedAdvance - deficit
        // 方向档位 (bias = Ws/Wc): PushOutFirst 下拉入依旧罕见;PushInFirst 下
        // 该闸恒通,由下面的均摊闸决定。
        if (overflow >= deficit * compressBias) {
            i += 1
            continue
        }
        // NeighborAmortizedAdjustment (ADR 0038), fill side: the pull may not
        // introduce a compression DENSITY worse than the stretch density it
        // cures (per-gap normalized; the fill is a cascade — curr refills from
        // ITS next line, so its deficit is not priced here). overflow ≤ 0 means
        // the cluster fits without compressing: always a win.
        if (overflow > 0f) {
            val prevGaps = lineGapCount(prev.clusterRange, gapBoundaries)
            val dStretchCured = if (prevGaps == 0) 0f else deficit / prevGaps
            val dCompressionIntroduced =
                overflow / maxOf(1, lineGapCount(prev.clusterRange.first..groupEnd, gapBoundaries))
            if (dCompressionIntroduced > dStretchCured) {
                i += 1
                continue
            }
        }
        val result = tryPushIn(
            prev = prev,
            curr = curr,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = limit,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            mergeThroughClusterIndex = groupEnd,
            reasonCode = "LineAdjustmentPushIn",
        )
        if (result.candidate.accepted) {
            out[i] = result.previous
            if (result.current == null) out.removeAt(i + 1) else out[i + 1] = result.current
            if (result.previous.repair.isContinuableZeroShrinkFillPushIn() && result.current != null) {
                continue
            }
        }
        i += 1
    }
    return out
}

private fun RepairOption?.isContinuableZeroShrinkFillPushIn(): Boolean =
    this is RepairOption.PushIn &&
        totalShrink <= 0.001f &&
        reason.startsWith("LineAdjustmentPushIn:")

private fun fillPushInGroupEnd(
    curr: LineCandidate,
    forbiddenLineStartClusters: Set<Int>?,
    forbiddenLineEndClusters: Set<Int>,
    unbreakableRanges: List<IntRange>,
): Int? {
    var groupEnd = curr.clusterRange.first
    while (groupEnd <= curr.clusterRange.last) {
        val containing = unbreakableRanges.firstOrNull { groupEnd in it && it.last > groupEnd }
        if (containing != null) {
            groupEnd = containing.last
            if (groupEnd > curr.clusterRange.last) return null
        }
        if (groupEnd in forbiddenLineEndClusters) {
            groupEnd += 1
            continue
        }
        val nextHead = groupEnd + 1
        if (nextHead <= curr.clusterRange.last && forbiddenLineStartClusters?.contains(nextHead) == true) {
            groupEnd = nextHead
            continue
        }
        return groupEnd
    }
    return null
}

/** Gated [applyFillPushIn] over a [LineSolution] — no-op when not [enabled]. */
internal fun LineSolution.withFillPushIn(
    enabled: Boolean,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    shrinkOpportunities: List<ShrinkOpportunity>,
    firstLineIndent: Float,
    compressBias: Float,
    forbiddenLineStartClusters: Set<Int>?,
    forbiddenLineEndClusters: Set<Int>,
    unbreakableRanges: List<IntRange>,
    pushInPenalty: Int,
    gapBoundaries: Set<Int> = emptySet(),
): LineSolution =
    if (!enabled) {
        this
    } else {
        LineSolution(
            lines = applyFillPushIn(
                lines, naturalClusters, adjustedClusters, maxWidth,
                shrinkOpportunities, firstLineIndent, compressBias,
                forbiddenLineStartClusters, forbiddenLineEndClusters, unbreakableRanges, pushInPenalty,
                gapBoundaries,
            ),
            totalBadness = totalBadness,
        )
    }

/**
 * Distribute [totalShrink] across [opportunities] in STRICT TIER ORDER
 * (CLREQ 挤压处理优先顺序): tier k is exhausted before tier k+1 is touched.
 * Within a tier, shrink is shared proportionally to capacity (equal caps →
 * equal amounts, the CLREQ「同时、同等量」rule); rounding remainder lands on
 * the tier's last entry. Allocations carry the consumption channel so the
 * engine knows whether to consume glue (one- or two-sided) or raw advance.
 */
private fun distributePushInShrink(
    opportunities: List<ShrinkOpportunity>,
    totalShrink: Float,
): List<PushInAllocation> {
    if (opportunities.isEmpty() || totalShrink <= 0f) return emptyList()

    val allocations = mutableListOf<PushInAllocation>()
    var remaining = totalShrink
    val byTier = opportunities.groupBy { it.tier }
    for (tier in byTier.keys.sorted()) {
        val tierOpps = byTier.getValue(tier)
        if (remaining <= 0f) break
        val tierCapacity = tierOpps.sumOf { it.capacity.toDouble() }.toFloat()
        if (tierCapacity <= 0f) continue
        val tierShrink = remaining.coerceAtMost(tierCapacity)
        var tierRemaining = tierShrink
        val ordered = tierOpps.sortedBy { it.clusterIndex }
        ordered.forEachIndexed { i, opp ->
            val isLast = (i == ordered.lastIndex)
            val share = if (isLast) {
                tierRemaining.coerceAtMost(opp.capacity)
            } else {
                (tierShrink * opp.capacity / tierCapacity).coerceAtMost(opp.capacity)
            }
            if (share > 0f) {
                allocations += PushInAllocation(
                    clusterIndex = opp.clusterIndex,
                    shrink = share,
                    availableCapacity = opp.capacity,
                    channel = opp.channel,
                )
                tierRemaining -= share
            }
        }
        remaining -= (tierShrink - tierRemaining.coerceAtLeast(0f))
    }
    return allocations
}

// NeighborAmortizedAdjustment (ADR 0038): per-line SIGNED adjustment density —
// stretch +, compression −, in px per justification gap. The visible quantity a
// reader perceives is per-gap spacing change, so costs are priced on it, convex
// (d²: two half-adjusted lines beat one fully-adjusted line) plus a neighbor
// difference term ((dᵢ−dᵢ₋₁)²: no tight line pressed against a loose line).
// 末行与 MandatoryBreak 行 d=0(段末自然收束,不参与均摊)。
internal fun lineGapCount(range: IntRange, gapBoundaries: Set<Int>): Int {
    if (range.isEmptyClusterRange()) return 0
    var n = 0
    for (i in range.first until range.last) if (i in gapBoundaries) n += 1
    return n
}

internal fun lineAdjustmentDensity(
    line: LineCandidate,
    limit: Float,
    isLast: Boolean,
    gapBoundaries: Set<Int>,
): Float {
    if (isLast || line.endReason != LineEndReason.AutoWrap) return 0f
    // Stretch density (justify fill). Compression does not surface here: pushed-in
    // lines sit at ~limit and carry their repair penalty; the fill GATE prices the
    // compression side explicitly (−overflow/gaps) when deciding the pull.
    // A line with ZERO stretchable gaps has density 0 — its deficit is plain
    // raggedness (priced linearly), not visible spacing; max(1,…) here would
    // fabricate a huge density that poisons neighbors into matching it.
    val gaps = lineGapCount(line.clusterRange, gapBoundaries)
    if (gaps == 0) return 0f
    val delta = (limit - line.adjustedWidth).coerceAtLeast(0f)
    return delta / gaps
}

/** Convex fill term + neighbor-difference term, normalized back to px by [dRef]. */
internal fun amortizedAdjustmentCost(d: Float, prevD: Float, dRef: Float): Float {
    val ref = dRef.coerceAtLeast(1f)
    val diff = d - prevD
    return (d * d + diff * diff) / ref
}

internal fun rebuildLine(
    clusterRange: IntRange,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    endReason: LineEndReason = LineEndReason.AutoWrap,
    repair: RepairOption? = null,
    repairCandidates: List<RepairCandidate> = emptyList(),
): LineCandidate {
    require(!clusterRange.isEmptyClusterRange()) { "Use emptyLineCandidate for an empty line." }
    var natural = 0f
    var adjusted = 0f
    for (idx in clusterRange) {
        natural += naturalClusters[idx].advance
        adjusted += adjustedClusters[idx].advance
    }
    return LineCandidate(
        clusterRange = clusterRange,
        sourceRange = TextRange(
            adjustedClusters[clusterRange.first].range.start,
            adjustedClusters[clusterRange.last].range.end,
        ),
        naturalWidth = natural,
        adjustedWidth = adjusted,
        endReason = endReason,
        repair = repair,
        repairCandidates = repairCandidates,
    )
}

internal fun emptyLineCandidate(
    sourceOffset: Int,
    endReason: LineEndReason = LineEndReason.ParagraphEnd,
): LineCandidate =
    LineCandidate(
        clusterRange = EMPTY_CLUSTER_RANGE,
        sourceRange = TextRange(sourceOffset, sourceOffset),
        naturalWidth = 0f,
        adjustedWidth = 0f,
        endReason = endReason,
    )

internal fun IntRange.isEmptyClusterRange(): Boolean = first > last

private val EMPTY_CLUSTER_RANGE: IntRange = 1..0

internal fun findGreedyEnd(
    adjustedClusters: List<Cluster>,
    start: Int,
    maxWidth: Float,
    endExclusive: Int = adjustedClusters.size,
): Int {
    var accum = 0f
    var i = start
    while (i < endExclusive) {
        val next = accum + adjustedClusters[i].advance
        if (next > maxWidth && i > start) return i
        accum = next
        i += 1
    }
    return endExclusive
}
