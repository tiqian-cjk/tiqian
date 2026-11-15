package org.tiqian.apple.coretext

import kotlinx.cinterop.CValue
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.cValue
import kotlinx.cinterop.convert
import kotlinx.cinterop.get
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.set
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.ColorSpan
import org.tiqian.core.LayoutResult
import org.tiqian.core.Link
import org.tiqian.core.Underline
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.positionedClusters
import org.tiqian.core.positionedRichTextSegments
import org.tiqian.core.richTextDecorationLineY
import org.tiqian.core.richTextDecorationSegments
import org.tiqian.font.fontRoleNameUsesLatinFace
import org.tiqian.shaping.coretext.CoreTextSupport
import platform.CoreFoundation.CFArrayGetCount
import platform.CoreFoundation.CFArrayGetValueAtIndex
import platform.CoreGraphics.CGContextFillEllipseInRect
import platform.CoreGraphics.CGContextFillPath
import platform.CoreGraphics.CGContextFillRect
import platform.CoreGraphics.CGContextAddPath
import platform.CoreGraphics.CGContextRef
import platform.CoreGraphics.CGContextReplacePathWithStrokedPath
import platform.CoreGraphics.CGContextRestoreGState
import platform.CoreGraphics.CGContextSaveGState
import platform.CoreGraphics.CGContextSetLineWidth
import platform.CoreGraphics.CGContextSetRGBFillColor
import platform.CoreGraphics.CGGlyphVar
import platform.CoreGraphics.CGPathAddQuadCurveToPoint
import platform.CoreGraphics.CGPathCreateMutable
import platform.CoreGraphics.CGPathMoveToPoint
import platform.CoreGraphics.CGPathRelease
import platform.CoreGraphics.CGPoint
import platform.CoreGraphics.CGRect
import platform.CoreText.CTFontDrawGlyphs
import platform.CoreText.CTFontRef
import platform.CoreText.CTLineGetGlyphRuns
import platform.CoreText.CTRunGetGlyphCount
import platform.CoreText.CTRunGetGlyphs
import platform.CoreText.CTRunGetPositions
import platform.CoreText.CTRunRef
private const val WAVY_HALF_WAVE_EM = 0.20
private const val WAVY_AMPLITUDE_EM = 0.06
private const val WAVY_ENDPOINT_EPSILON_PX = 0.01
private const val INTERLINEAR_SKIP_INK_CLEARANCE_EM = 0.10f
private const val INTERLINEAR_SKIP_INK_CLEARANCE_MAX_PX = 13f

/**
 * Draws a Tiqian [LayoutResult] into a `CGContext` via `CTFontDrawGlyphs`.
 *
 * Base text is drawn by re-shaping each *positioned* cluster (post-line-break) with the
 * same CTFont the engine measured — the Core Text peer of what `SkiaLayoutRenderer` does.
 * Positions come from [positionedClusters] (per-cluster `drawX` + line baseline), NOT from
 * the flat pre-line-break glyph runs. On top of the base run it paints the engine-computed
 * decoration geometry: 着重号 dots, 专名号/书名号/示亡号 lines, and the shape-once 拼音 /
 * 注音 annotation glyphs (`RubyDecisionInfo.glyphs` / `BopomofoGlyphPlacement.glyphs`).
 *
 * Rich text (ADR 0030): [draw] takes the same per-span [TextSpan] styles and render-only
 * [ColorSpan] colors the Skia frontend does. Each base cluster is drawn with the font its span
 * asks for (family / size / weight / synthetic-oblique italic) — the same face the shaper
 * measured — and clusters inside a [ColorSpan] are painted in that color; everything else
 * inherits the context's fill color. 拼音 ruby is drawn at its engine-computed [RubyDecisionInfo.fontWeight].
 *
 * Fonts are borrowed from [CoreTextSupport]'s process cache (never CFRelease'd here) — the
 * same cache the shaper and metrics resolver use, so `measure == draw` (AGENTS.md #5) holds
 * and the 注音 hot path no longer rebuilds a `CTFontDescriptor`/`CTFont` per glyph.
 *
 * Coordinates: `LayoutResult` is top-left / y-down; the CGContext is native bottom-left /
 * y-up, so a layout y maps to `canvasHeight - y`. Glyphs are drawn with the default text
 * matrix (upright in y-up). The renderer does NOT set a base fill color — it inherits the
 * context's current fill color, so callers control light/dark text color.
 */
