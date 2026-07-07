package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withAnnotation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextPaint
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle

// Annotation tags + extractors are the AnnotatedString WIRE PROTOCOL between the
// public builders (emphasis/ruby/bopomofo/…) and the engine. INTERNAL on purpose —
// not a versioned public contract; third parties author via the builders.

/** Annotation tag carrying a [DecorationKind] name over an AnnotatedString range. */
internal const val CjkDecorationTag = "org.tiqian.decoration"

/** Annotation tag carrying 拼音 (above-base ruby) text over its base range. */
internal const val CjkRubyTag = "org.tiqian.ruby"

/** Annotation tag carrying 注音 (right-side ㄅㄆㄇ ruby) text over its base range. */
internal const val CjkBopomofoTag = "org.tiqian.bopomofo"

/** Annotation tag carrying Tiqian rich-text roles such as inline code. */
internal const val CjkRichTextTag = "org.tiqian.richtext"

/** Separates an optional ruby font family from the reading inside the annotation item. */
private const val RubyFontSeparator = "\u001F"

private const val InlineCodeRoleItem = "InlineCode"

/**
 * 行间注 (拼音/ruby, ADR 0032): appends [base] and annotates it with the [ruby]
 * reading placed above it. The reading is NOT part of the source string
 * (复制/搜索 保真 — only [base] is appended):
 *
 * ```
 * CjkText(buildAnnotatedString {
 *     append("我爱")
 *     ruby("北京", "Běijīng")                               // 默认注文字体
 *     bopomofo("中", "ㄓㄨㄥ", fontFamily = "BpmfGenYoMin")  // 注音用 ㄅㄆㄇ 字体
 *     append("。")
 * })
 * ```
 *
 * [fontFamily] sets the 注文-ONLY font (拼音/释义各取所需，本就独立于正文)；
 * null = 渲染器默认（ADR 0032）。
 */
fun AnnotatedString.Builder.ruby(base: String, ruby: String, fontFamily: String? = null) {
    val item = if (fontFamily != null) "$fontFamily$RubyFontSeparator$ruby" else ruby
    withAnnotation(CjkRubyTag, item) { append(base) }
}

/**
 * 注音 (ㄅㄆㄇ, ADR 0033): appends [base] and annotates it with the [bopomofo] reading
 * (engine parses the tone). Placed on the base's RIGHT side. [fontFamily] should
 * be a font carrying ㄅㄆㄇ glyphs.
 *
 * ```
 * bopomofo("中", "ㄓㄨㄥ", fontFamily = "BpmfGenYoMin")
 * ```
 */
fun AnnotatedString.Builder.bopomofo(base: String, bopomofo: String, fontFamily: String? = null) {
    val item = if (fontFamily != null) "$fontFamily$RubyFontSeparator$bopomofo" else bopomofo
    withAnnotation(CjkBopomofoTag, item) { append(base) }
}

/** Extracts [RubySpan]s from 拼音 ([CjkRubyTag]) + 注音 ([CjkBopomofoTag]) annotations. */
internal fun AnnotatedString.cjkRubySpans(): List<RubySpan> =
    rubySpansFor(CjkRubyTag, RubyKind.Pinyin) + rubySpansFor(CjkBopomofoTag, RubyKind.Bopomofo)

private fun AnnotatedString.rubySpansFor(tag: String, kind: RubyKind): List<RubySpan> =
    getStringAnnotations(tag, 0, length).map {
        val parts = it.item.split(RubyFontSeparator, limit = 2)
        if (parts.size == 2) {
            RubySpan(TextRange(it.start, it.end), parts[1], fontFamilies = listOf(parts[0]), kind = kind)
        } else {
            RubySpan(TextRange(it.start, it.end), it.item, kind = kind)
        }
    }

/** Extracts [DecorationSpan]s from the [CjkDecorationTag] annotations (unknown kinds skipped). */
internal fun AnnotatedString.cjkDecorations(): List<DecorationSpan> =
    getStringAnnotations(CjkDecorationTag, 0, length).mapNotNull {
        runCatching { DecorationKind.valueOf(it.item) }.getOrNull()
            ?.let { kind -> DecorationSpan(TextRange(it.start, it.end), kind) }
    }

/**
 * Extracts [ColorSpan]s from `SpanStyle.color` (rich-text 颜色, ADR 0030 A 档).
 * Other SpanStyle attributes (size/weight/style) are layout-affecting — they
 * wait for the engine to consume `TiqianTextContent.spans` (B 档).
 */
