package org.tiqian.web

import kotlin.JsFun
import kotlin.js.ExperimentalWasmJsInterop
import kotlin.js.JsAny
import kotlin.js.js
import kotlinx.browser.document
import kotlinx.browser.window
import org.tiqian.core.ColorSpan
import org.tiqian.core.DEFAULT_EMPHASIS_DOT_CENTER_OFFSET_EM
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.Ic
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.INLINE_OBJECT_REPLACEMENT_CHAR
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FontRole
import org.tiqian.font.FontRoleContext
import org.tiqian.shaping.web.WebCanvasFontMetricsResolver
import org.tiqian.shaping.web.WebCanvasTextShaper
import org.tiqian.shaping.web.WebCjkDashCapability
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.Element
import org.w3c.dom.DocumentFragment
import org.w3c.dom.HTMLElement
import org.w3c.dom.Node
import org.w3c.dom.events.Event

/**
 * Browser embed API for ADR 0039 dogfood.
 *
 * Host pages keep their SSR markdown for no-JS / SEO / Pagefind. Tiqian enhances
 * eligible paragraphs in place: the source `<p>` remains the semantic and CSS
 * owner while only its inline children are replaced with pre-broken line DOM.
 */
@OptIn(ExperimentalWasmJsInterop::class)
object TiqianWeb {
    private const val ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]"
    private const val DEFAULT_PARAGRAPH_SELECTOR = "p"
    private const val SKIPPED_ANCESTOR_SELECTOR =
        ".not-prose, pre, table, .katex, .katex-display, .expressive-code, .tq-paragraph, [data-tiqian-skip]"

    private var installed = false
    private val states = LinkedHashMap<HTMLElement, RootState>()
    private val progressiveJobs = LinkedHashMap<HTMLElement, ProgressiveJob>()

    fun install() {
        if (installed) return
        installed = true
        installTiqianCopyHandler()
        installTiqianGlobalApiBridge()
        document.addEventListener("tiqian:enhance", listener@{ event: Event ->
            val root = eventRoot(event) ?: document.body ?: return@listener
            enhance(root, optionsFromJs(eventOptions(event)))
        })
        document.addEventListener("tiqian:enhance-progressively", listener@{ event: Event ->
            val root = eventRoot(event) ?: document.body ?: return@listener
            enhanceProgressively(root, optionsFromJs(eventOptions(event)))
        })
        document.addEventListener("tiqian:destroy", listener@{ event: Event ->
            val root = eventRoot(event) ?: document.body ?: return@listener
            destroy(root)
        })
        document.addEventListener("tiqian:enhance-all", { event: Event ->
            enhanceAll(optionsFromJs(eventOptions(event)))
        })
        document.addEventListener("tiqian:relayout", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            relayout(root)
        })
        document.addEventListener("tiqian:refresh", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            refresh(root)
        })
    }

    fun enhanceAll(options: EnhanceOptions = EnhanceOptions()): Int {
        val roots = document.querySelectorAll(ROOT_SELECTOR)
        var count = 0
        for (i in 0 until roots.length) {
            val root = roots.item(i) as? HTMLElement ?: continue
            count += enhance(root, options)
        }
        return count
    }

    fun enhance(root: HTMLElement, options: EnhanceOptions = EnhanceOptions()): Int {
        installTiqianCopyHandler()
        destroy(root)
        val state = createRootState(root, options)
        for (paragraph in paragraphCandidates(root, state.options.paragraphSelector)) {
            processParagraph(paragraph, state)
        }
        publishState(state)
        return state.paragraphs.size
    }

    /**
     * Enhance in bounded animation-frame slices. Paragraphs not reached yet stay
     * as native SSR DOM, so loading Tiqian never creates one page-sized long task.
     */
    fun enhanceProgressively(root: HTMLElement, options: EnhanceOptions = EnhanceOptions()) {
        installTiqianCopyHandler()
        destroy(root)
        val state = createRootState(root, options)
        val job = ProgressiveJob(
            state = state,
            candidates = paragraphCandidates(root, state.options.paragraphSelector),
            startedAt = performanceNow(),
        )
        states[root] = state
        progressiveJobs[root] = job
        publishState(state, keepEmpty = true)
        if (job.candidates.isEmpty()) {
            finishProgressiveJob(job)
        } else {
            scheduleProgressiveSlice(job)
        }
    }

    fun destroy(root: HTMLElement) {
        progressiveJobs.remove(root)?.frameId?.let { window.cancelAnimationFrame(it) }
        val state = states.remove(root)
        if (state != null) {
            for (paragraph in state.paragraphs) {
                restoreParagraph(paragraph)
            }
            for (issue in state.issues) {
                clearIssue(issue)
            }
        }
        root.removeAttribute("data-tiqian-enhanced")
        root.removeAttribute("data-tiqian-enhanced-count")
        root.removeAttribute("data-tiqian-issue-count")
    }

    private fun createRootState(root: HTMLElement, options: EnhanceOptions): RootState {
        val resolved = options.withRootDefaults(root)
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            fontMetricsResolver = WebCanvasFontMetricsResolver(resolved.fonts),
            textShaper = WebCanvasTextShaper(resolved.fonts, resolved.cjkDashCapability),
        )
        return RootState(root, resolved, engine, mutableListOf(), mutableListOf())
    }

    private fun paragraphCandidates(root: HTMLElement, selector: String): List<HTMLElement> {
        val nodes = root.querySelectorAll(selector)
        return buildList {
            for (i in 0 until nodes.length) {
                val paragraph = nodes.item(i) as? HTMLElement ?: continue
                if (belongsToRootScope(paragraph, root, ROOT_SELECTOR)) add(paragraph)
            }
        }
    }

    private fun processParagraph(paragraph: HTMLElement, state: RootState) {
        if (!shouldTryParagraph(paragraph)) return
        val lowered = try {
            MarkdownParagraphLowerer.lower(paragraph, state.options)
        } catch (error: Throwable) {
            val issue = CapabilityIssue(
                "DomLoweringFailure",
                error.message ?: "unexpected DOM lowering failure",
                paragraph,
            )
            state.issues += issue
            reportIssue(issue)
            return
        }
        if (lowered == null) {
            val issue = MarkdownParagraphLowerer.lastIssue ?: CapabilityIssue(
                "UnsupportedParagraph",
                "paragraph could not be lowered",
                paragraph,
            )
            state.issues += issue
            reportIssue(issue)
            return
        }

        val originalRenderedAttribute = paragraph.getAttribute("data-tq-rendered")
        val originalStyleAttribute = paragraph.getAttribute("style")
        val originalPosition = paragraph.style.getPropertyValue("position")
        val originalPositionPriority = paragraph.style.getPropertyPriority("position")
        val originalContent = document.createDocumentFragment()
        while (paragraph.firstChild != null) {
            originalContent.appendChild(paragraph.firstChild!!)
        }
        paragraph.setAttribute("data-tq-rendered", "true")
        val item = EnhancedParagraph(
            source = paragraph,
            originalContent = originalContent,
            lowered = lowered,
            originalRenderedAttribute = originalRenderedAttribute,
            originalStyleAttribute = originalStyleAttribute,
            originalPosition = originalPosition,
            originalPositionPriority = originalPositionPriority,
        )
        val layoutIssue = try {
            layoutParagraph(item, state.options, state.engine)
        } catch (error: Throwable) {
            CapabilityIssue(
                "WebEnhancementFailure",
                error.message ?: "unexpected layout or DOM rendering failure",
                paragraph,
            )
        }
        if (layoutIssue == null) {
            state.paragraphs += item
        } else {
            restoreParagraph(item)
            state.issues += layoutIssue
            reportIssue(layoutIssue)
        }
    }

    private fun publishState(state: RootState, keepEmpty: Boolean = false) {
        val hasWork = state.paragraphs.isNotEmpty() || state.issues.isNotEmpty()
        if (!hasWork && !keepEmpty) {
            states.remove(state.root)
            state.root.removeAttribute("data-tiqian-enhanced")
            state.root.removeAttribute("data-tiqian-enhanced-count")
            state.root.removeAttribute("data-tiqian-issue-count")
            return
        }
        states[state.root] = state
        state.root.setAttribute("data-tiqian-enhanced", "true")
        state.root.setAttribute("data-tiqian-enhanced-count", "${state.paragraphs.size}")
        if (state.issues.isEmpty()) {
            state.root.removeAttribute("data-tiqian-issue-count")
        } else {
            state.root.setAttribute("data-tiqian-issue-count", "${state.issues.size}")
        }
    }

    private fun scheduleProgressiveSlice(job: ProgressiveJob) {
        job.frameId = window.requestAnimationFrame {
            runProgressiveSlice(job)
        }
    }

    private fun runProgressiveSlice(job: ProgressiveJob) {
        if (progressiveJobs[job.state.root] !== job) return
        job.frameId = null
        val sliceStartedAt = performanceNow()
        do {
            processParagraph(job.candidates[job.nextIndex], job.state)
            job.nextIndex += 1
        } while (
            job.nextIndex < job.candidates.size &&
            performanceNow() - sliceStartedAt < MAX_PROGRESSIVE_SLICE_MS
        )
        val sliceDuration = performanceNow() - sliceStartedAt
        job.maxSliceDuration = maxOf(job.maxSliceDuration, sliceDuration)
        publishState(job.state, keepEmpty = true)
        if (job.nextIndex >= job.candidates.size) {
            finishProgressiveJob(job)
        } else {
            scheduleProgressiveSlice(job)
        }
    }

    private fun finishProgressiveJob(job: ProgressiveJob) {
        if (progressiveJobs.remove(job.state.root) !== job) return
        publishState(job.state)
        dispatchTiqianReady(
            root = job.state.root,
            enhancedCount = job.state.paragraphs.size,
            issueCount = job.state.issues.size,
            durationMs = performanceNow() - job.startedAt,
            maxSliceMs = job.maxSliceDuration,
        )
    }

    private fun relayout(root: HTMLElement) {
        val state = states[root] ?: return
        if (state.issues.isNotEmpty()) {
            // CapabilityTransitionRetry: some capabilities (notably
            // box-decoration-break:clone) depend on the current line count.
            // A later width can make a native paragraph eligible again.
            enhance(root, state.options)
            return
        }
        val paragraphs = state.paragraphs.toList()
        for (paragraph in paragraphs) {
            val issue = layoutParagraph(paragraph, state.options, state.engine) ?: continue
            restoreParagraph(paragraph)
            state.paragraphs.remove(paragraph)
            state.issues += issue
            reportIssue(issue)
        }
        publishState(state)
    }

    /**
     * HostTypographyInvalidation: width-only relayout can reuse lowered source,
     * but a host font/size/weight/line-height change must restore the semantic
     * DOM and lower it again. Otherwise canvas measures the old computed style
     * while light DOM paints the new one, producing clipped whole-line overflow.
     */
    internal fun refresh(root: HTMLElement, progressively: Boolean = true) {
        val options = states[root]?.options ?: return
        if (progressively) {
            enhanceProgressively(root, options)
        } else {
            enhance(root, options)
        }
    }

    private fun layoutParagraph(
        paragraph: EnhancedParagraph,
        options: EnhanceOptions,
        engine: ExplainableStubParagraphLayoutEngine,
    ): CapabilityIssue? {
        val width = elementWidth(paragraph.source).toFloat()
            .takeIf { it > 0f }
            ?: elementWidth(paragraph.source.parentElement as? HTMLElement ?: paragraph.source).toFloat()
                .takeIf { it > 0f }
            ?: 320f
        if (paragraph.lastWidth != null && kotlin.math.abs(paragraph.lastWidth!! - width) < 0.5f) return null
        paragraph.lastWidth = width
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(
                    text = paragraph.lowered.text,
                    spans = paragraph.lowered.spans,
                    sourceBoundaries = paragraph.lowered.sourceBoundaries,
                ),
                textStyle = paragraph.lowered.textStyle,
                constraints = LayoutConstraints(maxWidth = width),
                paragraphStyle = ParagraphStyle(
                    lineHeight = paragraph.lowered.lineHeight,
                    firstLineIndent = Ic(options.firstLineIndentIc),
                    emphasisDotCenterOffsetEm = options.emphasisDotCenterOffsetEm,
                ),
                decorations = paragraph.lowered.decorations,
                rubySpans = emptyList(),
                inlineBoxes = paragraph.lowered.inlineBoxes,
                inlineObjects = paragraph.lowered.inlineObjects,
            ),
        )
        val shapingCapabilityIssue = result.debug.shapingDecisions.firstOrNull {
            it.capabilityIssue != null
        }
        if (shapingCapabilityIssue != null) {
            return CapabilityIssue(
                name = shapingCapabilityIssue.capabilityIssue!!,
                detail = shapingCapabilityIssue.reason,
                element = paragraph.source,
            )
        }
        val invalidShaping = result.debug.shapingDecisions.firstOrNull { decision ->
            decision.displayText.isNotEmpty() &&
                decision.displayText.none { it == '\n' || it == '\r' } &&
                (!decision.advance.isFinite() || decision.advance <= ZERO_ADVANCE_EPSILON)
        }
        if (invalidShaping != null) {
            return CapabilityIssue(
                name = "InvalidWebShapingAdvance",
                detail = buildString {
                    append("text=")
                    append(invalidShaping.displayText)
                    append("; advance=")
                    append(invalidShaping.advance)
                    append("; ")
                    append(invalidShaping.reason)
                },
                element = paragraph.source,
            )
        }
        val clonedDecoration = paragraph.lowered.sourceSpans.firstOrNull { span ->
            span.inlineBoxStyle.boxDecorationBreak == "clone" &&
                (kotlin.math.abs(span.inlineBoxStyle.inlineStart) >= INLINE_EDGE_EPSILON ||
                    kotlin.math.abs(span.inlineBoxStyle.inlineEnd) >= INLINE_EDGE_EPSILON) &&
                result.lines.count { line ->
                    line.range.start < span.range.end && line.range.end > span.range.start
                } > 1
        }
        if (clonedDecoration != null) {
            return CapabilityIssue(
                name = "InlineCloneDecorationBreakUnsupported",
                detail = clonedDecoration.element.tagName.lowercase(),
                element = paragraph.source,
            )
        }
        ensureHostFlowStyles(paragraph)
        ensureContainingBlock(paragraph)
        DomParagraphRenderer.render(
            paragraph.source,
            result,
            options.fonts,
            sourceSpans = paragraph.lowered.sourceSpans,
            inlineObjects = paragraph.lowered.domInlineObjects,
        )
        DomParagraphRenderer.verifyCjkDashRuns(paragraph.source)?.let { detail ->
            return CapabilityIssue(
                name = "DomDashFaceGeometryMismatch",
                detail = detail,
                element = paragraph.source,
            )
        }
        return null
    }

    private fun shouldTryParagraph(paragraph: HTMLElement): Boolean {
        if (hasClosest(paragraph, SKIPPED_ANCESTOR_SELECTOR)) return false
        if (paragraph.getAttribute("data-tiqian-skip") != null) return false
        if (paragraph.textContent?.isBlank() != false && !hasOpaqueInlineCandidate(paragraph)) return false
        return true
    }

    private fun hasOpaqueInlineCandidate(paragraph: HTMLElement): Boolean {
        val descendants = paragraph.querySelectorAll("*")
        for (index in 0 until descendants.length) {
            val element = descendants.item(index) as? Element ?: continue
            val tag = element.tagName.uppercase()
            val display = computedStyle(element, "display").trim().lowercase()
            if (tag in NON_TEXT_INLINE_TAGS || tag.contains('-') || display in OPAQUE_INLINE_DISPLAYS) {
                return true
            }
        }
        return false
    }

    private fun reportIssue(issue: CapabilityIssue) {
        if (!issue.markerCaptured) {
            issue.originalNameAttribute = issue.element.getAttribute("data-tiqian-capability-issue")
            issue.originalDetailAttribute = issue.element.getAttribute("data-tiqian-capability-detail")
            issue.markerCaptured = true
        }
        issue.element.setAttribute("data-tiqian-capability-issue", issue.name)
        issue.element.setAttribute("data-tiqian-capability-detail", issue.detail.take(CAPABILITY_DETAIL_LIMIT))
        consoleWarn("TiqianWeb skipped paragraph: ${issue.name} (${issue.detail})")
    }

    private fun optionsFromJs(options: JsAny?): EnhanceOptions {
        val cjk = optionString(options, "cjkFontFamily")
        val latin = optionString(options, "latinFontFamily")
        val monospace = optionString(options, "monospaceFontFamily")
        val cjkSerif = optionString(options, "cjkSerifFontFamily")
        val latinSerif = optionString(options, "latinSerifFontFamily")
        val fontSize = optionFloat(options, "fontSize")
        val lineHeight = optionFloat(options, "lineHeight")
        val firstLineIndent = optionFloat(options, "firstLineIndentIc") ?: 0f
        val emphasisDotCenterOffsetEm = optionFloat(options, "emphasisDotCenterOffsetEm")
            ?: DEFAULT_EMPHASIS_DOT_CENTER_OFFSET_EM
        val paragraphSelector = optionString(options, "paragraphSelector") ?: DEFAULT_PARAGRAPH_SELECTOR
        val dashCapabilityObject = optionObject(options, "cjkDashCapability")
        val dashCapability = dashCapabilityObject?.let { capability ->
            WebCjkDashCapability(
                status = optionString(capability, "status") ?: "unavailable",
                sessionId = optionString(capability, "sessionId"),
                detail = optionString(capability, "detail"),
            )
        }
        return EnhanceOptions(
            fontFamilies = FontFamilyOptions(cjk, latin, monospace, cjkSerif, latinSerif),
            fontSize = fontSize,
            lineHeight = lineHeight,
            firstLineIndentIc = firstLineIndent,
            emphasisDotCenterOffsetEm = emphasisDotCenterOffsetEm,
            paragraphSelector = paragraphSelector,
            cjkDashCapability = dashCapability,
        )
    }

    private fun optionFloat(options: JsAny?, name: String): Float? {
        val value = optionNumber(options, name)
        return if (value.isFinite()) value.toFloat() else null
    }

    data class EnhanceOptions(
        val fontFamilies: FontFamilyOptions = FontFamilyOptions(),
        val fontSize: Float? = null,
        val lineHeight: Float? = null,
        val firstLineIndentIc: Float = 0f,
        val emphasisDotCenterOffsetEm: Float = DEFAULT_EMPHASIS_DOT_CENTER_OFFSET_EM,
        val paragraphSelector: String = DEFAULT_PARAGRAPH_SELECTOR,
        val cjkDashCapability: WebCjkDashCapability? = null,
    ) {
        lateinit var fonts: WebFontFamilies
            private set

        fun withRootDefaults(root: HTMLElement): EnhanceOptions {
            val inheritedFontFamily = computedStyle(root, "font-family").trim().takeIf { it.isNotBlank() }
            val resolvedCjk = fontFamilies.cjk ?: inheritedFontFamily ?: DEFAULT_CJK_FONT_FAMILY
            val resolvedLatin = fontFamilies.latin ?: inheritedFontFamily ?: DEFAULT_LATIN_FONT_FAMILY
            val resolved = copy(
                fontFamilies = fontFamilies.copy(
                    cjk = resolvedCjk,
                    latin = resolvedLatin,
                    monospace = fontFamilies.monospace ?: DEFAULT_MONOSPACE_FONT_FAMILY,
                    cjkSerif = fontFamilies.cjkSerif ?: DEFAULT_CJK_SERIF_FONT_FAMILY,
                    latinSerif = fontFamilies.latinSerif ?: DEFAULT_LATIN_SERIF_FONT_FAMILY,
                ),
            )
            resolved.fonts = WebFontFamilies(
                cjk = resolved.fontFamilies.cjk!!,
                latin = resolved.fontFamilies.latin!!,
                latinMonospace = resolved.fontFamilies.monospace!!,
                cjkSerif = resolved.fontFamilies.cjkSerif!!,
                latinSerif = resolved.fontFamilies.latinSerif!!,
            )
            return resolved
        }
    }

    data class FontFamilyOptions(
        val cjk: String? = null,
        val latin: String? = null,
        val monospace: String? = null,
        val cjkSerif: String? = null,
        val latinSerif: String? = null,
    )

    private data class RootState(
        val root: HTMLElement,
        val options: EnhanceOptions,
        val engine: ExplainableStubParagraphLayoutEngine,
        val paragraphs: MutableList<EnhancedParagraph>,
        val issues: MutableList<CapabilityIssue>,
    )

    private data class ProgressiveJob(
        val state: RootState,
        val candidates: List<HTMLElement>,
        val startedAt: Double,
        var nextIndex: Int = 0,
        var frameId: Int? = null,
        var maxSliceDuration: Double = 0.0,
    )

    private data class EnhancedParagraph(
        val source: HTMLElement,
        val originalContent: DocumentFragment,
        val lowered: LoweredParagraph,
        val originalRenderedAttribute: String?,
        val originalStyleAttribute: String?,
        val originalPosition: String,
        val originalPositionPriority: String,
        var lastWidth: Float? = null,
        var containingBlockApplied: Boolean = false,
        val hostStyleOverrides: MutableList<HostStyleOverride> = mutableListOf(),
    )

    private data class HostStyleOverride(
        val property: String,
        val appliedValue: String,
        val originalValue: String,
        val originalPriority: String,
    )

    data class CapabilityIssue(
        val name: String,
        val detail: String,
        val element: HTMLElement,
    ) {
        internal var markerCaptured: Boolean = false
        internal var originalNameAttribute: String? = null
        internal var originalDetailAttribute: String? = null
    }

    private fun ensureContainingBlock(paragraph: EnhancedParagraph) {
        if (paragraph.containingBlockApplied) return
        if (computedStyle(paragraph.source, "position").trim().lowercase() != "static") return
        paragraph.source.style.setProperty("position", "relative", "important")
        paragraph.containingBlockApplied = true
    }

    private fun ensureHostFlowStyles(paragraph: EnhancedParagraph) {
        if (paragraph.hostStyleOverrides.isNotEmpty()) return
        for ((property, value) in HOST_FLOW_STYLE_OVERRIDES) {
            paragraph.hostStyleOverrides += HostStyleOverride(
                property = property,
                appliedValue = value,
                originalValue = paragraph.source.style.getPropertyValue(property),
                originalPriority = paragraph.source.style.getPropertyPriority(property),
            )
            paragraph.source.style.setProperty(property, value, "important")
        }
    }

    private fun restoreParagraph(paragraph: EnhancedParagraph) {
        while (paragraph.source.firstChild != null) {
            paragraph.source.removeChild(paragraph.source.firstChild!!)
        }
        paragraph.source.appendChild(paragraph.originalContent)
        restoreAttribute(paragraph.source, "data-tq-rendered", paragraph.originalRenderedAttribute)
        if (paragraph.containingBlockApplied &&
            paragraph.source.style.getPropertyValue("position") == "relative" &&
            paragraph.source.style.getPropertyPriority("position") == "important"
        ) {
            if (paragraph.originalPosition.isEmpty()) {
                paragraph.source.style.removeProperty("position")
            } else {
                paragraph.source.style.setProperty(
                    "position",
                    paragraph.originalPosition,
                    paragraph.originalPositionPriority,
                )
            }
        }
        for (override in paragraph.hostStyleOverrides.asReversed()) {
            if (paragraph.source.style.getPropertyValue(override.property) != override.appliedValue ||
                paragraph.source.style.getPropertyPriority(override.property) != "important"
            ) {
                continue
            }
            if (override.originalValue.isEmpty()) {
                paragraph.source.style.removeProperty(override.property)
            } else {
                paragraph.source.style.setProperty(
                    override.property,
                    override.originalValue,
                    override.originalPriority,
                )
            }
        }
        paragraph.hostStyleOverrides.clear()
        if (paragraph.originalStyleAttribute == null) {
            removeEmptyStyleAttribute(paragraph.source)
        }
        paragraph.containingBlockApplied = false
    }

    private fun clearIssue(issue: CapabilityIssue) {
        if (!issue.markerCaptured) return
        restoreAttribute(issue.element, "data-tiqian-capability-issue", issue.originalNameAttribute)
        restoreAttribute(issue.element, "data-tiqian-capability-detail", issue.originalDetailAttribute)
        issue.markerCaptured = false
    }

    private fun restoreAttribute(element: HTMLElement, name: String, value: String?) {
        if (value == null) {
            element.removeAttribute(name)
        } else {
            element.setAttribute(name, value)
        }
    }

}

