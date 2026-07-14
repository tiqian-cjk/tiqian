@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web

import kotlin.JsFun
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.browser.document
import org.w3c.dom.HTMLElement

class TiqianWebCopyTest {
    private val mounted = mutableListOf<HTMLElement>()

    @AfterTest
    fun cleanup() {
        clearSelection()
        for (root in mounted) {
            TiqianWeb.destroy(root)
            root.parentNode?.removeChild(root)
        }
        mounted.clear()
    }

    @Test
    fun singleParagraphClipboardRestoresSourceAndSemanticHtml() {
        val root = mount(
            "<div><p data-tq-rendered='true' " +
                "style='position: relative !important; white-space-collapse: preserve !important'>" +
                "前<strong data-tq-source-semantic='true' data-tq-cjk-emphasis='true' " +
                "style='font-weight: 400 !important; color: red'>" +
                "<span data-tq-geometry='true' style='all: unset !important'>强调</span></strong>" +
                "<a data-tq-source-semantic='true' class='host-link' href='/target/'>" +
                "<span data-tq-geometry='true'>链接</span></a>" +
                "<span data-tq-geometry='true'><span data-tq-src='原文'>显示</span></span>" +
                "<span data-tq-src='&#10;' data-tq-hard-break='true' style='display:none'></span>" +
                "<br data-tq-engine-break='MandatoryBreak'>后" +
                "<span data-tq-copy-ignore='true'>paint-only</span></p></div>",
        )
        TiqianWeb.install()
        val paragraph = root.querySelector("p") as HTMLElement

        assertEquals("前强调链接原文\n后", copiedData(paragraph, "text/plain"))
        val html = copiedData(paragraph, "text/html")

        assertTrue(html.contains("<strong"), html)
        assertTrue(html.contains("color: red"), html)
        assertFalse(html.contains("font-weight"), html)
        assertTrue(html.contains("class=\"host-link\""), html)
        assertTrue(html.contains("href=\"/target/\""), html)
        assertTrue(html.contains("原文"), html)
        assertFalse(html.contains("显示"), html)
        assertFalse(html.contains("paint-only"), html)
        assertFalse(html.contains("data-tq-"), html)
        assertFalse(html.contains("all: unset"), html)
        assertEquals(1, Regex("<br\\b").findAll(html).count(), html)
    }

    @Test
    fun partialRangeKeepsEitherHalfOfAMandatoryBreak() {
        val root = mount(
            "<div><p data-tq-rendered='true'>前" +
                "<span data-tq-src='&#10;' data-tq-hard-break='true' style='display:none'></span>" +
                "<br data-tq-engine-break='MandatoryBreak'>后</p></div>",
        )
        TiqianWeb.install()
        val marker = root.querySelector("[data-tq-hard-break]") as HTMLElement
        val semanticBreak = root.querySelector("br[data-tq-engine-break='MandatoryBreak']") as HTMLElement

        assertEquals("\n", copiedNodeData(marker, "text/plain"))
        assertEquals("\n", copiedNodeData(semanticBreak, "text/plain"))
        assertEquals("<br>", copiedNodeData(marker, "text/html"))
        assertEquals("<br>", copiedNodeData(semanticBreak, "text/html"))
    }

    @Test
    fun crossParagraphClipboardKeepsOnlySourceParagraphBoundaries() {
        val root = mount(
            "<div data-tiqian-root='true' style='width:90px'>" +
                "<p>第一段很长会产生软折行，<strong>重点仍然保留</strong>。</p>" +
                "<p>第二段也会折行，<a class='host-link' href='/target/'>链接仍然保留</a>。</p>" +
                "</div>",
        )
        assertEquals(
            2,
            TiqianWeb.enhance(
                root,
                TiqianWeb.EnhanceOptions(fontSize = 18f, lineHeight = 30f),
            ),
        )

        assertEquals(
            "第一段很长会产生软折行，重点仍然保留。\n第二段也会折行，链接仍然保留。",
            copiedData(root, "text/plain"),
        )
        val html = copiedData(root, "text/html")

        assertEquals(2, Regex("<p(?:\\s|>)").findAll(html).count(), html)
        assertTrue(html.contains("<strong"), html)
        assertTrue(html.contains("class=\"host-link\""), html)
        assertTrue(html.contains("href=\"/target/\""), html)
        assertFalse(html.contains("data-tq-"), html)
        assertFalse(html.contains("tq-line"), html)
        assertFalse(html.contains("data-tq-engine-break"), html)
    }

    @Test
    fun copyOutsideRenderedParagraphRemainsNative() {
        TiqianWeb.install()
        val root = mount("<div><p>普通站点文本不属于提椠。</p></div>")
        val paragraph = root.querySelector("p") as HTMLElement

        assertFalse(copyWasIntercepted(paragraph))
        assertEquals("", copiedData(paragraph, "text/plain"))
        assertEquals("", copiedData(paragraph, "text/html"))
    }

    private fun mount(html: String): HTMLElement {
        val wrapper = document.createElement("div") as HTMLElement
        wrapper.innerHTML = html
        val root = wrapper.firstElementChild as HTMLElement
        document.body!!.appendChild(root)
        mounted += root
        return root
    }
}
@JsFun(
    """(element, type) => {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNodeContents(element);
      selection.removeAllRanges();
      selection.addRange(range);
      const clipboardData = new DataTransfer();
      element.dispatchEvent(new ClipboardEvent("copy", {
        bubbles: true,
        cancelable: true,
        clipboardData
      }));
      const value = clipboardData.getData(type);
      selection.removeAllRanges();
      return value;
    }""",
)
private external fun copiedData(element: HTMLElement, type: String): String
@JsFun(
    """(node, type) => {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNode(node);
      selection.removeAllRanges();
      selection.addRange(range);
      const clipboardData = new DataTransfer();
      node.parentElement.dispatchEvent(new ClipboardEvent("copy", {
        bubbles: true,
        cancelable: true,
        clipboardData
      }));
      const value = clipboardData.getData(type);
      selection.removeAllRanges();
      return value;
    }""",
)
private external fun copiedNodeData(node: HTMLElement, type: String): String
@JsFun(
    """(element) => {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNodeContents(element);
      selection.removeAllRanges();
      selection.addRange(range);
      const event = new ClipboardEvent("copy", {
        bubbles: true,
        cancelable: true,
        clipboardData: new DataTransfer()
      });
      element.dispatchEvent(event);
      selection.removeAllRanges();
      return event.defaultPrevented;
    }""",
)
private external fun copyWasIntercepted(element: HTMLElement): Boolean
@JsFun("() => { const selection = getSelection(); if (selection) selection.removeAllRanges(); }")
private external fun clearSelection()