internal fun AnnotatedString.cjkColorSpans(): List<ColorSpan> =
    spanStyles.filter { it.item.color != Color.Unspecified }
        .map { ColorSpan(it.start, it.end, it.item.color.toArgb()) }

/**
 * Extracts render/semantic rich-text roles. These spans add no layout rules of their own; their
 * source edges are passed separately as cluster-boundary hints so [LayoutResult] geometry can
 * preserve exact source ranges without a renderer-side text layout fork.
 */
internal fun AnnotatedString.cjkRichTextSpans(): List<RichTextSpan> {
    val out = mutableListOf<RichTextSpan>()
    for (span in spanStyles) {
        val range = TextRange(span.start, span.end)
        val style = span.item
        if (style.background != Color.Unspecified) {
            out += RichTextSpan(
                range = range,
                role = RichTextRole.Background,
                paint = RichTextPaint(style.background.toArgb()),
            )
        }
        val decoration = style.textDecoration
        if (decoration != null && decoration != TextDecoration.None) {
            val linePaint = RichTextPaint(style.color.takeIf { it != Color.Unspecified }?.toArgb())
            if (TextDecoration.Underline in decoration) {
                out += RichTextSpan(range, RichTextRole.Underline, linePaint)
            }
            if (TextDecoration.LineThrough in decoration) {
                out += RichTextSpan(range, RichTextRole.LineThrough, linePaint)
            }
        }
    }
    for (link in getLinkAnnotations(0, length)) {
        val target = when (val item = link.item) {
            is LinkAnnotation.Url -> item.url
            is LinkAnnotation.Clickable -> item.tag
            else -> continue
        }
        out += RichTextSpan(TextRange(link.start, link.end), RichTextRole.Link(target))
    }
    for (role in getStringAnnotations(CjkRichTextTag, 0, length)) {
        if (role.item == InlineCodeRoleItem) {
            out += RichTextSpan(TextRange(role.start, role.end), RichTextRole.InlineCode)
        }
    }
    return out
}

/**
 * Source range edges that should be exact cluster boundaries for geometry queries.
 * Render-only ranges (color, underline, links) still need boxes that end at the
 * authored source edge rather than a proportional slice through a larger Latin cluster.
 */
internal fun AnnotatedString.cjkSourceBoundaries(): Set<Int> {
    val out = sortedSetOf<Int>()
    fun addBoundary(offset: Int) {
        if (offset > 0 && offset < length) out += offset
    }
    fun addRange(start: Int, end: Int) {
        addBoundary(start)
        addBoundary(end)
    }
    spanStyles.forEach { addRange(it.start, it.end) }
    getLinkAnnotations(0, length).forEach { addRange(it.start, it.end) }
    getStringAnnotations(CjkDecorationTag, 0, length).forEach { addRange(it.start, it.end) }
    getStringAnnotations(CjkRubyTag, 0, length).forEach { addRange(it.start, it.end) }
    getStringAnnotations(CjkBopomofoTag, 0, length).forEach { addRange(it.start, it.end) }
    getStringAnnotations(CjkRichTextTag, 0, length).forEach { addRange(it.start, it.end) }
    return out
}

/**
 * Flattens the layout-affecting `SpanStyle`s (`fontSize` / `fontWeight` /
 * `fontStyle` / `baselineShift`) into non-overlapping, fully-resolved [TextSpan]s for the engine +
 * renderer (rich-text 字号/字重/斜体/上标位移, ADR 0030 B 档). Each segment's style is
 * [base] with the covering overrides applied (later spans win), so unset fields
 * inherit the paragraph base — `.em` font size is relative to [base] (1.8.em =
 * 1.8× base, the natural inline-emphasis unit); `.sp` is resolved to px via
 * [density] (density + fontScale aware — NOT treated as raw px). Compose baseline
 * shift multipliers resolve against the segment's final font size and are flipped
 * into Tiqian's +down coordinate system. Segments with no layout-affecting override
 * are dropped (color rides [cjkColorSpans]).
 */
