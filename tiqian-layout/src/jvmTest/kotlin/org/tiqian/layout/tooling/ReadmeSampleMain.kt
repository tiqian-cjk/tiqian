package org.tiqian.layout.tooling

import org.jetbrains.skia.DynamicMemoryWStream
import org.jetbrains.skia.Font
import org.jetbrains.skia.FontSlant
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect as SkiaRect
import org.jetbrains.skia.shaper.Shaper
import org.jetbrains.skia.svg.SVGCanvas
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubyLineHeightMode
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaSystemTypefaces
import org.tiqian.shaping.skia.SkiaTextShaper
import org.tiqian.shaping.skia.drawTiqianGlyphs
import org.tiqian.shaping.skia.shapeTextBlob
import org.w3c.dom.Node
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.transform.OutputKeys
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult
import kotlin.math.abs

private const val SAMPLE_TEXT =
    "博物馆在整理藏品时，会为每件器物建立独立记录。编号A-17的青铜盉高26.8厘米，口径12.4厘米；" +
        "器盖内有铭文，旧拓本记作“王……作”，腹部饰两道弦纹。旧目录《馆藏青铜器》将它记作" +
        "“兽首流铜器”，1986年（原登记簿未载月份）复查时改用现名——原编号、照片和修复记录仍" +
        "一并保留，以便核对。"

private const val FONT_SIZE = 28f
private const val MEASURE = 840f
private const val CANVAS_PADDING = 42f
private const val SVG_NAMESPACE = "http://www.w3.org/2000/svg"
private const val BLACK_INK = -0x1000000
private const val WHITE_INK = -0x1

fun main(args: Array<String>) {
    require(args.size == 2) { "Expected black-text and white-text SVG paths" }
    val variants = listOf(
        File(args[0]) to BLACK_INK,
        File(args[1]) to WHITE_INK,
    )
    val result = layoutReadmeSample()
    verifyReadmeSample(result)

    variants.forEach { (output, inkColor) ->
        output.parentFile.mkdirs()
        output.writeBytes(withAccessibilityMetadata(renderSvg(result, inkColor)))
        println("README sample: ${output.absolutePath}")
    }
    println("lines=${result.lines.size}, size=${result.size.width}x${result.size.height}")
}

private fun layoutReadmeSample(): LayoutResult {
    val rubyRange = SAMPLE_TEXT.rangeOf("盉")
    val emphasisRange = SAMPLE_TEXT.rangeOf("一并保留")
    val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = SkiaTextShaper(),
        fontMetricsResolver = SkiaFontMetricsResolver(),
    )
    return engine.layout(
        LayoutInput(
            content = TiqianTextContent(SAMPLE_TEXT),
            textStyle = TextStyle(fontSize = FONT_SIZE),
            paragraphStyle = ParagraphStyle(
                firstLineIndent = 2.ic,
                rubyLineHeightMode = RubyLineHeightMode.UniformParagraph,
            ),
            constraints = LayoutConstraints(maxWidth = MEASURE),
            decorations = listOf(DecorationSpan(emphasisRange, DecorationKind.Emphasis)),
            rubySpans = listOf(RubySpan(rubyRange, "hé")),
        ),
    )
}

private fun verifyReadmeSample(result: LayoutResult) {
    val missingGlyphs = result.debug.shapingDecisions.sumOf { it.missingGlyphs }
    check(missingGlyphs == 0) { "README sample shaped $missingGlyphs missing glyphs" }
    check(result.debug.rubyDecisions.singleOrNull()?.text == "hé") {
        "README sample must contain the hé ruby annotation"
    }
    val rubyLineHeight = result.debug.rubyLineHeightDecision
        ?: error("README sample must expose its ruby line-height decision")
    check(rubyLineHeight.mode == RubyLineHeightMode.UniformParagraph.name) {
        "README sample must use uniform paragraph ruby line height: $rubyLineHeight"
    }
    check(rubyLineHeight.lineExtras.all { abs(it - rubyLineHeight.maxExtra) <= 0.01f }) {
        "README sample must apply one ruby line-height increment to every line: $rubyLineHeight"
    }
    val lineHeights = result.lines.map { it.bottom - it.top }
    check(lineHeights.all { abs(it - lineHeights.first()) <= 0.01f }) {
        "README sample must keep a uniform baseline grid: $lineHeights"
    }
    val emphasisDots = result.debug.decorationDecisions.count {
        it.kind == DecorationKind.Emphasis.name && it.applied
    }
    check(emphasisDots == 4) { "README sample expected 4 emphasis dots, got $emphasisDots" }
    check(result.lines.size >= 4) { "README sample should demonstrate multi-line layout" }
}

