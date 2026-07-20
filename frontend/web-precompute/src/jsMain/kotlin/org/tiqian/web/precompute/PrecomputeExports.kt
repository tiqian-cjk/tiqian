@file:OptIn(kotlin.js.ExperimentalJsExport::class)

package org.tiqian.web.precompute

import kotlin.js.JsExport
import org.tiqian.core.Ic
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.layout.toPreparedParagraphJson

/**
 * Stable, narrow JSON ABI consumed by `@tiqian/prose/precompute`.
 *
 * The caller has already prepared an immutable exact-font session. Keeping the
 * exported values primitive avoids exposing the core model through the JavaScript
 * ABI while the returned plan remains inspectable and versioned.
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
): String = precomputeParagraph(
    fontSessionId = fontSessionId,
    text = text,
    maxWidthPx = maxWidthPx,
    fontFamilies = fontFamilies,
    fontSizePx = fontSizePx,
    lineHeightPx = lineHeightPx,
    locale = locale,
    fontWeight = fontWeight,
    italic = italic,
    firstLineIndentIc = firstLineIndentIc,
    lineLengthGridEnabled = lineLengthGridEnabled,
    sourceBoundaries = "",
    textSpans = "",
    inlineBoxes = "",
)

private const val RECORD_SEPARATOR = '\u001e'
private const val FIELD_SEPARATOR = '\u001d'
private const val FAMILY_SEPARATOR = '\u001f'

private fun parseBoundaries(value: String, textLength: Int): Set<Int> =
    value.split(',')
        .filter(String::isNotBlank)
        .map { it.toInt() }
        .onEach { require(it in 0..textLength) { "InvalidSourceBoundary" } }
        .toSet()

private fun parseTextSpans(value: String, locale: String, textLength: Int): List<TextSpan> =
    value.split(RECORD_SEPARATOR)
        .filter(String::isNotBlank)
        .map { record ->
            val fields = record.split(FIELD_SEPARATOR)
            require(fields.size == 7) { "InvalidTextSpanWire" }
            val start = fields[0].toInt()
            val end = fields[1].toInt()
            require(start in 0 until end && end <= textLength) { "InvalidTextSpanRange" }
            val families = fields[2].split(FAMILY_SEPARATOR).filter(String::isNotBlank)
            require(families.isNotEmpty()) { "MissingTextSpanFontFamilies" }
            val fontSize = fields[3].toFloat()
            val fontWeight = fields[4].toInt()
            val italic = when (fields[5]) {
                "true" -> true
                "false" -> false
                else -> error("InvalidTextSpanItalic")
            }
            val baselineShift = fields[6].toFloat()
            require(fontSize.isFinite() && fontSize > 0f) { "InvalidTextSpanFontSize" }
            require(fontWeight in 1..1000) { "InvalidTextSpanFontWeight" }
            require(baselineShift.isFinite()) { "InvalidTextSpanBaselineShift" }
            TextSpan(
                range = TextRange(start, end),
                style = TextStyle(
                    fontFamilies = families,
                    fontSize = fontSize,
                    locale = locale,
                    fontWeight = fontWeight,
                    italic = italic,
                    baselineShift = baselineShift,
                ),
            )
        }

private fun parseInlineBoxes(value: String, textLength: Int): List<InlineBoxSpan> =
    value.split(RECORD_SEPARATOR)
        .filter(String::isNotBlank)
        .map { record ->
            val fields = record.split(FIELD_SEPARATOR)
            require(fields.size == 4) { "InvalidInlineBoxWire" }
            val start = fields[0].toInt()
            val end = fields[1].toInt()
            val inlineStart = fields[2].toFloat()
            val inlineEnd = fields[3].toFloat()
            require(start in 0 until end && end <= textLength) { "InvalidInlineBoxRange" }
            require(inlineStart.isFinite() && inlineEnd.isFinite()) { "InvalidInlineBoxGeometry" }
            InlineBoxSpan(TextRange(start, end), inlineStart, inlineEnd)
        }

/** Structured paragraph ABI: semantics stay in JS; metric spans enter the real layout pipeline. */
@JsExport
fun precomputeParagraph(
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
    sourceBoundaries: String,
    textSpans: String,
    inlineBoxes: String,
): String {
    require(text.isNotBlank()) { "EmptyParagraph" }
    require(maxWidthPx.isFinite() && maxWidthPx > 0.0) { "InvalidMaximumMeasure" }
    require(fontSizePx.isFinite() && fontSizePx > 0.0) { "InvalidFontSize" }
    require(lineHeightPx.isFinite() && lineHeightPx > 0.0) { "InvalidLineHeight" }
    require(firstLineIndentIc.isFinite()) { "InvalidFirstLineIndent" }
    require(fontWeight in 1..1000) { "InvalidFontWeight" }

    val families = fontFamilies.split(FAMILY_SEPARATOR).filter(String::isNotBlank)
    require(families.isNotEmpty()) { "MissingExplicitFontFamilies" }

    val textStyle = TextStyle(
        fontFamilies = families,
        fontSize = fontSizePx.toFloat(),
        locale = locale,
        fontWeight = fontWeight,
        italic = italic,
    )
    val input = LayoutInput(
        content = TiqianTextContent(
            text = text,
            spans = parseTextSpans(textSpans, locale, text.length),
            sourceBoundaries = parseBoundaries(sourceBoundaries, text.length),
        ),
        textStyle = textStyle,
        paragraphStyle = ParagraphStyle(
            lineHeight = lineHeightPx.toFloat(),
            firstLineIndent = Ic(firstLineIndentIc.toFloat()),
            lineLengthGrid = LineLengthGrid(enabled = lineLengthGridEnabled),
        ),
        constraints = LayoutConstraints(maxWidth = maxWidthPx.toFloat()),
        inlineBoxes = parseInlineBoxes(inlineBoxes, text.length),
    )
    val result = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        fontMetricsResolver = HarfBuzzBuildFontMetricsResolver(fontSessionId),
        textShaper = HarfBuzzBuildTextShaper(fontSessionId),
    ).layout(input)
    return result.toPreparedParagraphJson()
}

fun main() = Unit
