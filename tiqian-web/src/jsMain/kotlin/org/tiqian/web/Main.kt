@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web

import kotlinx.browser.document
import kotlinx.browser.window
import org.w3c.dom.HTMLElement
import org.w3c.dom.HTMLButtonElement
import org.w3c.dom.HTMLInputElement
import org.w3c.dom.events.Event
import kotlin.math.roundToInt

/**
 * ADR 0039 live demo: the real Tiqian engine lays out CJK body text IN THE
 * browser Kotlin/JS runtime, measuring with `WebCanvasTextShaper` (offscreen measureText)
 * and painting via `DomParagraphRenderer` (`PreBrokenLineDom`). The width slider
 * exercises `ReflowByRebreak` — each change re-runs the engine and re-paints.
 * The production embedding path is [TiqianWeb]. This file is only a demo shell.
 */

private const val FONT_SIZE = 19f
private const val BENCHMARK_PARAGRAPH_COUNT = 24
private const val BENCHMARK_WARMUP_COUNT = 1
private const val BENCHMARK_RUN_COUNT = 3

private val demoOptions = TiqianWeb.EnhanceOptions(
    fontSize = FONT_SIZE,
    lineHeight = FONT_SIZE * 1.75f,
    firstLineIndentIc = 2f,
    fontFamilies = TiqianWeb.FontFamilyOptions(
        cjk = "\"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
        latin = "\"Inter\", \"Source Han Sans SC\", \"Noto Sans CJK SC\", \"PingFang SC\", sans-serif",
    ),
)

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

    val benchmarkButton = (document.createElement("button") as HTMLButtonElement).apply {
        textContent = "运行 Kotlin/JS 排版基准"
        style.setProperty("margin", "20px 0 8px")
        style.setProperty("padding", "8px 12px")
    }
    val benchmarkResult = (document.createElement("pre") as HTMLElement).apply {
        id = "benchmark-result"
        textContent = "等待运行：${BENCHMARK_PARAGRAPH_COUNT} 段，预热 $BENCHMARK_WARMUP_COUNT 次，测量 $BENCHMARK_RUN_COUNT 次。"
        style.setProperty("white-space", "pre-wrap")
        style.setProperty("font", "13px/1.5 ui-monospace, monospace")
    }
    val benchmarkStage = (document.createElement("div") as HTMLElement).apply {
        setAttribute("data-tiqian-root", "true")
        setAttribute("data-tq-benchmark", "true")
        style.setProperty("width", "680px")
        style.setProperty("max-width", "calc(100vw - 80px)")
        style.setProperty("max-height", "240px")
        style.setProperty("overflow", "hidden")
        style.setProperty("border", "1px solid #e6e3de")
        style.setProperty("padding", "16px")
        repeat(BENCHMARK_PARAGRAPH_COUNT) { index ->
            appendParagraph(BENCHMARK_PARAGRAPHS[index % BENCHMARK_PARAGRAPHS.size])
        }
    }

    fun relayout() {
        val width = slider.value.toFloat()
        label.textContent = "提椠引擎 · 浏览器内布局 · 宽度 ${width.toInt()}px · 字号 ${FONT_SIZE.toInt()}px"
        stage.style.setProperty("width", "${width}px")
        TiqianWeb.destroy(stage)
        while (stage.firstChild != null) stage.removeChild(stage.firstChild!!)
        stage.appendDemoParagraphs()
        TiqianWeb.enhance(stage, demoOptions)
    }

    slider.addEventListener("input", { _: Event -> relayout() })
    benchmarkButton.addEventListener("click", {
        benchmarkButton.disabled = true
        benchmarkResult.textContent = "运行中……"
        window.setTimeout({
            val durations = mutableListOf<Double>()
            repeat(BENCHMARK_WARMUP_COUNT + BENCHMARK_RUN_COUNT) { run ->
                TiqianWeb.destroy(benchmarkStage)
                val startedAt = window.performance.now()
                val enhancedCount = TiqianWeb.enhance(benchmarkStage, demoOptions)
                val duration = window.performance.now() - startedAt
                check(enhancedCount == BENCHMARK_PARAGRAPH_COUNT) {
                    "benchmark enhanced $enhancedCount / $BENCHMARK_PARAGRAPH_COUNT paragraphs"
                }
                if (run >= BENCHMARK_WARMUP_COUNT) durations += duration
            }
            val sorted = durations.sorted()
            val median = sorted[sorted.size / 2]
            val result = buildString {
                append("段落：$BENCHMARK_PARAGRAPH_COUNT\n")
                append("每轮：${durations.joinToString(", ") { "${it.roundedMillisecond()} ms" }}\n")
                append("中位数：${median.roundedMillisecond()} ms\n")
                append("平均每段：${(median / BENCHMARK_PARAGRAPH_COUNT).roundedMillisecond()} ms")
            }
            benchmarkResult.textContent = result
            benchmarkResult.setAttribute("data-tq-benchmark-median-ms", median.toString())
            benchmarkButton.disabled = false
            null
        }, 0)
    })
    root.appendChild(label)
    root.appendChild(slider)
    root.appendChild(stage)
    root.appendChild(benchmarkButton)
    root.appendChild(benchmarkResult)
    root.appendChild(benchmarkStage)
    relayout()
}

private fun Double.roundedMillisecond(): String = (this * 10.0).roundToInt().div(10.0).toString()

private val BENCHMARK_PARAGRAPHS = listOf(
    "自然语言是图灵完备的。不存在一个语言中的概念是另一个语言中原则上无法表达的。文字进入真实正文以后，标点空间、避头尾、断行和两端对齐必须在同一条布局管线中完成。",
    "有人会说星期八是 the eighth day of the week，有人会说十三月是 the thirteenth month of the year。是不是不重要；只要这个差别可以被定义，它就能够被另一种语言表达。",
    "浏览器负责字体加载、Canvas 测量和 DOM 绘制；提椠负责 source、fallback、shaping、metrics、punctuation、line break、repair、adjustment 与最终 LayoutResult。",
)

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
