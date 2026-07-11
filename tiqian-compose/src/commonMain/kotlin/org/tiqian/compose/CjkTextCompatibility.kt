package org.tiqian.compose

import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.text.style.TextOverflow
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
}

/**
 * Compose text features Tiqian accepts at the boundary but cannot yet preserve faithfully. The list
 * is intentionally about semantics, not implementation accidents, so dogfooding can turn each issue
 * into a Tiqian fixture or model/backend task.
 */
enum class CjkTextCapabilityIssue {
    ParagraphStyleRanges,
    /** Retained for callers compiled against older reports; current `LinkAnnotation` ranges and clicks are supported. */
    LinkAnnotations,
    /** Always-on link styles are supported; focus, hover, and press styles still need stateful rendering. */
    LinkInteractionStyles,
    UrlAnnotations,
    TtsAnnotations,
    InlinePlaceholders,
    UnknownStringAnnotations,
    BrushForeground,
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
    OverflowEllipsis,
}

/**
 * Reports which parts of [this] and [style] the current Tiqian Compose frontend cannot yet preserve
 * faithfully. This is a diagnostic boundary, not a host-renderer switch:
 *
 * ```
 * val compatibility = annotated.cjkTextCompatibility(style, overflow = overflow)
 * check(compatibility.canPreserveAllKnownSemantics) { compatibility.issues }
 * CjkText(annotated, style = style, overflow = overflow)
 * ```
 */
@OptIn(ExperimentalTextApi::class)
@Suppress("DEPRECATION")
fun AnnotatedString.cjkTextCompatibility(
    style: ComposeTextStyle = ComposeTextStyle.Default,
    overflow: TextOverflow = TextOverflow.Clip,
): CjkTextCompatibility {
    val issues = linkedSetOf<CjkTextCapabilityIssue>()

    if (paragraphStyles.isNotEmpty()) issues += CjkTextCapabilityIssue.ParagraphStyleRanges
    if (getUrlAnnotations(0, length).isNotEmpty()) issues += CjkTextCapabilityIssue.UrlAnnotations
    if (getTtsAnnotations(0, length).isNotEmpty()) issues += CjkTextCapabilityIssue.TtsAnnotations
    if (text.any { it == InlinePlaceholderChar }) issues += CjkTextCapabilityIssue.InlinePlaceholders

    val supportedStringTags = setOf(CjkDecorationTag, CjkRubyTag, CjkBopomofoTag, CjkRichTextTag)
    if (getStringAnnotations(0, length).any { it.tag !in supportedStringTags }) {
        issues += CjkTextCapabilityIssue.UnknownStringAnnotations
    }

    style.collectCapabilityIssues(issues)
    if (overflow != TextOverflow.Clip && overflow != TextOverflow.Visible) {
        issues += CjkTextCapabilityIssue.OverflowEllipsis
    }
    spanStyles.forEach { it.item.collectCapabilityIssues(issues) }
    getLinkAnnotations(0, length).forEach { link ->
        val linkStyles = link.item.styles ?: return@forEach
        linkStyles.style?.collectCapabilityIssues(issues)
        if (
            linkStyles.focusedStyle != null ||
            linkStyles.hoveredStyle != null ||
            linkStyles.pressedStyle != null
        ) {
            issues += CjkTextCapabilityIssue.LinkInteractionStyles
        }
    }

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
    if (shadow != null && shadow != Shadow.None) issues += CjkTextCapabilityIssue.Shadow
    if (drawStyle != null && drawStyle != Fill) issues += CjkTextCapabilityIssue.DrawStyle
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