@OptIn(ExperimentalWasmJsInterop::class)
private object MarkdownParagraphLowerer {
    private val fontRoleClassifier = CjkFontRoleClassifier()
    private val graphemeSegmenter: JsAny? = createLowererGraphemeSegmenter()

    var lastIssue: TiqianWeb.CapabilityIssue? = null
        private set

    fun lower(paragraph: HTMLElement, options: TiqianWeb.EnhanceOptions): LoweredParagraph? {
        lastIssue = null
        val fallbackStyle = TextStyle(fontSize = DEFAULT_FONT_SIZE)
        val computedParagraphStyle = computedTextStyle(paragraph, fallbackStyle)
        val fontSize = options.fontSize ?: computedParagraphStyle.fontSize
        val baseStyle = computedParagraphStyle.copy(fontSize = fontSize)
        val lineHeight = options.lineHeight
            ?: parseCssLineHeight(computedStyle(paragraph, "line-height"), fontSize)
            ?: fontSize * DEFAULT_LINE_HEIGHT_MULTIPLIER
        val baseInlineStyle = InlineStyle(
            textStyle = baseStyle,
            whiteSpace = cssWhiteSpaceMode(computedStyle(paragraph, "white-space")),
        )
        val builder = LoweringBuilder(paragraph, baseInlineStyle, lineHeight)
        if (!builder.appendChildren(paragraph, baseInlineStyle, depth = 0)) {
            return null
        }
        val lowered = builder.build()
        if (lowered.text.isBlank()) {
            lastIssue = TiqianWeb.CapabilityIssue("EmptyParagraph", "paragraph has no text", paragraph)
            return null
        }
        return lowered
    }

