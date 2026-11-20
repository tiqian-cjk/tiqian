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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LinkAddressDisplay
import org.tiqian.core.InlineAttachment
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextPaint
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.layoutAutoSpaceSuppressedRanges
import org.tiqian.core.layoutInlineBoxes
import org.tiqian.core.layoutLineBreakSpans

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

/** Annotation tag carrying [InlineAttachment] over a layout-affecting range. */
internal const val CjkInlineAttachmentTag = "org.tiqian.inline-attachment"

/** Annotation tag marking the U+200B appended by [wbr] as a line break opportunity, not content. */
internal const val CjkWbrTag = "org.tiqian.wbr"

private const val ZeroWidthSpace = '\u200B'
private const val WbrItem = "wbr"

/** Separates an optional ruby font family from the reading inside the annotation item. */
private const val RubyFontSeparator = "\u001F"

private const val InlineCodeRoleItem = "InlineCode"
private const val TechnicalInlineRoleItem = "TechnicalInline"
private const val InteractionOnlyRoleItem = "InteractionOnly"

/** Marks an existing source range as belonging to one of its neighbouring text runs. */
fun AnnotatedString.Builder.addCjkInlineAttachment(
    attachment: InlineAttachment,
    start: Int,
    end: Int,
) {
    addStringAnnotation(CjkInlineAttachmentTag, attachment.name, start, end)
}

/** Marks a renderer-owned inline range for technical breaking without adding paint or padding. */
fun AnnotatedString.Builder.addTechnicalInlineAnnotation(start: Int, end: Int) {
    require(start in 0..end && end <= length) {
        "Technical inline range [$start, $end) must be inside AnnotatedString length $length"
    }
    if (start != end) addStringAnnotation(CjkRichTextTag, TechnicalInlineRoleItem, start, end)
}

/** Keeps a Compose clickable range interactive without classifying it as a textual link. */
fun AnnotatedString.Builder.addCjkInteractionOnlyAnnotation(start: Int, end: Int) {
    require(start in 0..end && end <= length) {
        "Interaction-only range [$start, $end) must be inside AnnotatedString length $length"
    }
    if (start != end) addStringAnnotation(CjkRichTextTag, InteractionOnlyRoleItem, start, end)
}

/** Applies the always-on part of Compose link styling after authored spans so it wins on overlap. */
internal fun AnnotatedString.withBaseLinkStyles(): AnnotatedString {
    val links = getLinkAnnotations(0, length).mapNotNull { link ->
        link.item.styles?.style?.let { style -> AnnotatedString.Range(style, link.start, link.end) }
    }
    if (links.isEmpty()) return this
    return AnnotatedString.Builder(this).apply {
        links.forEach { addStyle(it.item, it.start, it.end) }
    }.toAnnotatedString()
}

/**
 * 行间注 (拼音/ruby, ADR 0032): appends [base] and annotates it with the [ruby]
 * reading placed above it. The reading is NOT part of the source string, search text, or
 * accessibility semantics. When its whole base is selected, clipboard plain text follows the Web
 * frontend and appends the reading as `base（ruby）`; a partial base selection copies only source:
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

/**
 * Line break opportunity, the Compose counterpart of HTML `<wbr>`: appends U+200B ZERO WIDTH SPACE
 * and marks it with [CjkWbrTag]. The engine treats U+200B as a zero-width soft break opportunity
 * (UAX #14 class ZW), so a line may break at this position without a hyphen or visible space,
 * which matches how browsers lay out `<wbr>`.
 *
 * HTML `<wbr>` is an element and contributes no characters to the text content, so browsers leave
 * it out of copied text and the accessibility tree. The marked U+200B follows the same rule: the
 * clipboard text and the accessibility semantics text omit it. Selection offsets and
 * [CjkSelectionState.selectedText] still count it, because it occupies one source index. A U+200B
 * appended with plain `append` carries no tag and is copied as ordinary source text.
 *
 * ```
 * CjkText(buildAnnotatedString {
 *     withStyle(topicStyle) { append("#话题甲#") }
 *     wbr()                                    // 两个话题之间允许换行
 *     withStyle(topicStyle) { append("#话题乙#") }
 * })
 * ```
 */
