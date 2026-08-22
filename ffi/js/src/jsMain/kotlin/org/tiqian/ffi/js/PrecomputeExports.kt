@file:OptIn(kotlin.js.ExperimentalJsExport::class)

package org.tiqian.ffi.js

import kotlin.js.JsExport

/**
 * Stable, narrow JSON ABI consumed by `@tiqian/precompute`.
 *
 * The caller has already prepared an immutable exact-font session. Keeping the
 * exported values primitive avoids exposing the core model through the JavaScript
 * ABI while the returned plan remains inspectable and versioned. Parsing and
 * the layout call live in `PrecomputeWire.kt`. ADR 0050.
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
    lineBreakSpans = "",
)

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
    lineBreakSpans: String,
): String = precomputeParagraphPlan(
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
    sourceBoundaries = sourceBoundaries,
    textSpans = textSpans,
    inlineBoxes = inlineBoxes,
    lineBreakSpans = lineBreakSpans,
)

internal fun buildPrecomputeBackends(fontSessionId: String): PrecomputeBackends =
    PrecomputeBackends(
        textShaper = HarfBuzzBuildTextShaper(fontSessionId),
        fontMetricsResolver = HarfBuzzBuildFontMetricsResolver(fontSessionId),
    )

fun main() = Unit