    private class LoweringBuilder(
        private val sourceElement: HTMLElement,
        private val baseInlineStyle: InlineStyle,
        private val baseLineHeight: Float,
    ) {
        val text = StringBuilder()
        private val spans = mutableListOf<TextSpan>()
        private val decorations = mutableListOf<DecorationSpan>()
        private val inlineBoxes = mutableListOf<InlineBoxSpan>()
        private val inlineObjects = mutableListOf<InlineObjectSpan>()
        private val domInlineObjects = mutableListOf<DomInlineObject>()
        private val sourceSpans = mutableListOf<DomSourceSpan>()
        private val sourceBoundaries = linkedSetOf<Int>()
        private val whitespaceModes = mutableListOf<CssWhiteSpaceMode>()
        private val hardBreakOffsets = linkedSetOf<Int>()

        fun appendChildren(element: Element, style: InlineStyle, depth: Int): Boolean {
            val nodes = element.childNodes
            for (i in 0 until nodes.length) {
                val node = nodes.item(i) ?: continue
                if (!appendNode(node, style, depth)) return false
            }
            return true
        }

        private fun appendNode(node: Node, style: InlineStyle, depth: Int): Boolean {
            return when (node.nodeType) {
                Node.TEXT_NODE -> {
                    appendText(node.textContent ?: "", style)
                    true
                }
                Node.ELEMENT_NODE -> appendElement(node as Element, style, depth)
                else -> true
            }
        }

        private fun appendElement(element: Element, style: InlineStyle, depth: Int): Boolean {
            val tag = element.tagName.uppercase()
            if (tag == "BR") {
                hardBreakOffsets += text.length
                appendRawText("\n", style.whiteSpace)
                return true
            }
            val display = computedStyle(element, "display").trim().lowercase()
            val opaqueCandidate = tag in NON_TEXT_INLINE_TAGS ||
                tag.contains('-') ||
                display in OPAQUE_INLINE_DISPLAYS
            if (opaqueCandidate) {
                if (display !in OPAQUE_INLINE_LEVEL_DISPLAYS) {
                    return unsupported(
                        "UnsupportedInlineFormattingContext",
                        "${tag.lowercase()}:$display",
                    )
                }
                if (!isCloneSafeOpaqueInlineObject(element)) {
                    return unsupported("UnsupportedStatefulInlineObject", tag.lowercase())
                }
                return appendOpaqueInlineObject(element, style.whiteSpace)
            }
            if (display != "inline" && display != "contents") {
                return unsupported(
                    "UnsupportedInlineFormattingContext",
                    "${tag.lowercase()}:$display",
                )
            }
            val inheritedStrongWeight = style.cjkStrongBaseWeight
            val strongBaseWeight = if (tag == "STRONG") {
                inheritedStrongWeight ?: style.textStyle.fontWeight
            } else {
                null
            }
            val elementStyle = computedInlineStyle(element, style).let { computed ->
                if (tag == "STRONG") {
                    computed.copy(cjkStrongBaseWeight = strongBaseWeight)
                } else {
                    computed
                }
            }
            return appendSemantic(element, elementStyle, depth, strongBaseWeight)
        }

        private fun appendOpaqueInlineObject(
            element: Element,
            whiteSpace: CssWhiteSpaceMode,
        ): Boolean {
            val geometry = parseOpaqueInlineObjectGeometry(measuredOpaqueInlineObjectGeometry(element))
                ?: return unsupported("InvalidInlineObjectGeometry", element.tagName.lowercase())
            val start = text.length
            appendRawText(INLINE_OBJECT_REPLACEMENT_CHAR.toString(), whiteSpace)
            val range = TextRange(start, text.length)
            sourceBoundaries += range.start
            sourceBoundaries += range.end
            inlineObjects += InlineObjectSpan(
                range = range,
                advance = geometry.advance,
                ascent = geometry.ascent,
                descent = geometry.descent,
            )
            domInlineObjects += DomInlineObject(
                range = range,
                element = element,
                marginRight = parseCssPx(computedStyle(element, "margin-right")) ?: 0f,
            )
            return true
        }

        private fun appendSemantic(
            element: Element,
            style: InlineStyle,
            depth: Int,
            cjkStrongBaseWeight: Int?,
        ): Boolean {
            val inlineStart = measuredInlineEdge(element, "start").toFloat()
            val inlineEnd = measuredInlineEdge(element, "end").toFloat()
            if (!inlineStart.isFinite() || !inlineEnd.isFinite()) {
                return unsupported("InvalidInlineBoxGeometry", element.tagName.lowercase())
            }
            val start = text.length
            if (!appendChildren(element, style, depth + 1)) return false
            val end = text.length
            if (end > start) {
                val range = TextRange(start, end)
                sourceBoundaries += start
                sourceBoundaries += end
                if (kotlin.math.abs(inlineStart) >= INLINE_EDGE_EPSILON ||
                    kotlin.math.abs(inlineEnd) >= INLINE_EDGE_EPSILON
                ) {
                    inlineBoxes += InlineBoxSpan(
                        range = range,
                        inlineStart = inlineStart,
                        inlineEnd = inlineEnd,
                    )
                }
                sourceSpans += DomSourceSpan(
                    range = range,
                    element = element,
                    depth = depth,
                    cjkStrongBaseWeight = cjkStrongBaseWeight,
                    computedColor = computedStyle(element, "color").takeIf { it.isNotBlank() },
                    inlineBoxStyle = DomInlineBoxStyle(
                        inlineStart = inlineStart,
                        inlineEnd = inlineEnd,
                        marginRight = parseCssPx(computedStyle(element, "margin-right")) ?: 0f,
                        letterSpacing = parseCssPx(computedStyle(element, "letter-spacing")) ?: 0f,
                        boxDecorationBreak = computedStyle(element, "box-decoration-break")
                            .trim()
                            .lowercase(),
                    ),
                )
            }
            return true
        }

        private fun unsupported(name: String, detail: String): Boolean {
            lastIssue = TiqianWeb.CapabilityIssue(name, detail, sourceElement)
            return false
        }

        private fun appendText(value: String, style: InlineStyle) {
            if (value.isEmpty()) return
            val strongBaseWeight = style.cjkStrongBaseWeight
            if (strongBaseWeight == null) {
                appendTextSegment(value, style.textStyle, style.whiteSpace, emphasis = false)
                return
            }

            val boundaries = lowererGraphemeBoundaries(graphemeSegmenter, value)
                .split(',')
                .mapNotNull(String::toIntOrNull)
                .filter { it in 0..value.length }
                .distinct()
                .sorted()
                .let { offsets ->
                    buildList {
                        if (offsets.firstOrNull() != 0) add(0)
                        addAll(offsets)
                        if (lastOrNull() != value.length) add(value.length)
                    }
                }
            var runStart = boundaries.first()
            var runIsCjk = false
            var hasRun = false
            for ((start, end) in boundaries.zipWithNext()) {
                if (end <= start) continue
                val role = fontRoleClassifier.classify(
                    value,
                    TextRange(start, end),
                    FontRoleContext(locale = style.textStyle.locale),
                )
                val isCjk = role == FontRole.CjkText || role == FontRole.CjkPunctuation
                if (hasRun && isCjk != runIsCjk) {
                    appendStrongTextSegment(value.substring(runStart, start), style, runIsCjk, strongBaseWeight)
                    runStart = start
                }
                runIsCjk = isCjk
                hasRun = true
            }
            if (hasRun && runStart < value.length) {
                appendStrongTextSegment(value.substring(runStart), style, runIsCjk, strongBaseWeight)
            }
        }

        private fun appendStrongTextSegment(
            value: String,
            style: InlineStyle,
            isCjk: Boolean,
            strongBaseWeight: Int,
        ) {
            val textStyle = if (isCjk) {
                style.textStyle.copy(fontWeight = strongBaseWeight)
            } else {
                style.textStyle
            }
            appendTextSegment(value, textStyle, style.whiteSpace, emphasis = isCjk)
        }

        private fun appendTextSegment(
            value: String,
            style: TextStyle,
            whiteSpace: CssWhiteSpaceMode,
            emphasis: Boolean,
        ) {
            if (value.isEmpty()) return
            val start = text.length
            appendRawText(value, whiteSpace)
            val end = text.length
            if (style != baseInlineStyle.textStyle) {
                spans += TextSpan(
                    TextRange(start, end),
                    style,
                )
                sourceBoundaries += start
                sourceBoundaries += end
            }
            if (emphasis) {
                decorations += DecorationSpan(TextRange(start, end), DecorationKind.Emphasis)
                sourceBoundaries += start
                sourceBoundaries += end
            }
        }

        private fun appendRawText(value: String, whiteSpace: CssWhiteSpaceMode) {
            text.append(value)
            repeat(value.length) { whitespaceModes += whiteSpace }
        }

        fun build(): LoweredParagraph {
            val projection = cssWhiteSpaceCollapseProjection(
                text = text.toString(),
                modes = whitespaceModes,
                hardBreakOffsets = hardBreakOffsets,
            )
            return LoweredParagraph(
                text = projection.text,
                textStyle = baseInlineStyle.textStyle,
                lineHeight = baseLineHeight,
                spans = spans.mapNotNull { span ->
                    projection.range(span.range)?.let { span.copy(range = it) }
                },
                decorations = decorations.mapNotNull { span ->
                    projection.range(span.range)?.let { span.copy(range = it) }
                },
                inlineBoxes = inlineBoxes.mapNotNull { span ->
                    projection.range(span.range)?.let { span.copy(range = it) }
                },
                inlineObjects = inlineObjects.mapNotNull { span ->
                    projection.range(span.range)?.let { span.copy(range = it) }
                },
                domInlineObjects = domInlineObjects.mapNotNull { inlineObject ->
                    projection.range(inlineObject.range)?.let { inlineObject.copy(range = it) }
                },
                sourceSpans = sourceSpans.mapNotNull { span ->
                    projection.range(span.range)?.let { span.copy(range = it) }
                },
                sourceBoundaries = sourceBoundaries
                    .map(projection::boundary)
                    .filter { it > 0 && it < projection.text.length }
                    .toSet(),
            )
        }
    }
}

