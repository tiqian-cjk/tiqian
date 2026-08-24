package org.tiqian.layout

import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.TiqianTextContent
import org.tiqian.test.EarlyLayoutFixtures
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
 * TIQIAN_UPDATE_GOLDEN=1 ./gradlew :layout:jvmTest --tests '*LayoutDumpGoldenTest*'
 * ```
 *
 * then review the golden diff like any other code change.
 */
class LayoutDumpGoldenTest {

    private val goldenDir = File("../conformance/dumps")
    private val updateMode = System.getenv("TIQIAN_UPDATE_GOLDEN") == "1"

    @Test
    fun layoutDecisionDumpsMatchGolden() {
        val failures = mutableListOf<String>()
        for (fixture in EarlyLayoutFixtures.all) {
            val dump = buildString {
                appendLine("fixture: ${fixture.id}")
                appendLine("text: ${fixture.text.escapeDumpText()}")
                appendLine("maxWidth: ${fixture.constraints.maxWidth.fmt()}")
                for ((label, breaker) in listOf(
                    "greedy" to GreedyLineBreaker(),
                    "lookahead" to LookaheadLineBreaker(),
                    "paragraph-dp" to ParagraphDpLineBreaker(),
                )) {
                    val hyphenator = if (fixture.useEnglishHyphenation) {
                        org.tiqian.linebreak.EnglishHyphenation.enUs
                    } else {
                        org.tiqian.linebreak.NoHyphenator
                    }
                    val engine = if (fixture.pinBasicNoHang) {
                        ExplainableStubParagraphLayoutEngine(
                            lineBreaker = breaker,
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
                        ExplainableStubParagraphLayoutEngine(lineBreaker = breaker, hyphenator = hyphenator)
                    }
                    val result = engine.layout(
                        LayoutInput(
                            content = TiqianTextContent(
                                fixture.text,
                                lineBreakSpans = fixture.lineBreakSpans,
                            ),
                            constraints = fixture.constraints,
                            paragraphStyle = org.tiqian.core.ParagraphStyle(
                                lineHeight = fixture.lineHeight,
                                firstLineIndent = fixture.firstLineIndentEm?.let { org.tiqian.core.Ic(it) },
                                rubyLineHeightMode = fixture.rubyLineHeightMode,
                                lineLengthGrid = fixture.lineLengthGrid,
                            ),
                            decorations = fixture.decorations,
                            rubySpans = fixture.rubySpans,
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
        debug.lineLengthGridDecision?.let { g ->
            if (g.enabled && g.slack > 0f) {
                appendLine(
                    "grid container=${g.containerWidth.fmt()} measure=${g.measure.fmt()}(${g.cells}字) " +
                        "slack=${g.slack.fmt()} body=${g.bodyAlignment}@${g.bodyOffset.fmt()}",
                )
            }
        }
        debug.firstLineIndentDecision?.let { f ->
            if (f.source != "Explicit") {
                appendLine(
                    "firstindent ${f.resolvedEm.fmt()}字 measure=${f.measureEm.fmt()}字 " +
                        "threshold=${f.thresholdEm.fmt()}字 ${f.source}",
                )
            }
        }
        debug.kinsokuDecision?.let { k ->
            appendLine("kinsoku measure=${k.measureEm.fmt()}字 level=${k.level} hang=${k.hanging} reason=${k.reason}")
        }
        debug.contextualKinsokuDecisions.forEach { k ->
            appendLine(
                "context-kinsoku ${k.range.start}-${k.range.end} " +
                    "source='${k.sourceText.escapeDumpText()}' cluster=${k.clusterIndex} " +
                    "forbid=${k.forbiddenPosition} reason=${k.reason}" +
                    (k.impossibleMeasureFallback?.let { " fallback=$it" } ?: ""),
            )
        }
        debug.breakOpportunityDecisions.forEach { decision ->
            appendLine(
                "break-opportunity ${decision.range.start}-${decision.range.end} " +
                    "source='${decision.sourceText.escapeDumpText()}' " +
                    "offsets=${decision.breakOffsets.joinToString(",")}" +
                    (decision.tier?.let { " tier=$it" } ?: "") +
                    " reason=${decision.reason}",
            )
        }
        debug.emergencyTrackingEligibilityDecisions.forEach { decision ->
            appendLine(
                "tracking-eligibility ${decision.range.start}-${decision.range.end} " +
                    "source='${decision.sourceText.escapeDumpText()}' reason=${decision.reason}",
            )
        }
        debug.inlineObjectPunctuationAttachmentDecisions.forEach { attachment ->
            appendLine(
                "inline-object-punctuation ${attachment.objectRange.start}-${attachment.objectRange.end} " +
                    "separator=${attachment.separatorRange.start}-${attachment.separatorRange.end} " +
                    "punctuation=${attachment.punctuationRange.start}-${attachment.punctuationRange.end} " +
                    "source='${attachment.punctuationText.escapeDumpText()}' " +
                    "collapsed=${attachment.collapsedAdvance.fmt()} " +
                    "protected=${attachment.protectedRange.start}-${attachment.protectedRange.end} " +
                    "reason=${attachment.reason}",
            )
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
                    "deficit=${j.deficitBefore.fmt()}->${j.deficitAfter.fmt()}" +
                        j.allocations
                            .joinToString(",") {
                                "${it.kind}@${it.clusterRange.start}+${it.delta.fmt()}" +
                                    if (it.reason == it.kind) "" else "(${it.reason})"
                            }
                            .takeIf { it.isNotEmpty() }
                            ?.let { " $it" }
                            .orEmpty()
                } ?: "-"
            val indent = if (line.indent > 0f) "indent=${line.indent.fmt()} " else ""
            val hyphen = if (line.hyphenAdvance > 0f) "hyphen=${line.hyphenAdvance.fmt()} " else ""
            appendLine(
                "line[$i] ${line.range.start}-${line.range.end} $indent$hyphen" +
                    "natural=${line.naturalWidth.fmt()} adjusted=${line.adjustedWidth.fmt()} " +
                    "visual=${line.visualWidth.fmt()} repair=$repair candidates=$candidates justify=$justify",
            )
        }
        clusters.forEach { c ->
            appendLine(
                "cluster ${c.range.start}-${c.range.end} '${c.displayText}' adv=${c.advance.fmt()}" +
                    (if (c.glyphInlineShift != 0f) " glyphShift=${c.glyphInlineShift.fmt()}" else ""),
            )
        }
        debug.fontDecisions.forEach { f ->
            appendLine(
                "font ${f.range.start}-${f.range.end} role=${f.role} key=${f.fontKey} " +
                    "display='${f.displayText}' sub=${f.substitutionReason}",
            )
        }
        debug.roleOverrides.forEach { role ->
            appendLine(
                "role-override ${role.range.start}-${role.range.end} " +
                    "source='${role.sourceText.escapeDumpText()}' " +
                    "${role.originalRole}->${role.overriddenRole} " +
                    "policy=${role.source} reason=${role.reason}",
            )
        }
        debug.punctuationDecisions.forEach { p ->
            appendLine(
                "punct ${p.range.start}-${p.range.end} '${p.char}' class=${p.punctuationClass} " +
                    "adv=${p.advance.fmt()} body=${p.bodyWidth.fmt()} " +
                    "lead=${p.leadingGlueNatural.fmt()} trail=${p.trailingGlueNatural.fmt()} " +
                    (if (p.leadingGlueInitiallyConsumed != 0f || p.trailingGlueInitiallyConsumed != 0f) {
                        "initial=${p.leadingGlueInitiallyConsumed.fmt()}/${p.trailingGlueInitiallyConsumed.fmt()} "
                    } else {
                        ""
                    }) +
                    "anchor=${p.anchor} source=${p.geometrySource}" +
                    (if (p.advanceExpansion != 0f) " expand=${p.advanceExpansion.fmt()}" else "") +
                    (if (p.glyphInlineShift != 0f) " glyphShift=${p.glyphInlineShift.fmt()}" else "") +
                    (p.glyphPlacementReason?.let { " placement=$it" } ?: "") +
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
                    "justify=${g.justificationDelta.fmt()}" +
                    (if (g.rubySpread != 0f) " ruby=${g.rubySpread.fmt()}" else "") +
                    (if (g.glyphInlineShift != 0f) " glyphShift=${g.glyphInlineShift.fmt()}" else "") +
                    (g.glyphPlacementReason?.let { " placement=$it" } ?: "") +
                    " resolved=${g.resolvedAdvance.fmt()}",
            )
        }
        debug.inlineBoxDecisions.forEach { box ->
            appendLine(
                "inline-box ${box.range.start}-${box.range.end} " +
                    "start=${box.inlineStart.fmt()} end=${box.inlineEnd.fmt()} " +
                    "outer=${box.outerSpacing} " +
                    "clusters=${box.firstClusterIndex}-${box.lastClusterIndex} reason=${box.reason}",
            )
        }
        debug.inlineObjectDecisions.forEach { inlineObject ->
            appendLine(
                "inline-object ${inlineObject.range.start}-${inlineObject.range.end} " +
                    "advance=${inlineObject.advance.fmt()} ascent=${inlineObject.ascent.fmt()} " +
                    "descent=${inlineObject.descent.fmt()} cluster=${inlineObject.clusterIndex} " +
                    "line=${inlineObject.lineIndex} " +
                    "edges=${if (inlineObject.leadingUniformStretch) "stretch" else "fixed"}/" +
                    "${inlineObject.leadingPreferredStretchKind ?: "-"}/" +
                    "${inlineObject.leadingPreferredStretchNaturalWidth.fmt()}→" +
                    "${inlineObject.leadingPreferredStretchTargetWidth.fmt()}/" +
                    "${inlineObject.leadingPreferredStretchCapacity.fmt()}/" +
                    "${if (inlineObject.leadingPreventsLineBreak) "closed" else "natural"}/" +
                    "${inlineObject.leadingShrinkCapacity.fmt()}/" +
                    "${inlineObject.leadingLineEndDiscardableAdvance.fmt()}.." +
                    "${if (inlineObject.trailingUniformStretch) "stretch" else "fixed"}/" +
                    "${inlineObject.trailingPreferredStretchKind ?: "-"}/" +
                    "${inlineObject.trailingPreferredStretchNaturalWidth.fmt()}→" +
                    "${inlineObject.trailingPreferredStretchTargetWidth.fmt()}/" +
                    "${inlineObject.trailingPreferredStretchCapacity.fmt()}/" +
                    "${if (inlineObject.trailingPreventsLineBreak) "closed" else "natural"}/" +
                    "${inlineObject.trailingShrinkCapacity.fmt()}/" +
                    "${inlineObject.trailingLineEndDiscardableAdvance.fmt()} reason=${inlineObject.reason}",
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
        debug.mandatoryBreakDecisions.forEach { b ->
            appendLine(
                "mandatorybreak ${b.range.start}-${b.range.end} afterCluster=${b.breakAfterClusterIndex} " +
                    "reason=${b.reason}",
            )
        }
        debug.zeroWidthBreakDecisions.forEach { b ->
            appendLine(
                "zerowidthbreak ${b.range.start}-${b.range.end} " +
                    "source='${b.sourceText.escapeDumpText()}' cluster=${b.clusterIndex} reason=${b.reason}",
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
                    "applied=${d.applied} anchor=${d.anchorX.fmt()},${d.anchorY.fmt()} " +
                    "diameter=${d.dotDiameter.fmt()} reason=${d.reason}",
            )
        }
        debug.lineSpacingDecision?.let { d ->
            appendLine(
                "linespacing natural=${d.naturalHeight.fmt()} requested=${d.requestedLineHeight?.fmt() ?: "-"} " +
                    "resolved=${d.resolvedHeight.fmt()} floor=${d.spacingFloor.fmt()} " +
                    "applied=${d.floorApplied} reason=${d.reason}",
            )
        }
        debug.rubyLineHeightDecision?.let { d ->
            appendLine(
                "rubylineheight mode=${d.mode} base=${d.baseLineHeight.fmt()} " +
                    "face=${d.baseFaceHeight.fmt()} ruby=${d.rubyExtent.fmt()} " +
                    "available=${d.availableInterlineSpace.fmt()} maxExtra=${d.maxExtra.fmt()} " +
                    "extras=${d.lineExtras.joinToString(",") { it.fmt() }.ifEmpty { "-" }} " +
                "lines=${d.expandedLineIndices.joinToString(",").ifEmpty { "-" }} reason=${d.reason}",
            )
        }
        debug.inlineObjectLineHeightDecision?.let { d ->
            appendLine(
                "inlineobjectlineheight base=${d.baseLineHeight.fmt()} " +
                    "face=${d.baseFaceAscent.fmt()}+${d.baseFaceDescent.fmt()} " +
                    "available=${d.availableInterlineSpace.fmt()} " +
                    "clearance=${d.minimumClearance.fmt()} " +
                    "ascents=${d.lineAscents.joinToString(",") { it.fmt() }.ifEmpty { "-" }} " +
                    "descents=${d.lineDescents.joinToString(",") { it.fmt() }.ifEmpty { "-" }} " +
                    "extras=${d.lineExtras.joinToString(",") { it.fmt() }.ifEmpty { "-" }} " +
                    "boundaries=${d.boundaryShiftsAfter.joinToString(",") { it.fmt() }.ifEmpty { "-" }} " +
                    "trailing=${d.trailingExtra.fmt()} " +
                    "lines=${d.expandedLineIndices.joinToString(",").ifEmpty { "-" }} reason=${d.reason}",
            )
        }
        debug.maxLinesDecision?.let { d ->
            appendLine("maxlines laidOut=${d.laidOutLines} visible=${d.visibleLines} reason=${d.reason}")
        }
        debug.decorationSegments.forEach { seg ->
            appendLine(
                "decobox ${seg.sourceRange.start}-${seg.sourceRange.end} kind=${seg.kind} line=${seg.lineIndex} " +
                    "rect=${seg.left.fmt()},${seg.top.fmt()},${seg.right.fmt()},${seg.bottom.fmt()} " +
                    "open=${if (seg.openStart) "start" else "-"}/${if (seg.openEnd) "end" else "-"} reason=${seg.reason}",
            )
        }
        debug.rubyDecisions.forEach { r ->
            appendLine(
                "ruby ${r.baseRange.start}-${r.baseRange.end} '${r.text}' line=${r.lineIndex} " +
                    "centerX=${r.centerX.fmt()} baselineY=${r.baselineY.fmt()} size=${r.fontSize.fmt()} " +
                    "box=${r.ascent.fmt()}/${r.descent.fmt()} width=${r.width.fmt()} " +
                    "overhang=${r.overhang.fmt()} locale=${r.locale}",
            )
        }
        debug.bopomofoDecisions.forEach { z ->
            appendLine(
                "bopomofo ${z.baseRange.start}-${z.baseRange.end} '${z.text}' " +
                    "line=${z.lineIndex} locale=${z.locale}",
            )
            z.placements.forEach { p ->
                appendLine(
                    "  ${p.role} '${p.text}' rect=${p.left.fmt()},${p.top.fmt()},${p.width.fmt()},${p.height.fmt()} " +
                        "draw=${p.drawX.fmt()},${p.baselineY.fmt()} size=${p.fontSize.fmt()}",
                )
            }
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

    private fun String.escapeDumpText(): String = buildString {
        for (ch in this@escapeDumpText) {
            when (ch) {
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\u000B' -> append("\\v")
                '\u000C' -> append("\\f")
                '\u0085' -> append("\\u0085")
                '\u2028' -> append("\\u2028")
                '\u2029' -> append("\\u2029")
                '\u200B' -> append("\\u200B")
                else -> append(ch)
            }
        }
    }
}
