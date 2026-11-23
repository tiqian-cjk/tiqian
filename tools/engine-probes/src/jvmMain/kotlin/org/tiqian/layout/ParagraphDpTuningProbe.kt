package org.tiqian.layout

import org.tiqian.boring.runtime.SortedMapTable
import org.tiqian.boring.runtime.SortedSetTable
import org.tiqian.core.isEmptyClusterRange
import org.tiqian.core.Cluster
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineEndReason
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.shaping.jvm.AwtTextShaper
import kotlin.test.Test

/**
 * Diagnostic probe (NOT production, NOT an assertion): read the committed
 * output of lookahead vs `paragraph-dp` through the SAME lens the ADR 0041 v3
 * cost model uses — per-gap-class stretch density, visible-stretch runs,
 * compression — plus the paragraph-level facts the model currently does NOT
 * price (line count, 末行 cluster count).
 *
 * Purpose: locate where the v3 model is still mis-tuned against Chinese body
 * typography before any knob is touched. Everything printed here is measured
 * on real AWT advances through the production engine.
 *
 * Run: `TIQIAN_RUN_EXPERIMENTS=1 ./gradlew :layout:jvmTest --tests '*ParagraphDpTuningProbe*'`
 * (output in the test's stdout / build/reports).
 */
class ParagraphDpTuningProbe {

    private class Recorded(
        val naturalClusters: List<Cluster>,
        val adjustedClusters: List<Cluster>,
        val maxWidth: Float,
        val firstLineIndent: Float,
        val cjkInterCharBoundaries: SortedSetTable<Int>,
        val sinoWesternBoundaries: SortedSetTable<Int>,
        val maxCjkStretchPerGap: Float,
        val sinoWesternStretchCap: Float,
    )

    private class Recorder(private val inner: LineBreaker) : LineBreaker {
        override fun get_strategyName(): String = inner.strategyName
        var recorded: Recorded? = null
        var solution: LineSolution? = null

        override fun breakLines(
            naturalClusters: MutableList<Cluster>,
            adjustedClusters: MutableList<Cluster>,
            maxWidth: Float,
            shrinkOpportunities: MutableList<ShrinkOpportunity>?,
            unbreakableRanges: UnbreakableRanges?,
            firstLineIndent: Float,
            hangableClusters: SortedSetTable<Int>?,
            extendableHangRanges: MutableList<org.tiqian.core.IntRange>?,
            forbiddenLineStartClusters: SortedSetTable<Int>?,
            forbiddenLineEndClusters: SortedSetTable<Int>?,
            hyphenBreakClusters: SortedSetTable<Int>?,
            cjkInterCharBoundaries: SortedSetTable<Int>?,
            maxCjkStretchPerGap: Float?,
            sinoWesternBoundaries: SortedSetTable<Int>?,
            sinoWesternStretchCap: Float,
            lineAdjustmentPushIn: Boolean,
            lineAdjustmentCompressBias: Float,
            hardBreakAfterClusters: SortedSetTable<Int>?,
            nonRenderingControlClusters: SortedSetTable<Int>?,
            progressiveBreakOpportunities: SortedMapTable<Int, ProgressiveBreakOpportunity>?,
        ): LineSolution {
            val ranges = unbreakableRanges ?: UnbreakableRanges.Empty
            val maxStretch = maxCjkStretchPerGap ?: Float.POSITIVE_INFINITY
            val cjk = cjkInterCharBoundaries ?: LineBreakerLines.emptyIntSet()
            val sino = sinoWesternBoundaries ?: LineBreakerLines.emptyIntSet()
            val result = inner.breakLines(
                naturalClusters, adjustedClusters, maxWidth, shrinkOpportunities,
                ranges, firstLineIndent, hangableClusters, extendableHangRanges,
                forbiddenLineStartClusters, forbiddenLineEndClusters, hyphenBreakClusters,
                cjk, maxStretch, sino,
                sinoWesternStretchCap, lineAdjustmentPushIn, lineAdjustmentCompressBias,
                hardBreakAfterClusters, nonRenderingControlClusters, progressiveBreakOpportunities,
            )
            recorded = Recorded(
                naturalClusters, adjustedClusters, maxWidth, firstLineIndent,
                cjk, sino,
                maxStretch, sinoWesternStretchCap,
            )
            solution = result
            return result
        }
    }