data class LoweredParagraph(
    val text: String,
    val textStyle: TextStyle,
    val lineHeight: Float,
    val spans: List<TextSpan>,
    val decorations: List<DecorationSpan>,
    val inlineBoxes: List<InlineBoxSpan>,
    val inlineObjects: List<InlineObjectSpan>,
    val domInlineObjects: List<DomInlineObject>,
    val sourceSpans: List<DomSourceSpan>,
    val sourceBoundaries: Set<Int>,
)

data class DomInlineObject(
    val range: TextRange,
    val element: Element,
    val marginRight: Float = 0f,
)

data class DomSourceSpan(
    val range: TextRange,
    val element: Element,
    val depth: Int,
    val cjkStrongBaseWeight: Int? = null,
    val computedColor: String? = null,
    val inlineBoxStyle: DomInlineBoxStyle = DomInlineBoxStyle(),
)

data class DomInlineBoxStyle(
    val inlineStart: Float = 0f,
    val inlineEnd: Float = 0f,
    val marginRight: Float = 0f,
    val letterSpacing: Float = 0f,
    val boxDecorationBreak: String = "slice",
)

data class CssRenderStyleSpan(
    val range: TextRange,
    val style: CssRenderStyle,
)

data class CssRenderStyle(
    val color: String? = null,
    val backgroundColor: String? = null,
    val textDecorationLine: String? = null,
    val textDecorationColor: String? = null,
    val textDecorationStyle: String? = null,
    val textDecorationThickness: String? = null,
    val textUnderlineOffset: String? = null,
)

