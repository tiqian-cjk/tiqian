package org.tiqian.web

import kotlinx.browser.document
import org.tiqian.core.LayoutResult
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
 */
object DomParagraphRenderer {

    fun render(host: HTMLElement, result: LayoutResult, fonts: WebFontFamilies) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        val fontSize = result.input.textStyle.fontSize

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
                // Split only a plain (non-substituted) multi-letter word, so the two halves
                // still copy back to the exact source; a substituted cluster stays whole.
                if (display.length > 1 && trailingGap != 0f && cluster.text == display) {
                    lineDiv.appendChild(glyphSpan(display.dropLast(1), display.dropLast(1), leadingMargin, 0f, false, family))
                    lineDiv.appendChild(glyphSpan(display.takeLast(1), display.takeLast(1), 0f, trailingGap, true, family))
                } else {
                    lineDiv.appendChild(glyphSpan(display, cluster.text, leadingMargin, trailingGap, display.length == 1, family))
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
                    glyphSpan("-", "-", (line.indent + line.visualWidth) - flowEnd, 0f, true, fonts.latin),
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
        }
        return span
    }
}
