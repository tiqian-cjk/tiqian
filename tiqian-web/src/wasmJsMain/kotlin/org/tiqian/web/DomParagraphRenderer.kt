package org.tiqian.web

import kotlin.js.ExperimentalWasmJsInterop
import kotlinx.browser.document
import org.tiqian.core.BopomofoDecisionInfo
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.LayoutResult
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyDecisionInfo
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.positionedClusters
import org.tiqian.font.FontRole
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.CanvasRenderingContext2D
import org.w3c.dom.HTMLElement
import org.w3c.dom.HTMLCanvasElement

/**
 * `PreBrokenLineDom` (ADR 0039): the engine owns the whole line layout; this
 * renderer only PAINTS its result into the DOM. Half-width punctuation, 中西
 * autospace, justify, 推入推出 and the line-end hyphen all come from the engine,
 * not the browser — the browser never re-wraps or word-breaks.
 *
 * `InlineFlowLineDom`: each line is a block; within it the glyphs are plain INLINE
 * spans laid out by flow, so they share ONE line box and the native selection
 * highlight is continuous — none of the per-glyph seams/gaps that absolute
 * per-glyph positioning produces. The engine's inter-glyph gap is
 * `drawX[i+1] − drawX[i] − naturalWidth[i]`, where `naturalWidth` is the shaped
 * GLYPH advance — NOT `Cluster.advance`, which carries the layout-owned
 * glue/justify stretch and equals the `drawX` step, so using it would cancel
 * every gap and kill justification.
 *
 * `SelectableGapSpacing`: that gap must land in a box the SELECTION covers, or the
 * highlight gets a hole at every stretched space (as plain `margin` does). So the
 * trailing gap is `letter-spacing` for single-code-point glyphs (CJK /
 * punctuation / spaces — seamless, negative for half-width punctuation) and
 * `padding-right` for multi-letter Latin words (letter-spacing would splay
 * `the`→`t h e`). Both are inside the native selection box. The first glyph's
 * 段首缩进 is a leading `margin-left`.
 *
 * `CopyTransparentSpacingSpans`: copy is reconstructed by the page's `copy`
 * handler from `textContent` (which ignores block boundaries → no injected
 * newlines from soft wraps) with substituted spans (`——`→`⸺`) mapped back to
 * their `data-tq-src` source (ADR 0037 source-faithful copy).
 *
 * `CssNativeDecorations`: ordinary rich-text underline / strike-through use native
 * CSS `text-decoration-skip-ink`, while CLREQ 行间线 (专名号 / 书名号甲式) paint
 * engine-owned SVG segments so each annotated item is one continuous line.
 * 着重号 paints engine-sized SVG circles at the engine's `DecorationDecisionInfo`
 * anchors (Han only, punctuation skipped); Latin clusters in the same emphasis span
 * render italic because that is what the engine measured. Ruby / Bopomofo
 * annotations ride real DOM spans after the base and copy parenthesised through
 * `data-tq-src`. Link ranges become real `<a>` nodes, while Color / background
 * ride the same per-cluster style.
 */
@OptIn(ExperimentalWasmJsInterop::class)
object DomParagraphRenderer {

    fun render(
        host: HTMLElement,
        result: LayoutResult,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan> = emptyList(),
        richTextSpans: List<RichTextSpan> = emptyList(),
    ) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        host.style.setProperty("position", "relative")
        val fontSize = result.input.textStyle.fontSize
        val decorations = result.input.decorations
        val emphasisRanges = decorations
            .filter { it.kind == DecorationKind.Emphasis }
            .map { it.range }

        // Natural shaped width per cluster from the GLYPH advances (which exclude
        // layout-owned glue/justify — see the class doc). Cluster.advance carries
        // that glue and would cancel the margins.
        val naturalWidth = HashMap<TextRange, Float>()
        for (run in result.glyphRuns) {
            for (glyph in run.glyphs) {
                naturalWidth[glyph.clusterRange] = (naturalWidth[glyph.clusterRange] ?: 0f) + glyph.advance
            }
        }
        fun styleAt(offset: Int): TextStyle =
            result.input.content.spans.lastOrNull { offset >= it.range.start && offset < it.range.end }?.style
                ?: result.input.textStyle