private data class InlineStyle(
    val textStyle: TextStyle,
    val whiteSpace: CssWhiteSpaceMode,
    val cjkStrongBaseWeight: Int? = null,
)

/**
 * CssWhiteSpaceCollapseProjection: DOM source formatting is projected through
 * the host's `white-space` semantics before it becomes Tiqian source text.
 * Only a real `<br>` is marked separately as a structural mandatory break.
 */
private enum class CssWhiteSpaceMode {
    Collapse,
    CollapsePreserveBreaks,
    Preserve,
}

private data class CssWhiteSpaceProjection(
    val text: String,
    private val boundaryMap: IntArray,
) {
    fun boundary(sourceOffset: Int): Int = boundaryMap[sourceOffset]

    fun range(sourceRange: TextRange): TextRange? {
        val start = boundary(sourceRange.start)
        val end = boundary(sourceRange.end)
        return if (end > start) TextRange(start, end) else null
    }
}

private fun cssWhiteSpaceCollapseProjection(
    text: String,
    modes: List<CssWhiteSpaceMode>,
    hardBreakOffsets: Set<Int>,
): CssWhiteSpaceProjection {
    require(modes.size == text.length) {
        "Whitespace mode count ${modes.size} must match source length ${text.length}"
    }
    require(hardBreakOffsets.all { it in text.indices && text[it] == '\n' }) {
        "Structural hard-break offsets must point at source newlines"
    }

    val projected = StringBuilder(text.length)
    val boundaryMap = IntArray(text.length + 1)
    var pendingStart = -1
    var pendingEnd = -1

    fun resolvePendingWhitespace(emit: Boolean) {
        if (pendingStart < 0) return
        val before = projected.length
        if (emit && projected.isNotEmpty() && projected.last() != '\n') {
            projected.append(' ')
        }
        val after = projected.length
        boundaryMap[pendingStart] = before
        for (boundary in (pendingStart + 1)..pendingEnd) {
            boundaryMap[boundary] = after
        }
        pendingStart = -1
        pendingEnd = -1
    }

    fun deferCollapsedWhitespace(index: Int) {
        if (pendingStart < 0) {
            pendingStart = index
            boundaryMap[index] = projected.length
        }
        pendingEnd = index + 1
    }

    fun appendPreserved(index: Int, char: Char) {
        resolvePendingWhitespace(emit = true)
        boundaryMap[index] = projected.length
        projected.append(char)
        boundaryMap[index + 1] = projected.length
    }

    var index = 0
    while (index < text.length) {
        if (index in hardBreakOffsets) {
            resolvePendingWhitespace(emit = false)
            boundaryMap[index] = projected.length
            projected.append('\n')
            boundaryMap[index + 1] = projected.length
            index += 1
            continue
        }

        val char = text[index]
        when (modes[index]) {
            CssWhiteSpaceMode.Collapse -> {
                if (char.isCssCollapsibleWhitespace()) {
                    deferCollapsedWhitespace(index)
                } else {
                    appendPreserved(index, char)
                }
                index += 1
            }

            CssWhiteSpaceMode.CollapsePreserveBreaks -> {
                if (char == '\r' || char == '\n') {
                    resolvePendingWhitespace(emit = false)
                    boundaryMap[index] = projected.length
                    projected.append('\n')
                    boundaryMap[index + 1] = projected.length
                    if (
                        char == '\r' &&
                        index + 1 < text.length &&
                        text[index + 1] == '\n' &&
                        modes[index + 1] == CssWhiteSpaceMode.CollapsePreserveBreaks &&
                        index + 1 !in hardBreakOffsets
                    ) {
                        boundaryMap[index + 2] = projected.length
                        index += 2
                    } else {
                        index += 1
                    }
                } else if (char.isCssCollapsibleWhitespace()) {
                    deferCollapsedWhitespace(index)
                    index += 1
                } else {
                    appendPreserved(index, char)
                    index += 1
                }
            }

            CssWhiteSpaceMode.Preserve -> {
                if (char == '\r') {
                    resolvePendingWhitespace(emit = true)
                    boundaryMap[index] = projected.length
                    projected.append('\n')
                    boundaryMap[index + 1] = projected.length
                    if (
                        index + 1 < text.length &&
                        text[index + 1] == '\n' &&
                        modes[index + 1] == CssWhiteSpaceMode.Preserve &&
                        index + 1 !in hardBreakOffsets
                    ) {
                        boundaryMap[index + 2] = projected.length
                        index += 2
                    } else {
                        index += 1
                    }
                } else {
                    appendPreserved(index, char)
                    index += 1
                }
            }
        }
    }
    resolvePendingWhitespace(emit = false)
    boundaryMap[text.length] = projected.length
    return CssWhiteSpaceProjection(projected.toString(), boundaryMap)
}

