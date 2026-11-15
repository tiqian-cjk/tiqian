package org.tiqian.apple

import kotlinx.cinterop.ExperimentalForeignApi
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.FloatIc
import org.tiqian.apple.coretext.CoreTextLayoutRenderer
import kotlin.math.ceil
import kotlin.math.max

/**
 * Swift-facing authoring API for a Tiqian document. This is the SDK surface an AppKit/UIKit/SwiftUI
 * app builds against — the app owns the *content* (what text, which runs are bold/colored, the list
 * items); the kit owns the *typesetting* (lowering to the engine's spans, driving the CLREQ layout,
 * stacking blocks, drawing). Nothing here hard-codes example passages.
 *
 * Author a paragraph fluently with [ParagraphContent], assemble paragraphs / lists / section
 * breaks into a [DocBuilder] (from `Typesetter.documentBuilder()`), then `layout(width:)`.
 */

/**
 * A rich-text paragraph's content, built fluently (each call returns `this`). Sizes are relative
 * (`sizeEm`, 1.0 = body) and colors are `0xAARRGGBB` longs (`0` = inherit the view's text color),
 * so the same content lays out at any body font size. Ruby / 着重号 / 专名号 / 书名号 / 示亡号 ride
 * alongside the base text exactly as CLREQ models them.
 */
class ParagraphContent {
    internal val pieces = mutableListOf<Piece>()
    internal var localeTag: String = "zh-Hans"
        private set

    /** Plain body text. */
    fun text(s: String): ParagraphContent = apply { pieces += Piece.Text(s) }

    /** A fully-specified styled run: [bold] weight, [italic], relative [sizeEm], [family], [argb] color (0 = inherit). */
    fun run(s: String, bold: Boolean, italic: Boolean, sizeEm: Float, family: String?, argb: Long): ParagraphContent =
        apply { pieces += Piece.Run(s, bold, italic, sizeEm, family, argb) }

    /**
     * A single source run carrying any combination of style, colour, ruby and CLREQ decorations.
     * [s] is appended exactly once; every aspect becomes an independent span over that same range.
     */
    fun piece(
        s: String, bold: Boolean, italic: Boolean, sizeEm: Float, family: String?, argb: Long,
        rubyReading: String?, rubyBopomofo: Boolean,
        emphasis: Boolean, properNoun: Boolean, bookTitle: Boolean, mourning: Boolean,
        locale: String? = null, rubyLocale: String? = null, linkTarget: String? = null,
    ): ParagraphContent = apply {
        val decorations = buildList {
            if (emphasis) add(DecorationKind.Emphasis)
            if (properNoun) add(DecorationKind.ProperNoun)
            if (bookTitle) add(DecorationKind.BookTitle)
            if (mourning) add(DecorationKind.Mourning)
        }
        pieces += Piece.Run(
            s = s,
            bold = bold,
            italic = italic,
            sizeEm = sizeEm,
            family = family,
            argb = argb,
            rubyReading = rubyReading,
            rubyBopomofo = rubyBopomofo,
            decorations = decorations,
            locale = locale,
            rubyLocale = rubyLocale,
            linkTarget = linkTarget,
        )
    }

    fun bold(s: String): ParagraphContent = run(s, bold = true, italic = false, sizeEm = 1f, family = null, argb = 0L)
    fun italic(s: String): ParagraphContent = run(s, bold = false, italic = true, sizeEm = 1f, family = null, argb = 0L)
    fun sized(s: String, em: Float): ParagraphContent = run(s, bold = false, italic = false, sizeEm = em, family = null, argb = 0L)
    fun family(s: String, family: String): ParagraphContent = run(s, bold = false, italic = false, sizeEm = 1f, family = family, argb = 0L)
    fun colored(s: String, argb: Long): ParagraphContent = run(s, bold = false, italic = false, sizeEm = 1f, family = null, argb = argb)

    /** 拼音 above the base characters. */
    fun pinyin(base: String, reading: String): ParagraphContent = apply { pieces += Piece.Ruby(base, reading, bopomofo = false) }

    /** 注音 (ㄅㄆㄇ) beside the base characters; `RubyKind.Bopomofo` defaults the注文 to `zh-TW`. */
    fun bopomofo(base: String, reading: String): ParagraphContent = apply {
        pieces += Piece.Ruby(base, reading, bopomofo = true)
    }

    fun emphasis(s: String): ParagraphContent = apply { pieces += Piece.Deco(s, DecorationKind.Emphasis) }
    fun properNoun(s: String): ParagraphContent = apply { pieces += Piece.Deco(s, DecorationKind.ProperNoun) }
    fun bookTitle(s: String): ParagraphContent = apply { pieces += Piece.Deco(s, DecorationKind.BookTitle) }
    fun mourning(s: String): ParagraphContent = apply { pieces += Piece.Deco(s, DecorationKind.Mourning) }

