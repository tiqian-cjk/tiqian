package org.tiqian.playground

import org.tiqian.core.Ic
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.positionedClusters
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaTextShaper
import java.io.File

/**
 * ADR 0039 `PreBrokenLineDom` 原型:用真引擎 + 真 Skia 度量把正文排好,把每行的
 * positioned cluster 几何序列化成自包含 HTML —— 引擎持有全部行布局(推入推出 /
 * 邻行均摊 / 避头尾 / justify),DOM 只把 cluster 画在引擎算好的 drawX 上。并排一栏
 * 浏览器默认渲染(同宽同字号)作对照,验证「模型必须真」在浏览器里长什么样。
 *
 * 这是静态忠实渲染(冻结当前宽度几何);真正的 ReflowByRebreak 通过对同一段正文
 * 在两个宽度各排一遍来演示。运行:`./gradlew :tiqian-playground:runWebPrototype`。
 */
private val paragraphs = listOf(
    "自然语言是图灵完备的。不存在一个语言中的概念是另一个语言中原则上无法表达的。",
    "有人会说星期八是 the eighth day of the week，有人会说十三月是 the thirteenth " +
        "month of the year——是不是不重要。哪怕你找到了「星期八」和 the eighth day of " +
        "the week 之间的精微差别，只要这个差别是可以在汉语中定义的，它就是能在英语中" +
        "表达的。这本质上是 Church-Turing Thesis。",
)

private const val FONT_SIZE = 18f
private val WIDTHS = listOf(360f, 280f)

fun main() {
    val shaper = SkiaTextShaper()
    // 默认不断词(ADR 0029 2026-07 amendment):中文夹用英文整词转行。
    val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = shaper,
    )

    fun layout(text: String, maxWidth: Float): LayoutResult = engine.layout(
        LayoutInput(
            content = TiqianTextContent(text),
            textStyle = TextStyle(fontSize = FONT_SIZE),
            constraints = LayoutConstraints(maxWidth = maxWidth),
            paragraphStyle = ParagraphStyle(
                lineHeight = FONT_SIZE * 1.7f,
                firstLineIndent = Ic(2f),
            ),
        ),
    )

    val sb = StringBuilder()
    sb.append(HTML_HEAD)
    for (width in WIDTHS) {
        sb.append("<h2>宽度 ${width.toInt()}px · 字号 ${FONT_SIZE.toInt()}px</h2>\n")
        sb.append("<div class=\"cols\">\n")
        // 提椠引擎栏
        sb.append("<div class=\"col\"><div class=\"tag\">提椠引擎 · PreBrokenLineDom</div>")
        sb.append("<div class=\"tq\" style=\"width:${width}px\" lang=\"zh-Hans\">\n")
        for (text in paragraphs) sb.append(renderEngineParagraph(layout(text, width)))
        sb.append("</div></div>\n")
        // 浏览器默认栏
        sb.append("<div class=\"col\"><div class=\"tag\">浏览器默认 &lt;p&gt;</div>")
        sb.append("<div class=\"native\" style=\"width:${width}px\" lang=\"zh-Hans\">\n")
        for (text in paragraphs) sb.append("<p>").append(escape(text)).append("</p>\n")
        sb.append("</div></div>\n")
        sb.append("</div>\n")
    }
    sb.append(HTML_TAIL)

    val out = File(System.getenv("TIQIAN_WEB_PROTO_OUT") ?: "build/reports/tiqian-web-prototype/index.html")
    out.parentFile.mkdirs()
    out.writeText(sb.toString())
    println("Web prototype HTML: ${out.absolutePath}")
}

/** One paragraph → stacked line blocks; each cluster absolutely placed at engine drawX. */
private fun renderEngineParagraph(result: LayoutResult): String {
    val sb = StringBuilder()
    for (line in result.lines) {
        val h = line.bottom - line.top
        sb.append("<div class=\"ln\" style=\"height:${h}px\">")
        for (pc in result.positionedClusters(line)) {
            val cluster = result.clusters[pc.clusterIndex]
            if (cluster.displayText.isBlank()) continue
            // 每个 cluster 落在引擎算好的 drawX;共享行高 → 基线自动对齐。半宽标点靠
            // 邻居贴近 + 标点墨迹本就偏在半格内自然成形,无需裁剪。
            sb.append("<span style=\"left:${pc.drawX}px;line-height:${h}px\">")
                .append(escape(cluster.displayText))
                .append("</span>")
        }
        sb.append("</div>\n")
    }
    return sb.toString()
}

private fun escape(s: String): String =
    s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

private val HTML_HEAD = """
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>提椠 · Web 渲染原型 (ADR 0039)</title>
<style>
  body { margin: 0; padding: 24px; background: #faf9f7; color: #1a1a1a;
         font-family: -apple-system, "PingFang SC", "Noto Sans CJK SC", sans-serif; }
  h1 { font-size: 18px; font-weight: 600; }
  h1 .sub { color: #888; font-weight: 400; font-size: 14px; margin-left: 8px; }
  h2 { font-size: 14px; color: #555; font-weight: 500; margin: 28px 0 10px; }
  .cols { display: flex; gap: 28px; flex-wrap: wrap; align-items: flex-start; }
  .col { }
  .tag { font-size: 11px; color: #999; margin-bottom: 6px; letter-spacing: .04em; }
  .tq, .native { background: #fff; border: 1px solid #e6e3de; border-radius: 6px;
                 padding: 14px 0; box-sizing: content-box; }
  /* 提椠:每行一个块,cluster 绝对定位在引擎 drawX */
  .tq .ln { position: relative; }
  .tq .ln span { position: absolute; top: 0; font-size: ${FONT_SIZE}px;
                 font-family: "Inter", "Source Han Sans CN", "Noto Sans CJK SC", "PingFang SC", sans-serif;
                 white-space: pre; }
  /* 浏览器默认:交给 <p>,同字号同族,看它自己怎么排 */
  .native p { margin: 0 14px; font-size: ${FONT_SIZE}px; line-height: 1.7;
              text-align: justify;
              font-family: "Inter", "Source Han Sans CN", "Noto Sans CJK SC", "PingFang SC", sans-serif; }
  .note { margin-top: 28px; font-size: 12px; color: #999; max-width: 640px; line-height: 1.7; }
</style>
<h1>提椠 · Web 渲染原型 <span class="sub">ADR 0039 PreBrokenLineDom · 真引擎 + 真 Skia 度量</span></h1>
""".trimIndent()

private val HTML_TAIL = """
<div class="note">
左栏 = 提椠引擎排好行布局(推入推出 / 邻行均摊 / 避头尾 / 中西间距 / 两端对齐 / 破折号
`——`→`⸺` / 引号形选)后,DOM 只把每个 cluster 画在引擎算好的 drawX 上。右栏 = 同宽同字号
交给浏览器默认 `<p>`(即便开了 `text-align: justify`)。同一段正文在两个宽度各排一遍 =
ReflowByRebreak。静态忠实渲染,冻结当前宽度几何。
</div>
""".trimIndent()