fun AnnotatedString.Builder.wbr() {
    withAnnotation(CjkWbrTag, WbrItem) { append(ZeroWidthSpace) }
}

/** Source offsets of the characters appended by [wbr], in ascending order. */
internal fun AnnotatedString.cjkWbrOffsets(): IntArray =
    getStringAnnotations(CjkWbrTag, 0, length)
        .filter { it.end == it.start + 1 && text[it.start] == ZeroWidthSpace }
        .map { it.start }
        .distinct()
        .sorted()
        .toIntArray()

/** Calls [block] with each non-empty sub-range of [start, end) that lies between [wbr] offsets. */
internal inline fun IntArray.forEachWbrFreeRange(start: Int, end: Int, block: (start: Int, end: Int) -> Unit) {
    var cursor = start
    for (offset in this) {
        if (offset < start || offset >= end) continue
        if (offset > cursor) block(cursor, offset)
        cursor = offset + 1
    }
    if (end > cursor) block(cursor, end)
}

/**
 * Returns the [start, end) slice of this text with the [wbr] characters removed. Every other span
 * and annotation keeps one range whose offsets are mapped to the shorter text, so a link that
 * covers a [wbr] stays one link instead of two adjacent ones.
 */
internal fun AnnotatedString.withoutCjkWbr(
    start: Int = 0,
    end: Int = length,
    wbrOffsets: IntArray = cjkWbrOffsets(),
): AnnotatedString {
    val slice = if (start == 0 && end == length) this else subSequence(start, end)
    val removed = wbrOffsets.filter { it in start until end }.map { it - start }.toIntArray()
    if (removed.isEmpty()) return slice
    val text = buildString {
        removed.forEachWbrFreeRange(0, slice.length) { from, to -> append(slice.text, from, to) }
    }
    val annotations = mutableListOf<AnnotatedString.Range<out AnnotatedString.Annotation>>()
    // mapAnnotations is the only public accessor that visits every annotation type; the
    // transform records each range and returns it unchanged.
    slice.mapAnnotations { range ->
        if (range.tag != CjkWbrTag) {
            val mappedStart = removed.wbrSourceToProjectedOffset(range.start)
            val mappedEnd = removed.wbrSourceToProjectedOffset(range.end)
            // A range that covered only wbr characters has nothing left to annotate.
            if (mappedStart < mappedEnd || range.start == range.end) {
                annotations += AnnotatedString.Range(range.item, mappedStart, mappedEnd, range.tag)
            }
        }
        range
    }
    return AnnotatedString(text, annotations)
}

/** Maps a source offset to the matching offset in [withoutCjkWbr] output. */
internal fun IntArray.wbrSourceToProjectedOffset(offset: Int): Int = offset - count { it < offset }