    /** BCP-47 locale for base-paragraph shaping (default zh-Hans; annotations keep their own locale). */
    fun locale(bcp47: String): ParagraphContent = apply { localeTag = bcp47 }
}

/** One inline piece of a paragraph (kit-internal; the app uses [ParagraphContent]'s methods). */
internal sealed interface Piece {
    data class Text(val s: String) : Piece
    data class Run(
        val s: String,
        val bold: Boolean,
        val italic: Boolean,
        val sizeEm: Float,
        val family: String?,
        val argb: Long,
        val rubyReading: String? = null,
        val rubyBopomofo: Boolean = false,
        val decorations: List<DecorationKind> = emptyList(),
        val locale: String? = null,
        val rubyLocale: String? = null,
        val linkTarget: String? = null,
    ) : Piece
    data class Ruby(
        val base: String,
        val reading: String,
        val bopomofo: Boolean,
        val locale: String? = null,
    ) : Piece
    data class Deco(val s: String, val kind: DecorationKind) : Piece
}

/** 段首缩排 (CLREQ §6.2.1) → the engine's `(blockIndent, firstLineIndent)`. */
internal sealed interface Indent {
    data object FirstLine : Indent
    data object Flush : Indent
    data class Hanging(val amount: Float = 2f) : Indent
    data class Quote(val amount: Float = 2f, val firstLine: Float = 0f) : Indent

    fun resolve(): Pair<Ic, Ic?> = when (this) {
        FirstLine -> Ic.Zero to null // adaptive default
        Flush -> Ic.Zero to Ic.Zero
        is Hanging -> FloatIc.ic(amount) to FloatIc.ic(-amount)
        is Quote -> FloatIc.ic(amount) to FloatIc.ic(firstLine)
    }
}

/** A list item's marker text (CLREQ 凸排). */
internal sealed interface Marker {
    fun format(n: Int): String

    data object Decimal : Marker {
        override fun format(n: Int): String = "$n."
    }

    data class CjkNumber(val suffix: String = "、") : Marker {
        override fun format(n: Int): String = cjkNumeral(n) + suffix
    }

    data class Bullet(val glyph: String = "•") : Marker {
        override fun format(n: Int): String = glyph
    }
}

private val CJK_DIGITS = listOf("零", "一", "二", "三", "四", "五", "六", "七", "八", "九")

/** 1–99 → 汉字数字 (十、二十一…); out of range → Arabic. */
private fun cjkNumeral(n: Int): String = when {
    n in 0..9 -> CJK_DIGITS[n]
    n in 10..19 -> "十" + (if (n == 10) "" else CJK_DIGITS[n - 10])
    n in 20..99 -> CJK_DIGITS[n / 10] + "十" + (if (n % 10 == 0) "" else CJK_DIGITS[n % 10])
    else -> n.toString()
}

/** A block the app has authored but not yet laid out. */
internal sealed interface AuthoredBlock {
    class Para(val content: ParagraphContent, val indent: Indent) : AuthoredBlock
    class ListBlock(val items: List<ParagraphContent>, val marker: Marker) : AuthoredBlock
    data object Section : AuthoredBlock
}

/**
 * Assembles authored blocks into a [Document]. Obtain one from `Typesetter.documentBuilder()`,
 * add blocks fluently, then [layout]. Bound to the typesetter's engine + renderer + body font size.
 */
@OptIn(ExperimentalForeignApi::class)
class DocBuilder internal constructor(
    private val engineLayout: (LayoutInput) -> LayoutResult,
    private val renderer: CoreTextLayoutRenderer,
    private val baseSize: Float,
) {
    private val blocks = mutableListOf<AuthoredBlock>()

    /** A body paragraph with the CLREQ adaptive first-line indent. */
    fun paragraph(content: ParagraphContent): DocBuilder = apply { blocks += AuthoredBlock.Para(content, Indent.FirstLine) }

    /** A paragraph with no indent (titles, lead-ins). */
    fun flushParagraph(content: ParagraphContent): DocBuilder = apply { blocks += AuthoredBlock.Para(content, Indent.Flush) }

    /** A quote block: the whole paragraph indents [amount] 字. */
    fun quote(content: ParagraphContent, amount: Float = 2f): DocBuilder = apply { blocks += AuthoredBlock.Para(content, Indent.Quote(amount)) }

    /** 凸排: first line flush, the rest indent [amount] 字. */
    fun hangingParagraph(content: ParagraphContent, amount: Float = 2f): DocBuilder = apply { blocks += AuthoredBlock.Para(content, Indent.Hanging(amount)) }

    /** One blank line of vertical space (CLREQ 节). */
    fun section(): DocBuilder = apply { blocks += AuthoredBlock.Section }

    /** 编号列表 with 汉字数字 markers (一、二、…), body aligned in a 凸排 column. */
    fun numberedList(items: List<ParagraphContent>): DocBuilder = apply { blocks += AuthoredBlock.ListBlock(items, Marker.CjkNumber()) }

    /** 编号列表 with Arabic markers (1. 2. …). */
    fun decimalList(items: List<ParagraphContent>): DocBuilder = apply { blocks += AuthoredBlock.ListBlock(items, Marker.Decimal) }

    /** 项目符号列表 (• …). */
    fun bulletList(items: List<ParagraphContent>): DocBuilder = apply { blocks += AuthoredBlock.ListBlock(items, Marker.Bullet()) }

    /** Lay every block out at [width] engine-px and stack them into a drawable [Document]. */
    fun layout(width: Float): Document = layoutBlocks(blocks, engineLayout, renderer, width, baseSize)
}

