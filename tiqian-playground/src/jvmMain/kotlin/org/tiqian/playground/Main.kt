package org.tiqian.playground

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.test.LayoutFixture
import org.tiqian.text.test.EarlyLayoutFixtures
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
    val line = result.lines.singleOrNull()
    val naturalWidth = line?.naturalWidth ?: result.size.width
    val adjustedWidth = line?.adjustedWidth ?: result.size.width

    println("${fixture.id}:")
    println("  text=${fixture.text}")
    println("  width natural=${naturalWidth.oneDecimal()} adjusted=${adjustedWidth.oneDecimal()} result=${result.size.width.oneDecimal()}")
    println("  clusters=${result.clusters.joinToString(" | ") { it.compactDump() }}")
    if (result.debug.punctuationSpacingDecisions.isNotEmpty()) {
        println("  spacing:")
        result.debug.punctuationSpacingDecisions.forEach { println("    $it") }
    }
    println()
}

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
              body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f7f7f4; color: #1f2328; }
              main { max-width: 1120px; margin: 0 auto; padding: 32px 24px 48px; }
              h1 { font-size: 28px; margin: 0 0 24px; }
              section { border-top: 1px solid #d8d4ca; padding: 24px 0 28px; }
              h2 { font-size: 18px; margin: 0 0 8px; }
              p { margin: 0 0 12px; color: #596168; }
              .sample { font-size: 24px; line-height: 1.6; margin: 8px 0 16px; }
              .metrics { display: flex; gap: 12px; flex-wrap: wrap; font-size: 13px; margin-bottom: 14px; }
              .metric { background: #ece8df; border: 1px solid #d6d0c4; border-radius: 6px; padding: 6px 8px; }
              .clusters { display: flex; align-items: stretch; gap: 2px; min-height: 62px; margin: 12px 0; }
              .cluster { box-sizing: border-box; min-width: 24px; border: 1px solid #9fb3c8; background: #dce9f5; border-radius: 4px; padding: 6px; overflow: hidden; }
              .cluster.punctuation { border-color: #c39a54; background: #f4dfb7; }
              .cluster .glyph { display: block; font-size: 18px; white-space: nowrap; }
              .cluster .meta { display: block; font-size: 11px; color: #596168; white-space: nowrap; }
              pre { margin: 8px 0 0; padding: 12px; overflow: auto; background: #20242a; color: #eef2f7; border-radius: 6px; font-size: 12px; }
            </style>
            """.trimIndent(),
        )
        appendLine("</head>")
        appendLine("<body><main>")
        appendLine("<h1>提椠 layout playground</h1>")
        items.forEach { item -> appendLine(item.renderSection()) }
        appendLine("</main></body></html>")
    }

private fun PlaygroundReportItem.renderSection(): String {
    val line = result.lines.singleOrNull()
    val naturalWidth = line?.naturalWidth ?: result.size.width
    val adjustedWidth = line?.adjustedWidth ?: result.size.width
    val spacing = result.debug.punctuationSpacingDecisions

    return buildString {
        appendLine("<section>")
        appendLine("<h2>${fixture.id.escapeHtml()}</h2>")
        appendLine("<p>${fixture.notes.escapeHtml()}</p>")
        appendLine("<div class=\"sample\">${fixture.text.escapeHtml()}</div>")
        appendLine("<div class=\"metrics\">")
        appendLine("<span class=\"metric\">natural ${naturalWidth.oneDecimal()}</span>")
        appendLine("<span class=\"metric\">adjusted ${adjustedWidth.oneDecimal()}</span>")
        appendLine("<span class=\"metric\">result ${result.size.width.oneDecimal()}</span>")
        appendLine("<span class=\"metric\">clusters ${result.clusters.size}</span>")
        appendLine("<span class=\"metric\">spacing decisions ${spacing.size}</span>")
        appendLine("</div>")
        appendLine("<div class=\"clusters\">")
        result.clusters.forEach { cluster -> appendLine(cluster.renderCluster()) }
        appendLine("</div>")
        if (spacing.isNotEmpty()) {
            appendLine("<pre>${spacing.joinToString("\n").escapeHtml()}</pre>")
        }
        appendLine("</section>")
    }
}

private fun Cluster.renderCluster(): String {
    val classes = if (fontKey == "cjk-primary" && text != displayText || text.any { it.isPunctuationLike() }) {
        "cluster punctuation"
    } else {
        "cluster"
    }
    val widthPx = (advance * 3f).coerceAtLeast(24f)
    return "<div class=\"$classes\" style=\"width:${widthPx.oneDecimal()}px\">" +
        "<span class=\"glyph\">${displayText.escapeHtml()}</span>" +
        "<span class=\"meta\">${range.start}-${range.end}</span>" +
        "<span class=\"meta\">${advance.oneDecimal()}</span>" +
        "</div>"
}

private fun Char.isPunctuationLike(): Boolean =
    this in "，、。；：！？“”‘’（）《》〈〉「」『』·・‧•～~-/／…⋯—⸺"

private fun Float.oneDecimal(): String =
    String.format(Locale.US, "%.1f", this)

private fun String.escapeHtml(): String =
    replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