private fun Char.isCssCollapsibleWhitespace(): Boolean =
    this == ' ' || this == '\t' || this == '\n' || this == '\r' || this == '\u000C'

private fun cssWhiteSpaceMode(
    value: String,
    fallback: CssWhiteSpaceMode = CssWhiteSpaceMode.Collapse,
): CssWhiteSpaceMode {
    val normalized = value.trim().lowercase()
    return when {
        normalized == "normal" || normalized == "nowrap" ||
            normalized == "collapse" || normalized.startsWith("collapse ") -> CssWhiteSpaceMode.Collapse
        normalized == "pre-line" || normalized.startsWith("preserve-breaks") ->
            CssWhiteSpaceMode.CollapsePreserveBreaks
        normalized == "pre" || normalized == "pre-wrap" || normalized == "break-spaces" ||
            normalized.startsWith("preserve ") -> CssWhiteSpaceMode.Preserve
        else -> fallback
    }
}

private data class OpaqueInlineObjectGeometry(
    val advance: Float,
    val ascent: Float,
    val descent: Float,
)

private fun parseOpaqueInlineObjectGeometry(value: String): OpaqueInlineObjectGeometry? {
    val parts = value.split(',').mapNotNull(String::toFloatOrNull)
    if (parts.size != 3) return null
    val (advance, ascent, descent) = parts
    if (!advance.isFinite() || advance <= INLINE_EDGE_EPSILON) return null
    if (!ascent.isFinite() || ascent < 0f || !descent.isFinite() || descent < 0f) return null
    if (ascent + descent <= INLINE_EDGE_EPSILON) return null
    return OpaqueInlineObjectGeometry(advance, ascent, descent)
}

