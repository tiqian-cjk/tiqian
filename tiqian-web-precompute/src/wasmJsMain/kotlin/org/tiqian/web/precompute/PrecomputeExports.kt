@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web.precompute

import kotlin.js.JsExport
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.layout.toPreparedParagraphJson

/**
 * Stable, narrow JSON ABI consumed by `@tiqian/prose/precompute`.
 *
 * The caller has already prepared an immutable exact-font session. Keeping the
 * exported values primitive avoids exposing the core model through experimental
 * Wasm interop while the returned plan remains inspectable and versioned.
 */
@JsExport
fun precomputePlainParagraph(
    fontSessionId: String,
    text: String,
    maxWidthPx: Double,
    fontFamilies: String,
    fontSizePx: Double,
    lineHeightPx: Double,
    locale: String,
    fontWeight: Int,
    italic: Boolean,
    firstLineIndentIc: Double,
    lineLengthGridEnabled: Boolean,
): String {
    require(text.isNotBlank()) { "EmptyParagraph" }
    require(maxWidthPx.isFinite() && maxWidthPx > 0.0) { "InvalidMaximumMeasure" }
    require(fontSizePx.isFinite() && fontSizePx > 0.0) { "InvalidFontSize" }
    require(lineHeightPx.isFinite() && lineHeightPx > 0.0) { "InvalidLineHeight" }
    require(firstLineIndentIc.isFinite()) { "InvalidFirstLineIndent" }
    require(fontWeight in 1..1000) { "InvalidFontWeight" }

    val families = fontFamilies.split('\u001f').filter(String::isNotBlank)
    require(families.isNotEmpty()) { "MissingExplicitFontFamilies" }

    val textStyle = TextStyle(
        fontFamilies = families,
        fontSize = fontSizePx.toFloat(),
        locale = locale,
        fontWeight = fontWeight,
        italic = italic,
    )
    val input = LayoutInput(
        content = TiqianTextContent(text),
        textStyle = textStyle,
        paragraphStyle = ParagraphStyle(
            lineHeight = lineHeightPx.toFloat(),
            firstLineIndent = Ic(firstLineIndentIc.toFloat()),
            lineLengthGrid = LineLengthGrid(enabled = lineLengthGridEnabled),
        ),
        constraints = LayoutConstraints(maxWidth = maxWidthPx.toFloat()),
    )
    val result = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        fontMetricsResolver = HarfBuzzBuildFontMetricsResolver(fontSessionId),
        textShaper = HarfBuzzBuildTextShaper(fontSessionId),
    ).layout(input)
    return result.toPreparedParagraphJson()
}

fun main() = Unit