class CoreTextLayoutRenderer(
    private val cjkFamily: String = CoreTextSupport.DEFAULT_CJK_FAMILY,
    private val latinFamily: String = CoreTextSupport.DEFAULT_LATIN_FAMILY,
) {
    fun draw(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        spans: List<TextSpan> = emptyList(),
        colorSpans: List<ColorSpan> = emptyList(),
        richTextSpans: List<RichTextSpan> = emptyList(),
    ) {
        if (canvasHeight <= 0.0) return
        val fontSize = result.input.textStyle.fontSize.toDouble()
        drawBaseText(result, context, canvasHeight, spans, colorSpans)
        drawLineEndHyphens(result, context, canvasHeight, colorSpans)
        drawEmphasisDots(result, context, canvasHeight, colorSpans)
        drawDecorationSegments(result, context, canvasHeight, fontSize, colorSpans)
        drawLinkUnderlines(result, context, canvasHeight, spans, colorSpans, richTextSpans)
        drawRuby(result, context, canvasHeight)
        drawBopomofo(result, context, canvasHeight)
    }

    // --- base text -----------------------------------------------------------

    private fun drawBaseText(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        spans: List<TextSpan>,
        colorSpans: List<ColorSpan>,
    ) {
        val baseStyle = result.input.textStyle
        val featuresByClusterRange = buildMap {
            for (run in result.glyphRuns) {
                for (glyph in run.glyphs) put(glyph.clusterRange, run.openTypeFeatures)
            }
        }
        for (pc in result.positionedClusters()) {
            val cluster = result.clusters.getOrNull(pc.clusterIndex) ?: continue
            if (cluster.displayText.isEmpty()) continue
            // Per-span style (rich text): the face the shaper measured this run with — family from
            // the span (else the role default), plus weight + synthetic-oblique italic.
            val style = styleAt(spans, cluster.range.start) ?: baseStyle
            // Latin-vs-CJK face from the engine's authoritative font decision + the shared
            // `usesLatinFace` rule (font/FontPolicy.kt) — the SAME rule shaping and metrics use — so
            // the drawn face can't drift from the measured one (a .notdef sized in the wrong face
            // would overflow its slot). Parsing `fontKey` would re-implement that rule and risk drift.
            val isLatin = result.usesLatinFaceAt(cluster.range)
            val family = style.fontFamilies.firstOrNull() ?: if (isLatin) latinFamily else cjkFamily
            val font = CoreTextSupport.font(family, style.fontSize.toDouble(), style.fontWeight, style.italic) ?: continue
            val baselineY = pc.baseline + cluster.baselineShift
            val argb = colorAt(colorSpans, cluster.range.start)
            val openTypeFeatures = featuresByClusterRange[cluster.range].orEmpty()
            if (argb != null) {
                CGContextSaveGState(context)
                setFill(context, argb)
                drawShapedText(
                    context,
                    font,
                    cluster.displayText,
                    pc.drawX.toDouble(),
                    baselineY.toDouble(),
                    canvasHeight,
                    language = style.locale,
                    openTypeFeatures = openTypeFeatures,
                )
                CGContextRestoreGState(context)
            } else {
                drawShapedText(
                    context,
                    font,
                    cluster.displayText,
                    pc.drawX.toDouble(),
                    baselineY.toDouble(),
                    canvasHeight,
                    language = style.locale,
                    openTypeFeatures = openTypeFeatures,
                )
            }
        }
    }

    /**
     * Draws the synthetic line-end hyphen for Western auto-hyphenation. The engine reserves
     * [LineBox.hyphenAdvance] just past `indent + visualWidth` (ADR 0029) but leaves drawing to the
     * frontend; without this, a hyphenated word breaks with hyphen geometry yet shows no hyphen. Drawn
     * by re-shaping "-" (the same character the engine measured) in the Latin face at the body size.
     */
    private fun drawLineEndHyphens(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        colorSpans: List<ColorSpan>,
    ) {
        val baseStyle = result.input.textStyle
        val font = CoreTextSupport.font(latinFamily, baseStyle.fontSize.toDouble(), baseStyle.fontWeight, baseStyle.italic)
            ?: return
        for (line in result.lines) {
            if (line.hyphenAdvance <= 0f) continue
            // The hyphen takes the color of the cluster it breaks after.
            val anchor = result.clusters[line.clusterRange.last].range.start
            val argb = colorAt(colorSpans, anchor)
            if (argb != null) {
                CGContextSaveGState(context)
                setFill(context, argb)
                drawShapedText(context, font, "-", (line.indent + line.visualWidth).toDouble(), line.baseline.toDouble(), canvasHeight)
                CGContextRestoreGState(context)
            } else {
                drawShapedText(context, font, "-", (line.indent + line.visualWidth).toDouble(), line.baseline.toDouble(), canvasHeight)
            }
        }
    }

    /** The last [TextSpan] whose source range covers [offset] (later spans win), or null. */
    private fun styleAt(spans: List<TextSpan>, offset: Int): TextStyle? =
        spans.lastOrNull { offset >= it.range.start && offset < it.range.end }?.style

    /** The last [ColorSpan] (ARGB) covering [offset], or null to inherit the context fill color. */
    private fun colorAt(colorSpans: List<ColorSpan>, offset: Int): Int? =
        colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.argb

    /**
     * Whether the cluster at [range] draws in the Latin face, from the engine's own font decision
     * (`debug.fontDecisions`) resolved through the shared `usesLatinFace` rule — the same source and
     * rule the shaper and metrics use. Mirrors the Compose frontend (`LayoutResultReplayIndex`).
     */
    private fun LayoutResult.usesLatinFaceAt(range: TextRange): Boolean {
        val role = debug.fontDecisions
            .firstOrNull { range.start >= it.range.start && range.end <= it.range.end }
            ?.role
        return fontRoleNameUsesLatinFace(role)
    }

    private fun setFill(context: CGContextRef, argb: Int) {
        val a = ((argb ushr 24) and 0xFF) / 255.0
        val r = ((argb ushr 16) and 0xFF) / 255.0
        val g = ((argb ushr 8) and 0xFF) / 255.0
        val b = (argb and 0xFF) / 255.0
        CGContextSetRGBFillColor(context, r, g, b, a)
    }

    /**
     * Shape [text] with [font] and draw it with its glyph origin at ([penX], baseline
     * [baselineY] in layout space). Uses each Core Text run's own font so a character the
     * base font lacks still draws with the fallback face Core Text selected.
     */
    private fun drawShapedText(
        context: CGContextRef,
        font: CTFontRef,
        text: String,
        penX: Double,
        baselineY: Double,
        canvasHeight: Double,
        vertical: Boolean = false,
        language: String? = null,
        openTypeFeatures: List<String> = emptyList(),
    ) {
        val penYUp = canvasHeight - baselineY
        // Borrowed from the shared shaping cache — the SAME `line()` the shaper measured with, keyed by
        // [language] too, so replay selects the same `locl` glyphs it measured (measure == draw). Do
        // NOT CFRelease — the cache owns it, and the line is replayed cheaply on every repaint.
        val line = CoreTextSupport.line(text, font, vertical, language, openTypeFeatures) ?: return
        val runs = CTLineGetGlyphRuns(line) ?: return
        val runCount = CFArrayGetCount(runs).toInt()
        for (r in 0 until runCount) {
            val run: CTRunRef = CFArrayGetValueAtIndex(runs, r.convert())!!.reinterpret()
            drawRun(context, run, font, penX, penYUp)
        }
    }

    private fun drawRun(context: CGContextRef, run: CTRunRef, fallbackFont: CTFontRef, penX: Double, penYUp: Double) {
        val n = CTRunGetGlyphCount(run).toInt()
        if (n <= 0) return
        val runFont = CoreTextSupport.runFontOf(run) ?: fallbackFont
        memScoped {
            val glyphs = allocArray<CGGlyphVar>(n)
            val src = allocArray<CGPoint>(n)
            CTRunGetGlyphs(run, CoreTextSupport.cfRange(0, 0), glyphs)
            CTRunGetPositions(run, CoreTextSupport.cfRange(0, 0), src)
            val dst = allocArray<CGPoint>(n)
            for (i in 0 until n) {
                // CTRun positions are already in Core Graphics (y-up, baseline-relative) space.
                dst[i].x = penX + src[i].x
                dst[i].y = penYUp + src[i].y
            }
            CTFontDrawGlyphs(runFont, glyphs, dst, n.convert(), context)
        }
    }

    // --- annotation drawing (拼音 / 注音) ------------------------------------

    private fun drawRuby(result: LayoutResult, context: CGContextRef, canvasHeight: Double) {
        for (ruby in result.debug.rubyDecisions) {
            if (ruby.text.isEmpty()) continue
            // Re-shape 拼音 with the resolved font (run's own face) rather than replaying the
            // engine's stored glyph ids: replaying ids against a fresh family font misdraws
            // when the reading triggered a Core Text fallback face — the same protection the
            // 注音 path uses (its ids would otherwise belong to a different face). Weight is the
            // engine-computed 注文字重 (heavier than 基文 at small sizes for legibility, ADR 0032) —
            // the 拼音 peer of what the 注音 path already does. Font is borrowed — do NOT CFRelease.
            val font = CoreTextSupport.font(ruby.fontFamilies.firstOrNull() ?: latinFamily, ruby.fontSize.toDouble(), ruby.fontWeight) ?: continue
            drawShapedText(
                context,
                font,
                ruby.text,
                (ruby.centerX - ruby.width / 2f).toDouble(),
                ruby.baselineY.toDouble(),
                canvasHeight,
                language = ruby.locale,
            )
        }
    }

    /**
     * 注音: draw each placement as a real Core Text vertical run. The engine records the
     * horizontal-baseline origin that Skia/Android replay; Core Text's vertical run pen is the
     * 字身框 top centre instead, so the ㄅㄆㄇ symbol origin is derived from the box here. The
     * ink-positioned 调号/轻声 marks are computed from each platform's own ink, so their recorded
     * [drawX]/[baselineY] already match this Core Text run and are replayed as-is.
     */
    private fun drawBopomofo(result: LayoutResult, context: CGContextRef, canvasHeight: Double) {
        for (z in result.debug.bopomofoDecisions) {
            val family = z.fontFamilies.firstOrNull() ?: cjkFamily
            val weight = z.fontWeight // 注文字重 = 基文 + 300 (engine-computed, BopomofoLegibilityWeightBoost)
            for (p in z.placements) {
                if (p.text.isEmpty()) continue
                val font = CoreTextSupport.font(family, p.fontSize.toDouble(), weight) ?: continue
                val penX: Double
                val baselineY: Double
                if (p.role == BopomofoGlyphRole.Symbol) {
                    penX = (p.left + p.width / 2f).toDouble()
                    baselineY = p.top.toDouble()
                } else {
                    penX = p.drawX.toDouble()
                    baselineY = p.baselineY.toDouble()
                }
                drawShapedText(
                    context = context,
                    font = font,
                    text = p.text,
                    penX = penX,
                    baselineY = baselineY,
                    canvasHeight = canvasHeight,
                    vertical = true,
                    language = z.locale,
                    openTypeFeatures = listOf("vert=1"),
                )
            }
        }
    }

    // --- 着重号 / 专名号 / 书名号 / 示亡号 -----------------------------------

    private fun drawEmphasisDots(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        colorSpans: List<ColorSpan>,
    ) {
        for (d in result.debug.decorationDecisions) {
            if (!d.applied || d.dotDiameter <= 0f) continue
            val radius = d.dotDiameter.toDouble() / 2.0
            val cx = d.anchorX.toDouble()
            val cy = canvasHeight - d.anchorY.toDouble()
            drawWithColor(context, colorAt(colorSpans, d.clusterRange.start)) {
                CGContextFillEllipseInRect(context, rect(cx - radius, cy - radius, radius * 2, radius * 2))
            }
        }
    }

    private fun drawDecorationSegments(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        fontSize: Double,
        colorSpans: List<ColorSpan>,
    ) {
        val stroke = (fontSize / 16.0).coerceAtLeast(1.0)
        val skipClearance = maxOf(
            stroke.toFloat(),
            (fontSize.toFloat() * INTERLINEAR_SKIP_INK_CLEARANCE_EM)
                .coerceAtMost(INTERLINEAR_SKIP_INK_CLEARANCE_MAX_PX),
        )
        for (s in result.debug.decorationSegments) {
            drawWithColor(context, colorAt(colorSpans, s.sourceRange.start)) {
                when (s.kind) {
                    "ProperNoun", "BookTitle" -> {
                        val skips = result.coreTextInkSkipIntervals(
                            lineIndex = s.lineIndex,
                            bandTop = s.top - stroke.toFloat(),
                            bandBottom = s.top + stroke.toFloat(),
                        )
                        keptIntervals(
                            left = s.left.toDouble(),
                            right = s.right.toDouble(),
                            skips = skips,
                            clearance = skipClearance.toDouble(),
                        ) { left, right ->
                            if (s.kind == "ProperNoun") {
                                hLine(context, left, right, s.top.toDouble(), stroke, canvasHeight)
                            } else {
                                wavyLine(context, left, right, s.top.toDouble(), stroke, canvasHeight, fontSize)
                            }
                        }
                    }
                    // 示亡号: a frame; continuation edges (openStart/openEnd) stay undrawn.
                    else -> {
                        hLine(context, s.left.toDouble(), s.right.toDouble(), s.top.toDouble(), stroke, canvasHeight)
                        hLine(context, s.left.toDouble(), s.right.toDouble(), s.bottom.toDouble(), stroke, canvasHeight)
                        if (!s.openStart) vLine(context, s.left.toDouble(), s.top.toDouble(), s.bottom.toDouble(), stroke, canvasHeight)
                        if (!s.openEnd) vLine(context, s.right.toDouble(), s.top.toDouble(), s.bottom.toDouble(), stroke, canvasHeight)
                    }
                }
            }
        }
    }

    /**
     * `AppleNativeLinkUnderline`: native `AttributedString.link` ranges remain semantic
     * [Link] spans. The Apple renderer supplies their ordinary solid underline using
     * the same source boxes, punctuation-glue trim and recorded glyph ink used by other frontends.
     */
    private fun drawLinkUnderlines(
        result: LayoutResult,
        context: CGContextRef,
        canvasHeight: Double,
        spans: List<TextSpan>,
        colorSpans: List<ColorSpan>,
        richTextSpans: List<RichTextSpan>,
    ) {
        val underlines = richTextSpans.mapNotNull { span ->
            if (span.role is Link) span.copy(role = Underline.instance) else null
        }
        if (underlines.isEmpty()) return
        val segments = result.richTextDecorationSegments(
            result.positionedRichTextSegments(underlines),
        )
        val stroke = (result.input.textStyle.fontSize / 16f).coerceAtLeast(1f)
        for (segment in segments) {
            val style = styleAt(spans, segment.range.start) ?: result.input.textStyle
            val lineY = result.richTextDecorationLineY(segment, stroke)
            val skipClearance = maxOf(
                stroke,
                (style.fontSize * INTERLINEAR_SKIP_INK_CLEARANCE_EM)
                    .coerceAtMost(INTERLINEAR_SKIP_INK_CLEARANCE_MAX_PX),
            )
            val skips = result.coreTextInkSkipIntervals(
                lineIndex = segment.lineIndex,
                bandTop = lineY - stroke,
                bandBottom = lineY + stroke,
            )
            drawWithColor(
                context,
                segment.span.paint.argb ?: colorAt(colorSpans, segment.range.start),
            ) {
                keptIntervals(
                    left = segment.left.toDouble(),
                    right = segment.right.toDouble(),
                    skips = skips,
                    clearance = skipClearance.toDouble(),
                ) { left, right ->
                    hLine(context, left, right, lineY.toDouble(), stroke.toDouble(), canvasHeight)
                }
            }
        }
    }

    private fun hLine(context: CGContextRef, left: Double, right: Double, y: Double, stroke: Double, canvasHeight: Double) {
        val cgY = canvasHeight - y
        CGContextFillRect(context, rect(left, cgY - stroke / 2.0, right - left, stroke))
    }

    /**
     * 书名号甲式的圆形二次贝塞尔波浪。参数与 Compose/Android 相同：半波长 0.2em、
     * 振幅 0.06em。Core Graphics 先把 path 展开成描边轮廓再用当前 fill color 填充，因此
     * 深色模式和富文本颜色都不依赖额外的 stroke-color 状态。
     */
    private fun wavyLine(context: CGContextRef, left: Double, right: Double, y: Double, stroke: Double, canvasHeight: Double, fontSize: Double) {
        if (right <= left) return
        val halfWave = (fontSize * WAVY_HALF_WAVE_EM).coerceAtLeast(1.0)
        val amplitude = fontSize * WAVY_AMPLITUDE_EM
        val cgY = canvasHeight - y
        val path = CGPathCreateMutable() ?: return
        CGPathMoveToPoint(path, null, left, cgY)
        var x = left
        var up = true
        while (x < right - WAVY_ENDPOINT_EPSILON_PX) {
            val nextX = minOf(x + halfWave, right)
            val controlY = cgY + if (up) amplitude * 2.0 else -amplitude * 2.0
            CGPathAddQuadCurveToPoint(path, null, (x + nextX) / 2.0, controlY, nextX, cgY)
            x = nextX
            up = !up
        }
        CGContextAddPath(context, path)
        CGContextSetLineWidth(context, stroke)
        CGContextReplacePathWithStrokedPath(context)
        CGContextFillPath(context)
        CGPathRelease(path)
    }

    private fun drawWithColor(context: CGContextRef, argb: Int?, draw: () -> Unit) {
        if (argb == null) {
            draw()
            return
        }
        CGContextSaveGState(context)
        setFill(context, argb)
        draw()
        CGContextRestoreGState(context)
    }

    private fun vLine(context: CGContextRef, x: Double, top: Double, bottom: Double, stroke: Double, canvasHeight: Double) {
        val cgTop = canvasHeight - top
        val cgBottom = canvasHeight - bottom
        val lo = minOf(cgTop, cgBottom)
        CGContextFillRect(context, rect(x - stroke / 2.0, lo, stroke, maxOf(cgTop, cgBottom) - lo))
    }

    // --- helpers -------------------------------------------------------------

    private fun rect(x: Double, y: Double, w: Double, h: Double): CValue<CGRect> =
        cValue { origin.x = x; origin.y = y; size.width = w; size.height = h }
}

