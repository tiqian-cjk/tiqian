package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.test.EarlyLayoutFixtures
import java.io.File
import kotlin.test.Test
import kotlin.test.fail

/**
 * Golden regression baseline for layout decisions (Slice 6 验收).
 *
 * Every fixture is laid out with the deterministic stub shaper (platform
 * fonts would make goldens machine-dependent) under both breakers, and the
 * full structured decision dump is compared against the checked-in golden.
 * Any change to line breaking, punctuation geometry, spacing, justification
 * or repairs shows up as a readable diff here instead of waiting for an
 * eyeball in the playground.
 *
 * To regenerate after an INTENTIONAL behaviour change:
 *
 * ```
 * TIQIAN_UPDATE_GOLDEN=1 ./gradlew :tiqian-layout:jvmTest --tests '*LayoutDumpGoldenTest*'
 * ```
 *
 * then review the golden diff like any other code change.
 */
class LayoutDumpGoldenTest {

    private val goldenDir = File("src/jvmTest/resources/golden/layout-dumps")
    private val updateMode = System.getenv("TIQIAN_UPDATE_GOLDEN") == "1"

    @Test
    fun layoutDecisionDumpsMatchGolden() {
        val failures = mutableListOf<String>()
        for (fixture in EarlyLayoutFixtures.all) {
            val dump = buildString {
                appendLine("fixture: ${fixture.id}")
                appendLine("text: ${fixture.text}")
                appendLine("maxWidth: ${fixture.constraints.maxWidth.fmt()}")
                for ((label, breaker) in listOf(
                    "greedy" to GreedyLineBreaker(),
                    "lookahead" to LookaheadLineBreaker(),
                )) {
                    val engine = if (fixture.pinBasicNoHang) {
                        ExplainableStubParagraphLayoutEngine(
                            lineBreaker = breaker,
                            clreqProfileResolver = {
                                ink.duo3.tiqian.clreq.ClreqProfile.MainlandHorizontal.copy(
                                    kinsokuMode = ink.duo3.tiqian.clreq.KinsokuMode.Fixed(
                                        ink.duo3.tiqian.clreq.KinsokuLevel.Basic,
                                    ),
                                )
                            },
                        )
                    } else {
                        ExplainableStubParagraphLayoutEngine(lineBreaker = breaker)
                    }
                    val result = engine.layout(
                        LayoutInput(
                            content = TiqianTextContent(fixture.text),
                            constraints = fixture.constraints,
                            paragraphStyle = ink.duo3.tiqian.core.ParagraphStyle(
                                lineHeight = fixture.lineHeight,
                                firstLineIndentEm = fixture.firstLineIndentEm,
                            ),
                            decorations = fixture.decorations,
                        ),
                    )
                    append(result.dump(label))
                }
            }

            val goldenFile = File(goldenDir, "${fixture.id}.txt")
            if (updateMode) {
                goldenFile.parentFile.mkdirs()
                goldenFile.writeText(dump)
                continue
            }
            if (!goldenFile.exists()) {
                failures += "missing golden ${goldenFile.path} — run with TIQIAN_UPDATE_GOLDEN=1"
                continue
            }
            val expected = goldenFile.readText()
            if (expected != dump) {
                failures += diffMessage(fixture.id, expected, dump)
            }
        }
        if (failures.isNotEmpty()) {
            fail(
                failures.joinToString("\n\n") +
                    "\n\nIf the change is intentional, regenerate with " +
                    "TIQIAN_UPDATE_GOLDEN=1 and review the golden diff.",
            )
        }
        if (updateMode) {
            println("golden dumps written to ${goldenDir.absolutePath}")
        }
    }