    /** What the v3 model believes one committed line looks like after justify. */
    private class LineProfile(
        val clusters: Int,
        val dSino: Float,
        val dCjk: Float,
        val residual: Float,
        val compression: Float,
        val sinoAtCap: Boolean,
        val pushIn: Boolean = false,
        val hang: Boolean = false,
    ) {
        val visibleStretch: Boolean get() = maxOf(dSino, dCjk) > 0.5f
    }

    private fun profile(lines: List<LineCandidate>, r: Recorded): List<LineProfile> {
        val out = mutableListOf<LineProfile>()
        val body = lines.filter { !it.clusterRange.isEmptyClusterRange() }
        for ((idx, line) in body.withIndex()) {
            val isLast = idx == body.lastIndex || line.endReason != LineEndReason.AutoWrap
            val limit = lineLimit(r.maxWidth, r.firstLineIndent, line.clusterRange.first)
            val inMeasure = line.inMeasureClusterRange
            val sinoGaps = lineGapCount(inMeasure, r.sinoWesternBoundaries)
            val cjkGaps = lineGapCount(inMeasure, r.cjkInterCharBoundaries)
            val pushIn = line.repair as? RepairOption.PushIn
            val hang = line.hangingClusterIndices.size > 0
            // `adjustedWidth` is already post-shrink (tryPushIn contract), so the
            // deficit below is the HONEST leftover the justifier still has to
            // stretch — a push-in line is not automatically a flush line.
            val deficit = if (isLast) 0f else (limit - line.adjustedWidth).coerceAtLeast(0f)
            val sinoFill = if (sinoGaps > 0) minOf(deficit, sinoGaps * r.sinoWesternStretchCap) else 0f
            val dSino = if (sinoGaps > 0) sinoFill / sinoGaps else 0f
            val cjkDeficit = deficit - sinoFill
            val dCjk = if (cjkGaps > 0) cjkDeficit / cjkGaps else 0f
            out += LineProfile(
                clusters = inMeasure.last - inMeasure.first + 1,
                dSino = dSino,
                dCjk = dCjk,
                residual = if (cjkGaps == 0) cjkDeficit else 0f,
                compression = pushIn?.totalShrink ?: 0f,
                sinoAtCap = sinoGaps > 0 && dSino >= r.sinoWesternStretchCap - 0.01f,
                pushIn = pushIn != null,
                hang = hang,
            )
        }
        return out
    }

    private fun summarize(profiles: List<LineProfile>): String {
        var run = 0
        var maxRun = 0
        var visible = 0
        for (p in profiles) {
            if (p.visibleStretch) {
                run += 1
                visible += 1
                maxRun = maxOf(maxRun, run)
            } else {
                run = 0
            }
        }
        val lastClusters = profiles.lastOrNull()?.clusters ?: 0
        return "lines=%2d 末行字=%2d 拉伸行=%d 最长游程=%d maxDSino=%4.2f%s maxDCjk=%5.2f 推入行=%d 悬挂行=%d".format(
            profiles.size,
            lastClusters,
            visible,
            maxRun,
            profiles.maxOfOrNull { it.dSino } ?: 0f,
            if (profiles.any { it.sinoAtCap }) "*" else " ",
            profiles.maxOfOrNull { it.dCjk } ?: 0f,
            profiles.count { it.pushIn },
            profiles.count { it.hang },
        )
    }

