package org.tiqian.web

import kotlinx.browser.document
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
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
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.web.WebCanvasFontMetricsResolver
import org.tiqian.shaping.web.WebCanvasTextShaper
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.HTMLElement
import org.w3c.dom.HTMLInputElement

/**
 * ADR 0039 live demo: the real Tiqian engine lays out CJK body text IN THE
 * BROWSER (wasmJs), measuring with `WebCanvasTextShaper` (offscreen measureText)
 * and painting via `DomParagraphRenderer` (`PreBrokenLineDom`). The width slider
 * exercises `ReflowByRebreak` — each change re-runs the engine and re-paints.
 */
private class DemoPara(
    val text: String,
    val decorations: List<DecorationSpan> = emptyList(), // Emphasis / BookTitle — affect layout
    val colorSpans: List<ColorSpan> = emptyList(),        // render-only
    val richTextSpans: List<RichTextSpan> = emptyList(),  // render-only
    val spans: List<TextSpan> = emptyList(),              // layout-affecting style spans
    val rubySpans: List<RubySpan> = emptyList(),          // layout-affecting annotations
)

private val paragraphs = listOf(
    DemoPara("自然语言是图灵完备的。不存在一个语言中的概念是另一个语言中原则上无法表达的。"),
    DemoPara(
        "有人会说星期八是 the eighth day of the week，有人会说十三月是 the thirteenth " +
            "month of the year——是不是不重要。哪怕你找到了「星期八」和 the eighth day of " +
            "the week 之间的精微差别，只要这个差别是可以在汉语中定义的，它就是能在英语中" +
            "表达的。这本质上是 Church-Turing Thesis。",
    ),
    // 富文本装饰:着重号(0-3)、下划线(4-7)、颜色(8-10)、高亮(11-13)、删除线(14-17)、行内代码(18-22)、链接(23-35)、书名号甲式波浪线(39-42)
    DemoPara(
        "着重号、下划线、颜色、高亮、删除线、code、跨行链接动画同步状态演示、书名号红楼梦。",
        decorations = listOf(
            DecorationSpan(TextRange(0, 3), DecorationKind.Emphasis),
            DecorationSpan(TextRange(39, 42), DecorationKind.BookTitle),
        ),
        colorSpans = listOf(
            ColorSpan(0, 3, 0xFFB9472A.toInt()),
            ColorSpan(4, 7, 0xFF2563A6.toInt()),
            ColorSpan(8, 10, 0xFFCC3311.toInt()),
            ColorSpan(39, 42, 0xFF6F3FB5.toInt()),
        ),
        richTextSpans = listOf(
            RichTextSpan(TextRange(4, 7), RichTextRole.Underline),
            RichTextSpan(TextRange(11, 13), RichTextRole.Background, RichTextPaint(0xFFFFE066.toInt())),
            RichTextSpan(TextRange(14, 17), RichTextRole.LineThrough),
            RichTextSpan(TextRange(18, 22), RichTextRole.InlineCode),
            RichTextSpan(TextRange(23, 35), RichTextRole.Link("https://www.w3.org/TR/clreq/")),
        ),
        spans = listOf(
            TextSpan(TextRange(18, 22), TextStyle(fontSize = FONT_SIZE, fontFamilies = listOf("monospace"))),
        ),
    ),
    // 富文本样式:大字(0-2)、粗体(3-5)、italic(6-12)、衬线(13-15)
    DemoPara(
        "大字、粗体、italic、衬线。",
        spans = listOf(
            TextSpan(TextRange(0, 2), TextStyle(fontSize = FONT_SIZE * 1.45f)),
            TextSpan(TextRange(3, 5), TextStyle(fontSize = FONT_SIZE, fontWeight = 700)),
            TextSpan(TextRange(6, 12), TextStyle(fontSize = FONT_SIZE, italic = true)),
            TextSpan(TextRange(13, 15), TextStyle(fontSize = FONT_SIZE, fontFamilies = listOf("serif"))),
        ),
    ),
    // 行间注 ruby:北京(3-5)、咖啡(6-8)
    DemoPara(
        "行间注北京和咖啡。",
        rubySpans = listOf(
            RubySpan(TextRange(3, 5), "Běijīng"),
            RubySpan(TextRange(6, 8), "kāfēi"),
        ),
    ),
    // 单字 ruby:中(3-4)；相邻长注文避让:张(7-8)、王(8-9)、李(9-10)
    DemoPara(
        "单字注中；避让张王李。",
        rubySpans = listOf(
            RubySpan(TextRange(3, 4), "zhōng"),
            RubySpan(TextRange(7, 8), "zhuāng"),
            RubySpan(TextRange(8, 9), "chuáng"),
            RubySpan(TextRange(9, 10), "shuāng"),
        ),
    ),
    // ruby 悬出侵入较短相邻注文空间:明(4-5)、一(5-6)
    DemoPara(
        "短邻侵入明一。",
        rubySpans = listOf(
            RubySpan(TextRange(4, 5), "míng"),
            RubySpan(TextRange(5, 6), "yī"),
        ),
    ),
    // 注音 bopomofo(右侧竖排 ㄅㄆㄇ + 调号):覆盖阴平、阳平、上声、去声、轻声。
    DemoPara(
        "注音中文你好的。",
        rubySpans = listOf(
            RubySpan(TextRange(2, 3), "ㄓㄨㄥ", kind = RubyKind.Bopomofo),
            RubySpan(TextRange(3, 4), "ㄨㄣˊ", kind = RubyKind.Bopomofo),
            RubySpan(TextRange(4, 5), "ㄋㄧˇ", kind = RubyKind.Bopomofo),
            RubySpan(TextRange(5, 6), "ㄏㄠˋ", kind = RubyKind.Bopomofo),
            RubySpan(TextRange(6, 7), "˙ㄉㄜ", kind = RubyKind.Bopomofo),
        ),
    ),
)

