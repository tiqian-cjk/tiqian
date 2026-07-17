@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web

import kotlin.JsFun
import kotlinx.browser.document
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.w3c.dom.Element
import org.w3c.dom.HTMLElement
import org.w3c.dom.events.Event
import org.tiqian.shaping.web.WebCjkDashCapability

class TiqianWebEnhancerTest {
    private val mounted = mutableListOf<HTMLElement>()

    @AfterTest
    fun cleanup() {
        for (root in mounted) {
            TiqianWeb.destroy(root)
            root.parentNode?.removeChild(root)
        }
        mounted.clear()
        restoreTestAnimationFrames()
    }

    @Test
    fun exactFontSessionUsesSharedBackendAndCanonicalPreparedDomBridge() {
        installExactFontSessionFixture(failShaping = false)
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="plain" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文正文。</p>
                </div>
                """.trimIndent(),
            )

            val count = TiqianWeb.enhance(root, exactTestOptions())

            assertEquals(1, count)
            val paragraph = root.querySelector("p") as HTMLElement
            assertEquals("true", paragraph.getAttribute("data-tq-canonical-plain"))
            assertEquals("true", paragraph.getAttribute("data-tq-canonical-source"))
            assertEquals("zh-Hans", paragraph.getAttribute("lang"))
            assertNotNull(paragraph.querySelector("[data-tq-exact-rendered]"))
            assertTrue(exactPreparedPlan().contains("\"layoutRevision\":\"tiqian-layout-v2\""))
            assertTrue(exactPreparedPlan().contains("\"height\":"))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun exactFontSessionAlsoShapesSemanticParagraphsBeforeRuntimeDomReplay() {
        installExactFontSessionFixture(failShaping = false)
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="rich" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文<a href="/more">链接</a>正文。</p>
                </div>
                """.trimIndent(),
            )

            val count = TiqianWeb.enhance(root, exactTestOptions())

            assertEquals(1, count)
            val paragraph = root.querySelector("p") as HTMLElement
            assertTrue(exactFontShapeCount() > 0)
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertNotNull(paragraph.querySelector("a[href='/more']"))
            assertNotNull(paragraph.querySelector(".tq-line"))
            assertNull(paragraph.querySelector("[data-tq-exact-rendered]"))
            assertEquals("中文链接正文。", copySelection(paragraph))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun semanticParagraphFallsBackPerUnsupportedFontRunWithoutAbandoningExactLayout() {
        installExactFontSessionFixture(failShaping = false, failFamily = "Fixture Mono")
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 260px">
                  <p data-tq-snapshot-key="rich" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文<code style="font-family: 'Fixture Mono'">code42</code>正文。</p>
                </div>
                """.trimIndent(),
            )

            assertEquals(1, TiqianWeb.enhance(root, exactTestOptions()))

            val paragraph = root.querySelector("p") as HTMLElement
            assertTrue(exactFontShapeCount() > 0)
            assertTrue(exactFontFallbackCount() > 0)
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
            assertNotNull(paragraph.querySelector("code"))
            assertEquals("中文code42正文。", copySelection(paragraph))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun unkeyedRuntimeCompletionKeepsExactDashWhenAnotherRunNeedsBrowserFallback() {
        installExactFontSessionFixture(failShaping = false, failText = "坏")
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 260px">
                  <p style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">坏——正文。</p>
                </div>
                """.trimIndent(),
            )
            val options = exactTestOptions().copy(
                paragraphSelector = "p:not([data-tq-snapshot-key])",
                cjkDashCapability = WebCjkDashCapability(
                    status = "unavailable",
                    detail = "ServerShapingReplayRequired",
                ),
            )

            assertEquals(1, TiqianWeb.enhance(root, options))

            val paragraph = root.querySelector("p") as HTMLElement
            assertTrue(exactFontShapeCount() > 0)
            assertTrue(exactFontFallbackCount() > 0)
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
            assertNotNull(paragraph.querySelector(".tq-line"))
            assertEquals("坏——正文。", copySelection(paragraph))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun unsupportedGlyphFallbackKeepsExactParagraphLineMetrics() {
        installExactFontSessionFixture(failShaping = false, failText = "a")
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 300px">
                  <p data-tq-snapshot-key="exact" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文<a href="/more">链接</a>正文。</p>
                  <p data-tq-snapshot-key="fallback" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">… and <a href="/more">more</a>.</p>
                </div>
                """.trimIndent(),
            )

            assertEquals(2, TiqianWeb.enhance(root, exactTestOptions()))

            val paragraphs = root.querySelectorAll("p")
            val exactParagraph = paragraphs.item(0) as HTMLElement
            val fallbackParagraph = paragraphs.item(1) as HTMLElement
            val exactLine = exactParagraph.querySelector(".tq-line") as HTMLElement
            val fallbackLine = fallbackParagraph.querySelector(".tq-line") as HTMLElement
            assertTrue(exactFontFallbackCount() > 0)
            assertEquals(
                exactLine.style.getPropertyValue("--tq-line-height"),
                fallbackLine.style.getPropertyValue("--tq-line-height"),
            )
            assertEquals(
                exactLine.style.getPropertyValue("--tq-line-baseline-offset"),
                fallbackLine.style.getPropertyValue("--tq-line-baseline-offset"),
            )
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun exactBrowserFallbackCarriesLatinQuoteFeaturesIntoPreparedDomPlan() {
        installExactFontSessionFixture(failShaping = false)
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="plain" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">that’s James’ ’90s</p>
                </div>
                """.trimIndent(),
            )

            val count = TiqianWeb.enhance(root, exactTestOptions())

            assertEquals(1, count)
            assertTrue(
                exactPreparedPlan().contains("\"openTypeFeatures\":[\"pwid\",\"palt\"]"),
                exactPreparedPlan(),
            )
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun browserFontFallbackMeasuresAndReplaysLatinCurlyQuoteFeatures() {
        val source = "that’s；（如 ‘O’, ‘Q’）"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 500px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val featureRuns = paragraph.querySelectorAll(
            "span[data-tq-open-type-features='pwid,palt']",
        )
        assertEquals(3, featureRuns.length, paragraph.innerHTML)
        var quotedCodePoints = 0
        for (index in 0 until featureRuns.length) {
            val run = featureRuns.item(index) as HTMLElement
            quotedCodePoints += run.textContent.orEmpty().count { it in '\u2018'..'\u201D' }
        }
        assertEquals(5, quotedCodePoints, paragraph.innerHTML)
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun browserQuoteContextMatrixReplaysOnlyLatinQuoteFeatures() {
        data class QuoteCase(
            val source: String,
            val html: String = source,
            val proportionalQuoteCount: Int,
        )

        val cases = listOf(
            QuoteCase(source = "中“文”中", proportionalQuoteCount = 0),
            QuoteCase(source = "“Hello”", proportionalQuoteCount = 2),
            QuoteCase(source = "that’s James’ ’90s", proportionalQuoteCount = 3),
            QuoteCase(source = "中文 ‘don’t’", proportionalQuoteCount = 3),
            QuoteCase(source = "他说：“She said ‘hello’.”", proportionalQuoteCount = 2),
            QuoteCase(
                source = "中文 ‘don’t’",
                html = "中文 <strong>‘don’t’</strong>",
                proportionalQuoteCount = 3,
            ),
        )
        val root = mount(
            "<div data-tiqian-root='true' style='width: 520px'>" +
                cases.joinToString(separator = "") { "<p>${it.html}</p>" } +
                "</div>",
        )

        TiqianWeb.install()
        assertEquals(cases.size, TiqianWeb.enhance(root, testOptions()))

        fun assertCases() {
            val paragraphs = root.querySelectorAll("p")
            for ((index, case) in cases.withIndex()) {
                val paragraph = paragraphs.item(index) as HTMLElement
                val featureRuns = paragraph.querySelectorAll(
                    "span[data-tq-open-type-features='pwid,palt']",
                )
                var actualQuoteCount = 0
                for (runIndex in 0 until featureRuns.length) {
                    actualQuoteCount += featureRuns.item(runIndex)!!
                        .textContent
                        .orEmpty()
                        .count { it.isCurlyQuoteForWebTest() }
                }
                assertEquals(case.proportionalQuoteCount, actualQuoteCount, case.source)
                assertEquals(case.source, copySelection(paragraph), case.source)
            }
        }
        assertCases()

        installTestAnimationFrames()
        root.style.width = "180px"
        dispatchRelayout(root)
        flushAllTestAnimationFrames()
        assertCases()
    }

    @Test
    fun unavailableExactFaceFallsBackToTheBrowserPipeline() {
        installExactFontSessionFixture(failShaping = true)
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="plain" style="font-size: 18px; line-height: 30px">中文正文。</p>
                </div>
                """.trimIndent(),
            )

            val count = TiqianWeb.enhance(root, exactTestOptions())

            assertEquals(1, count)
            val paragraph = root.querySelector("p") as HTMLElement
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertEquals("true", paragraph.getAttribute("data-tq-canonical-source"))
            assertNotNull(paragraph.querySelector(".tq-line"))
            assertNull(paragraph.querySelector("[data-tq-exact-rendered]"))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun exactPreparedDomGeometryMismatchDisablesRepeatedExactAttemptsForTheRoot() {
        installExactFontSessionFixture(failShaping = false)
        failExactPreparedDomValidation("fixture-line-drift")
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="plain" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文正文。</p>
                  <p data-tq-snapshot-key="second" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">第二段正文。</p>
                </div>
                """.trimIndent(),
            )
            val paragraph = root.querySelector("p") as HTMLElement

            val count = TiqianWeb.enhance(root, exactTestOptions())

            assertEquals(2, count)
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertNull(paragraph.querySelector("[data-tq-exact-rendered]"))
            assertNotNull(paragraph.querySelector(".tq-line"))
            assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
            assertEquals(1, exactPreparedRenderCount())
            assertEquals(
                "fixture-line-drift",
                root.getAttribute("data-tiqian-exact-layout-fallback"),
            )
            val second = root.querySelector("p[data-tq-snapshot-key='second']") as HTMLElement
            assertNull(second.querySelector("[data-tq-exact-rendered]"))
            assertNotNull(second.querySelector(".tq-line"))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun layoutOptionOverrideCannotReuseTheSnapshotExactSession() {
        installExactFontSessionFixture(failShaping = false)
        try {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <p data-tq-snapshot-key="plain" style="font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px">中文正文。</p>
                </div>
                """.trimIndent(),
            )

            val count = TiqianWeb.enhance(root, exactTestOptions().copy(fontSize = 24f))

            assertEquals(1, count)
            val paragraph = root.querySelector("p") as HTMLElement
            assertNull(paragraph.getAttribute("data-tq-canonical-plain"))
            assertNull(paragraph.querySelector("[data-tq-exact-rendered]"))
            assertNotNull(paragraph.querySelector(".tq-line"))
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun plainRuntimeFlowUsesTextNodesUntilGeometryActuallyNeedsASpan() {
        val source = "很长时间没写"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals(source, directTextContent(paragraph), paragraph.innerHTML)
        val selectionEnd = assertNotNull(paragraph.querySelector("span[data-tq-selection-end='true']"))
        assertEquals("\u200B", selectionEnd.textContent)
        assertEquals("true", selectionEnd.getAttribute("data-tq-copy-ignore"))
        assertEquals("true", selectionEnd.getAttribute("aria-hidden"))
        assertEquals(
            0,
            paragraph.querySelectorAll(
                "span[data-tq-geometry]:not(.tq-line):not([data-tq-line-end-sentinel])",
            ).length,
        )
        val generated = paragraph.querySelectorAll("[data-tq-geometry][style]")
        for (index in 0 until generated.length) {
            val style = (generated.item(index) as? HTMLElement)?.getAttribute("style").orEmpty()
            assertFalse(style.contains("all:"), style)
            assertFalse(style.contains("text-spacing-trim:"), style)
        }
        assertFalse(paragraph.getAttribute("style").orEmpty().contains("white-space"))
        assertFalse(paragraph.getAttribute("style").orEmpty().contains("text-autospace"))
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun enhancesSupportedMarkdownInlineParagraphInPlace() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p>中文<strong>粗体</strong><em>italic</em><code>code</code><a class="host-link" href="/target/">链接</a><br>换行。</p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as? HTMLElement
        assertNotNull(paragraph)
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNull(root.querySelector(".tq-paragraph"))
        assertEquals("中文粗体italiccode链接\n换行。", copySelection(paragraph))
        assertNotNull(paragraph.querySelector("strong"))
        assertNotNull(paragraph.querySelector("em"))
        assertNotNull(paragraph.querySelector("code"))
        assertNotNull(paragraph.querySelector("a.host-link[href='/target/']"))
        assertTrue(paragraph.style.display.isEmpty())
        assertNull(paragraph.getAttribute("data-tq-copy-ignore"))
    }

    @Test
    fun keepsInlineCodeParagraphNativeWithoutKnownMonospaceFontFace() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p>中文<code style='font-family: "MissingFixtureMono", monospace'>code</code>正文。</p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(
            root,
            TiqianWeb.EnhanceOptions(fontSize = 18f, lineHeight = 30f),
        )

        assertEquals(0, count)
        val paragraph = root.querySelector("p") as HTMLElement
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "InlineCodeFontFaceUnavailable",
            paragraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertTrue(paragraph.textContent?.contains("中文code正文。") == true)
    }

    @Test
    fun longInlineCodeTokenUsesRuntimeEmergencyBreaksWithoutOverflow() {
        val token = "eeeeeeeebad9a5e4b24e74cb55e829fb82c8244c0a5a3bae585179575af33bb0"
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p style="font-size: 18px; line-height: 30px">域名是 <code style="padding-left: 4px; padding-right: 4px">$token</code>，它不会消失。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNotNull(paragraph.querySelector("code"))
        assertTrue(paragraph.querySelectorAll(".tq-line").length > 1)
        assertTrue(paragraph.scrollWidth <= paragraph.clientWidth + 1)
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals("域名是 $token，它不会消失。", copySelection(paragraph))
    }

    @Test
    fun enhancesLeafListItemsWithoutReplacingListContainers() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <ul>
                <li id="outer">外层<ul><li id="inner">内层<strong>正文</strong>。</li></ul></li>
                <li id="plain">普通列表项。</li>
              </ul>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(2, count)
        val outer = root.querySelector("#outer") as HTMLElement
        val inner = root.querySelector("#inner") as HTMLElement
        val plain = root.querySelector("#plain") as HTMLElement
        val outerList = root.querySelector("ul") as HTMLElement
        val innerList = outer.querySelector(":scope > ul") as HTMLElement
        assertNull(outer.getAttribute("data-tq-rendered"))
        assertNotNull(outer.querySelector(":scope > ul"))
        assertNull(outerList.getAttribute("data-tq-list-layout"))
        assertNull(innerList.getAttribute("data-tq-list-layout"))
        assertEquals("true", inner.getAttribute("data-tq-rendered"))
        assertEquals("true", plain.getAttribute("data-tq-rendered"))
        assertNotNull(inner.querySelector("strong"))
        assertEquals("list-item", computedStyleValue(inner, "display"))
        assertEquals("内层正文。", copySelection(inner))
    }

    @Test
    fun progressiveEnhancementDoesNotMeasureSkippedAutoSizedListContainers() {
        for (display in listOf("flex", "grid")) {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 220px">
                  <ol>
                    <li id="outer" style="display: $display">
                      <p id="child">脚注正文应由客户端接管，而且接管前后不能改变 auto-sized item 的宿主宽度。</p>
                      <a href="#note">↩</a>
                    </li>
                  </ol>
                </div>
                """.trimIndent(),
            )
            val outer = root.querySelector("#outer") as HTMLElement
            val child = root.querySelector("#child") as HTMLElement
            val sourceWidth = elementWidth(child)
            var stale = false
            root.addEventListener("tiqian:ready", { event ->
                stale = relayoutEventIsStale(event)
            })
            installTestAnimationFrames()

            TiqianWeb.enhanceProgressively(root, testOptions())
            flushAllTestAnimationFrames()

            assertNull(outer.getAttribute("data-tq-rendered"))
            assertEquals("true", child.getAttribute("data-tq-rendered"))
            assertEquals(sourceWidth, elementWidth(child), 0.5)
            assertEquals("true", child.getAttribute("data-tq-host-inline-size"))
            assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
            assertFalse(stale)

            TiqianWeb.destroy(root)
            assertNull(child.getAttribute("data-tq-host-inline-size"))
            assertEquals(sourceWidth, elementWidth(child), 0.5)
        }
    }

