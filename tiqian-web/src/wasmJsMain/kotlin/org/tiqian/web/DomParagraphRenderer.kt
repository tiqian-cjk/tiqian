package org.tiqian.web

import kotlinx.browser.document
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.LayoutResult
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.positionedClusters
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.HTMLElement

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
 * `CssNativeDecorations`: rich text is painted with per-cluster CSS, which on web
 * gets NATIVE `text-decoration-skip-ink` — the underline / 专名号 / 书名号 (wavy)
 * break around descenders for free, and stay continuous across the engine's
 * `letter-spacing` gaps (unlike the predecessor 赫蹏, whose inserted-whitespace
 * elements broke the line). 着重号 uses CSS `text-emphasis` on exactly the
 * clusters the engine marked (Han only, punctuation skipped). Color / background
 * ride the same per-cluster style.
 */
object DomParagraphRenderer {

    fun render(
        host: HTMLElement,
        result: LayoutResult,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan> = emptyList(),
        richTextSpans: List<RichTextSpan> = emptyList(),
    ) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        val fontSize = result.input.textStyle.fontSize
        val decorations = result.input.decorations
        // Clusters the engine actually dotted (着重号 skips punctuation, ADR 0018).
        val emphasized = result.debug.decorationDecisions
            .filter { it.applied && it.kind == DecorationKind.Emphasis.name }
            .map { it.clusterRange }

        // Natural shaped width per cluster from the GLYPH advances (which exclude
        // layout-owned glue/justify — see the class doc). Cluster.advance carries
        // that glue and would cancel the margins.
        val naturalWidth = HashMap<TextRange, Float>()
        for (run in result.glyphRuns) {
            for (glyph in run.glyphs) {
                naturalWidth[glyph.clusterRange] = (naturalWidth[glyph.clusterRange] ?: 0f) + glyph.advance
            }
        }

        for (line in result.lines) {
            val h = line.bottom - line.top
            val lineDiv = document.createElement("div") as HTMLElement
            lineDiv.style.apply {
                setProperty("height", "${h}px")
                setProperty("line-height", "${h}px")
                setProperty("white-space", "pre") // engine owns wrapping; never let the browser re-break
                setProperty("font-size", "${fontSize}px")
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

            val cells = result.positionedClusters(line)
                .filter { result.clusters[it.clusterIndex].displayText.isNotEmpty() }
            for (i in cells.indices) {
                val pc = cells[i]
                val cluster = result.clusters[pc.clusterIndex]
                val nat = naturalWidth[cluster.range] ?: cluster.advance
                // Leading offset for the first glyph (段首缩进); the rest flow.
                val leadingMargin = if (i == 0) pc.drawX else 0f
                // Trailing gap = the engine's glue/justify after this glyph. It MUST land in
                // a box the native selection covers, or the highlight gets a hole there.
                // `letter-spacing` is covered (but splays a multi-letter word into "t h e");
                // `padding-right` does NOT splay but is NOT covered by ::selection. So a
                // single-glyph cluster carries its gap with letter-spacing, and a multi-letter
                // word is split — its last letter (a single glyph) carries the gap with
                // letter-spacing (`SelectableTrailingGapViaLastLetter`), keeping the word body
                // intact and the gap selectable.
                val trailingGap = if (i + 1 < cells.size) {
                    cells[i + 1].drawX - pc.drawX - nat
                } else {
                    0f
                }
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                val family = fonts.forRoleName(roleName)
                val display = cluster.displayText
                val deco = decoFor(cluster.range, colorSpans, richTextSpans, decorations, emphasized)
                // Split only a plain (non-substituted) multi-letter word, so the two halves
                // still copy back to the exact source; a substituted cluster stays whole.
                if (display.length > 1 && trailingGap != 0f && cluster.text == display) {
                    lineDiv.appendChild(glyphSpan(display.dropLast(1), display.dropLast(1), leadingMargin, 0f, false, family, deco))
                    lineDiv.appendChild(glyphSpan(display.takeLast(1), display.takeLast(1), 0f, trailingGap, true, family, deco))
                } else {
                    lineDiv.appendChild(glyphSpan(display, cluster.text, leadingMargin, trailingGap, display.length == 1, family, deco))
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
                lineDiv.appendChild(
                    glyphSpan("-", "-", (line.indent + line.visualWidth) - flowEnd, 0f, true, fonts.latin, ClusterDeco()),
                )
            }
            host.appendChild(lineDiv)
        }
    }

    private fun glyphSpan(
        text: String,
        source: String,
        marginLeft: Float,
        trailingGap: Float,
        singleGlyph: Boolean,
        fontFamily: String,
        deco: ClusterDeco,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = text
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
            setProperty("white-space", "pre")
            // CssNativeDecorations — continuous across letter-spacing, native skip-ink.
            deco.color?.let { setProperty("color", it) }
            deco.background?.let { setProperty("background-color", it) }
            deco.textDecoration?.let {
                setProperty("text-decoration", it)
                deco.decorationColor?.let { c -> setProperty("text-decoration-color", c) }
            }
            if (deco.emphasis) {
                setProperty("text-emphasis", "filled dot")
                setProperty("text-emphasis-position", "under") // 着重号 sits UNDER the char (horizontal CJK)
                setProperty("-webkit-text-emphasis", "filled dot")
                setProperty("-webkit-text-emphasis-position", "under")
            }
        }
        return span
    }

