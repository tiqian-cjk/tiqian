package org.tiqian.playground

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.PunctuationDecisionInfo
import org.tiqian.text.core.Rect
import org.tiqian.text.core.SpacingDecisionInfo
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.layout.GreedyLineBreaker
import org.tiqian.text.layout.LookaheadLineBreaker
import org.tiqian.text.shaping.ExplainableStubTextShaper
import org.tiqian.text.shaping.TextShaper
import org.tiqian.text.shaping.jvm.AwtTextShaper
import org.tiqian.text.test.EarlyLayoutFixtures
import org.tiqian.text.test.LayoutFixture
import java.awt.Font
import java.awt.font.FontRenderContext
import java.awt.geom.AffineTransform
import java.awt.geom.PathIterator
import java.io.File
import java.util.Locale

fun main() {
    val shaperMode = ShaperMode.fromEnvironment()
    val textShaper = shaperMode.createShaper()
    val greedyEngine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = GreedyLineBreaker(),
        textShaper = textShaper,
    )
    val lookaheadEngine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = textShaper,
    )
    val reportItems = mutableListOf<PlaygroundReportItem>()

    println("shaper=${shaperMode.id} (${shaperMode.description})")
    println()

    EarlyLayoutFixtures.all.forEach { fixture ->
        val input = LayoutInput(
            content = TiqianTextContent(fixture.text),
            constraints = fixture.constraints,
            paragraphStyle = org.tiqian.text.core.ParagraphStyle(textAlign = fixture.textAlign),
        )
        val greedyResult = greedyEngine.layout(input)
        val lookaheadResult = lookaheadEngine.layout(input)

        reportItems += PlaygroundReportItem(fixture, greedyResult, lookaheadResult)
        printFixtureDump(fixture, greedyResult, lookaheadResult)
    }

    val reportFile = File("build/reports/tiqian-layout-playground/index.html")
    reportFile.parentFile.mkdirs()
    reportFile.writeText(renderHtmlReport(reportItems, shaperMode))
    println()
    println("HTML report: ${reportFile.absolutePath}")
}

private data class PlaygroundReportItem(
    val fixture: LayoutFixture,
    val greedy: LayoutResult,
    val lookahead: LayoutResult,
)

private enum class ShaperMode(
    val id: String,
    val description: String,
) {
    JvmAwt(
        id = "jvm-awt",
        description = "JVM AWT Font.layoutGlyphVector real advance",
    ),
    Stub(
        id = "stub",
        description = "deterministic nominal em advance",
    );

    fun createShaper(): TextShaper =
        when (this) {
            JvmAwt -> AwtTextShaper()
            Stub -> ExplainableStubTextShaper()
        }

    companion object {
        fun fromEnvironment(): ShaperMode =
            when (System.getenv("TIQIAN_PLAYGROUND_SHAPER")?.lowercase(Locale.ROOT)) {
                "stub" -> Stub
                "jvm", "jvm-awt", "awt", null, "" -> JvmAwt
                else -> JvmAwt
            }
    }
}

private fun printFixtureDump(fixture: LayoutFixture, greedy: LayoutResult, lookahead: LayoutResult) {
    println("${fixture.id}:")
    println("  text=${fixture.text}")
    printEngineDump("greedy   ", greedy)
    printEngineDump("lookahead", lookahead)
    if (greedy.debug.spacingDecisions.isNotEmpty()) {
        println("  spacing (paragraph-wide, identical across engines):")
        greedy.debug.spacingDecisions.forEach { println("    ${it.compactDump()}") }
    }
    println()
}