private fun renderSvg(result: LayoutResult, inkColor: Int): ByteArray {
    val width = MEASURE + CANVAS_PADDING * 2f
    val height = result.size.height + CANVAS_PADDING * 2f
    val stream = DynamicMemoryWStream()
    val canvas = SVGCanvas.make(
        SkiaRect(0f, 0f, width, height),
        stream,
        convertTextToPaths = true,
        prettyXML = true,
    )
    val ink = Paint().apply { color = inkColor }
    val cjkFont = Font(SkiaSystemTypefaces.cjk, FONT_SIZE)
    val latinFont = Font(SkiaSystemTypefaces.latin, FONT_SIZE)
    val shaper = Shaper.makeShaperDrivenWrapper()
    try {
        canvas.save()
        canvas.translate(CANVAS_PADDING, CANVAS_PADDING)
        drawTiqianGlyphs(canvas, result, cjkFont, latinFont, ink, shaper)

        result.debug.decorationDecisions.forEach { dot ->
            if (dot.applied && dot.dotDiameter > 0f) {
                canvas.drawCircle(
                    dot.anchorX,
                    dot.anchorY,
                    dot.dotDiameter / 2f,
                    ink,
                )
            }
        }

        result.debug.rubyDecisions.forEach { ruby ->
            val rubyStyle = FontStyle(ruby.fontWeight, FontStyle.NORMAL.width, FontSlant.UPRIGHT)
            val typeface = SkiaSystemTypefaces.typeface(
                isLatin = true,
                family = ruby.fontFamilies.firstOrNull(),
                style = rubyStyle,
            ) ?: SkiaSystemTypefaces.latin
            Font(typeface, ruby.fontSize).use { rubyFont ->
                val rubyWidth = rubyFont.measureTextWidth(ruby.text)
                shapeTextBlob(shaper, ruby.text, rubyFont, result.input.textStyle.locale)?.use { blob ->
                    canvas.drawTextBlob(blob, ruby.centerX - rubyWidth / 2f, ruby.baselineY, ink)
                }
            }
        }
        canvas.restore()
    } finally {
        canvas.close()
        shaper.close()
        latinFont.close()
        cjkFont.close()
        ink.close()
    }

    return try {
        val bytes = ByteArray(stream.bytesWritten())
        check(stream.read(bytes, 0, bytes.size)) { "Unable to read generated SVG bytes" }
        bytes
    } finally {
        stream.close()
    }
}

private fun withAccessibilityMetadata(svg: ByteArray): ByteArray {
    val documentBuilderFactory = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        setFeature("http://xml.org/sax/features/external-general-entities", false)
        setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
        setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
    }
    val document = documentBuilderFactory.newDocumentBuilder().parse(ByteArrayInputStream(svg))
    val root = document.documentElement
    removeWhitespaceTextNodes(root)
    val title = document.createElementNS(SVG_NAMESPACE, "title").apply {
        setAttribute("id", "sample-title")
        textContent = "提椠简体中文横排样张"
    }
    val description = document.createElementNS(SVG_NAMESPACE, "desc").apply {
        setAttribute("id", "sample-description")
        textContent = "$SAMPLE_TEXT 盉字上方注拼音 hé，一并保留四字使用着重号。"
    }
    root.insertBefore(description, root.firstChild)
    root.insertBefore(title, description)
    root.setAttribute("role", "img")
    root.setAttribute("aria-labelledby", "sample-title sample-description")

    val output = ByteArrayOutputStream()
    val transformerFactory = TransformerFactory.newInstance().apply {
        setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
        setAttribute(XMLConstants.ACCESS_EXTERNAL_STYLESHEET, "")
    }
    transformerFactory.newTransformer().apply {
        setOutputProperty(OutputKeys.ENCODING, "UTF-8")
        setOutputProperty(OutputKeys.INDENT, "yes")
        setOutputProperty("{http://xml.apache.org/xslt}indent-amount", "2")
        transform(DOMSource(document), StreamResult(output))
    }
    return output.toByteArray()
}

private fun removeWhitespaceTextNodes(node: Node) {
    var child = node.firstChild
    while (child != null) {
        val next = child.nextSibling
        if (child.nodeType == Node.TEXT_NODE && child.nodeValue.isNullOrBlank()) {
            node.removeChild(child)
        } else {
            removeWhitespaceTextNodes(child)
        }
        child = next
    }
}

private fun String.rangeOf(fragment: String): TextRange {
    val start = indexOf(fragment)
    require(start >= 0) { "Missing sample fragment: $fragment" }
    return TextRange(start, start + fragment.length)
}