    /** Per-cluster CSS resolved from the engine's render-only spans/decorations. */
    private data class ClusterDeco(
        val color: String? = null,
        val background: String? = null,
        val textDecoration: String? = null,
        val decorationColor: String? = null,
        val emphasis: Boolean = false,
    )

    private fun decoFor(
        range: TextRange,
        colorSpans: List<ColorSpan>,
        richTextSpans: List<RichTextSpan>,
        decorations: List<org.tiqian.core.DecorationSpan>,
        emphasized: List<TextRange>,
    ): ClusterDeco {
        val off = range.start
        val color = colorSpans.lastOrNull { off >= it.start && off < it.end }?.let { argbToCss(it.argb) }

        val lines = LinkedHashSet<String>()
        var wavy = false
        var decorationColor: String? = null
        var background: String? = null
        for (s in richTextSpans) {
            if (off < s.range.start || off >= s.range.end) continue
            when (s.role) {
                RichTextRole.Underline -> { lines += "underline"; s.paint.argb?.let { decorationColor = argbToCss(it) } }
                RichTextRole.LineThrough -> lines += "line-through"
                RichTextRole.Background -> s.paint.argb?.let { background = argbToCss(it) }
                RichTextRole.InlineCode -> background = argbToCss(s.paint.argb ?: INLINE_CODE_BACKGROUND)
                else -> {}
            }
        }
        for (d in decorations) {
            if (off < d.range.start || off >= d.range.end) continue
            when (d.kind) {
                DecorationKind.ProperNoun -> lines += "underline" // 专名号: straight underline
                DecorationKind.BookTitle -> { lines += "underline"; wavy = true } // 书名号甲式: wavy
                else -> {} // Emphasis handled via text-emphasis; Mourning frame is a later slice
            }
        }
        val textDecoration = if (lines.isEmpty()) null else lines.joinToString(" ") + if (wavy) " wavy" else ""
        val emphasis = emphasized.any { off >= it.start && off < it.end }
        return ClusterDeco(color, background, textDecoration, decorationColor, emphasis)
    }

    /** ARGB Int → CSS `rgba(...)`. */
    private fun argbToCss(argb: Int): String {
        val a = ((argb ushr 24) and 0xFF) / 255.0
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return "rgba($r, $g, $b, $a)"
    }

    private const val INLINE_CODE_BACKGROUND = 0x1A000000
}