private fun computedTextStyle(element: Element, fallback: TextStyle): TextStyle {
    val fontFamilies = parseCssFontFamilies(computedStyle(element, "font-family"))
        .takeIf { it.isNotEmpty() }
        ?: fallback.fontFamilies
    val fontSize = parseCssPx(computedStyle(element, "font-size")) ?: fallback.fontSize
    val fontWeight = parseCssFontWeight(computedStyle(element, "font-weight")) ?: fallback.fontWeight
    val italic = parseCssItalic(computedStyle(element, "font-style")) ?: fallback.italic
    return fallback.copy(
        fontFamilies = fontFamilies,
        fontSize = fontSize,
        fontWeight = fontWeight,
        italic = italic,
    )
}

private fun computedInlineStyle(element: Element, fallback: InlineStyle): InlineStyle {
    val computed = computedTextStyle(element, fallback.textStyle)
    val localBaselineShift = computedInlineBaselineShift(element)
    return InlineStyle(
        textStyle = computed.copy(
            baselineShift = fallback.textStyle.baselineShift + localBaselineShift,
        ),
        whiteSpace = cssWhiteSpaceMode(
            computedStyle(element, "white-space"),
            fallback.whiteSpace,
        ),
        cjkStrongBaseWeight = fallback.cjkStrongBaseWeight,
    )
}

private fun computedInlineBaselineShift(element: Element): Float {
    var relativeShift = 0f
    if (computedStyle(element, "position").trim().lowercase() == "relative") {
        val top = parseCssPx(computedStyle(element, "top"))
        val bottom = parseCssPx(computedStyle(element, "bottom"))
        relativeShift = top ?: bottom?.let { -it } ?: 0f
    }
    val verticalAlign = computedStyle(element, "vertical-align").trim().lowercase()
    return when {
        verticalAlign.isBlank() || verticalAlign == "baseline" -> relativeShift
        parseCssPx(verticalAlign) != null -> relativeShift - parseCssPx(verticalAlign)!!
        else -> measuredInlineBaselineShift(element).toFloat().takeIf { it.isFinite() } ?: 0f
    }
}

private fun parseCssFontFamilies(value: String): List<String> {
    val families = mutableListOf<String>()
    val token = StringBuilder()
    var quote: Char? = null

    fun flush() {
        val family = token.toString().trim().removeSurrounding("\"").removeSurrounding("'")
        if (family.isNotEmpty()) families += family
        token.clear()
    }

    for (char in value) {
        when {
            quote != null && char == quote -> {
                quote = null
                token.append(char)
            }
            quote != null -> token.append(char)
            char == '\'' || char == '"' -> {
                quote = char
                token.append(char)
            }
            char == ',' -> flush()
            else -> token.append(char)
        }
    }
    flush()
    return families
}

private fun parseCssPx(value: String): Float? {
    val trimmed = value.trim()
    if (!trimmed.endsWith("px")) return null
    return trimmed.removeSuffix("px").trim().toFloatOrNull()
}

private fun parseCssLineHeight(value: String, fontSize: Float): Float? {
    val trimmed = value.trim()
    parseCssPx(trimmed)?.let { return it }
    return trimmed.toFloatOrNull()?.let { it * fontSize }
}

private fun parseCssFontWeight(value: String): Int? {
    val trimmed = value.trim().lowercase()
    return when (trimmed) {
        "normal" -> 400
        "bold" -> 700
        "lighter", "bolder" -> null
        else -> trimmed.toFloatOrNull()?.toInt()?.coerceIn(1, 900)
    }
}