private fun printEngineDump(label: String, result: LayoutResult) {
    val totalVisual = result.lines.sumOf { it.visualWidth.toDouble() }.toFloat()
    val repairs = result.debug.lineDecisions.count { it.repair != null }
    val justifications = result.debug.justificationDecisions.count { it.allocations.isNotEmpty() }
    println(
        "  [$label] size=${result.size.width.oneDecimal()}x${result.size.height.oneDecimal()} lines=${result.lines.size} visual-sum=${totalVisual.oneDecimal()} repairs=$repairs justifications=$justifications",
    )
    result.lines.forEachIndexed { lineIndex, line ->
        val repair = result.debug.lineDecisions.getOrNull(lineIndex)?.repair
        val justify = result.debug.justificationDecisions.firstOrNull { it.lineRange == line.range }
        val repairTag = if (repair != null) " repair=$repair" else ""
        val justifyTag = if (justify != null && justify.allocations.isNotEmpty()) {
            val kinds = justify.allocations.map { it.kind }.distinct().joinToString("+")
            " justify=$kinds(+${(justify.deficitBefore - justify.deficitAfter).oneDecimal()})"
        } else ""
        println(
            "    line[$lineIndex] adjusted=${line.adjustedWidth.oneDecimal()} visual=${line.visualWidth.oneDecimal()} range=${line.range.start}-${line.range.end}$repairTag$justifyTag",
        )
    }
}

private fun SpacingDecisionInfo.compactDump(): String =
    "${range.start}-${range.end} '$leftChar$rightChar' " +
        "naturalInner=${naturalInnerGlue.oneDecimal()} adjustedInner=${adjustedInnerGlue.oneDecimal()} " +
        "reduction=${reduction.oneDecimal()} target=${reductionTargetRange.start}-${reductionTargetRange.end} $reason"

private fun Cluster.compactDump(): String =
    "${range.start}-${range.end} '$displayText' ${advance.oneDecimal()} $fontKey"

