package org.tiqian.android.view

import android.graphics.Color
import android.graphics.Typeface
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.text.style.ParagraphStyle as PlatformParagraphSpan
import android.text.style.RelativeSizeSpan
import android.text.style.ReplacementSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.SubscriptSpan
import android.text.style.SuperscriptSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import android.text.style.UnderlineSpan
import org.tiqian.core.ColorSpan
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextPaint
import org.tiqian.core.Background
import org.tiqian.core.LineThrough
import org.tiqian.core.Link
import org.tiqian.core.Underline
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent

/**
 * Capability report for displaying an Android [Spanned] through [CjkTextView] without losing
 * rich-text semantics. Lowering still accepts the input; [issues] names the span semantics the
 * current View frontend cannot yet preserve faithfully.
 */
data class CjkSpannedCompatibility(
    val issues: Set<CjkSpannedCapabilityIssue> = emptySet(),
) {
    val canPreserveAllKnownSemantics: Boolean
        get() = issues.isEmpty()
}

/** Platform span semantics accepted at the boundary but not yet preserved faithfully. */
enum class CjkSpannedCapabilityIssue {
    ParagraphSpans,
    ClickableSpanCallbacks,
    ReplacementSpans,
    AbsoluteSizeInDip,
    TypefaceFamilies,
    BaselineShift,
    UnknownSpans,
}

/**
 * Reports which spans of [this] the current View frontend cannot yet preserve faithfully. This is
 * a diagnostic boundary, not a host-renderer switch — the [CjkTextContent] lowering accepts
 * the same input either way, mirroring `AnnotatedString.cjkTextCompatibility()` in the Compose
 * frontend.
 */
fun CharSequence.cjkSpannedCompatibility(): CjkSpannedCompatibility {
    val spanned = this as? Spanned ?: return CjkSpannedCompatibility()
    val issues = linkedSetOf<CjkSpannedCapabilityIssue>()
    for (span in spanned.getSpans(0, spanned.length, Any::class.java)) {
        when (span) {
            is StyleSpan, is ForegroundColorSpan, is BackgroundColorSpan,
            is UnderlineSpan, is StrikethroughSpan, is RelativeSizeSpan, is URLSpan,
            -> Unit

            is AbsoluteSizeSpan ->
                if (span.dip) issues += CjkSpannedCapabilityIssue.AbsoluteSizeInDip
            is SuperscriptSpan, is SubscriptSpan ->
                issues += CjkSpannedCapabilityIssue.BaselineShift
            is TypefaceSpan -> issues += CjkSpannedCapabilityIssue.TypefaceFamilies
            is ClickableSpan -> issues += CjkSpannedCapabilityIssue.ClickableSpanCallbacks
            is ReplacementSpan -> issues += CjkSpannedCapabilityIssue.ReplacementSpans
            is PlatformParagraphSpan -> issues += CjkSpannedCapabilityIssue.ParagraphSpans
            else -> issues += CjkSpannedCapabilityIssue.UnknownSpans
        }
    }
    return CjkSpannedCompatibility(issues)
}

/**
 * Lowers an Android [CharSequence] and its supported platform spans into a
 * [CjkTextContent]: [StyleSpan], [ForegroundColorSpan], [BackgroundColorSpan],
 * [UnderlineSpan], [StrikethroughSpan], [RelativeSizeSpan], px [AbsoluteSizeSpan] and [URLSpan].
 * Unsupported spans keep the base style; check them with [cjkSpannedCompatibility].
 */
fun CjkTextContent(
    text: CharSequence,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    textColor: Int = Color.BLACK,
): CjkTextContent {
    val source = text.toString()
    val spanned = text as? Spanned
        ?: return CjkTextContent(
            content = TiqianTextContent(source),
            textStyle = textStyle,
            paragraphStyle = paragraphStyle,
            textColor = textColor,
        )

    val colorSpans = mutableListOf<ColorSpan>()
    val richTextSpans = mutableListOf<RichTextSpan>()
    val styleEdits = mutableListOf<Pair<TextRange, (TextStyle) -> TextStyle>>()
    for (span in spanned.getSpans(0, spanned.length, Any::class.java)) {
        val start = spanned.getSpanStart(span).coerceIn(0, source.length)
        val end = spanned.getSpanEnd(span).coerceIn(0, source.length)
        if (end <= start) continue
        val range = TextRange(start, end)
        when (span) {
            is StyleSpan -> when (span.style) {
                Typeface.BOLD -> styleEdits += range to { it.copy(fontWeight = 700) }
                Typeface.ITALIC -> styleEdits += range to { it.copy(italic = true) }
                Typeface.BOLD_ITALIC ->
                    styleEdits += range to { it.copy(fontWeight = 700, italic = true) }
            }
            is ForegroundColorSpan -> colorSpans += ColorSpan(start, end, span.foregroundColor)
            is BackgroundColorSpan -> richTextSpans += RichTextSpan(
                range,
                Background.instance,
                RichTextPaint(argb = span.backgroundColor),
            )
            is UnderlineSpan -> richTextSpans += RichTextSpan(range, Underline.instance)
            is StrikethroughSpan -> richTextSpans += RichTextSpan(range, LineThrough.instance)
            is RelativeSizeSpan -> {
                val proportion = span.sizeChange
                styleEdits += range to { it.copy(fontSize = it.fontSize * proportion) }
            }
            is AbsoluteSizeSpan -> if (!span.dip) {
                val sizePx = span.size.toFloat()
                styleEdits += range to { it.copy(fontSize = sizePx) }
            }
            is URLSpan -> {
                // Underline carries the platform link affordance; glyph color stays the host's
                // text color until the host authors an explicit ColorSpan.
                richTextSpans += RichTextSpan(range, Link(span.url))
                richTextSpans += RichTextSpan(range, Underline.instance)
            }
        }
    }
    return CjkTextContent(
        content = TiqianTextContent(
            text = source,
            spans = flattenSpannedStyleEdits(source.length, textStyle, styleEdits),
        ),
        textStyle = textStyle,
        paragraphStyle = paragraphStyle,
        textColor = textColor,
        colorSpans = colorSpans,
        richTextSpans = richTextSpans,
    )
}

/** Flattens overlapping span edits into non-overlapping, fully resolved [TextSpan]s. */
private fun flattenSpannedStyleEdits(
    textLength: Int,
    base: TextStyle,
    edits: List<Pair<TextRange, (TextStyle) -> TextStyle>>,
): List<TextSpan> {
    if (edits.isEmpty()) return emptyList()
    val cuts = sortedSetOf(0, textLength)
    for ((range, _) in edits) {
        cuts += range.start
        cuts += range.end
    }
    val points = cuts.toList()
    val out = mutableListOf<TextSpan>()
    for (index in 0 until points.size - 1) {
        val segment = TextRange(points[index], points[index + 1])
        var style = base
        for ((range, apply) in edits) {
            if (segment.start >= range.start && segment.end <= range.end) style = apply(style)
        }
        if (style != base) out += TextSpan(segment, style)
    }
    return out
}