/** Maps an offset in [withoutCjkWbr] output back to a source offset before any adjacent [wbr]. */
internal fun IntArray.wbrProjectedToSourceOffset(offset: Int): Int {
    var source = offset
    for (wbrOffset in this) {
        if (wbrOffset < source) source++ else break
    }
    return source
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
internal fun AnnotatedString.cjkRichTextSpans(
    adjacentSameStyleClearance: Float = 0f,
    inlineCodePaint: RichTextPaint = RichTextPaint(
        adjacentSameStyleClearance = adjacentSameStyleClearance,
    ),
): List<RichTextSpan> {
    val out = mutableListOf<RichTextSpan>()
    val interactionOnlyRanges = getStringAnnotations(CjkRichTextTag, 0, length)
        .filter { it.item == InteractionOnlyRoleItem }
        .mapTo(mutableSetOf()) { it.start to it.end }
    for (span in spanStyles) {
        val range = TextRange(span.start, span.end)
        val style = span.item
        if (style.background != Color.Unspecified) {
            out += RichTextSpan(
                range = range,
                role = org.tiqian.core.Background.instance,
                paint = RichTextPaint(
                    argb = style.background.toArgb(),
                    adjacentSameStyleClearance = adjacentSameStyleClearance,
                ),
            )
        }
        val decoration = style.textDecoration
        if (decoration != null && decoration != TextDecoration.None) {
            val linePaint = RichTextPaint(
                argb = style.color.takeIf { it != Color.Unspecified }?.toArgb(),
                adjacentSameStyleClearance = adjacentSameStyleClearance,
            )
            if (TextDecoration.Underline in decoration) {
                out += RichTextSpan(range, org.tiqian.core.Underline.instance, linePaint)
            }
            if (TextDecoration.LineThrough in decoration) {
                out += RichTextSpan(range, org.tiqian.core.LineThrough.instance, linePaint)
            }
        }
    }
    for (link in getLinkAnnotations(0, length)) {
        if (link.item is LinkAnnotation.Clickable && (link.start to link.end) in interactionOnlyRanges) {
            continue
        }
        val target = when (val item = link.item) {
            is LinkAnnotation.Url -> item.url
            is LinkAnnotation.Clickable -> item.tag
            else -> continue
        }
        out += RichTextSpan(TextRange(link.start, link.end), org.tiqian.core.Link(target))
    }
    for (role in getStringAnnotations(CjkRichTextTag, 0, length)) {
        when (role.item) {
            InlineCodeRoleItem -> out += RichTextSpan(
                TextRange(role.start, role.end), org.tiqian.core.InlineCode.instance, inlineCodePaint,
            )
            TechnicalInlineRoleItem -> out += RichTextSpan(
                TextRange(role.start, role.end), org.tiqian.core.TechnicalInline.instance,
            )
        }
    }
    return out
}

/**
 * Tiqian inline code, renderer-owned technical ranges, and links whose visible text is the
 * address itself ([LinkAddressDisplay]) share one break policy. Other link text keeps prose
 * line breaking.
 */
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
    getStringAnnotations(CjkInlineAttachmentTag, 0, length).forEach { addRange(it.start, it.end) }
    cjkWbrOffsets().forEach { addRange(it, it + 1) }
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
    val attachments = getStringAnnotations(CjkInlineAttachmentTag, 0, length).mapNotNull { range ->
        runCatching { InlineAttachment.valueOf(range.item) }.getOrNull()?.let { attachment ->
            AnnotatedString.Range(attachment, range.start, range.end)
        }
    }
    if (relevant.isEmpty() && attachments.isEmpty()) return emptyList()
    val bounds = sortedSetOf(0, length)
    relevant.forEach { bounds += it.start; bounds += it.end }
    attachments.forEach { bounds += it.start; bounds += it.end }
    val pts = bounds.toList()
    val out = mutableListOf<TextSpan>()
    for (i in 0 until pts.size - 1) {
        val a = pts[i]
        val b = pts[i + 1]
        if (a >= b) continue
        val covering = relevant.filter { it.start <= a && it.end >= b }
        val coveringAttachments = attachments.filter { it.start <= a && it.end >= b }
        if (covering.isEmpty() && coveringAttachments.isEmpty()) continue
        var size = base.fontSize
        var weight = base.fontWeight
        var italic = base.italic
        var families = base.fontFamilies
        var baselineShiftMultiplier: Float? = null
        var inlineAttachment = base.inlineAttachment
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
        coveringAttachments.forEach { inlineAttachment = it.item }
        val baselineShift = base.baselineShift - (baselineShiftMultiplier ?: 0f) * size
        out += TextSpan(
            TextRange(a, b),
            base.copy(
                fontSize = size,
                fontWeight = weight,
                italic = italic,
                fontFamilies = families,
                baselineShift = baselineShift,
                inlineAttachment = inlineAttachment,
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
    paragraphStyle: ParagraphStyle = DefaultCjkTextParagraphStyle,
): LayoutResult {
    val renderText = text.withBaseLinkStyles()
    val core = textStyle.toCoreTextStyle(density)
    val richTextSpans = renderText.cjkRichTextSpans(
        adjacentSameStyleClearance = with(density) { 1.dp.toPx() },
        inlineCodePaint = defaultInlineCodePaint(density),
    )
    return measure(
        text = renderText.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = paragraphStyle.withCjkTextStyleLineHeight(textStyle, density),
        decorations = renderText.cjkDecorations(),
        spans = renderText.cjkStyleSpans(core, density),
        rubySpans = renderText.cjkRubySpans(),
        inlineBoxes = richTextSpans.layoutInlineBoxes(),
        sourceBoundaries = renderText.cjkSourceBoundaries(),
        lineBreakSpans = richTextSpans.layoutLineBreakSpans(renderText.text),
        autoSpaceSuppressedRanges = richTextSpans.layoutAutoSpaceSuppressedRanges(),
    )
}

/**
 * Full pre-layout counterpart to the rich `CjkText(AnnotatedString)` path, including measured
 * inline objects and renderer-owned backgrounds/decorations.
 */
fun ParagraphMeasurer.measureWithInlineContent(
    text: AnnotatedString,
    constraints: LayoutConstraints,
    density: Density,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle = DefaultCjkTextParagraphStyle,
    inlineObjects: List<CjkInlineObject>,
    inlineDecorations: List<CjkInlineDecoration> = emptyList(),
    inlineBackgrounds: List<CjkInlineBackground> = emptyList(),
): LayoutResult {
    val lowered = lowerComposeText(text, style, paragraphStyle)
    val renderText = lowered.text.withBaseLinkStyles()
    val core = lowered.textStyle.toCoreTextStyle(density)
    val richTextSpans = renderText.cjkRichTextSpans(
        adjacentSameStyleClearance = with(density) { 1.dp.toPx() },
        inlineCodePaint = defaultInlineCodePaint(density),
    ) + inlineBackgrounds.map { it.toCore(density) } + inlineDecorations.map { it.toCore(density) }
    val sourceBoundaries = buildSet {
        addAll(renderText.cjkSourceBoundaries())
        richTextSpans.forEach { span ->
            add(span.range.start)
            add(span.range.end)
        }
    }
    return measure(
        LayoutInput(
            content = TiqianTextContent(
                text = renderText.text,
                spans = renderText.cjkStyleSpans(core, density),
                sourceBoundaries = sourceBoundaries.toList(),
                lineBreakSpans = richTextSpans.layoutLineBreakSpans(renderText.text),
                autoSpaceSuppressedRanges = richTextSpans.layoutAutoSpaceSuppressedRanges(),
            ),
            textStyle = core,
            paragraphStyle = lowered.paragraphStyle.withCjkTextStyleLineHeight(lowered.textStyle, density),
            constraints = constraints,
            decorations = renderText.cjkDecorations(),
            rubySpans = renderText.cjkRubySpans(),
            inlineBoxes = richTextSpans.layoutInlineBoxes(),
            inlineObjects = inlineObjects.map { it.toCore(density) },
        ),
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
    paragraphStyle: ParagraphStyle = DefaultCjkTextParagraphStyle,
): LayoutResult {
    val lowered = lowerComposeText(text, style, paragraphStyle)
    val renderText = lowered.text.withBaseLinkStyles()
    val core = lowered.textStyle.toCoreTextStyle(density)
    val richTextSpans = renderText.cjkRichTextSpans(
        adjacentSameStyleClearance = with(density) { 1.dp.toPx() },
        inlineCodePaint = defaultInlineCodePaint(density),
    )
    return measure(
        text = renderText.text,
        constraints = constraints,
        textStyle = core,
        paragraphStyle = lowered.paragraphStyle.withCjkTextStyleLineHeight(lowered.textStyle, density),
        decorations = renderText.cjkDecorations(),
        spans = renderText.cjkStyleSpans(core, density),
        rubySpans = renderText.cjkRubySpans(),
        inlineBoxes = richTextSpans.layoutInlineBoxes(),
        sourceBoundaries = renderText.cjkSourceBoundaries(),
        lineBreakSpans = richTextSpans.layoutLineBreakSpans(renderText.text),
        autoSpaceSuppressedRanges = richTextSpans.layoutAutoSpaceSuppressedRanges(),
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
        withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 0.875.em)) { block() }
    }
}
