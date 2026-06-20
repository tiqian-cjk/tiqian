package ink.duo3.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.text.withAnnotation
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.RubyKind
import ink.duo3.tiqian.core.RubySpan
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.core.ColorSpan

/** Annotation tag carrying a [DecorationKind] name over an AnnotatedString range. */
const val CjkDecorationTag = "ink.duo3.tiqian.decoration"

/** Annotation tag carrying 拼音 (above-base ruby) text over its base range. */
const val CjkRubyTag = "ink.duo3.tiqian.ruby"

/** Annotation tag carrying 注音 (right-side ㄅㄆㄇ ruby) text over its base range. */
const val CjkZhuyinTag = "ink.duo3.tiqian.zhuyin"

/** Separates an optional ruby font family from the reading inside the annotation item. */
private const val RubyFontSeparator = "\u001F"

/**
 * Authors decorations as attributed text. Instead of counting source offsets
 * into a [DecorationSpan] (`TextRange(4, 16)`), wrap the span in [cjkEmphasis] /
 * [properNoun] / [mourning] / [bookTitle] inside `buildAnnotatedString { … }`:
 *
 * ```
 * CjkParagraph(buildAnnotatedString {
 *     append("他强调：")
 *     cjkEmphasis { append("豆子新鲜最要紧") }
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
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(profile),
) {
    CjkParagraph(
        text = text.text,
        modifier = modifier,
        textStyle = textStyle,
        paragraphStyle = paragraphStyle,
        profile = profile,
        decorations = text.cjkDecorations(),
        colorSpans = text.cjkColorSpans(),
        spans = text.cjkStyleSpans(textStyle),
        rubySpans = text.cjkRubySpans(),
        measurer = measurer,
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
 *     cjkRuby("北京", "Běijīng")                               // 默认注文字体
 *     cjkRuby("中", "ㄓㄨㄥ", fontFamily = "BpmfGenYoMin")      // 注音用 ㄅㄆㄇ 字体
 *     append("。")
 * })
 * ```
 *
 * [fontFamily] sets the 注文-ONLY font (注音 需含 ㄅㄆㄇ 字形的字体；拼音/释义 各取
 * 所需，本就独立于正文)；null = 渲染器默认（ADR 0032）。
 */
fun AnnotatedString.Builder.cjkRuby(base: String, ruby: String, fontFamily: String? = null) {
    val item = if (fontFamily != null) "$fontFamily$RubyFontSeparator$ruby" else ruby
    withAnnotation(CjkRubyTag, item) { append(base) }
}

/**
 * 注音 (ㄅㄆㄇ, ADR 0033): appends [base] and annotates it with the [zhuyin] reading
 * (engine parses the tone). Placed on the base's RIGHT side. [fontFamily] should
 * be a font carrying ㄅㄆㄇ glyphs.
 *
 * ```
 * cjkZhuyin("中", "ㄓㄨㄥ", fontFamily = "BpmfGenYoMin")
 * ```
 */
fun AnnotatedString.Builder.cjkZhuyin(base: String, zhuyin: String, fontFamily: String? = null) {
    val item = if (fontFamily != null) "$fontFamily$RubyFontSeparator$zhuyin" else zhuyin
    withAnnotation(CjkZhuyinTag, item) { append(base) }
}

/** Extracts [RubySpan]s from 拼音 ([CjkRubyTag]) + 注音 ([CjkZhuyinTag]) annotations. */
fun AnnotatedString.cjkRubySpans(): List<RubySpan> =
    rubySpansFor(CjkRubyTag, RubyKind.Pinyin) + rubySpansFor(CjkZhuyinTag, RubyKind.Zhuyin)

private fun AnnotatedString.rubySpansFor(tag: String, kind: RubyKind): List<RubySpan> =
    getStringAnnotations(tag, 0, length).map {
        val parts = it.item.split(RubyFontSeparator, limit = 2)
        if (parts.size == 2) {
            RubySpan(TextRange(it.start, it.end), parts[1], fontFamilies = listOf(parts[0]), kind = kind)
        } else {
            RubySpan(TextRange(it.start, it.end), it.item, kind = kind)
        }
    }

/** Extracts [DecorationSpan]s from the [CjkDecorationTag] annotations. */
fun AnnotatedString.cjkDecorations(): List<DecorationSpan> =
    getStringAnnotations(CjkDecorationTag, 0, length).map {
        DecorationSpan(TextRange(it.start, it.end), DecorationKind.valueOf(it.item))
    }

/**
 * Extracts [ColorSpan]s from `SpanStyle.color` (rich-text 颜色, ADR 0030 A 档).
 * Other SpanStyle attributes (size/weight/style) are layout-affecting — they
 * wait for the engine to consume `TiqianTextContent.spans` (B 档).
 */
fun AnnotatedString.cjkColorSpans(): List<ColorSpan> =
    spanStyles.filter { it.item.color != Color.Unspecified }
        .map { ColorSpan(it.start, it.end, it.item.color.toArgb()) }

/**
 * Flattens the layout-affecting `SpanStyle`s (`fontSize` / `fontWeight` /
 * `fontStyle`) into non-overlapping, fully-resolved [TextSpan]s for the engine +
 * renderer (rich-text 字号/字重/斜体, ADR 0030 B 档). Each segment's style is
 * [base] with the covering overrides applied (later spans win), so unset fields
 * inherit the paragraph base — `.em` font size is relative to [base] (1.8.em =
 * 1.8× base, the natural inline-emphasis unit), `.sp`/raw is engine px. Segments
 * with no layout-affecting override are dropped (color rides [cjkColorSpans]).
 */
fun AnnotatedString.cjkStyleSpans(base: TextStyle): List<TextSpan> {
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
                size = if (unit.type == TextUnitType.Em) base.fontSize * unit.value else unit.value
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

/** 着重号 over [block]'s text. */
inline fun AnnotatedString.Builder.cjkEmphasis(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Emphasis.name) { block() }
}

/** 专名号（straight underline）over [block]'s text. */
inline fun AnnotatedString.Builder.properNoun(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.ProperNoun.name) { block() }
}

/** 示亡号（mourning frame）over [block]'s text. */
inline fun AnnotatedString.Builder.mourning(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Mourning.name) { block() }
}

/** 书名号甲式（wavy underline）over [block]'s text. */
inline fun AnnotatedString.Builder.bookTitle(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.BookTitle.name) { block() }
}