    @Test
    fun progressiveEnhancementPreservesWidthDerivedThroughShrinkToFitAncestor() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 576px">
              <figure style="display: inline-block; margin: 0; max-width: 100%">
                <div style="width: 500px"></div>
                <figcaption>
                  <p style="margin: 0">ContentSizedParagraphWithoutNativeBreakOpportunitiesMustKeepTheHostMeasureWhileItsSourceNodesAreInCustody</p>
                </figcaption>
              </figure>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val sourceWidth = elementWidth(paragraph)
        var stale = false
        root.addEventListener("tiqian:ready", { event ->
            stale = relayoutEventIsStale(event)
        })
        installTestAnimationFrames()

        TiqianWeb.enhanceProgressively(root, testOptions())
        flushAllTestAnimationFrames()

        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertEquals("true", paragraph.getAttribute("data-tq-host-inline-size"))
        assertEquals(sourceWidth, elementWidth(paragraph), 0.5)
        assertFalse(stale)

        TiqianWeb.destroy(root)
        assertNull(paragraph.getAttribute("data-tq-host-inline-size"))
        assertEquals(sourceWidth, elementWidth(paragraph), 0.5)
    }

    @Test
    fun orderedListKeepsNativeMarkersOnATwoIcBodyIndent() {
        val tenthSource = "第十项正文足够长，换行以后仍然沿着同一正文列继续排列。"
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 230px; font-size: 18px; line-height: 30px">
              <style>
                ol { box-sizing: border-box; padding-inline-start: 36px; margin-inline: 0; }
              </style>
              <p id="body">正文足够长，第一行应当填满与列表相同的版心网格，然后继续换行。</p>
              <ol start="8">
                <li id="eight">第八项。</li>
                <li id="nine">第九项。</li>
                <li id="ten">$tenthSource</li>
              </ol>
            </div>
            """.trimIndent(),
        )

        assertEquals(4, TiqianWeb.enhance(root, testOptions()))

        val list = root.querySelector("ol") as HTMLElement
        val body = root.querySelector("#body") as HTMLElement
        val tenth = root.querySelector("#ten") as HTMLElement
        assertNull(tenth.querySelector(":scope > [data-tq-list-marker]"))
        assertNull(list.getAttribute("data-tq-list-layout"))
        assertNull(list.getAttribute("data-tq-list-gutter-ic"))
        assertNull(list.getAttribute("role"))
        assertFalse(tenth.textContent.orEmpty().contains("10."))
        assertEquals("36px", computedStyleValue(list, "padding-inline-start"))
        assertEquals("list-item", computedStyleValue(tenth, "display"))

        val proseLine = body.querySelector("[data-tq-line-width]") as HTMLElement
        val listLine = tenth.querySelector(":scope > [data-tq-line-width]") as HTMLElement
        val proseMeasure = proseLine.getAttribute("data-tq-line-width")!!.toDouble()
        val listMeasure = listLine.getAttribute("data-tq-line-width")!!.toDouble()
        assertTrue(kotlin.math.abs((36.0 + listMeasure) - proseMeasure) < 0.5)
        assertEquals(tenthSource, copySelection(tenth))

        val wideLines = renderedLineSignature(tenth)
        TiqianWeb.install()
        installTestAnimationFrames()
        root.style.width = "176px"
        dispatchRelayout(root)
        flushAllTestAnimationFrames()
        assertNotEquals(wideLines, renderedLineSignature(tenth))
        assertNull(tenth.querySelector(":scope > [data-tq-list-marker]"))
        assertEquals(tenthSource, copySelection(tenth))

        TiqianWeb.destroy(root)
        assertNull(list.getAttribute("data-tq-list-layout"))
        assertNull(list.getAttribute("data-tq-list-gutter-ic"))
        assertNull(list.getAttribute("role"))
        assertNull(tenth.getAttribute("data-tq-list-item"))
        assertNull(tenth.querySelector("[data-tq-list-marker]"))
        assertEquals(tenthSource, tenth.textContent)
    }

    @Test
    fun unorderedListUsesTwoIcNativeMarkerColumnAndNoParagraphIndent() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 216px; font-size: 18px; line-height: 30px">
              <style>
                ul { box-sizing: border-box; padding-inline-start: 36px; margin-inline: 0; }
              </style>
              <p>普通正文保留显式的两字段首缩进，用于证明列表没有继承它。</p>
              <ul><li id="bullet">项目正文不会再叠加段首缩进，续行只服从共享标记列。</li></ul>
            </div>
            """.trimIndent(),
        )
        val options = TiqianWeb.EnhanceOptions(
            fontSize = 18f,
            lineHeight = 30f,
            firstLineIndentIc = 2f,
        )

        assertEquals(2, TiqianWeb.enhance(root, options))

        val list = root.querySelector("ul") as HTMLElement
        val paragraph = root.querySelector("p") as HTMLElement
        val item = root.querySelector("#bullet") as HTMLElement
        val paragraphLine = paragraph.querySelector(":scope > .tq-line") as HTMLElement
        val itemLine = item.querySelector(":scope > .tq-line") as HTMLElement
        assertNull(list.getAttribute("data-tq-list-gutter-ic"))
        assertNull(item.querySelector(":scope > [data-tq-list-marker]"))
        assertEquals("36px", computedStyleValue(list, "padding-inline-start"))
        assertEquals("list-item", computedStyleValue(item, "display"))
        assertEquals("36px", paragraphLine.style.getPropertyValue("margin-left"))
        assertTrue(itemLine.style.getPropertyValue("margin-left").isEmpty())
    }

    @Test
    fun listItemPaddingIsExcludedFromTheAvailableLineMeasure() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 216px; font-size: 18px; line-height: 30px">
              <style>
                ul { box-sizing: border-box; padding-inline-start: 36px; margin-inline: 0; }
                li { box-sizing: border-box; padding-inline-start: 7px; }
              </style>
              <ul><li id="padded">列表项自己的 padding 不能被正文版心重复占用。</li></ul>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val item = root.querySelector("#padded") as HTMLElement
        val line = item.querySelector(":scope > [data-tq-line-width]") as HTMLElement
        val lineMeasure = line.getAttribute("data-tq-line-width")!!.toDouble()
        val contentWidth = item.clientWidth -
            cssPx(computedStyleValue(item, "padding-left")) -
            cssPx(computedStyleValue(item, "padding-right"))
        assertTrue(lineMeasure <= contentWidth + 0.5)
        assertTrue(
            kotlin.math.abs(lineMeasure - 162.0) < 0.5,
            "173px content box should expose nine 18px cells, was $lineMeasure",
        )
        assertEquals("列表项自己的 padding 不能被正文版心重复占用。", copySelection(item))
    }

    @Test
    fun canonicalPreparedParagraphCanFallBackIntoRuntimeWithoutTreatingGeometryAsHostObjects() {
        val source = "甲’乙\n丙"
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 180px; font-size: 18px; line-height: 30px">
              <p data-tq-rendered="true" data-tq-canonical-plain="true" data-tq-canonical-source="true"><span data-tq-geometry="true">甲</span><span data-tq-src="’" data-tq-geometry="true">＇</span><br data-tq-engine-break="AutoWrap"><span data-tq-geometry="true">乙</span><span data-tq-src="&#10;" data-tq-hard-break="true"></span><br data-tq-engine-break="MandatoryBreak"><span data-tq-geometry="true">丙</span></p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun canonicalPreparedFallbackSamplesHostLineHeightBeforeRuntimeLowering() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 180px">
              <style>
                #prepared-fallback { font-size: 18px; line-height: 30px; white-space: normal; }
                #prepared-fallback[data-tq-rendered="true"][data-tq-canonical-plain="true"] {
                  line-height: 0 !important;
                  white-space: pre !important;
                }
              </style>
              <p id="prepared-fallback" data-tq-rendered="true" data-tq-canonical-plain="true" data-tq-canonical-source="true"><span data-tq-geometry="true">第一行正文</span><br data-tq-engine-break="AutoWrap"><span data-tq-geometry="true">第二行正文</span></p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root))

        val paragraph = root.querySelector("#prepared-fallback") as HTMLElement
        val line = paragraph.querySelector(":scope > .tq-line") as HTMLElement
        assertEquals(30f, cssPx(line.style.getPropertyValue("--tq-line-height")))
        assertEquals("第一行正文第二行正文", copySelection(paragraph))
    }

    @Test
    fun variationSelectorStaysWithItsVisibleBaseDuringWebShaping() {
        val source = "返回正文 ↩︎"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 220px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        val paragraph = root.querySelector("p") as HTMLElement
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun leavesStrongAsBoldByDefault() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p style="font-weight: 430">前<strong style="font-weight: 700">强调，CSharp</strong>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val strong = assertNotNull(paragraph.querySelector("strong") as? HTMLElement)
        assertNull(strong.getAttribute("data-tq-cjk-emphasis"))
        assertEquals(0, paragraph.querySelectorAll("circle").length)
        assertEquals("700", computedStyleValue(strong, "font-weight"))
        assertEquals("前强调，CSharp后。", copySelection(paragraph))
    }

    @Test
    fun jsOptionsCanExplicitlyMapStrongToEmphasisMarks() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p style="font-size: 18px; line-height: 30px">前<strong>强调</strong>后。</p>
            </div>
            """.trimIndent(),
        )
        TiqianWeb.install()

        dispatchEnhanceWithStrongAsEmphasisMarks(root)

        val paragraph = root.querySelector("p") as HTMLElement
        assertNotNull(paragraph.querySelector("strong[data-tq-cjk-emphasis]"))
        assertEquals(2, paragraph.querySelectorAll("circle").length)
    }

    @Test
    fun explicitlyRendersOnlyCjkContentInStrongAsEmphasisMarks() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p style="font-weight: 430">前<strong style="font-weight: 700; color: rgb(1, 2, 3)">强调，CSharp 42🙂</strong>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(
            1,
            TiqianWeb.enhance(
                root,
                testOptions().copy(strongAsEmphasisMarks = true),
            ),
        )

        val paragraph = root.querySelector("p") as HTMLElement
        val strong = paragraph.querySelector("strong[data-tq-cjk-emphasis]") as? HTMLElement
        assertNotNull(strong)
        assertEquals("430", computedStyleValue(strong, "font-weight"))
        assertEquals(2, paragraph.querySelectorAll("circle").length)
        val overlay = assertNotNull(paragraph.querySelector("svg[data-tq-geometry='true']"))
        val firstDot = assertNotNull(paragraph.querySelector("circle"))
        assertEquals("rgb(1, 2, 3)", firstDot.getAttribute("fill"))
        assertFalse(overlay.getAttribute("style")?.contains("position:absolute") == true)
        assertTrue(overlay.getAttribute("style")?.startsWith("--tq-overlay-width:") == true)
        assertEquals("--tq-decoration-color:rgb(1, 2, 3)", firstDot.getAttribute("style"))

        val descendants = strong.querySelectorAll("span")
        var cjkRun: HTMLElement? = null
        var latinRun: HTMLElement? = null
        for (index in 0 until descendants.length) {
            val element = descendants.item(index) as? HTMLElement ?: continue
            val content = element.textContent ?: continue
            if (content.contains("强调")) cjkRun = element
            if (content.contains("CSharp")) latinRun = element
        }
        assertNotNull(cjkRun)
        assertNotNull(latinRun)
        assertEquals("430", computedStyleValue(cjkRun, "font-weight"))
        assertEquals("700", computedStyleValue(latinRun, "font-weight"))
        assertEquals("前强调，CSharp 42🙂后。", copySelection(paragraph))
    }

    @Test
    fun exposesExplicitEmphasisDotGap() {
        fun enhanceWithGap(gap: Float): Float {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 320px">
                  <p style="font-size: 18px">前<strong>强调</strong>后。</p>
                </div>
                """.trimIndent(),
            )
            assertEquals(
                1,
                TiqianWeb.enhance(
                    root,
                    testOptions().copy(
                        emphasisDotGapEm = gap,
                        strongAsEmphasisMarks = true,
                    ),
                ),
            )
            return root.querySelector("circle")!!.getAttribute("cy")!!.toFloat()
        }

        val defaultCenter = enhanceWithGap(0.10f)
        val adjustedCenter = enhanceWithGap(0.25f)
        assertEquals(18f * 0.15f, adjustedCenter - defaultCenter, 0.01f)
    }

    @Test
    fun enhanceEventWithoutOptionsUsesComputedParagraphMetrics() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p style="font-size: 18px; line-height: 32px">无配置事件也必须继承宿主字号。</p>
            </div>
            """.trimIndent(),
        )
        TiqianWeb.install()

        dispatchEnhanceWithoutOptions(root)

        val paragraph = root.querySelector("p") as HTMLElement
        val line = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(line)
        assertEquals(32f, cssPx(line.style.getPropertyValue("--tq-line-height")))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun typographyRefreshRelowersCurrentHostMetrics() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p style="font-size: 16px; line-height: 28px; font-weight: 400">宿主样式加载后需要重新度量。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root))
        var paragraph = root.querySelector("p") as HTMLElement
        assertEquals(
            28f,
            cssPx(
                (paragraph.querySelector(".tq-line") as HTMLElement)
                    .style.getPropertyValue("--tq-line-height"),
            ),
        )

        paragraph.style.fontSize = "18px"
        paragraph.style.lineHeight = "32px"
        paragraph.style.fontWeight = "460"
        TiqianWeb.refresh(root, progressively = false)

        paragraph = root.querySelector("p") as HTMLElement
        val line = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(line)
        assertEquals(32f, cssPx(line.style.getPropertyValue("--tq-line-height")))
        assertEquals("18px", computedStyleValue(paragraph, "font-size"))
        assertEquals("460", computedStyleValue(paragraph, "font-weight"))
    }

    @Test
    fun enhanceAllFindsCustomElementRoots() {
        val root = mount(
            """
            <tiqian-prose style="display: block; width: 220px">
              <p>命令式 API 也必须找到 custom element。</p>
            </tiqian-prose>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhanceAll(testOptions()))
        assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
        assertNotNull(root.querySelector(".tq-line"))
    }

    @Test
    fun nestedRootsOwnOnlyTheirDirectParagraphScope() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p class="outer">外层正文。</p>
              <div data-tiqian-root="true"><p class="inner">内层正文。</p></div>
            </div>
            """.trimIndent(),
        )

        assertEquals(2, TiqianWeb.enhanceAll(testOptions()))

        val innerRoot = root.querySelector("[data-tiqian-root]") as? HTMLElement
        assertNotNull(innerRoot)
        assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
        assertEquals("1", innerRoot.getAttribute("data-tiqian-enhanced-count"))
        assertEquals(1, root.querySelectorAll("p.outer[data-tq-rendered='true']").length)
        assertEquals(1, root.querySelectorAll("p.inner[data-tq-rendered='true']").length)
        TiqianWeb.destroy(innerRoot)
    }

    @Test
    fun reportsStatefulInlineObjectAndKeepsOriginalParagraph() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p>中文<button style="display: inline-block">unsupported</button>。</p>
            </div>
            """.trimIndent(),
        )
        val original = (root.querySelector("p") as HTMLElement).innerHTML

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(0, count)
        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals(original, paragraph.innerHTML)
        assertEquals("UnsupportedStatefulInlineObject", paragraph.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun lowersMeasurableUnknownInlineElementsAsOpaqueObjects() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 260px">
              <p style="font-size: 18px; line-height: 30px">前<span class="badge" style="display:inline-block;width:42px;height:20px">badge</span><img class="icon" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'/%3E" alt="icon" width="20" height="20" style="display:inline-block;padding-bottom:4px"><svg class="raw-svg" width="18" height="20" viewBox="0 0 18 20" style="display:inline-block"><circle cx="9" cy="10" r="8"></circle></svg>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals(3, paragraph.querySelectorAll("[data-tq-inline-object]").length)
        assertNotNull(paragraph.querySelector("span.badge[data-tq-inline-object]"))
        assertNotNull(paragraph.querySelector("img.icon[data-tq-inline-object][alt='icon']"))
        assertNotNull(paragraph.querySelector("svg.raw-svg[data-tq-inline-object] circle"))
        assertEquals("前badge后。", copySelection(paragraph))
        assertTrue(paragraph.textContent?.contains('\uFFFC') == false)
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))

        val objectLine = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(objectLine)
        assertTrue(cssPx(objectLine.style.getPropertyValue("--tq-line-height")) >= 30f)
    }

    @Test
    fun enhancesParagraphWhoseOnlyContentIsAnInlineObject() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p><svg class="only-object" width="24" height="20" viewBox="0 0 24 20" style="display:inline-block"><circle cx="12" cy="10" r="8"></circle></svg></p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNotNull(paragraph.querySelector("svg.only-object[data-tq-inline-object] circle"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun lowersTextualInlineElementsByFormattingContextInsteadOfTagWhitelist() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p>中<span class="host-span">span</span><mark>mark</mark><del>delete</del><spoiler>秘密</spoiler>文。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNotNull(paragraph.querySelector("span.host-span[data-tq-source-semantic]"))
        assertNotNull(paragraph.querySelector("mark[data-tq-source-semantic]"))
        assertNotNull(paragraph.querySelector("del[data-tq-source-semantic]"))
        assertNotNull(paragraph.querySelector("spoiler[data-tq-source-semantic]"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun unverifiedCanvasEllipsisKeepsSourceDisplayAndCopyText() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p>中文……中文。</p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as HTMLElement
        assertTrue(paragraph.textContent?.contains("……") == true)
        assertTrue(paragraph.textContent?.contains("⋯⋯") == false)
        assertEquals("中文……中文。", copySelection(paragraph))
    }

    @Test
    fun keepsDashParagraphNativeWithoutAVerifiableFontSource() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 420px">
              <p style="font-family: Arial, sans-serif">中文——中文。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(0, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertTrue(paragraph.textContent?.contains("中文——中文。") == true)
        assertTrue(paragraph.textContent?.contains('⸺') == false)
        assertEquals("NoConformingCjkDashGlyph", paragraph.getAttribute("data-tiqian-capability-issue"))
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals("中文——中文。", copySelection(paragraph))
    }

    @Test
    fun expandsCjkContextCurlyQuotesButKeepsLatinPairsProportional() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 600px">
              <p style="font-family: Arial, sans-serif; font-size: 20px; line-height: 32px"><span class="cjk-quotes">中“文”中</span></p>
              <p style="font-family: Arial, sans-serif; font-size: 20px; line-height: 32px"><span class="latin-quotes">A“A”A</span></p>
            </div>
            """.trimIndent(),
        )

        assertEquals(2, TiqianWeb.enhance(root))

        val cjk = root.querySelector(".cjk-quotes[data-tq-source-semantic]") as? HTMLElement
        val latin = root.querySelector(".latin-quotes[data-tq-source-semantic]") as? HTMLElement
        assertNotNull(cjk)
        assertNotNull(latin)
        // Three Han glyphs + two context-CJK quote boxes = 5em. The same
        // source quote codepoints in Latin prose retain the face's narrow
        // proportional advances instead of being globally widened.
        assertEquals(100.0, elementWidth(cjk), 1.0)
        assertTrue(elementWidth(latin) < 80.0, "Latin quote pair was widened: ${elementWidth(latin)}px")
        assertEquals("中“文”中", copySelection(cjk))
        assertEquals("A“A”A", copySelection(latin))
    }

    @Test
    fun copyKeepsHardBreakAndSourceTextButOmitsSoftWraps() {
        val source = "第一行中文需要自动换行。第二段内容继续占满宽度。"
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 120px">
              <p>$source<br>显式换行之后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        val paragraph = root.querySelector("p") as HTMLElement
        assertTrue(paragraph.querySelectorAll(".tq-line").length > 2)

        val visualBreaks = paragraph.querySelectorAll(
            "br[data-tq-engine-break]:not([data-tq-engine-break='MandatoryBreak'])",
        )
        assertTrue(visualBreaks.length > 0)
        for (index in 0 until visualBreaks.length) {
            val visualBreak = visualBreaks.item(index) as HTMLElement
            assertEquals("true", visualBreak.getAttribute("aria-hidden"))
            assertEquals("true", visualBreak.getAttribute("data-tq-copy-ignore"))
        }
        val sourceBreak = paragraph.querySelector("br[data-tq-engine-break='MandatoryBreak']") as HTMLElement
        assertNull(sourceBreak.getAttribute("aria-hidden"))
        assertNull(sourceBreak.getAttribute("data-tq-copy-ignore"))

        assertEquals("$source\n显式换行之后。", copySelection(paragraph))
    }

    @Test
    fun collapsesHostFormattingWhitespaceAndKeepsReflowDeterministic() {
        val expected = "第一句。 第二句。 第三句。\n第四句。"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 220px'>" +
                "<p>第一句。\n<strong>第二句。\n第三句。</strong><br>\n第四句。</p>" +
                "</div>",
        )
        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals(expected, nativeInnerText(paragraph))

        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals(expected, copySelection(paragraph))
        assertEquals(1, paragraph.querySelectorAll("[data-tq-hard-break]").length)
        assertEquals(0, emptyRenderedLineCount(paragraph))
        assertNotNull(paragraph.querySelector("strong[data-tq-source-semantic]"))

        val initial = renderedLineSignature(paragraph)
        installTestAnimationFrames()
        root.style.width = "120px"
        dispatchRelayout(root)
        assertEquals(initial, renderedLineSignature(paragraph), "relayout must wait for an animation frame")
        assertEquals(1, pendingTestAnimationFrameCount())
        flushAllTestAnimationFrames()
        val narrow = renderedLineSignature(paragraph)
        assertNotEquals(initial, narrow, "narrow width must exercise a real reflow")

        root.style.width = "220px"
        dispatchRelayout(root)
        flushAllTestAnimationFrames()
        assertEquals(initial, renderedLineSignature(paragraph))
        assertEquals(expected, copySelection(paragraph))
        assertEquals(0, emptyRenderedLineCount(paragraph))
    }

    @Test
    fun normalizesPreservedCrLfToOneSegmentBreak() {
        val root = mount(
            "<div data-tiqian-root='true' style='width: 220px'><p style='white-space: pre-wrap'></p></div>",
        )
        val paragraph = root.querySelector("p") as HTMLElement
        paragraph.textContent = "前\r\n后"

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        assertEquals("前\n后", copySelection(paragraph))
        assertEquals(1, paragraph.querySelectorAll("[data-tq-hard-break]").length)
        assertEquals(0, emptyRenderedLineCount(paragraph))
    }

    @Test
    fun widthDependentCapabilityRetryRestartsProgressivelyFromNativeSource() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 520px">
              <p class="clone"><span style="box-decoration-break: clone; -webkit-box-decoration-break: clone; padding: 0 6px">跨行复制盒模型只在窄行失去保真能力</span></p>
              <p class="plain">普通段落在 capability retry 时不能跨帧暴露原生正文。</p>
            </div>
            """.trimIndent(),
        )
        val cloneParagraph = root.querySelector("p.clone") as HTMLElement
        val plainParagraph = root.querySelector("p.plain") as HTMLElement
        val originalHtml = cloneParagraph.innerHTML
        var relayoutReadyCount = 0
        root.addEventListener("tiqian:relayout-ready", { relayoutReadyCount += 1 })
        TiqianWeb.install()

        assertEquals(2, TiqianWeb.enhance(root, testOptions()))
        assertEquals("true", cloneParagraph.getAttribute("data-tq-rendered"))
        assertEquals("true", plainParagraph.getAttribute("data-tq-rendered"))

        installTestAnimationFrames()
        root.style.width = "90px"
        dispatchRelayout(root)
        flushAllTestAnimationFrames()

        assertEquals(originalHtml, cloneParagraph.innerHTML)
        assertNull(cloneParagraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "InlineCloneDecorationBreakUnsupported",
            cloneParagraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertEquals("true", plainParagraph.getAttribute("data-tq-rendered"))
        assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
        assertEquals(1, relayoutReadyCount)
        val narrowRenderedChild = assertNotNull(plainParagraph.firstChild)

        root.style.width = "520px"
        dispatchRelayout(root)

        assertEquals(1, pendingTestAnimationFrameCount())
        assertEquals(1, relayoutReadyCount)
        assertNull(cloneParagraph.getAttribute("data-tq-rendered"))
        assertNull(plainParagraph.getAttribute("data-tq-rendered"))
        assertEquals(originalHtml, cloneParagraph.innerHTML)
        assertFalse(plainParagraph.firstChild === narrowRenderedChild)
        assertEquals("0", root.getAttribute("data-tiqian-enhanced-count"))

        flushAllTestAnimationFrames()

        assertEquals(2, relayoutReadyCount)
        assertEquals("true", cloneParagraph.getAttribute("data-tq-rendered"))
        assertEquals("true", plainParagraph.getAttribute("data-tq-rendered"))
        assertNull(cloneParagraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals("2", root.getAttribute("data-tiqian-enhanced-count"))
    }

    @Test
    fun stableCapabilityIssueStaysNativeWhileEnhancedParagraphsRelayoutNormally() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p class="issue" style="font-size: 0px">零 advance 是稳定 capability issue。</p>
              <p class="plain" style="font-size: 18px; line-height: 30px">普通正文仍应走 off-DOM 响应式重排。</p>
            </div>
            """.trimIndent(),
        )
        val issueParagraph = root.querySelector("p.issue") as HTMLElement
        val plainParagraph = root.querySelector("p.plain") as HTMLElement
        val issueSourceChild = assertNotNull(issueParagraph.firstChild)
        TiqianWeb.install()

        assertEquals(1, TiqianWeb.enhance(root))
        assertEquals("InvalidWebShapingAdvance", issueParagraph.getAttribute("data-tiqian-capability-issue"))
        val renderedChild = assertNotNull(plainParagraph.firstChild)
        val initial = renderedLineSignature(plainParagraph)
        var relayoutReadyCount = 0
        root.addEventListener("tiqian:relayout-ready", { relayoutReadyCount += 1 })

        installTestAnimationFrames()
        root.style.width = "120px"
        dispatchRelayout(root)

        assertTrue(plainParagraph.firstChild === renderedChild, "relayout preparation must keep rendered DOM live")
        assertTrue(issueParagraph.firstChild === issueSourceChild)
        assertEquals(1, pendingTestAnimationFrameCount())

        flushAllTestAnimationFrames()

        assertFalse(plainParagraph.firstChild === renderedChild)
        assertNotEquals(initial, renderedLineSignature(plainParagraph))
        assertTrue(issueParagraph.firstChild === issueSourceChild)
        assertNull(issueParagraph.getAttribute("data-tq-rendered"))
        assertEquals("InvalidWebShapingAdvance", issueParagraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
        assertEquals(1, relayoutReadyCount)
    }

    @Test
    fun inlineShapingFeatureThatLayoutResultCannotModelStaysNative() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p>阅读 <span style="font-feature-settings: 'hwid'; font-variant-east-asian: proportional-width">Font size</span> 以了解更多。</p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML

        assertEquals(0, TiqianWeb.enhance(root, testOptions()))
        assertEquals(originalHtml, paragraph.innerHTML)
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "UnsupportedInlineShapingStyle",
            paragraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertEquals(
            "span:font-feature-settings",
            paragraph.getAttribute("data-tiqian-capability-detail"),
        )
    }

    @Test
    fun generatedInlineContentThatLayoutResultCannotModelStaysNative() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <style>
                .generated-footnote::before { content: "["; }
                .generated-footnote::after { content: "]"; }
                .absolute-decoration::before { content: "•"; position: absolute; }
              </style>
              <p>正文<a class="generated-footnote" href="#note">1</a>继续。</p>
              <p>正文<span class="absolute-decoration">装饰</span>继续。</p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals(originalHtml, paragraph.innerHTML)
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "UnsupportedGeneratedInlineContent",
            paragraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertTrue(
            paragraph.getAttribute("data-tiqian-capability-detail")
                ?.startsWith("a::before:") == true,
        )
        val decorated = root.querySelector("p:last-of-type") as HTMLElement
        assertEquals("true", decorated.getAttribute("data-tq-rendered"))
        assertNull(decorated.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun zeroWidthSpaceSoftBreakEnhancesAndCopiesSourceFaithfully() {
        val source = "A.\u200B.\u200B.Complete？AaFont？"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 120px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertTrue(paragraph.querySelectorAll(".tq-line").length > 1)
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun copyOmitsEngineOwnedHyphenGlyphs() {
        val source = "中Network"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 64px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val hyphen = paragraph.querySelector(
            "span[data-tq-copy-ignore][aria-hidden='true']:not(.tq-line)",
        )
        assertNotNull(hyphen)
        assertEquals("-", hyphen.textContent)
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun preservesOneNativeLinkAcrossEngineOwnedLines() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 120px">
              <p><a class="host-link" href="/target/" target="_self" rel="author" title="Host title" style="color: rgb(10, 11, 12); text-decoration-style: dotted; transition: text-decoration-color 200ms">一段足够长而且确定会跨过许多视觉行的链接文字</a>。<a class="other-link" href="/other/">其他</a></p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val links = root.querySelectorAll("p a.host-link[href='/target/']")
        assertEquals(1, links.length, "one source link must remain one DOM link across soft wraps")
        val link = links.item(0) as HTMLElement
        assertTrue(link.parentElement === root.querySelector("p"), "top-level source link must stay a direct child")
        assertEquals("_self", link.getAttribute("target"))
        assertEquals("author", link.getAttribute("rel"))
        assertEquals("Host title", link.getAttribute("title"))
        assertEquals("rgb(10, 11, 12)", link.style.getPropertyValue("color"))
        assertEquals("dotted", link.style.getPropertyValue("text-decoration-style"))
        assertEquals("text-decoration-color 200ms", link.style.getPropertyValue("transition"))
        assertNull(link.getAttribute("data-tq-link-group"))
        assertTrue(link.querySelectorAll("br[data-tq-engine-break]").length > 1)
        assertEquals("一段足够长而且确定会跨过许多视觉行的链接文字", link.textContent)

        TiqianWeb.refresh(root, progressively = false)
        val refreshedLinks = root.querySelectorAll("p a.host-link[href='/target/']")
        assertEquals(1, refreshedLinks.length)
        assertNull((refreshedLinks.item(0) as HTMLElement).getAttribute("data-tq-link-group"))
    }

    @Test
    fun keepsOneLinkAcrossConsecutiveEmptyHardBreakLines() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p><a class="host-link" href="/target/">甲<br><br>乙</a></p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val links = paragraph.querySelectorAll("a.host-link[href='/target/']")
        assertEquals(1, links.length)
        val link = links.item(0) as HTMLElement
        assertEquals(2, link.querySelectorAll("[data-tq-hard-break]").length)
        assertEquals(2, link.querySelectorAll("br[data-tq-engine-break='MandatoryBreak']").length)
        assertEquals("甲\n\n乙", copySelection(paragraph))
    }

    @Test
    fun keepsSemanticLinkContinuousAcrossGeometryFragments() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 700px">
              <p style="font-size: 18px; line-height: 30px">对比（来自<a class="host-link" href="/pull/4479">添加windows-reactor的PR</a>）：</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val links = paragraph.querySelectorAll("a.host-link[href='/pull/4479']")
        assertEquals(1, links.length, "one source link must stay one semantic wrapper per line")
        val link = links.item(0) as HTMLElement
        assertEquals("添加windows-reactor的PR", copySelection(link))
        assertTrue(link.children.length > 1, "geometry fragments should live inside the host link")
    }

    @Test
    fun keepsHostFontFamiliesAsTheMeasureAndPaintSource() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p style='font-family: "CP-hashed", "HostFace", sans-serif; font-size: 21px; line-height: 33px; font-weight: 460; font-style: italic;'>中<a href="/target/" style='font-family: "LinkFace", sans-serif; font-size: 22px; font-weight: 520; font-style: normal;'>链接</a><code style='font-family: "CodeFace", monospace; font-size: 13px; font-weight: 430; font-style: normal;'>code</code></p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(
            root,
            TiqianWeb.EnhanceOptions(
                fontFamilies = TiqianWeb.FontFamilyOptions(
                    cjk = "ConfiguredCjk, sans-serif",
                    latin = "ConfiguredLatin, sans-serif",
                    monospace = "ConfiguredMono, monospace",
                ),
            ),
        )

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as HTMLElement
        assertTrue(paragraph.style.fontFamily.contains("CP-hashed"))
        assertTrue(paragraph.style.fontFamily.contains("HostFace"))
        val line = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(line)
        assertEquals(33f, cssPx(line.style.getPropertyValue("--tq-line-height")))
        assertEquals(computedStyleValue(paragraph, "font-family"), computedStyleValue(line, "font-family"))
        assertEquals("21px", computedStyleValue(line, "font-size"))

        val link = paragraph.querySelector("a") as HTMLElement
        assertTrue(link.style.fontFamily.contains("LinkFace"))
        assertEquals("22px", link.style.fontSize)
        assertEquals("520", link.style.fontWeight)

        val code = paragraph.querySelector("code") as HTMLElement
        assertTrue(code.style.fontFamily.contains("CodeFace"))
        assertEquals("13px", code.style.fontSize)
        assertEquals("430", code.style.fontWeight)
    }

    @Test
    fun preservesHostInlineRenderStylesOnSemanticTags() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p>中<strong class="host-strong" style='color: rgb(1, 2, 3); text-decoration-line: underline; text-decoration-color: rgb(4, 5, 6); text-decoration-style: dotted; text-decoration-thickness: 2px; text-underline-offset: 3px;'>强调</strong></p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val strong = root.querySelector("p strong.host-strong") as? HTMLElement
        assertNotNull(strong)
        assertEquals("rgb(1, 2, 3)", strong.style.getPropertyValue("color"))
        assertEquals("underline", strong.style.getPropertyValue("text-decoration-line"))
        assertEquals("rgb(4, 5, 6)", strong.style.getPropertyValue("text-decoration-color"))
        assertEquals("dotted", strong.style.getPropertyValue("text-decoration-style"))
        assertEquals("2px", strong.style.getPropertyValue("text-decoration-thickness"))
        assertEquals("3px", strong.style.getPropertyValue("text-underline-offset"))
    }

    @Test
    fun measuresHostInlineBoxEdgesIntoLayout() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p>中<code style="padding-left: 4px; padding-right: 4px">code</code>文。</p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as HTMLElement
        val code = paragraph.querySelector("code") as? HTMLElement
        assertNotNull(code)
        assertEquals("4px", computedStyleValue(code, "padding-left"))
        assertEquals("4px", computedStyleValue(code, "padding-right"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
    }

    @Test
    fun keepsSuperscriptGeneratedContentNativeAndPreservesUniqueId() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <style>
                .fn::before { content: "["; }
                .fn::after { content: "]"; }
              </style>
              <p>这里有脚注<sup style="position: relative; top: -5px; font-size: 12px; line-height: 0"><a class="fn" id="fnref-1" href="#fn-1">1</a></sup>并继续正文。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(0, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val sup = paragraph.querySelector("sup") as? HTMLElement
        assertNotNull(sup)
        assertEquals("-5px", computedStyleValue(sup, "top"))
        assertEquals(1, paragraph.querySelectorAll("#fnref-1").length)
        assertNotNull(paragraph.querySelector("a.fn[href='#fn-1']"))
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "UnsupportedGeneratedInlineContent",
            paragraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertTrue(
            paragraph.getAttribute("data-tiqian-capability-detail")
                ?.startsWith("a::before:") == true,
        )
    }

    @Test
    fun keepsInlineBoxAsOneNativeElementAcrossEngineLines() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 90px">
              <p>前<spoiler style="padding-left: 4px; padding-right: 4px; border: 1px solid">一段足够长并且必然跨行的语义内容</spoiler>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val inline = root.querySelectorAll("p spoiler")
        assertEquals(1, inline.length)
        val spoiler = inline.item(0) as HTMLElement
        assertTrue(spoiler.querySelectorAll("br[data-tq-engine-break]").length > 1)
        assertEquals("4px", computedStyleValue(spoiler, "padding-left"))
        assertEquals("4px", computedStyleValue(spoiler, "padding-right"))
        assertNull(spoiler.getAttribute("data-tq-inline-open-start"))
        assertNull(spoiler.getAttribute("data-tq-inline-open-end"))
    }

    @Test
    fun engineGeometrySpansAreNeutralToHostSpanRules() {
        val root = mount(
            """
            <div class="host" data-tiqian-root="true" style="width: 320px">
              <style>
                .host p span { display: block !important; padding: 19px !important; font-size: 40px !important; }
                [data-tq-rendered="true"] span[data-tq-geometry="true"] {
                  all: unset !important;
                  display: inline !important;
                  text-spacing-trim: space-all !important;
                }
              </style>
              <p style="font-size: 18px; line-height: 30px">引擎生成的几何节点不能继承宿主对真实 span 的盒模型。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertNull(paragraph.querySelector(".tq-flow"))
        val run = paragraph.querySelector(":scope > [data-tq-geometry]:not(.tq-line)") as? HTMLElement
        assertNotNull(run)
        assertEquals("inline", computedStyleValue(run, "display"))
        assertEquals(0f, cssPx(computedStyleValue(run, "padding-left")))
        assertEquals(18f, cssPx(computedStyleValue(run, "font-size")))
    }

    @Test
    fun engineAnnotationsAreNeutralToHostSpanAndSvgRules() {
        val root = mount(
            """
            <div class="host" data-tiqian-root="true" style="width: 320px">
              <style>
                [data-tq-rendered="true"] svg[data-tq-geometry="true"] {
                  all: unset !important;
                  display: block !important;
                }
                [data-tq-rendered="true"] svg[data-tq-geometry="true"] circle[data-tq-decoration-dot] {
                  fill: var(--tq-decoration-color) !important;
                }
                .host p span { display: block !important; padding: 19px !important; }
                .host p svg { display: none !important; }
                .host p svg circle { fill: rgb(255, 0, 255) !important; }
              </style>
              <p style="color: rgb(1, 2, 3)">前<strong>强调</strong>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(
            1,
            TiqianWeb.enhance(root, testOptions().copy(strongAsEmphasisMarks = true)),
        )

        val paragraph = root.querySelector("p") as HTMLElement
        val svg = paragraph.querySelector("svg[data-tq-geometry]")
        val circle = paragraph.querySelector("circle")
        assertNotNull(svg)
        assertNotNull(circle)
        assertEquals("block", computedStyleValueElement(svg, "display"))
        assertEquals("rgb(1, 2, 3)", computedStyleValueElement(circle, "fill"))
    }

    @Test
    fun emitsFinalAndLatinAdjacentPunctuationSpacingWithoutClippingInk() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 220px">
              <p style="font-size: 18px; line-height: 30px">你想要开发一个小软件（单文件），那么你现在应该选择C++（MFC）、Rust（Winio）。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val lines = paragraph.querySelectorAll(".tq-line")
        assertTrue(lines.length > 1)
        for (index in 0 until lines.length) {
            val line = lines.item(index) as HTMLElement
            assertTrue(line.style.getPropertyValue("--tq-line-height").isNotEmpty())
            assertTrue(line.style.getPropertyValue("--tq-line-baseline-offset").isNotEmpty())
            assertEquals("", line.style.getPropertyValue("display"))
            assertEquals("", line.style.getPropertyValue("width"))
            assertEquals("", line.style.getPropertyValue("height"))
            assertEquals("", line.style.getPropertyValue("line-height"))
            assertEquals("", line.style.getPropertyValue("vertical-align"))
            assertEquals("", line.style.getPropertyValue("overflow"))
            assertEquals("", line.style.getPropertyValue("pointer-events"))
            assertNotNull(line.getAttribute("data-tq-line-width"))
        }

        val last = assertNotNull(lastTextLeaf(paragraph))
        assertTrue(
            cssPx(computedStyleValue(last, "letter-spacing")) < -0.1,
            "expected final-cluster compression: ${paragraph.innerHTML}",
        )
    }

    @Test
    fun browserPunctuationTrimDoesNotDoubleCompressClosingCommaOpeningSequence() {
        val source = "前句「甲」、「乙」后句。"
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 700px">
              <style>[data-tq-rendered="true"] [data-tq-geometry] { text-spacing-trim: space-all !important; }</style>
              <p style="font-size: 18px; line-height: 30px">$source</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val closingCommaRun = assertNotNull(geometryLeafWithText(paragraph, "」、"))
        assertEquals("space-all", computedStyleValue(closingCommaRun, "text-spacing-trim"))
        val characterWidths = textNodeCharacterWidths(closingCommaRun)
            .split(',')
            .mapNotNull(String::toDoubleOrNull)
        assertEquals(2, characterWidths.size)
        assertTrue(
            characterWidths.all { it >= 8.25 },
            "browser punctuation trimming consumed a second half-em: $characterWidths; ${paragraph.innerHTML}",
        )
        assertTrue(
            kotlin.math.abs(elementWidth(closingCommaRun) - 18.0) < 0.75,
            "closing-comma run must replay one em, was ${elementWidth(closingCommaRun)}; ${paragraph.innerHTML}",
        )
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun negativeGapAfterMultiCharacterRunUsesOverlapInsteadOfBeingDropped() {
        assertEquals(DomRunSpacing.Overlap(-9f), resolveDomRunSpacing("C++", -9f))
    }

    @Test
    fun positiveGapAfterMultiCharacterRunUsesSelectableCarrierWithoutBreakingShaping() {
        assertEquals(DomRunSpacing.TrailingLetter(9f), resolveDomRunSpacing("C++", 9f))

        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 700px">
              <p>中文<a href="/target/" style="padding: 4px; margin: -4px">bug</a>中文。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val link = root.querySelector("p a") as HTMLElement
        assertEquals(4f, cssPx(computedStyleValue(link, "padding-right")))
        assertEquals(-4f, cssPx(computedStyleValue(link, "margin-right")))
        val fragments = link.querySelectorAll(":scope > span")
        var spacingFragment: HTMLElement? = null
        for (index in 0 until fragments.length) {
            val fragment = fragments.item(index) as HTMLElement
            val carrier = fragment.querySelector("[data-tq-spacing-carrier]") as? HTMLElement
            if (carrier != null && elementWidth(carrier) > 0.1) {
                spacingFragment = fragment
            }
        }
        val fragment = assertNotNull(spacingFragment)
        val carrier = assertNotNull(fragment.querySelector("[data-tq-spacing-carrier]") as? HTMLElement)
        assertEquals("bug", fragment.firstChild?.textContent)
        assertEquals("\u00A0", carrier.textContent)
        assertEquals("true", carrier.getAttribute("data-tq-copy-ignore"))
        assertEquals("true", carrier.getAttribute("aria-hidden"))
        assertEquals("inline-block", computedStyleValue(carrier, "display"))
        assertEquals(0f, cssPx(computedStyleValue(fragment, "padding-right")))
        assertTrue(
            selectionCoversElement(fragment, carrier),
            "engine spacing must remain inside the native Range selection: ${fragment.outerHTML}",
        )
        assertEquals("bug", copySelection(link))
    }

    @Test
    fun keepsNativeParagraphWhenVisibleGlyphsHaveNoMeasuredAdvance() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p style="font-size: 0px">不可生成零宽行盒。</p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val original = paragraph.innerHTML

        val count = TiqianWeb.enhance(root)

        assertEquals(0, count)
        assertEquals(original, paragraph.innerHTML)
        assertEquals("InvalidWebShapingAdvance", paragraph.getAttribute("data-tiqian-capability-issue"))
        assertTrue(paragraph.getAttribute("data-tiqian-capability-detail")?.contains("advance=0") == true)
    }

    @Test
    fun combiningMarksAreShapedWithTheirBasesInsteadOfRejectingTheParagraph() {
        val source = "合法组合标记༎ຶ与螺丝Ỏ̷仍应保留在正文中。"
        val root = mount(
            "<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>",
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals(source, copySelection(paragraph))
    }

    @Test
    fun plainBodyTextUsesSparseRunsRatherThanOneNodePerCluster() {
        val text = "中文排版需要保留语义与宿主样式，同时由引擎负责断行和标点几何。".repeat(8)
        val root = mount("<div data-tiqian-root='true' style='width: 320px'><p>$text</p></div>")

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as HTMLElement
        val renderedNodes = paragraph.querySelectorAll("*").length
        assertTrue(renderedNodes < text.length / 2, "renderedNodes=$renderedNodes chars=${text.length}")
        assertTrue(paragraph.querySelectorAll(".tq-line").length > 1)
        assertEquals("true", paragraph.getAttribute("data-tq-canonical-source"))
    }

    @Test
    fun destroyRestoresOriginalChildrenAndHostAttributes() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p data-tq-rendered="host-owned" data-tq-canonical-source="host-owned" data-tq-copy-ignore="host-owned">需要<strong>增强</strong>。</p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals("host-owned", paragraph.getAttribute("data-tq-copy-ignore"))
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))

        TiqianWeb.destroy(root)

        assertEquals(originalHtml, paragraph.innerHTML)
        assertEquals("host-owned", paragraph.getAttribute("data-tq-copy-ignore"))
        assertEquals("host-owned", paragraph.getAttribute("data-tq-rendered"))
        assertEquals("host-owned", paragraph.getAttribute("data-tq-canonical-source"))
        assertNull(paragraph.getAttribute("style"))
    }

    @Test
    fun copyHandlerDoesNotInterceptTextOutsideRenderedParagraphs() {
        val root = mount("<div><p>普通站点文本不属于 Tiqian。</p></div>")
        TiqianWeb.install()
        val paragraph = root.querySelector("p") as HTMLElement

        assertEquals("普通站点文本不属于 Tiqian。", copySelection(paragraph))
        assertFalse(copySelectionWasIntercepted(paragraph))
    }

    @Test
    fun destroyCancelsProgressiveWorkBeforeItTouchesNativeContent() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p>渐进增强尚未执行时仍然是原生正文。</p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML

        TiqianWeb.enhanceProgressively(root, testOptions())
        assertEquals("0", root.getAttribute("data-tiqian-enhanced-count"))

        TiqianWeb.destroy(root)

        assertEquals(originalHtml, paragraph.innerHTML)
        assertNull(root.getAttribute("data-tiqian-enhanced"))
        assertNull(paragraph.getAttribute("data-tq-rendered"))
    }

    @Test
    fun longProgressiveEnhancementCommitsParagraphsAtomicallyAcrossFrames() {
        val markup = (0 until 18).joinToString("") { index ->
            "<p>第${index}段在自己的准备帧中原子切换。</p>"
        }
        val root = mount("<div data-tiqian-root='true' style='width: 180px'>$markup</div>")
        val paragraphs = (0 until 18).map { index ->
            root.querySelectorAll("p").item(index) as HTMLElement
        }
        val sourceChildren = paragraphs.map { paragraph -> assertNotNull(paragraph.firstChild) }
        var readyCount = 0
        var stale = false
        root.addEventListener("tiqian:ready", { event ->
            readyCount += 1
            stale = relayoutEventIsStale(event)
        })
        installTestAnimationFrames()

        TiqianWeb.enhanceProgressively(root, testOptions())

        var progressiveFrames = 0
        var previousRenderedCount = 0
        while (pendingTestAnimationFrameCount() > 0) {
            assertEquals(1, flushOneTestAnimationFrame())
            val renderedCount = root.querySelectorAll("p[data-tq-rendered='true']").length
            assertTrue(renderedCount >= previousRenderedCount)
            assertTrue(paragraphs.indices.all { index ->
                val paragraph = paragraphs[index]
                paragraph.firstChild === sourceChildren[index] ||
                    paragraph.getAttribute("data-tq-rendered") == "true"
            }, "each paragraph must be either intact source or a complete Tiqian result")
            if (pendingTestAnimationFrameCount() > 0) {
                progressiveFrames += 1
                assertTrue(renderedCount in 1 until paragraphs.size)
                assertEquals(renderedCount.toString(), root.getAttribute("data-tiqian-enhanced-count"))
                assertEquals(0, readyCount)
            }
            previousRenderedCount = renderedCount
        }

        assertTrue(progressiveFrames >= 2)
        assertTrue(paragraphs.indices.all { index ->
            paragraphs[index].firstChild !== sourceChildren[index]
        })
        assertEquals("18", root.getAttribute("data-tiqian-enhanced-count"))
        assertEquals(1, readyCount)
        assertFalse(stale)
    }

    @Test
    fun progressiveEnhancementPrioritizesViewportParagraphs() {
        val markup = (0 until 18).joinToString("") { index ->
            "<p>第${index}段用于验证视口优先顺序。</p>"
        }
        val root = mount("<div data-tiqian-root='true' style='width: 180px'>$markup</div>")
        val paragraphs = (0 until 18).map { index ->
            root.querySelectorAll("p").item(index) as HTMLElement
        }
        paragraphs.forEachIndexed { index, paragraph ->
            setElementRect(paragraph, top = 1_000_000.0 - index * 1_000.0, width = 180.0)
        }
        setElementRect(paragraphs.last(), top = 0.0, width = 180.0)
        installTestAnimationFrames()

        TiqianWeb.enhanceProgressively(root, testOptions())
        assertEquals(1, flushOneTestAnimationFrame())

        assertEquals("true", paragraphs.last().getAttribute("data-tq-rendered"))
        assertTrue(root.querySelectorAll("p[data-tq-rendered='true']").length < paragraphs.size)
        flushAllTestAnimationFrames()
        assertEquals(18, root.querySelectorAll("p[data-tq-rendered='true']").length)
    }

    @Test
    fun progressiveEnhancementRollsBackPartialWorkPreparedAcrossDifferentWidths() {
        val markup = (0 until 18).joinToString("") { index ->
            "<p>第${index}段不能把旧宽度结果混入同一次整批提交。</p>"
        }
        val root = mount("<div data-tiqian-root='true' style='width: 320px'>$markup</div>")
        val paragraphs = (0 until 18).map { index ->
            root.querySelectorAll("p").item(index) as HTMLElement
        }
        val sourceChildren = paragraphs.map { paragraph -> assertNotNull(paragraph.firstChild) }
        var readyCount = 0
        var stale = false
        root.addEventListener("tiqian:ready", { event ->
            readyCount += 1
            stale = relayoutEventIsStale(event)
        })
        installTestAnimationFrames()

        TiqianWeb.enhanceProgressively(root, testOptions())
        assertEquals(1, flushOneTestAnimationFrame())
        root.style.width = "120px"
        flushAllTestAnimationFrames()

        assertTrue(paragraphs.indices.all { index ->
            paragraphs[index].firstChild === sourceChildren[index]
        })
        assertEquals(0, root.querySelectorAll("p[data-tq-rendered='true']").length)
        assertEquals(1, readyCount)
        assertTrue(stale)

        TiqianWeb.enhanceProgressively(root, testOptions())
        flushAllTestAnimationFrames()

        assertEquals(18, root.querySelectorAll("p[data-tq-rendered='true']").length)
        assertEquals(2, readyCount)
        assertFalse(stale)
    }

    @Test
    fun relayoutDuringInitialProgressiveWorkRestartsWithoutStrandingCandidates() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 240px">
              <p>第一段必须在重启后增强。</p>
              <p>第二段也不能被旧 job 遗漏。</p>
            </div>
            """.trimIndent(),
        )
        var readyCount = 0
        root.addEventListener("tiqian:ready", { readyCount += 1 })
        TiqianWeb.install()
        installTestAnimationFrames()

        TiqianWeb.enhanceProgressively(root, testOptions())
        root.style.width = "120px"
        dispatchRelayout(root)

        assertEquals(1, cancelledTestAnimationFrameCount())
        assertEquals(1, pendingTestAnimationFrameCount())
        assertEquals("0", root.getAttribute("data-tiqian-enhanced-count"))

        flushAllTestAnimationFrames()

        assertEquals(2, root.querySelectorAll("p[data-tq-rendered='true']").length)
        assertEquals("2", root.getAttribute("data-tiqian-enhanced-count"))
        assertEquals(1, readyCount)
    }

    @Test
    fun newerRelayoutReplacesPendingWorkAndUsesTheLatestWidth() {
        val source = "连续 resize 只应提交最新宽度的分帧重排结果。".repeat(4)
        val root = mount("<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>")
        val expectedRoot = mount(
            "<div data-tiqian-root='true' style='width: 100px'><p>$source</p></div>",
        )
        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals(1, TiqianWeb.enhance(expectedRoot, testOptions()))
        val paragraph = root.querySelector("p") as HTMLElement
        val initial = renderedLineSignature(paragraph)
        val expected = renderedLineSignature(expectedRoot.querySelector("p") as HTMLElement)
        assertNotEquals(initial, expected)
        var relayoutReadyCount = 0
        root.addEventListener("tiqian:relayout-ready", { relayoutReadyCount += 1 })

        installTestAnimationFrames()
        root.style.width = "180px"
        dispatchRelayout(root)
        root.style.width = "100px"
        dispatchRelayout(root)

        assertEquals(1, cancelledTestAnimationFrameCount())
        assertEquals(1, pendingTestAnimationFrameCount())
        assertEquals(initial, renderedLineSignature(paragraph))

        flushAllTestAnimationFrames()

        assertEquals(expected, renderedLineSignature(paragraph))
        assertEquals(0, pendingTestAnimationFrameCount())
        assertEquals(1, relayoutReadyCount)
    }

    @Test
    fun relayoutKeepsOldTiqianDomUntilItsFirstProgressiveFrame() {
        val root = mount(
            "<div data-tiqian-root='true' style='width: 320px'>" +
                "<p>第一段在所有准备完成前保持旧节点。</p>" +
                "<p>第二段也不能提前暴露新排版。</p>" +
                "</div>",
        )
        TiqianWeb.install()
        assertEquals(2, TiqianWeb.enhance(root, testOptions()))
        val first = root.querySelectorAll("p").item(0) as HTMLElement
        val second = root.querySelectorAll("p").item(1) as HTMLElement
        val firstRenderedChild = first.firstChild
        val secondRenderedChild = second.firstChild
        assertNotNull(firstRenderedChild)
        assertNotNull(secondRenderedChild)
        var relayoutReadyCount = 0
        root.addEventListener("tiqian:relayout-ready", { relayoutReadyCount += 1 })

        installTestAnimationFrames()
        root.style.width = "120px"
        dispatchRelayout(root)

        assertTrue(first.firstChild === firstRenderedChild)
        assertTrue(second.firstChild === secondRenderedChild)
        assertEquals(1, pendingTestAnimationFrameCount())

        flushAllTestAnimationFrames()

        assertFalse(first.firstChild === firstRenderedChild)
        assertFalse(second.firstChild === secondRenderedChild)
        assertEquals(1, relayoutReadyCount)
    }

    @Test
    fun longRelayoutYieldsAndCommitsEachParagraphAtomically() {
        val markup = (0 until 18).joinToString("") { index ->
            "<p>第${index}段在分帧提交时必须一直保持上一份提椠排版。</p>"
        }
        val root = mount("<div data-tiqian-root='true' style='width: 320px'>$markup</div>")
        TiqianWeb.install()
        assertEquals(18, TiqianWeb.enhance(root, testOptions()))
        val paragraphs = (0 until 18).map { index ->
            root.querySelectorAll("p").item(index) as HTMLElement
        }
        val previousChildren = paragraphs.map { paragraph -> assertNotNull(paragraph.firstChild) }
        var relayoutReadyCount = 0
        root.addEventListener("tiqian:relayout-ready", { relayoutReadyCount += 1 })

        installTestAnimationFrames()
        root.style.width = "120px"
        dispatchRelayout(root)

        var progressiveFrames = 0
        var previousUpdatedCount = 0
        while (pendingTestAnimationFrameCount() > 0) {
            assertEquals(1, flushOneTestAnimationFrame())
            val updatedCount = paragraphs.indices.count { index ->
                paragraphs[index].firstChild !== previousChildren[index]
            }
            assertTrue(updatedCount >= previousUpdatedCount)
            if (pendingTestAnimationFrameCount() > 0) {
                progressiveFrames += 1
                assertTrue(updatedCount in 1 until paragraphs.size)
                assertEquals(0, relayoutReadyCount)
            }
            previousUpdatedCount = updatedCount
        }

        assertTrue(progressiveFrames >= 2, "a long root must still yield during relayout")
        assertTrue(paragraphs.indices.all { index ->
            paragraphs[index].firstChild !== previousChildren[index]
        })
        assertEquals(1, relayoutReadyCount)
    }

    @Test
    fun relayoutNeverCommitsPreparedMeasureOneGridCellBehindCurrentWidth() {
        val source = "任务执行中再次跨格时不能提交落后最终宽度的排版。".repeat(4)
        val root = mount("<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>")
        val intermediateRoot = mount(
            "<div data-tiqian-root='true' style='width: 180px'><p>$source</p></div>",
        )
        val finalRoot = mount(
            "<div data-tiqian-root='true' style='width: 162px'><p>$source</p></div>",
        )
        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals(1, TiqianWeb.enhance(intermediateRoot, testOptions()))
        assertEquals(1, TiqianWeb.enhance(finalRoot, testOptions()))
        val paragraph = root.querySelector("p") as HTMLElement
        val initialChild = assertNotNull(paragraph.firstChild)
        val initial = renderedLineSignature(paragraph)
        val intermediate = renderedLineSignature(intermediateRoot.querySelector("p") as HTMLElement)
        val final = renderedLineSignature(finalRoot.querySelector("p") as HTMLElement)
        assertNotEquals(initial, intermediate)
        assertNotEquals(intermediate, final)
        var readyCount = 0
        var staleCount = 0
        root.addEventListener("tiqian:relayout-ready", { event ->
            readyCount += 1
            if (relayoutEventIsStale(event)) staleCount += 1
        })

        installTestAnimationFrames()
        root.style.width = "180px"
        dispatchRelayout(root)
        root.style.width = "162px"
        flushAllTestAnimationFrames()

        assertTrue(paragraph.firstChild === initialChild)
        assertEquals(initial, renderedLineSignature(paragraph))
        assertEquals(1, readyCount)
        assertEquals(1, staleCount)

        dispatchRelayout(root)
        flushAllTestAnimationFrames()

        assertEquals(final, renderedLineSignature(paragraph))
        assertEquals(2, readyCount)
        assertEquals(1, staleCount)
    }

    @Test
    fun relayoutDiscardsPreparedMeasureMoreThanOneGridCellBehindCurrentWidth() {
        val source = "长文 resize 不能把相差多个字格的历史结果逐级播放出来。".repeat(4)
        val root = mount("<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>")
        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        val paragraph = root.querySelector("p") as HTMLElement
        val initialChild = assertNotNull(paragraph.firstChild)
        val initial = renderedLineSignature(paragraph)
        var readyCount = 0
        var staleCount = 0
        root.addEventListener("tiqian:relayout-ready", { event ->
            readyCount += 1
            if (relayoutEventIsStale(event)) staleCount += 1
        })

        installTestAnimationFrames()
        root.style.width = "180px"
        dispatchRelayout(root)
        root.style.width = "144px"
        flushAllTestAnimationFrames()

        assertTrue(paragraph.firstChild === initialChild)
        assertEquals(initial, renderedLineSignature(paragraph))
        assertEquals(1, readyCount)
        assertEquals(1, staleCount)
    }

    @Test
    fun relayoutDiscardsPreparedMeasureAfterOvershootOrDirectionReversal() {
        val source = "反向 resize 或越过当前目标时不能提交旧方向的排版。".repeat(4)
        TiqianWeb.install()
        installTestAnimationFrames()

        fun assertStaleAt(currentWidth: String, reason: String) {
            val root = mount(
                "<div data-tiqian-root='true' style='width: 320px'><p>$source</p></div>",
            )
            assertEquals(1, TiqianWeb.enhance(root, testOptions()))
            val paragraph = root.querySelector("p") as HTMLElement
            val initialChild = assertNotNull(paragraph.firstChild)
            val initial = renderedLineSignature(paragraph)
            var readyCount = 0
            var staleCount = 0
            root.addEventListener("tiqian:relayout-ready", { event ->
                readyCount += 1
                if (relayoutEventIsStale(event)) staleCount += 1
            })

            root.style.width = "180px"
            dispatchRelayout(root)
            root.style.width = currentWidth
            flushAllTestAnimationFrames()

            assertTrue(paragraph.firstChild === initialChild, reason)
            assertEquals(initial, renderedLineSignature(paragraph), reason)
            assertEquals(1, readyCount)
            assertEquals(1, staleCount)
        }

        assertStaleAt("240px", "prepared measure overshot the current target")
        assertStaleAt("360px", "viewport reversed past the previously committed measure")
    }

    @Test
    fun relayoutCommitFailureRollsBackRenderedNodesAndStillCompletesTheJob() {
        installExactFontSessionFixture(failShaping = false)
        try {
            val root = mount(
                "<div data-tiqian-root='true' style='width: 220px'>" +
                    "<p data-tq-snapshot-key='plain' style=\"font-family: 'Fixture CJK'; font-size: 18px; line-height: 30px\">" +
                    "原节点必须在异常后原样回来。</p></div>",
            )
            TiqianWeb.install()
            assertEquals(1, TiqianWeb.enhance(root, exactTestOptions()))
            val paragraph = root.querySelector("p") as HTMLElement
            val renderedChild = paragraph.firstChild
            val renderedHtml = paragraph.innerHTML
            val renderedStyle = paragraph.getAttribute("style")
            assertNotNull(renderedChild)
            var errorCount = 0
            var readyCount = 0
            root.addEventListener("tiqian:relayout-error", { errorCount += 1 })
            root.addEventListener("tiqian:relayout-ready", { readyCount += 1 })

            installTestAnimationFrames()
            failExactPreparedDomRender("fixture-commit-failure")
            root.style.width = "180px"
            dispatchRelayout(root)
            flushAllTestAnimationFrames()

            assertTrue(paragraph.firstChild === renderedChild)
            assertEquals(renderedHtml, paragraph.innerHTML)
            assertEquals(renderedStyle, paragraph.getAttribute("style"))
            assertEquals("true", paragraph.getAttribute("data-tq-canonical-plain"))
            assertEquals("true", paragraph.getAttribute("data-tq-canonical-source"))
            assertTrue(
                root.getAttribute("data-tiqian-relayout-error")?.contains("fixture-commit-failure") == true,
            )
            assertEquals(1, errorCount)
            assertEquals(1, readyCount, "terminal ready must release the JS in-flight state")
            assertEquals(0, pendingTestAnimationFrameCount())

            installExactFontSessionFixture(failShaping = false)
            root.style.width = "140px"
            dispatchRelayout(root)
            flushAllTestAnimationFrames()

            assertNull(root.getAttribute("data-tiqian-relayout-error"))
            assertEquals(2, readyCount)
            assertFalse(paragraph.firstChild === renderedChild)
        } finally {
            clearExactFontSessionFixture()
        }
    }

    @Test
    fun fractionalWidthCrossingAFontSizeGridBoundaryRelayouts() {
        val source = "小数宽度跨字格边界不能被像素容差吞掉。".repeat(20)
        val root = mount(
            "<div data-tiqian-root='true' style='width: 305.98px'><p>$source</p></div>",
        )
        val options = testOptions().copy(fontSize = 15.3f, lineHeight = 22.95f)
        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, options))
        val paragraph = root.querySelector("p") as HTMLElement
        val nineteenCells = renderedLineSignature(paragraph)

        installTestAnimationFrames()
        root.style.width = "306.02px"
        dispatchRelayout(root)
        flushAllTestAnimationFrames()

        assertNotEquals(
            nineteenCells,
            renderedLineSignature(paragraph),
            "19→20 cells is a real measure change even though the raw width delta is below 0.5px",
        )
    }

    @Test
    fun destroyCancelsPendingRelayoutBeforeItCanRestoreRenderedDom() {
        val root = mount(
            "<div data-tiqian-root='true' style='width: 260px'><p>取消 resize job 后必须保持原生正文。</p></div>",
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML
        TiqianWeb.install()
        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        installTestAnimationFrames()
        root.style.width = "100px"
        dispatchRelayout(root)
        assertEquals(1, pendingTestAnimationFrameCount())

        TiqianWeb.destroy(root)
        assertEquals(1, cancelledTestAnimationFrameCount())
        flushAllTestAnimationFrames()

        assertEquals(originalHtml, paragraph.innerHTML)
        assertNull(root.getAttribute("data-tiqian-enhanced"))
        assertNull(paragraph.getAttribute("data-tq-rendered"))
    }

    private fun mount(html: String): HTMLElement {
        val wrapper = document.createElement("div") as HTMLElement
        wrapper.innerHTML = html
        val root = wrapper.firstElementChild as HTMLElement
        document.body!!.appendChild(root)
        mounted += root
        return root
    }

    private fun testOptions(): TiqianWeb.EnhanceOptions =
        TiqianWeb.EnhanceOptions(
            monospaceFontContractExplicit = true,
            fontSize = 18f,
            lineHeight = 30f,
        )

    private fun exactTestOptions(): TiqianWeb.EnhanceOptions = TiqianWeb.EnhanceOptions(
        monospaceFontContractExplicit = true,
        paragraphSelector = "p[data-tq-snapshot-key]",
        exactFontSession = TiqianWeb.ExactFontSessionCapability(
            status = "conforming",
            sessionId = "fixture-exact-session",
            detail = "test",
        ),
    )
}
@JsFun(
    """() => {
      if (globalThis.__TiqianTestAnimationFrames) return;
      var tqInstallFrameState = {
        originalRequest: window.requestAnimationFrame,
        originalCancel: window.cancelAnimationFrame,
        callbacks: new Map(),
        nextId: 1,
        cancelled: 0,
      };
      globalThis.__TiqianTestAnimationFrames = tqInstallFrameState;
      window.requestAnimationFrame = (callback) => {
        var tqFrameId = tqInstallFrameState.nextId++;
        tqInstallFrameState.callbacks.set(tqFrameId, callback);
        return tqFrameId;
      };
      window.cancelAnimationFrame = (tqFrameId) => {
        if (tqInstallFrameState.callbacks.delete(tqFrameId)) tqInstallFrameState.cancelled += 1;
      };
    }""",
)
private external fun installTestAnimationFrames()
@JsFun(
    """() => {
      var tqFlushOneState = globalThis.__TiqianTestAnimationFrames;
      if (!tqFlushOneState) return 0;
      var tqFlushOneCallbacks = Array.from(tqFlushOneState.callbacks.values());
      tqFlushOneState.callbacks.clear();
      for (const tqFlushOneCallback of tqFlushOneCallbacks) tqFlushOneCallback(performance.now());
      return tqFlushOneCallbacks.length;
    }""",
)
private external fun flushOneTestAnimationFrame(): Int
@JsFun(
    """() => {
      var tqFlushAllState = globalThis.__TiqianTestAnimationFrames;
      if (!tqFlushAllState) return 0;
      var tqFlushAllSlices = 0;
      while (tqFlushAllState.callbacks.size > 0) {
        if (tqFlushAllSlices++ > 1000) throw new Error("animation frame test queue did not settle");
        var tqFlushAllCallbacks = Array.from(tqFlushAllState.callbacks.values());
        tqFlushAllState.callbacks.clear();
        for (const tqFlushAllCallback of tqFlushAllCallbacks) tqFlushAllCallback(performance.now());
      }
      return tqFlushAllSlices;
    }""",
)
private external fun flushAllTestAnimationFrames(): Int
@JsFun("() => globalThis.__TiqianTestAnimationFrames ? globalThis.__TiqianTestAnimationFrames.callbacks.size : 0")
private external fun pendingTestAnimationFrameCount(): Int
@JsFun("() => globalThis.__TiqianTestAnimationFrames ? globalThis.__TiqianTestAnimationFrames.cancelled : 0")
private external fun cancelledTestAnimationFrameCount(): Int
@JsFun(
    """() => {
      var tqPreviousWarnCapture = globalThis.__TiqianTestConsoleWarnCapture;
      if (tqPreviousWarnCapture) throw new Error("console.warn capture already installed");
      var tqOriginalWarn = console.warn;
      var tqMessages = [];
      globalThis.__TiqianTestConsoleWarnCapture = { original: tqOriginalWarn, messages: tqMessages };
      console.warn = (...args) => tqMessages.push(args.map(String).join(" "));
    }""",
)
private external fun installTestConsoleWarnCapture()
@JsFun(
    """() => {
      var tqWarnCapture = globalThis.__TiqianTestConsoleWarnCapture;
      return tqWarnCapture ? tqWarnCapture.messages.join("\n") : "";
    }""",
)
private external fun capturedTestConsoleWarnings(): String
@JsFun(
    """() => {
      var tqWarnCapture = globalThis.__TiqianTestConsoleWarnCapture;
      if (!tqWarnCapture) return;
      console.warn = tqWarnCapture.original;
      delete globalThis.__TiqianTestConsoleWarnCapture;
    }""",
)
private external fun restoreTestConsoleWarnCapture()
@JsFun(
    """(element, top, width) => {
      element.getBoundingClientRect = () => new DOMRect(0, top, width, 30);
    }""",
)
private external fun setElementRect(element: HTMLElement, top: Double, width: Double)
@JsFun("(event) => event.detail && event.detail.stale === true")
private external fun relayoutEventIsStale(event: Event): Boolean
@JsFun(
    """() => {
      var tqRestoreFrameState = globalThis.__TiqianTestAnimationFrames;
      if (!tqRestoreFrameState) return;
      window.requestAnimationFrame = tqRestoreFrameState.originalRequest;
      window.cancelAnimationFrame = tqRestoreFrameState.originalCancel;
      delete globalThis.__TiqianTestAnimationFrames;
    }""",
)
private external fun restoreTestAnimationFrames()
private fun installExactFontSessionFixture(
    failShaping: Boolean,
    failFamily: String? = null,
    failText: String? = null,
) {
    installExactFontSessionFixtureBridge(failShaping, failFamily, failText)
}
@JsFun(
    """(failShaping, failFamily, failText) => {
      const shapes = new Map();
      const metrics = new Map();
      let nextHandle = 1;
      globalThis.__TiqianExactPreparedPlan = "";
      globalThis.__TiqianExactPreparedRenderCount = 0;
      globalThis.__TiqianExactFontShapeCount = 0;
      globalThis.__TiqianExactFontFallbackCount = 0;
      globalThis.__TiqianFontBackend = {
        shape(_session, displayText, families, fontSize, _fontWeight, _italic, _locale, role) {
          if (failShaping ||
              (failFamily && String(families).includes(failFamily)) ||
              (failText && String(displayText).includes(failText))) {
            globalThis.__TiqianExactFontFallbackCount += 1;
            throw new Error("NoExactFontFace:test");
          }
          globalThis.__TiqianExactFontShapeCount += 1;
          const handle = nextHandle++;
          const glyphs = [];
          let glyphIndex = 0;
          for (const _point of displayText) {
            glyphs.push({
              id: 100 + glyphIndex,
              advance: fontSize,
              x: glyphIndex * fontSize,
              y: 0,
              bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
            });
            glyphIndex++;
          }
          const features = role === "LatinText" && /[‘’“”]/u.test(displayText)
            ? ["pwid", "palt"]
            : [];
          shapes.set(handle, { glyphs, advance: glyphs.length * fontSize, features });
          return handle;
        },
        shapeGlyphCount: (handle) => shapes.get(handle).glyphs.length,
        shapeGlyphId: (handle, index) => shapes.get(handle).glyphs[index].id,
        shapeGlyphAdvance: (handle, index) => shapes.get(handle).glyphs[index].advance,
        shapeGlyphX: (handle, index) => shapes.get(handle).glyphs[index].x,
        shapeGlyphY: (handle, index) => shapes.get(handle).glyphs[index].y,
        shapeGlyphBound: (handle, index, edge) => shapes.get(handle).glyphs[index].bounds[edge],
        shapeAdvance: (handle) => shapes.get(handle).advance,
        shapeFaceId: () => "Fixture CJK",
        shapeFontInstanceId: () => "fixture:0:default",
        shapeScript: () => "Hani",
        shapeFeatureCount: (handle) => shapes.get(handle).features.length,
        shapeFeature: (handle, index) => shapes.get(handle).features[index],
        shapeUnsafeBreakCount: () => 0,
        releaseShape: (handle) => shapes.delete(handle),
        metrics(_session, families, fontSize) {
          if (failShaping || (failFamily && String(families).includes(failFamily))) {
            globalThis.__TiqianExactFontFallbackCount += 1;
            throw new Error("NoExactFontFace:test");
          }
          const handle = nextHandle++;
          metrics.set(handle, [fontSize, fontSize * 0.25, 0, fontSize * 0.88, fontSize * 0.12]);
          return handle;
        },
        metricValue: (handle, index) => metrics.get(handle)[index],
        releaseMetrics: (handle) => metrics.delete(handle),
      };
      globalThis.__TiqianPreparedDomRenderer = {
        render(host, planJson, locale) {
          if (failShaping) throw new Error("Exact renderer must not run after shaping failure");
          globalThis.__TiqianExactPreparedRenderCount += 1;
          globalThis.__TiqianExactPreparedPlan = planJson;
          host.innerHTML = `<span data-tq-exact-rendered="${'$'}{locale}"></span>`;
          return {};
        },
      };
      globalThis.__TiqianPreparedDomValidator = { issue: () => null };
    }""",
)
private external fun installExactFontSessionFixtureBridge(
    failShaping: Boolean,
    failFamily: String?,
    failText: String?,
)
@JsFun("() => globalThis.__TiqianExactFontShapeCount || 0")
private external fun exactFontShapeCount(): Int
@JsFun("() => globalThis.__TiqianExactFontFallbackCount || 0")
private external fun exactFontFallbackCount(): Int
@JsFun("(detail) => { globalThis.__TiqianPreparedDomValidator = { issue: () => detail }; }")
private external fun failExactPreparedDomValidation(detail: String)
@JsFun("(detail) => { globalThis.__TiqianPreparedDomRenderer = { render() { throw new Error(detail); } }; }")
private external fun failExactPreparedDomRender(detail: String)
@JsFun("() => globalThis.__TiqianExactPreparedPlan || ''")
private external fun exactPreparedPlan(): String
@JsFun("() => globalThis.__TiqianExactPreparedRenderCount || 0")
private external fun exactPreparedRenderCount(): Int
@JsFun("() => { delete globalThis.__TiqianFontBackend; delete globalThis.__TiqianPreparedDomRenderer; delete globalThis.__TiqianPreparedDomValidator; delete globalThis.__TiqianExactPreparedPlan; delete globalThis.__TiqianExactPreparedRenderCount; delete globalThis.__TiqianExactFontShapeCount; delete globalThis.__TiqianExactFontFallbackCount; }")
private external fun clearExactFontSessionFixture()
@JsFun("(root) => document.dispatchEvent(new CustomEvent('tiqian:enhance', { detail: { root } }))")
private external fun dispatchEnhanceWithoutOptions(root: HTMLElement)
@JsFun("(root) => document.dispatchEvent(new CustomEvent('tiqian:enhance', { detail: { root, options: { strongAsEmphasisMarks: true } } }))")
private external fun dispatchEnhanceWithStrongAsEmphasisMarks(root: HTMLElement)
@JsFun("(root) => document.dispatchEvent(new CustomEvent('tiqian:relayout', { detail: { root } }))")
private external fun dispatchRelayout(root: HTMLElement)
@JsFun("(element, type) => element.dispatchEvent(new Event(type))")
private external fun dispatchDomEvent(element: HTMLElement, type: String)
@JsFun(
    """(element) => {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNodeContents(element);
      selection.removeAllRanges();
      selection.addRange(range);
      const clipboardData = new DataTransfer();
      element.dispatchEvent(new ClipboardEvent('copy', {
        bubbles: true,
        cancelable: true,
        clipboardData
      }));
      const text = clipboardData.getData('text/plain') || selection.toString();
      selection.removeAllRanges();
      return text;
    }""",
)
private external fun copySelection(element: HTMLElement): String
@JsFun(
    """(element) => {
      const selection = getSelection();
      const range = document.createRange();
      range.selectNodeContents(element);
      selection.removeAllRanges();
      selection.addRange(range);
      const event = new ClipboardEvent('copy', {
        bubbles: true,
        cancelable: true,
        clipboardData: new DataTransfer()
      });
      element.dispatchEvent(event);
      selection.removeAllRanges();
      return event.defaultPrevented;
    }""",
)
private external fun copySelectionWasIntercepted(element: HTMLElement): Boolean
@JsFun("(element) => element.innerText")
private external fun nativeInnerText(element: HTMLElement): String
@JsFun(
    """(paragraph) => Array.from(paragraph.querySelectorAll('.tq-line'))
      .filter((line) => line.dataset.tqLineEmpty === 'true')
      .length""",
)
private external fun emptyRenderedLineCount(paragraph: HTMLElement): Int
@JsFun(
    """(paragraph) => Array.from(paragraph.querySelectorAll('.tq-line'))
      .map((line) => [
        line.dataset.tqLineRange,
        line.dataset.tqLineWidth,
        line.dataset.tqLineEnd
      ].join('\u001f'))
      .join('\u001e')""",
)
private external fun renderedLineSignature(paragraph: HTMLElement): String
@JsFun(
    """(paragraph) => Array.from(paragraph.childNodes)
      .filter((node) => node.nodeType === Node.TEXT_NODE)
      .map((node) => node.data)
      .join('')""",
)
private external fun directTextContent(paragraph: HTMLElement): String
@JsFun(
    """(paragraph) => {
      const leaves = Array.from(paragraph.querySelectorAll('[data-tq-geometry]'))
        .filter((element) => !element.classList.contains('tq-line') && element.textContent.length > 0);
      return leaves.length === 0 ? null : leaves[leaves.length - 1];
    }""",
)
private external fun lastTextLeaf(paragraph: HTMLElement): HTMLElement?
@JsFun(
    """(paragraph, text) => Array.from(paragraph.querySelectorAll('[data-tq-geometry]'))
      .find((element) => element.textContent === text) || null""",
)
private external fun geometryLeafWithText(paragraph: HTMLElement, text: String): HTMLElement?
@JsFun(
    """(element) => {
      const node = element.firstChild;
      if (!node || node.nodeType !== Node.TEXT_NODE) return '';
      const widths = [];
      for (let index = 0; index < node.data.length; index += 1) {
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + 1);
        widths.push(range.getBoundingClientRect().width);
      }
      return widths.join(',');
    }""",
)
private external fun textNodeCharacterWidths(element: HTMLElement): String
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyleValue(element: HTMLElement, property: String): String
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyleValueElement(element: Element, property: String): String
@JsFun(
    """(container, target) => {
      const range = document.createRange();
      range.selectNodeContents(container);
      const selected = range.getBoundingClientRect();
      const expected = target.getBoundingClientRect();
      return selected.left <= expected.left + 0.1 && selected.right >= expected.right - 0.1;
    }""",
)
private external fun selectionCoversElement(container: HTMLElement, target: HTMLElement): Boolean
@JsFun("(element) => element.getBoundingClientRect().width")
private external fun elementWidth(element: HTMLElement): Double

private fun Char.isCurlyQuoteForWebTest(): Boolean =
    this == '\u2018' || this == '\u2019' || this == '\u201C' || this == '\u201D'

private fun cssPx(value: String): Float = value.removeSuffix("px").toFloatOrNull() ?: 0f
