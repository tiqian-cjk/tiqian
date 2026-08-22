package org.tiqian.ffi.js

import org.tiqian.core.Ic
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.InlineBoxOuterSpacing
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.LineBreakSpan
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.layout.toPreparedParagraphJson
import org.tiqian.shaping.TextShaper
import org.tiqian.font.FontMetricsResolver

/**
 * Separator-encoded wire ABI of the js export face (ADR 0050). Callers pass
 * flat primitives; the plan comes back as one JSON string. The encoding serves
 * the browser paths: `precompute.js`, `layout-worker.js`, and the parity
 * oracle. Native hosts use the packed binary ABI of `ffi/native`.
 */

internal const val RECORD_SEPARATOR = '\u001e'
internal const val FIELD_SEPARATOR = '\u001d'
internal const val FAMILY_SEPARATOR = '\u001f'

/** Platform-provided shaping/metrics pair behind a session id. */
internal class PrecomputeBackends(
    val textShaper: TextShaper,
    val fontMetricsResolver: FontMetricsResolver,
)

internal fun parseBoundaries(value: String, textLength: Int): Set<Int> =
    value.split(',')
        .filter(String::isNotBlank)
        .map { it.toInt() }
        .onEach { require(it in 0..textLength) { "InvalidSourceBoundary" } }
        .toSet()

internal fun parseTextSpans(value: String, locale: String, textLength: Int): List<TextSpan> =
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

internal fun parseInlineBoxes(value: String, textLength: Int): List<InlineBoxSpan> =
    value.split(RECORD_SEPARATOR)
        .filter(String::isNotBlank)
        .map { record ->
            val fields = record.split(FIELD_SEPARATOR)
            require(fields.size == 4 || fields.size == 5) { "InvalidInlineBoxWire" }
            val start = fields[0].toInt()
            val end = fields[1].toInt()
            val inlineStart = fields[2].toFloat()
            val inlineEnd = fields[3].toFloat()
            require(start in 0 until end && end <= textLength) { "InvalidInlineBoxRange" }
            require(inlineStart.isFinite() && inlineEnd.isFinite()) { "InvalidInlineBoxGeometry" }
            val outerSpacing = fields.getOrNull(4)
                ?.let(InlineBoxOuterSpacing::valueOf)
                ?: InlineBoxOuterSpacing.Narrow
            InlineBoxSpan(TextRange(start, end), inlineStart, inlineEnd, outerSpacing)
        }

internal fun parseLineBreakSpans(value: String, textLength: Int): List<LineBreakSpan> =
    value.split(RECORD_SEPARATOR)
        .filter(String::isNotBlank)
        .map { record ->
            val fields = record.split(FIELD_SEPARATOR)
            require(fields.size == 3) { "InvalidLineBreakSpanWire" }
            val start = fields[0].toInt()
            val end = fields[1].toInt()
            require(start in 0 until end && end <= textLength) { "InvalidLineBreakSpanRange" }
            LineBreakSpan(TextRange(start, end), LineBreakPolicy.valueOf(fields[2]))
        }

/** Structured paragraph ABI: semantics stay in the host; metric spans enter the real layout pipeline. */
internal fun precomputeParagraphPlan(
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
    lineBreakSpans: String,
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
            lineBreakSpans = parseLineBreakSpans(lineBreakSpans, text.length),
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
    val backends = buildPrecomputeBackends(fontSessionId)
    val result = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        fontMetricsResolver = backends.fontMetricsResolver,
        textShaper = backends.textShaper,
    ).layout(input)
    return result.toPreparedParagraphJson()
}
