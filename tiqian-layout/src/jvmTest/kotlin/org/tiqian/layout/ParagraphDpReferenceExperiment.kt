package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineEndReason
import org.tiqian.core.TiqianTextContent
import org.tiqian.test.EarlyLayoutFixtures
import kotlin.math.sqrt
import kotlin.test.Test

/**
 * Measurement experiment (NOT production): how much line-quality does the
 * committed `LookaheadLineBreaker` (window=2, horizon=2, local commit) leave on
 * the table versus a paragraph-global optimum of the SAME ADR 0038 cost?
 *
 * A recording wrapper captures the exact `breakLines` inputs the engine feeds
 * the production breaker; a reference DP then optimizes the identical cost
 * (convex density + neighbor difference + orphan + gapless raggedness) over the
 * same candidate universe, restricted to be CONSERVATIVE for the DP:
 *  - no synthetic-hyphen ends (the lookahead may use them),
 *  - no push-in/hang repairs (kinsoku is enforced as hard candidate filters),
 * so the reported improvement is a LOWER BOUND on what a production
 * `ParagraphDynamicProgramming` strategy could recover. Repair penalties are
 * excluded from BOTH sides' scores (structure-only comparison).
 */
class ParagraphDpReferenceExperiment {

    private class RecordedInputs(
        val naturalClusters: List<Cluster>,
        val adjustedClusters: List<Cluster>,
        val maxWidth: Float,
        val unbreakableRanges: List<IntRange>,
        val firstLineIndent: Float,
        val forbiddenLineStartClusters: Set<Int>?,
        val forbiddenLineEndClusters: Set<Int>,
        val hyphenBreakClusters: Set<Int>,
        val cjkInterCharBoundaries: Set<Int>,
        val maxCjkStretchPerGap: Float,
        val sinoWesternBoundaries: Set<Int>,
        val hardBreakAfterClusters: Set<Int>,
        val nonRenderingControlClusters: Set<Int>,
    )

    private class RecordingLineBreaker(private val inner: LineBreaker) : LineBreaker {
        override val strategyName: String get() = inner.strategyName
        var recorded: RecordedInputs? = null
        var solution: LineSolution? = null

        override fun breakLines(
            naturalClusters: List<Cluster>,
            adjustedClusters: List<Cluster>,
            maxWidth: Float,
            shrinkOpportunities: List<ShrinkOpportunity>,
            unbreakableRanges: List<IntRange>,
            firstLineIndent: Float,
            hangableClusters: Set<Int>,
            extendableHangRanges: List<IntRange>,
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
            nonRenderingControlClusters: Set<Int>,
        ): LineSolution {
            val result = inner.breakLines(
                naturalClusters, adjustedClusters, maxWidth, shrinkOpportunities,
                unbreakableRanges, firstLineIndent, hangableClusters, extendableHangRanges,
                forbiddenLineStartClusters, forbiddenLineEndClusters, hyphenBreakClusters,
                cjkInterCharBoundaries, maxCjkStretchPerGap, sinoWesternBoundaries,
                sinoWesternStretchCap, lineAdjustmentPushIn, lineAdjustmentCompressBias,
                hardBreakAfterClusters, nonRenderingControlClusters,
            )
            recorded = RecordedInputs(
                naturalClusters, adjustedClusters, maxWidth, unbreakableRanges,
                firstLineIndent, forbiddenLineStartClusters, forbiddenLineEndClusters,
                hyphenBreakClusters, cjkInterCharBoundaries, maxCjkStretchPerGap,
                sinoWesternBoundaries, hardBreakAfterClusters, nonRenderingControlClusters,
            )
            solution = result
            return result
        }
    }