internal fun AnnotatedString.cjkStyleSpans(base: TextStyle, density: Density): List<TextSpan> {
    val relevant = spanStyles.filter {
        it.item.fontSize != TextUnit.Unspecified || it.item.fontWeight != null ||
            it.item.fontStyle != null || it.item.fontFamily != null ||
            it.item.baselineShift != null
    }
    if (relevant.isEmpty()) return emptyList()
    val bounds = sortedSetOf(0, length)
    relevant.forEach { bounds += it.start; bounds += it.end }
    val pts = bounds.toList()
    val out = mutableListOf<TextSpan>()
    for (i in 0 until pts.size - 1) {
        val a = pts[i]
        val b = pts[i + 1]
        if (a >= b) continue
        val covering = relevant.filter { it.start <= a && it.end >= b }
        if (covering.isEmpty()) continue
        var size = base.fontSize
        var weight = base.fontWeight
        var italic = base.italic
        var families = base.fontFamilies
        var baselineShiftMultiplier: Float? = null
        for (s in covering) {
            val unit = s.item.fontSize
            if (unit != TextUnit.Unspecified) {
                size = when (unit.type) {
                    TextUnitType.Em -> base.fontSize * unit.value      // relative to base (density-free)
                    TextUnitType.Sp -> with(density) { unit.toPx() }   // correct px (incl. fontScale)
                    else -> base.fontSize
                }
            }
            s.item.fontWeight?.let { weight = it.weight }
            s.item.fontStyle?.let { italic = it == FontStyle.Italic }
            s.item.baselineShift?.let { baselineShiftMultiplier = it.multiplier }
            // Generic families (Serif/SansSerif/Monospace) carry a token name the
            // engine resolves role-aware; custom FontListFontFamily is not wired
            // (no portable name) and stays at base (ADR 0030 字体 limitation).
            (s.item.fontFamily as? GenericFontFamily)?.let { families = listOf(it.name) }
        }
        val baselineShift = base.baselineShift - (baselineShiftMultiplier ?: 0f) * size
        out += TextSpan(
            TextRange(a, b),
            base.copy(
                fontSize = size,
                fontWeight = weight,
                italic = italic,
                fontFamilies = families,
                baselineShift = baselineShift,
            ),
        )
    }
    return out
}

/**
 * Pre-layout a rich-text [text] without rendering — the measure-side counterpart to
 * `CjkText(AnnotatedString)`. Extracts the same layout-affecting
 * spans (装饰/样式/ruby; color is render-only, not a measure input) and lowers
 * [textStyle] via [density]. Use for hit-testing / size queries before drawing.
 */
fun ParagraphMeasurer.measure(
    text: AnnotatedString,
    constraints: LayoutConstraints,
    density: Density,
    textStyle: CjkTextStyle = CjkTextStyle(),
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
): LayoutResult {
    val core = textStyle.toCoreTextStyle(density)
    return measure(
        text = text.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = paragraphStyle.withCjkTextStyleLineHeight(textStyle, density),
        decorations = text.cjkDecorations(),
        spans = text.cjkStyleSpans(core, density),
        rubySpans = text.cjkRubySpans(),
        sourceBoundaries = text.cjkSourceBoundaries(),
    )
}

/**
 * Pre-layout counterpart to `CjkText(AnnotatedString, style = ...)`.
 */
fun ParagraphMeasurer.measure(
    text: AnnotatedString,
    constraints: LayoutConstraints,
    density: Density,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
): LayoutResult {
    val lowered = lowerComposeText(text, style, paragraphStyle)
    val core = lowered.textStyle.toCoreTextStyle(density)
    return measure(
        text = lowered.text.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = lowered.paragraphStyle.withCjkTextStyleLineHeight(lowered.textStyle, density),
        decorations = lowered.text.cjkDecorations(),
        spans = lowered.text.cjkStyleSpans(core, density),
        rubySpans = lowered.text.cjkRubySpans(),
        sourceBoundaries = lowered.text.cjkSourceBoundaries(),
    )
}

// NOT inline: the tag is internal and a public inline fun can't reference it.

/** 着重号 over [block]'s text. */
fun AnnotatedString.Builder.emphasis(block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Emphasis.name) { block() }
}

/** 专名号（straight underline）over [block]'s text. */
fun AnnotatedString.Builder.properNoun(block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.ProperNoun.name) { block() }
}

/** 示亡号（mourning frame）over [block]'s text. */
fun AnnotatedString.Builder.mourning(block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Mourning.name) { block() }
}

/** 书名号甲式（wavy underline）over [block]'s text. */
fun AnnotatedString.Builder.bookTitle(block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.BookTitle.name) { block() }
}

/** Inline code over [block]'s source text: monospace shaping plus Tiqian-owned code background. */
fun AnnotatedString.Builder.inlineCode(block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkRichTextTag, InlineCodeRoleItem) {
        withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { block() }
    }
}
