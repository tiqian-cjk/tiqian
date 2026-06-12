package ink.duo3.tiqian.playground

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.LineBox
import ink.duo3.tiqian.core.PunctuationDecisionInfo
import ink.duo3.tiqian.core.Rect
import ink.duo3.tiqian.core.SpacingDecisionInfo
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.GreedyLineBreaker
import ink.duo3.tiqian.layout.LookaheadLineBreaker
import ink.duo3.tiqian.shaping.ExplainableStubTextShaper
import ink.duo3.tiqian.shaping.TextShaper
import ink.duo3.tiqian.shaping.jvm.AwtTextShaper
import ink.duo3.tiqian.shaping.skia.SkiaTextShaper
import ink.duo3.tiqian.test.EarlyLayoutFixtures
import ink.duo3.tiqian.test.LayoutFixture
import java.awt.Color
import java.awt.Font
import java.awt.GraphicsEnvironment
import java.awt.RenderingHints
import java.awt.font.FontRenderContext
import java.awt.geom.AffineTransform
import java.awt.geom.PathIterator
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.Locale
import javax.imageio.ImageIO

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
            paragraphStyle = ink.duo3.tiqian.core.ParagraphStyle(
                lineHeight = fixture.lineHeight,
                firstLineIndentEm = fixture.firstLineIndentEm,
            ),
            decorations = fixture.decorations,
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

/**
 * Picks one CJK and one Latin AWT font and uses them to actually draw the
 * engine-computed layout into a PNG. The point of the playground is to let
 * the reader compare the engine output to the browser-default rendering;
 * everything else (overlays, boxes, ink dots, decision tags) is debug noise
 * that lives in `<details>` blocks.
 */
private object PlaygroundFontProbe {
    val cjk: String
    val latin: String

    init {
        val available = GraphicsEnvironment.getLocalGraphicsEnvironment()
            .availableFontFamilyNames.toSet()
        cjk = listOf(
            "Source Han Sans CN",
            "Source Han Sans CN VF",
            "Noto Sans CJK SC",
            "PingFang SC",
            "Hiragino Sans GB",
            "Sarasa UI SC",
            "Heiti SC",
            "STHeiti",
        ).firstOrNull { it in available } ?: Font.SERIF
        latin = listOf(
            "Inter",
            "SF Pro Text",
            "SF Pro",
            "Roboto",
            "Helvetica Neue",
        ).firstOrNull { it in available } ?: Font.SANS_SERIF
    }
}

/** Result of the raster step — the PNG plus the natural canvas dimensions in CSS pixels. */
private data class RasterResult(val dataUri: String, val widthPx: Float, val heightPx: Float)