    /** Structure-only ADR 0038 cost of a committed partition (no repair penalties). */
    private fun partitionCost(lines: List<LineCandidate>, inputs: RecordedInputs): Double {
        val gapBoundaries = inputs.cjkInterCharBoundaries + inputs.sinoWesternBoundaries
        val dRef = inputs.maxCjkStretchPerGap
        var prevD = 0f
        var total = 0.0
        for ((idx, line) in lines.withIndex()) {
            if (line.clusterRange.isEmptyClusterRange()) continue
            val isLast = idx == lines.lastIndex
            val limit = lineLimit(inputs.maxWidth, inputs.firstLineIndent, line.clusterRange.first)
            val ragged = if (isLast) 0f else (limit - line.adjustedWidth).coerceAtLeast(0f)
            val inMeasure = line.inMeasureClusterRange
            val gaps = lineGapCount(inMeasure, gapBoundaries)
            val residual = if (gaps == 0) ragged else 0f
            val d = lineAdjustmentDensity(line, limit, isLast, gapBoundaries)
            val orphan = if (!isLast && !inMeasure.isEmptyClusterRange() && inMeasure.first == inMeasure.last) 20f else 0f
            total += (residual * RAGGEDNESS_WEIGHT + orphan +
                amortizedAdjustmentCost(d, prevD, dRef) * RAGGEDNESS_WEIGHT).toDouble()
            prevD = d
        }
        return total
    }

    private fun densities(lines: List<LineCandidate>, inputs: RecordedInputs): List<Float> {
        val gapBoundaries = inputs.cjkInterCharBoundaries + inputs.sinoWesternBoundaries
        return lines.filter { !it.clusterRange.isEmptyClusterRange() }.mapIndexed { idx, line ->
            val isLast = idx == lines.lastIndex
            val limit = lineLimit(inputs.maxWidth, inputs.firstLineIndent, line.clusterRange.first)
            lineAdjustmentDensity(line, limit, isLast, gapBoundaries)
        }
    }

    /** Paragraph-global DP over the same cost. Edge = one line; state = (start, end). */
    private fun dpPartition(inputs: RecordedInputs): List<LineCandidate>? {
        val n = inputs.adjustedClusters.size
        if (n == 0) return null
        val gapBoundaries = inputs.cjkInterCharBoundaries + inputs.sinoWesternBoundaries
        val dRef = inputs.maxCjkStretchPerGap
        val sortedHard = inputs.hardBreakAfterClusters.sorted()

        val allLines = mutableListOf<LineCandidate>()
        var segmentStart = 0
        var hardIdx = 0
        while (segmentStart < n) {
            while (hardIdx < sortedHard.size && sortedHard[hardIdx] < segmentStart) hardIdx += 1
            val mandatoryEnd = if (hardIdx < sortedHard.size) sortedHard[hardIdx] else null
            val segEndExcl = mandatoryEnd?.plus(1) ?: n
            val segLines = dpSegment(inputs, segmentStart, segEndExcl, gapBoundaries, dRef, mandatoryEnd != null)
                ?: return null
            allLines += segLines
            segmentStart = segEndExcl
        }
        return allLines
    }

    private fun candidateEnds(inputs: RecordedInputs, start: Int, segEndExcl: Int): List<Int> {
        val limit = lineLimit(inputs.maxWidth, inputs.firstLineIndent, start)
        val greedyEnd = findGreedyEnd(
            inputs.adjustedClusters, start, limit,
            endExclusive = segEndExcl,
            nonRenderingControlClusters = inputs.nonRenderingControlClusters,
        )
        if (greedyEnd >= segEndExcl) return listOf(segEndExcl)
        return ((greedyEnd - CANDIDATE_WINDOW)..greedyEnd)
            .filter { it in (start + 1)..segEndExcl }
            .filter { e -> inputs.unbreakableRanges.none { e > it.first && e <= it.last } }
            .filter { e -> e == segEndExcl || e !in inputs.hyphenBreakClusters }
            .filter { e ->
                e == segEndExcl ||
                    (inputs.forbiddenLineStartClusters?.contains(e) != true && (e - 1) !in inputs.forbiddenLineEndClusters)
            }
            .filter { e ->
                (start until e).any { it !in inputs.nonRenderingControlClusters } || e == segEndExcl
            }
            .ifEmpty { listOf(greedyEnd) }
    }