/** A paragraph lowered from authored pieces to the engine's span model. */
internal class Lowered(
    val text: String,
    val spans: List<TextSpan>,
    val colorSpans: List<ColorSpan>,
    val rubySpans: List<RubySpan>,
    val decorations: List<DecorationSpan>,
    val richTextSpans: List<RichTextSpan>,
    val sourceBoundaries: Set<Int>,
    val locale: String,
)

/** Lower [content] to the engine's spans, turning relative `sizeEm` into px at [baseSize]. */
internal fun lower(content: ParagraphContent, baseSize: Float): Lowered {
    val sb = StringBuilder()
    val spans = mutableListOf<TextSpan>()
    val colors = mutableListOf<ColorSpan>()
    val rubies = mutableListOf<RubySpan>()
    val decos = mutableListOf<DecorationSpan>()
    val richText = mutableListOf<RichTextSpan>()
    val bounds = mutableSetOf<Int>()
    for (piece in content.pieces) {
        when (piece) {
            is Piece.Text -> sb.append(piece.s)
            is Piece.Run -> {
                val start = sb.length
                sb.append(piece.s)
                val end = sb.length
                val styled = piece.bold || piece.italic || piece.sizeEm != 1f ||
                    piece.family != null || piece.locale != null
                if (styled) {
                    spans += TextSpan(
                        TextRange(start, end),
                        TextStyle(
                            fontFamilies = piece.family?.let { listOf(it) } ?: emptyList(),
                            fontSize = baseSize * piece.sizeEm,
                            locale = piece.locale ?: content.localeTag,
                            fontWeight = if (piece.bold) 700 else 400,
                            italic = piece.italic,
                        ),
                    )
                    bounds += start; bounds += end
                }
                if (piece.argb != 0L) {
                    colors += ColorSpan(start, end, (piece.argb and 0xFFFFFFFFL).toInt())
                    bounds += start; bounds += end
                }
                piece.rubyReading?.let { reading ->
                    rubies += RubySpan(
                        TextRange(start, end),
                        reading,
                        kind = if (piece.rubyBopomofo) RubyKind.Bopomofo else RubyKind.Pinyin,
                        locale = piece.rubyLocale ?: if (piece.rubyBopomofo) "zh-TW" else null,
                    )
                    bounds += start; bounds += end
                }
                piece.decorations.forEach { kind ->
                    decos += DecorationSpan(TextRange(start, end), kind)
                    bounds += start; bounds += end
                }
                piece.linkTarget?.let { target ->
                    richText += RichTextSpan(TextRange(start, end), Link(target))
                    bounds += start; bounds += end
                }
            }
            is Piece.Ruby -> {
                val start = sb.length
                sb.append(piece.base)
                val end = sb.length
                rubies += RubySpan(
                    TextRange(start, end),
                    piece.reading,
                    kind = if (piece.bopomofo) RubyKind.Bopomofo else RubyKind.Pinyin,
                    locale = piece.locale ?: if (piece.bopomofo) "zh-TW" else null,
                )
                bounds += start; bounds += end
            }
            is Piece.Deco -> {
                val start = sb.length
                sb.append(piece.s)
                val end = sb.length
                decos += DecorationSpan(TextRange(start, end), piece.kind)
                bounds += start; bounds += end
            }
        }
    }
    return Lowered(sb.toString(), spans, colors, rubies, decos, richText, bounds, content.localeTag)
}

/**
 * Lays each block out (lowering paragraphs to engine spans) and stacks them vertically with uniform
 * cross-paragraph line spacing; a [Marker] column offsets list bodies (CLREQ 凸排). Mirrors the
 * Compose demo's block layout — but this is generic document layout, not example content.
 */
