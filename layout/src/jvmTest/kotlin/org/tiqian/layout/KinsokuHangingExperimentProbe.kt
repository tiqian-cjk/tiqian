package org.tiqian.layout

import org.tiqian.core.Ic

import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.HangingPunctuationStyle
import org.tiqian.clreq.KinsokuLevel
import org.tiqian.clreq.KinsokuMode
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.shaping.ExplainableStubTextShaper
import java.io.File
import kotlin.test.Test

/**
 * Experiment (not a pass/fail test): with line width measured in 字数, how do
 * CLREQ kinsoku levels (GB 法 vs 严格处理) and line-end hanging punctuation
 * behave on large real text across line widths?
 *
 * Corpora (deterministic stub shaper, fontSize 16, CJK = 1em so maxWidth =
 * N×16 == N 字):
 *   - `wiki-zh-corpus.txt`  — zh.wikipedia 正文, dash/ellipsis-sparse.
 *   - `lit-zh-corpus.txt`   — same sentences with 破折号/省略号 injected at
 *     ~1% density (literary/dialogue analogue) to expose where 严格处理's
 *     extra line-start prohibition actually costs.
 *
 * Metric `looseness` = the worst single inter-hanzi gap opened by
 * justification on a line (max CjkInterChar delta, in em) — the visual
 * signal CLREQ calls 字距过松. Reported as mean and p95 over all justified
 * (non-last) lines, alongside repair mix and unrepairable (LeaveRagged) rate.
 *
 * Run: `./gradlew :layout:jvmTest --tests '*KinsokuHangingExperimentProbe*'`
 * (output in the test's stdout / build/reports). Skips gracefully when the
 * corpora are absent.
 *
 * Corpora are NOT vendored (Wikipedia CC-BY-SA). Regenerate locally:
 *   - `wiki-zh-corpus.txt`: zh.wikipedia action API plaintext extracts of a
 *     few long articles, paragraphs ≥30 chars, headings dropped.
 *   - `lit-zh-corpus.txt`: the wiki sentences with 破折号/省略号 injected at
 *     ~1% density (seeded) as a literary/dialogue analogue.
 * See ADR 0025 for the recipe and findings.
 */
class KinsokuHangingExperimentProbe {

    private val fontSize = 16f
    private val widths = listOf(8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 40)

    private data class Agg(
        var lines: Int = 0,
        var loose: MutableList<Float> = mutableListOf(),
        var ragged: Int = 0,
        var carry: Int = 0,
        var hang: Int = 0,
        var pushIn: Int = 0,
    )

    private fun engine(level: KinsokuLevel, hang: HangingPunctuationStyle) =
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = ExplainableStubTextShaper(),
            clreqProfileResolver = { _ ->
                ClreqProfile.MainlandHorizontal.copy(
                    kinsokuMode = KinsokuMode.Fixed(level, hang),
                )
            },
        )

    private fun run(paragraphs: List<String>, level: KinsokuLevel, hang: HangingPunctuationStyle, charsPerLine: Int): Agg {
        val eng = engine(level, hang)
        val agg = Agg()
        val maxWidth = charsPerLine * fontSize
        for (p in paragraphs) {
            val result = eng.layout(
                LayoutInput(
                    content = TiqianTextContent(p),
                    constraints = LayoutConstraints(maxWidth = maxWidth),
                    paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
                ),
            )
            // Looseness over justified (non-last) lines.
            for (j in result.debug.justificationDecisions) {
                agg.lines += 1
                val worst = j.allocations
                    .filter { it.kind == "CjkInterChar" }
                    .maxOfOrNull { it.delta } ?: 0f
                agg.loose += worst / fontSize
            }
            for (d in result.debug.lineDecisions) {
                when (d.repair) {
                    "LeaveRagged" -> agg.ragged += 1
                    "CarryPrevious" -> agg.carry += 1
                    "Hang" -> agg.hang += 1
                    "PushIn" -> agg.pushIn += 1
                }
            }
        }
        return agg
    }

    private fun List<Float>.p95(): Float {
        if (isEmpty()) return 0f
        val s = sorted()
        return s[((s.size - 1) * 0.95f).toInt()]
    }

    private fun loadCorpus(name: String): List<String> {
        val f = File("src/jvmTest/resources/$name")
        if (!f.exists()) return emptyList()
        return f.readText().split("\n").filter { it.isNotBlank() }
    }

    @Test
    fun reportKinsokuAndHangingAcrossLineWidths() {
        val corpora = listOf(
            "wiki (encyclopedic, dash-sparse)" to loadCorpus("wiki-zh-corpus.txt"),
            "lit (dash/ellipsis ~1%)" to loadCorpus("lit-zh-corpus.txt"),
        ).filter { it.second.isNotEmpty() }
        if (corpora.isEmpty()) {
            println("KinsokuHangingExperimentProbe: corpora missing, skipping.")
            return
        }

        for ((corpusName, paras) in corpora) {
            val totalChars = paras.sumOf { it.length }
            println()
            println("=== $corpusName — ${paras.size} paragraphs, $totalChars chars ===")
            println("width=字数  config            lines  loose_mean  loose_p95  ragged/1k  carry/1k  hang/1k")

            data class Cfg(val tag: String, val level: KinsokuLevel, val hang: HangingPunctuationStyle)
            val configs = listOf(
                Cfg("GB            ", KinsokuLevel.GbStyle, HangingPunctuationStyle.Disabled),
                Cfg("Strict        ", KinsokuLevel.Strict, HangingPunctuationStyle.Disabled),
                Cfg("GB+hang       ", KinsokuLevel.GbStyle, HangingPunctuationStyle.PauseStops),
                Cfg("Strict+hang   ", KinsokuLevel.Strict, HangingPunctuationStyle.PauseStops),
            )

            for (n in widths) {
                for (c in configs) {
                    val a = run(paras, c.level, c.hang, n)
                    val perK = if (a.lines == 0) 0f else 1000f / a.lines
                    println(
                        "%-10d %s %6d  %9.4f  %9.4f  %8.2f  %8.2f  %7.2f".format(
                            n, c.tag, a.lines,
                            a.loose.average().toFloat(), a.loose.p95(),
                            a.ragged * perK, a.carry * perK, a.hang * perK,
                        ),
                    )
                }
                println()
            }
        }
    }
}