    private fun dpSegment(
        inputs: RecordedInputs,
        segStart: Int,
        segEndExcl: Int,
        gapBoundaries: Set<Int>,
        dRef: Float,
        endsWithMandatory: Boolean,
    ): List<LineCandidate>? {
        data class Edge(val start: Int, val end: Int, val line: LineCandidate, val d: Float)

        fun buildLine(start: Int, end: Int): LineCandidate {
            val isParagraphEnd = end == inputs.adjustedClusters.size
            val reason = when {
                endsWithMandatory && end == segEndExcl -> LineEndReason.MandatoryBreak
                isParagraphEnd -> LineEndReason.ParagraphEnd
                else -> LineEndReason.AutoWrap
            }
            return rebuildLine(
                clusterRange = start..(end - 1),
                naturalClusters = inputs.naturalClusters,
                adjustedClusters = inputs.adjustedClusters,
                endReason = reason,
            )
        }

        fun edgeCost(line: LineCandidate, isLastOfParagraph: Boolean, prevD: Float): Pair<Float, Float> {
            val limit = lineLimit(inputs.maxWidth, inputs.firstLineIndent, line.clusterRange.first)
            val ragged = if (isLastOfParagraph) 0f else (limit - line.adjustedWidth).coerceAtLeast(0f)
            val inMeasure = line.inMeasureClusterRange
            val gaps = lineGapCount(inMeasure, gapBoundaries)
            val residual = if (gaps == 0) ragged else 0f
            val d = lineAdjustmentDensity(line, limit, isLastOfParagraph, gapBoundaries)
            val orphan = if (!isLastOfParagraph && inMeasure.first == inMeasure.last) 20f else 0f
            val cost = residual * RAGGEDNESS_WEIGHT + orphan +
                amortizedAdjustmentCost(d, prevD, dRef) * RAGGEDNESS_WEIGHT
            return cost to d
        }

        // dp keyed by incoming edge; value = best cost of covering [segStart, edge.end).
        val bestByEdge = HashMap<Long, Float>()
        val parentEdge = HashMap<Long, Long>()
        val edgesByEnd = HashMap<Int, MutableList<Edge>>()
        fun key(s: Int, e: Int): Long = s.toLong() shl 32 or e.toLong()

        // Every edge goes forward, so increasing start order is a topological
        // order: all incoming edges of `start` exist before its expansion.
        for (start in segStart until segEndExcl) {
            if (start != segStart && edgesByEnd[start].isNullOrEmpty()) continue
            for (e in candidateEnds(inputs, start, segEndExcl)) {
                val line = buildLine(start, e)
                val isLastOfParagraph = e == inputs.adjustedClusters.size ||
                    (e == segEndExcl && !endsWithMandatory)
                val incoming = if (start == segStart) {
                    listOf<Edge?>(null)
                } else {
                    edgesByEnd[start].orEmpty()
                }
                if (incoming.isEmpty()) continue
                var bestCost = Float.POSITIVE_INFINITY
                var bestParent = -1L
                for (prev in incoming) {
                    val prevCost = if (prev == null) 0f else bestByEdge.getValue(key(prev.start, prev.end))
                    val prevD = prev?.d ?: 0f
                    val (cost, _) = edgeCost(line, isLastOfParagraph, prevD)
                    val totalCost = prevCost + cost
                    if (totalCost < bestCost) {
                        bestCost = totalCost
                        bestParent = if (prev == null) -1L else key(prev.start, prev.end)
                    }
                }
                val k = key(start, e)
                val existing = bestByEdge[k]
                if (existing == null || bestCost < existing) {
                    bestByEdge[k] = bestCost
                    if (bestParent != -1L) parentEdge[k] = bestParent
                    val (_, d) = edgeCost(line, isLastOfParagraph, 0f)
                    edgesByEnd.getOrPut(e) { mutableListOf() }
                        .removeAll { it.start == start }
                    edgesByEnd.getOrPut(e) { mutableListOf() } += Edge(start, e, line, d)
                }
            }
        }

        // Choose the cheapest edge that ends the segment, then walk parents.
        val terminal = edgesByEnd[segEndExcl].orEmpty()
            .minByOrNull { bestByEdge.getValue(key(it.start, it.end)) } ?: return null
        val orderedEdges = mutableListOf<Edge>()
        var cursor: Long? = key(terminal.start, terminal.end)
        val edgeByKey = edgesByEnd.values.flatten().associateBy { key(it.start, it.end) }
        while (cursor != null) {
            val edge = edgeByKey[cursor] ?: break
            orderedEdges += edge
            cursor = parentEdge[cursor]
        }
        orderedEdges.reverse()
        if (orderedEdges.firstOrNull()?.start != segStart) return null
        return orderedEdges.map { it.line }
    }

