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
    private val states = LinkedHashMap<HTMLElement, RootState>()
    private val progressiveJobs = LinkedHashMap<HTMLElement, ProgressiveJob>()
    private val pendingCjkDashRetries = LinkedHashMap<HTMLElement, EnhanceOptions>()

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
        document.addEventListener("tiqian:enhance-atomically", listener@{ event: Event ->
            val root = eventRoot(event) ?: document.body ?: return@listener
            enhanceAtomically(root, optionsFromJs(eventOptions(event)))
        })
        document.addEventListener("tiqian:retry-cjk-dash", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            retryCjkDashCapability(root, optionsFromJs(eventOptions(event)))
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
        document.addEventListener("tiqian:cancel-layout-work", listener@{ event: Event ->
            val root = eventRoot(event) ?: return@listener
            cancelProgressiveJob(root)
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
        val candidates = paragraphCandidates(root, state.options.paragraphSelector)
            .withIndex()
            .sortedWith(
                compareBy<IndexedValue<HTMLElement>> {
                    paragraphViewportDistance(it.value)
                }.thenBy { it.index },
            )
            .map { it.value }
        val capturedMeasures = candidates.map { paragraph ->
            val fontSize = state.options.fontSize
                ?: parseCssPx(computedStyle(paragraph, "font-size"))
                ?: DEFAULT_FONT_SIZE
            effectiveLineMeasure(sourceParagraphWidth(paragraph), fontSize)
        }
        var stale = false
        fun liveMeasure(index: Int): Float {
            val paragraph = candidates[index]
            val fontSize = state.options.fontSize
                ?: parseCssPx(computedStyle(paragraph, "font-size"))
                ?: DEFAULT_FONT_SIZE
            return effectiveLineMeasure(
                sourceParagraphWidth(paragraph),
                fontSize,
            )
        }
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
            startedAt = performanceNow(),
        )
        states[root] = state
        publishState(state, keepEmpty = true)
        startProgressiveJob(job)
    }

    /**
     * ResponsiveTypographyAtomicRefresh: an already rendered root must not be
     * restored and rebuilt across multiple paints when a resize breakpoint
     * changes shaping inputs. Re-lower and render synchronously in one event
     * callback; the reported max slice is the full long-task cost so callers can
     * distinguish this safety boundary from ordinary progressive loading.
     */
    private fun enhanceAtomically(root: HTMLElement, options: EnhanceOptions) {
        val startedAt = performanceNow()
        try {
            val enhancedCount = enhance(root, options)
            val duration = performanceNow() - startedAt
            dispatchTiqianRelayoutReady(
                root = root,
                enhancedCount = enhancedCount,
                issueCount = states[root]?.issues?.size ?: 0,
                durationMs = duration,
                maxSliceMs = duration,
                failed = false,
                error = null,
                stale = false,
            )
        } catch (error: Throwable) {
            val detail = (error.message ?: error.toString()).take(CAPABILITY_DETAIL_LIMIT)
            destroy(root)
            root.setAttribute(RELAYOUT_ERROR_ATTRIBUTE, detail)
            val duration = performanceNow() - startedAt
            dispatchTiqianProgressiveError(root, ProgressiveJobKind.Relayout.name, detail, duration, duration)
            dispatchTiqianRelayoutReady(
                root = root,
                enhancedCount = 0,
                issueCount = 1,
                durationMs = duration,
                maxSliceMs = duration,
                failed = true,
                error = detail,
                stale = false,
            )
        }
    }

    fun destroy(root: HTMLElement) {
        pendingCjkDashRetries.remove(root)
        cancelProgressiveJob(root)
        val state = states.remove(root)
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
        root.removeAttribute("data-tiqian-enhanced")
        root.removeAttribute("data-tiqian-enhanced-count")
        root.removeAttribute("data-tiqian-issue-count")
        root.removeAttribute(RELAYOUT_ERROR_ATTRIBUTE)
        root.removeAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE)
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
        val originalPreparedFlowAttribute = paragraph.getAttribute("data-tq-canonical-plain")
        val originalCanonicalSourceAttribute = paragraph.getAttribute(CANONICAL_SOURCE_ATTRIBUTE)
        val originalLangAttribute = paragraph.getAttribute("lang")
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
            originalPreparedFlowAttribute = originalPreparedFlowAttribute,
            originalCanonicalSourceAttribute = originalCanonicalSourceAttribute,
            originalLangAttribute = originalLangAttribute,
            originalStyleAttribute = originalStyleAttribute,
            originalPosition = originalPosition,
            originalPositionPriority = originalPositionPriority,
        )
        val layoutIssue = try {
            layoutParagraph(
                paragraph = item,
                options = state.activeOptions(),
                engine = state.activeEngine(),
                semanticExactEngine = state.activeSemanticExactEngine(),
                browserFallbackEngine = state.activeExactFallbackEngine(),
                onExactPreparedDomFallback = state::disableExactPreparedDom,
            )
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
        progressiveJobs.remove(root)?.frameId?.let { window.cancelAnimationFrame(it) }
    }

    private fun runProgressiveSlice(job: ProgressiveJob) {
        if (progressiveJobs[job.state.root] !== job) return
        job.frameId = null
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
                performanceNow() - sliceStartedAt < MAX_PROGRESSIVE_SLICE_MS
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
        if (job.kind == ProgressiveJobKind.Relayout) {
            dispatchTiqianRelayoutReady(
                root = job.state.root,
                enhancedCount = job.state.paragraphs.size,
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
                enhancedCount = job.state.paragraphs.size,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                capabilityRetry = job.kind == ProgressiveJobKind.CjkDashRetry,
            )
        }
        pendingCjkDashRetries.remove(job.state.root)?.let { options ->
            retryCjkDashCapability(job.state.root, options)
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
        if (job.kind == ProgressiveJobKind.Relayout) {
            dispatchTiqianRelayoutReady(
                root = job.state.root,
                enhancedCount = job.state.paragraphs.size,
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
                enhancedCount = job.state.paragraphs.size,
                issueCount = job.state.issues.size,
                durationMs = performanceNow() - job.startedAt,
                maxSliceMs = job.maxSliceDuration,
                capabilityRetry = job.kind == ProgressiveJobKind.CjkDashRetry,
            )
        }
    }

    internal fun retryCjkDashCapability(root: HTMLElement, options: EnhanceOptions) {
        if (progressiveJobs[root] != null) {
            pendingCjkDashRetries[root] = options
            return
        }
        val state = states[root] ?: return
        val retriable = state.issues.filter { it.name == CJK_DASH_CAPABILITY_ISSUE }
        if (retriable.isEmpty()) return
        dispatchTiqianCapabilityRetryStart(root)
        val replacement = createRootState(root, options)
        state.options = replacement.options
        state.engine = replacement.engine
        state.semanticExactEngine = replacement.semanticExactEngine
        state.browserFallbackEngine = replacement.browserFallbackEngine
        state.exactPreparedDomEnabled = replacement.exactPreparedDomEnabled
        state.exactPreparedDomFallback = replacement.exactPreparedDomFallback
        val candidates = retriable.map { it.element }.distinct()
        for (issue in retriable) {
            clearIssue(issue)
            state.issues.remove(issue)
        }
        startProgressiveJob(
            ProgressiveJob(
                state = state,
                kind = ProgressiveJobKind.CjkDashRetry,
                itemCount = candidates.size,
                processItem = { index -> processParagraph(candidates[index], state) },
                startedAt = performanceNow(),
            ),
        )
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
        val state = states[root] ?: return
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
            constraints = LayoutConstraints(maxWidth = width),
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
        var exactPreparedDom = exactFontLayout && paragraph.lowered.isCanonicalPlainParagraph()
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
            val pendingCjkDashProbe =
                shapingCapabilityIssue.capabilityIssue == CJK_DASH_CAPABILITY_ISSUE &&
                    options.cjkDashCapability?.status == "pending"
            return ParagraphLayoutPreparation.Unsupported(
                CapabilityIssue(
                    name = shapingCapabilityIssue.capabilityIssue!!,
                    detail = shapingCapabilityIssue.reason,
                    element = paragraph.source,
                    reportToConsole = !pendingCjkDashProbe,
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
            langAttribute = paragraph.source.getAttribute("lang"),
            styleAttribute = paragraph.source.getAttribute("style"),
            capabilityNameAttribute = paragraph.source.getAttribute("data-tiqian-capability-issue"),
            capabilityDetailAttribute = paragraph.source.getAttribute("data-tiqian-capability-detail"),
            lastMeasure = paragraph.lastMeasure,
            containingBlockApplied = paragraph.containingBlockApplied,
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
        val dashCapabilityObject = optionObject(options, "cjkDashCapability")
        val dashCapability = dashCapabilityObject?.let { capability ->
            WebCjkDashCapability(
                status = optionString(capability, "status") ?: "unavailable",
                sessionId = optionString(capability, "sessionId"),
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
        CjkDashRetry,
    }

    private class ProgressiveJob(
        val state: RootState,
        val kind: ProgressiveJobKind,
        val itemCount: Int,
        val processItem: (Int) -> Unit,
        val onItemsFinished: (() -> Unit)? = null,
        val onFailure: (() -> Unit)? = null,
        val stale: (() -> Boolean)? = null,
        val startedAt: Double,
        var nextIndex: Int = 0,
        var frameId: Int? = null,
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
        val originalLangAttribute: String?,
        val originalStyleAttribute: String?,
        val originalPosition: String,
        val originalPositionPriority: String,
        var lastMeasure: Float? = null,
        var containingBlockApplied: Boolean = false,
    )

    private data class LiveParagraphSnapshot(
        val paragraph: EnhancedParagraph,
        val content: DocumentFragment,
        val renderedAttribute: String?,
        val preparedFlowAttribute: String?,
        val canonicalSourceAttribute: String?,
        val langAttribute: String?,
        val styleAttribute: String?,
        val capabilityNameAttribute: String?,
        val capabilityDetailAttribute: String?,
        val lastMeasure: Float?,
        val containingBlockApplied: Boolean,
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
        return if (canonicalPrepared) {
            withCanonicalPreparedHostStyleProbe(paragraph) {
                lowerWithCurrentStyles(paragraph, options, canonicalPrepared = true)
            }
        } else {
            lowerWithCurrentStyles(paragraph, options, canonicalPrepared = false)
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

private fun LoweredParagraph.isCanonicalPlainParagraph(): Boolean =
    spans.isEmpty() &&
        decorations.isEmpty() &&
        inlineBoxes.isEmpty() &&
        inlineObjects.isEmpty() &&
        domInlineObjects.isEmpty() &&
        sourceSpans.isEmpty()

private fun isExactFontSessionCapabilityFailure(error: Throwable): Boolean {
    val detail = error.message.orEmpty()
    return EXACT_FONT_SESSION_CAPABILITY_FAILURES.any(detail::contains)
}

/**
 * SemanticExactRunFallback: rich paragraphs may intentionally introduce a
 * different font family (for example inline code). Preserve exact HarfBuzz
 * shaping for every covered run and delegate only the unsupported run to the
 * browser adapter, whose semantic clone keeps the corresponding host style.
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
@JsFun("(event) => event.detail && event.detail.options ? event.detail.options : null")
private external fun eventOptions(event: Event): JsAny?
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
@JsFun("(element) => { const style = getComputedStyle(element); const number = (value) => Number.parseFloat(value) || 0; return element.getBoundingClientRect().width - number(style.paddingLeft) - number(style.paddingRight) - number(style.borderLeftWidth) - number(style.borderRightWidth); }")
private external fun elementContentWidth(element: HTMLElement): Double
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
@JsFun("(element) => { if (!(element.getAttribute('style') || '').trim()) element.removeAttribute('style'); }")
private external fun removeEmptyStyleAttribute(element: HTMLElement)
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
@JsFun("(root, enhancedCount, issueCount, durationMs, maxSliceMs, capabilityRetry) => root.dispatchEvent(new CustomEvent('tiqian:ready', { detail: { enhancedCount, issueCount, durationMs, maxSliceMs, capabilityRetry } }))")
private external fun dispatchTiqianReady(
    root: HTMLElement,
    enhancedCount: Int,
    issueCount: Int,
    durationMs: Double,
    maxSliceMs: Double,
    capabilityRetry: Boolean,
)
@JsFun("(root, enhancedCount, issueCount, durationMs, maxSliceMs, failed, error, stale) => root.dispatchEvent(new CustomEvent('tiqian:relayout-ready', { detail: { enhancedCount, issueCount, durationMs, maxSliceMs, capabilityRetry: false, relayout: true, failed, error, stale } }))")
private external fun dispatchTiqianRelayoutReady(
    root: HTMLElement,
    enhancedCount: Int,
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
@JsFun("(root) => root.dispatchEvent(new CustomEvent('tiqian:capability-retry-start'))")
private external fun dispatchTiqianCapabilityRetryStart(root: HTMLElement)
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
private const val CANONICAL_SOURCE_ATTRIBUTE = "data-tq-canonical-source"
private const val RELAYOUT_ERROR_ATTRIBUTE = "data-tiqian-relayout-error"
private const val EXACT_PREPARED_FALLBACK_ATTRIBUTE = "data-tiqian-exact-layout-fallback"
private const val CJK_DASH_CAPABILITY_ISSUE = "NoConformingCjkDashGlyph"
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
