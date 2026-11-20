package org.tiqian.demo.android

import org.tiqian.android.view.CjkTextContent
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.Ic
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.Underline

private const val SHOWCASE_TEXT_COLOR = 0xFF202124.toInt()
private const val SHOWCASE_ACCENT_RED = 0xFFB00020.toInt()
private const val SHOWCASE_ACCENT_GREEN = 0xFF1A6E3C.toInt()

/** The Compose demo's underline sample: line decorations stop at punctuation glue. */
internal fun tiqianViewShowcaseUnderlineSample(textSize: Float): CjkTextContent =
    ShowcaseParagraphBuilder(TextStyle(fontSize = textSize)).apply {
        underlined("“开标点与句末标点。”")
        append(" 下划线只画字身，不吃首尾标点 glue。")
    }.toContent(ParagraphStyle().copy(firstLineIndent = Ic.Zero))

/**
 * The Compose demo essay, restated through the View frontend's typed content model. Outer lists
 * are 节 (sections), mirroring the `CjkBlock.Section` structure of the Compose blocks overload.
 */
internal fun tiqianViewShowcaseSections(textSize: Float): List<List<CjkTextContent>> {
    val base = TextStyle(fontSize = textSize)
    val style = ParagraphStyle()
    val flush = style.copy(firstLineIndent = Ic.Zero)
    // 凸排：块缩进 + 等量负段首缩进，续行悬挂在 marker 之后。
    fun hanging(markerWidth: Int) =
        style.copy(
            blockIndent = Ic(markerWidth.toFloat()),
            firstLineIndent = Ic((-markerWidth).toFloat()),
        )
    fun paragraph(
        paragraphStyle: ParagraphStyle = style,
        build: ShowcaseParagraphBuilder.() -> Unit,
    ) = ShowcaseParagraphBuilder(base).apply(build).toContent(paragraphStyle)

    return listOf(
        listOf(
            paragraph(flush) {
                styled("一台排版引擎的自述") { it.copy(fontSize = textSize * 1.9f, fontWeight = 700) }
            },
            paragraph {
                append("诸位好。我叫")
                ruby("提椠", "tíqiàn")
                append("，一台对中文正文")
                emphasis("斤斤计较")
                append("的排版引擎。别家把 espresso 和汉字一锅乱炖，我偏要在中西之间留出")
                emphasis("四分之一个字")
                append("的体面距离——你瞧，连这句里的 OpenType，我都没让它贴脸。")
            },
        ),
        listOf(
            paragraph(flush) {
                append("我的")
                styled("家规") { it.copy(fontWeight = 700) }
                append("不多，列在下面：")
            },
            paragraph(hanging(2)) {
                append("一、标点不许在行首撒野：逗号句号一律")
                emphasis("避头尾")
                append("，该挤就挤，该悬就悬。")
            },
            paragraph(hanging(2)) {
                append("二、字体随你挑——")
                styled("宋体的雅") { it.copy(fontFamilies = listOf("serif")) }
                append("、")
                styled("等宽的拙") { it.copy(fontFamilies = listOf("monospace")) }
                append("，按角色各取所需。")
            },
            paragraph(hanging(2)) {
                append("三、注音拼音都伺候，连")
                ruby("生僻字", "shēngpì zì")
                append("也给你标得明明白白。")
            },
        ),
        listOf(
            paragraph {
                append("上周我还痛失一员旧部：")
                decorated("双面印刷", DecorationKind.Mourning)
                append("。它本为纸张正反透印而生，奈何屏幕没有背面，只好请它")
                emphasis("先走一步")
                append("。")
                styled("纸终究比屏幕厚道，这话我只敢斜着说。") { it.copy(italic = true) }
            },
            paragraph {
                append("台湾来的朋友也照顾周到——")
                bopomofo("您", "ㄋㄧㄣˊ")
                bopomofo("好", "ㄏㄠˇ")
                append("，")
                bopomofo("请", "ㄑㄧㄥˇ")
                append("坐：ㄅㄆㄇ 竖在字旁，平上去入标得")
                emphasis("分毫不差")
                append("。")
            },
        ),
        listOf(
            paragraph(style.copy(firstLineIndent = Ic.Zero, blockIndent = Ic(2f))) {
                append("我奉")
                decorated("CLREQ", DecorationKind.ProperNoun)
                append("——也就是")
                decorated("《中文排版需求》", DecorationKind.BookTitle)
                append("——为圭臬，闲来也翻翻")
                decorated("Unicode", DecorationKind.ProperNoun)
                append("的家底。")
            },
            paragraph(flush) { append("顺带一提，这些我也顺手包办：") },
            paragraph(hanging(1)) { append("• 整数字格行长，正文严丝合缝落在格子上；") },
            paragraph(hanging(1)) { append("• 行尾标点悬挂、中西自动间距，统统全自动；") },
            paragraph(hanging(1)) { append("• 挤一挤放得下的，绝不硬把一整行拉稀。") },
        ),
        listOf(
            paragraph {
                append("有人嫌我")
                styled("龟毛") { it.copy(italic = true) }
                append("，我只当是")
                colored("褒奖", SHOWCASE_ACCENT_RED)
                append("。毕竟，好看的中文，是")
                styled("一个字一个字", argb = SHOWCASE_ACCENT_GREEN) {
                    it.copy(fontSize = textSize * 1.3f, fontWeight = 700)
                }
                append("抠出来的。")
            },
        ),
    )
}

private class ShowcaseParagraphBuilder(private val base: TextStyle) {
    private val text = StringBuilder()
    private val spans = mutableListOf<TextSpan>()
    private val colorSpans = mutableListOf<ColorSpan>()
    private val richTextSpans = mutableListOf<RichTextSpan>()
    private val decorations = mutableListOf<DecorationSpan>()
    private val rubySpans = mutableListOf<RubySpan>()

    fun append(value: String) {
        text.append(value)
    }

    fun styled(value: String, argb: Int? = null, transform: (TextStyle) -> TextStyle) {
        val range = appendRange(value)
        spans += TextSpan(range, transform(base))
        if (argb != null) colorSpans += ColorSpan(range.start, range.end, argb)
    }

    fun colored(value: String, argb: Int) {
        val range = appendRange(value)
        colorSpans += ColorSpan(range.start, range.end, argb)
    }

    fun underlined(value: String) {
        richTextSpans += RichTextSpan(appendRange(value), Underline.instance)
    }

    fun emphasis(value: String) = decorated(value, DecorationKind.Emphasis)

    fun decorated(value: String, kind: DecorationKind) {
        decorations += DecorationSpan(appendRange(value), kind)
    }

    fun ruby(value: String, annotation: String) {
        rubySpans += RubySpan(appendRange(value), annotation)
    }

    fun bopomofo(value: String, annotation: String) {
        rubySpans += RubySpan(appendRange(value), annotation, kind = RubyKind.Bopomofo)
    }

    fun toContent(paragraphStyle: ParagraphStyle): CjkTextContent = CjkTextContent(
        content = TiqianTextContent(text.toString(), spans = spans.toList()),
        textStyle = base,
        paragraphStyle = paragraphStyle,
        textColor = SHOWCASE_TEXT_COLOR,
        colorSpans = colorSpans.toList(),
        richTextSpans = richTextSpans.toList(),
        decorations = decorations.toList(),
        rubySpans = rubySpans.toList(),
    )

    private fun appendRange(value: String): TextRange {
        val start = text.length
        text.append(value)
        return TextRange(start, text.length)
    }
}