    private class Tally {
        var dpWins = 0
        var ties = 0
        var lookaheadWins = 0
        var totalLookCost = 0.0
        var totalDpCost = 0.0
        val rows = mutableListOf<String>()
        val artifactRows = mutableListOf<String>()
    }

    private fun compareOne(id: String, recorder: RecordingLineBreaker, tally: Tally) {
        val inputs = recorder.recorded ?: return
        val lookLines = recorder.solution?.lines?.filter { !it.clusterRange.isEmptyClusterRange() } ?: return
        if (lookLines.size < 3) return
        val dpLines = dpPartition(inputs) ?: return

        val lookCost = partitionCost(lookLines, inputs)
        val dpCost = partitionCost(dpLines, inputs)
        val lookD = densities(lookLines, inputs)
        val dpD = densities(dpLines, inputs)
        val delta = lookCost - dpCost
        val rel = if (lookCost > 1e-6) delta / lookCost * 100 else 0.0
        val usedHyphen = lookLines.any {
            it.endReason == LineEndReason.AutoWrap && it.clusterRange.last + 1 in inputs.hyphenBreakClusters
        }
        val usedRepair = lookLines.any { it.repair != null || it.hangingClusterIndices.isNotEmpty() }
        val flags = (if (usedHyphen) "H" else "") + (if (usedRepair) "R" else "")
        val row = "%-34s %-2s lines=%2d/%2d cost look=%8.2f dp=%8.2f Δ=%6.1f%% maxD %5.2f→%5.2f σ %5.2f→%5.2f".format(
            id.take(34), flags, lookLines.size, dpLines.size, lookCost, dpCost, rel,
            lookD.maxOrNull() ?: 0f, dpD.maxOrNull() ?: 0f, stddev(lookD), stddev(dpD),
        )
        // The reference DP deliberately has no synthetic-hyphen candidates; when
        // the production solution hyphenates, the universes differ and the row
        // is an artifact of the restriction, not a real comparison.
        if (usedHyphen && dpCost > lookCost) {
            tally.artifactRows += row
            return
        }
        tally.rows += row
        tally.totalLookCost += lookCost
        tally.totalDpCost += dpCost
        when {
            delta > lookCost * 0.01 + 1e-3 -> tally.dpWins += 1
            delta < -(lookCost * 0.01 + 1e-3) -> tally.lookaheadWins += 1
            else -> tally.ties += 1
        }
    }

