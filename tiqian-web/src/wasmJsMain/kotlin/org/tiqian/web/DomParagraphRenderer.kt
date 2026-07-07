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
 * `CopyTransparentSpacingSpans`: every cluster (spaces included) is a span in
 * SOURCE ORDER inside ONE positioned container — no per-line block boundaries.
 * So `Selection.toString()` concatenates source text with real spaces and no
 * injected newlines from soft wraps (ADR 0037 source-faithful copy). Residual
 * gap: codepoint-SUBSTITUTED clusters (`——`→`⸺`) still copy as the display
 * form; mapping those back to source needs a `copy` handler — a named follow-up.
 */
object DomParagraphRenderer {

    fun render(host: HTMLElement, result: LayoutResult, fonts: WebFontFamilies) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        val fontSize = result.input.textStyle.fontSize
        val height = result.lines.lastOrNull()?.bottom ?: 0f

        host.style.setProperty("position", "relative")
        host.style.setProperty("height", "${height}px")

        for (line in result.lines) {
            val h = line.bottom - line.top
            // ContiguousSelectionBoxes: each span fills its OCCUPIED cell — from its
            // own drawX to the next cluster's drawX — so the selection highlight
            // tiles the whole line instead of leaving gaps at every justify /
            // autospace / half-width-punctuation space (which belong to no glyph).
            // The glyph still paints at drawX (box left); a narrower punctuation
            // glyph just underfills its cell, a wider one overflows it — both fine.
            val cells = result.positionedClusters(line)
                .filter { result.clusters[it.clusterIndex].displayText.isNotEmpty() }
            for (i in cells.indices) {
                val pc = cells[i]
                val cluster = result.clusters[pc.clusterIndex]
                val cellRight = if (i + 1 < cells.size) cells[i + 1].drawX else pc.right
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                host.appendChild(
                    glyphSpan(
                        cluster.displayText, cluster.text, pc.drawX, line.top,
                        (cellRight - pc.drawX).coerceAtLeast(0f), h, fontSize,
                        fonts.forRoleName(roleName),
                    ),
                )
            }
            // EngineOwnedHyphenation: the engine reserved the hyphen inside the
            // measure; draw it at indent+visualWidth. The browser never hyphenates.
            if (line.hyphenAdvance > 0f) {
                host.appendChild(
                    glyphSpan("-", "-", line.indent + line.visualWidth, line.top, 0f, h, fontSize, fonts.latin),
                )
            }
        }
    }

    private fun glyphSpan(
        text: String,
        source: String,
        left: Float,
        top: Float,
        cellWidth: Float,
        lineHeight: Float,
        fontSize: Float,
        fontFamily: String,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = text
        // Source-faithful copy: a CLREQ-substituted cluster (——→⸺, ……→⋯) shows
        // the display form but must COPY as source. The copy handler reads this.
        if (source != text) span.setAttribute("data-tq-src", source)
        span.style.apply {
            setProperty("position", "absolute")
            setProperty("left", "${left}px")
            setProperty("top", "${top}px")
            setProperty("height", "${lineHeight}px")
            setProperty("line-height", "${lineHeight}px")
            setProperty("font-size", "${fontSize}px")
            setProperty("font-family", fontFamily)
            setProperty("white-space", "pre")
            // Fill the occupied cell so selection highlights tile (cellWidth 0 = the
            // line-end hyphen, which keeps its natural glyph width).
            if (cellWidth > 0f) {
                setProperty("display", "inline-block")
                setProperty("box-sizing", "border-box")
                setProperty("width", "${cellWidth}px")
            }
        }
        return span
    }
}