private fun rasterizeLayoutToPngSkia(result: LayoutResult, fixture: LayoutFixture, scale: Int = 2): RasterResult {
    val maxWidth = fixture.constraints.maxWidth.coerceAtLeast(1f)
    val height = result.size.height.coerceAtLeast(16f)
    val fontSize = result.input.textStyle.fontSize
    val language = result.input.textStyle.locale

    val cjkFont = org.jetbrains.skia.Font(ink.duo3.tiqian.shaping.skia.SkiaSystemTypefaces.cjk, fontSize)
    val latinFont = org.jetbrains.skia.Font(ink.duo3.tiqian.shaping.skia.SkiaSystemTypefaces.latin, fontSize)

    // Same canvas padding logic as the AWT raster: engine line boxes use
    // CenteredCjkVisual metrics, real font ascent/descent overflow them.
    val fontAscent = maxOf(-cjkFont.metrics.ascent, -latinFont.metrics.ascent)
    val fontDescent = maxOf(cjkFont.metrics.descent, latinFont.metrics.descent)
    val engineBaseline = result.lines.firstOrNull()?.baseline ?: (fontSize / 2f)
    val engineDescent = result.lines.lastOrNull()?.let { it.bottom - it.baseline } ?: (fontSize / 2f)
    val topPad = (fontAscent - engineBaseline).coerceAtLeast(0f)
    val bottomPad = (fontDescent - engineDescent).coerceAtLeast(0f)

    val canvasWidth = maxWidth
    val canvasHeight = height + topPad + bottomPad
    val widthPx = (canvasWidth * scale).toInt().coerceAtLeast(1)
    val heightPx = (canvasHeight * scale).toInt().coerceAtLeast(1)

    val surface = org.jetbrains.skia.Surface.makeRasterN32Premul(widthPx, heightPx)
    val canvas = surface.canvas
    canvas.scale(scale.toFloat(), scale.toFloat())
    canvas.clear(-1)
    val paint = org.jetbrains.skia.Paint().apply { color = 0xFF000000.toInt() }
    val shaper = org.jetbrains.skia.shaper.Shaper.makeShaperDrivenWrapper()
    val defaultAutoSpaceGap = 0.25f * fontSize
    // Consumed leading glue shifts the glyph origin left (the blob keeps the
    // font's built-in leading blank; the engine removed it from the advance).
    val leadingConsumedByRange = result.debug.geometryDecisions
        .filter { it.leadingGlueConsumed > 0f }
        .associate { it.range to it.leadingGlueConsumed }

    for (line in result.lines) {
        val lineClusters = result.clusters.filter {
            it.range.start >= line.range.start && it.range.end <= line.range.end
        }
        var x = line.indent
        val baselineY = line.baseline + topPad
        for ((clusterIndexInLine, cluster) in lineClusters.withIndex()) {
            val role = result.debug.fontDecisions.firstOrNull {
                // Containment: segmented word clusters sit inside the
                // decision's range (see SkiaLayoutRenderer).
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role
            val font = if (role == "LatinText") latinFont else cjkFont

            val autoSpaces = result.debug.autoSpaceDecisions
                .filter { it.clusterRange == cluster.range }
            val leadingDecision = autoSpaces.firstOrNull { it.side == "leading" }
                val leadingStrip = leadingDecision?.charactersAffected ?: 0
            val trailingDecision = autoSpaces.firstOrNull { it.side == "trailing" }
                val trailingStrip = trailingDecision?.charactersAffected ?: 0
            val isLineStart = clusterIndexInLine == 0
            val isLineEnd = clusterIndexInLine == lineClusters.lastIndex
            // Insert decisions carry charactersAffected=0 but still gap.
                val leadingGap = if (leadingDecision != null && !isLineStart) defaultAutoSpaceGap else 0f
            val trailingGap = if (trailingDecision != null && !isLineEnd) defaultAutoSpaceGap else 0f
            val paintText = cluster.displayText
                .drop(leadingStrip)
                .let { if (trailingStrip > 0) it.dropLast(trailingStrip) else it }

            if (paintText.isNotEmpty()) {
                val leadingShift = leadingConsumedByRange[cluster.range] ?: 0f
                ink.duo3.tiqian.shaping.skia.shapeTextBlob(shaper, paintText, font, language)?.let { blob ->
                    canvas.drawTextBlob(blob, x + leadingGap - leadingShift, baselineY, paint)
                }
            }

            if (leadingStrip > 0 || trailingStrip > 0) {
                val paintWidth = if (paintText.isNotEmpty()) {
                    org.jetbrains.skia.TextLine.make(paintText, font).width
                } else {
                    0f
                }
                x += leadingGap + paintWidth + trailingGap
            } else {
                x += cluster.advance
            }
        }
    }

    // Emphasis dots (ADR 0018): align the dot glyph's ink centre to the
    // engine-decided anchor; topPad shifts engine canvas coords like the
    // baselines above.
    val appliedDots = result.debug.decorationDecisions.filter { it.applied }
    if (appliedDots.isNotEmpty()) {
        val dotGlyph = cjkFont.getUTF32Glyph(EMPHASIS_DOT.code)
        val dotInk = cjkFont.getBounds(shortArrayOf(dotGlyph)).firstOrNull()
        val dotBlob = ink.duo3.tiqian.shaping.skia.shapeTextBlob(shaper, EMPHASIS_DOT.toString(), cjkFont, language)
        if (dotBlob != null && dotInk != null) {
            val inkCenterX = (dotInk.left + dotInk.right) / 2f
            val inkCenterY = (dotInk.top + dotInk.bottom) / 2f
            for (dot in appliedDots) {
                canvas.drawTextBlob(dotBlob, dot.anchorX - inkCenterX, topPad + dot.anchorY - inkCenterY, paint)
            }
        }
    }

    // 示亡号 frames (ADR 0018): stroke per-line segments; continuation
    // edges (open start/end) stay undrawn.
    if (result.debug.decorationSegments.isNotEmpty()) {
        val framePaint = org.jetbrains.skia.Paint().apply {
            color = 0xFF000000.toInt()
            mode = org.jetbrains.skia.PaintMode.STROKE
            strokeWidth = (fontSize / 16f).coerceAtLeast(1f)
        }
        for (seg in result.debug.decorationSegments) {
            val t = topPad + seg.top
            val b = topPad + seg.bottom
            canvas.drawLine(seg.left, t, seg.right, t, framePaint)
            canvas.drawLine(seg.left, b, seg.right, b, framePaint)
            if (!seg.openStart) canvas.drawLine(seg.left, t, seg.left, b, framePaint)
            if (!seg.openEnd) canvas.drawLine(seg.right, t, seg.right, b, framePaint)
        }
    }

    val bytes = surface.makeImageSnapshot()
        .encodeToData(org.jetbrains.skia.EncodedImageFormat.PNG)!!
        .bytes
    val dataUri = "data:image/png;base64,${Base64.getEncoder().encodeToString(bytes)}"
    return RasterResult(dataUri = dataUri, widthPx = canvasWidth, heightPx = canvasHeight)
}

/** CLREQ 着重号 glyph: U+2022 BULLET (CLREQ allows U+25CF or U+2022). */
private const val EMPHASIS_DOT = '•'

private fun rasterizeLayoutToPng(result: LayoutResult, fixture: LayoutFixture, scale: Int = 2): RasterResult {
    val maxWidth = fixture.constraints.maxWidth.coerceAtLeast(1f)
    val height = result.size.height.coerceAtLeast(16f)
    val fontSize = result.input.textStyle.fontSize

    val cjkFont = Font(PlaygroundFontProbe.cjk, Font.PLAIN, 1).deriveFont(fontSize)
    val latinFont = Font(PlaygroundFontProbe.latin, Font.PLAIN, 1).deriveFont(fontSize)

    // Engine uses CenteredCjkVisual metrics: baseline at em/2, line height = em.
    // Real AWT fonts have asymmetric ascent/descent (≈14/4 at 16px) so glyph
    // ink overflows the engine line box top by `fontAscent - engine.ascent`
    // and the bottom by `fontDescent - engine.descent`. Pad the canvas so the
    // ink fits inside the PNG instead of getting clipped at y=0 / y=height.
    val measureCtx = FontRenderContext(AffineTransform(), true, true)
    val cjkLm = cjkFont.getLineMetrics("中", measureCtx)
    val latinLm = latinFont.getLineMetrics("Mg", measureCtx)
    val fontAscent = maxOf(cjkLm.ascent, latinLm.ascent)
    val fontDescent = maxOf(cjkLm.descent, latinLm.descent)
    val engineBaseline = result.lines.firstOrNull()?.baseline ?: (fontSize / 2f)
    val engineDescent = result.lines.lastOrNull()?.let { it.bottom - it.baseline } ?: (fontSize / 2f)
    val topPad = (fontAscent - engineBaseline).coerceAtLeast(0f)
    val bottomPad = (fontDescent - engineDescent).coerceAtLeast(0f)

    val canvasWidth = maxWidth
    val canvasHeight = height + topPad + bottomPad
    val widthPx = (canvasWidth * scale).toInt().coerceAtLeast(1)
    val heightPx = (canvasHeight * scale).toInt().coerceAtLeast(1)

    val img = BufferedImage(widthPx, heightPx, BufferedImage.TYPE_INT_ARGB)
    val g = img.createGraphics()
    try {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON)
        g.scale(scale.toDouble(), scale.toDouble())
        g.color = Color.WHITE
        g.fillRect(0, 0, (canvasWidth + 1).toInt(), (canvasHeight + 1).toInt())

        // Default autospace gap used by the engine when AutoSpacePolicy isn't
        // surfaced per-cluster. Matches ClreqProfile defaults; if a future
        // profile customises gapEm this rasterizer would over- or under-pad
        // the boundary by the difference. Acceptable for the playground.
        val defaultAutoSpaceGap = 0.25f * fontSize
        val leadingConsumedAwt = result.debug.geometryDecisions
            .filter { it.leadingGlueConsumed > 0f }
            .associate { it.range to it.leadingGlueConsumed }

        for (line in result.lines) {
            val lineClusters = result.clusters.filter {
                it.range.start >= line.range.start && it.range.end <= line.range.end
            }
            var x = line.indent
            val baselineY = line.baseline + topPad
            for ((clusterIndexInLine, cluster) in lineClusters.withIndex()) {
                val role = result.debug.fontDecisions.firstOrNull {
                // Containment: segmented word clusters sit inside the
                // decision's range (see SkiaLayoutRenderer).
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role
                g.font = when (role) {
                    "LatinText" -> latinFont
                    else -> cjkFont
                }
                g.color = Color.BLACK

                // For `text-autospace: replace`: REMOVE typed U+0020 from the
                // rendered text at CJK boundaries, replace with the autospace
                // gap. The engine reduces cluster.advance by what the shaped
                // typed spaces contributed, but the residual cluster.advance
                // doesn't perfectly track AWT's measured paint width — so we
                // step x by the painted width + leading/trailing gaps rather
                // than trust cluster.advance for stripped clusters. Engine
                // model is still correct; this is a visual-only override.
                val autoSpaces = result.debug.autoSpaceDecisions
                    .filter { it.clusterRange == cluster.range }
                val leadingDecision = autoSpaces.firstOrNull { it.side == "leading" }
                val leadingStrip = leadingDecision?.charactersAffected ?: 0
                val trailingDecision = autoSpaces.firstOrNull { it.side == "trailing" }
                val trailingStrip = trailingDecision?.charactersAffected ?: 0
                // TextAutoSpaceLineEdgeTrim: the engine removes the autospace
                // gap at line edges, so the rasterizer must not paint it.
                val isLineStart = clusterIndexInLine == 0
                val isLineEnd = clusterIndexInLine == lineClusters.lastIndex
                // Insert decisions carry charactersAffected=0 but still gap.
                val leadingGap = if (leadingDecision != null && !isLineStart) defaultAutoSpaceGap else 0f
                val trailingGap = if (trailingDecision != null && !isLineEnd) defaultAutoSpaceGap else 0f
                val paintText = cluster.displayText
                    .drop(leadingStrip)
                    .let { if (trailingStrip > 0) it.dropLast(trailingStrip) else it }

                if (paintText.isNotEmpty()) {
                    // Consumed leading glue shifts the glyph origin left (the
                    // drawn glyph keeps the font's built-in leading blank; the
                    // engine removed it from the cluster's advance).
                    val leadingShift = leadingConsumedAwt[cluster.range] ?: 0f
                    g.drawString(paintText, x + leadingGap - leadingShift, baselineY)
                }

                if (leadingStrip > 0 || trailingStrip > 0) {
                    // Override: render-time step = autospace gap + AWT-measured
                    // paint width + autospace gap. Decouples from engine's
                    // cluster.advance for this cluster, which already accounts
                    // for shaped-space variance.
                    val paintWidth = if (paintText.isNotEmpty()) {
                        g.font.getStringBounds(paintText, g.fontRenderContext).width.toFloat()
                    } else {
                        0f
                    }
                    x += leadingGap + paintWidth + trailingGap
                } else {
                    x += cluster.advance
                }
            }
        }

        // Emphasis dots — the AWT raster is the legacy debug view; a filled
        // circle approximates the dot glyph (the skia raster draws the real
        // U+2022 glyph aligned to the same engine anchor).
        val dotDiameter = fontSize * 0.22f
        for (dot in result.debug.decorationDecisions) {
            if (!dot.applied) continue
            g.fillOval(
                (dot.anchorX - dotDiameter / 2f).toInt(),
                (topPad + dot.anchorY - dotDiameter / 2f).toInt(),
                dotDiameter.toInt().coerceAtLeast(2),
                dotDiameter.toInt().coerceAtLeast(2),
            )
        }

        // 示亡号 frames; continuation edges stay undrawn.
        for (seg in result.debug.decorationSegments) {
            val t = (topPad + seg.top).toInt()
            val b = (topPad + seg.bottom).toInt()
            val l = seg.left.toInt()
            val r = seg.right.toInt()
            g.drawLine(l, t, r, t)
            g.drawLine(l, b, r, b)
            if (!seg.openStart) g.drawLine(l, t, l, b)
            if (!seg.openEnd) g.drawLine(r, t, r, b)
        }
    } finally {
        g.dispose()
    }

    val bytes = ByteArrayOutputStream().use {
        ImageIO.write(img, "PNG", it)
        it.toByteArray()
    }
    val dataUri = "data:image/png;base64,${Base64.getEncoder().encodeToString(bytes)}"
    return RasterResult(dataUri = dataUri, widthPx = canvasWidth, heightPx = canvasHeight)
}

private enum class ShaperMode(
    val id: String,
    val description: String,
) {
    JvmAwt(
        id = "jvm-awt",
        description = "JVM AWT Font.layoutGlyphVector real advance",
    ),
    Skia(
        id = "skia",
        description = "Skiko TextLine real advance + ink bounds",
    ),
    Stub(
        id = "stub",
        description = "deterministic nominal em advance",
    );

    fun createShaper(): TextShaper =
        when (this) {
            JvmAwt -> AwtTextShaper()
            Skia -> SkiaTextShaper()
            Stub -> ExplainableStubTextShaper()
        }

    companion object {
        fun fromEnvironment(): ShaperMode =
            when (System.getenv("TIQIAN_PLAYGROUND_SHAPER")?.lowercase(Locale.ROOT)) {
                "stub" -> Stub
                "skia", "skiko" -> Skia
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
    if (greedy.debug.autoSpaceDecisions.isNotEmpty()) {
        println("  autospace (paragraph-wide, identical across engines):")
        greedy.debug.autoSpaceDecisions.forEach {
            println(
                "    ${it.clusterRange.start}-${it.clusterRange.end} side=${it.side} boundary=${it.boundaryRole} " +
                    "affected=${it.charactersAffected} reduction=${it.totalReduction} ${it.reason}",
            )
        }
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
        val indentTag = if (line.indent > 0f) " indent=${line.indent.oneDecimal()}" else ""
        println(
            "    line[$lineIndex]$indentTag adjusted=${line.adjustedWidth.oneDecimal()} visual=${line.visualWidth.oneDecimal()} range=${line.range.start}-${line.range.end}$repairTag$justifyTag",
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
              .render-col { min-width: 0; }
              .col-label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 6px; }
              .sample-browser { line-height: 1; padding: 0; background: var(--panel); border: 1px dashed var(--rule); box-sizing: content-box; word-break: break-word; }
              .sample-raster { display: block; background: var(--panel); border: 1px dashed var(--rule); image-rendering: -webkit-optimize-contrast; }
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
            "<p class=\"intro\">三栏对比：<strong>浏览器默认</strong>排版 · 提椠 <strong>greedy</strong> · 提椠 <strong>lookahead</strong>。" +
                "中间和右侧都是用 AWT 按引擎计算出的位置直接绘制的 PNG——你看到的就是引擎实际产出的图像，跟浏览器渲染一对一可比。" +
                "决策细节（line decisions、spacing、justification、几何账本等）折叠在每个 fixture 下方 <code>decisions</code> 块里，按需展开。" +
                "当前 shaper：<code>${shaperMode.id.escapeHtml()}</code>（${shaperMode.description.escapeHtml()}）；" +
                "切回 deterministic stub 用 <code>TIQIAN_PLAYGROUND_SHAPER=stub</code>。</p>",
        )
        items.forEach { item -> appendLine(item.renderSection(shaperMode)) }
        appendLine("</main></body></html>")
    }

private fun PlaygroundReportItem.renderSection(shaperMode: ShaperMode): String {
    val maxWidth = fixture.constraints.maxWidth
    val spacing = greedy.debug.spacingDecisions
    val fontSize = greedy.input.textStyle.fontSize

    return buildString {
        appendLine("<section>")
        appendLine("<h2>${fixture.id.escapeHtml()}</h2>")
        appendLine("<p class=\"notes\">${fixture.notes.escapeHtml()}</p>")

        appendLine("<div class=\"compare\">")

        // Browser default column.
        appendLine("<div class=\"render-col\">")
        appendLine(
            "<div class=\"col-label\">browser default · ${maxWidth.oneDecimal()}px · ${fontSize.oneDecimal()}px font</div>",
        )
        appendLine(
            "<div class=\"sample-browser\" style=\"width:${maxWidth.oneDecimal()}px; font-size:${fontSize.oneDecimal()}px\">${fixture.text.escapeHtml()}</div>",
        )
        appendLine("</div>")

        // Tiqian engine columns — actual rasterized output from the engine.
        appendLine(renderRasterColumn("Tiqian greedy", greedy, fixture, shaperMode))
        appendLine(renderRasterColumn("Tiqian lookahead", lookahead, fixture, shaperMode))

        appendLine("</div>") // .compare

        // Decision metadata is collapsed by default — read on demand only.
        appendLine("<details>")
        appendLine(
            "<summary>decisions · greedy size ${greedy.size.width.oneDecimal()}×${greedy.size.height.oneDecimal()} · lookahead size ${lookahead.size.width.oneDecimal()}×${lookahead.size.height.oneDecimal()} · spacing ${spacing.size}</summary>",
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

private fun renderRasterColumn(
    label: String,
    result: LayoutResult,
    fixture: LayoutFixture,
    shaperMode: ShaperMode,
): String {
    val repairs = result.debug.lineDecisions.count { it.repair != null }
    val justifications = result.debug.justificationDecisions.count { it.allocations.isNotEmpty() }
    val summary = buildList {
        add("${result.lines.size} lines")
        if (repairs > 0) add("$repairs repairs")
        if (justifications > 0) add("$justifications justify")
    }.joinToString(" · ")
    // The raster must use the same measurement stack as the engine: in skia
    // mode an AWT drawString would paint Western glyph forms while the engine
    // stepped by the locl CJK advances (visible as a hole after `——`).
    val raster = when (shaperMode) {
        ShaperMode.Skia -> rasterizeLayoutToPngSkia(result, fixture)
        else -> rasterizeLayoutToPng(result, fixture)
    }

    return buildString {
        appendLine("<div class=\"render-col\">")
        appendLine("<div class=\"col-label\">${label.escapeHtml()} · ${summary.escapeHtml()}</div>")
        appendLine(
            "<img class=\"sample-raster\" src=\"${raster.dataUri}\" " +
                "style=\"width:${raster.widthPx.oneDecimal()}px; height:${raster.heightPx.oneDecimal()}px\" " +
                "alt=\"${label.escapeHtml()} raster\">",
        )
        appendLine("</div>")
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
            var x = line.indent
            lineClusters.forEach { cluster ->
                val role = result.debug.fontDecisions.firstOrNull {
                // Containment: segmented word clusters sit inside the
                // decision's range (see SkiaLayoutRenderer).
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role
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
                val noBounds = if (decision.glyphsWithoutInkBounds > 0) {
                    " noBounds=${decision.glyphsWithoutInkBounds}/${decision.glyphCount}"
                } else {
                    ""
                }
                appendLine(
                    "<span class=\"metric\">shape ${decision.range.start}-${decision.range.end} " +
                        "'${decision.displayText.escapeHtml()}' ${decision.advance.oneDecimal()} ${decision.source}$noBounds</span>",
                )
            }
            appendLine("</div>")
        }
        if (result.debug.autoSpaceDecisions.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.autoSpaceDecisions.forEach { decision ->
                appendLine(
                    "<span class=\"metric\">aspace ${decision.clusterRange.start}-${decision.clusterRange.end} " +
                        "side=${decision.side} boundary=${decision.boundaryRole} affected=${decision.charactersAffected} " +
                        "reduction=${decision.totalReduction.oneDecimal()}</span>",
                )
            }
            appendLine("</div>")
        }
        if (result.debug.decorationDecisions.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.decorationDecisions.forEach { decision ->
                appendLine(
                    "<span class=\"metric\">deco ${decision.clusterRange.start}-${decision.clusterRange.end} " +
                        "'${decision.sourceText.escapeHtml()}' ${decision.kind} applied=${decision.applied} " +
                        "anchor=${decision.anchorX.oneDecimal()},${decision.anchorY.oneDecimal()} ${decision.reason}</span>",
                )
            }
            appendLine("</div>")
        }
        if (result.debug.decorationSegments.isNotEmpty()) {
            appendLine("<div class=\"metrics\">")
            result.debug.decorationSegments.forEach { seg ->
                appendLine(
                    "<span class=\"metric\">decobox ${seg.sourceRange.start}-${seg.sourceRange.end} ${seg.kind} " +
                        "line=${seg.lineIndex} rect=${seg.left.oneDecimal()},${seg.top.oneDecimal()}," +
                        "${seg.right.oneDecimal()},${seg.bottom.oneDecimal()} ${seg.reason}</span>",
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
                    decision.haltAdvance?.let { add("halt=${it.oneDecimal()}") }
                    decision.inkWidth?.let { add("inkW=${it.oneDecimal()}") }
                    decision.inkCenter?.let { add("inkC=${it.oneDecimal()}") }
                }.joinToString(" ")
                val sourceTag = decision.geometrySource
                val fallback = decision.inkBoundsFallback?.let { " fallback=$it" } ?: ""
                val haltWarn = decision.haltValidation?.let { " haltWarn=$it" } ?: ""
                appendLine(
                    "<span class=\"metric\">punct ${decision.range.start}-${decision.range.end} " +
                        "'${decision.char.toString().escapeHtml()}' body=${decision.bodyWidth.oneDecimal()} " +
                        "lead=${decision.leadingGlueNatural.oneDecimal()} trail=${decision.trailingGlueNatural.oneDecimal()} " +
                        "$inkMeasures $sourceTag$fallback$haltWarn$ink</span>",
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
            if (line.indent > 0f) {
                appendLine("<span class=\"metric\">indent ${line.indent.oneDecimal()}</span>")
            }
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