private fun parseCssItalic(value: String): Boolean? {
    val trimmed = value.trim().lowercase()
    if (trimmed.isBlank()) return null
    return trimmed.startsWith("italic") || trimmed.startsWith("oblique")
}

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(event) => event.detail && event.detail.root ? event.detail.root : null")
private external fun eventRoot(event: Event): HTMLElement?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(event) => event.detail && event.detail.options ? event.detail.options : null")
private external fun eventOptions(event: Event): JsAny?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(options, name) => options && options[name] != null ? String(options[name]) : null")
private external fun optionString(options: JsAny?, name: String): String?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(options, name) => { if (!options || options[name] == null) return NaN; const number = Number(options[name]); return Number.isFinite(number) ? number : NaN; }")
private external fun optionNumber(options: JsAny?, name: String): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(options, name) => options && options[name] && typeof options[name] === 'object' ? options[name] : null")
private external fun optionObject(options: JsAny?, name: String): JsAny?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => element.getBoundingClientRect().width")
private external fun elementWidth(element: HTMLElement): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(element, side) => {
      const style = getComputedStyle(element);
      const margin = Number.parseFloat(
        side === "start" ? style.marginLeft : style.marginRight
      ) || 0;
      const boxes = Array.from(element.getClientRects()).filter((rect) => rect.width || rect.height);
      if (!boxes.length) return margin;
      const range = document.createRange();
      range.selectNodeContents(element);
      const content = Array.from(range.getClientRects()).filter((rect) => rect.width || rect.height);
      if (!content.length) return margin;
      const edge = side === "start"
        ? Math.max(0, content[0].left - boxes[0].left)
        : Math.max(0, boxes[boxes.length - 1].right - content[content.length - 1].right);
      return edge + margin;
    }""",
)
private external fun measuredInlineEdge(element: Element, side: String): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(element) => {
      if (!element.parentNode || getComputedStyle(element).display === "contents") return 0;
      const makeProbe = () => {
        const probe = document.createElement("span");
        probe.setAttribute("data-tq-baseline-probe", "");
        probe.style.cssText = "display:inline-block!important;width:0!important;height:0!important;" +
          "margin:0!important;padding:0!important;border:0!important;font-size:0!important;" +
          "line-height:0!important;vertical-align:baseline!important;position:static!important;";
        return probe;
      };
      const outer = makeProbe();
      const inner = makeProbe();
      try {
        element.parentNode.insertBefore(outer, element);
        element.insertBefore(inner, element.firstChild);
        return inner.getBoundingClientRect().bottom - outer.getBoundingClientRect().bottom;
      } finally {
        inner.remove();
        outer.remove();
      }
    }""",
)
private external fun measuredInlineBaselineShift(element: Element): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(element) => {
      const parent = element.parentNode;
      if (!parent) return "";
      const style = getComputedStyle(element);
      if (style.position === "absolute" || style.position === "fixed" ||
          style.getPropertyValue("float") !== "none" || style.transform !== "none") return "";
      const rect = element.getBoundingClientRect();
      if (!Number.isFinite(rect.width) || !Number.isFinite(rect.height) ||
          rect.width <= 0 || rect.height <= 0) return "";
      const number = (value) => Number.parseFloat(value) || 0;
      const probe = document.createElement("span");
      probe.setAttribute("data-tq-baseline-probe", "");
      probe.style.cssText = "display:inline-block!important;width:0!important;height:0!important;" +
        "margin:0!important;padding:0!important;border:0!important;font-size:0!important;" +
        "line-height:0!important;vertical-align:baseline!important;position:static!important;";
      try {
        parent.insertBefore(probe, element.nextSibling);
        const baseline = probe.getBoundingClientRect().bottom;
        const advance = rect.width + number(style.marginLeft) + number(style.marginRight);
        const ascent = Math.max(0, baseline - rect.top + number(style.marginTop));
        const descent = Math.max(0, rect.bottom - baseline + number(style.marginBottom));
        return [advance, ascent, descent].join(",");
      } finally {
        probe.remove();
      }
    }""",
)
private external fun measuredOpaqueInlineObjectGeometry(element: Element): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(element) => {
      if (element.hasAttribute("data-tiqian-static-inline-object")) return true;
      const name = element.localName || "";
      if (name.includes("-")) return false;
      const interactive = "a,button,input,select,textarea,iframe,object,embed,audio,video,canvas,[contenteditable='true'],[tabindex]";
      if (element.matches(interactive) || element.querySelector(interactive)) return false;
      const nodes = [element, ...element.querySelectorAll("*")];
      return !nodes.some((node) => Array.from(node.attributes || []).some((attr) =>
        attr.name.toLowerCase().startsWith("on")
      ));
    }""",
)
private external fun isCloneSafeOpaqueInlineObject(element: Element): Boolean

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyle(element: Element, property: String): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => { if (!(element.getAttribute('style') || '').trim()) element.removeAttribute('style'); }")
private external fun removeEmptyStyleAttribute(element: HTMLElement)

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """() => typeof Intl !== 'undefined' && Intl.Segmenter
      ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
      : null""",
)
private external fun createLowererGraphemeSegmenter(): JsAny?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(segmenter, text) => {
      const boundaries = [0];
      if (segmenter) {
        for (const item of segmenter.segment(text)) {
          if (item.index > 0) boundaries.push(item.index);
        }
      } else {
        let offset = 0;
        for (const point of Array.from(text)) {
          offset += point.length;
          if (offset < text.length) boundaries.push(offset);
        }
      }
      boundaries.push(text.length);
      return boundaries.join(',');
    }""",
)
private external fun lowererGraphemeBoundaries(segmenter: JsAny?, text: String): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, selector) => !!element.closest(selector)")
private external fun hasClosest(element: HTMLElement, selector: String): Boolean

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    "(paragraph, root, selector) => { const owner = paragraph.closest(selector); return !owner || owner === root || !root.contains(owner); }",
)
private external fun belongsToRootScope(paragraph: HTMLElement, root: HTMLElement, selector: String): Boolean

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(message) => console.warn(message)")
private external fun consoleWarn(message: String)

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("() => performance.now()")
private external fun performanceNow(): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(root, enhancedCount, issueCount, durationMs, maxSliceMs) => root.dispatchEvent(new CustomEvent('tiqian:ready', { detail: { enhancedCount, issueCount, durationMs, maxSliceMs } }))")
private external fun dispatchTiqianReady(
    root: HTMLElement,
    enhancedCount: Int,
    issueCount: Int,
    durationMs: Double,
    maxSliceMs: Double,
)

@OptIn(ExperimentalWasmJsInterop::class)
private fun installTiqianGlobalApiBridge() {
    js(
        """
        if (!globalThis.TiqianWeb || !globalThis.TiqianWeb.__tiqianKotlinBridge) {
          globalThis.TiqianWeb = {
            __tiqianKotlinBridge: true,
            enhance(root, options) {
              document.dispatchEvent(new CustomEvent("tiqian:enhance", {
                detail: { root: root || document.body, options: options || {} }
              }));
              return root || document.body;
            },
            enhanceProgressively(root, options) {
              document.dispatchEvent(new CustomEvent("tiqian:enhance-progressively", {
                detail: { root: root || document.body, options: options || {} }
              }));
              return root || document.body;
            },
            destroy(root) {
              document.dispatchEvent(new CustomEvent("tiqian:destroy", {
                detail: { root: root || document.body }
              }));
            },
            enhanceAll(options) {
              document.dispatchEvent(new CustomEvent("tiqian:enhance-all", {
                detail: { options: options || {} }
              }));
            }
          };
        }
        """,
    )
}

@OptIn(ExperimentalWasmJsInterop::class)
private fun installTiqianCopyHandler() {
    js(
        """
        if (!globalThis.__tiqianCopyHandlerInstalled) {
          globalThis.__tiqianCopyHandlerInstalled = true;
          document.addEventListener("copy", function (e) {
            var sel = window.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
            var range = sel.getRangeAt(0);
            var renderedAncestor = function (node) {
              var element = node && node.nodeType === 1 ? node : node && node.parentElement;
              return element && element.closest ? element.closest("[data-tq-rendered]") : null;
            };
            var touchesRendered = !!renderedAncestor(range.startContainer) ||
              !!renderedAncestor(range.endContainer);
            if (!touchesRendered) {
              var common = range.commonAncestorContainer;
              var commonElement = common && common.nodeType === 1 ? common : common && common.parentElement;
              var candidates = commonElement && commonElement.querySelectorAll
                ? Array.from(commonElement.querySelectorAll("[data-tq-rendered]"))
                : [];
              if (commonElement && commonElement.matches && commonElement.matches("[data-tq-rendered]")) {
                candidates.unshift(commonElement);
              }
              touchesRendered = candidates.some(function (candidate) {
                try { return range.intersectsNode(candidate); } catch (_) { return false; }
              });
            }
            if (!touchesRendered) return;
            var frag = range.cloneContents();
            if (!frag.querySelectorAll) return;
            frag.querySelectorAll("[data-tq-copy-ignore]").forEach(function (el) {
              el.remove();
            });
            frag.querySelectorAll("[data-tq-src]").forEach(function (el) {
              el.textContent = el.getAttribute("data-tq-src");
            });
            var text = frag.textContent;
            if (text && e.clipboardData) {
              e.clipboardData.setData("text/plain", text);
              e.preventDefault();
            }
          });
        }
        """,
    )
}

private const val DEFAULT_FONT_SIZE = 19f
private const val INLINE_EDGE_EPSILON = 0.01f
private const val ZERO_ADVANCE_EPSILON = 0.01f
private const val CAPABILITY_DETAIL_LIMIT = 512
private const val MAX_PROGRESSIVE_SLICE_MS = 8.0
private const val DEFAULT_LINE_HEIGHT_MULTIPLIER = 1.75f
private const val DEFAULT_CJK_FONT_FAMILY = "\"MiSans VF\", \"PingFang SC\", \"Noto Sans CJK SC\", sans-serif"
private const val DEFAULT_LATIN_FONT_FAMILY = "\"InterVariable\", \"Inter\", \"MiSans VF\", sans-serif"
private const val DEFAULT_MONOSPACE_FONT_FAMILY =
    "\"JetBrains Mono Variable\", \"SFMono-Regular\", Menlo, Consolas, \"MiSans VF\", monospace"
private const val DEFAULT_CJK_SERIF_FONT_FAMILY = "\"MetroSungPlus-SC\", \"Songti SC\", serif"
private const val DEFAULT_LATIN_SERIF_FONT_FAMILY = "Georgia, \"Times New Roman\", serif"

private val HOST_FLOW_STYLE_OVERRIDES = listOf(
    "white-space-collapse" to "preserve",
    "overflow-wrap" to "normal",
    "text-autospace" to "no-autospace",
    "text-wrap-mode" to "nowrap",
    "-webkit-hyphens" to "manual",
    "hyphens" to "manual",
    "word-break" to "normal",
)

private val NON_TEXT_INLINE_TAGS = setOf(
    "AREA",
    "AUDIO",
    "BUTTON",
    "CANVAS",
    "EMBED",
    "IFRAME",
    "IMG",
    "INPUT",
    "MATH",
    "OBJECT",
    "PICTURE",
    "SCRIPT",
    "SELECT",
    "STYLE",
    "SVG",
    "TEMPLATE",
    "TEXTAREA",
    "VIDEO",
)

private val OPAQUE_INLINE_DISPLAYS = setOf("inline-block", "inline-flex", "inline-grid")
private val OPAQUE_INLINE_LEVEL_DISPLAYS = OPAQUE_INLINE_DISPLAYS + "inline"
