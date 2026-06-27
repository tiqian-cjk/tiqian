package org.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.text.withAnnotation
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.ColorSpan

// Annotation tags + extractors are the AnnotatedString WIRE PROTOCOL between the
// public builders (emphasis/ruby/bopomofo/…) and the engine. INTERNAL on purpose —
// not a versioned public contract (Codex #4); third parties author via the builders.

/** Annotation tag carrying a [DecorationKind] name over an AnnotatedString range. */
internal const val CjkDecorationTag = "org.tiqian.decoration"

/** Annotation tag carrying 拼音 (above-base ruby) text over its base range. */
internal const val CjkRubyTag = "org.tiqian.ruby"

/** Annotation tag carrying 注音 (right-side ㄅㄆㄇ ruby) text over its base range. */
internal const val CjkBopomofoTag = "org.tiqian.bopomofo"

/** Separates an optional ruby font family from the reading inside the annotation item. */
private const val RubyFontSeparator = "\u001F"

/**
 * Authors decorations as attributed text. Instead of counting source offsets
 * into a [DecorationSpan] (`TextRange(4, 16)`), wrap the span in [emphasis] /
 * [properNoun] / [mourning] / [bookTitle] inside `buildAnnotatedString { … }`:
 *
 * ```
 * CjkParagraph(buildAnnotatedString {
 *     append("他强调：")
 *     emphasis { append("豆子新鲜最要紧") }
 *     append("，烘焙其次。")
 * })
 * ```
 *
 * [AnnotatedString.text] is the unchanged source (复制/搜索保真). `SpanStyle.color`
 * (render-only) and `SpanStyle.fontSize` (layout-affecting, ADR 0030 B 档) map to
 * the engine; weight/style/family are not consumed yet.
 */
@Composable
fun CjkParagraph(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    textStyle: CjkTextStyle = CjkTextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    val density = LocalDensity.current
    val coreStyle = textStyle.toCoreTextStyle(density)
    CjkParagraphImpl(
        text = text.text,
        semanticsText = text,
        modifier = modifier,
        textStyle = coreStyle,
        paragraphStyle = paragraphStyle.copy(
            lineHeight = textStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight,
        ),
        color = textStyle.colorArgbOrNull() ?: DEFAULT_TEXT_COLOR,
        decorations = text.cjkDecorations(),
        colorSpans = text.cjkColorSpans(),
        spans = text.cjkStyleSpans(coreStyle, density),
        rubySpans = text.cjkRubySpans(),
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Compose interop entry for migrating from `Text(AnnotatedString, style = …)` without first
 * projecting rich text into Tiqian's narrower style object. Pair with
 * [AnnotatedString.cjkTextCompatibility] at renderer boundaries to expose Compose features Tiqian
 * does not yet preserve. The input is still accepted; the report is a Tiqian work list, not a
 * host-renderer switch.
 */
@Composable
fun CjkParagraph(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    val density = LocalDensity.current
    val cjkStyle = style.toCjkTextStyle()
    val coreStyle = cjkStyle.toCoreTextStyle(density)
    CjkParagraphImpl(
        text = text.text,
        semanticsText = text,
        modifier = modifier,
        textStyle = coreStyle,
        paragraphStyle = paragraphStyle.copy(
            lineHeight = cjkStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight,
        ),
        color = cjkStyle.colorArgbOrNull() ?: DEFAULT_TEXT_COLOR,
        decorations = text.cjkDecorations(),
        colorSpans = text.cjkColorSpans(),
        spans = text.cjkStyleSpans(coreStyle, density),
        rubySpans = text.cjkRubySpans(),
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * 行间注 (拼音/ruby, ADR 0032): appends [base] and annotates it with the [ruby]
 * reading placed above it. The reading is NOT part of the source string
 * (复制/搜索 保真 — only [base] is appended):
 *
 * ```
 * CjkParagraph(buildAnnotatedString {
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
 * Flattens the layout-affecting `SpanStyle`s (`fontSize` / `fontWeight` /
 * `fontStyle`) into non-overlapping, fully-resolved [TextSpan]s for the engine +
 * renderer (rich-text 字号/字重/斜体, ADR 0030 B 档). Each segment's style is
 * [base] with the covering overrides applied (later spans win), so unset fields
 * inherit the paragraph base — `.em` font size is relative to [base] (1.8.em =
 * 1.8× base, the natural inline-emphasis unit); `.sp` is resolved to px via
 * [density] (density + fontScale aware — NOT treated as raw px). Segments with no
 * layout-affecting override are dropped (color rides [cjkColorSpans]).
 */
internal fun AnnotatedString.cjkStyleSpans(base: TextStyle, density: Density): List<TextSpan> {
    val relevant = spanStyles.filter {
        it.item.fontSize != TextUnit.Unspecified || it.item.fontWeight != null ||
            it.item.fontStyle != null || it.item.fontFamily != null
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
            // Generic families (Serif/SansSerif/Monospace) carry a token name the
            // engine resolves role-aware; custom FontListFontFamily is not wired
            // (no portable name) and stays at base (ADR 0030 字体 limitation).
            (s.item.fontFamily as? GenericFontFamily)?.let { families = listOf(it.name) }
        }
        out += TextSpan(
            TextRange(a, b),
            base.copy(fontSize = size, fontWeight = weight, italic = italic, fontFamilies = families),
        )
    }
    return out
}

/**
 * Pre-layout a rich-text [text] without rendering — the measure-side counterpart to
 * `CjkParagraph(AnnotatedString)` (Codex #5). Extracts the same layout-affecting
 * spans (装饰/样式/ruby; color is render-only, not a measure input) and lowers
 * [textStyle] via [density]. Use for hit-testing / size queries before drawing.
 */
fun ParagraphMeasurer.measure(
    text: AnnotatedString,
    constraints: LayoutConstraints,
    density: Density,
    textStyle: CjkTextStyle = CjkTextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
): LayoutResult {
    val core = textStyle.toCoreTextStyle(density)
    return measure(
        text = text.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = paragraphStyle.copy(
            lineHeight = textStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight,
        ),
        decorations = text.cjkDecorations(),
        spans = text.cjkStyleSpans(core, density),
        rubySpans = text.cjkRubySpans(),
    )
}

/**
 * Pre-layout counterpart to [CjkParagraph] with Compose [style].
 */
fun ParagraphMeasurer.measure(
    text: AnnotatedString,
    constraints: LayoutConstraints,
    density: Density,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
): LayoutResult {
    val cjkStyle = style.toCjkTextStyle()
    val core = cjkStyle.toCoreTextStyle(density)
    return measure(
        text = text.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = paragraphStyle.copy(
            lineHeight = cjkStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight,
        ),
        decorations = text.cjkDecorations(),
        spans = text.cjkStyleSpans(core, density),
        rubySpans = text.cjkRubySpans(),
    )
}

// NOT inline: the tag is internal (Codex #4) and a public inline fun can't reference it.

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
