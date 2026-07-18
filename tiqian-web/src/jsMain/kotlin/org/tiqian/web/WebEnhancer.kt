@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web

import kotlin.JsFun
import kotlin.js.JsAny
import kotlin.js.js
import kotlinx.browser.document
import kotlinx.browser.window
import org.tiqian.core.ColorSpan
import org.tiqian.core.DEFAULT_EMPHASIS_DOT_GAP_EM
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.Ic
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.INLINE_OBJECT_REPLACEMENT_CHAR
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.layout.toPreparedParagraphJson
import org.tiqian.shaping.HarfBuzzSessionFontMetricsResolver
import org.tiqian.shaping.HarfBuzzSessionTextShaper
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FontRole
import org.tiqian.font.FontRoleContext
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
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
object TiqianWeb {
    private const val ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]"
    private const val DEFAULT_PARAGRAPH_SELECTOR = "p, li"
    private const val SKIPPED_ANCESTOR_SELECTOR =
        ".not-prose, pre, table, .katex, .katex-display, .expressive-code, .tq-paragraph, [data-tiqian-skip]"

    private var installed = false
    // DetachedRootWeakOwnership: navigation can discard a rendered article
    // without reconstructing its semantic DOM. Weak ownership retains the
    // source fragments only if a host later reconnects that exact element.
    private val states: dynamic = js("new WeakMap()")
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
        document.addEventListener("tiqian:detach", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            detach(root)
        })
        document.addEventListener("tiqian:enhance-all", { event: Event ->
            enhanceAll(optionsFromJs(eventOptions(event)))
        })
        document.addEventListener("tiqian:relayout", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            relayout(root)
        })
        document.addEventListener("tiqian:cancel-layout-work", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            cancelProgressiveJob(root)
        })
        document.addEventListener("tiqian:worker-layout-request", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            val paragraph = eventParagraph(event) ?: return@listener
            setEventResult(
                event,
                workerLayoutRequest(root, paragraph, optionsFromJs(eventOptions(event))),
            )
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
        val candidates = paragraphCandidates(root, state.options.paragraphSelector)
        if (rejectMissingSharedRuntimeStyles(state, candidates)) return 0
        for (paragraph in candidates) {
            processParagraph(paragraph, state)
        }
        publishState(state)
        return state.paragraphs.size
    }

    /**
     * Enhance viewport-near paragraphs first in bounded animation-frame slices.
     * Each paragraph is replaced atomically in the slice that prepared it; the
     * remaining paragraphs keep responsive semantic source DOM.
     */
    fun enhanceProgressively(root: HTMLElement, options: EnhanceOptions = EnhanceOptions()) =
        enhanceProgressively(root, options, ProgressiveJobKind.Enhance)

    private fun enhanceProgressively(
        root: HTMLElement,
        options: EnhanceOptions,
        kind: ProgressiveJobKind,
    ) {
        installTiqianCopyHandler()
        destroy(root)
        val state = createRootState(root, options)
        val sourceCandidates = paragraphCandidates(root, state.options.paragraphSelector)
        if (rejectMissingSharedRuntimeStyles(state, sourceCandidates)) return
        val candidates = sourceCandidates
            .withIndex()
            .sortedWith(
                compareBy<IndexedValue<HTMLElement>> {
                    paragraphViewportDistance(it.value)
                }.thenBy { it.index },
            )
            .map { it.value }
        val capturedMeasures = candidates.map { paragraph ->
            responsiveSourceMeasure(paragraph, state.options.fontSize)
        }
        var stale = false
        fun liveMeasure(index: Int): Float =
            responsiveSourceMeasure(candidates[index], state.options.fontSize)
        val job = ProgressiveJob(
            state = state,
            kind = kind,
            itemCount = candidates.size,
            processItem = { index ->
                if (liveMeasure(index) != capturedMeasures[index]) {
                    stale = true
                } else {
                    processParagraph(candidates[index], state)
                }
            },
            onItemsFinished = {
                stale = stale || candidates.indices.any { index ->
                    liveMeasure(index) != capturedMeasures[index]
                }
                if (stale) {
                    for (paragraph in state.paragraphs.asReversed()) restoreParagraph(paragraph)
                    for (issue in state.issues.asReversed()) clearIssue(issue)
                    state.paragraphs.clear()
                    state.issues.clear()
                }
            },
            stale = { stale },
            shouldScheduleIdle = { index ->
                candidates.getOrNull(index)?.let(::paragraphIsWithinProgressiveForegroundRange) == false
            },
            startedAt = performanceNow(),
        )
        states.set(root, state)
        publishState(state, keepEmpty = true)
        startProgressiveJob(job)
    }

    /**
     * SharedRuntimeStylesCapabilityGate: renderer-owned geometry depends on the
     * package stylesheet for its line strut, reset, and nowrap invariants. The
     * public ESM entry waits for that stylesheet; direct Kotlin callers must do
     * the same instead of silently painting a second browser-owned layout.
     */
    private fun rejectMissingSharedRuntimeStyles(
        state: RootState,
        candidates: List<HTMLElement>,
    ): Boolean {
        if (computedStyle(state.root, "--tq-styles-ready").trim() == "1") return false
        for (paragraph in candidates) {
            val issue = CapabilityIssue(
                name = "MissingSharedRuntimeStyles",
                detail = "Load @tiqian/prose/styles.css before TiqianWeb.enhance",
                element = paragraph,
            )
            state.issues += issue
            reportIssue(issue)
        }
        publishState(state)
        return true
    }

    fun destroy(root: HTMLElement) {
        cancelProgressiveJob(root)
        val state = states.get(root) as? RootState
        states.delete(root)
        if (state != null) {
            for (paragraph in state.paragraphs) {
                restoreParagraph(paragraph)
            }
            for (issue in state.issues) {
                clearIssue(issue)
            }
            // A precomputed snapshot may be live without a Kotlin runtime
            // state while list-only enhancement starts. Its compact value CSS
            // belongs to the snapshot owner and must survive that no-op destroy.
            releasePreparedRootDomStyles(root)
        }
        val snapshotCount = observableSnapshotCount(root)
        if (snapshotCount > 0) {
            root.setAttribute("data-tiqian-enhanced", "true")
            root.setAttribute("data-tiqian-enhanced-count", "$snapshotCount")
        } else {
            root.removeAttribute("data-tiqian-enhanced")
            root.removeAttribute("data-tiqian-enhanced-count")
        }
        root.removeAttribute("data-tiqian-issue-count")
        root.removeAttribute(RELAYOUT_ERROR_ATTRIBUTE)
        root.removeAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE)
    }

    /**
     * Cancels a detached root and releases its document-scoped value styles
     * without rebuilding paragraph DOM that the router is about to discard.
     * The weak state remains available to [destroy] if the same node reconnects.
     */
    fun detach(root: HTMLElement) {
        cancelProgressiveJob(root)
        releasePreparedRootDomStyles(root)
    }

    private fun createRootState(root: HTMLElement, options: EnhanceOptions): RootState {
        root.removeAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE)
        val exactEligibleOptions = if (options.allowsSnapshotExactLayout()) {
            options
        } else {
            options.copy(exactFontSession = null)
        }
        val resolved = exactEligibleOptions.withRootDefaults(root)
        val exactSessionId = resolved.conformingExactFontSessionId()
        val browserMetrics = WebCanvasFontMetricsResolver(resolved.fonts)
        val browserShaper = WebCanvasTextShaper(resolved.fonts, resolved.cjkDashCapability)
        val browserEngine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            fontMetricsResolver = browserMetrics,
            textShaper = browserShaper,
        )
        val exactMetrics = exactSessionId?.let(::HarfBuzzSessionFontMetricsResolver)
        val exactShaper = exactSessionId?.let(::HarfBuzzSessionTextShaper)
        val engine = if (exactMetrics != null && exactShaper != null) {
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                fontMetricsResolver = exactMetrics,
                textShaper = exactShaper,
            )
        } else {
            browserEngine
        }
        val semanticExactEngine = if (exactMetrics != null && exactShaper != null) {
            ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                fontMetricsResolver = ExactSessionBrowserFallbackFontMetricsResolver(
                    exact = exactMetrics,
                    browser = browserMetrics,
                ),
                textShaper = ExactSessionBrowserFallbackTextShaper(
                    exact = exactShaper,
                    browser = browserShaper,
                ),
            )
        } else {
            null
        }
        return RootState(
            root = root,
            options = resolved,
            engine = engine,
            semanticExactEngine = semanticExactEngine,
            browserFallbackEngine = browserEngine.takeIf { exactSessionId != null },
            paragraphs = mutableListOf(),
            issues = mutableListOf(),
        )
    }

    private fun paragraphCandidates(root: HTMLElement, selector: String): List<HTMLElement> {
        val nodes = root.querySelectorAll(selector)
        return buildList {
            for (i in 0 until nodes.length) {
                val paragraph = nodes.item(i) as? HTMLElement ?: continue
                // RuntimeEligibleMeasureSet: progressive staleness compares the
                // same leaf paragraphs that can actually enter the pipeline.
                // Measuring a host-owned outer <li> and later rendering its
                // child <p> changes the container's live width/measure, which
                // used to roll back every valid child as a false stale job.
                if (
                    belongsToRootScope(paragraph, root, ROOT_SELECTOR) &&
                    shouldTryParagraph(paragraph)
                ) add(paragraph)
            }
        }
    }

    /**
     * WorkerLayoutInputContract keeps DOM ownership on the main thread while
     * serializing only the immutable layout model. The Worker runs the existing
     * Lookahead engine against the already-proven exact replay session; any
     * unsupported semantic, decoration or inline object remains native when an
     * exact session is active; exact layout must never fall back to synchronous
     * Kotlin/JS on the navigation thread.
     */
    private fun workerLayoutRequest(
        root: HTMLElement,
        paragraph: HTMLElement,
        options: EnhanceOptions,
    ): String? {
        if (!belongsToRootScope(paragraph, root, ROOT_SELECTOR) || !shouldTryParagraph(paragraph)) {
            return null
        }
        if (!options.allowsSnapshotExactLayout()) return null
        val resolved = options.withRootDefaults(root)
        val lowered = try {
            MarkdownParagraphLowerer.lower(paragraph, resolved)
        } catch (_: Throwable) {
            null
        } ?: return null
        return workerLayoutRequest(paragraph, lowered, resolved)
    }

    private fun workerLayoutRequest(
        paragraph: HTMLElement,
        lowered: LoweredParagraph,
        options: EnhanceOptions,
    ): String? {
        if (options.conformingExactFontSessionId() == null) return null
        if (
            lowered.decorations.isNotEmpty() || lowered.inlineObjects.isNotEmpty() ||
            lowered.domInlineObjects.isNotEmpty() || lowered.sourceSpans.any { span ->
                span.inlineBoxStyle.boxDecorationBreak == "clone" &&
                    (kotlin.math.abs(span.inlineBoxStyle.inlineStart) >= INLINE_EDGE_EPSILON ||
                        kotlin.math.abs(span.inlineBoxStyle.inlineEnd) >= INLINE_EDGE_EPSILON)
            } || lowered.spans.any { it.style.locale != lowered.textStyle.locale }
        ) return null
        val rawWidth = sourceParagraphWidth(paragraph)
        if (!rawWidth.isFinite() || rawWidth <= 0f) return null
        // WorkerLineMeasureMatchesResponsiveGrid: the responsive coordinator
        // intentionally treats widths within the same floor(width / fontSize)
        // cell count as one layout input. Serialize that effective measure,
        // not the transient CSS width observed while a window is being dragged,
        // so preparation and commit use the same Worker plan inside the grid.
        val measure = effectiveLineMeasure(rawWidth, lowered.textStyle.fontSize)
        return workerLayoutRequestJson(
            paragraph = paragraph,
            lowered = lowered,
            width = measure,
            firstLineIndentIc = if (paragraph.tagName.uppercase() == "LI") {
                0f
            } else {
                options.firstLineIndentIc
            },
        )
    }

    private fun processParagraph(paragraph: HTMLElement, state: RootState) {
        if (!shouldTryParagraph(paragraph)) return
        // Capture host-owned inline typography before any computed-style probe.
        // CSSStyleDeclaration can leave an empty style attribute after a
        // temporary property is removed even when the source had no attribute.
        val originalStyleAttribute = paragraph.getAttribute("style")
        val originalFontSize = paragraph.style.getPropertyValue("font-size")
        val originalFontSizePriority = paragraph.style.getPropertyPriority("font-size")
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
        val originalPreparedFlowAttribute = paragraph.getAttribute("data-tq-canonical-plain")
        val originalCanonicalSourceAttribute = paragraph.getAttribute(CANONICAL_SOURCE_ATTRIBUTE)
        val originalExactPreparedDomAttribute = paragraph.getAttribute(EXACT_PREPARED_DOM_ATTRIBUTE)
        val originalLangAttribute = paragraph.getAttribute("lang")
        val originalPosition = paragraph.style.getPropertyValue("position")
        val originalPositionPriority = paragraph.style.getPropertyPriority("position")
        val originalInlineSize = paragraph.style.getPropertyValue("inline-size")
        val originalInlineSizePriority = paragraph.style.getPropertyPriority("inline-size")
        val originalHostInlineSizeAttribute = paragraph.getAttribute(HOST_INLINE_SIZE_ATTRIBUTE)
        val hostFontSizeApplied = applyConfiguredHostFontSize(paragraph, state.options.fontSize)
        val sourceInlineSize = captureSourceInlineSize(paragraph)
        val activeOptions = state.activeOptions()
        val workerRequest = workerLayoutRequest(paragraph, lowered, activeOptions)
        val workerPlan = workerRequest?.let { request ->
            takePreparedWorkerLayoutPlan(
                paragraph,
                activeOptions.conformingExactFontSessionId()!!,
                request,
            )
        }
        val workerIssue = if (workerRequest != null && workerPlan == null) {
            preparedWorkerLayoutIssue(
                paragraph,
                activeOptions.conformingExactFontSessionId()!!,
                workerRequest,
            )
        } else {
            null
        }
        // WorkerIneligibleRichRunBrowserFallback: SSR and the exact Worker
        // still fail closed when a semantic run has no replayable font
        // evidence. In the live browser, a rich paragraph can shape just that
        // unsupported run through its resolved host font while covered runs
        // remain on the exact session. The progressive scheduler bounds this
        // main-thread fallback to the individual paragraph slice.
        val canUseRichBrowserFallback =
            !lowered.isCanonicalPlainParagraph() &&
                workerIssue?.let(::isExactFontSessionCapabilityFailureDetail) == true
        if (
            activeOptions.requireExactLayoutWorker &&
            workerRequest != null &&
            workerPlan == null &&
            !canUseRichBrowserFallback
        ) {
            if (originalStyleAttribute == null) {
                paragraph.removeAttribute("style")
            } else {
                paragraph.setAttribute("style", originalStyleAttribute)
            }
            val detail = workerIssue ?: "the exact layout Worker produced no reusable plan"
            val issue = CapabilityIssue(
                name = "ExactLayoutWorkerPlanUnavailable",
                detail = detail,
                element = paragraph,
            )
            state.issues += issue
            reportIssue(issue)
            return
        }
        val originalContent = document.createDocumentFragment()
        while (paragraph.firstChild != null) {
            originalContent.appendChild(paragraph.firstChild!!)
        }
        val hostInlineSizeApplied = stabilizeContentSizedItemInlineSize(
            paragraph,
            sourceInlineSize,
        )
        paragraph.setAttribute("data-tq-rendered", "true")
        paragraph.setAttribute(RUNTIME_RENDER_FONT_ATTRIBUTE, "true")
        val item = EnhancedParagraph(
            source = paragraph,
            originalContent = originalContent,
            lowered = lowered,
            originalRenderedAttribute = originalRenderedAttribute,
            originalPreparedFlowAttribute = originalPreparedFlowAttribute,
            originalCanonicalSourceAttribute = originalCanonicalSourceAttribute,
            originalExactPreparedDomAttribute = originalExactPreparedDomAttribute,
            originalLangAttribute = originalLangAttribute,
            originalStyleAttribute = originalStyleAttribute,
            originalPosition = originalPosition,
            originalPositionPriority = originalPositionPriority,
            originalInlineSize = originalInlineSize,
            originalInlineSizePriority = originalInlineSizePriority,
            originalFontSize = originalFontSize,
            originalFontSizePriority = originalFontSizePriority,
            originalHostInlineSizeAttribute = originalHostInlineSizeAttribute,
            hostInlineSizeApplied = hostInlineSizeApplied,
            hostFontSizeApplied = hostFontSizeApplied,
        )
        val layoutIssue = try {
            if (workerPlan == null) {
                layoutParagraph(
                    paragraph = item,
                    options = activeOptions,
                    engine = state.activeEngine(),
                    semanticExactEngine = state.activeSemanticExactEngine(),
                    browserFallbackEngine = state.activeExactFallbackEngine(),
                    onExactPreparedDomFallback = state::disableExactPreparedDom,
                )
            } else {
                commitWorkerPreparedParagraph(
                    paragraph = item,
                    workerPlan = workerPlan,
                    onExactPreparedDomFallback = state::disableExactPreparedDom,
                )
            }
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
            states.delete(state.root)
            state.root.removeAttribute("data-tiqian-enhanced")
            state.root.removeAttribute("data-tiqian-enhanced-count")
            state.root.removeAttribute("data-tiqian-issue-count")
            return
        }
        states.set(state.root, state)
        state.root.setAttribute("data-tiqian-enhanced", "true")
        state.root.setAttribute(
            "data-tiqian-enhanced-count",
            "${state.paragraphs.size + observableSnapshotCount(state.root)}",
        )
        if (state.issues.isEmpty()) {
            state.root.removeAttribute("data-tiqian-issue-count")
        } else {
            state.root.setAttribute("data-tiqian-issue-count", "${state.issues.size}")
        }
    }

    private fun scheduleProgressiveSlice(job: ProgressiveJob) {
        val idle = job.shouldScheduleIdle(job.nextIndex)
        job.scheduledSliceToken = scheduleProgressiveCallback(
            callback = { runProgressiveSlice(job, idle) },
            idle = idle,
        )
    }

    private fun startProgressiveJob(job: ProgressiveJob) {
        cancelProgressiveJob(job.state.root)
        job.state.root.removeAttribute(RELAYOUT_ERROR_ATTRIBUTE)
        progressiveJobs[job.state.root] = job
        if (job.itemCount == 0) {
            try {
                job.onItemsFinished?.invoke()
                finishProgressiveJob(job)
            } catch (error: Throwable) {
                job.onFailure?.invoke()
                failProgressiveJob(job, error)
            }
        } else {
            scheduleProgressiveSlice(job)
        }
    }

    private fun cancelProgressiveJob(root: HTMLElement) {
        progressiveJobs.remove(root)?.scheduledSliceToken?.let(::cancelProgressiveCallback)
    }

    private fun runProgressiveSlice(job: ProgressiveJob, idleSlice: Boolean) {
        if (progressiveJobs[job.state.root] !== job) return
        job.scheduledSliceToken = null
        val sliceStartedAt = performanceNow()
        var processedInSlice = 0
        try {
            do {
                job.processItem(job.nextIndex)
                job.nextIndex += 1
                processedInSlice += 1
            } while (
                job.nextIndex < job.itemCount &&
                processedInSlice < MAX_PROGRESSIVE_ITEMS_PER_SLICE &&
                performanceNow() - sliceStartedAt < MAX_PROGRESSIVE_SLICE_MS &&
                (!idleSlice || processedInSlice < MAX_PROGRESSIVE_IDLE_ITEMS_PER_SLICE) &&
                !job.shouldScheduleIdle(job.nextIndex) &&
                !progressiveInputIsPending()
            )
        } catch (error: Throwable) {
            job.onFailure?.invoke()
            failProgressiveJob(job, error)
            return
        }
        val sliceDuration = performanceNow() - sliceStartedAt
        job.maxSliceDuration = maxOf(job.maxSliceDuration, sliceDuration)
        publishState(job.state, keepEmpty = true)
        if (job.nextIndex >= job.itemCount) {
            try {
                job.onItemsFinished?.invoke()
                job.maxSliceDuration = maxOf(
                    job.maxSliceDuration,
                    performanceNow() - sliceStartedAt,
                )
                finishProgressiveJob(job)
            } catch (error: Throwable) {
                job.onFailure?.invoke()
                failProgressiveJob(job, error)
            }
        } else {
            scheduleProgressiveSlice(job)
        }
    }

    private fun finishProgressiveJob(job: ProgressiveJob) {
        if (progressiveJobs.remove(job.state.root) !== job) return
        job.state.root.removeAttribute(RELAYOUT_ERROR_ATTRIBUTE)
        publishState(job.state)
        val runtimeEnhancedCount = job.state.paragraphs.size
        val snapshotCount = observableSnapshotCount(job.state.root)
        if (job.kind == ProgressiveJobKind.Relayout) {
            dispatchTiqianRelayoutReady(
                root = job.state.root,
                enhancedCount = runtimeEnhancedCount + snapshotCount,
                runtimeEnhancedCount = runtimeEnhancedCount,
                snapshotCount = snapshotCount,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                failed = false,
                error = null,
                stale = job.commitSkipped || job.stale?.invoke() == true,
            )
        } else {
            dispatchTiqianReady(
                root = job.state.root,
                enhancedCount = runtimeEnhancedCount + snapshotCount,
                runtimeEnhancedCount = runtimeEnhancedCount,
                snapshotCount = snapshotCount,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                stale = job.commitSkipped || job.stale?.invoke() == true,
            )
        }
    }

    private fun failProgressiveJob(job: ProgressiveJob, error: Throwable) {
        if (progressiveJobs.remove(job.state.root) !== job) return
        val detail = (error.message ?: error.toString()).take(CAPABILITY_DETAIL_LIMIT)
        job.state.root.setAttribute(RELAYOUT_ERROR_ATTRIBUTE, detail)
        publishState(job.state, keepEmpty = true)
        dispatchTiqianProgressiveError(
            root = job.state.root,
            kind = job.kind.name,
            detail = detail,
            durationMs = performanceNow() - job.startedAt,
            maxSliceMs = job.maxSliceDuration,
        )
        val runtimeEnhancedCount = job.state.paragraphs.size
        val snapshotCount = observableSnapshotCount(job.state.root)
        if (job.kind == ProgressiveJobKind.Relayout) {
            dispatchTiqianRelayoutReady(
                root = job.state.root,
                enhancedCount = runtimeEnhancedCount + snapshotCount,
                runtimeEnhancedCount = runtimeEnhancedCount,
                snapshotCount = snapshotCount,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                failed = true,
                error = detail,
                stale = false,
            )
        } else {
            dispatchTiqianReady(
                root = job.state.root,
                enhancedCount = runtimeEnhancedCount + snapshotCount,
                runtimeEnhancedCount = runtimeEnhancedCount,
                snapshotCount = snapshotCount,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                stale = false,
            )
        }
    }

    private fun relayout(root: HTMLElement) {
        val runningJob = progressiveJobs[root]
        if (runningJob?.kind == ProgressiveJobKind.Enhance) {
            // Responsive changes are normally observed only after tiqian:ready,
            // but a manual relayout can still arrive during initial enhancement.
            // Restart from native source at the latest width so candidates that
            // have not been reached by the old job are not stranded.
            enhanceProgressively(root, runningJob.state.options)
            return
        }
        val state = states.get(root) as? RootState ?: return
        val activeOptions = state.activeOptions()
        val activeEngine = state.activeEngine()
        val activeExactFallbackEngine = state.activeExactFallbackEngine()
        cancelProgressiveJob(root)
        if (state.issues.any { it.name in WIDTH_DEPENDENT_CAPABILITY_ISSUES }) {
            // WidthDependentCapabilityTransitionRetry: only named
            // capabilities whose eligibility depends on line count need to be
            // lowered again at the new width. Restore semantic source once,
            // then let viewport-near paragraphs take over atomically in bounded
            // slices just like any other source refresh.
            enhanceProgressively(root, state.options, ProgressiveJobKind.Relayout)
            return
        }
        val paragraphs = state.paragraphs.toList()
        // ViewportPriorityRelayout: capture the priority before any live DOM is
        // changed. A paragraph intersecting the viewport has distance zero;
        // the remaining paragraphs follow by proximity and document order.
        val workOrder = paragraphs.indices
            .map { index -> index to paragraphViewportDistance(paragraphs[index].source) }
            .sortedWith(compareBy<Pair<Int, Double>> { it.second }.thenBy { it.first })
            .map { it.first }
        // WidthSnapshotPerRelayoutJob: every paragraph is prepared against the
        // geometry seen when the job starts. If the host changes again while
        // slices are running, element.js schedules one latest-width follow-up
        // instead of allowing a queue of obsolete widths to replay.
        val widths = paragraphs.map(::paragraphWidth)
        val commitSession = ProgressiveRelayoutSession(
            paragraphs = paragraphs,
            state = state,
        )
        startProgressiveJob(
            ProgressiveJob(
                state = state,
                kind = ProgressiveJobKind.Relayout,
                itemCount = paragraphs.size,
                processItem = { index ->
                    val paragraphIndex = workOrder[index]
                    val paragraph = paragraphs[paragraphIndex]
                    val preparation = prepareParagraphLayout(
                        paragraph = paragraph,
                        options = activeOptions,
                        engine = activeEngine,
                        semanticExactEngine = state.activeSemanticExactEngine(),
                        browserFallbackEngine = activeExactFallbackEngine,
                        widthOverride = widths[paragraphIndex],
                    )
                    // ParagraphCurrentMeasureCommit: keep the previous
                    // paragraph DOM until its replacement is ready, then
                    // require the captured measure to still equal the live
                    // measure immediately before the single-paragraph commit.
                    val currentWidth = paragraphWidth(paragraph)
                    if (
                        isCurrentResponsiveMeasure(
                            preparedWidth = widths[paragraphIndex],
                            currentWidth = currentWidth,
                            fontSize = paragraph.lowered.textStyle.fontSize,
                        )
                    ) {
                        commitSession.processItem(paragraphIndex, preparation)
                    } else {
                        commitSession.stale = true
                    }
                },
                onItemsFinished = commitSession::finish,
                onFailure = commitSession::rollback,
                stale = { commitSession.stale },
                shouldScheduleIdle = { index ->
                    workOrder.getOrNull(index)
                        ?.let { paragraphIndex -> paragraphs[paragraphIndex].source }
                        ?.let(::paragraphIsWithinProgressiveForegroundRange) == false
                },
                startedAt = performanceNow(),
            ),
        )
    }

    /**
     * HostTypographyInvalidation: width-only relayout can reuse lowered source,
     * but a host font/size/weight/line-height change must restore the semantic
     * DOM and lower it again. Otherwise canvas measures the old computed style
     * while light DOM paints the new one, producing clipped whole-line overflow.
     */
    internal fun refresh(root: HTMLElement, progressively: Boolean = true) {
        val options = (states.get(root) as? RootState)?.options ?: return
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
        semanticExactEngine: ExplainableStubParagraphLayoutEngine? = null,
        browserFallbackEngine: ExplainableStubParagraphLayoutEngine? = null,
        onExactPreparedDomFallback: (String) -> Unit = {},
    ): CapabilityIssue? {
        return when (
            val preparation = prepareParagraphLayout(
                paragraph = paragraph,
                options = options,
                engine = engine,
                semanticExactEngine = semanticExactEngine,
                browserFallbackEngine = browserFallbackEngine,
            )
        ) {
            ParagraphLayoutPreparation.Unchanged -> null
            is ParagraphLayoutPreparation.Unsupported -> preparation.issue
            is ParagraphLayoutPreparation.Ready -> when (
                val commit = commitPreparedParagraph(
                    paragraph = paragraph,
                    preparation = preparation,
                    options = options,
                    browserFallbackEngine = browserFallbackEngine,
                    onExactPreparedDomFallback = onExactPreparedDomFallback,
                )
            ) {
                is ParagraphCommitResult.Success -> {
                    paragraph.lastMeasure = commit.measure
                    null
                }
                is ParagraphCommitResult.Unsupported -> commit.issue
            }
        }
    }

    private fun commitWorkerPreparedParagraph(
        paragraph: EnhancedParagraph,
        workerPlan: String,
        onExactPreparedDomFallback: (String) -> Unit,
    ): CapabilityIssue? {
        val width = paragraphWidth(paragraph)
        paragraph.source.setAttribute(EXACT_PREPARED_DOM_ATTRIBUTE, "true")
        paragraph.source.setAttribute(CANONICAL_SOURCE_ATTRIBUTE, "true")
        if (paragraph.lowered.sourceSpans.isEmpty()) {
            paragraph.source.setAttribute("data-tq-canonical-plain", "true")
        } else {
            paragraph.source.removeAttribute("data-tq-canonical-plain")
        }
        paragraph.source.setAttribute("lang", paragraph.lowered.textStyle.locale)
        renderPreparedWorkerParagraphDom(
            paragraph.source,
            workerPlan,
            paragraph.lowered.textStyle.locale,
            paragraph.lowered.text,
        )
        val preparedDomIssue = validatePreparedParagraphDom(paragraph.source, width.toDouble())
        if (preparedDomIssue != null) {
            onExactPreparedDomFallback(preparedDomIssue)
            releasePreparedParagraphDomStyles(paragraph.source)
            restoreAttribute(
                paragraph.source,
                EXACT_PREPARED_DOM_ATTRIBUTE,
                paragraph.originalExactPreparedDomAttribute,
            )
            restoreAttribute(
                paragraph.source,
                "data-tq-canonical-plain",
                paragraph.originalPreparedFlowAttribute,
            )
            restoreAttribute(
                paragraph.source,
                CANONICAL_SOURCE_ATTRIBUTE,
                paragraph.originalCanonicalSourceAttribute,
            )
            restoreAttribute(paragraph.source, "lang", paragraph.originalLangAttribute)
            return CapabilityIssue(
                name = "WorkerPreparedDomContractMismatch",
                detail = preparedDomIssue,
                element = paragraph.source,
            )
        }
        paragraph.lastMeasure = effectiveLineMeasure(width, paragraph.lowered.textStyle.fontSize)
        return null
    }

    private fun paragraphWidth(paragraph: EnhancedParagraph): Float {
        return sourceParagraphWidth(paragraph.source)
    }

    private fun sourceParagraphWidth(paragraph: HTMLElement): Float {
        // ContentBoxLineMeasure: LayoutConstraints describe the inline content
        // box where glyphs are placed. A host may add padding directly to a
        // paragraph-shaped list item; using its border-box width lays the line
        // out once through that padding and then starts it after the padding,
        // causing a real right-edge overflow. Font backend selection does not
        // change which CSS box owns the available line measure.
        return elementContentWidth(paragraph).toFloat()
            .takeIf { it > 0f }
            ?: elementContentWidth(paragraph.parentElement as? HTMLElement ?: paragraph).toFloat()
                .takeIf { it > 0f }
            ?: 320f
    }

    private fun prepareParagraphLayout(
        paragraph: EnhancedParagraph,
        options: EnhanceOptions,
        engine: ExplainableStubParagraphLayoutEngine,
        semanticExactEngine: ExplainableStubParagraphLayoutEngine? = null,
        browserFallbackEngine: ExplainableStubParagraphLayoutEngine? = null,
        widthOverride: Float? = null,
        ignoreUnchangedMeasure: Boolean = false,
    ): ParagraphLayoutPreparation {
        val width = widthOverride ?: paragraphWidth(paragraph)
        // LineLengthGridResponsiveInvalidation: the Web adapter currently
        // exposes the default Start-aligned body, so widths within the same
        // floor(width / fontSize) cell count produce identical layout and a
        // zero body offset. Compare the actual engine measure instead of a raw
        // pixel tolerance, which could hide a grid crossing at fractional font
        // sizes.
        val fontSize = paragraph.lowered.textStyle.fontSize
        val measure = effectiveLineMeasure(width, fontSize)
        if (!ignoreUnchangedMeasure && paragraph.lastMeasure == measure) {
            return ParagraphLayoutPreparation.Unchanged
        }
        val input = LayoutInput(
            content = TiqianTextContent(
                text = paragraph.lowered.text,
                spans = paragraph.lowered.spans,
                sourceBoundaries = paragraph.lowered.sourceBoundaries,
            ),
            textStyle = paragraph.lowered.textStyle,
            // EngineLineMeasureMatchesResponsiveGrid: retain the raw width in
            // ParagraphLayoutPreparation for host-box validation, but feed the
            // same quantized measure to every synchronous/Worker layout path.
            constraints = LayoutConstraints(maxWidth = measure),
            paragraphStyle = ParagraphStyle(
                lineHeight = paragraph.lowered.lineHeight,
                firstLineIndent = if (
                    paragraph.source.tagName.uppercase() == "LI"
                ) Ic.Zero else Ic(options.firstLineIndentIc),
                emphasisDotGapEm = options.emphasisDotGapEm,
            ),
            decorations = paragraph.lowered.decorations,
            rubySpans = emptyList(),
            inlineBoxes = paragraph.lowered.inlineBoxes,
            inlineObjects = paragraph.lowered.inlineObjects,
        )
        // ExactSessionSemanticLayout: semantic DOM changes how LayoutResult is
        // replayed, not which font backend owns shaping and measurement. Keep
        // links, code, and other supported inline semantics on the same exact
        // session as canonical plain paragraphs; use the browser adapter only
        // when that session reports a named font capability failure.
        val exactFontLayout = browserFallbackEngine != null
        // KeyedCanonicalPreparedDomOnly: a snapshot key proves that the server
        // captured a complete exact replay corpus for this canonical source.
        // An unkeyed runtime-completion paragraph may carry only the required
        // exact runs (notably a CJK dash) and must therefore retain per-run
        // browser fallback instead of retrying its whole paragraph through the
        // browser shaper after one unrelated replay miss.
        var exactPreparedDom = exactFontLayout &&
            paragraph.source.hasAttribute("data-tq-snapshot-key") &&
            paragraph.lowered.isCanonicalPlainParagraph()
        val layoutEngine = if (exactFontLayout && !exactPreparedDom) {
            semanticExactEngine ?: engine
        } else {
            engine
        }
        val result = if (exactFontLayout) {
            try {
                layoutEngine.layout(input)
            } catch (error: Throwable) {
                if (!isExactFontSessionCapabilityFailure(error)) throw error
                exactPreparedDom = false
                browserFallbackEngine.layout(input)
            }
        } else {
            engine.layout(input)
        }
        val shapingCapabilityIssue = result.debug.shapingDecisions.firstOrNull {
            it.capabilityIssue != null
        }
        if (shapingCapabilityIssue != null) {
            return ParagraphLayoutPreparation.Unsupported(
                CapabilityIssue(
                    name = shapingCapabilityIssue.capabilityIssue!!,
                    detail = shapingCapabilityIssue.reason,
                    element = paragraph.source,
                ),
            )
        }
        val invalidShaping = result.debug.shapingDecisions.firstOrNull { decision ->
            decision.displayText.isNotEmpty() &&
                decision.displayText.none { it == '\n' || it == '\r' } &&
                (!decision.advance.isFinite() || decision.advance <= ZERO_ADVANCE_EPSILON)
        }
        if (invalidShaping != null) {
            return ParagraphLayoutPreparation.Unsupported(
                CapabilityIssue(
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
                ),
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
            return ParagraphLayoutPreparation.Unsupported(
                CapabilityIssue(
                    name = "InlineCloneDecorationBreakUnsupported",
                    detail = clonedDecoration.element.tagName.lowercase(),
                    element = paragraph.source,
                ),
            )
        }
        return ParagraphLayoutPreparation.Ready(
            result = result,
            width = width,
            measure = measure,
            exactPreparedDom = exactPreparedDom,
        )
    }

    private fun effectiveLineMeasure(width: Float, fontSize: Float): Float {
        // InvalidTypographyPreservesCapabilityDiagnosis: a zero/non-finite
        // host font size has no meaningful character grid. Keep the positive
        // host width so shaping can report its precise zero-advance capability
        // issue instead of failing earlier with an unrelated maxWidth error.
        if (!fontSize.isFinite() || fontSize <= 0f) return width
        val gridCells = kotlin.math.floor(width / fontSize).toInt().coerceAtLeast(1)
        return (gridCells * fontSize).coerceAtMost(width)
    }

    private fun isCurrentResponsiveMeasure(
        preparedWidth: Float,
        currentWidth: Float,
        fontSize: Float,
    ): Boolean = effectiveLineMeasure(preparedWidth, fontSize) ==
        effectiveLineMeasure(currentWidth, fontSize)

    private fun commitPreparedParagraph(
        paragraph: EnhancedParagraph,
        preparation: ParagraphLayoutPreparation.Ready,
        options: EnhanceOptions,
        browserFallbackEngine: ExplainableStubParagraphLayoutEngine?,
        onExactPreparedDomFallback: (String) -> Unit = {},
    ): ParagraphCommitResult {
        val result = preparation.result
        if (preparation.exactPreparedDom) {
            paragraph.source.setAttribute("data-tq-canonical-plain", "true")
            paragraph.source.setAttribute(CANONICAL_SOURCE_ATTRIBUTE, "true")
            paragraph.source.setAttribute("lang", paragraph.lowered.textStyle.locale)
            renderPreparedParagraphDom(
                paragraph.source,
                result.toPreparedParagraphJson(),
                paragraph.lowered.textStyle.locale,
            )
            val preparedDomIssue = validatePreparedParagraphDom(
                paragraph.source,
                preparation.width.toDouble(),
            )
            if (preparedDomIssue != null) {
                onExactPreparedDomFallback(preparedDomIssue)
                restoreAttribute(
                    paragraph.source,
                    "data-tq-canonical-plain",
                    paragraph.originalPreparedFlowAttribute,
                )
                restoreAttribute(
                    paragraph.source,
                    CANONICAL_SOURCE_ATTRIBUTE,
                    paragraph.originalCanonicalSourceAttribute,
                )
                restoreAttribute(paragraph.source, "lang", paragraph.originalLangAttribute)
                val fallbackOptions = options.withoutExactFontSession()
                val fallbackPreparation = prepareParagraphLayout(
                    paragraph = paragraph,
                    options = fallbackOptions,
                    engine = browserFallbackEngine!!,
                    browserFallbackEngine = null,
                    widthOverride = preparation.width,
                    ignoreUnchangedMeasure = true,
                )
                return when (fallbackPreparation) {
                    ParagraphLayoutPreparation.Unchanged -> error(
                        "Exact prepared DOM fallback unexpectedly skipped relayout",
                    )
                    is ParagraphLayoutPreparation.Unsupported ->
                        ParagraphCommitResult.Unsupported(fallbackPreparation.issue)
                    is ParagraphLayoutPreparation.Ready -> commitPreparedParagraph(
                        paragraph = paragraph,
                        preparation = fallbackPreparation,
                        options = fallbackOptions,
                        browserFallbackEngine = null,
                        onExactPreparedDomFallback = onExactPreparedDomFallback,
                    )
                }
            }
        } else {
            releasePreparedParagraphDomStyles(paragraph.source)
            restoreAttribute(
                paragraph.source,
                "data-tq-canonical-plain",
                paragraph.originalPreparedFlowAttribute,
            )
            restoreAttribute(paragraph.source, "lang", paragraph.originalLangAttribute)
            ensureContainingBlock(paragraph)
            DomParagraphRenderer.render(
                paragraph.source,
                result,
                options.fonts,
                sourceSpans = paragraph.lowered.sourceSpans,
                inlineObjects = paragraph.lowered.domInlineObjects,
            )
            DomParagraphRenderer.verifyCjkDashRuns(paragraph.source)?.let { detail ->
                return ParagraphCommitResult.Unsupported(
                    CapabilityIssue(
                        name = "DomDashFaceGeometryMismatch",
                        detail = detail,
                        element = paragraph.source,
                    ),
                )
            }
            if (paragraph.lowered.isCanonicalPlainParagraph()) {
                paragraph.source.setAttribute(CANONICAL_SOURCE_ATTRIBUTE, "true")
            } else {
                restoreAttribute(
                    paragraph.source,
                    CANONICAL_SOURCE_ATTRIBUTE,
                    paragraph.originalCanonicalSourceAttribute,
                )
            }
        }
        return ParagraphCommitResult.Success(preparation.measure)
    }

    private class ProgressiveRelayoutSession(
        paragraphs: List<EnhancedParagraph>,
        private val state: RootState,
    ) {
        private val paragraphs = paragraphs.toList()
        private val snapshots = LinkedHashMap<EnhancedParagraph, LiveParagraphSnapshot>()
        private val successful = mutableListOf<Pair<EnhancedParagraph, Float>>()
        private val unsupported = mutableListOf<Pair<EnhancedParagraph, CapabilityIssue>>()
        private val stateParagraphsBefore = state.paragraphs.toList()
        private val stateIssuesBefore = state.issues.toList()
        var stale: Boolean = false

        fun processItem(index: Int, preparation: ParagraphLayoutPreparation) {
            val paragraph = paragraphs[index]
            when (preparation) {
                ParagraphLayoutPreparation.Unchanged -> Unit
                is ParagraphLayoutPreparation.Unsupported -> {
                    snapshots[paragraph] = TiqianWeb.captureLiveParagraph(paragraph)
                    unsupported += paragraph to preparation.issue
                    TiqianWeb.restoreParagraph(paragraph)
                }
                is ParagraphLayoutPreparation.Ready -> {
                    snapshots[paragraph] = TiqianWeb.captureLiveParagraph(paragraph)
                    when (
                        val result = TiqianWeb.commitPreparedParagraph(
                            paragraph = paragraph,
                            preparation = preparation,
                            options = state.options,
                            browserFallbackEngine = state.browserFallbackEngine,
                            onExactPreparedDomFallback = state::disableExactPreparedDom,
                        )
                    ) {
                        is ParagraphCommitResult.Success -> {
                            paragraph.lastMeasure = result.measure
                            successful += paragraph to result.measure
                        }
                        is ParagraphCommitResult.Unsupported -> {
                            unsupported += paragraph to result.issue
                            TiqianWeb.restoreParagraph(paragraph)
                        }
                    }
                }
            }
        }

        fun finish() {
            for ((paragraph, measure) in successful) {
                if (unsupported.none { (unsupportedParagraph, _) -> unsupportedParagraph === paragraph }) {
                    paragraph.lastMeasure = measure
                }
            }
            for ((paragraph, issue) in unsupported) {
                state.paragraphs.remove(paragraph)
                state.issues += issue
                TiqianWeb.reportIssue(issue)
            }
        }

        fun rollback() {
            state.paragraphs.clear()
            state.paragraphs.addAll(stateParagraphsBefore)
            state.issues.clear()
            state.issues.addAll(stateIssuesBefore)
            TiqianWeb.rollbackRelayoutSnapshots(snapshots.values.toList())
        }
    }

    private fun captureLiveParagraph(paragraph: EnhancedParagraph): LiveParagraphSnapshot {
        val content = document.createDocumentFragment()
        val snapshot = LiveParagraphSnapshot(
            paragraph = paragraph,
            content = content,
            renderedAttribute = paragraph.source.getAttribute("data-tq-rendered"),
            preparedFlowAttribute = paragraph.source.getAttribute("data-tq-canonical-plain"),
            canonicalSourceAttribute = paragraph.source.getAttribute(CANONICAL_SOURCE_ATTRIBUTE),
            exactPreparedDomAttribute = paragraph.source.getAttribute(EXACT_PREPARED_DOM_ATTRIBUTE),
            langAttribute = paragraph.source.getAttribute("lang"),
            styleAttribute = paragraph.source.getAttribute("style"),
            capabilityNameAttribute = paragraph.source.getAttribute("data-tiqian-capability-issue"),
            capabilityDetailAttribute = paragraph.source.getAttribute("data-tiqian-capability-detail"),
            lastMeasure = paragraph.lastMeasure,
            containingBlockApplied = paragraph.containingBlockApplied,
            hostInlineSizeApplied = paragraph.hostInlineSizeApplied,
            hostInlineSizeAttribute = paragraph.source.getAttribute(HOST_INLINE_SIZE_ATTRIBUTE),
            originalContentHadChildren = paragraph.originalContent.firstChild != null,
        )
        while (paragraph.source.firstChild != null) {
            content.appendChild(paragraph.source.firstChild!!)
        }
        return snapshot
    }

    private fun rollbackRelayoutSnapshots(snapshots: List<LiveParagraphSnapshot>) {
        for (snapshot in snapshots.asReversed()) {
            val paragraph = snapshot.paragraph
            if (snapshot.originalContentHadChildren && paragraph.originalContent.firstChild == null) {
                // restoreParagraph() handed the semantic source fragment back
                // to the live DOM; move those exact nodes into source custody
                // again before replaying the previous rendered fragment.
                while (paragraph.source.firstChild != null) {
                    paragraph.originalContent.appendChild(paragraph.source.firstChild!!)
                }
            } else {
                while (paragraph.source.firstChild != null) {
                    paragraph.source.removeChild(paragraph.source.firstChild!!)
                }
            }
            paragraph.source.appendChild(snapshot.content)
            restoreAttribute(paragraph.source, "data-tq-rendered", snapshot.renderedAttribute)
            restoreAttribute(
                paragraph.source,
                "data-tq-canonical-plain",
                snapshot.preparedFlowAttribute,
            )
            restoreAttribute(
                paragraph.source,
                CANONICAL_SOURCE_ATTRIBUTE,
                snapshot.canonicalSourceAttribute,
            )
            restoreAttribute(
                paragraph.source,
                EXACT_PREPARED_DOM_ATTRIBUTE,
                snapshot.exactPreparedDomAttribute,
            )
            restoreAttribute(paragraph.source, "lang", snapshot.langAttribute)
            restoreAttribute(paragraph.source, "style", snapshot.styleAttribute)
            restoreAttribute(
                paragraph.source,
                "data-tiqian-capability-issue",
                snapshot.capabilityNameAttribute,
            )
            restoreAttribute(
                paragraph.source,
                "data-tiqian-capability-detail",
                snapshot.capabilityDetailAttribute,
            )
            paragraph.lastMeasure = snapshot.lastMeasure
            paragraph.containingBlockApplied = snapshot.containingBlockApplied
            paragraph.hostInlineSizeApplied = snapshot.hostInlineSizeApplied
            restoreAttribute(
                paragraph.source,
                HOST_INLINE_SIZE_ATTRIBUTE,
                snapshot.hostInlineSizeAttribute,
            )
        }
    }

    private fun shouldTryParagraph(paragraph: HTMLElement): Boolean {
        if (hasClosest(paragraph, SKIPPED_ANCESTOR_SELECTOR)) return false
        if (paragraph.getAttribute("data-tiqian-skip") != null) return false
        // `LeafListItemParagraph`: Markdown commonly emits list text directly
        // inside <li>, so a list item is a paragraph-shaped flow owner and must
        // enter the same pipeline. An outer item that owns a nested block stays
        // native as a container; its leaf descendants are still independent
        // candidates. This avoids replacing a nested <ul>/<ol> while preserving
        // list markers and host list semantics.
        if (
            paragraph.tagName.uppercase() == "LI" &&
            paragraph.querySelector(":scope > p, :scope > ul, :scope > ol, :scope > blockquote, :scope > pre, :scope > table") != null
        ) {
            return false
        }
        // PureBlockImageParagraphExclusion: Markdown commonly wraps a
        // standalone image in <p>. A block image owns no inline text flow for
        // Tiqian to lay out, so leave the host wrapper native without reporting
        // a capability issue. Text mixed with a block image still enters the
        // lowerer and fails atomically as an unsupported formatting context.
        if (isPureBlockImageParagraph(paragraph)) return false
        if (paragraph.textContent?.isBlank() != false && !hasOpaqueInlineCandidate(paragraph)) return false
        return true
    }

    private fun isPureBlockImageParagraph(paragraph: HTMLElement): Boolean {
        if (paragraph.tagName.uppercase() != "P" || paragraph.textContent?.isBlank() != true) return false
        val children = paragraph.querySelectorAll(":scope > *")
        if (children.length == 0) return false
        for (index in 0 until children.length) {
            val child = children.item(index) as? Element ?: return false
            if (
                child.tagName.uppercase() != "IMG" ||
                computedStyle(child, "display").trim().lowercase() != "block"
            ) return false
        }
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
        // PendingCapabilityIsObservableNotTerminal: the semantic paragraph is
        // intentionally kept native while the asynchronous dash-face probe is
        // in flight. Keep the DOM marker for the targeted retry, but reserve a
        // console warning for the retry's final unavailable/mismatch result.
        if (issue.reportToConsole) {
            consoleWarn("TiqianWeb skipped paragraph: ${issue.name} (${issue.detail})")
        }
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
        val emphasisDotGapEm = optionFloat(options, "emphasisDotGapEm")
            ?: DEFAULT_EMPHASIS_DOT_GAP_EM
        val strongAsEmphasisMarks = optionBoolean(options, "strongAsEmphasisMarks") ?: false
        val paragraphSelector = optionString(options, "paragraphSelector") ?: DEFAULT_PARAGRAPH_SELECTOR
        val requireExactLayoutWorker = optionBoolean(options, "requireExactLayoutWorker") ?: false
        val dashCapabilityObject = optionObject(options, "cjkDashCapability")
        val dashCapability = dashCapabilityObject?.let { capability ->
            WebCjkDashCapability(
                status = optionString(capability, "status") ?: "unavailable",
                detail = optionString(capability, "detail"),
            )
        }
        val exactFontSessionObject = optionObject(options, "exactFontSession")
        val exactFontSession = exactFontSessionObject?.let { capability ->
            ExactFontSessionCapability(
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
            emphasisDotGapEm = emphasisDotGapEm,
            strongAsEmphasisMarks = strongAsEmphasisMarks,
            paragraphSelector = paragraphSelector,
            cjkDashCapability = dashCapability,
            exactFontSession = exactFontSession,
            requireExactLayoutWorker = requireExactLayoutWorker,
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
        val emphasisDotGapEm: Float = DEFAULT_EMPHASIS_DOT_GAP_EM,
        val strongAsEmphasisMarks: Boolean = false,
        val paragraphSelector: String = DEFAULT_PARAGRAPH_SELECTOR,
        val cjkDashCapability: WebCjkDashCapability? = null,
        val exactFontSession: ExactFontSessionCapability? = null,
        /**
         * Internal custom-element contract: every Worker-representable exact
         * layout must commit its prepared plan. Rich paragraphs outside that
         * contract retain the sliced browser-shaping path.
         */
        val requireExactLayoutWorker: Boolean = false,
    ) {
        lateinit var fonts: WebFontFamilies
            private set

        fun withRootDefaults(root: HTMLElement): EnhanceOptions {
            require(fontSize == null || (fontSize.isFinite() && fontSize > 0f)) {
                "InvalidFontSize"
            }
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

        internal fun conformingExactFontSessionId(): String? = exactFontSession
            ?.takeIf { it.status == "conforming" }
            ?.sessionId
            ?.takeIf(String::isNotBlank)

        internal fun allowsSnapshotExactLayout(): Boolean =
            fontSize == null &&
                lineHeight == null &&
                firstLineIndentIc == 0f &&
                fontFamilies.cjk == null &&
                fontFamilies.latin == null &&
                fontFamilies.monospace == null &&
                fontFamilies.cjkSerif == null &&
                fontFamilies.latinSerif == null

        internal fun withoutExactFontSession(): EnhanceOptions =
            copy(exactFontSession = null).also { fallback -> fallback.fonts = fonts }
    }

    data class FontFamilyOptions(
        val cjk: String? = null,
        val latin: String? = null,
        val monospace: String? = null,
        val cjkSerif: String? = null,
        val latinSerif: String? = null,
    )

    data class ExactFontSessionCapability(
        val status: String = "unavailable",
        val sessionId: String? = null,
        val detail: String? = null,
    )

    private data class RootState(
        val root: HTMLElement,
        var options: EnhanceOptions,
        var engine: ExplainableStubParagraphLayoutEngine,
        var semanticExactEngine: ExplainableStubParagraphLayoutEngine?,
        var browserFallbackEngine: ExplainableStubParagraphLayoutEngine?,
        val paragraphs: MutableList<EnhancedParagraph>,
        val issues: MutableList<CapabilityIssue>,
        var exactPreparedDomEnabled: Boolean = browserFallbackEngine != null,
        var exactPreparedDomFallback: String? = null,
    ) {
        fun activeOptions(): EnhanceOptions =
            if (exactPreparedDomEnabled) options else options.withoutExactFontSession()

        fun activeEngine(): ExplainableStubParagraphLayoutEngine =
            if (exactPreparedDomEnabled) engine else browserFallbackEngine ?: engine

        fun activeSemanticExactEngine(): ExplainableStubParagraphLayoutEngine? =
            semanticExactEngine.takeIf { exactPreparedDomEnabled }

        fun activeExactFallbackEngine(): ExplainableStubParagraphLayoutEngine? =
            browserFallbackEngine.takeIf { exactPreparedDomEnabled }

        fun disableExactPreparedDom(detail: String) {
            if (!exactPreparedDomEnabled) return
            exactPreparedDomEnabled = false
            exactPreparedDomFallback = detail.take(CAPABILITY_DETAIL_LIMIT)
            root.setAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE, exactPreparedDomFallback!!)
        }
    }

    private enum class ProgressiveJobKind {
        Enhance,
        Relayout,
    }

    private class ProgressiveJob(
        val state: RootState,
        val kind: ProgressiveJobKind,
        val itemCount: Int,
        val processItem: (Int) -> Unit,
        val onItemsFinished: (() -> Unit)? = null,
        val onFailure: (() -> Unit)? = null,
        val stale: (() -> Boolean)? = null,
        val shouldScheduleIdle: (Int) -> Boolean = { false },
        val startedAt: Double,
        var nextIndex: Int = 0,
        var scheduledSliceToken: JsAny? = null,
        var maxSliceDuration: Double = 0.0,
        var commitSkipped: Boolean = false,
    )


    private sealed class ParagraphLayoutPreparation {
        data object Unchanged : ParagraphLayoutPreparation()

        data class Ready(
            val result: LayoutResult,
            val width: Float,
            val measure: Float,
            val exactPreparedDom: Boolean,
        ) : ParagraphLayoutPreparation()

        data class Unsupported(val issue: CapabilityIssue) : ParagraphLayoutPreparation()
    }

    private sealed class ParagraphCommitResult {
        data class Success(val measure: Float) : ParagraphCommitResult()
        data class Unsupported(val issue: CapabilityIssue) : ParagraphCommitResult()
    }

    private data class EnhancedParagraph(
        val source: HTMLElement,
        val originalContent: DocumentFragment,
        val lowered: LoweredParagraph,
        val originalRenderedAttribute: String?,
        val originalPreparedFlowAttribute: String?,
        val originalCanonicalSourceAttribute: String?,
        val originalExactPreparedDomAttribute: String?,
        val originalLangAttribute: String?,
        val originalStyleAttribute: String?,
        val originalPosition: String,
        val originalPositionPriority: String,
        val originalInlineSize: String,
        val originalInlineSizePriority: String,
        val originalFontSize: String,
        val originalFontSizePriority: String,
        val originalHostInlineSizeAttribute: String?,
        var lastMeasure: Float? = null,
        var containingBlockApplied: Boolean = false,
        var hostInlineSizeApplied: String? = null,
        val hostFontSizeApplied: String? = null,
    )

    private data class SourceInlineSize(
        val borderBoxWidth: Double,
        val contentBoxWidth: Double,
        val borderBoxSizing: Boolean,
    )

    private data class LiveParagraphSnapshot(
        val paragraph: EnhancedParagraph,
        val content: DocumentFragment,
        val renderedAttribute: String?,
        val preparedFlowAttribute: String?,
        val canonicalSourceAttribute: String?,
        val exactPreparedDomAttribute: String?,
        val langAttribute: String?,
        val styleAttribute: String?,
        val capabilityNameAttribute: String?,
        val capabilityDetailAttribute: String?,
        val lastMeasure: Float?,
        val containingBlockApplied: Boolean,
        val hostInlineSizeApplied: String?,
        val hostInlineSizeAttribute: String?,
        val originalContentHadChildren: Boolean,
    )

    data class CapabilityIssue(
        val name: String,
        val detail: String,
        val element: HTMLElement,
        val reportToConsole: Boolean = true,
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

    private fun captureSourceInlineSize(paragraph: HTMLElement): SourceInlineSize =
        SourceInlineSize(
            borderBoxWidth = paragraph.getBoundingClientRect().width,
            contentBoxWidth = elementContentWidth(paragraph),
            borderBoxSizing =
                computedStyle(paragraph, "box-sizing").trim().lowercase() == "border-box",
        )

    private fun applyConfiguredHostFontSize(paragraph: HTMLElement, fontSize: Float?): String? {
        if (fontSize == null) return null
        paragraph.style.setProperty("font-size", "${fontSize}px", "important")
        return paragraph.style.getPropertyValue("font-size")
    }

    private fun responsiveSourceMeasure(paragraph: HTMLElement, configuredFontSize: Float?): Float {
        if (configuredFontSize == null) {
            val computedFontSize = parseCssPx(computedStyle(paragraph, "font-size"))
                ?: DEFAULT_FONT_SIZE
            return effectiveLineMeasure(sourceParagraphWidth(paragraph), computedFontSize)
        }
        val originalStyle = paragraph.getAttribute("style")
        paragraph.style.setProperty("font-size", "${configuredFontSize}px", "important")
        return try {
            effectiveLineMeasure(sourceParagraphWidth(paragraph), configuredFontSize)
        } finally {
            if (originalStyle == null) {
                paragraph.removeAttribute("style")
            } else {
                paragraph.setAttribute("style", originalStyle)
            }
        }
    }

    private fun stabilizeContentSizedItemInlineSize(
        paragraph: HTMLElement,
        source: SourceInlineSize,
    ): String? {
        val empty = captureSourceInlineSize(paragraph)
        val sourceUsedInlineSize = if (source.borderBoxSizing) {
            source.borderBoxWidth
        } else {
            source.contentBoxWidth
        }
        val emptyUsedInlineSize = if (source.borderBoxSizing) {
            empty.borderBoxWidth
        } else {
            empty.contentBoxWidth
        }
        // SourceMeasureBeforeCustodyTransfer: flex/grid items and descendants
        // of shrink-to-fit ancestors can derive their used inline size from the
        // semantic children that Tiqian moves into source custody. Detect that
        // real dependency from the before/after used size rather than guessing
        // a finite set of parent display modes. Ordinary blocks keep their host
        // auto sizing; only a custody-induced width change is stabilized.
        if (
            !sourceUsedInlineSize.isFinite() || sourceUsedInlineSize <= 0.0 ||
            !emptyUsedInlineSize.isFinite() ||
            kotlin.math.abs(sourceUsedInlineSize - emptyUsedInlineSize) < 0.5
        ) return null
        val usedInlineSize = sourceUsedInlineSize
        if (!usedInlineSize.isFinite() || usedInlineSize <= 0.0) return null
        val serialized = "${usedInlineSize}px"
        paragraph.style.setProperty("inline-size", serialized, "important")
        paragraph.setAttribute(HOST_INLINE_SIZE_ATTRIBUTE, "true")
        return serialized
    }

    private fun restoreParagraph(paragraph: EnhancedParagraph) {
        releasePreparedParagraphDomStyles(paragraph.source)
        while (paragraph.source.firstChild != null) {
            paragraph.source.removeChild(paragraph.source.firstChild!!)
        }
        paragraph.source.appendChild(paragraph.originalContent)
        restoreAttribute(paragraph.source, "data-tq-rendered", paragraph.originalRenderedAttribute)
        restoreAttribute(
            paragraph.source,
            "data-tq-canonical-plain",
            paragraph.originalPreparedFlowAttribute,
        )
        restoreAttribute(
            paragraph.source,
            CANONICAL_SOURCE_ATTRIBUTE,
            paragraph.originalCanonicalSourceAttribute,
        )
        restoreAttribute(
            paragraph.source,
            EXACT_PREPARED_DOM_ATTRIBUTE,
            paragraph.originalExactPreparedDomAttribute,
        )
        paragraph.source.removeAttribute(RUNTIME_RENDER_FONT_ATTRIBUTE)
        restoreAttribute(paragraph.source, "lang", paragraph.originalLangAttribute)
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
        val appliedInlineSize = paragraph.hostInlineSizeApplied
        if (
            appliedInlineSize != null &&
            paragraph.source.getAttribute(HOST_INLINE_SIZE_ATTRIBUTE) == "true" &&
            paragraph.source.style.getPropertyValue("inline-size") == appliedInlineSize &&
            paragraph.source.style.getPropertyPriority("inline-size") == "important"
        ) {
            if (paragraph.originalInlineSize.isEmpty()) {
                paragraph.source.style.removeProperty("inline-size")
            } else {
                paragraph.source.style.setProperty(
                    "inline-size",
                    paragraph.originalInlineSize,
                    paragraph.originalInlineSizePriority,
                )
            }
        }
        val appliedFontSize = paragraph.hostFontSizeApplied
        if (
            appliedFontSize != null &&
            paragraph.source.style.getPropertyValue("font-size") == appliedFontSize &&
            paragraph.source.style.getPropertyPriority("font-size") == "important"
        ) {
            if (paragraph.originalFontSize.isEmpty()) {
                paragraph.source.style.removeProperty("font-size")
            } else {
                paragraph.source.style.setProperty(
                    "font-size",
                    paragraph.originalFontSize,
                    paragraph.originalFontSizePriority,
                )
            }
        }
        restoreAttribute(
            paragraph.source,
            HOST_INLINE_SIZE_ATTRIBUTE,
            paragraph.originalHostInlineSizeAttribute,
        )
        if (paragraph.originalStyleAttribute == null) {
            if (paragraph.source.getAttribute("style")?.isBlank() != false) {
                paragraph.source.removeAttribute("style")
            }
        }
        paragraph.containingBlockApplied = false
        paragraph.hostInlineSizeApplied = null
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
private object MarkdownParagraphLowerer {
    private val fontRoleClassifier = CjkFontRoleClassifier()
    private val graphemeSegmenter: JsAny? = createLowererGraphemeSegmenter()

    var lastIssue: TiqianWeb.CapabilityIssue? = null
        private set

    fun lower(paragraph: HTMLElement, options: TiqianWeb.EnhanceOptions): LoweredParagraph? {
        lastIssue = null
        val canonicalPrepared =
            paragraph.getAttribute("data-tq-rendered") == "true" &&
                paragraph.getAttribute("data-tq-canonical-plain") == "true"
        return withConfiguredFontSizeProbe(paragraph, options.fontSize) {
            if (canonicalPrepared) {
                withCanonicalPreparedHostStyleProbe(paragraph) {
                    lowerWithCurrentStyles(paragraph, options, canonicalPrepared = true)
                }
            } else {
                lowerWithCurrentStyles(paragraph, options, canonicalPrepared = false)
            }
        }
    }

    /**
     * ConfiguredFontSizeSingleSource: an explicit engine font size must be live
     * while descendant computed styles are sampled. Otherwise inherited links
     * and code runs are lowered at the host size even though the base run is
     * measured at the override. The host is restored before custody transfer;
     * the renderer then applies the same size for the enhanced paragraph.
     */
    private fun <T> withConfiguredFontSizeProbe(
        paragraph: HTMLElement,
        fontSize: Float?,
        block: () -> T,
    ): T {
        if (fontSize == null) return block()
        val originalStyle = paragraph.getAttribute("style")
        paragraph.style.setProperty("font-size", "${fontSize}px", "important")
        return try {
            block()
        } finally {
            if (originalStyle == null) {
                paragraph.removeAttribute("style")
            } else {
                paragraph.setAttribute("style", originalStyle)
            }
        }
    }

    private fun lowerWithCurrentStyles(
        paragraph: HTMLElement,
        options: TiqianWeb.EnhanceOptions,
        canonicalPrepared: Boolean,
    ): LoweredParagraph? {
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
        if (canonicalPrepared) {
            val source = canonicalPreparedPlainSource(paragraph)
            if (source.isBlank()) {
                lastIssue = TiqianWeb.CapabilityIssue("EmptyParagraph", "paragraph has no text", paragraph)
                return null
            }
            return LoweredParagraph(
                text = source,
                textStyle = baseStyle,
                lineHeight = lineHeight,
                spans = emptyList(),
                decorations = emptyList(),
                inlineBoxes = emptyList(),
                inlineObjects = emptyList(),
                domInlineObjects = emptyList(),
                sourceSpans = emptyList(),
                sourceBoundaries = emptySet(),
            )
        }
        generatedPseudoContentIssue(paragraph)?.let { detail ->
            lastIssue = TiqianWeb.CapabilityIssue(
                "UnsupportedGeneratedInlineContent",
                detail,
                paragraph,
            )
            return null
        }
        val builder = LoweringBuilder(
            sourceElement = paragraph,
            baseInlineStyle = baseInlineStyle,
            baseLineHeight = lineHeight,
            strongAsEmphasisMarks = options.strongAsEmphasisMarks,
        )
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

    /**
     * CanonicalPreparedHostStyleProbe: a direct-SSR prepared paragraph carries
     * `data-tq-rendered`, so the public replay CSS intentionally gives it
     * `line-height: 0` and `white-space: pre`. When a width miss falls back to
     * runtime layout, those are renderer-owned values rather than host
     * typography. Suppress the replay selector only while sampling computed
     * paragraph styles, then restore the attribute synchronously before any
     * layout mutation can be painted.
     */
    private fun <T> withCanonicalPreparedHostStyleProbe(
        paragraph: HTMLElement,
        block: () -> T,
    ): T {
        val rendered = paragraph.getAttribute("data-tq-rendered")
        paragraph.removeAttribute("data-tq-rendered")
        return try {
            block()
        } finally {
            if (rendered == null) {
                paragraph.removeAttribute("data-tq-rendered")
            } else {
                paragraph.setAttribute("data-tq-rendered", rendered)
            }
        }
    }

    private class LoweringBuilder(
        private val sourceElement: HTMLElement,
        private val baseInlineStyle: InlineStyle,
        private val baseLineHeight: Float,
        private val strongAsEmphasisMarks: Boolean,
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
            // RuntimeInlineCodeUsesResolvedBrowserFont: build-time snapshots
            // must fail closed without exact monospace font/box evidence, but
            // the live browser already exposes the resolved host font and box
            // metrics. Lower that run normally and let the sliced browser
            // shaping fallback handle Worker-ineligible rich paragraphs.
            inlineShapingStyleIssue(element, sourceElement)?.let { property ->
                return unsupported(
                    "UnsupportedInlineShapingStyle",
                    "${tag.lowercase()}:$property",
                )
            }
            val inheritedStrongWeight = style.cjkStrongBaseWeight
            val strongBaseWeight = if (tag == "STRONG" && strongAsEmphasisMarks) {
                inheritedStrongWeight ?: style.textStyle.fontWeight
            } else {
                null
            }
            val elementStyle = computedInlineStyle(element, style).let { computed ->
                if (tag == "STRONG" && strongAsEmphasisMarks) {
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

private fun canonicalPreparedPlainSource(parent: Node): String = buildString {
    fun appendNode(node: Node) {
        if (node.nodeType == Node.TEXT_NODE) {
            append(node.textContent.orEmpty())
            return
        }
        if (node.nodeType != Node.ELEMENT_NODE) return
        val element = node as Element
        if (element.hasAttribute("data-tq-copy-ignore")) return
        if (element.hasAttribute("data-tq-src")) {
            val following = element.nextSibling as? Element
            val pairedMandatoryBreak = element.hasAttribute("data-tq-hard-break") &&
                following?.tagName?.uppercase() == "BR" &&
                following.getAttribute("data-tq-engine-break") == "MandatoryBreak"
            if (!pairedMandatoryBreak) append(element.getAttribute("data-tq-src").orEmpty())
            return
        }
        if (element.tagName.uppercase() == "BR") {
            if (element.getAttribute("data-tq-engine-break") == "MandatoryBreak") append('\n')
            return
        }
        val children = element.childNodes
        for (index in 0 until children.length) children.item(index)?.let(::appendNode)
    }
    val children = parent.childNodes
    for (index in 0 until children.length) children.item(index)?.let(::appendNode)
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

private const val WORKER_RECORD_SEPARATOR = '\u001e'
private const val WORKER_FIELD_SEPARATOR = '\u001d'
private const val WORKER_FAMILY_SEPARATOR = '\u001f'

private fun workerLayoutRequestJson(
    paragraph: HTMLElement,
    lowered: LoweredParagraph,
    width: Float,
    firstLineIndentIc: Float,
): String {
    val textSpans = lowered.spans.joinToString(WORKER_RECORD_SEPARATOR.toString()) { span ->
        listOf(
            span.range.start,
            span.range.end,
            span.style.fontFamilies.joinToString(WORKER_FAMILY_SEPARATOR.toString()),
            span.style.fontSize,
            span.style.fontWeight,
            span.style.italic,
            span.style.baselineShift,
        ).joinToString(WORKER_FIELD_SEPARATOR.toString())
    }
    val inlineBoxes = lowered.inlineBoxes.joinToString(WORKER_RECORD_SEPARATOR.toString()) { box ->
        listOf(
            box.range.start,
            box.range.end,
            box.inlineStart,
            box.inlineEnd,
        ).joinToString(WORKER_FIELD_SEPARATOR.toString())
    }
    return buildString {
        append('{')
        append("\"text\":").appendWorkerJsonString(lowered.text).append(',')
        append("\"maxWidthPx\":").append(width).append(',')
        append("\"fontFamilies\":").appendWorkerJsonString(
            lowered.textStyle.fontFamilies.joinToString(WORKER_FAMILY_SEPARATOR.toString()),
        ).append(',')
        append("\"fontSizePx\":").append(lowered.textStyle.fontSize).append(',')
        append("\"lineHeightPx\":").append(lowered.lineHeight).append(',')
        append("\"locale\":").appendWorkerJsonString(lowered.textStyle.locale).append(',')
        append("\"fontWeight\":").append(lowered.textStyle.fontWeight).append(',')
        append("\"italic\":").append(lowered.textStyle.italic).append(',')
        append("\"firstLineIndentIc\":").append(firstLineIndentIc).append(',')
        append("\"sourceBoundaries\":").appendWorkerJsonString(
            lowered.sourceBoundaries.sorted().joinToString(","),
        ).append(',')
        append("\"textSpans\":").appendWorkerJsonString(textSpans).append(',')
        append("\"inlineBoxes\":").appendWorkerJsonString(inlineBoxes).append(',')
        append("\"semantics\":[")
        lowered.sourceSpans.forEachIndexed { index, span ->
            if (index > 0) append(',')
            append('{')
            append("\"start\":").append(span.range.start).append(',')
            append("\"end\":").append(span.range.end).append(',')
            append("\"tagName\":").appendWorkerJsonString(span.element.tagName.lowercase()).append(',')
            append("\"attributes\":").append(elementAttributesJson(span.element)).append(',')
            append("\"order\":").append(index)
            append('}')
        }
        append("],\"renderInlineBoxes\":[")
        lowered.inlineBoxes.forEachIndexed { index, box ->
            if (index > 0) append(',')
            append('{')
            append("\"start\":").append(box.range.start).append(',')
            append("\"end\":").append(box.range.end).append(',')
            append("\"inlineStartPx\":").append(box.inlineStart).append(',')
            append("\"inlineEndPx\":").append(box.inlineEnd)
            append('}')
        }
        append("],\"sourceTag\":").appendWorkerJsonString(paragraph.tagName.lowercase())
        append('}')
    }
}

private fun StringBuilder.appendWorkerJsonString(value: String): StringBuilder {
    append('"')
    for (char in value) {
        when (char) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000c' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (char.code < 0x20) {
                append("\\u").append(char.code.toString(16).padStart(4, '0'))
            } else {
                append(char)
            }
        }
    }
    return append('"')
}

private fun LoweredParagraph.isCanonicalPlainParagraph(): Boolean =
    spans.isEmpty() &&
        decorations.isEmpty() &&
        inlineBoxes.isEmpty() &&
        inlineObjects.isEmpty() &&
        domInlineObjects.isEmpty() &&
        sourceSpans.isEmpty()

private fun isExactFontSessionCapabilityFailure(error: Throwable): Boolean {
    return isExactFontSessionCapabilityFailureDetail(error.message.orEmpty())
}

private fun isExactFontSessionCapabilityFailureDetail(detail: String): Boolean =
    EXACT_FONT_SESSION_CAPABILITY_FAILURES.any(detail::contains)

/**
 * SemanticExactRunFallback: rich paragraphs may intentionally introduce a
 * different font family (for example inline code). Preserve the exact server
 * HarfBuzz replay for every covered run and delegate only the unsupported run
 * to the browser adapter, whose semantic clone keeps the corresponding host style.
 */
private class ExactSessionBrowserFallbackTextShaper(
    private val exact: TextShaper,
    private val browser: TextShaper,
) : TextShaper {
    override fun shape(input: ShapingInput): ShapingResult = try {
        exact.shape(input)
    } catch (error: Throwable) {
        if (!isExactFontSessionCapabilityFailure(error)) throw error
        browser.shape(input)
    }
}

private class ExactSessionBrowserFallbackFontMetricsResolver(
    private val exact: FontMetricsResolver,
    private val browser: FontMetricsResolver,
) : FontMetricsResolver {
    override fun resolve(request: FontMetricsRequest): RawFontMetrics = try {
        exact.resolve(request)
    } catch (error: Throwable) {
        if (!isExactFontSessionCapabilityFailure(error)) throw error
        browser.resolve(request)
    }
}

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

// InlineShapingStyleParityContract: TextStyle currently models family, size,
// weight, italic and baseline shift. The renderer preserves semantic wrappers,
// so an inherited shaping property that changes only inside such a wrapper
// would otherwise make browser glyph advances diverge from LayoutResult.
private val unsupportedInlineShapingProperties = listOf(
    "font-feature-settings",
    "font-variation-settings",
    "font-stretch",
    "font-kerning",
    "font-optical-sizing",
    "font-variant-ligatures",
    "font-variant-alternates",
    "font-variant-east-asian",
    "font-variant-caps",
    "font-variant-numeric",
    "font-variant-position",
    "font-language-override",
    "font-size-adjust",
    "word-spacing",
    "text-transform",
    "text-rendering",
)

private fun inlineShapingStyleIssue(element: Element, paragraph: Element): String? =
    unsupportedInlineShapingProperties.firstOrNull { property ->
        computedStyle(element, property).trim().lowercase() !=
            computedStyle(paragraph, property).trim().lowercase()
    }

// RootGeneratedInlineContentMustStayNative: a pseudo directly on the paragraph
// has no source range to which InlineBoxSpan can attach. Descendant semantic
// elements are supported instead: measuredInlineEdge() reserves their actual
// ::before/::after advance while the one cloned semantic element keeps the host
// pseudo, copy, accessibility and interaction behavior intact.
private fun generatedPseudoContentIssue(element: Element): String? {
    for (pseudo in listOf("::before", "::after")) {
        val content = flowParticipatingPseudoContent(element, pseudo)?.trim()
        if (content != null) {
            return "${element.tagName.lowercase()}$pseudo:$content"
        }
    }
    return null
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
@JsFun("(event) => event.detail && event.detail.root ? event.detail.root : null")
private external fun eventRoot(event: Event): HTMLElement?
@JsFun("(event) => event.detail && event.detail.paragraph ? event.detail.paragraph : null")
private external fun eventParagraph(event: Event): HTMLElement?
@JsFun("(event) => event.detail && event.detail.options ? event.detail.options : null")
private external fun eventOptions(event: Event): JsAny?
@JsFun("(event, value) => { if (event.detail) event.detail.result = value; }")
private external fun setEventResult(event: Event, value: String?)
@JsFun("(options, name) => options && options[name] != null ? String(options[name]) : null")
private external fun optionString(options: JsAny?, name: String): String?
@JsFun("(options, name) => { if (!options || options[name] == null) return NaN; const number = Number(options[name]); return Number.isFinite(number) ? number : NaN; }")
private external fun optionNumber(options: JsAny?, name: String): Double
@JsFun("(options, name) => options && typeof options[name] === 'boolean' ? options[name] : null")
private external fun optionBoolean(options: JsAny?, name: String): Boolean?
@JsFun("(options, name) => options && options[name] && typeof options[name] === 'object' ? options[name] : null")
private external fun optionObject(options: JsAny?, name: String): JsAny?
@JsFun("(host, planJson, locale) => globalThis.__TiqianPreparedDomRenderer.render(host, planJson, locale)")
private external fun renderPreparedParagraphDom(
    host: HTMLElement,
    planJson: String,
    locale: String,
): JsAny?
@JsFun("(element) => JSON.stringify(Array.from(element.attributes || [], (attribute) => [attribute.name, attribute.value]))")
private external fun elementAttributesJson(element: Element): String
@JsFun("(element, sessionKey, requestText) => globalThis.__TiqianLayoutWorker && typeof globalThis.__TiqianLayoutWorker.take === 'function' ? globalThis.__TiqianLayoutWorker.take(element, sessionKey, requestText) : null")
private external fun takePreparedWorkerLayoutPlan(
    element: HTMLElement,
    sessionKey: String,
    requestText: String,
): String?
@JsFun("(element, sessionKey, requestText) => globalThis.__TiqianLayoutWorker && typeof globalThis.__TiqianLayoutWorker.issue === 'function' ? globalThis.__TiqianLayoutWorker.issue(element, sessionKey, requestText) : null")
private external fun preparedWorkerLayoutIssue(
    element: HTMLElement,
    sessionKey: String,
    requestText: String,
): String?
@JsFun(
    """(host, recordJson, locale, sourceText) => {
      const record = JSON.parse(recordJson);
      return globalThis.__TiqianPreparedDomRenderer.render(
        host,
        record.plan,
        locale,
        {
          sourceText,
          semantics: record.semantics || [],
          inlineBoxes: record.inlineBoxes || []
        }
      );
    }""",
)
private external fun renderPreparedWorkerParagraphDom(
    host: HTMLElement,
    recordJson: String,
    locale: String,
    sourceText: String,
): JsAny?
@JsFun("(host) => !!(globalThis.__TiqianPreparedDomRenderer && globalThis.__TiqianPreparedDomRenderer.release && globalThis.__TiqianPreparedDomRenderer.release(host) === true)")
private external fun releasePreparedParagraphDomStyles(host: HTMLElement): Boolean
@JsFun("(root) => !!(globalThis.__TiqianPreparedDomRenderer && globalThis.__TiqianPreparedDomRenderer.releaseRoot && globalThis.__TiqianPreparedDomRenderer.releaseRoot(root) === true)")
private external fun releasePreparedRootDomStyles(root: HTMLElement): Boolean
@JsFun("(host, width) => globalThis.__TiqianPreparedDomValidator && typeof globalThis.__TiqianPreparedDomValidator.issue === 'function' ? globalThis.__TiqianPreparedDomValidator.issue(host, width) : 'PreparedDomValidatorUnavailable'")
private external fun validatePreparedParagraphDom(host: HTMLElement, width: Double): String?
@JsFun(
    """(element) => {
      const rect = element.getBoundingClientRect();
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      if (rect.bottom >= 0 && rect.top <= viewportHeight) return 0;
      return rect.bottom < 0 ? -rect.bottom : rect.top - viewportHeight;
    }""",
)
private external fun paragraphViewportDistance(element: HTMLElement): Double
@JsFun(
    """(element) => {
      const rect = element.getBoundingClientRect();
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      return rect.bottom >= 0 && rect.top <= viewportHeight;
    }""",
)
private external fun paragraphIsWithinProgressiveForegroundRange(element: HTMLElement): Boolean
@JsFun(
    """() => {
      try {
        return typeof navigator !== "undefined" && navigator.scheduling &&
          typeof navigator.scheduling.isInputPending === "function" &&
          navigator.scheduling.isInputPending({ includeContinuous: true }) === true;
      } catch (error) {
        return false;
      }
    }""",
)
private external fun progressiveInputIsPending(): Boolean
@JsFun(
    """(callback, idle) => {
      const MINIMUM_IDLE_BUDGET_MS = 8;
      const token = { kind: "cooperative", idleId: 0, frameId: 0 };
      const inputIsPending = () => {
        try {
          return typeof navigator !== "undefined" && navigator.scheduling &&
            typeof navigator.scheduling.isInputPending === "function" &&
            navigator.scheduling.isInputPending({ includeContinuous: true }) === true;
        } catch (error) {
          return false;
        }
      };
      const scheduleFrame = (continuation) => {
        token.frameId = requestAnimationFrame(() => {
          token.frameId = 0;
          if (inputIsPending()) scheduleFrame(continuation);
          else continuation();
        });
      };
      if (idle) {
        // PendingInputAwareIdleTail: layout is already complete in the Worker;
        // each callback commits at most one offscreen paragraph. A normal
        // 60 Hz idle period cannot provide the old 20 ms threshold, so waiting
        // for it made a quiet resized article advance only once per timeout.
        // Require one 8 ms commit slice, and yield only to input that is still
        // pending rather than to an arbitrary post-scroll quiet window.
        const requestWhenIdle = () => {
          if (typeof requestIdleCallback === "function" &&
              typeof cancelIdleCallback === "function") {
            token.idleId = requestIdleCallback((deadline) => {
              token.idleId = 0;
              if (inputIsPending() || (!deadline.didTimeout &&
                  deadline.timeRemaining() < MINIMUM_IDLE_BUDGET_MS)) {
                scheduleFrame(requestWhenIdle);
              } else {
                callback();
              }
            }, { timeout: 1000 });
          } else {
            scheduleFrame(callback);
          }
        };
        requestWhenIdle();
        return token;
      }
      scheduleFrame(callback);
      return token;
    }""",
)
private external fun scheduleProgressiveCallback(callback: () -> Unit, idle: Boolean): JsAny
@JsFun(
    """(token) => {
      if (token.idleId && typeof cancelIdleCallback === "function") cancelIdleCallback(token.idleId);
      if (token.frameId) cancelAnimationFrame(token.frameId);
    }""",
)
private external fun cancelProgressiveCallback(token: JsAny)
@JsFun("(element) => { const style = getComputedStyle(element); const number = (value) => Number.parseFloat(value) || 0; return element.getBoundingClientRect().width - number(style.paddingLeft) - number(style.paddingRight) - number(style.borderLeftWidth) - number(style.borderRightWidth); }")
private external fun elementContentWidth(element: HTMLElement): Double
// NestedInlineBoxEdgeOwnership: compare an inline's flow edge with its direct
// in-flow content boundary. A descendant semantic box owns its own padding,
// margins and pseudo content, so an outer <sup>/<span> must not reserve that
// same edge again merely because Range.getClientRects() ends on a deep text leaf.
@JsFun(
    """(element, side) => {
      const style = getComputedStyle(element);
      const margin = Number.parseFloat(
        side === "start" ? style.marginLeft : style.marginRight
      ) || 0;
      const boxes = Array.from(element.getClientRects()).filter((rect) => rect.width || rect.height);
      if (!boxes.length) return margin;
      const boundary = (node) => {
        if (node.nodeType === Node.TEXT_NODE) {
          const range = document.createRange();
          range.selectNodeContents(node);
          const rects = Array.from(range.getClientRects()).filter((rect) => rect.width || rect.height);
          if (!rects.length) return null;
          return side === "start" ? rects[0].left : rects[rects.length - 1].right;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return null;
        const childStyle = getComputedStyle(node);
        if (childStyle.display === "none" || childStyle.position === "absolute" ||
            childStyle.position === "fixed") return null;
        const rects = Array.from(node.getClientRects()).filter((rect) => rect.width || rect.height);
        if (rects.length) {
          const rect = side === "start" ? rects[0] : rects[rects.length - 1];
          const childMargin = Number.parseFloat(
            side === "start" ? childStyle.marginLeft : childStyle.marginRight
          ) || 0;
          return side === "start" ? rect.left - childMargin : rect.right + childMargin;
        }
        const children = Array.from(node.childNodes);
        if (side === "end") children.reverse();
        for (const child of children) {
          const value = boundary(child);
          if (value != null) return value;
        }
        return null;
      };
      const children = Array.from(element.childNodes);
      if (side === "end") children.reverse();
      let contentBoundary = null;
      for (const child of children) {
        contentBoundary = boundary(child);
        if (contentBoundary != null) break;
      }
      if (contentBoundary == null) return margin;
      const flowEdge = side === "start"
        ? boxes[0].left - margin
        : boxes[boxes.length - 1].right + margin;
      return side === "start"
        ? Math.max(0, contentBoundary - flowEdge)
        : Math.max(0, flowEdge - contentBoundary);
    }""",
)
private external fun measuredInlineEdge(element: Element, side: String): Double
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
@JsFun("(element, property) => getComputedStyle(element).getPropertyValue(property)")
private external fun computedStyle(element: Element, property: String): String
@JsFun(
    """(element, pseudo) => {
      const style = getComputedStyle(element, pseudo);
      const content = style.getPropertyValue('content').trim();
      if (!content || content === 'none' || content === 'normal' || content === '""' || content === "''") return null;
      if (style.display === 'none' || style.position === 'absolute' || style.position === 'fixed') return null;
      return content;
    }""",
)
private external fun flowParticipatingPseudoContent(element: Element, pseudo: String): String?
@JsFun(
    """() => typeof Intl !== 'undefined' && Intl.Segmenter
      ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
      : null""",
)
private external fun createLowererGraphemeSegmenter(): JsAny?
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
@JsFun("(element, selector) => !!element.closest(selector)")
private external fun hasClosest(element: HTMLElement, selector: String): Boolean
@JsFun(
    "(paragraph, root, selector) => { const owner = paragraph.closest(selector); return !owner || owner === root || !root.contains(owner); }",
)
private external fun belongsToRootScope(paragraph: HTMLElement, root: HTMLElement, selector: String): Boolean
@JsFun("(message) => console.warn(message)")
private external fun consoleWarn(message: String)
@JsFun("() => performance.now()")
private external fun performanceNow(): Double
@JsFun("(root) => { const value = Number(root.getAttribute('data-tiqian-snapshot-count')); return Number.isSafeInteger(value) && value > 0 ? value : 0; }")
private external fun observableSnapshotCount(root: HTMLElement): Int
@JsFun("(root, enhancedCount, runtimeEnhancedCount, snapshotCount, issueCount, durationMs, maxSliceMs, stale) => root.dispatchEvent(new CustomEvent('tiqian:ready', { detail: { enhancedCount, runtimeEnhancedCount, snapshotCount, issueCount, durationMs, maxSliceMs, stale } }))")
private external fun dispatchTiqianReady(
    root: HTMLElement,
    enhancedCount: Int,
    runtimeEnhancedCount: Int,
    snapshotCount: Int,
    issueCount: Int,
    durationMs: Double,
    maxSliceMs: Double,
    stale: Boolean,
)
@JsFun("(root, enhancedCount, runtimeEnhancedCount, snapshotCount, issueCount, durationMs, maxSliceMs, failed, error, stale) => root.dispatchEvent(new CustomEvent('tiqian:relayout-ready', { detail: { enhancedCount, runtimeEnhancedCount, snapshotCount, issueCount, durationMs, maxSliceMs, relayout: true, failed, error, stale } }))")
private external fun dispatchTiqianRelayoutReady(
    root: HTMLElement,
    enhancedCount: Int,
    runtimeEnhancedCount: Int,
    snapshotCount: Int,
    issueCount: Int,
    durationMs: Double,
    maxSliceMs: Double,
    failed: Boolean,
    error: String?,
    stale: Boolean,
)
@JsFun("(root, kind, detail, durationMs, maxSliceMs) => root.dispatchEvent(new CustomEvent(kind === 'Relayout' ? 'tiqian:relayout-error' : 'tiqian:error', { detail: { kind, error: detail, durationMs, maxSliceMs } }))")
private external fun dispatchTiqianProgressiveError(
    root: HTMLElement,
    kind: String,
    detail: String,
    durationMs: Double,
    maxSliceMs: Double,
)
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
            workerLayoutRequest(root, paragraph, options) {
              var detail = {
                root: root || document.body,
                paragraph: paragraph,
                options: options || {},
                result: null
              };
              document.dispatchEvent(new CustomEvent("tiqian:worker-layout-request", { detail }));
              return detail.result;
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

/**
 * Package entrypoints install `SourceFaithfulSemanticClipboard` from copy.js.
 * This fallback mirrors that contract for direct Kotlin/JS runtime consumers.
 */
private fun installTiqianCopyHandler() {
    js(
        """
        if (globalThis.__TiqianInstallCopyHandler) {
          globalThis.__TiqianInstallCopyHandler(document);
        } else if (!globalThis.__tiqianCopyHandlerInstalled) {
          var blockElements = new Set([
            "ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DD", "DIV", "DL", "DT",
            "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER", "FORM", "H1", "H2", "H3",
            "H4", "H5", "H6", "HEADER", "HR", "LI", "MAIN", "NAV", "OL", "P", "PRE",
            "SECTION", "TABLE", "TR", "UL"
          ]);
          var engineFlowStyleProperties = [
            "white-space-collapse", "overflow-wrap", "text-autospace", "text-spacing-trim",
            "text-wrap-mode", "-webkit-hyphens", "hyphens", "word-break"
          ];
          var clipboardTextForNode;
          var clipboardTextForChildren = function (parent) {
            var children = Array.from(parent.childNodes || []);
            var containsBlock = children.some(function (child) {
              return child.nodeType === 1 && blockElements.has(child.tagName);
            });
            var result = "";
            var previous = null;
            children.forEach(function (child) {
              if (containsBlock && child.nodeType === 3 && !(child.data || "").trim()) return;
              var item = clipboardTextForNode(child);
              if (previous && (previous.block || item.block) && result && item.text &&
                  !result.endsWith("\n") && !item.text.startsWith("\n")) {
                result += "\n";
              }
              result += item.text;
              previous = item;
            });
            return result;
          };
          clipboardTextForNode = function (node) {
            if (node.nodeType === 3) return { block: false, text: node.data || "" };
            if (node.nodeType !== 1) return { block: false, text: "" };
            if (node.tagName === "BR") return { block: false, text: "\n" };
            return {
              block: blockElements.has(node.tagName),
              text: clipboardTextForChildren(node)
            };
          };
          globalThis.__TiqianCreateClipboardPayload = function (frag, documentObject) {
            if (!frag || !frag.querySelectorAll || !documentObject || !documentObject.createElement) {
              return { text: "", html: "" };
            }
            frag.querySelectorAll("[data-tq-copy-ignore]").forEach(function (el) { el.remove(); });
            frag.querySelectorAll("[data-tq-src]").forEach(function (el) {
              if (el.hasAttribute("data-tq-hard-break")) {
                var semanticBreak = el.nextElementSibling;
                if (semanticBreak && semanticBreak.matches &&
                    semanticBreak.matches("br[data-tq-engine-break='MandatoryBreak']")) {
                  el.remove();
                } else {
                  el.replaceWith(documentObject.createElement("br"));
                }
              } else {
                el.replaceWith(documentObject.createTextNode(el.getAttribute("data-tq-src") || ""));
              }
            });
            frag.querySelectorAll(
              "[data-tq-engine-break]:not([data-tq-engine-break='MandatoryBreak'])"
            ).forEach(function (el) { el.remove(); });
            Array.from(frag.querySelectorAll("[data-tq-geometry]")).reverse().forEach(function (el) {
              el.replaceWith.apply(el, Array.from(el.childNodes));
            });
            frag.querySelectorAll("*").forEach(function (el) {
              var rendered = el.hasAttribute("data-tq-rendered");
              var sourceSemantic = el.hasAttribute("data-tq-source-semantic");
              var cjkStrong = el.hasAttribute("data-tq-cjk-emphasis");
              if (el.style && (rendered || sourceSemantic)) {
                engineFlowStyleProperties.forEach(function (property) { el.style.removeProperty(property); });
                if (rendered) el.style.removeProperty("position");
                if (!(el.getAttribute("style") || "").trim()) el.removeAttribute("style");
              }
              if (cjkStrong && el.style) {
                el.style.removeProperty("font-weight");
                if (!(el.getAttribute("style") || "").trim()) el.removeAttribute("style");
              }
              Array.from(el.attributes).forEach(function (attribute) {
                if (attribute.name.startsWith("data-tq-")) el.removeAttribute(attribute.name);
              });
            });
            var wrapper = documentObject.createElement("div");
            wrapper.appendChild(frag);
            return { text: clipboardTextForChildren(wrapper), html: wrapper.innerHTML };
          };
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
              var payload = globalThis.__TiqianCreateClipboardPayload(range.cloneContents(), document);
              if ((payload.text || payload.html) && e.clipboardData) {
                e.clipboardData.setData("text/plain", payload.text);
                if (payload.html) e.clipboardData.setData("text/html", payload.html);
                e.preventDefault();
              }
            });
          }
        }
        """,
    )
}

private const val DEFAULT_FONT_SIZE = 19f
private const val INLINE_EDGE_EPSILON = 0.01f
private const val ZERO_ADVANCE_EPSILON = 0.01f
private const val CAPABILITY_DETAIL_LIMIT = 512
private const val MAX_PROGRESSIVE_SLICE_MS = 8.0
private const val MAX_PROGRESSIVE_ITEMS_PER_SLICE = 8
// ViewportForegroundIdleTail: visible and one-viewport-adjacent paragraphs
// receive frame-budgeted work. The remaining native source stays responsive
// and advances one paragraph per input-gapped idle callback so long articles
// cannot occupy every animation frame during scrolling or window resizing.
private const val MAX_PROGRESSIVE_IDLE_ITEMS_PER_SLICE = 1
private const val CANONICAL_SOURCE_ATTRIBUTE = "data-tq-canonical-source"
private const val EXACT_PREPARED_DOM_ATTRIBUTE = "data-tq-exact-prepared-dom"
private const val RUNTIME_RENDER_FONT_ATTRIBUTE = "data-tq-runtime-render-font"
private const val HOST_INLINE_SIZE_ATTRIBUTE = "data-tq-host-inline-size"
private const val RELAYOUT_ERROR_ATTRIBUTE = "data-tiqian-relayout-error"
private const val EXACT_PREPARED_FALLBACK_ATTRIBUTE = "data-tiqian-exact-layout-fallback"
private const val DEFAULT_LINE_HEIGHT_MULTIPLIER = 1.75f
private const val DEFAULT_CJK_FONT_FAMILY = "\"MiSans VF\", \"PingFang SC\", \"Noto Sans CJK SC\", sans-serif"
private const val DEFAULT_LATIN_FONT_FAMILY = "\"InterVariable\", \"Inter\", \"MiSans VF\", sans-serif"
private const val DEFAULT_MONOSPACE_FONT_FAMILY =
    "\"JetBrains Mono Variable\", \"SFMono-Regular\", Menlo, Consolas, \"MiSans VF\", monospace"
private const val DEFAULT_CJK_SERIF_FONT_FAMILY = "\"MetroSungPlus-SC\", \"Songti SC\", serif"
private const val DEFAULT_LATIN_SERIF_FONT_FAMILY = "Georgia, \"Times New Roman\", serif"

private val EXACT_FONT_SESSION_CAPABILITY_FAILURES = listOf(
    "NoExactFontFace",
    "MissingGlyph",
    "MissingServerShapingReplay",
    "NoExactMetricFace",
    "NonUniformUnicodeRangeMetrics",
)

private val WIDTH_DEPENDENT_CAPABILITY_ISSUES = setOf(
    "InlineCloneDecorationBreakUnsupported",
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