    private fun layoutWithRecorder(
        text: String,
        maxWidth: Float,
        useEnglishHyphenation: Boolean = false,
        pinBasicNoHang: Boolean = false,
        lineHeight: Float? = null,
        firstLineIndentEm: Float? = 2f,
        decorations: List<org.tiqian.core.DecorationSpan> = emptyList(),
        breaker: LineBreaker = LookaheadLineBreaker(),
    ): RecordingLineBreaker {
        val recorder = RecordingLineBreaker(breaker)
        val hyphenator = if (useEnglishHyphenation) {
            org.tiqian.linebreak.EnglishHyphenation.enUs
        } else {
            org.tiqian.linebreak.NoHyphenator
        }
        val engine = if (pinBasicNoHang) {
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = recorder,
                hyphenator = hyphenator,
                clreqProfileResolver = {
                    org.tiqian.clreq.ClreqProfile.MainlandHorizontal.copy(
                        kinsokuMode = org.tiqian.clreq.KinsokuMode.Fixed(
                            org.tiqian.clreq.KinsokuLevel.Basic,
                        ),
                    )
                },
            )
        } else {
            ExplainableStubParagraphLayoutEngine(lineBreaker = recorder, hyphenator = hyphenator)
        }
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = maxWidth),
                paragraphStyle = org.tiqian.core.ParagraphStyle(
                    lineHeight = lineHeight,
                    firstLineIndent = firstLineIndentEm?.let { org.tiqian.core.Ic(it) },
                ),
                decorations = decorations,
            ),
        )
        return recorder
    }

    @Test
    fun compareLookaheadAgainstParagraphDp() {
        val tally = Tally()

        for (fixture in EarlyLayoutFixtures.all) {
            val recorder = layoutWithRecorder(
                text = fixture.text,
                maxWidth = fixture.constraints.maxWidth,
                useEnglishHyphenation = fixture.useEnglishHyphenation,
                pinBasicNoHang = fixture.pinBasicNoHang,
                lineHeight = fixture.lineHeight,
                firstLineIndentEm = fixture.firstLineIndentEm,
                decorations = fixture.decorations,
            )
            compareOne(fixture.id, recorder, tally)
        }

        // 移动端窄版心 sweep:真实中文长段在 15–25 字/行下的表现——这是局部
        // 搜索次优最可能被放大的区域(每行 gap 少、单行密度方差大)。
        for (text in NARROW_SWEEP_TEXTS.withIndex()) {
            for (width in NARROW_SWEEP_WIDTHS) {
                val recorder = layoutWithRecorder(text = text.value, maxWidth = width)
                compareOne("narrow-${text.index + 1}-w${width.toInt()}", recorder, tally)
            }
        }

        println("== ParagraphDpReferenceExperiment (conservative DP lower bound) ==")
        tally.rows.forEach(::println)
        if (tally.artifactRows.isNotEmpty()) {
            println("-- excluded (hyphenation outside DP universe) --")
            tally.artifactRows.forEach(::println)
        }
        println(
            "comparable=%d | DP better: %d, tie: %d, lookahead better: %d | total cost %.1f → %.1f (%+.1f%%)".format(
                tally.rows.size, tally.dpWins, tally.ties, tally.lookaheadWins,
                tally.totalLookCost, tally.totalDpCost,
                if (tally.totalLookCost > 0) {
                    (tally.totalDpCost - tally.totalLookCost) / tally.totalLookCost * 100
                } else {
                    0.0
                },
            ),
        )
    }

    @Test
    fun productionDpBeatsLookaheadOnCommittedOutput() {
        data class Case(val id: String, val text: String, val width: Float, val useHyphenation: Boolean, val pinBasicNoHang: Boolean, val lineHeight: Float?, val indentEm: Float?, val decorations: List<org.tiqian.core.DecorationSpan>)

        val cases = EarlyLayoutFixtures.all.map {
            Case(it.id, it.text, it.constraints.maxWidth, it.useEnglishHyphenation, it.pinBasicNoHang, it.lineHeight, it.firstLineIndentEm, it.decorations)
        } + NARROW_SWEEP_TEXTS.withIndex().flatMap { (i, text) ->
            NARROW_SWEEP_WIDTHS.map { w -> Case("narrow-${i + 1}-w${w.toInt()}", text, w, false, false, null, 2f, emptyList()) }
        }

        var better = 0
        var tie = 0
        var worse = 0
        var totalLook = 0.0
        var totalDp = 0.0
        var worstLookMax = 0f
        var worstDpMax = 0f
        val regressions = mutableListOf<String>()
        val catastrophes = mutableListOf<String>()
        println("== production ParagraphDpLineBreaker vs LookaheadLineBreaker (committed output) ==")
        for (case in cases) {
            val look = layoutWithRecorder(case.text, case.width, case.useHyphenation, case.pinBasicNoHang, case.lineHeight, case.indentEm, case.decorations)
            val dp = layoutWithRecorder(case.text, case.width, case.useHyphenation, case.pinBasicNoHang, case.lineHeight, case.indentEm, case.decorations, breaker = ParagraphDpLineBreaker())
            val inputs = look.recorded ?: continue
            val lookLines = look.solution?.lines?.filter { !it.clusterRange.isEmptyClusterRange() } ?: continue
            val dpLines = dp.solution?.lines?.filter { !it.clusterRange.isEmptyClusterRange() } ?: continue

            // Committed lines must partition the cluster list in order.
            var expected = 0
            for (line in dpLines) {
                kotlin.test.assertEquals(expected, line.clusterRange.first, "${case.id}: dp lines must tile clusters")
                expected = line.clusterRange.last + 1
            }
            kotlin.test.assertEquals(inputs.adjustedClusters.size, expected, "${case.id}: dp lines must cover the paragraph")

            if (lookLines.size < 3) continue
            val lookCost = partitionCost(lookLines, inputs)
            val dpCost = partitionCost(dpLines, inputs)
            totalLook += lookCost
            totalDp += dpCost
            val lookMax = densities(lookLines, inputs).maxOrNull() ?: 0f
            val dpMax = densities(dpLines, inputs).maxOrNull() ?: 0f
            worstLookMax = maxOf(worstLookMax, lookMax)
            worstDpMax = maxOf(worstDpMax, dpMax)
            // CatastropheGuard (ADR 0041 修订): the 2026-07-18 目检 falsified
            // TOTAL cost as a perception proxy, but the convex term's original
            // claim survived — no strategy may render a line meaningfully more
            // stretched than the other's worst on the same input. Tolerance
            // 1.5px/gap covers the documented hang-edge gap: lookahead can
            // reach 0 via 行尾悬挂, which the DP edge model does not carry yet.
            // Tighten toward 0.5 when hang edges land.
            if (dpMax > lookMax + 1.5f) {
                catastrophes += "%-30s worst-line density look=%.2f dp=%.2f".format(case.id, lookMax, dpMax)
            }
            val rel = if (lookCost > 1e-6) (lookCost - dpCost) / lookCost * 100 else 0.0
            when {
                lookCost - dpCost > lookCost * 0.01 + 1e-3 -> better += 1
                dpCost - lookCost > lookCost * 0.01 + 1e-3 -> {
                    worse += 1
                    regressions += "%-30s look=%8.2f dp=%8.2f (%+.1f%%)".format(case.id, lookCost, dpCost, -rel)
                }
                else -> tie += 1
            }
            println(
                "%-30s lines=%2d/%2d cost look=%8.2f dp=%8.2f Δ=%6.1f%% maxD %5.2f→%5.2f".format(
                    case.id.take(30), lookLines.size, dpLines.size, lookCost, dpCost, rel, lookMax, dpMax,
                ),
            )
        }
        println("summary: better=%d tie=%d worse=%d | total %.1f → %.1f (%+.1f%%) | worst maxD %.2f → %.2f".format(
            better, tie, worse, totalLook, totalDp,
            if (totalLook > 0) (totalDp - totalLook) / totalLook * 100 else 0.0,
            worstLookMax, worstDpMax,
        ))
        regressions.forEach { println("INFO cost-regression $it") }
        kotlin.test.assertTrue(
            catastrophes.isEmpty(),
            "DP rendered a meaningfully worse line than lookahead:\n" + catastrophes.joinToString("\n"),
        )
    }

    @Test
    fun benchmarkDpAgainstLookahead() {
        val longText = NARROW_SWEEP_TEXTS.joinToString("") + NARROW_SWEEP_TEXTS.joinToString("")
        data class Bench(val id: String, val text: String, val width: Float)
        val cases = listOf(
            Bench("real-320 (~200字)", NARROW_SWEEP_TEXTS[0], 320f),
            Bench("narrow-240 (~200字)", NARROW_SWEEP_TEXTS[2], 240f),
            Bench("long-320 (~1500字)", longText, 320f),
            Bench("long-600 (~1500字)", longText, 600f),
        )

        fun medianNanos(runs: Int, block: () -> Unit): Long {
            val samples = LongArray(runs)
            for (i in 0 until runs) {
                val t0 = System.nanoTime()
                block()
                samples[i] = System.nanoTime() - t0
            }
            samples.sort()
            return samples[runs / 2]
        }

        println("== ParagraphDp vs Lookahead: wall time (median) ==")
        for (case in cases) {
            // End-to-end engine.layout, fresh engine per breaker (shared caches warm inside).
            fun engineFor(breaker: LineBreaker) = ExplainableStubParagraphLayoutEngine(lineBreaker = breaker)
            val lookEngine = engineFor(LookaheadLineBreaker())
            val dpEngine = engineFor(ParagraphDpLineBreaker())
            val input = org.tiqian.core.LayoutInput(
                content = TiqianTextContent(case.text),
                constraints = LayoutConstraints(maxWidth = case.width),
                paragraphStyle = org.tiqian.core.ParagraphStyle(firstLineIndent = org.tiqian.core.Ic(2f)),
            )
            repeat(30) { lookEngine.layout(input); dpEngine.layout(input) } // warmup/JIT
            val lookTotal = medianNanos(60) { lookEngine.layout(input) }
            val dpTotal = medianNanos(60) { dpEngine.layout(input) }

            // Breaker-only on identical recorded inputs.
            val recorder = RecordingLineBreaker(LookaheadLineBreaker())
            ExplainableStubParagraphLayoutEngine(lineBreaker = recorder).layout(input)
            val inputs = recorder.recorded!!
            val lookBreaker = LookaheadLineBreaker()
            val dpBreaker = ParagraphDpLineBreaker()
            fun runBreaker(b: LineBreaker) {
                b.breakLines(
                    inputs.naturalClusters, inputs.adjustedClusters, inputs.maxWidth,
                    emptyList(), inputs.unbreakableRanges, inputs.firstLineIndent,
                    emptySet(), emptyList(), inputs.forbiddenLineStartClusters,
                    inputs.forbiddenLineEndClusters, inputs.hyphenBreakClusters,
                    inputs.cjkInterCharBoundaries, inputs.maxCjkStretchPerGap,
                    inputs.sinoWesternBoundaries, 0f, true, 1.2f,
                    inputs.hardBreakAfterClusters, inputs.nonRenderingControlClusters,
                )
            }
            repeat(60) { runBreaker(lookBreaker); runBreaker(dpBreaker) }
            val lookOnly = medianNanos(120) { runBreaker(lookBreaker) }
            val dpOnly = medianNanos(120) { runBreaker(dpBreaker) }

            println(
                "%-20s clusters=%4d | layout() look=%6.2fms dp=%6.2fms (%.2fx) | breaker-only look=%6.0fµs dp=%6.0fµs (%.2fx)".format(
                    case.id, inputs.adjustedClusters.size,
                    lookTotal / 1e6, dpTotal / 1e6, dpTotal.toDouble() / lookTotal,
                    lookOnly / 1e3, dpOnly / 1e3, dpOnly.toDouble() / lookOnly,
                ),
            )
        }
    }

    private fun stddev(values: List<Float>): Float {
        if (values.size < 2) return 0f
        val mean = values.sum() / values.size
        return sqrt(values.sumOf { ((it - mean) * (it - mean)).toDouble() } / values.size).toFloat()
    }

    private companion object {
        const val RAGGEDNESS_WEIGHT = 0.5f
        const val CANDIDATE_WINDOW = 12

        val NARROW_SWEEP_WIDTHS = listOf(240f, 280f, 320f, 400f)

        /** Real-shaped Chinese prose (self-written), punctuation-rich, ~200–300 chars. */
        val NARROW_SWEEP_TEXTS = listOf(
            "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
                "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
                "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
                "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
                "，但也不算太离谱。",
            "活字印刷并没有立刻取代抄写。相反，在古腾堡之后的半个世纪里，抄写坊的生意甚至更好了：印刷" +
                "本压低了书价，识字的人多了，想要精装手抄本的人也跟着多了。真正的转折发生在版式上——页码、" +
                "目录、索引、标点，这些今天看来理所当然的东西，都是印刷时代为了「检索」而发明的。书从此不再" +
                "只是被从头读到尾的东西，它变成了可以随手翻开的工具。",
            "汉字排版的难处不在字多，而在字与字之间没有空格。西文靠词间空白断行，中文只能在字间下刀，" +
                "于是「避头尾」成了第一条铁律：句号不能落在行首，引号不能孤悬行尾。老师傅的手艺，是在拆行时" +
                "顺手把标点挤一挤、把字距匀一匀，让每一行看起来都一样满。这门手艺后来被写进了规范，又被写进" +
                "了程序——名字换成了 justify，道理还是那个道理。",
        )
    }
}
