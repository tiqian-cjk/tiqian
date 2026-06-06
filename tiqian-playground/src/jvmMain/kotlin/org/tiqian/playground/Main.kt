package org.tiqian.playground

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.SpacingDecisionInfo
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.test.EarlyLayoutFixtures
import org.tiqian.text.test.LayoutFixture
import java.io.File
import java.util.Locale

fun main() {
    val engine = ExplainableStubParagraphLayoutEngine()
    val reportItems = mutableListOf<PlaygroundReportItem>()

    EarlyLayoutFixtures.all.forEach { fixture ->
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(fixture.text),
                constraints = fixture.constraints,
            ),
        )

        reportItems += PlaygroundReportItem(fixture, result)
        printFixtureDump(fixture, result)
    }

    val reportFile = File("build/reports/tiqian-layout-playground/index.html")
    reportFile.parentFile.mkdirs()
    reportFile.writeText(renderHtmlReport(reportItems))
    println()
    println("HTML report: ${reportFile.absolutePath}")
}

private data class PlaygroundReportItem(
    val fixture: LayoutFixture,
    val result: LayoutResult,
)

private fun printFixtureDump(fixture: LayoutFixture, result: LayoutResult) {
    val totalNatural = result.lines.sumOf { it.naturalWidth.toDouble() }.toFloat()
    val totalAdjusted = result.lines.sumOf { it.adjustedWidth.toDouble() }.toFloat()

    println("${fixture.id}:")
    println("  text=${fixture.text}")
    println("  size=${result.size.width.oneDecimal()}x${result.size.height.oneDecimal()} lines=${result.lines.size} natural-sum=${totalNatural.oneDecimal()} adjusted-sum=${totalAdjusted.oneDecimal()}")
    result.lines.forEachIndexed { lineIndex, line ->
        val lineClusters = result.clusters.filter { it.range.start >= line.range.start && it.range.end <= line.range.end }
        println(
            "  line[$lineIndex] natural=${line.naturalWidth.oneDecimal()} adjusted=${line.adjustedWidth.oneDecimal()} " +
                "baseline=${line.baseline.oneDecimal()} top=${line.top.oneDecimal()} bottom=${line.bottom.oneDecimal()}",
        )
        println("    clusters=${lineClusters.joinToString(" | ") { it.compactDump() }}")
    }
    if (result.debug.spacingDecisions.isNotEmpty()) {
        println("  spacing:")
        result.debug.spacingDecisions.forEach { println("    ${it.compactDump()}") }
    }
    println()
}

private fun SpacingDecisionInfo.compactDump(): String =
    "${range.start}-${range.end} '$leftChar$rightChar' " +
        "naturalInner=${naturalInnerGlue.oneDecimal()} adjustedInner=${adjustedInnerGlue.oneDecimal()} " +
        "reduction=${reduction.oneDecimal()} target=${reductionTargetRange.start}-${reductionTargetRange.end} $reason"

private fun Cluster.compactDump(): String =
    "${range.start}-${range.end} '$displayText' ${advance.oneDecimal()} $fontKey"

private fun renderHtmlReport(items: List<PlaygroundReportItem>): String =
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
              }
              body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--fg); }
              main { max-width: 1280px; margin: 0 auto; padding: 32px 24px 64px; }
              h1 { font-size: 28px; margin: 0 0 8px; }
              .intro { color: var(--muted); margin: 0 0 24px; font-size: 14px; max-width: 80ch; }
              section { border-top: 1px solid var(--rule); padding: 24px 0 32px; }
              h2 { font-size: 18px; margin: 0 0 4px; }
              .notes { margin: 0 0 14px; color: var(--muted); font-size: 13px; }
              .compare { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; align-items: start; margin: 12px 0 14px; }
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
              .sample-engine .repair-tag { position: absolute; right: -6px; transform: translate(100%, 0); padding: 1px 6px; font-size: 10px; background: rgba(196, 80, 60, 0.12); color: #b03a2e; border: 1px solid rgba(196, 80, 60, 0.45); border-radius: 3px; white-space: nowrap; pointer-events: none; }
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
            "<p class=\"intro\">每个 fixture 显示两栏：左侧是浏览器在相同宽度下的默认排版结果（没有走提椠引擎），" +
                "右侧是提椠引擎计算出的 cluster 位置——每个矩形是引擎决定的一个 cluster，宽度 = " +
                "<code>cluster.advance</code>，纵向位置 = <code>line.top / bottom</code>。红线是 baseline、" +
                "蓝色点线是 line box 上下沿。Latin 字 cluster 在 stub 实现里按 1em/字符计宽，所以 Latin 文字会从 cluster 框里溢出——这是 stub 故意暴露的差异。</p>",
        )
        items.forEach { item -> appendLine(item.renderSection()) }
        appendLine("</main></body></html>")
    }