    private fun LayoutResult.dump(label: String): String = buildString {
        appendLine("== $label ==")
        appendLine("size ${size.width.fmt()}x${size.height.fmt()}")
        debug.kinsokuDecision?.let { k ->
            appendLine("kinsoku measure=${k.measureEm.fmt()}字 level=${k.level} hang=${k.hanging} reason=${k.reason}")
        }
        lines.forEachIndexed { i, line ->
            val decision = debug.lineDecisions.getOrNull(i)
            val repair = decision?.repairDecision?.let { r ->
                "${r.kind}(${r.reasonCode} shrink=${r.shrink.fmt()})"
            } ?: "-"
            val candidates = decision?.repairCandidates.orEmpty()
                .joinToString(",") { "${it.kind}${if (it.accepted) "+" else "-"}" }
                .ifEmpty { "-" }
            val justify = debug.justificationDecisions.firstOrNull { it.lineRange == line.range }
                ?.let { j ->
                    "deficit=${j.deficitBefore.fmt()}->${j.deficitAfter.fmt()} " +
                        j.allocations.joinToString(",") { "${it.kind}@${it.clusterRange.start}+${it.delta.fmt()}" }
                } ?: "-"
            val indent = if (line.indent > 0f) "indent=${line.indent.fmt()} " else ""
            appendLine(
                "line[$i] ${line.range.start}-${line.range.end} $indent" +
                    "natural=${line.naturalWidth.fmt()} adjusted=${line.adjustedWidth.fmt()} " +
                    "visual=${line.visualWidth.fmt()} repair=$repair candidates=$candidates justify=$justify",
            )
        }
        clusters.forEach { c ->
            appendLine("cluster ${c.range.start}-${c.range.end} '${c.displayText}' adv=${c.advance.fmt()}")
        }
        debug.fontDecisions.forEach { f ->
            appendLine(
                "font ${f.range.start}-${f.range.end} role=${f.role} key=${f.fontKey} " +
                    "display='${f.displayText}' sub=${f.substitutionReason}",
            )
        }
        debug.punctuationDecisions.forEach { p ->
            appendLine(
                "punct ${p.range.start}-${p.range.end} '${p.char}' class=${p.punctuationClass} " +
                    "adv=${p.advance.fmt()} body=${p.bodyWidth.fmt()} " +
                    "lead=${p.leadingGlueNatural.fmt()} trail=${p.trailingGlueNatural.fmt()} " +
                    "anchor=${p.anchor} source=${p.geometrySource}" +
                    (p.haltAdvance?.let { " halt=${it.fmt()}" } ?: "") +
                    (p.inkBoundsFallback?.let { " fallback=$it" } ?: "") +
                    (p.haltValidation?.let { " haltWarn=$it" } ?: ""),
            )
        }
        debug.geometryDecisions.forEach { g ->
            appendLine(
                "geom ${g.range.start}-${g.range.end} body=${g.bodyWidth.fmt()} " +
                    "lead=${g.leadingGlueConsumed.fmt()}/${g.leadingGlueNatural.fmt()} " +
                    "trail=${g.trailingGlueConsumed.fmt()}/${g.trailingGlueNatural.fmt()} " +
                    "justify=${g.justificationDelta.fmt()} resolved=${g.resolvedAdvance.fmt()}",
            )
        }
        debug.spacingDecisions.forEach { s ->
            appendLine(
                "spacing ${s.range.start}-${s.range.end} '${s.leftChar}${s.rightChar}' " +
                    "inner=${s.naturalInnerGlue.fmt()}->${s.adjustedInnerGlue.fmt()} " +
                    "target=${s.reductionTargetRange.start}-${s.reductionTargetRange.end}",
            )
        }
        debug.autoSpaceDecisions.forEach { a ->
            appendLine(
                "autospace ${a.clusterRange.start}-${a.clusterRange.end} side=${a.side} " +
                    "boundary=${a.boundaryRole} reduction=${a.totalReduction.fmt()}",
            )
        }
        debug.lineEdgeTrimDecisions.forEach { t ->
            appendLine(
                "edgetrim ${t.clusterRange.start}-${t.clusterRange.end} side=${t.side} " +
                    "trim=${t.trimAmount.fmt()} reason=${t.reason}",
            )
        }
        debug.decorationDecisions.forEach { d ->
            appendLine(
                "deco ${d.clusterRange.start}-${d.clusterRange.end} '${d.sourceText}' kind=${d.kind} " +
                    "applied=${d.applied} anchor=${d.anchorX.fmt()},${d.anchorY.fmt()} reason=${d.reason}",
            )
        }
        debug.lineSpacingDecision?.let { d ->
            appendLine(
                "linespacing natural=${d.naturalHeight.fmt()} requested=${d.requestedLineHeight?.fmt() ?: "-"} " +
                    "resolved=${d.resolvedHeight.fmt()} floor=${d.spacingFloor.fmt()} " +
                    "sides=${d.printingSides} applied=${d.floorApplied} reason=${d.reason}",
            )
        }
        debug.decorationSegments.forEach { seg ->
            appendLine(
                "decobox ${seg.sourceRange.start}-${seg.sourceRange.end} kind=${seg.kind} line=${seg.lineIndex} " +
                    "rect=${seg.left.fmt()},${seg.top.fmt()},${seg.right.fmt()},${seg.bottom.fmt()} " +
                    "open=${if (seg.openStart) "start" else "-"}/${if (seg.openEnd) "end" else "-"} reason=${seg.reason}",
            )
        }
    }

    private fun diffMessage(id: String, expected: String, actual: String): String {
        val expectedLines = expected.lines()
        val actualLines = actual.lines()
        val diffs = mutableListOf<String>()
        for (i in 0 until maxOf(expectedLines.size, actualLines.size)) {
            val e = expectedLines.getOrNull(i)
            val a = actualLines.getOrNull(i)
            if (e != a) {
                diffs += "  line ${i + 1}:\n    golden: ${e ?: "<missing>"}\n    actual: ${a ?: "<missing>"}"
                if (diffs.size >= 8) {
                    diffs += "  …"
                    break
                }
            }
        }
        return "golden mismatch for fixture '$id':\n" + diffs.joinToString("\n")
    }

    private fun Float.fmt(): String = "%.1f".format(this)
}