    private fun run(
        text: String,
        maxWidth: Float,
        breaker: LineBreaker,
        indentEm: Float?,
        useHyphenation: Boolean,
        pinBasicNoHang: Boolean,
        lineHeight: Float?,
        decorations: List<org.tiqian.core.DecorationSpan>,
    ): Recorder {
        val recorder = Recorder(breaker)
        val engine = if (pinBasicNoHang) {
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = recorder,
                textShaper = AwtTextShaper(),
                hyphenator = if (useHyphenation) {
                    org.tiqian.linebreak.EnglishHyphenation.enUs()
                } else {
                    org.tiqian.linebreak.NoHyphenator()
                },
                clreqProfileResolver = object : org.tiqian.clreq.ClreqProfileResolver {
                    override fun resolve(profileId: org.tiqian.core.LayoutProfileId): org.tiqian.clreq.ClreqProfile =
                        org.tiqian.clreq.ClreqProfile.MainlandHorizontal.copy(
                            kinsokuMode = org.tiqian.clreq.KinsokuMode.Fixed(
                                org.tiqian.clreq.KinsokuLevel.Basic,
                                org.tiqian.clreq.HangingPunctuationStyle.Disabled,
                            ),
                        )
                },
            )
        } else {
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = recorder,
                textShaper = AwtTextShaper(),
                hyphenator = if (useHyphenation) {
                    org.tiqian.linebreak.EnglishHyphenation.enUs()
                } else {
                    org.tiqian.linebreak.NoHyphenator()
                },
            )
        }
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = maxWidth),
                paragraphStyle = ParagraphStyle(
                    lineHeight = lineHeight,
                    firstLineIndent = indentEm?.let { Ic(it) },
                ),
                decorations = decorations,
            ),
        )
        return recorder
    }

    @Test
    fun reportPerceptualProfiles() {
        if (System.getenv("TIQIAN_RUN_EXPERIMENTS") != "1") {
            println("ParagraphDpTuningProbe: set TIQIAN_RUN_EXPERIMENTS=1 to run.")
            return
        }
        data class Case(val id: String, val text: String, val width: Float, val hyphen: Boolean, val pin: Boolean, val lh: Float?, val indent: Float?, val deco: List<org.tiqian.core.DecorationSpan>)

        val cases = PROSE.withIndex().flatMap { (i, text) ->
            WIDTHS.map { w -> Case("prose-" + (i + 1) + "-w" + w.toInt(), text, w, false, false, null, 2f, emptyList()) }
        }

        println()
        println("=== ParagraphDp tuning probe: committed output through the v3 lens (AWT advances) ===")
        println("    (* = 中西间距顶到 cap)")
        var lastLineOrphanLook = 0
        var lastLineOrphanDp = 0
        var extraLines = 0
        var fewerLines = 0
        for (case in cases) {
            val look = run(case.text, case.width, LookaheadLineBreaker(), case.indent, case.hyphen, case.pin, case.lh, case.deco)
            val dp = run(case.text, case.width, ParagraphDpLineBreaker(), case.indent, case.hyphen, case.pin, case.lh, case.deco)
            val r = look.recorded ?: continue
            val lookLines = look.solution?.lines ?: continue
            val dpLines = dp.solution?.lines ?: continue
            val lookP = profile(lookLines, r)
            val dpP = profile(dpLines, r)
            if (lookP.size < 3) continue
            if (lookP.lastOrNull()?.clusters == 1) lastLineOrphanLook += 1
            if (dpP.lastOrNull()?.clusters == 1) lastLineOrphanDp += 1
            if (dpP.size > lookP.size) extraLines += 1
            if (dpP.size < lookP.size) fewerLines += 1
            println("%-26s look %s".format(case.id.take(26), summarize(lookP)))
            println("%-26s dp   %s".format("", summarize(dpP)))
            val lookSeq = lookP.joinToString(" ") { fmt(it) }
            val dpSeq = dpP.joinToString(" ") { fmt(it) }
            if (lookSeq != dpSeq) {
                println("%-26s      look d: %s".format("", lookSeq))
                println("%-26s      dp   d: %s".format("", dpSeq))
            }
        }
        println(
            "totals: 末行孤字 look=%d dp=%d | dp 行数更多=%d 更少=%d".format(
                lastLineOrphanLook, lastLineOrphanDp, extraLines, fewerLines,
            ),
        )
    }

    /**
     * `CompressionVisibilityDiscount` sweep: how much of the lookahead's
     * all-natural profile does the DP recover as compression gets cheaper?
     */
    @Test
    fun sweepCompressionVisibility() {
        if (System.getenv("TIQIAN_RUN_EXPERIMENTS") != "1") {
            println("ParagraphDpTuningProbe: set TIQIAN_RUN_EXPERIMENTS=1 to run.")
            return
        }
        data class Case(val id: String, val text: String, val width: Float, val hyphen: Boolean, val pin: Boolean, val lh: Float?, val indent: Float?, val deco: List<org.tiqian.core.DecorationSpan>)

        val cases = PROSE.withIndex().flatMap { (i, text) ->
            WIDTHS.map { w -> Case("prose-" + (i + 1) + "-w" + w.toInt(), text, w, false, false, null, 2f, emptyList()) }
        }

        val variants: List<Pair<String, LineBreaker>> = listOf(
            "lookahead" to LookaheadLineBreaker(),
            "dp v=1.0 " to ParagraphDpLineBreaker(compressionVisibility = 1f),
            "dp v=0.5 " to ParagraphDpLineBreaker(compressionVisibility = 0.5f),
            "dp v=0.35" to ParagraphDpLineBreaker(compressionVisibility = 0.35f),
            "dp v=0.2 " to ParagraphDpLineBreaker(compressionVisibility = 0.2f),
            "dp v=0.05" to ParagraphDpLineBreaker(compressionVisibility = 0.05f),
        )

        println()
        println("=== CompressionVisibilityDiscount sweep (aggregate over ${cases.size} cases) ===")
        println("%-10s %8s %8s %8s %8s %8s %8s %8s".format(
            "variant", "拉伸行", "最长游程", "maxDCjk", "推入行", "总行数", "末行<3字", "顶cap行",
        ))
        for ((label, breaker) in variants) {
            var visible = 0
            var worstRun = 0
            var worstD = 0f
            var pushIns = 0
            var lines = 0
            var shortLast = 0
            var atCap = 0
            for (case in cases) {
                val rec = run(case.text, case.width, breaker, case.indent, case.hyphen, case.pin, case.lh, case.deco)
                val r = rec.recorded ?: continue
                val p = profile(rec.solution?.lines ?: continue, r)
                if (p.size < 3) continue
                var run = 0
                for (line in p) {
                    if (line.visibleStretch) {
                        visible += 1
                        run += 1
                        worstRun = maxOf(worstRun, run)
                    } else {
                        run = 0
                    }
                    if (line.sinoAtCap) atCap += 1
                }
                worstD = maxOf(worstD, p.maxOf { maxOf(it.dSino, it.dCjk) })
                pushIns += p.count { it.pushIn }
                lines += p.size
                if ((p.lastOrNull()?.clusters ?: 99) < 3) shortLast += 1
            }
            println("%-10s %8d %8d %8.2f %8d %8d %8d %8d".format(
                label, visible, worstRun, worstD, pushIns, lines, shortLast, atCap,
            ))
        }
    }

    /** `d` (post-repair stretch), suffixed `p` when the line also carries a push-in. */
    private fun fmt(p: LineProfile): String {
        val d = maxOf(p.dSino, p.dCjk)
        val head = if (d <= 0.01f) "0" else "%.1f".format(d)
        return "%4s".format(head + (if (p.sinoAtCap) "*" else "") + (if (p.pushIn) "p" else ""))
    }

    private companion object {
        val WIDTHS = listOf(240f, 280f, 320f, 360f, 400f)

        /** Real Chinese prose, punctuation-rich, with embedded Western runs. */
        val PROSE = listOf(
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
            "这个 API 的名字叫 ParagraphLayoutEngine，它接受一段 UTF-16 文本和一组约束，返回可解释的" +
                "LayoutResult。所谓「可解释」，是说每一次断行、每一处标点压缩、每一个字体回退，都在 debug " +
                "info 里留下一条带名字的决策记录——CompressionAsDpEdge、StretchRunSparsity、" +
                "KinsokuAvoidanceOverRepair，诸如此类。名字不是为了好看，是为了让后来的人知道这里做过取舍。",
        )
    }
}