private fun PlaygroundReportItem.renderSection(): String {
    val totalNatural = result.lines.sumOf { it.naturalWidth.toDouble() }.toFloat()
    val totalAdjusted = result.lines.sumOf { it.adjustedWidth.toDouble() }.toFloat()
    val spacing = result.debug.spacingDecisions
    val maxWidth = fixture.constraints.maxWidth
    val totalHeight = if (result.lines.isEmpty()) result.size.height else result.lines.last().bottom

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

        // Tiqian engine column.
        appendLine("<div>")
        appendLine("<div class=\"col-label\">Tiqian engine · width ${maxWidth.oneDecimal()}px · lines ${result.lines.size}</div>")
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
                appendLine(renderGlyphBox(cluster, role, leftPx = x, line = line))
                x += cluster.advance
            }
            val repair = result.debug.lineDecisions.getOrNull(lineIndex)?.repair
            if (repair != null) {
                appendLine(
                    "<div class=\"repair-tag\" style=\"top:${line.top.oneDecimal()}px\">↻ $repair</div>",
                )
            }
        }
        appendLine("</div>")
        appendLine(renderLegend())
        appendLine("</div>")

        appendLine("</div>") // .compare

        // Metadata block (collapsible).
        appendLine("<details>")
        appendLine("<summary>metadata · size ${result.size.width.oneDecimal()}×${result.size.height.oneDecimal()} · natural-sum ${totalNatural.oneDecimal()} · adjusted-sum ${totalAdjusted.oneDecimal()} · clusters ${result.clusters.size} · spacing ${spacing.size}</summary>")
        result.lines.forEachIndexed { lineIndex, line ->
            appendLine("<div class=\"metrics\">")
            appendLine("<span class=\"metric\">line $lineIndex</span>")
            appendLine("<span class=\"metric\">range ${line.range.start}-${line.range.end}</span>")
            appendLine("<span class=\"metric\">natural ${line.naturalWidth.oneDecimal()}</span>")
            appendLine("<span class=\"metric\">adjusted ${line.adjustedWidth.oneDecimal()}</span>")
            appendLine("<span class=\"metric\">baseline ${line.baseline.oneDecimal()}</span>")
            appendLine("</div>")
        }
        if (spacing.isNotEmpty()) {
            appendLine("<pre>${spacing.joinToString("\n") { it.compactDump() }.escapeHtml()}</pre>")
        }
        appendLine("</details>")

        appendLine("</section>")
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

private fun renderGlyphBox(cluster: Cluster, role: String?, leftPx: Float, line: LineBox): String {
    val klass = when {
        role == "CjkPunctuation" || cluster.text.any { it.isCjkPunctuationLike() } -> "glyph cjk-punct"
        role == "LatinText" -> "glyph latin"
        role == "CjkText" -> "glyph cjk-text"
        else -> "glyph cjk-text"
    }
    val height = line.bottom - line.top
    return "<div class=\"$klass\" style=\"left:${leftPx.oneDecimal()}px; top:${line.top.oneDecimal()}px; width:${cluster.advance.oneDecimal()}px; height:${height.oneDecimal()}px\">" +
        "<span class=\"ch\">${cluster.displayText.escapeHtml()}</span>" +
        "</div>"
}

private fun renderLegend(): String =
    """
    <div class="legend">
      <span><span class="swatch" style="background: var(--glyph-cjk); color: var(--glyph-cjk-border)"></span>CJK text</span>
      <span><span class="swatch" style="background: var(--glyph-punct); color: var(--glyph-punct-border)"></span>CJK punct</span>
      <span><span class="swatch" style="background: var(--glyph-latin); color: var(--glyph-latin-border)"></span>Latin</span>
      <span><span class="swatch baseline-sw" style="color: var(--baseline)"></span>baseline</span>
      <span><span class="swatch linebox-sw" style="color: var(--linebox)"></span>line box</span>
    </div>
    """.trimIndent()

private fun Char.isCjkPunctuationLike(): Boolean =
    this in "，、。；：！？“”‘’（）《》〈〉「」『』·・‧•～…⋯—⸺"

private fun Float.oneDecimal(): String =
    String.format(Locale.US, "%.1f", this)

private fun String.escapeHtml(): String =
    replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
