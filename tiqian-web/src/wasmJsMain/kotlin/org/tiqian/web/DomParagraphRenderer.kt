package org.tiqian.web

import kotlinx.browser.document
import org.tiqian.core.LayoutResult
import org.tiqian.core.positionedClusters
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.HTMLElement

/**
 * `PreBrokenLineDom` (ADR 0039): the engine owns the whole line layout; this
 * renderer only PAINTS its result into the DOM. Half-width punctuation, 中西
 * autospace, justify, 推入推出 and the line-end hyphen all come from the engine,
 * not the browser — the browser never re-wraps or word-breaks.
 *
 * `InlineFlowLineDom`: each line is a block, and within it the glyphs are plain
 * INLINE spans laid out by flow, with the engine's inter-glyph spacing injected
 * as `margin-left` (NEGATIVE for half-width punctuation, pulling the next glyph
 * onto the punctuation's blank half). Because the glyphs share ONE line box,
 * the native selection highlight is continuous — no per-glyph seams or gaps that
 * absolute per-glyph positioning produces. The margin is `drawX[i] − (drawX[i-1]
 * + advance[i-1])`, and `advance` is the web shaper's own `measureText` width, so
 * flow lands each glyph exactly at the engine's `drawX` (measure == render).
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

        for (line in result.lines) {
            val h = line.bottom - line.top
            val lineDiv = document.createElement("div") as HTMLElement
            lineDiv.style.apply {
                setProperty("height", "${h}px")
                setProperty("line-height", "${h}px")
                setProperty("white-space", "pre") // engine owns wrapping; never let the browser re-break
                setProperty("font-size", "${fontSize}px")
            }

            val cells = result.positionedClusters(line)
                .filter { result.clusters[it.clusterIndex].displayText.isNotEmpty() }
            var naturalEnd = 0f // running x (from line start) where the previous glyph naturally ends
            for (pc in cells) {
                val cluster = result.clusters[pc.clusterIndex]
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                lineDiv.appendChild(
                    glyphSpan(
                        cluster.displayText, cluster.text, pc.drawX - naturalEnd, fonts.forRoleName(roleName),
                    ),
                )
                naturalEnd = pc.drawX + cluster.advance
            }
            // EngineOwnedHyphenation: the engine reserved the hyphen inside the
            // measure; place it at indent+visualWidth. The browser never hyphenates.
            if (line.hyphenAdvance > 0f) {
                lineDiv.appendChild(
                    glyphSpan("-", "-", (line.indent + line.visualWidth) - naturalEnd, fonts.latin),
                )
            }
            host.appendChild(lineDiv)
        }
    }

    private fun glyphSpan(
        text: String,
        source: String,
        marginLeft: Float,
        fontFamily: String,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = text
        // Source-faithful copy: a CLREQ-substituted cluster (——→⸺, ……→⋯) shows
        // the display form but must COPY as source. The copy handler reads this.
        if (source != text) span.setAttribute("data-tq-src", source)
        span.style.apply {
            setProperty("margin-left", "${marginLeft}px")
            setProperty("font-family", fontFamily)
            setProperty("white-space", "pre")
        }
        return span
    }
}