private fun renderHtmlReport(items: List<PlaygroundReportItem>, shaperMode: ShaperMode): String =
    buildString {
        appendLine("<!doctype html>")
        appendLine("<html lang=\"zh-Hans\">")
        appendLine("<head>")
        appendLine("<meta charset=\"utf-8\">")
        appendLine("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        appendLine("<title>提椠 layout playground</title>")
        appendLine(
            """
            <style>
              :root {
                --fg: #1f2328;
                --muted: #596168;
                --bg: #f7f7f4;
                --panel: #ffffff;
                --rule: #d8d4ca;
                --baseline: rgba(196, 80, 60, 0.55);
                --linebox: rgba(80, 120, 200, 0.45);
                --glyph-cjk: rgba(108, 168, 230, 0.18);
                --glyph-cjk-border: rgba(80, 130, 200, 0.45);
                --glyph-punct: rgba(232, 174, 80, 0.22);
                --glyph-punct-border: rgba(195, 134, 50, 0.55);
                --glyph-latin: rgba(140, 200, 140, 0.18);
                --glyph-latin-border: rgba(80, 160, 80, 0.50);
                --ink: rgba(210, 55, 55, 0.78);
                --ink-fill: rgba(210, 55, 55, 0.10);
              }
              body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--fg); }
              main { max-width: 1280px; margin: 0 auto; padding: 32px 24px 64px; }
              h1 { font-size: 28px; margin: 0 0 8px; }
              .intro { color: var(--muted); margin: 0 0 24px; font-size: 14px; max-width: 80ch; }
              section { border-top: 1px solid var(--rule); padding: 24px 0 32px; }
              h2 { font-size: 18px; margin: 0 0 4px; }
              .notes { margin: 0 0 14px; color: var(--muted); font-size: 13px; }
              .compare { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 24px; align-items: start; margin: 12px 0 14px; }
              .col-label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 6px; }
              .sample-browser { font-size: 16px; line-height: 1; padding: 0; background: var(--panel); border: 1px dashed var(--rule); box-sizing: content-box; word-break: break-word; }
              .sample-engine { position: relative; font-size: 16px; line-height: 1; background: var(--panel); border: 1px dashed var(--rule); box-sizing: content-box; overflow: visible; }
              .sample-engine .line-box { position: absolute; left: 0; right: 0; border-top: 1px dotted var(--linebox); pointer-events: none; }
              .sample-engine .line-box.last { border-bottom: 1px dotted var(--linebox); }
              .sample-engine .baseline { position: absolute; left: 0; right: 0; height: 0; border-top: 1px solid var(--baseline); pointer-events: none; }
              .sample-engine .glyph { position: absolute; box-sizing: border-box; display: flex; align-items: center; justify-content: center; overflow: visible; }
              .sample-engine .glyph.latin { justify-content: flex-start; }
              .sample-engine .glyph.cjk-text { background: var(--glyph-cjk); border-left: 1px solid var(--glyph-cjk-border); border-right: 1px solid var(--glyph-cjk-border); }
              .sample-engine .glyph.cjk-punct { background: var(--glyph-punct); border-left: 1px solid var(--glyph-punct-border); border-right: 1px solid var(--glyph-punct-border); }
              .sample-engine .glyph.latin { background: var(--glyph-latin); border-left: 1px solid var(--glyph-latin-border); border-right: 1px solid var(--glyph-latin-border); }
              .sample-engine .glyph .ch { font-size: 16px; line-height: 1; transform: translateY(0); }
              .sample-engine .glyph.cjk-punct .ch.has-measured-layer { color: transparent; }
              .sample-engine .glyph .measured-layer { position: absolute; inset: 0; overflow: visible; pointer-events: none; }
              .sample-engine .glyph .measured-layer path { fill: var(--fg); }
              .sample-engine .glyph .measured-layer rect { stroke: var(--ink); fill: var(--ink-fill); vector-effect: non-scaling-stroke; }
              .sample-engine .repair-tag { position: absolute; right: -6px; transform: translate(100%, 0); padding: 1px 6px; font-size: 10px; background: rgba(196, 80, 60, 0.12); color: #b03a2e; border: 1px solid rgba(196, 80, 60, 0.45); border-radius: 3px; white-space: nowrap; pointer-events: none; }
              .sample-engine .justify-tag { position: absolute; right: -6px; transform: translate(100%, 0); padding: 1px 6px; font-size: 10px; background: rgba(60, 140, 90, 0.10); color: #2e7d4f; border: 1px solid rgba(60, 140, 90, 0.40); border-radius: 3px; white-space: nowrap; pointer-events: none; }
              .sample-engine .max-width-rule { position: absolute; top: 0; bottom: 0; width: 1px; background: rgba(80, 120, 200, 0.3); pointer-events: none; }
              .legend { display: flex; gap: 12px; font-size: 11px; color: var(--muted); margin-top: 8px; flex-wrap: wrap; }
              .legend .swatch { display: inline-block; width: 10px; height: 10px; vertical-align: middle; margin-right: 4px; border: 1px solid currentColor; }
              .legend .baseline-sw { background: transparent; border-top: 1px solid var(--baseline); border-left: none; border-right: none; border-bottom: none; height: 0; width: 14px; }
              .legend .linebox-sw { background: transparent; border-top: 1px dotted var(--linebox); border-left: none; border-right: none; border-bottom: none; height: 0; width: 14px; }
              details { margin-top: 14px; }
              summary { cursor: pointer; font-size: 13px; color: var(--muted); user-select: none; }
              .metrics { display: flex; gap: 10px; flex-wrap: wrap; font-size: 12px; margin: 10px 0; }
              .metric { background: var(--panel); border: 1px solid var(--rule); border-radius: 4px; padding: 4px 8px; }
              pre { margin: 8px 0 0; padding: 12px; overflow: auto; background: #20242a; color: #eef2f7; border-radius: 6px; font-size: 12px; }
            </style>
            """.trimIndent(),
        )
        appendLine("</head>")
        appendLine("<body><main>")
        appendLine("<h1>提椠 layout playground</h1>")
        appendLine(
            "<p class=\"intro\">每个 fixture 显示三栏：浏览器默认排版 · 提椠 greedy · 提椠 lookahead。" +
                "中间和右侧是提椠引擎按真实算出的 cluster 位置渲染：每个矩形是一个 cluster，宽度 = " +
                "<code>cluster.advance</code>，纵向位置 = <code>line.top / bottom</code>。" +
                "红线 = baseline；蓝色点线 = line box 上下沿；右上红色 <code>↻ 标签</code>表示该行触发了 kinsoku repair。" +
                "lookahead 会用更小的窗口（默认 ±1 cluster）扫多种断行，挑 raggedness + repair penalty 最低的那种。" +
                "当前 shaper：<code>${shaperMode.id.escapeHtml()}</code>（${shaperMode.description.escapeHtml()}）。" +
                "如需回到 deterministic stub，对 playground 设置 <code>TIQIAN_PLAYGROUND_SHAPER=stub</code>。</p>",
        )
        items.forEach { item -> appendLine(item.renderSection()) }
        appendLine("</main></body></html>")
    }

private fun PlaygroundReportItem.renderSection(): String {
    val maxWidth = fixture.constraints.maxWidth
    val spacing = greedy.debug.spacingDecisions

    return buildString {
        appendLine("<section>")
        appendLine("<h2>${fixture.id.escapeHtml()}</h2>")
        appendLine("<p class=\"notes\">${fixture.notes.escapeHtml()}</p>")

        appendLine("<div class=\"compare\">")

        // Browser default column.
        appendLine("<div>")
        appendLine("<div class=\"col-label\">browser default · width ${maxWidth.oneDecimal()}px · font 16px</div>")
        appendLine("<div class=\"sample-browser\" style=\"width:${maxWidth.oneDecimal()}px\">${fixture.text.escapeHtml()}</div>")
        appendLine("</div>")

        // Tiqian engine columns.
        appendLine(renderEngineColumn("Tiqian greedy", greedy, maxWidth))
        appendLine(renderEngineColumn("Tiqian lookahead", lookahead, maxWidth))

        appendLine("</div>") // .compare
        appendLine(renderLegend())

        // Metadata block (collapsible).
        appendLine("<details>")
        appendLine(
            "<summary>metadata · greedy size ${greedy.size.width.oneDecimal()}×${greedy.size.height.oneDecimal()} · lookahead size ${lookahead.size.width.oneDecimal()}×${lookahead.size.height.oneDecimal()} · spacing ${spacing.size}</summary>",
        )
        appendLine(renderEngineMetadata("greedy", greedy))
        appendLine(renderEngineMetadata("lookahead", lookahead))
        if (spacing.isNotEmpty()) {
            appendLine("<pre>${spacing.joinToString("\n") { it.compactDump() }.escapeHtml()}</pre>")
        }
        appendLine("</details>")

        appendLine("</section>")
    }
}

private fun renderEngineColumn(label: String, result: LayoutResult, maxWidth: Float): String {
    val totalHeight = if (result.lines.isEmpty()) result.size.height else result.lines.last().bottom
    val repairs = result.debug.lineDecisions.count { it.repair != null }
    return buildString {
        appendLine("<div>")
        appendLine(
            "<div class=\"col-label\">${label.escapeHtml()} · width ${maxWidth.oneDecimal()}px · lines ${result.lines.size}${if (repairs > 0) " · repairs $repairs" else ""}</div>",
        )
        appendLine(
            "<div class=\"sample-engine\" style=\"width:${maxWidth.oneDecimal()}px; height:${totalHeight.oneDecimal()}px\">",
        )
        result.lines.forEachIndexed { lineIndex, line ->
            appendLine(renderLineOverlays(line, lineIndex, result.lines.lastIndex))
            val lineClusters = result.clusters.filter {
                it.range.start >= line.range.start && it.range.end <= line.range.end
            }
            var x = 0f
            lineClusters.forEach { cluster ->
                val role = result.debug.fontDecisions.firstOrNull { it.range == cluster.range }?.role
                appendLine(
                    renderGlyphBox(
                        cluster = cluster,
                        role = role,
                        inkOverlays = result.debug.punctuationDecisions.inkOverlaysFor(cluster),
                        fontSize = result.input.textStyle.fontSize,
                        leftPx = x,
                        line = line,
                    ),
                )
                x += cluster.advance
            }
            val repair = result.debug.lineDecisions.getOrNull(lineIndex)?.repair
            if (repair != null) {
                appendLine(
                    "<div class=\"repair-tag\" style=\"top:${line.top.oneDecimal()}px\">↻ $repair</div>",
                )
            }
            val justification = result.debug.justificationDecisions.firstOrNull { it.lineRange == line.range }
            if (justification != null && justification.allocations.isNotEmpty()) {
                val kinds = justification.allocations.map { it.kind }.distinct().joinToString("+")
                val totalDelta = justification.allocations.sumOf { it.delta.toDouble() }.toFloat()
                appendLine(
                    "<div class=\"justify-tag\" style=\"top:${(line.top + 18f).oneDecimal()}px\">↔ ${kinds} +${totalDelta.oneDecimal()}</div>",
                )
            }
        }
        appendLine("</div>")
        appendLine("</div>")
    }
}

private fun renderEngineMetadata(label: String, result: LayoutResult): String =
    buildString {
        appendLine("<div class=\"col-label\">${label.escapeHtml()}</div>")
        if (result.debug.shapingDecisions.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.shapingDecisions.forEach { decision ->
                appendLine(
                    "<span class=\"metric\">shape ${decision.range.start}-${decision.range.end} " +
                        "'${decision.displayText.escapeHtml()}' ${decision.advance.oneDecimal()} ${decision.source}</span>",
                )
            }
            appendLine("</div>")
        }
        if (result.debug.punctuationDecisions.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.punctuationDecisions.forEach { decision ->
                val ink = decision.inkBounds?.let { " ink=${it.compactDump()}" } ?: ""
                val inkMeasures = buildList {
                    add("floor=${decision.policyBodyFloor.oneDecimal()}")
                    decision.inkWidth?.let { add("inkW=${it.oneDecimal()}") }
                    decision.inkCenter?.let { add("inkC=${it.oneDecimal()}") }
                }.joinToString(" ")
                val sourceTag = decision.geometrySource
                appendLine(
                    "<span class=\"metric\">punct ${decision.range.start}-${decision.range.end} " +
                        "'${decision.char.toString().escapeHtml()}' body=${decision.bodyWidth.oneDecimal()} " +
                        "lead=${decision.leadingGlueNatural.oneDecimal()} trail=${decision.trailingGlueNatural.oneDecimal()} " +
                        "$inkMeasures $sourceTag$ink</span>",
                )
            }
            appendLine("</div>")
        }
        if (result.debug.geometryDecisions.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.geometryDecisions.forEach { decision ->
                appendLine(
                    "<span class=\"metric\">geom ${decision.range.start}-${decision.range.end} " +
                        "'${decision.displayText.escapeHtml()}' body=${decision.bodyWidth.oneDecimal()} " +
                        "lead=${decision.leadingGlueConsumed.oneDecimal()}/${decision.leadingGlueNatural.oneDecimal()} " +
                        "trail=${decision.trailingGlueConsumed.oneDecimal()}/${decision.trailingGlueNatural.oneDecimal()} " +
                        "justify=+${decision.justificationDelta.oneDecimal()} resolved=${decision.resolvedAdvance.oneDecimal()}</span>",
                )
            }
            appendLine("</div>")
        }
        result.lines.forEachIndexed { lineIndex, line ->
            val repair = result.debug.lineDecisions.getOrNull(lineIndex)
            val justification = result.debug.justificationDecisions.firstOrNull { it.lineRange == line.range }
            appendLine("<div class=\"metrics\">")
            appendLine("<span class=\"metric\">line $lineIndex</span>")
            appendLine("<span class=\"metric\">range ${line.range.start}-${line.range.end}</span>")
            appendLine("<span class=\"metric\">natural ${line.naturalWidth.oneDecimal()}</span>")
            appendLine("<span class=\"metric\">adjusted ${line.adjustedWidth.oneDecimal()}</span>")
            appendLine("<span class=\"metric\">visual ${line.visualWidth.oneDecimal()}</span>")
            if (repair?.repair != null) {
                appendLine("<span class=\"metric\">repair ${repair.repair} (+${repair.repairPenalty})</span>")
            }
            repair?.repairDecision?.let { decision ->
                appendLine(
                    "<span class=\"metric\">reason ${decision.reasonCode} @${decision.offenderRange.start}-${decision.offenderRange.end}</span>",
                )
                decision.targetClusterIndex?.let { target ->
                    appendLine(
                        "<span class=\"metric\">target cluster $target shrink ${decision.shrink.oneDecimal()}/${decision.availableCapacity.oneDecimal()}</span>",
                    )
                }
                decision.carriedClusterIndex?.let { carried ->
                    appendLine("<span class=\"metric\">carried cluster $carried</span>")
                }
            }
            repair?.repairCandidates?.forEach { candidate ->
                val status = if (candidate.accepted) "accepted" else "rejected:${candidate.rejectionReason}"
                val details = buildList {
                    candidate.targetClusterIndex?.let { add("target $it") }
                    candidate.carriedClusterIndex?.let { add("carried $it") }
                    if (candidate.requiredShrink > 0f || candidate.availableCapacity > 0f) {
                        add("shrink ${candidate.requiredShrink.oneDecimal()}/${candidate.availableCapacity.oneDecimal()}")
                    }
                }.joinToString(" ")
                val suffix = if (details.isEmpty()) "" else " $details"
                appendLine(
                    "<span class=\"metric\">candidate ${candidate.kind} $status$suffix</span>",
                )
            }
            if (justification != null) {
                appendLine(
                    "<span class=\"metric\">justify deficit ${justification.deficitBefore.oneDecimal()}→${justification.deficitAfter.oneDecimal()}</span>",
                )
                justification.allocations.forEach { alloc ->
                    appendLine(
                        "<span class=\"metric\">${alloc.kind} +${alloc.delta.oneDecimal()} @${alloc.clusterRange.start}-${alloc.clusterRange.end}</span>",
                    )
                }
            }
            appendLine("</div>")
        }
    }

private fun renderLineOverlays(line: LineBox, lineIndex: Int, lastIndex: Int): String {
    // line.baseline is paragraph-absolute (cumulative across lines) — matches the
    // sample-engine container's top, so it can be used as the CSS `top` directly.
    val lineBoxClass = if (lineIndex == lastIndex) "line-box last" else "line-box"
    return buildString {
        appendLine("<div class=\"$lineBoxClass\" style=\"top:${line.top.oneDecimal()}px; height:${(line.bottom - line.top).oneDecimal()}px\"></div>")
        appendLine("<div class=\"baseline\" style=\"top:${line.baseline.oneDecimal()}px\"></div>")
    }
}

private fun renderGlyphBox(
    cluster: Cluster,
    role: String?,
    inkOverlays: List<InkOverlay>,
    fontSize: Float,
    leftPx: Float,
    line: LineBox,
): String {
    val klass = when {
        role == "CjkPunctuation" || cluster.text.any { it.isCjkPunctuationLike() } -> "glyph cjk-punct"
        role == "LatinText" -> "glyph latin"
        role == "CjkText" -> "glyph cjk-text"
        else -> "glyph cjk-text"
    }
    val height = line.bottom - line.top
    val baselineWithinLine = line.baseline - line.top
    return "<div class=\"$klass\" style=\"left:${leftPx.oneDecimal()}px; top:${line.top.oneDecimal()}px; width:${cluster.advance.oneDecimal()}px; height:${height.oneDecimal()}px\">" +
        inkOverlays.renderMeasuredLayer(
            width = cluster.advance,
            height = height,
            baselineWithinLine = baselineWithinLine,
            role = role,
            fontSize = fontSize,
        ) +
        "<span class=\"ch${if (inkOverlays.isNotEmpty()) " has-measured-layer" else ""}\">${cluster.displayText.escapeHtml()}</span>" +
        "</div>"
}

private data class InkOverlay(
    val xOffset: Float,
    val char: Char,
    val advance: Float,
    val bounds: Rect,
)

private fun List<PunctuationDecisionInfo>.inkOverlaysFor(cluster: Cluster): List<InkOverlay> {
    val decisions = filter { decision ->
        decision.range.start >= cluster.range.start && decision.range.end <= cluster.range.end
    }.sortedBy { it.range.start }
    var x = 0f
    return decisions.mapNotNull { decision ->
        val overlay = decision.inkBounds?.let { bounds ->
            InkOverlay(
                xOffset = x,
                char = decision.char,
                advance = decision.advance,
                bounds = bounds,
            )
        }
        x += decision.advance
        overlay
    }
}

private fun List<InkOverlay>.renderMeasuredLayer(
    width: Float,
    height: Float,
    baselineWithinLine: Float,
    role: String?,
    fontSize: Float,
): String {
    if (isEmpty()) return ""
    return buildString {
        append(
            "<svg class=\"measured-layer\" viewBox=\"0 0 ${width.oneDecimal()} ${height.oneDecimal()}\" " +
                "width=\"${width.oneDecimal()}\" height=\"${height.oneDecimal()}\" aria-hidden=\"true\">",
        )
        this@renderMeasuredLayer.forEach { overlay ->
            val xOffset = overlay.xOffset
            val bounds = overlay.bounds
            val pathData = overlay.char.awtGlyphPathData(
                x = xOffset,
                baseline = baselineWithinLine,
                role = role,
                fontSize = fontSize,
            )
            append(
                "<path d=\"${pathData.escapeHtml()}\" />",
            )
            append(
                "<rect x=\"${(xOffset + bounds.left).oneDecimal()}\" " +
                    "y=\"${(baselineWithinLine + bounds.top).oneDecimal()}\" " +
                    "width=\"${bounds.width.oneDecimal()}\" height=\"${bounds.height.oneDecimal()}\" />",
            )
        }
        append("</svg>")
    }
}

private val fontRenderContext = FontRenderContext(AffineTransform(), true, true)

private fun Char.awtGlyphPathData(
    x: Float,
    baseline: Float,
    role: String?,
    fontSize: Float,
): String {
    val font = Font(role.awtLogicalFamily(), Font.PLAIN, 1).deriveFont(fontSize)
    val glyphVector = font.layoutGlyphVector(
        fontRenderContext,
        charArrayOf(this),
        0,
        1,
        Font.LAYOUT_LEFT_TO_RIGHT,
    )
    return glyphVector
        .getGlyphOutline(0, x, baseline)
        .toSvgPathData()
}

private fun String?.awtLogicalFamily(): String =
    when (this) {
        "CjkText",
        "CjkPunctuation",
        -> Font.SERIF

        else -> Font.SANS_SERIF
    }

private fun java.awt.Shape.toSvgPathData(): String {
    val iterator = getPathIterator(null)
    val coords = FloatArray(6)
    return buildString {
        while (!iterator.isDone) {
            when (iterator.currentSegment(coords)) {
                PathIterator.SEG_MOVETO -> append("M ${coords[0].pathNumber()} ${coords[1].pathNumber()} ")
                PathIterator.SEG_LINETO -> append("L ${coords[0].pathNumber()} ${coords[1].pathNumber()} ")
                PathIterator.SEG_QUADTO -> append(
                    "Q ${coords[0].pathNumber()} ${coords[1].pathNumber()} " +
                        "${coords[2].pathNumber()} ${coords[3].pathNumber()} ",
                )
                PathIterator.SEG_CUBICTO -> append(
                    "C ${coords[0].pathNumber()} ${coords[1].pathNumber()} " +
                        "${coords[2].pathNumber()} ${coords[3].pathNumber()} " +
                        "${coords[4].pathNumber()} ${coords[5].pathNumber()} ",
                )
                PathIterator.SEG_CLOSE -> append("Z ")
            }
            iterator.next()
        }
    }.trim()
}

private fun renderLegend(): String =
    """
    <div class="legend">
      <span><span class="swatch" style="background: var(--glyph-cjk); color: var(--glyph-cjk-border)"></span>CJK text</span>
      <span><span class="swatch" style="background: var(--glyph-punct); color: var(--glyph-punct-border)"></span>CJK punct</span>
      <span><span class="swatch" style="background: var(--glyph-latin); color: var(--glyph-latin-border)"></span>Latin</span>
      <span><span class="swatch" style="background: var(--ink-fill); color: var(--ink)"></span>ink bounds</span>
      <span><span class="swatch baseline-sw" style="color: var(--baseline)"></span>baseline</span>
      <span><span class="swatch linebox-sw" style="color: var(--linebox)"></span>line box</span>
    </div>
    """.trimIndent()

private fun Char.isCjkPunctuationLike(): Boolean =
    this in "，、。；：！？“”‘’（）《》〈〉「」『』·・‧•～…⋯—⸺"

private fun Float.oneDecimal(): String =
    String.format(Locale.US, "%.1f", this)

private fun Float.pathNumber(): String =
    String.format(Locale.US, "%.3f", this).trimEnd('0').trimEnd('.')

private fun Rect.compactDump(): String =
    "[${left.oneDecimal()},${top.oneDecimal()},${right.oneDecimal()},${bottom.oneDecimal()}]"

private fun String.escapeHtml(): String =
    replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
