package org.tiqian.web

import kotlinx.browser.document
import org.tiqian.core.LayoutResult
import org.tiqian.core.positionedClusters
import org.tiqian.shaping.web.WebFonts
import org.w3c.dom.HTMLElement

/**
 * `PreBrokenLineDom` (ADR 0039): the engine owns the whole line layout; this
 * renderer only PAINTS its result into the DOM. Each engine line becomes one
 * block; every cluster is placed at the engine's own `drawX` (so half-width
 * punctuation / 中西 autospace / justify / 推入推出 all come from the engine,
 * not the browser). The engine's line-end hyphen (`EngineOwnedHyphenation`) is
 * drawn explicitly — the browser never word-breaks. Text stays real DOM text
 * (selectable, copyable), unlike a canvas raster.
 */
object DomParagraphRenderer {

    fun render(host: HTMLElement, result: LayoutResult) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        val fontSize = result.input.textStyle.fontSize

        for (line in result.lines) {
            val h = line.bottom - line.top
            val lineDiv = document.createElement("div") as HTMLElement
            lineDiv.style.setProperty("position", "relative")
            lineDiv.style.setProperty("height", "${h}px")

            for (pc in result.positionedClusters(line)) {
                val cluster = result.clusters[pc.clusterIndex]
                if (cluster.displayText.isBlank()) continue
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                lineDiv.appendChild(
                    glyphSpan(cluster.displayText, pc.drawX, h, fontSize, WebFonts.forRoleName(roleName)),
                )
            }

            // EngineOwnedHyphenation: the engine already reserved the hyphen inside
            // the measure; draw it at indent+visualWidth. The browser never hyphenates.
            if (line.hyphenAdvance > 0f) {
                lineDiv.appendChild(
                    glyphSpan("-", line.indent + line.visualWidth, h, fontSize, WebFonts.LATIN),
                )
            }
            host.appendChild(lineDiv)
        }
    }

    private fun glyphSpan(
        text: String,
        left: Float,
        lineHeight: Float,
        fontSize: Float,
        fontFamily: String,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = text
        span.style.apply {
            setProperty("position", "absolute")
            setProperty("left", "${left}px")
            setProperty("top", "0")
            setProperty("line-height", "${lineHeight}px")
            setProperty("font-size", "${fontSize}px")
            setProperty("font-family", fontFamily)
            setProperty("white-space", "pre")
        }
        return span
    }
}
