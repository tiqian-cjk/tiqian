package org.tiqian.web

import kotlinx.browser.document
import org.w3c.dom.HTMLElement
import org.w3c.dom.HTMLInputElement
import org.w3c.dom.events.Event

/**
 * ADR 0039 live demo: the real Tiqian engine lays out CJK body text IN THE
 * BROWSER (wasmJs), measuring with `WebCanvasTextShaper` (offscreen measureText)
 * and painting via `DomParagraphRenderer` (`PreBrokenLineDom`). The width slider
 * exercises `ReflowByRebreak` — each change re-runs the engine and re-paints.
 * The production embedding path is [TiqianWeb]. This file is only a demo shell.
 */

private const val FONT_SIZE = 19f

fun main() {
    TiqianWeb.install()
    val root = document.getElementById("app") as? HTMLElement ?: return

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
    stage.setAttribute("data-tiqian-root", "true")
    stage.style.setProperty("background", "#fff")
    stage.style.setProperty("border", "1px solid #e6e3de")
    stage.style.setProperty("border-radius", "6px")
    stage.style.setProperty("padding", "16px")

    fun relayout() {
        val width = slider.value.toFloat()
        label.textContent = "提椠引擎 · 浏览器内布局 · 宽度 ${width.toInt()}px · 字号 ${FONT_SIZE.toInt()}px"
        stage.style.setProperty("width", "${width}px")
        TiqianWeb.destroy(stage)
        while (stage.firstChild != null) stage.removeChild(stage.firstChild!!)
        stage.appendDemoParagraphs()
        TiqianWeb.enhance(
            stage,
            TiqianWeb.EnhanceOptions(
                fontSize = FONT_SIZE,
                lineHeight = FONT_SIZE * 1.75f,
                firstLineIndentIc = 2f,
                fontFamilies = TiqianWeb.FontFamilyOptions(
                    cjk = "\"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
                    latin = "\"Inter\", \"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
                ),
            ),
        )
    }

    slider.addEventListener("input", { _: Event -> relayout() })
    root.appendChild(label)
    root.appendChild(slider)
    root.appendChild(stage)
    relayout()
}

private fun HTMLElement.appendDemoParagraphs() {
    appendParagraph("自然语言是图灵完备的。不存在一个语言中的概念是另一个语言中原则上无法表达的。")
    appendParagraph(
        "有人会说星期八是 the eighth day of the week，有人会说十三月是 the thirteenth " +
            "month of the year——是不是不重要。哪怕你找到了「星期八」和 the eighth day of " +
            "the week 之间的精微差别，只要这个差别是可以在汉语中定义的，它就是能在英语中" +
            "表达的。这本质上是 Church-Turing Thesis。",
    )
    appendHtmlParagraph(
        "真实博客 lowerer 支持 <strong>粗体</strong>、<em>italic</em>、<code>inline code</code>、" +
            "<a href=\"https://www.w3.org/TR/clreq/\">跨行链接动画同步状态演示</a><br>以及源码换行。",
    )
}

private fun HTMLElement.appendParagraph(text: String) {
    val p = document.createElement("p") as HTMLElement
    p.textContent = text
    appendChild(p)
}

private fun HTMLElement.appendHtmlParagraph(html: String) {
    val p = document.createElement("p") as HTMLElement
    p.innerHTML = html
    appendChild(p)
}