internal data class CoreTextInkInterval(val left: Float, val right: Float)

/**
 * `CoreTextRecordedInkSkipIntervals`: derives skip-ink evidence from glyph bounds already carried by
 * LayoutResult. No renderer re-shaping or platform guess is allowed to become a second geometry truth.
 */
internal fun LayoutResult.coreTextInkSkipIntervals(
    lineIndex: Int,
    bandTop: Float,
    bandBottom: Float,
): List<CoreTextInkInterval> {
    val positioned = positionedClusters().filter { it.lineIndex == lineIndex }.associateBy { it.range }
    return glyphRuns.flatMap { run ->
        run.glyphs.mapNotNull { glyph ->
            val bounds = glyph.bounds ?: return@mapNotNull null
            val cluster = positioned[glyph.clusterRange] ?: return@mapNotNull null
            val top = cluster.baseline + glyph.y + bounds.top
            val bottom = cluster.baseline + glyph.y + bounds.bottom
            if (bottom < bandTop || top > bandBottom) return@mapNotNull null
            CoreTextInkInterval(
                left = cluster.drawX + glyph.x + bounds.left,
                right = cluster.drawX + glyph.x + bounds.right,
            )
        }
    }
}

private inline fun keptIntervals(
    left: Double,
    right: Double,
    skips: List<CoreTextInkInterval>,
    clearance: Double,
    draw: (Double, Double) -> Unit,
) {
    val merged = skips
        .map {
            maxOf(left, it.left.toDouble() - clearance) to
                minOf(right, it.right.toDouble() + clearance)
        }
        .filter { (start, end) -> end > start }
        .sortedBy { it.first }
        .fold(mutableListOf<Pair<Double, Double>>()) { out, interval ->
            val previous = out.lastOrNull()
            if (previous != null && interval.first <= previous.second) {
                out[out.lastIndex] = previous.first to maxOf(previous.second, interval.second)
            } else {
                out += interval
            }
            out
        }
    var cursor = left
    for ((start, end) in merged) {
        if (start > cursor + 0.5) draw(cursor, start)
        cursor = maxOf(cursor, end)
    }
    if (cursor < right - 0.5) draw(cursor, right)
}
