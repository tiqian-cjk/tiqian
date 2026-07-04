package org.tiqian.compose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.ic
import org.tiqian.core.TextStyle
import kotlin.math.ceil
import kotlin.math.max

/** Mirrors the engine's default body line height (1.5em); used to size 节 gaps. */
private const val BODY_LINE_HEIGHT_EM = 1.5f

/**
 * Compose Text replacement entry for a single paragraph. This is the low-friction migration
 * surface: replace `Text(...)` with `CjkText(...)` without moving rich-text construction to a
 * Markdown/HTML layer. Layout-affecting CJK decisions still happen inside the engine; this facade
 * only lowers Compose style and text-control parameters into the existing paragraph contract.
 */
@Composable
fun CjkText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    style: ComposeTextStyle = ComposeTextStyle.Default,
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    CjkText(
        text = AnnotatedString(text),
        modifier = modifier,
        color = color,
        fontSize = fontSize,
        fontStyle = fontStyle,
        fontWeight = fontWeight,
        fontFamily = fontFamily,
        textDecoration = textDecoration,
        textAlign = textAlign,
        lineHeight = lineHeight,
        overflow = overflow,
        softWrap = softWrap,
        maxLines = maxLines,
        minLines = minLines,
        style = style,
        paragraphStyle = paragraphStyle,
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Tiqian-native single-paragraph counterpart to the Compose Text replacement facade.
 */
@Composable
fun CjkText(
    text: String,
    modifier: Modifier = Modifier,
    textStyle: CjkTextStyle,
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    CjkText(
        text = AnnotatedString(text),
        modifier = modifier,
        textStyle = textStyle,
        paragraphStyle = paragraphStyle,
        softWrap = softWrap,
        overflow = overflow,
        maxLines = maxLines,
        minLines = minLines,
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Compose Text replacement entry for an existing rich [AnnotatedString]. Renderer-owned spans stay
 * in the source [AnnotatedString]; paragraph-level text decoration is added as an outer span so the
 * same rich-text extraction path handles it.
 */
@Composable
fun CjkText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    style: ComposeTextStyle = ComposeTextStyle.Default,
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    val resolvedStyle = resolveComposeTextStyle(
        style = style,
        color = color,
        fontSize = fontSize,
        fontStyle = fontStyle,
        fontWeight = fontWeight,
        fontFamily = fontFamily,
        textDecoration = textDecoration,
        textAlign = textAlign,
        lineHeight = lineHeight,
    )
    val lowered = lowerComposeText(text, resolvedStyle, paragraphStyle)
    CjkText(
        text = lowered.text,
        modifier = modifier,
        textStyle = lowered.textStyle,
        paragraphStyle = lowered.paragraphStyle,
        softWrap = softWrap,
        overflow = overflow,
        maxLines = maxLines,
        minLines = minLines,
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Tiqian-native single-paragraph rich text entry with the same no-indent default as Compose Text.
 */
@Composable
fun CjkText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    textStyle: CjkTextStyle,
    paragraphStyle: ParagraphStyle = ComposeTextParagraphStyle,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onTextLayout: (LayoutResult) -> Unit = {},
) {
    val density = LocalDensity.current
    val coreStyle = textStyle.toCoreTextStyle(density)
    CjkTextLayout(
        text = text.text,
        semanticsText = text,
        modifier = modifier,
        textStyle = coreStyle,
        paragraphStyle = paragraphStyle.withCjkTextStyleLineHeight(textStyle, density),
        color = textStyle.colorArgbOrNull() ?: DEFAULT_TEXT_COLOR,
        decorations = text.cjkDecorations(),
        colorSpans = text.cjkColorSpans(),
        richTextSpans = text.cjkRichTextSpans(),
        spans = text.cjkStyleSpans(coreStyle, density),
        rubySpans = text.cjkRubySpans(),
        softWrap = softWrap,
        overflow = overflow,
        maxLines = maxLines,
        minLines = minLines,
        measurer = measurer,
        onTextLayout = onTextLayout,
    )
}

/**
 * Lays out MULTIPLE paragraphs and sections (CLREQ §6.2.1 段落调整). Each
 * paragraph runs the same internal layout node as the Compose Text facade; `CjkText` only splits the
 * source into blocks, maps each block's 段首缩排 style to the engine's
 * `blockIndent`/`firstLineIndent`, and stacks them.
 *
 * **行距段内段间一致**（CLREQ:「前段落末行、后段落首行与段落内行距一致」）成立于
 * 零 `Column` 间距：每个行盒上下各半 leading，相邻两段贴合后跨段 baseline 间距恰好
 * 一个 `lineHeight`。段间留白只来自显式的 [CjkBlock.Section]（空行=节）。
 */
@Composable
fun CjkText(
    blocks: List<CjkBlock>,
    modifier: Modifier = Modifier,
    textStyle: CjkTextStyle = CjkTextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    // Per-block layout出口: (blockIndex, itemIndex|null for a Paragraph, result).
    // List markers don't fire; the item BODY does, with its item index.
    onParagraphLayout: (blockIndex: Int, itemIndex: Int?, result: LayoutResult) -> Unit = { _, _, _ -> },
) {
    val density = LocalDensity.current
    val coreStyle = textStyle.toCoreTextStyle(density)
    // 节 (Section) = one blank line: the resolved line height (style > paragraph > default).
    val lineHeightPx = textStyle.lineHeightPxOrNull(density) ?: paragraphStyle.lineHeight
    val sectionPx = lineHeightPx ?: (coreStyle.fontSize * BODY_LINE_HEIGHT_EM)
    val sectionDp = with(density) { sectionPx.toDp() }
    Column(modifier) {
        blocks.forEachIndexed { blockIndex, block ->
            when (block) {
                is CjkBlock.Section -> Spacer(Modifier.height(sectionDp))
                is CjkBlock.Paragraph -> {
                    val (blockIc, firstIc) = block.indent.resolve(paragraphStyle.firstLineIndent)
                    CjkText(
                        text = block.text,
                        textStyle = textStyle,
                        paragraphStyle = paragraphStyle.copy(blockIndent = blockIc, firstLineIndent = firstIc),
                        overflow = TextOverflow.Visible,
                        measurer = measurer,
                        onTextLayout = { onParagraphLayout(blockIndex, null, it) },
                    )
                }
                is CjkBlock.List -> {
                    // 凸排列表：标记左对齐顶格于固定宽度的「标记列」(gutter)，正文整列
                    // 缩进到列宽——续行自然落在同列。列宽 = 自定义值，否则自动：默认 1 字，
                    // 但 1 字放不下列表里最宽的标记(如出现「10.」)时，整列升到放得下它的
                    // 最小整字数(每项同列、对齐)。标记宽实测——是几字由字体说了算，不靠数位数。
                    // Marker + body are FLUSH (the gutter is the only indent); the
                    // paragraph 段首缩进 must not stack on top of the列.
                    val listStyle = paragraphStyle.copy(firstLineIndent = Ic.Zero, blockIndent = Ic.Zero)
                    val gutterIc = block.indent ?: autoListGutterEm(block, coreStyle, listStyle, measurer)
                    val gutterDp = with(density) { gutterIc.toPx(coreStyle.fontSize).toDp() }
                    val markerStyle = listStyle.copy(lineLengthGrid = LineLengthGrid(enabled = false))
                    block.items.forEachIndexed { i, item ->
                        // alignByBaseline: when a body's first line carries 拼音 ruby it
                        // sits lower (its band is above), so line the marker up with the
                        // body TEXT by first baseline, not by the box top.
                        Row(Modifier.fillMaxWidth()) {
                            Box(Modifier.width(gutterDp).alignByBaseline()) {
                                CjkText(
                                    text = block.marker.format(block.start + i),
                                    textStyle = textStyle,
                                    paragraphStyle = markerStyle,
                                    overflow = TextOverflow.Visible,
                                    measurer = measurer,
                                )
                            }
                            CjkText(
                                text = item,
                                modifier = Modifier.weight(1f).alignByBaseline(),
                                textStyle = textStyle,
                                paragraphStyle = listStyle,
                                overflow = TextOverflow.Visible,
                                measurer = measurer,
                                onTextLayout = { onParagraphLayout(blockIndex, i, it) },
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Compose interop entry for document-style text. This keeps the CLREQ document model while letting
 * existing `TextStyle` values cross the Tiqian boundary unchanged at call sites.
 */
@Composable
fun CjkText(
    blocks: List<CjkBlock>,
    modifier: Modifier = Modifier,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(),
    onParagraphLayout: (blockIndex: Int, itemIndex: Int?, result: LayoutResult) -> Unit = { _, _, _ -> },
) {
    CjkText(
        blocks = blocks,
        modifier = modifier,
        textStyle = style.toCjkTextStyle(),
        paragraphStyle = lowerComposeParagraphStyle(style, paragraphStyle),
        measurer = measurer,
        onParagraphLayout = onParagraphLayout,
    )
}

/** A block in a CJK document (CLREQ §6.2.1). */
sealed interface CjkBlock {
    /**
     * 段落：富文本 [text]（`buildAnnotatedString` 表达 颜色/字号/字重/斜体/装饰/ruby）。
     * 纯文本走 [String] 便捷构造。
     */
    data class Paragraph(
        val text: AnnotatedString,
        val indent: ParagraphIndent = ParagraphIndent.FirstLine,
    ) : CjkBlock {
        constructor(text: String, indent: ParagraphIndent = ParagraphIndent.FirstLine) :
            this(AnnotatedString(text), indent)
    }

    /**
     * 编号/项目列表（CLREQ §6.2.1.1 凸排）：标记 [marker] 左对齐顶格，正文缩进到固定
     * 宽度的「标记列」，续行同列对齐。列宽默认 1 字，自动按列表中最宽标记升到放得下它
     * 的最小整字数（[indent] 非空则直接用该字数覆盖）。[start] 是首项编号。每项是富文本
     * （[AnnotatedString]）；纯文本项走 [ofStrings]。
     */
    data class List(
        val items: kotlin.collections.List<AnnotatedString>,
        val marker: ListMarker = ListMarker.Decimal,
        val indent: Ic? = null,
        val start: Int = 1,
    ) : CjkBlock {
        companion object {
            /** 纯文本项便捷构造。 */
            fun ofStrings(
                items: kotlin.collections.List<String>,
                marker: ListMarker = ListMarker.Decimal,
                indent: Ic? = null,
                start: Int = 1,
            ): List = List(items.map { AnnotatedString(it) }, marker, indent, start)
        }
    }

    /** 空行 = 一节的结束（CLREQ）：renders as one blank line of space. */
    data object Section : CjkBlock
}

/**
 * Auto 标记列宽（字）：1 字起，若 1 字放不下列表里最宽的标记，升到放得下它的最小整
 * 字数。标记宽**实测**（标记是真文本，丢给引擎量，grid 关掉取自然宽），所以「10.」算
 * 几字由字体决定，而非数位数。
 */
internal fun autoListGutterEm(
    block: CjkBlock.List,
    textStyle: TextStyle,
    paragraphStyle: ParagraphStyle,
    measurer: ParagraphMeasurer,
): Ic {
    // Measure the BARE marker: no grid quantization and no 段首缩进 (a marker is
    // flush), so the width is the glyphs alone — regardless of the caller's style.
    val noGrid = paragraphStyle.copy(
        lineLengthGrid = LineLengthGrid(enabled = false),
        firstLineIndent = Ic.Zero,
        blockIndent = Ic.Zero,
    )
    val widest = block.items.indices.maxOfOrNull { i ->
        measurer.measure(
            text = block.marker.format(block.start + i),
            constraints = LayoutConstraints(maxWidth = 100_000f),
            textStyle = textStyle,
            paragraphStyle = noGrid,
        ).size.width
    } ?: 0f
    return max(1, ceil(widest / textStyle.fontSize).toInt()).ic
}

/** Formats a list item's marker text (CLREQ 凸排 列表). */
sealed interface ListMarker {
    fun format(n: Int): String

    /** 阿拉伯数字 + 句点：`1.` `2.` … `10.`（最常见的编号列表）。 */
    data object Decimal : ListMarker {
        override fun format(n: Int): String = "$n."
    }

    /** 汉字数字 + 顿号：`一、` `二、` …（[suffix] 可改为 `）`/`.` 等）。 */
    data class CjkNumber(val suffix: String = "、") : ListMarker {
        override fun format(n: Int): String = cjkNumeral(n) + suffix
    }

    /** 带圈数字：`①` `②` …（1–20 用 U+2460 区，超出退回 `n.`）。 */
    data object Circled : ListMarker {
        override fun format(n: Int): String = if (n in 1..20) ('①' + (n - 1)).toString() else "$n."
    }

    /** 项目符号：默认 `•`，不随编号变（[glyph] 可改 `‧`/`·`/`◦` 等）。 */
    data class Bullet(val glyph: String = "•") : ListMarker {
        override fun format(n: Int): String = glyph
    }
}

private val CJK_DIGITS = listOf("零", "一", "二", "三", "四", "五", "六", "七", "八", "九")

/** 1–99 → 汉字数字（十、二十一…）；范围外退回阿拉伯数字。 */
private fun cjkNumeral(n: Int): String = when {
    n in 0..9 -> CJK_DIGITS[n]
    n in 10..19 -> "十" + (if (n == 10) "" else CJK_DIGITS[n - 10])
    n in 20..99 -> CJK_DIGITS[n / 10] + "十" + (if (n % 10 == 0) "" else CJK_DIGITS[n % 10])
    else -> n.toString()
}

/**
 * Per-paragraph 段首缩排 style (CLREQ §6.2.1.1/§6.2.1.2). Resolves to the
 * engine's `(blockIndent, firstLineIndent)`; the indent AMOUNT for
 * [FirstLine] stays the engine's MeasureAdaptiveFirstLineIndent decision.
 */
sealed interface ParagraphIndent {
    /** 段首缩进（自适应/基准）。 */
    data object FirstLine : ParagraphIndent

    /** 不缩进。 */
    data object Flush : ParagraphIndent

    /** 凸排：首行齐头、次行起缩 [indent]（对话/列表/法条）。 */
    data class Hanging(val indent: Ic = 2.ic) : ParagraphIndent

    /** 段落缩排：整段缩 [indent]（引用/诗词），首行再额外缩 [firstLine]。 */
    data class Block(val indent: Ic = 2.ic, val firstLine: Ic = Ic.Zero) : ParagraphIndent

    /** → `(blockIndent, firstLineIndent)`; null firstLine = adaptive default. */
    fun resolve(base: Ic?): Pair<Ic, Ic?> = when (this) {
        FirstLine -> Ic.Zero to base
        Flush -> Ic.Zero to Ic.Zero
        is Hanging -> indent to -indent
        is Block -> indent to firstLine
    }
}