@OptIn(ExperimentalForeignApi::class)
private fun layoutBlocks(
    blocks: List<AuthoredBlock>,
    engineLayout: (LayoutInput) -> LayoutResult,
    renderer: CoreTextLayoutRenderer,
    width: Float,
    baseSize: Float,
): Document {
    val placed = mutableListOf<PlacedBlock>()
    var cursorY = 0f
    val sectionGap = baseSize * 1.5f // one blank line (中文正文 leading)

    fun layoutPara(content: ParagraphContent, indent: Indent, columnWidth: Float): Pair<LayoutResult, Lowered> {
        val low = lower(content, baseSize)
        val (blockIc, firstIc) = indent.resolve()
        val result = engineLayout(
            LayoutInput(
                content = TiqianTextContent(low.text, low.spans, low.sourceBoundaries.toList()),
                textStyle = TextStyle(fontSize = baseSize, locale = low.locale),
                paragraphStyle = ParagraphStyle(blockIndent = blockIc, firstLineIndent = firstIc),
                constraints = LayoutConstraints(maxWidth = columnWidth),
                rubySpans = low.rubySpans,
                decorations = low.decorations,
            ),
        )
        return result to low
    }

    for (block in blocks) {
        when (block) {
            is AuthoredBlock.Section -> cursorY += sectionGap
            is AuthoredBlock.Para -> {
                val (result, low) = layoutPara(block.content, block.indent, width)
                placed += PlacedBlock(
                    result,
                    low.spans,
                    low.colorSpans,
                    low.richTextSpans,
                    x = 0.0,
                    yTop = cursorY.toDouble(),
                )
                cursorY += result.size.height
            }
            is AuthoredBlock.ListBlock -> {
                // Marker column width = widest marker rounded up to a whole 字, so every item's body
                // aligns in one column (CLREQ 凸排), continuation lines included.
                val markerResults = block.items.indices.map { i ->
                    engineLayout(
                        LayoutInput(
                            content = TiqianTextContent(block.marker.format(i + 1)),
                            textStyle = TextStyle(fontSize = baseSize),
                            // Match Compose's listStyle: the marker column is already the list's
                            // indent, so marker paragraphs must never acquire the adaptive body
                            // first-line indent. Otherwise its measured width grows by two 字 and
                            // the whole body column is shifted by the same bogus amount.
                            paragraphStyle = ParagraphStyle(
                                firstLineIndent = Ic.Zero,
                                blockIndent = Ic.Zero,
                                lineLengthGrid = LineLengthGrid(enabled = false),
                            ),
                            constraints = LayoutConstraints(maxWidth = width),
                        ),
                    )
                }
                val widest = markerResults.maxOfOrNull { it.size.width } ?: 0f
                val gutterPx = max(1, ceil(widest / baseSize).toInt()) * baseSize
                block.items.forEachIndexed { i, item ->
                    val markerR = markerResults[i]
                    // An extremely narrow native view can be smaller than its marker column.
                    // Preserve the marker gutter and let the body overflow that impossible measure,
                    // but never pass a non-positive constraint into the layout core.
                    val bodyWidth = (width - gutterPx).coerceAtLeast(1f)
                    val (bodyR, low) = layoutPara(item, Indent.Flush, bodyWidth)
                    // `ListFirstBaselineAlignment`: marker and body are independent paragraphs and
                    // may have different first-line boxes (notably •/decimal vs CJK). Align their
                    // actual baselines, then expand the row around whichever block extends farther.
                    val markerBaseline = markerR.lines.firstOrNull()?.baseline ?: 0f
                    val bodyBaseline = bodyR.lines.firstOrNull()?.baseline ?: 0f
                    val markerOffset = bodyBaseline - markerBaseline
                    val rowTopOffset = minOf(0f, markerOffset)
                    val markerY = cursorY + markerOffset - rowTopOffset
                    val bodyY = cursorY - rowTopOffset
                    placed += PlacedBlock(
                        markerR,
                        emptyList(),
                        emptyList(),
                        emptyList(),
                        // Marker alignment follows its occupied typographic box. Do not apply an
                        // ink-edge optical correction: the glyph's own side bearings are content.
                        x = 0.0,
                        yTop = markerY.toDouble(),
                    )
                    placed += PlacedBlock(
                        bodyR,
                        low.spans,
                        low.colorSpans,
                        low.richTextSpans,
                        x = gutterPx.toDouble(),
                        yTop = bodyY.toDouble(),
                        sourceSeparatorBefore = "",
                    )
                    cursorY += max(
                        markerOffset - rowTopOffset + markerR.size.height,
                        -rowTopOffset + bodyR.size.height,
                    )
                }
            }
        }
    }
    return Document(placed, width = width.toDouble(), height = cursorY.toDouble(), renderer = renderer)
}
