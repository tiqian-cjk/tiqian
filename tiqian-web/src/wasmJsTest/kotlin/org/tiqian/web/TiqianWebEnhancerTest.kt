package org.tiqian.web

import kotlin.JsFun
import kotlin.js.ExperimentalWasmJsInterop
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

class TiqianWebEnhancerTest {
    private val mounted = mutableListOf<HTMLElement>()

    @AfterTest
    fun cleanup() {
        for (root in mounted) {
            TiqianWeb.destroy(root)
            root.parentNode?.removeChild(root)
        }
        mounted.clear()
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
        assertTrue(paragraph.textContent?.contains("中文粗体italiccode链接换行。") == true)
        assertNotNull(paragraph.querySelector("strong"))
        assertNotNull(paragraph.querySelector("em"))
        assertNotNull(paragraph.querySelector("code"))
        assertNotNull(paragraph.querySelector("a.host-link[href='/target/']"))
        assertTrue(paragraph.style.display.isEmpty())
        assertNull(paragraph.getAttribute("data-tq-copy-ignore"))
    }

    @Test
    fun rendersOnlyCjkContentInStrongAsEmphasisMarks() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 320px">
              <p style="font-weight: 430">前<strong style="font-weight: 700; color: rgb(1, 2, 3)">强调，CSharp 42🙂</strong>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val strong = paragraph.querySelector("strong[data-tq-cjk-emphasis]") as? HTMLElement
        assertNotNull(strong)
        assertEquals("430", computedStyleValue(strong, "font-weight"))
        assertEquals(2, paragraph.querySelectorAll("circle").length)
        assertEquals("rgb(1, 2, 3)", paragraph.querySelector("circle")?.getAttribute("fill"))

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
    fun exposesExplicitEmphasisDotCenterOffset() {
        fun enhanceWithOffset(offset: Float): Float {
            val root = mount(
                """
                <div data-tiqian-root="true" style="width: 320px">
                  <p>前<strong>强调</strong>后。</p>
                </div>
                """.trimIndent(),
            )
            assertEquals(
                1,
                TiqianWeb.enhance(
                    root,
                    testOptions().copy(emphasisDotCenterOffsetEm = offset),
                ),
            )
            return root.querySelector("circle")!!.getAttribute("cy")!!.toFloat()
        }

        val defaultCenter = enhanceWithOffset(0.45f)
        val adjustedCenter = enhanceWithOffset(0.60f)
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
        assertEquals("32px", line.style.getPropertyValue("line-height"))
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
        assertEquals("28px", (paragraph.querySelector(".tq-line") as HTMLElement).style.lineHeight)

        paragraph.style.fontSize = "18px"
        paragraph.style.lineHeight = "32px"
        paragraph.style.fontWeight = "460"
        TiqianWeb.refresh(root, progressively = false)

        paragraph = root.querySelector("p") as HTMLElement
        val line = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(line)
        assertEquals("32px", line.style.lineHeight)
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
        assertEquals("前badge后。", paragraph.textContent)
        assertTrue(paragraph.textContent?.contains('\uFFFC') == false)
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))

        val objectLine = paragraph.querySelector(".tq-line") as? HTMLElement
        assertNotNull(objectLine)
        assertTrue(cssPx(objectLine.style.height) >= 30f)
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
    fun renderedSubstitutionKeepsSourceForCopyHandler() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p>中文……中文。</p>
            </div>
            """.trimIndent(),
        )

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val sourceMapped = root.querySelector("p [data-tq-src]") as? HTMLElement
        assertNotNull(sourceMapped)
        assertTrue(sourceMapped.getAttribute("data-tq-src")?.contains("……") == true)
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
        root.style.width = "120px"
        dispatchRelayout(root)
        val narrow = renderedLineSignature(paragraph)
        assertNotEquals(initial, narrow, "narrow width must exercise a real reflow")

        root.style.width = "220px"
        dispatchRelayout(root)
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
    fun widthDependentCapabilityFallsBackAtomicallyAndCanRecover() {
        val root = mount(
            """
            <div data-tiqian-root="true" style="width: 520px">
              <p><span style="box-decoration-break: clone; -webkit-box-decoration-break: clone; padding: 0 6px">跨行复制盒模型只在窄行失去保真能力</span></p>
            </div>
            """.trimIndent(),
        )
        val paragraph = root.querySelector("p") as HTMLElement
        val originalHtml = paragraph.innerHTML
        TiqianWeb.install()

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))
        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))

        root.style.width = "90px"
        dispatchRelayout(root)

        assertEquals(originalHtml, paragraph.innerHTML)
        assertNull(paragraph.getAttribute("data-tq-rendered"))
        assertEquals(
            "InlineCloneDecorationBreakUnsupported",
            paragraph.getAttribute("data-tiqian-capability-issue"),
        )
        assertEquals("0", root.getAttribute("data-tiqian-enhanced-count"))

        root.style.width = "520px"
        dispatchRelayout(root)

        assertEquals("true", paragraph.getAttribute("data-tq-rendered"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
        assertEquals("1", root.getAttribute("data-tiqian-enhanced-count"))
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
        assertEquals("添加windows-reactor的PR", link.textContent)
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
        assertEquals("33px", line.style.getPropertyValue("line-height"))
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
    fun preservesSuperscriptBaselineGeneratedContentAndUniqueId() {
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

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

        val paragraph = root.querySelector("p") as HTMLElement
        val sup = paragraph.querySelector("sup") as? HTMLElement
        assertNotNull(sup)
        assertEquals("-5px", computedStyleValue(sup, "top"))
        assertEquals(1, paragraph.querySelectorAll("#fnref-1").length)
        assertNotNull(paragraph.querySelector("a.fn[href='#fn-1']"))
        assertNull(paragraph.getAttribute("data-tiqian-capability-issue"))
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
              <style>.host p span { display: block !important; padding: 19px !important; font-size: 40px !important; }</style>
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
                .host p span { display: block !important; padding: 19px !important; }
                .host p svg { display: none !important; }
                .host p svg circle { fill: rgb(255, 0, 255) !important; }
              </style>
              <p style="color: rgb(1, 2, 3)">前<strong>强调</strong>后。</p>
            </div>
            """.trimIndent(),
        )

        assertEquals(1, TiqianWeb.enhance(root, testOptions()))

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
            assertEquals("visible", line.style.getPropertyValue("overflow"))
            assertEquals("0px", line.style.width)
            assertNotNull(line.getAttribute("data-tq-line-width"))
        }

        val last = assertNotNull(lastTextLeaf(paragraph))
        assertTrue(
            cssPx(computedStyleValue(last, "letter-spacing")) < -0.1,
            "expected final-cluster compression: ${paragraph.innerHTML}",
        )
    }

    @Test
    fun negativeGapAfterMultiCharacterRunUsesOverlapInsteadOfBeingDropped() {
        assertEquals(DomRunSpacing.Overlap(-9f), resolveDomRunSpacing("C++", -9f))
    }

    @Test
    fun positiveGapAfterMultiCharacterRunUsesOnlyItsFinalGrapheme() {
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
            val tail = fragment.lastElementChild as? HTMLElement
            if (tail != null && cssPx(computedStyleValue(tail, "letter-spacing")) > 0.1f) {
                spacingFragment = fragment
            }
        }
        val fragment = assertNotNull(spacingFragment)
        assertEquals("bug", fragment.textContent)
        assertEquals("g", fragment.lastElementChild?.textContent)
        assertEquals(0f, cssPx(computedStyleValue(fragment, "padding-right")))
        assertTrue(
            kotlin.math.abs(selectionTrailingGap(fragment)) < 0.1,
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
    fun plainBodyTextUsesSparseRunsRatherThanOneNodePerCluster() {
        val text = "中文排版需要保留语义与宿主样式，同时由引擎负责断行和标点几何。".repeat(8)
        val root = mount("<div data-tiqian-root='true' style='width: 320px'><p>$text</p></div>")

        val count = TiqianWeb.enhance(root, testOptions())

        assertEquals(1, count)
        val paragraph = root.querySelector("p") as HTMLElement
        val renderedNodes = paragraph.querySelectorAll("*").length
        assertTrue(renderedNodes < text.length / 2, "renderedNodes=$renderedNodes chars=${text.length}")
        assertTrue(paragraph.querySelectorAll(".tq-line").length > 1)
    }

    @Test
    fun destroyRestoresOriginalChildrenAndHostAttributes() {
        val root = mount(
            """
            <div data-tiqian-root="true">
              <p data-tq-rendered="host-owned" data-tq-copy-ignore="host-owned">需要<strong>增强</strong>。</p>
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
            fontSize = 18f,
            lineHeight = 30f,
        )
}

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(root) => document.dispatchEvent(new CustomEvent('tiqian:enhance', { detail: { root } }))")
private external fun dispatchEnhanceWithoutOptions(root: HTMLElement)

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(root) => document.dispatchEvent(new CustomEvent('tiqian:relayout', { detail: { root } }))")
private external fun dispatchRelayout(root: HTMLElement)

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, type) => element.dispatchEvent(new Event(type))")
private external fun dispatchDomEvent(element: HTMLElement, type: String)

@OptIn(ExperimentalWasmJsInterop::class)
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

@OptIn(ExperimentalWasmJsInterop::class)
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

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => element.innerText")
private external fun nativeInnerText(element: HTMLElement): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(paragraph) => Array.from(paragraph.querySelectorAll('.tq-line'))
      .filter((line) => line.dataset.tqLineEmpty === 'true')
      .length""",
)
private external fun emptyRenderedLineCount(paragraph: HTMLElement): Int

@OptIn(ExperimentalWasmJsInterop::class)
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

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(paragraph) => {
      const leaves = Array.from(paragraph.querySelectorAll('[data-tq-geometry]'))
        .filter((element) => !element.classList.contains('tq-line') && element.textContent.length > 0);
      return leaves.length === 0 ? null : leaves[leaves.length - 1];
    }""",
)
private external fun lastTextLeaf(paragraph: HTMLElement): HTMLElement?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyleValue(element: HTMLElement, property: String): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyleValueElement(element: Element, property: String): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(element) => {
      const range = document.createRange();
      range.selectNodeContents(element);
      return element.getBoundingClientRect().right - range.getBoundingClientRect().right;
    }""",
)
private external fun selectionTrailingGap(element: HTMLElement): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => element.getBoundingClientRect().width")
private external fun elementWidth(element: HTMLElement): Double

private fun cssPx(value: String): Float = value.removeSuffix("px").toFloatOrNull() ?: 0f
