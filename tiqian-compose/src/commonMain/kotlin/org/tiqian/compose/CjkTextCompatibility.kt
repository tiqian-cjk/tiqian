package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.unit.TextUnit

/** U+FFFC OBJECT REPLACEMENT CHARACTER, used by Compose inline content placeholders. */
private const val InlinePlaceholderChar = '\uFFFC'

/**
 * Capability report for rendering a Compose [AnnotatedString] through Tiqian without losing
 * rich-text semantics. Tiqian still accepts the input; [issues] names the semantics the current
 * Compose frontend cannot yet preserve faithfully.
 */
data class CjkTextCompatibility(
    val issues: Set<CjkTextCapabilityIssue> = emptySet(),
) {
    val canPreserveAllKnownSemantics: Boolean
        get() = issues.isEmpty()

    @Deprecated(
        "Use canPreserveAllKnownSemantics. Tiqian does not use this report to route to Compose Text.",
        ReplaceWith("canPreserveAllKnownSemantics"),
    )
    val canRenderWithTiqian: Boolean
        get() = canPreserveAllKnownSemantics

    @Deprecated(
        "Use issues. The report records Tiqian capability gaps; it is not a host-renderer route.",
        ReplaceWith("issues"),
    )
    val unsupportedReasons: Set<CjkTextCapabilityIssue>
        get() = issues
}

/**
 * Compose text features Tiqian accepts at the boundary but cannot yet preserve faithfully. The list
 * is intentionally about semantics, not implementation accidents, so dogfooding can turn each issue
 * into a Tiqian fixture or model/backend task.
 */
enum class CjkTextCapabilityIssue {
    ParagraphStyleRanges,
    LinkAnnotations,
    UrlAnnotations,
    TtsAnnotations,
    InlinePlaceholders,
    UnknownStringAnnotations,
    BrushForeground,
    BackgroundColor,
    TextDecoration,
    Shadow,
    DrawStyle,
    BaselineShift,
    GeometricTransform,
    LocaleList,
    FontSynthesis,
    FontFeatureSettings,
    LetterSpacing,
    NonGenericFontFamily,
    PlatformStyle,
    TextAlign,
    TextDirection,
    TextIndent,
    LineHeightStyle,
    LineBreak,
    Hyphens,
    TextMotion,
}

@Deprecated(
    "Use CjkTextCapabilityIssue. Tiqian reports capability gaps instead of host-renderer reasons.",
    ReplaceWith("CjkTextCapabilityIssue"),
)
typealias CjkTextUnsupportedReason = CjkTextCapabilityIssue

/**
 * Reports which parts of [this] and [style] the current Tiqian Compose frontend cannot yet preserve
 * faithfully. This is a diagnostic boundary, not a host-renderer switch:
 *
 * ```
 * val compatibility = annotated.cjkTextCompatibility(style)
 * check(compatibility.canPreserveAllKnownSemantics) { compatibility.issues }
 * CjkParagraph(annotated, style = style)
 * ```
 */
@OptIn(ExperimentalTextApi::class)
@Suppress("DEPRECATION")
fun AnnotatedString.cjkTextCompatibility(
    style: ComposeTextStyle = ComposeTextStyle.Default,
): CjkTextCompatibility {
    val issues = linkedSetOf<CjkTextCapabilityIssue>()

    if (paragraphStyles.isNotEmpty()) issues += CjkTextCapabilityIssue.ParagraphStyleRanges
    if (hasLinkAnnotations(0, length)) issues += CjkTextCapabilityIssue.LinkAnnotations
    if (getUrlAnnotations(0, length).isNotEmpty()) issues += CjkTextCapabilityIssue.UrlAnnotations
    if (getTtsAnnotations(0, length).isNotEmpty()) issues += CjkTextCapabilityIssue.TtsAnnotations
    if (text.any { it == InlinePlaceholderChar }) issues += CjkTextCapabilityIssue.InlinePlaceholders

    val supportedStringTags = setOf(CjkDecorationTag, CjkRubyTag, CjkBopomofoTag)
    if (getStringAnnotations(0, length).any { it.tag !in supportedStringTags }) {
        issues += CjkTextCapabilityIssue.UnknownStringAnnotations
    }

    style.collectCapabilityIssues(issues)
    spanStyles.forEach { it.item.collectCapabilityIssues(issues) }

    return CjkTextCompatibility(issues)
}

private fun ComposeTextStyle.collectCapabilityIssues(issues: MutableSet<CjkTextCapabilityIssue>) {
    toSpanStyle().collectCapabilityIssues(issues)
    if (textAlign != TextAlign.Unspecified) issues += CjkTextCapabilityIssue.TextAlign
    if (textDirection != TextDirection.Unspecified) issues += CjkTextCapabilityIssue.TextDirection
    if (textIndent != null) issues += CjkTextCapabilityIssue.TextIndent
    if (lineHeightStyle != null) issues += CjkTextCapabilityIssue.LineHeightStyle
    if (lineBreak != LineBreak.Unspecified) issues += CjkTextCapabilityIssue.LineBreak
    if (hyphens != Hyphens.Unspecified) issues += CjkTextCapabilityIssue.Hyphens
    if (textMotion != null) issues += CjkTextCapabilityIssue.TextMotion
    if (platformStyle != null) issues += CjkTextCapabilityIssue.PlatformStyle
}

private fun SpanStyle.collectCapabilityIssues(issues: MutableSet<CjkTextCapabilityIssue>) {
    if (brush != null) issues += CjkTextCapabilityIssue.BrushForeground
    if (background != Color.Unspecified) issues += CjkTextCapabilityIssue.BackgroundColor
    if (textDecoration != null && textDecoration != TextDecoration.None) {
        issues += CjkTextCapabilityIssue.TextDecoration
    }
    if (shadow != null && shadow != Shadow.None) issues += CjkTextCapabilityIssue.Shadow
    if (drawStyle != null && drawStyle != Fill) issues += CjkTextCapabilityIssue.DrawStyle
    if (baselineShift != null && baselineShift != BaselineShift.None) issues += CjkTextCapabilityIssue.BaselineShift
    val geometricTransform = textGeometricTransform
    if (geometricTransform != null && !geometricTransform.isIdentity()) {
        issues += CjkTextCapabilityIssue.GeometricTransform
    }
    if (localeList != null) issues += CjkTextCapabilityIssue.LocaleList
    if (fontSynthesis != null) issues += CjkTextCapabilityIssue.FontSynthesis
    if (fontFeatureSettings != null) issues += CjkTextCapabilityIssue.FontFeatureSettings
    if (letterSpacing != TextUnit.Unspecified) issues += CjkTextCapabilityIssue.LetterSpacing
    if (fontFamily != null && fontFamily !is GenericFontFamily) {
        issues += CjkTextCapabilityIssue.NonGenericFontFamily
    }
    if (platformStyle != null) issues += CjkTextCapabilityIssue.PlatformStyle
}

private fun TextGeometricTransform.isIdentity(): Boolean =
    scaleX == 1.0f && skewX == 0.0f