private fun DemoPara.sourceBoundaries(): Set<Int> = buildSet {
    fun addBoundary(offset: Int) {
        if (offset > 0 && offset < text.length) add(offset)
    }
    fun addRange(start: Int, end: Int) {
        addBoundary(start)
        addBoundary(end)
    }
    decorations.forEach { addRange(it.range.start, it.range.end) }
    colorSpans.forEach { addRange(it.start, it.end) }
    richTextSpans.forEach { addRange(it.range.start, it.range.end) }
    spans.forEach { addRange(it.range.start, it.range.end) }
    rubySpans.forEach { addRange(it.baseRange.start, it.baseRange.end) }
}

private const val FONT_SIZE = 19f

fun main() {
    // The APPLICATION picks its fonts; the SAME instance feeds both the shaper
    // (measure) and the renderer (draw) so advances match the drawn glyphs.
    val fonts = WebFontFamilies(
        cjk = "\"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
        latin = "\"Inter\", \"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
    )
    val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        fontMetricsResolver = WebCanvasFontMetricsResolver(fonts),
        textShaper = WebCanvasTextShaper(fonts),
    )
    val root = document.getElementById("app") as HTMLElement

    val label = document.createElement("div") as HTMLElement
    label.style.setProperty("font", "13px sans-serif")
    label.style.setProperty("color", "#666")
    label.style.setProperty("margin-bottom", "8px")

    val slider = (document.createElement("input") as HTMLInputElement).apply {
        type = "range"
        min = "220"
        max = "560"
        value = "360"
        style.setProperty("width", "560px")
        style.setProperty("display", "block")
        style.setProperty("margin-bottom", "20px")
    }

    val stage = document.createElement("div") as HTMLElement
    stage.style.setProperty("background", "#fff")
    stage.style.setProperty("border", "1px solid #e6e3de")
    stage.style.setProperty("border-radius", "6px")
    stage.style.setProperty("padding", "16px")

    fun relayout() {
        val width = slider.value.toFloat()
        label.textContent = "提椠引擎 · 浏览器内布局 · 宽度 ${width.toInt()}px · 字号 ${FONT_SIZE.toInt()}px"
        stage.style.setProperty("width", "${width}px")
        while (stage.firstChild != null) stage.removeChild(stage.firstChild!!)
        for (p in paragraphs) {
            val para = document.createElement("div") as HTMLElement
            para.style.setProperty("margin-bottom", "14px")
            val result = engine.layout(
                LayoutInput(
                    content = TiqianTextContent(
                        text = p.text,
                        spans = p.spans,
                        sourceBoundaries = p.sourceBoundaries(),
                    ),
                    textStyle = TextStyle(fontSize = FONT_SIZE),
                    constraints = LayoutConstraints(maxWidth = width),
                    paragraphStyle = ParagraphStyle(
                        lineHeight = FONT_SIZE * 1.75f,
                        firstLineIndent = Ic(2f),
                    ),
                    decorations = p.decorations,
                    rubySpans = p.rubySpans,
                ),
            )
            DomParagraphRenderer.render(para, result, fonts, p.colorSpans, p.richTextSpans)
            stage.appendChild(para)
        }
    }

    slider.addEventListener("input") { relayout() }
    root.appendChild(label)
    root.appendChild(slider)
    root.appendChild(stage)
    relayout()
}
// Source-faithful copy is pure DOM glue (reads `data-tq-src`, no engine state),
// so it lives in index.html's <script>, not here (ADR 0039 CopyTransparentSpacingSpans).