        // `InlineSelectableRuby` (ADR 0032): 注文 is a REAL span placed in DOM right
        // AFTER its base's last cluster — absolutely positioned into the 注文 band so it
        // doesn't push the base flow, but selectable and copy-ordered. A selection over a
        // ruby'd base therefore carries the 注文, which copies parenthesised after the base
        // (「北京（Běijīng）」) via `data-tq-src` (注文不进源, but surfaced on copy). Keyed
        // by base END offset so only the last base cluster gets it (北京 → one 注文).
        val rubyByBaseEnd = HashMap<Int, RubyDecisionInfo>()
        for (ruby in result.debug.rubyDecisions) {
            rubyByBaseEnd[ruby.baseRange.end] = ruby
        }
        // InlineSelectableBopomofo: 注音只生成一个行内 annotation span。
        // 这个 span 占据基文后的 actual layout advance，并在自身内部按 engine
        // placements 放置可见 glyph；同一个 span 也作为整体参与 selection/copy。
        val bopomofoByBaseEnd = HashMap<Int, MutableList<BopomofoDecisionInfo>>()
        for (z in result.debug.bopomofoDecisions) {
            bopomofoByBaseEnd.getOrPut(z.baseRange.end) { mutableListOf() }.add(z)
        }
        for (line in result.lines) {
            val h = line.bottom - line.top
            val lineDiv = document.createElement("div") as HTMLElement
            lineDiv.style.apply {
                setProperty("height", "${h}px")
                setProperty("line-height", "${h}px")
                setProperty("white-space", "pre") // engine owns wrapping; never let the browser re-break
                setProperty("font-size", "${fontSize}px")
                setProperty("position", "relative")
                // `FlushSelectionAtMeasure`: clip the line to the engine's content edge so a
                // line-end half-width punctuation's blank right half, or a collapsed trailing
                // space, extends NEITHER the ink NOR the selection highlight past the measure
                // — the selection's right edge stays as even as the left. The clip keeps any
                // legitimately hung glyphs — a line-end hyphen (`LineEndHangingHyphen`, ADR
                // 0029) or hung punctuation (ADR 0006) — inside it, so only blank overflow is cut.
                setProperty(
                    "width",
                    "${line.indent + line.visualWidth + line.hyphenAdvance + line.hangingPunctuationAdvance}px",
                )
                setProperty("overflow-x", "clip") // horizontal only — never clip Latin descenders
            }
            val content = document.createElement("span") as HTMLElement
            val baselineDelta = cssBaselineOffset(h, fontSize, fonts.cjk)?.let { cssBaseline ->
                (line.baseline - line.top) - cssBaseline
            }
            if (baselineDelta != null && baselineDelta != 0f) {
                // Shift the inline baseline onto Tiqian's line baseline via `vertical-align`,
                // NOT `position: relative` + `top`: a relatively-positioned inline span
                // mis-paints the native selection highlight on the taller ruby lines (the
                // highlight vanished on every 拼音 paragraph). `vertical-align` moves the
                // baseline the same way but the selection follows it. (down = negative)
                content.style.setProperty("vertical-align", "${-baselineDelta}px")
            }

            val cells = result.positionedClusters(line)
                .filter { result.clusters[it.clusterIndex].displayText.isNotEmpty() }
            for (i in cells.indices) {
                val pc = cells[i]
                val cluster = result.clusters[pc.clusterIndex]
                val nat = naturalWidth[cluster.range] ?: cluster.advance
                val leadingMargin = if (i == 0) pc.drawX else 0f
                val layoutTrailingGap = if (i + 1 < cells.size) {
                    cells[i + 1].drawX - pc.drawX - nat
                } else {
                    0f
                }
                val bopomofoAtEnd = bopomofoByBaseEnd[cluster.range.end]
                val bopomofoAdvanceWidth = if (bopomofoAtEnd == null) {
                    0f
                } else if (i + 1 < cells.size) {
                    layoutTrailingGap.coerceAtLeast(0f)
                } else {
                    (cluster.advance - nat).coerceAtLeast(0f)
                }
                val trailingGap = if (bopomofoAtEnd == null) {
                    layoutTrailingGap
                } else {
                    0f
                }
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                val clusterStyle = styleAt(cluster.range.start)
                val isLatin = roleName == FontRole.LatinText.name
                val family = fonts.forRoleName(roleName, clusterStyle.fontFamilies)
                val display = cluster.displayText
                val deco = decoFor(cluster.range, colorSpans, richTextSpans)
                val italic = clusterStyle.italic || isLatin &&
                    emphasisRanges.any { cluster.range.start >= it.start && cluster.range.start < it.end }

                if (display.length > 1 && trailingGap != 0f && cluster.text == display) {
                    content.appendChild(
                        glyphSpan(
                            display.dropLast(1),
                            display.dropLast(1),
                            leadingMargin,
                            trailingGap = 0f,
                            singleGlyph = false,
                            family,
                            clusterStyle.fontSize,
                            clusterStyle.fontWeight,
                            deco,
                            italic,
                        ),
                    )
                    content.appendChild(
                        glyphSpan(
                            display.takeLast(1),
                            display.takeLast(1),
                            marginLeft = 0f,
                            trailingGap,
                            singleGlyph = true,
                            family,
                            clusterStyle.fontSize,
                            clusterStyle.fontWeight,
                            deco,
                            italic,
                        ),
                    )
                } else {
                    content.appendChild(
                        glyphSpan(
                            display,
                            cluster.text,
                            leadingMargin,
                            trailingGap,
                            singleGlyph = display.length == 1,
                            family,
                            clusterStyle.fontSize,
                            clusterStyle.fontWeight,
                            deco,
                            italic,
                        ),
                    )
                }
                // InlineSelectableRuby: 注文 span DOM-follows the base's last cluster.
                rubyByBaseEnd[cluster.range.end]?.let {
                    content.appendChild(rubyInlineSpan(it, line.top, fonts, colorSpans))
                }
                bopomofoAtEnd?.forEach {
                    content.appendChild(bopomofoInlineSpan(it, bopomofoAdvanceWidth, line.top, h, fonts, colorSpans))
                }
            }
            // EngineOwnedHyphenation: the engine reserved the hyphen inside the measure;
            // place it at indent+visualWidth. The browser never hyphenates.
            if (line.hyphenAdvance > 0f) {
                val last = cells.lastOrNull()
                val flowEnd = if (last != null) {
                    last.drawX + (naturalWidth[result.clusters[last.clusterIndex].range] ?: 0f)
                } else {
                    0f
                }
                content.appendChild(
                    glyphSpan(
                        "-",
                        "-",
                        (line.indent + line.visualWidth) - flowEnd,
                        trailingGap = 0f,
                        singleGlyph = true,
                        fonts.latin,
                        result.input.textStyle.fontSize,
                        result.input.textStyle.fontWeight,
                        ClusterDeco(),
                        false,
                    ),
                )
            }
            lineDiv.appendChild(content)
            host.appendChild(lineDiv)
        }
        appendInterlinearLines(host, result, colorSpans)
        appendEmphasisDots(host, result, colorSpans)
        installLinkGroupInteractions(host)
    }

    /**
     * 注音 (ADR 0033): the engine places each ㄅㄆㄇ symbol + 调号 in its own box on the
     * base's right. The annotation itself is one inline selectable/copyable span;
     * its children only paint the engine placements inside that span.
     */
    private fun bopomofoInlineSpan(
        z: BopomofoDecisionInfo,
        width: Float,
        lineTop: Float,
        lineHeight: Float,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan>,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.setAttribute("data-tq-src", "（${z.text}）")
        span.setAttribute("lang", BOPOMOFO_LANG)
        span.style.apply {
            setProperty("display", "inline-block")
            setProperty("position", "relative")
            setProperty("vertical-align", "top")
            setProperty("width", "${width}px")
            setProperty("height", "${lineHeight}px")
            setProperty("box-sizing", "border-box")
            setProperty("line-height", "${lineHeight}px")
            setProperty("white-space", "pre")
            setProperty("overflow", "visible")
            setProperty("user-select", "all")
            setProperty("-webkit-user-select", "all")
        }

        // 注音-capable face: not just "a CJK font" — the ㄅㄆㄇ symbols are everywhere,
        // but the 注音-shaped 调号 (full-width U+02CA…) only live in TC/system fonts;
        // SC / Noto / Source Han fall back to a small Western accent for the tone.
        val font = BopomofoFontSpec(fonts.forBopomofo(z.fontFamilies), z.fontWeight)
        val color = colorAt(z.baseRange.start, colorSpans)
        val zoneLeft = bopomofoZoneLeft(z)
        for (p in z.placements) {
            val placement = bopomofoCssPlacement(p.text, p.role, font, p.left, p.top, p.width, p.height)
            val glyph = document.createElement("span") as HTMLElement
            glyph.textContent = p.text
            glyph.setAttribute("lang", BOPOMOFO_LANG)
            glyph.style.apply {
                setProperty("position", "absolute")
                setProperty("left", "${placement.left - zoneLeft}px")
                setProperty("top", "${placement.top - lineTop}px")
                setProperty("font-family", font.family)
                setProperty("font-style", "normal")
                setProperty("font-weight", "${font.weight}")
                setProperty("font-size", "${placement.fontSize}px")
                setProperty("color", color)
                setProperty("line-height", "${placement.lineHeight}px")
                setProperty("white-space", "pre")
                setProperty("display", "inline-block")
                setProperty("pointer-events", "none")
                setProperty("overflow", "visible")
                setProperty("writing-mode", "vertical-rl")
                setProperty("text-orientation", "upright")
                setProperty("font-feature-settings", "'vert' 1, 'vrt2' 1")
            }
            span.appendChild(glyph)
        }
        return span
    }

    /** Web mirror of Compose's 注音 placement formulas for Symbol / Tone / Neutral. */
    private fun bopomofoCssPlacement(
        text: String,
        role: BopomofoGlyphRole,
        font: BopomofoFontSpec,
        boxLeft: Float,
        boxTop: Float,
        boxWidth: Float,
        boxHeight: Float,
    ): BopomofoCssPlacement = when (role) {
        BopomofoGlyphRole.Symbol -> BopomofoCssPlacement(
            left = boxLeft,
            top = boxTop,
            fontSize = boxHeight,
            lineHeight = boxWidth,
        )
        BopomofoGlyphRole.Neutral -> {
            val fontSize = boxWidth
            BopomofoCssPlacement(
                left = boxLeft,
                top = boxTop + (boxHeight - fontSize) / 2f,
                fontSize = fontSize,
                lineHeight = boxWidth,
            )
        }
        BopomofoGlyphRole.Tone -> {
            val inkWidthEm = browserVerticalBopomofoToneInkWidthEm(text, font.weight)
            val fontSize = boxWidth * BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE / inkWidthEm.coerceAtLeast(0.1f)
            BopomofoCssPlacement(
                left = boxLeft,
                top = boxTop + (boxHeight - fontSize) / 2f,
                fontSize = fontSize,
                lineHeight = boxWidth,
            )
        }
    }

    private data class BopomofoCssPlacement(
        val left: Float,
        val top: Float,
        val fontSize: Float,
        val lineHeight: Float,
    )

    private data class BopomofoFontSpec(
        val family: String,
        val weight: Int,
    )

    private fun bopomofoZoneLeft(z: BopomofoDecisionInfo): Float {
        val symbol = z.placements.firstOrNull { it.role == BopomofoGlyphRole.Symbol }
        return symbol?.let { it.left - it.width / 9f }
            ?: z.placements.minOfOrNull { it.left }
            ?: 0f
    }

    private fun glyphSpan(
        text: String,
        source: String,
        marginLeft: Float,
        trailingGap: Float,
        singleGlyph: Boolean,
        fontFamily: String,
        fontSize: Float,
        fontWeight: Int,
        deco: ClusterDeco,
        italic: Boolean,
    ): HTMLElement {
        val span = document.createElement(if (deco.linkTarget == null) "span" else "a") as HTMLElement
        span.textContent = text
        deco.linkTarget?.let {
            span.setAttribute("href", it)
            span.setAttribute("target", "_blank")
            span.setAttribute("rel", "noopener noreferrer")
            deco.linkId?.let { id -> span.setAttribute("data-tq-link-id", id) }
            span.setAttribute("data-tq-link-color", deco.color ?: LINK_COLOR)
            span.setAttribute("data-tq-link-decoration-color", deco.decorationColor ?: deco.color ?: LINK_COLOR)
        }
        // Source-faithful copy: a CLREQ-substituted cluster (——→⸺, ……→⋯) shows
        // the display form but must COPY as source. The copy handler reads this.
        if (source != text) span.setAttribute("data-tq-src", source)
        span.style.apply {
            if (marginLeft != 0f) setProperty("margin-left", "${marginLeft}px")
            if (trailingGap != 0f) {
                // Both are inside the native selection box (unlike margin); letter-spacing
                // would splay a multi-letter word, so words use padding-right instead
                // (which cannot be negative — a rare clamp on the last word of a line).
                if (singleGlyph) setProperty("letter-spacing", "${trailingGap}px")
                else if (trailingGap > 0f) setProperty("padding-right", "${trailingGap}px")
            }
            setProperty("font-family", fontFamily)
            setProperty("font-size", "${fontSize}px")
            setProperty("font-weight", "$fontWeight")
            if (italic) setProperty("font-style", "italic")
            setProperty("white-space", "pre")
            deco.linkTarget?.let {
                setProperty("cursor", "pointer")
                setProperty("transition", "color 140ms ease, text-decoration-color 140ms ease")
            }
            // CssNativeDecorations — continuous across letter-spacing, native skip-ink.
            deco.color?.let { setProperty("color", it) }
            deco.background?.let { setProperty("background-color", it) }
            deco.textDecorationLine?.let {
                setProperty("text-decoration-line", it)
                setProperty("text-decoration-style", "solid")
                setProperty("text-decoration-skip-ink", "auto")
                // Sit the line BELOW the CJK face (≈ engine's baseline+0.18em, ADR 0024/0030):
                // an underline at the default baseline crosses CJK ink and skip-ink then shreds
                // it (the「书名号不连续」bug). Below the face → no ink crosses → continuous.
                if ("underline" in it) setProperty("text-underline-offset", "${UNDERLINE_OFFSET_EM}em")
                setProperty("text-decoration-thickness", "${LINE_THICKNESS_EM}em")
                deco.decorationColor?.let { c -> setProperty("text-decoration-color", c) }
            }
        }
        return span
    }

    /**
     * DomLineBaselineAlignment: body text stays native inline DOM text for
     * selection/copy, but the inline baseline is shifted onto Tiqian's line
     * baseline so engine-owned ruby / emphasis / interlinear geometry aligns with
     * the glyphs actually drawn by the browser.
     */
    private fun cssBaselineOffset(lineHeight: Float, fontSize: Float, fontFamily: String): Float? {
        metricsCtx.font = "normal 400 ${fontSize}px $fontFamily"
        val m = metricsCtx.measureText(BASELINE_METRIC_PROBE)
        val ascent = m.fontBoundingBoxAscent.toFloatOrNull()
            ?: m.actualBoundingBoxAscent.toFloatOrNull()
            ?: return null
        val descent = m.fontBoundingBoxDescent.toFloatOrNull()
            ?: m.actualBoundingBoxDescent.toFloatOrNull()
            ?: return null
        val leading = (lineHeight - (ascent + descent)).coerceAtLeast(0f)
        return leading / 2f + ascent
    }

    /**
     * `InlineSelectableRuby` (ADR 0032): the 注文 is a real, selectable span placed in
     * DOM right after its base's last cluster (so a copy of a ruby'd base carries it),
     * but absolutely positioned into the engine's 注文 band (centreX / baselineY, in the
     * line's own coordinate space) so it does NOT push the base flow. It shows the plain
     * 拼音 but COPIES parenthesised (`data-tq-src` = 「（拼音）」).
     */
    @OptIn(ExperimentalWasmJsInterop::class)
    private fun rubyInlineSpan(
        ruby: RubyDecisionInfo,
        lineTop: Float,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan>,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = ruby.text
        span.setAttribute("data-tq-src", "（${ruby.text}）")
        val family = fonts.forRuby(ruby.fontFamilies)
        metricsCtx.font = "normal ${ruby.fontWeight} ${ruby.fontSize}px $family"
        val ascent = metricsCtx.measureText(ruby.text).fontBoundingBoxAscent.toFloatOrNull()
            ?: (ruby.fontSize * RUBY_ASCENT_RATIO)
        span.style.apply {
            setProperty("position", "absolute")
            setProperty("left", "${ruby.centerX}px")
            setProperty("top", "${ruby.baselineY - lineTop - ascent}px")
            setProperty("transform", "translateX(-50%)")
            setProperty("font-family", family)
            setProperty("font-size", "${ruby.fontSize}px")
            setProperty("font-weight", "${ruby.fontWeight}")
            setProperty("line-height", "1")
            setProperty("white-space", "pre")
            setProperty("color", colorAt(ruby.baseRange.start, colorSpans))
        }
        return span
    }

    /**
     * EngineOwnedInterlinearLines (ADR 0024): 专名号 / 书名号甲式 use
     * DecorationSegmentInfo directly. CSS wavy underline restarts its wave per
     * inline span, so it cannot represent a continuous 书名号 over multiple CJK
     * clusters.
     */
    private fun appendInterlinearLines(
        host: HTMLElement,
        result: LayoutResult,
        colorSpans: List<ColorSpan>,
    ) {
        val segments = result.debug.decorationSegments.filter {
            it.kind == DecorationKind.ProperNoun.name || it.kind == DecorationKind.BookTitle.name
        }
        if (segments.isEmpty()) return

        val svg = document.createElementNS(SVG_NS, "svg")
        svg.setAttribute("aria-hidden", "true")
        svg.setAttribute("data-tq-copy-ignore", "true")
        svg.setAttribute(
            "style",
            "position:absolute;left:0;top:0;width:${result.size.width}px;height:${result.size.height}px;" +
                "overflow:visible;pointer-events:none;user-select:none;-webkit-user-select:none",
        )

        val fontSize = result.input.textStyle.fontSize
        val strokeWidth = fontSize * LINE_THICKNESS_EM
        for (seg in segments) {
            val stroke = colorAt(seg.sourceRange.start, colorSpans)
            when (seg.kind) {
                DecorationKind.ProperNoun.name -> {
                    val line = document.createElementNS(SVG_NS, "line")
                    line.setAttribute("x1", "${seg.left}")
                    line.setAttribute("y1", "${seg.top}")
                    line.setAttribute("x2", "${seg.right}")
                    line.setAttribute("y2", "${seg.top}")
                    line.setAttribute("stroke", stroke)
                    line.setAttribute("stroke-width", "$strokeWidth")
                    line.setAttribute("stroke-linecap", "butt")
                    svg.appendChild(line)
                }
                DecorationKind.BookTitle.name -> {
                    val path = document.createElementNS(SVG_NS, "path")
                    path.setAttribute("d", wavyLinePath(seg.left, seg.right, seg.top, fontSize))
                    path.setAttribute("fill", "none")
                    path.setAttribute("stroke", stroke)
                    path.setAttribute("stroke-width", "$strokeWidth")
                    path.setAttribute("stroke-linecap", "butt")
                    path.setAttribute("stroke-linejoin", "round")
                    svg.appendChild(path)
                }
            }
        }

        host.appendChild(svg)
    }

    /**
     * EmphasisDotAnchorAlignment (ADR 0018 amendment): render the engine-sized
     * dot as a real SVG circle centered on the engine anchor. This is intentionally
     * not CSS `text-emphasis`: native emphasis owns its own position and cannot
     * consume Tiqian's decoration geometry.
     */
    private fun appendEmphasisDots(
        host: HTMLElement,
        result: LayoutResult,
        colorSpans: List<ColorSpan>,
    ) {
        val dots = result.debug.decorationDecisions.filter {
            it.applied && it.kind == DecorationKind.Emphasis.name && it.dotDiameter > 0f
        }
        if (dots.isEmpty()) return

        val svg = document.createElementNS(SVG_NS, "svg")
        svg.setAttribute("aria-hidden", "true")
        svg.setAttribute("data-tq-copy-ignore", "true")
        svg.setAttribute(
            "style",
            "position:absolute;left:0;top:0;width:${result.size.width}px;height:${result.size.height}px;" +
                "overflow:visible;pointer-events:none;user-select:none;-webkit-user-select:none",
        )

        for (dot in dots) {
            val color = colorAt(dot.clusterRange.start, colorSpans)

            val circle = document.createElementNS(SVG_NS, "circle")
            circle.setAttribute("cx", "${dot.anchorX}")
            circle.setAttribute("cy", "${dot.anchorY}")
            circle.setAttribute("r", "${dot.dotDiameter * EMPHASIS_DOT_SCALE / 2f}")
            circle.setAttribute("fill", color)
            svg.appendChild(circle)
        }

        host.appendChild(svg)
    }

    /** Per-cluster CSS resolved from the engine's render-only spans/decorations. */
    private data class ClusterDeco(
        val color: String? = null,
        val background: String? = null,
        val textDecorationLine: String? = null,
        val decorationColor: String? = null,
        val linkTarget: String? = null,
        val linkId: String? = null,
    )

    private fun decoFor(
        range: TextRange,
        colorSpans: List<ColorSpan>,
        richTextSpans: List<RichTextSpan>,
    ): ClusterDeco {
        val off = range.start
        var color = colorSpans.lastOrNull { off >= it.start && off < it.end }?.let { argbToCss(it.argb) }

        val lines = LinkedHashSet<String>()
        var decorationColor: String? = null
        var background: String? = null
        var linkTarget: String? = null
        var linkId: String? = null
        for ((index, s) in richTextSpans.withIndex()) {
            if (off < s.range.start || off >= s.range.end) continue
            when (val role = s.role) {
                RichTextRole.Underline -> { lines += "underline"; s.paint.argb?.let { decorationColor = argbToCss(it) } }
                RichTextRole.LineThrough -> lines += "line-through"
                RichTextRole.Background -> s.paint.argb?.let { background = argbToCss(it) }
                RichTextRole.InlineCode -> background = argbToCss(s.paint.argb ?: INLINE_CODE_BACKGROUND)
                is RichTextRole.Link -> {
                    linkTarget = role.target
                    linkId = "link-${s.range.start}-${s.range.end}-$index"
                    lines += "underline"
                    if (color == null) color = LINK_COLOR
                }
            }
        }
        val textDecorationLine = if (lines.isEmpty()) null else lines.joinToString(" ")
        return ClusterDeco(color, background, textDecorationLine, decorationColor, linkTarget, linkId)
    }

    /**
     * LinkFragmentSharedHover: a source link may be split into multiple DOM nodes
     * by Tiqian-owned line breaking. Hover/focus is still a logical link state,
     * so all fragments with the same link id animate together.
     */
    private fun installLinkGroupInteractions(host: HTMLElement) {
        val links = host.querySelectorAll("a[data-tq-link-id]")
        for (i in 0 until links.length) {
            val link = links.item(i) as? HTMLElement ?: continue
            link.addEventListener("mouseenter") { setLinkGroupActive(host, link, true) }
            link.addEventListener("mouseleave") { setLinkGroupActive(host, link, false) }
            link.addEventListener("focus") { setLinkGroupActive(host, link, true) }
            link.addEventListener("blur") { setLinkGroupActive(host, link, false) }
        }
    }

    private fun setLinkGroupActive(host: HTMLElement, link: HTMLElement, active: Boolean) {
        val id = link.getAttribute("data-tq-link-id") ?: return
        val group = host.querySelectorAll("a[data-tq-link-id=\"$id\"]")
        for (i in 0 until group.length) {
            val item = group.item(i) as? HTMLElement ?: continue
            val color = if (active) LINK_HOVER_COLOR else item.getAttribute("data-tq-link-color") ?: LINK_COLOR
            val decorationColor = if (active) {
                LINK_HOVER_COLOR
            } else {
                item.getAttribute("data-tq-link-decoration-color") ?: color
            }
            item.style.setProperty("color", color)
            item.style.setProperty("text-decoration-color", decorationColor)
        }
    }

    private fun wavyLinePath(left: Float, right: Float, y: Float, fontSize: Float): String {
        val halfWave = (fontSize * WAVY_HALF_WAVE_EM).coerceAtLeast(1f)
        val amplitude = fontSize * WAVY_AMPLITUDE_EM
        val path = StringBuilder("M $left $y")
        var x = left
        var up = true
        while (x < right - WAVY_ENDPOINT_EPSILON_PX) {
            val rawNextX = x + halfWave
            val nextX = if (rawNextX >= right - WAVY_ENDPOINT_EPSILON_PX) right else rawNextX
            val controlY = if (up) y - amplitude * 2f else y + amplitude * 2f
            path.append(" Q ${(x + nextX) / 2f} $controlY $nextX $y")
            x = nextX
            up = !up
        }
        return path.toString()
    }

    private fun colorAt(offset: Int, colorSpans: List<ColorSpan>): String =
        colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.let { argbToCss(it.argb) } ?: "currentColor"

    private val metricsCtx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    private fun Double.toFloatOrNull(): Float? =
        if (isFinite() && this > 0.0) toFloat() else null

    /** ARGB Int → CSS `rgba(...)`. */
    private fun argbToCss(argb: Int): String {
        val a = ((argb ushr 24) and 0xFF) / 255.0
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return "rgba($r, $g, $b, $a)"
    }

    /**
     * BrowserVerticalBopomofoToneGlyphMetrics:
     * CSS vertical text paints the correct TC `vert` glyph, but the web platform
     * does not expose that glyph's ink bounds to DOM/canvas. These ratios mirror
     * Skia's `Font.getBounds(vertGlyphIds(...))` path with HarfBuzz extents for
     * PingFang TC Regular/Semibold (UPEM 1000), the system TC face preferred by
     * [WebFontFamilies]. Weight interpolation only selects between those two
     * measured profiles; it is a renderer fallback, not a layout decision.
     */
    private fun browserVerticalBopomofoToneInkWidthEm(text: String, fontWeight: Int): Float {
        val regular = when (text) {
            "ˇ" -> BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR
            else -> BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR
        }
        val semibold = when (text) {
            "ˇ" -> BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD
            else -> BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD
        }
        val t = ((fontWeight - 400) / 300f).coerceIn(0f, 1f)
        return regular + (semibold - regular) * t
    }

    private const val INLINE_CODE_BACKGROUND = 0x1A000000
    private const val LINK_COLOR = "#0969da"
    private const val LINK_HOVER_COLOR = "#0550ae"
    private const val SVG_NS = "http://www.w3.org/2000/svg"
    private const val BASELINE_METRIC_PROBE = "中"
    private const val BOPOMOFO_LANG = "zh-Hant-TW"

    // Interlinear line geometry (ADR 0024/0030): the web underline sits at
    // baseline + 0.18em, with a slightly heavier 0.08em stroke so it reads at
    // browser text sizes while staying clear of the CJK face.
    private const val UNDERLINE_OFFSET_EM = 0.18f
    private const val LINE_THICKNESS_EM = 0.08f
    private const val EMPHASIS_DOT_SCALE = 0.85f
    private const val RUBY_ASCENT_RATIO = 0.8f // fallback 注文 ascent when font metrics are unavailable
    private const val BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE = 0.82f
    private const val BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR = 0.404f
    private const val BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD = 0.446f
    private const val BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR = 0.644f
    private const val BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD = 0.682f
    private const val WAVY_HALF_WAVE_EM = 0.2f
    private const val WAVY_AMPLITUDE_EM = 0.06f
    private const val WAVY_ENDPOINT_EPSILON_PX = 0.01f
}
