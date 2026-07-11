package org.tiqian.web

import kotlin.JsFun
import kotlin.js.ExperimentalWasmJsInterop
import kotlin.js.JsAny
import kotlinx.browser.document
import org.tiqian.core.BopomofoDecisionInfo
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineEndReason
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyDecisionInfo
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.positionedClusters
import org.tiqian.font.FontRole
import org.tiqian.shaping.web.WebFontFamilies
import org.w3c.dom.CanvasRenderingContext2D
import org.w3c.dom.Element
import org.w3c.dom.HTMLElement
import org.w3c.dom.HTMLCanvasElement
import org.w3c.dom.events.Event

/**
 * `PreBrokenLineDom` (ADR 0039): the engine owns the whole line layout; this
 * renderer only PAINTS its result into the DOM. Half-width punctuation, 中西
 * autospace, justify, 推入推出 and the line-end hyphen all come from the engine,
 * not the browser — the browser never re-wraps or word-breaks.
 *
 * `InlineFlowLineDom`: each line is a block; within it adjacent clusters with the
 * same geometry and source semantics merge into sparse inline runs laid out by
 * flow. They share one line box, so native selection stays continuous without
 * per-glyph DOM seams. The engine's inter-glyph gap is
 * `drawX[i+1] − drawX[i] − naturalWidth[i]`, where `naturalWidth` is the shaped
 * GLYPH advance — NOT `Cluster.advance`, which carries the layout-owned
 * glue/justify stretch and equals the `drawX` step, so using it would cancel
 * every gap and kill justification.
 *
 * `SelectableGapSpacing`: that gap must land in a box the SELECTION covers, or the
 * highlight gets a hole at every stretched space (as positive `margin` does). So
 * the trailing gap is `letter-spacing` for single-code-point glyphs (CJK /
 * punctuation / spaces — seamless, negative for half-width punctuation). For a
 * positive gap after a multi-letter Latin word, only its final grapheme gets that
 * letter-spacing: applying it to the whole word would splay `the`→`t h e`, while
 * `padding-right` is excluded from native Range selection and breaks both the
 * highlight and inherited underline. A negative gap after a multi-letter word uses
 * `margin-right`; overlap cannot create a selection hole. The first glyph's 段首缩进
 * is a leading `margin-left`.
 *
 * `CopyTransparentSpacingSpans`: copy is reconstructed by the page's `copy`
 * handler from `textContent` (which ignores block boundaries → no injected
 * newlines from soft wraps) with substituted spans (`——`→`⸺`) mapped back to
 * their `data-tq-src` source. Mandatory breaks add a hidden source-only newline
 * marker, preserving `<br>` without confusing it with wrapping (ADR 0037).
 *
 * `CssNativeDecorations`: ordinary rich-text underline / strike-through use native
 * CSS `text-decoration-skip-ink`, while CLREQ 行间线 (专名号 / 书名号甲式) paint
 * engine-owned SVG segments so each annotated item is one continuous line.
 * 着重号 paints engine-sized SVG circles at the engine's `DecorationDecisionInfo`
 * anchors (Han only, punctuation skipped); Latin clusters in the same emphasis span
 * render italic because that is what the engine measured. Ruby / Bopomofo
 * annotations ride real DOM spans after the base and copy parenthesised through
 * `data-tq-src`. Host semantic spans are shallow-cloned from the source DOM, so
 * links and inline elements retain application-owned attributes and CSS states.
 * `ContinuousSemanticFlow` clones each source semantic path once for the whole
 * paragraph and inserts engine-owned `<br>` elements at line boundaries. A link
 * therefore remains one native DOM link even when it crosses multiple lines;
 * geometry-only spans inside it still carry autospace / justification deltas.
 */
@OptIn(ExperimentalWasmJsInterop::class)
object DomParagraphRenderer {
    private val graphemeSegmenter: JsAny? = createGraphemeSegmenter()

    data class Options(
        val inlineCodeBackgroundArgb: Int = INLINE_CODE_BACKGROUND,
    )

    fun render(
        host: HTMLElement,
        result: LayoutResult,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan> = emptyList(),
        richTextSpans: List<RichTextSpan> = emptyList(),
        cssStyleSpans: List<CssRenderStyleSpan> = emptyList(),
        sourceSpans: List<DomSourceSpan> = emptyList(),
        inlineObjects: List<DomInlineObject> = emptyList(),
        options: Options = Options(),
    ) {
        while (host.firstChild != null) host.removeChild(host.firstChild!!)
        val fontSize = result.input.textStyle.fontSize
        val decorations = result.input.decorations
        val emphasisRanges = decorations
            .filter { it.kind == DecorationKind.Emphasis }
            .map { it.range }

        // Natural shaped width per cluster from the GLYPH advances (which exclude
        // layout-owned glue/justify — see the class doc). Cluster.advance carries
        // that glue and would cancel the margins.
        val naturalWidth = HashMap<TextRange, Float>()
        val renderFontFamily = HashMap<TextRange, String>()
        val glyphIdsByRange = HashMap<TextRange, MutableList<UInt>>()
        for (run in result.glyphRuns) {
            for (glyph in run.glyphs) {
                naturalWidth[glyph.clusterRange] = (naturalWidth[glyph.clusterRange] ?: 0f) + glyph.advance
                glyph.renderFontKey?.let { renderFontFamily[glyph.clusterRange] = it }
                glyphIdsByRange.getOrPut(glyph.clusterRange) { mutableListOf() }.add(glyph.id)
            }
        }
        val shapingDecisionByRange = result.debug.shapingDecisions.associateBy { it.range }
        val punctuationDecisionByRange = result.debug.punctuationDecisions.associateBy { it.range }
        val inlineStartByOffset = HashMap<Int, Float>()
        val inlineEndByOffset = HashMap<Int, Float>()
        for (box in result.input.inlineBoxes) {
            if (box.inlineStart != 0f) {
                inlineStartByOffset[box.range.start] =
                    (inlineStartByOffset[box.range.start] ?: 0f) + box.inlineStart
            }
            if (box.inlineEnd != 0f) {
                inlineEndByOffset[box.range.end] =
                    (inlineEndByOffset[box.range.end] ?: 0f) + box.inlineEnd
            }
        }
        val inlineObjectByRange = inlineObjects.associateBy { it.range }
        val inlineObjectAdvanceByRange = result.input.inlineObjects.associate { it.range to it.advance }
        val zeroWidthBreakRanges = result.debug.zeroWidthBreakDecisions.mapTo(mutableSetOf()) { it.range }
        fun styleAt(offset: Int): TextStyle =
            result.input.content.spans.lastOrNull { offset >= it.range.start && offset < it.range.end }?.style
                ?: result.input.textStyle

        // `InlineSelectableRuby` (ADR 0032): 注文 is a REAL span placed in DOM right
        // AFTER its base's last cluster — absolutely positioned into the 注文 band so it
        // doesn't push the base flow, but selectable and copy-ordered. A selection over a
        // ruby'd base therefore carries the 注文, which copies parenthesised after the base
        // (「北京（Běijīng）」) via `data-tq-src` (注文不进源, but surfaced on copy). Keyed
        // by base END offset so only the last base cluster gets it (北京 → one 注文).
        val rubyByBaseEnd = HashMap<Int, RubyDecisionInfo>()
        for (ruby in result.debug.rubyDecisions) {
            rubyByBaseEnd[ruby.baseRange.end] = ruby
        }
        // InlineSelectableBopomofo: 注音只生成一个行内 annotation span。
        // 这个 span 占据基文后的 actual layout advance，并在自身内部按 engine
        // placements 放置可见 glyph；同一个 span 也作为整体参与 selection/copy。
        val bopomofoByBaseEnd = HashMap<Int, MutableList<BopomofoDecisionInfo>>()
        for (z in result.debug.bopomofoDecisions) {
            bopomofoByBaseEnd.getOrPut(z.baseRange.end) { mutableListOf() }.add(z)
        }
        // HostDirectSemanticFlow: generated runs and the original semantic
        // hierarchy are direct children of the source paragraph. An extra
        // wrapper would break host selectors such as `p > a:hover`.
        val flow = host

        fun semanticSpansFor(range: TextRange): List<DomSourceSpan> =
            sourceSpans
                .filter { range.start >= it.range.start && range.end <= it.range.end }
                .sortedBy { it.depth }

        val cellsByLine = result.lines.map { line ->
            result.positionedClusters(line)
                .filter {
                    val cluster = result.clusters[it.clusterIndex]
                    cluster.displayText.isNotEmpty() || cluster.range in zeroWidthBreakRanges
                }
        }

        // ContinuousSemanticFlow: unlike the previous per-line block renderer,
        // this path remains open across engine-owned soft breaks. HTML can then
        // expose one real <a> (and one real custom inline) for one source node.
        val activeSemanticSpans = mutableListOf<DomSourceSpan>()
        val activeSemanticElements = mutableListOf<HTMLElement>()
        fun semanticContainerFor(semanticSpans: List<DomSourceSpan>): HTMLElement {
            val commonLimit = minOf(activeSemanticSpans.size, semanticSpans.size)
            var common = 0
            while (common < commonLimit && activeSemanticSpans[common] == semanticSpans[common]) {
                common += 1
            }
            while (activeSemanticSpans.size > common) {
                activeSemanticSpans.removeAt(activeSemanticSpans.lastIndex)
                activeSemanticElements.removeAt(activeSemanticElements.lastIndex)
            }
            var container = activeSemanticElements.lastOrNull() ?: flow
            for (index in common until semanticSpans.size) {
                val sourceSpan = semanticSpans[index]
                val clone = cloneSemanticElement(sourceSpan)
                container.appendChild(clone)
                activeSemanticSpans += sourceSpan
                activeSemanticElements += clone
                container = clone
            }
            return container
        }

        fun semanticSpansCrossing(offset: Int): List<DomSourceSpan> =
            sourceSpans
                .filter { offset > it.range.start && offset < it.range.end }
                .sortedBy { it.depth }

        fun appendRun(run: RenderRun) {
            if (run.semanticSpans.isEmpty()) {
                semanticContainerFor(emptyList()).appendChild(renderRunElement(host, run, result.input.textStyle))
                return
            }
            val container = semanticContainerFor(run.semanticSpans)
            val hostLetterSpacing = run.semanticSpans.last().inlineBoxStyle.letterSpacing
            container.appendChild(renderSemanticFragment(run, result.input.textStyle, hostLetterSpacing))
        }

        fun appendInlineObject(
            inlineObject: DomInlineObject,
            semanticSpans: List<DomSourceSpan>,
            trailingGap: Float,
        ) {
            val container = semanticContainerFor(semanticSpans)
            val clone = inlineObject.element.cloneNode(true) as Element
            clone.setAttribute(INLINE_OBJECT_ATTRIBUTE, "true")
            clone.setAttribute("data-tq-object-range", "${inlineObject.range.start}-${inlineObject.range.end}")
            if (kotlin.math.abs(trailingGap) >= SPACING_EPSILON) {
                setInlineObjectTrailingMargin(clone, inlineObject.marginRight + trailingGap)
            }
            container.appendChild(clone)
        }

        for ((lineIndex, line) in result.lines.withIndex()) {
            val h = line.bottom - line.top
            val cells = cellsByLine[lineIndex]
            val lineMarker = document.createElement("span") as HTMLElement
            lineMarker.className = "tq-line"
            lineMarker.setAttribute("data-tq-copy-ignore", "true")
            lineMarker.setAttribute("aria-hidden", "true")
            lineMarker.setAttribute("data-tq-line-index", "$lineIndex")
            lineMarker.setAttribute("data-tq-line-range", "${line.range.start}-${line.range.end}")
            lineMarker.setAttribute("data-tq-line-width", "${line.indent + line.visualWidth + line.hyphenAdvance}")
            lineMarker.setAttribute("data-tq-line-end", line.endReason.name)
            lineMarker.setAttribute("data-tq-line-empty", "${cells.isEmpty()}")
            resetEngineInline(lineMarker)
            lineMarker.style.apply {
                setProperty("display", "inline-block", "important")
                setProperty("width", "0px", "important")
                setProperty("height", "${h}px", "important")
                setProperty("line-height", "${h}px", "important")
                setProperty("vertical-align", "${-(line.bottom - line.baseline)}px", "important")
                setProperty("overflow", "visible", "important")
                setProperty("pointer-events", "none", "important")
            }
            cells.firstOrNull()?.let { first ->
                val firstCluster = result.clusters[first.clusterIndex]
                val flowStart = first.drawX - firstCluster.leadingLayoutAdvance
                if (flowStart != 0f) {
                    lineMarker.style.setProperty("margin-left", "${flowStart}px", "important")
                }
            }
            semanticContainerFor(activeSemanticSpans).appendChild(lineMarker)

            var pendingRun: RenderRun? = null
            fun flushRun() {
                pendingRun?.let(::appendRun)
                pendingRun = null
            }

            for (i in cells.indices) {
                val pc = cells[i]
                val cluster = result.clusters[pc.clusterIndex]
                val inlineObject = inlineObjectByRange[cluster.range]
                val glyphWidth = inlineObjectAdvanceByRange[cluster.range]
                    ?: naturalWidth[cluster.range]
                    ?: cluster.advance
                val trailingInlineEdge = inlineEndByOffset[cluster.range.end] ?: 0f
                val rawTrailingGap = if (i + 1 < cells.size) {
                    val nextLeadingInlineEdge = inlineStartByOffset[cells[i + 1].range.start] ?: 0f
                    cells[i + 1].drawX - pc.drawX - glyphWidth -
                        trailingInlineEdge - nextLeadingInlineEdge
                } else {
                    (line.indent + line.visualWidth) - pc.drawX - glyphWidth - trailingInlineEdge
                }
                val layoutTrailingGap = if (kotlin.math.abs(rawTrailingGap) < SPACING_EPSILON) 0f else rawTrailingGap
                val bopomofoAtEnd = bopomofoByBaseEnd[cluster.range.end]
                val bopomofoAdvanceWidth = if (bopomofoAtEnd == null) {
                    0f
                } else if (i + 1 < cells.size) {
                    layoutTrailingGap.coerceAtLeast(0f)
                } else {
                    (cluster.advance - glyphWidth - trailingInlineEdge).coerceAtLeast(0f)
                }
                val trailingGap = if (bopomofoAtEnd == null) {
                    layoutTrailingGap
                } else {
                    0f
                }
                val semanticSpans = semanticSpansFor(cluster.range)
                if (inlineObject != null) {
                    flushRun()
                    appendInlineObject(inlineObject, semanticSpans, trailingGap)
                    continue
                }
                val roleName = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                val clusterStyle = styleAt(cluster.range.start)
                val isLatin = roleName == FontRole.LatinText.name
                val display = cluster.displayText
                val deco = decoFor(cluster.range, colorSpans, richTextSpans, cssStyleSpans, options)
                val italic = clusterStyle.italic || isLatin &&
                    emphasisRanges.any { cluster.range.start >= it.start && cluster.range.start < it.end }
                val spacing = resolveDomRunSpacing(display, trailingGap)
                val shapingDecision = shapingDecisionByRange[cluster.range]
                val punctuationDecision = punctuationDecisionByRange[cluster.range]
                val run = RenderRun(
                    range = cluster.range,
                    text = display,
                    source = cluster.text,
                    spacing = spacing,
                    semanticSpans = semanticSpans,
                    textStyle = clusterStyle,
                    deco = deco,
                    italic = italic,
                    renderFontFamily = renderFontFamily[cluster.range],
                    shapingLanguage = shapingDecision?.language,
                    resolvedFace = shapingDecision?.resolvedFace,
                    dashStrategy = shapingDecision?.strategy,
                    expectedShapedAdvance = shapingDecision?.strategy?.let { glyphWidth },
                    glyphIds = shapingDecision?.strategy?.let {
                        glyphIdsByRange[cluster.range]?.joinToString(",")
                    },
                    shapingEvidence = shapingDecision?.strategy?.let { shapingDecision.reason },
                    punctuationInkFloor = punctuationDecision
                        ?.takeIf { it.inkContainmentApplied }
                        ?.inkContainmentBodyFloor,
                    punctuationBodyWidth = punctuationDecision
                        ?.takeIf { it.inkContainmentApplied }
                        ?.bodyWidth,
                )
                if (pendingRun?.canMerge(run) == true) {
                    pendingRun!!.merge(run)
                } else {
                    flushRun()
                    pendingRun = run
                }

                val rubyAtEnd = rubyByBaseEnd[cluster.range.end]
                if (rubyAtEnd != null || bopomofoAtEnd != null) flushRun()
                // InlineSelectableRuby: 注文 span DOM-follows the base's last cluster.
                rubyAtEnd?.let {
                    semanticContainerFor(semanticSpans).appendChild(rubyInlineSpan(it, line.top, fonts, colorSpans))
                }
                bopomofoAtEnd?.forEach {
                    semanticContainerFor(semanticSpans)
                        .appendChild(bopomofoInlineSpan(it, bopomofoAdvanceWidth, line.top, h, fonts, colorSpans))
                }
            }
            flushRun()
            // EngineOwnedHyphenation: the engine reserved the hyphen inside the measure;
            // place it at indent+visualWidth. The browser never hyphenates.
            if (line.hyphenAdvance > 0f) {
                val last = cells.lastOrNull()
                val flowEnd = if (last != null) {
                    val lastCluster = result.clusters[last.clusterIndex]
                    last.drawX + (inlineObjectAdvanceByRange[lastCluster.range]
                        ?: naturalWidth[lastCluster.range]
                        ?: 0f) +
                        (inlineEndByOffset[lastCluster.range.end] ?: 0f)
                } else {
                    0f
                }
                semanticContainerFor(activeSemanticSpans).appendChild(
                    renderRunElement(
                        host,
                        RenderRun(
                            range = TextRange(0, 0),
                            text = "-",
                            source = "-",
                            spacing = DomRunSpacing.None,
                            semanticSpans = emptyList(),
                            textStyle = result.input.textStyle,
                            deco = ClusterDeco(),
                            italic = false,
                            leadingMargin = (line.indent + line.visualWidth) - flowEnd,
                        ),
                        result.input.textStyle,
                    ),
                )
            }
            val boundaryContainer = semanticContainerFor(semanticSpansCrossing(line.range.end))
            if (line.endReason == LineEndReason.MandatoryBreak) {
                val hardBreakSource = document.createElement("span") as HTMLElement
                hardBreakSource.setAttribute("data-tq-src", "\n")
                hardBreakSource.setAttribute("data-tq-hard-break", "true")
                resetEngineInline(hardBreakSource)
                hardBreakSource.style.setProperty("display", "none", "important")
                boundaryContainer.appendChild(hardBreakSource)
            }
            if (lineIndex < result.lines.lastIndex) {
                val softBreak = document.createElement("br") as HTMLElement
                softBreak.setAttribute("data-tq-engine-break", line.endReason.name)
                softBreak.style.setProperty("all", "unset", "important")
                boundaryContainer.appendChild(softBreak)
            }
        }
        semanticContainerFor(emptyList())
        appendInterlinearLines(host, result, colorSpans)
        appendEmphasisDots(host, result, colorSpans, sourceSpans)
    }

    private data class RenderRun(
        var range: TextRange,
        var text: String,
        var source: String,
        val spacing: DomRunSpacing,
        val semanticSpans: List<DomSourceSpan>,
        val textStyle: TextStyle,
        val deco: ClusterDeco,
        val italic: Boolean,
        val renderFontFamily: String? = null,
        val shapingLanguage: String? = null,
        val resolvedFace: String? = null,
        val dashStrategy: String? = null,
        val expectedShapedAdvance: Float? = null,
        val glyphIds: String? = null,
        val shapingEvidence: String? = null,
        val punctuationInkFloor: Float? = null,
        val punctuationBodyWidth: Float? = null,
        val leadingMargin: Float = 0f,
    ) {
        fun canMerge(other: RenderRun): Boolean =
            dashStrategy == null &&
                other.dashStrategy == null &&
            leadingMargin == 0f &&
                other.leadingMargin == 0f &&
                range.end == other.range.start &&
                spacing.approximatelyEquals(other.spacing) &&
                semanticSpans == other.semanticSpans &&
                textStyle == other.textStyle &&
                deco == other.deco &&
                italic == other.italic &&
                renderFontFamily == other.renderFontFamily &&
                shapingLanguage == other.shapingLanguage &&
                resolvedFace == other.resolvedFace &&
                punctuationInkFloor == other.punctuationInkFloor &&
                punctuationBodyWidth == other.punctuationBodyWidth

        fun merge(other: RenderRun) {
            range = TextRange(range.start, other.range.end)
            text += other.text
            source += other.source
        }
    }

    private fun DomRunSpacing.approximatelyEquals(other: DomRunSpacing): Boolean = when {
        this === DomRunSpacing.None && other === DomRunSpacing.None -> true
        this is DomRunSpacing.Letter && other is DomRunSpacing.Letter -> kotlin.math.abs(px - other.px) < 0.01f
        // These properties encode one trailing gap, not per-character tracking.
        // Merging two such runs would silently drop the first run's gap.
        this is DomRunSpacing.TrailingLetter && other is DomRunSpacing.TrailingLetter -> false
        this is DomRunSpacing.Overlap && other is DomRunSpacing.Overlap -> false
        else -> false
    }

    private fun renderRunElement(
        host: HTMLElement,
        run: RenderRun,
        paragraphStyle: TextStyle,
    ): HTMLElement {
        val fallbackLink = run.deco.linkTarget?.takeIf {
            run.semanticSpans.none { span -> span.element.tagName.equals("A", ignoreCase = true) }
        }
        val first = when {
            run.semanticSpans.isNotEmpty() -> cloneSemanticElement(run.semanticSpans.first())
            fallbackLink != null -> (document.createElement("a") as HTMLElement).apply {
                setAttribute("href", fallbackLink)
                run.deco.linkId?.let { installLinkFragmentState(host, this, it) }
            }
            else -> document.createElement("span") as HTMLElement
        }
        var leaf = first
        for (span in run.semanticSpans.drop(1)) {
            val child = cloneSemanticElement(span)
            leaf.appendChild(child)
            leaf = child
        }
        populateRunLeaf(
            leaf = leaf,
            run = run,
            paragraphStyle = paragraphStyle,
            hostBox = run.semanticSpans.lastOrNull()?.inlineBoxStyle ?: DomInlineBoxStyle(),
            insideSemantic = run.semanticSpans.isNotEmpty() &&
                run.semanticSpans.none { it.cjkStrongBaseWeight != null },
        )
        return first
    }

    private fun cloneSemanticElement(sourceSpan: DomSourceSpan): HTMLElement =
        (sourceSpan.element.cloneNode(false) as HTMLElement).also { clone ->
            clone.setAttribute(SOURCE_SEMANTIC_ATTRIBUTE, "true")
            applyEngineFlowConstraints(clone)
            sourceSpan.cjkStrongBaseWeight?.let { weight ->
                clone.setAttribute(CJK_STRONG_ATTRIBUTE, "true")
                clone.style.setProperty("font-weight", "$weight", "important")
            }
        }

    /**
     * SourceLinkFragmentStateBridge: one source link may need one DOM anchor per
     * engine-owned line. The browser cannot share `:hover` or `:focus` between
     * those nodes, so mirror only named state attributes across the group. The
     * host remains the sole owner of colors, decorations and transitions.
     *
     * State lives on the current clones instead of in a renderer registry. A
     * relayout or destroy therefore removes it even when node removal cannot
     * produce a matching leave/blur event.
     */
    private fun installLinkFragmentState(host: HTMLElement, link: HTMLElement, groupId: String) {
        link.setAttribute(LINK_GROUP_ATTRIBUTE, groupId)
        link.addEventListener("mouseenter", { _: Event ->
            setLinkFragmentState(host, groupId, LINK_HOVER_ATTRIBUTE, active = true)
        })
        link.addEventListener("mouseleave", { _: Event ->
            setLinkFragmentState(host, groupId, LINK_HOVER_ATTRIBUTE, active = false)
        })
        link.addEventListener("focus", { _: Event ->
            setLinkFragmentState(host, groupId, LINK_FOCUS_ATTRIBUTE, active = true)
        })
        link.addEventListener("blur", { _: Event ->
            setLinkFragmentState(host, groupId, LINK_FOCUS_ATTRIBUTE, active = false)
        })
    }

    private fun setLinkFragmentState(
        host: HTMLElement,
        groupId: String,
        stateAttribute: String,
        active: Boolean,
    ) {
        val fragments = host.querySelectorAll("[$LINK_GROUP_ATTRIBUTE]")
        for (index in 0 until fragments.length) {
            val fragment = fragments.item(index) as? HTMLElement ?: continue
            if (fragment.getAttribute(LINK_GROUP_ATTRIBUTE) != groupId) continue
            if (active) {
                fragment.setAttribute(stateAttribute, "true")
            } else {
                fragment.removeAttribute(stateAttribute)
            }
        }
    }

    private fun renderSemanticFragment(
        run: RenderRun,
        paragraphStyle: TextStyle,
        hostLetterSpacing: Float,
    ): HTMLElement = (document.createElement("span") as HTMLElement).apply {
        populateRunLeaf(
            leaf = this,
            run = run,
            paragraphStyle = paragraphStyle,
            // Padding/margin live on the single cloned semantic wrapper. Only
            // inherited letter-spacing must be added when a geometry fragment
            // overrides that property with an engine delta.
            hostBox = DomInlineBoxStyle(letterSpacing = hostLetterSpacing),
            insideSemantic = run.semanticSpans.none { it.cjkStrongBaseWeight != null },
        )
    }

    private fun populateRunLeaf(
        leaf: HTMLElement,
        run: RenderRun,
        paragraphStyle: TextStyle,
        hostBox: DomInlineBoxStyle,
        insideSemantic: Boolean,
    ) {
        if (!leaf.hasAttribute(SOURCE_SEMANTIC_ATTRIBUTE)) resetEngineInline(leaf)
        val trailingLetterApplied = when (val spacing = run.spacing) {
            is DomRunSpacing.TrailingLetter -> populateTrailingLetterSpacing(
                leaf = leaf,
                text = run.text,
                letterSpacing = hostBox.letterSpacing + spacing.px,
            )
            else -> {
                leaf.textContent = run.text
                false
            }
        }
        if (run.source != run.text) leaf.setAttribute("data-tq-src", run.source)
        run.shapingLanguage?.let { leaf.setAttribute("lang", it) }
        run.dashStrategy?.let { strategy ->
            leaf.setAttribute(DASH_STRATEGY_ATTRIBUTE, strategy)
            run.expectedShapedAdvance?.let { advance ->
                leaf.setAttribute(DASH_ADVANCE_ATTRIBUTE, "$advance")
            }
            run.renderFontFamily?.let { family -> leaf.setAttribute(DASH_FONT_FAMILY_ATTRIBUTE, family) }
            run.resolvedFace?.let { face -> leaf.setAttribute(DASH_FACE_ATTRIBUTE, face) }
            run.glyphIds?.let { glyphIds -> leaf.setAttribute(DASH_GLYPH_IDS_ATTRIBUTE, glyphIds) }
            run.shapingEvidence?.let { evidence -> leaf.setAttribute(DASH_EVIDENCE_ATTRIBUTE, evidence) }
        }
        run.punctuationInkFloor?.let { floor ->
            leaf.setAttribute(PUNCTUATION_INK_FLOOR_ATTRIBUTE, "$floor")
            run.punctuationBodyWidth?.let { body ->
                leaf.setAttribute(PUNCTUATION_BODY_WIDTH_ATTRIBUTE, "$body")
            }
        }

        leaf.style.apply {
            run.renderFontFamily?.let { setProperty("font-family", it, "important") }
            if (run.leadingMargin != 0f) setProperty("margin-left", "${run.leadingMargin}px", "important")
            when (val spacing = run.spacing) {
                DomRunSpacing.None -> Unit
                is DomRunSpacing.Letter -> setProperty(
                    "letter-spacing",
                    "${hostBox.letterSpacing + spacing.px}px",
                    "important",
                )
                is DomRunSpacing.TrailingLetter -> if (!trailingLetterApplied) {
                    setProperty("letter-spacing", "${hostBox.letterSpacing + spacing.px}px", "important")
                }
                is DomRunSpacing.Overlap -> setProperty(
                    "margin-right",
                    "${hostBox.marginRight + spacing.px}px",
                    "important",
                )
            }
            if (!insideSemantic && run.textStyle != paragraphStyle) {
                setProperty("font-size", "${run.textStyle.fontSize}px", "important")
                setProperty("font-weight", "${run.textStyle.fontWeight}", "important")
                setProperty("font-style", if (run.textStyle.italic) "italic" else "normal", "important")
            } else if (run.italic && !run.textStyle.italic) {
                setProperty("font-style", "italic", "important")
            }
            run.deco.color?.let { setProperty("color", it, "important") }
            run.deco.background?.let { setProperty("background-color", it, "important") }
            run.deco.textDecorationLine?.let {
                setProperty("text-decoration-line", it, "important")
                setProperty("text-decoration-style", run.deco.textDecorationStyle ?: "solid", "important")
                setProperty("text-decoration-skip-ink", "auto", "important")
                if ("underline" in it) {
                    setProperty(
                        "text-underline-offset",
                        run.deco.textUnderlineOffset ?: "${UNDERLINE_OFFSET_EM}em",
                        "important",
                    )
                }
                setProperty(
                    "text-decoration-thickness",
                    run.deco.textDecorationThickness ?: "${LINE_THICKNESS_EM}em",
                    "important",
                )
                run.deco.decorationColor?.let { color ->
                    setProperty("text-decoration-color", color, "important")
                }
            }
        }
    }

    /** Cross-check that selectable DOM paints the HarfBuzz dash with the pinned face metrics. */
    fun verifyCjkDashRuns(host: HTMLElement): String? {
        val runs = host.querySelectorAll("[$DASH_STRATEGY_ATTRIBUTE]")
        for (index in 0 until runs.length) {
            val run = runs.item(index) as? HTMLElement ?: continue
            val expected = run.getAttribute(DASH_ADVANCE_ATTRIBUTE)?.toFloatOrNull() ?: continue
            val actual = domTextRangeWidth(run).toFloat()
            val family = run.getAttribute(DASH_FONT_FAMILY_ATTRIBUTE) ?: ""
            val actualFamily = computedFontFamily(run)
            if (!sameLeadingCssFamily(actualFamily, family)) {
                return "PinnedDashFaceMismatch: expected=$family; actual=$actualFamily"
            }
            val tolerance = maxOf(DASH_DOM_ABSOLUTE_TOLERANCE_PX, expected * DASH_DOM_RELATIVE_TOLERANCE)
            if (!actual.isFinite() || kotlin.math.abs(actual - expected) > tolerance) {
                return buildString {
                    append("DashDomAdvanceMismatch: strategy=")
                    append(run.getAttribute(DASH_STRATEGY_ATTRIBUTE))
                    append("; expected=")
                    append(expected)
                    append("; actual=")
                    append(actual)
                    append("; tolerance=")
                    append(tolerance)
                    append("; face=")
                    append(run.getAttribute(DASH_FACE_ATTRIBUTE))
                }
            }
        }
        return null
    }

    private fun populateTrailingLetterSpacing(
        leaf: HTMLElement,
        text: String,
        letterSpacing: Float,
    ): Boolean {
        if (text.isEmpty()) {
            leaf.textContent = text
            return false
        }
        val tailStart = trailingGraphemeStart(graphemeSegmenter, text).coerceIn(0, text.lastIndex)
        leaf.textContent = ""
        if (tailStart > 0) {
            leaf.appendChild(document.createTextNode(text.substring(0, tailStart)))
        }
        val tail = document.createElement("span") as HTMLElement
        tail.textContent = text.substring(tailStart)
        resetEngineInline(tail)
        tail.style.setProperty("letter-spacing", "${letterSpacing}px", "important")
        leaf.appendChild(tail)
        return true
    }

    /**
     * 注音 (ADR 0033): the engine places each ㄅㄆㄇ symbol + 调号 in its own box on the
     * base's right. The annotation itself is one inline selectable/copyable span;
     * its children only paint the engine placements inside that span.
     */
    private fun bopomofoInlineSpan(
        z: BopomofoDecisionInfo,
        width: Float,
        lineTop: Float,
        lineHeight: Float,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan>,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.setAttribute("data-tq-src", "（${z.text}）")
        span.setAttribute("lang", BOPOMOFO_LANG)
        resetEngineInline(span)
        span.style.apply {
            setProperty("display", "inline-block", "important")
            setProperty("position", "relative", "important")
            setProperty("vertical-align", "top", "important")
            setProperty("width", "${width}px", "important")
            setProperty("height", "${lineHeight}px", "important")
            setProperty("box-sizing", "border-box", "important")
            setProperty("line-height", "${lineHeight}px", "important")
            setProperty("white-space", "pre", "important")
            setProperty("overflow", "visible", "important")
            setProperty("user-select", "all", "important")
            setProperty("-webkit-user-select", "all", "important")
        }

        // 注音-capable face: not just "a CJK font" — the ㄅㄆㄇ symbols are everywhere,
        // but the 注音-shaped 调号 (full-width U+02CA…) only live in TC/system fonts;
        // SC / Noto / Source Han fall back to a small Western accent for the tone.
        val font = BopomofoFontSpec(fonts.forBopomofo(z.fontFamilies), z.fontWeight)
        val color = colorAt(z.baseRange.start, colorSpans)
        val zoneLeft = bopomofoZoneLeft(z)
        for (p in z.placements) {
            val placement = bopomofoCssPlacement(p.text, p.role, font, p.left, p.top, p.width, p.height)
            val glyph = document.createElement("span") as HTMLElement
            glyph.textContent = p.text
            glyph.setAttribute("lang", BOPOMOFO_LANG)
            resetEngineInline(glyph)
            glyph.style.apply {
                setProperty("position", "absolute", "important")
                setProperty("left", "${placement.left - zoneLeft}px", "important")
                setProperty("top", "${placement.top - lineTop}px", "important")
                setProperty("font-family", font.family, "important")
                setProperty("font-style", "normal", "important")
                setProperty("font-weight", "${font.weight}", "important")
                setProperty("font-size", "${placement.fontSize}px", "important")
                setProperty("color", color, "important")
                setProperty("line-height", "${placement.lineHeight}px", "important")
                setProperty("white-space", "pre", "important")
                setProperty("display", "inline-block", "important")
                setProperty("pointer-events", "none", "important")
                setProperty("overflow", "visible", "important")
                setProperty("writing-mode", "vertical-rl", "important")
                setProperty("text-orientation", "upright", "important")
                setProperty("font-feature-settings", "'vert' 1, 'vrt2' 1", "important")
            }
            span.appendChild(glyph)
        }
        return span
    }

    /** Web mirror of Compose's 注音 placement formulas for Symbol / Tone / Neutral. */
    private fun bopomofoCssPlacement(
        text: String,
        role: BopomofoGlyphRole,
        font: BopomofoFontSpec,
        boxLeft: Float,
        boxTop: Float,
        boxWidth: Float,
        boxHeight: Float,
    ): BopomofoCssPlacement = when (role) {
        BopomofoGlyphRole.Symbol -> BopomofoCssPlacement(
            left = boxLeft,
            top = boxTop,
            fontSize = boxHeight,
            lineHeight = boxWidth,
        )
        BopomofoGlyphRole.Neutral -> {
            val fontSize = boxWidth
            BopomofoCssPlacement(
                left = boxLeft,
                top = boxTop + (boxHeight - fontSize) / 2f,
                fontSize = fontSize,
                lineHeight = boxWidth,
            )
        }
        BopomofoGlyphRole.Tone -> {
            val inkWidthEm = browserVerticalBopomofoToneInkWidthEm(text, font.weight)
            val fontSize = boxWidth * BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE / inkWidthEm.coerceAtLeast(0.1f)
            BopomofoCssPlacement(
                left = boxLeft,
                top = boxTop + (boxHeight - fontSize) / 2f,
                fontSize = fontSize,
                lineHeight = boxWidth,
            )
        }
    }

    private data class BopomofoCssPlacement(
        val left: Float,
        val top: Float,
        val fontSize: Float,
        val lineHeight: Float,
    )

    private data class BopomofoFontSpec(
        val family: String,
        val weight: Int,
    )

    private fun bopomofoZoneLeft(z: BopomofoDecisionInfo): Float {
        val symbol = z.placements.firstOrNull { it.role == BopomofoGlyphRole.Symbol }
        return symbol?.let { it.left - it.width / 9f }
            ?: z.placements.minOfOrNull { it.left }
            ?: 0f
    }

    /**
     * DomLineBaselineAlignment: body text stays native inline DOM text for
     * selection/copy, but the inline baseline is shifted onto Tiqian's line
     * baseline so engine-owned ruby / emphasis / interlinear geometry aligns with
     * the glyphs actually drawn by the browser.
     */
    private fun cssBaselineOffset(lineHeight: Float, fontSize: Float, fontFamily: String): Float? {
        metricsCtx.font = "normal 400 ${fontSize}px $fontFamily"
        val m = metricsCtx.measureText(BASELINE_METRIC_PROBE)
        val ascent = m.fontBoundingBoxAscent.toFloatOrNull()
            ?: m.actualBoundingBoxAscent.toFloatOrNull()
            ?: return null
        val descent = m.fontBoundingBoxDescent.toFloatOrNull()
            ?: m.actualBoundingBoxDescent.toFloatOrNull()
            ?: return null
        val leading = (lineHeight - (ascent + descent)).coerceAtLeast(0f)
        return leading / 2f + ascent
    }

    /**
     * `InlineSelectableRuby` (ADR 0032): the 注文 is a real, selectable span placed in
     * DOM right after its base's last cluster (so a copy of a ruby'd base carries it),
     * but absolutely positioned into the engine's 注文 band (centreX / baselineY, in the
     * line's own coordinate space) so it does NOT push the base flow. It shows the plain
     * 拼音 but COPIES parenthesised (`data-tq-src` = 「（拼音）」).
     */
    @OptIn(ExperimentalWasmJsInterop::class)
    private fun rubyInlineSpan(
        ruby: RubyDecisionInfo,
        lineTop: Float,
        fonts: WebFontFamilies,
        colorSpans: List<ColorSpan>,
    ): HTMLElement {
        val span = document.createElement("span") as HTMLElement
        span.textContent = ruby.text
        span.setAttribute("data-tq-src", "（${ruby.text}）")
        resetEngineInline(span)
        val family = fonts.forRuby(ruby.fontFamilies)
        metricsCtx.font = "normal ${ruby.fontWeight} ${ruby.fontSize}px $family"
        val ascent = metricsCtx.measureText(ruby.text).fontBoundingBoxAscent.toFloatOrNull()
            ?: (ruby.fontSize * RUBY_ASCENT_RATIO)
        span.style.apply {
            setProperty("position", "absolute", "important")
            setProperty("left", "${ruby.centerX}px", "important")
            setProperty("top", "${ruby.baselineY - lineTop - ascent}px", "important")
            setProperty("transform", "translateX(-50%)", "important")
            setProperty("font-family", family, "important")
            setProperty("font-size", "${ruby.fontSize}px", "important")
            setProperty("font-weight", "${ruby.fontWeight}", "important")
            setProperty("line-height", "1", "important")
            setProperty("white-space", "pre", "important")
            setProperty("color", colorAt(ruby.baseRange.start, colorSpans), "important")
        }
        return span
    }

    /**
     * EngineOwnedInterlinearLines (ADR 0024): 专名号 / 书名号甲式 use
     * DecorationSegmentInfo directly. CSS wavy underline restarts its wave per
     * inline span, so it cannot represent a continuous 书名号 over multiple CJK
     * clusters.
     */
    private fun appendInterlinearLines(
        host: HTMLElement,
        result: LayoutResult,
        colorSpans: List<ColorSpan>,
    ) {
        val segments = result.debug.decorationSegments.filter {
            it.kind == DecorationKind.ProperNoun.name || it.kind == DecorationKind.BookTitle.name
        }
        if (segments.isEmpty()) return

        val svg = document.createElementNS(SVG_NS, "svg")
        svg.setAttribute("aria-hidden", "true")
        svg.setAttribute("data-tq-copy-ignore", "true")
        svg.setAttribute(GEOMETRY_SPAN_ATTRIBUTE, "true")
        svg.setAttribute(
            "style",
            "all:unset!important;display:block!important;position:absolute!important;" +
                "left:0!important;top:0!important;width:${result.size.width}px!important;" +
                "height:${result.size.height}px!important;overflow:visible!important;" +
                "pointer-events:none!important;user-select:none!important;-webkit-user-select:none!important",
        )

        val fontSize = result.input.textStyle.fontSize
        val strokeWidth = fontSize * LINE_THICKNESS_EM
        for (seg in segments) {
            val stroke = colorAt(seg.sourceRange.start, colorSpans)
            when (seg.kind) {
                DecorationKind.ProperNoun.name -> {
                    val line = document.createElementNS(SVG_NS, "line")
                    line.setAttribute("x1", "${seg.left}")
                    line.setAttribute("y1", "${seg.top}")
                    line.setAttribute("x2", "${seg.right}")
                    line.setAttribute("y2", "${seg.top}")
                    line.setAttribute("stroke", stroke)
                    line.setAttribute("stroke-width", "$strokeWidth")
                    line.setAttribute("stroke-linecap", "butt")
                    line.setAttribute(
                        "style",
                        "stroke:$stroke!important;stroke-width:${strokeWidth}px!important;stroke-linecap:butt!important",
                    )
                    svg.appendChild(line)
                }
                DecorationKind.BookTitle.name -> {
                    val path = document.createElementNS(SVG_NS, "path")
                    path.setAttribute("d", wavyLinePath(seg.left, seg.right, seg.top, fontSize))
                    path.setAttribute("fill", "none")
                    path.setAttribute("stroke", stroke)
                    path.setAttribute("stroke-width", "$strokeWidth")
                    path.setAttribute("stroke-linecap", "butt")
                    path.setAttribute("stroke-linejoin", "round")
                    path.setAttribute(
                        "style",
                        "fill:none!important;stroke:$stroke!important;stroke-width:${strokeWidth}px!important;" +
                            "stroke-linecap:butt!important;stroke-linejoin:round!important",
                    )
                    svg.appendChild(path)
                }
            }
        }

        host.appendChild(svg)
    }

    /**
     * EmphasisDotAnchorAlignment (ADR 0018 amendment): render the engine-sized
     * dot as a real SVG circle centered on the engine anchor. This is intentionally
     * not CSS `text-emphasis`: native emphasis owns its own position and cannot
     * consume Tiqian's decoration geometry.
     */
    private fun appendEmphasisDots(
        host: HTMLElement,
        result: LayoutResult,
        colorSpans: List<ColorSpan>,
        sourceSpans: List<DomSourceSpan>,
    ) {
        val dots = result.debug.decorationDecisions.filter {
            it.applied && it.kind == DecorationKind.Emphasis.name && it.dotDiameter > 0f
        }
        if (dots.isEmpty()) return

        val svg = document.createElementNS(SVG_NS, "svg")
        svg.setAttribute("aria-hidden", "true")
        svg.setAttribute("data-tq-copy-ignore", "true")
        svg.setAttribute(GEOMETRY_SPAN_ATTRIBUTE, "true")
        svg.setAttribute(
            "style",
            "all:unset!important;display:block!important;position:absolute!important;" +
                "left:0!important;top:0!important;width:${result.size.width}px!important;" +
                "height:${result.size.height}px!important;overflow:visible!important;" +
                "pointer-events:none!important;user-select:none!important;-webkit-user-select:none!important",
        )

        for (dot in dots) {
            val color = colorSpans.lastOrNull {
                dot.clusterRange.start >= it.start && dot.clusterRange.start < it.end
            }?.let { argbToCss(it.argb) }
                ?: sourceSpans
                    .filter {
                        dot.clusterRange.start >= it.range.start &&
                            dot.clusterRange.start < it.range.end &&
                            it.computedColor != null
                    }
                    .maxByOrNull { it.depth }
                    ?.computedColor
                ?: "currentColor"

            val circle = document.createElementNS(SVG_NS, "circle")
            circle.setAttribute("cx", "${dot.anchorX}")
            circle.setAttribute("cy", "${dot.anchorY}")
            circle.setAttribute("r", "${dot.dotDiameter * EMPHASIS_DOT_SCALE / 2f}")
            circle.setAttribute("fill", color)
            circle.setAttribute("style", "fill:$color!important")
            svg.appendChild(circle)
        }

        host.appendChild(svg)
    }

    /** Per-cluster CSS resolved from the engine's render-only spans/decorations. */
    private data class ClusterDeco(
        val color: String? = null,
        val background: String? = null,
        val textDecorationLine: String? = null,
        val decorationColor: String? = null,
        val textDecorationStyle: String? = null,
        val textDecorationThickness: String? = null,
        val textUnderlineOffset: String? = null,
        val linkTarget: String? = null,
        val linkId: String? = null,
    )

    private fun decoFor(
        range: TextRange,
        colorSpans: List<ColorSpan>,
        richTextSpans: List<RichTextSpan>,
        cssStyleSpans: List<CssRenderStyleSpan>,
        options: Options,
    ): ClusterDeco {
        val off = range.start
        var color = colorSpans.lastOrNull { off >= it.start && off < it.end }?.let { argbToCss(it.argb) }

        val lines = LinkedHashSet<String>()
        var decorationColor: String? = null
        var textDecorationStyle: String? = null
        var textDecorationThickness: String? = null
        var textUnderlineOffset: String? = null
        var background: String? = null
        var linkTarget: String? = null
        var linkId: String? = null
        for (s in cssStyleSpans) {
            if (off < s.range.start || off >= s.range.end) continue
            s.style.color?.let { color = it }
            s.style.backgroundColor?.let { background = it }
            s.style.textDecorationLine?.split(' ')?.filterTo(lines) { it.isNotBlank() && it != "none" }
            s.style.textDecorationColor?.let { decorationColor = it }
            s.style.textDecorationStyle?.let { textDecorationStyle = it }
            s.style.textDecorationThickness?.let { textDecorationThickness = it }
            s.style.textUnderlineOffset?.let { textUnderlineOffset = it }
        }
        for ((index, s) in richTextSpans.withIndex()) {
            if (off < s.range.start || off >= s.range.end) continue
            when (val role = s.role) {
                RichTextRole.Underline -> { lines += "underline"; s.paint.argb?.let { decorationColor = argbToCss(it) } }
                RichTextRole.LineThrough -> lines += "line-through"
                RichTextRole.Background -> s.paint.argb?.let { background = argbToCss(it) }
                RichTextRole.InlineCode -> if (background == null) {
                    background = argbToCss(s.paint.argb ?: options.inlineCodeBackgroundArgb)
                }
                is RichTextRole.Link -> {
                    linkTarget = role.target
                    linkId = "link-${s.range.start}-${s.range.end}-$index"
                }
            }
        }
        val textDecorationLine = if (lines.isEmpty()) null else lines.joinToString(" ")
        return ClusterDeco(
            color = color,
            background = background,
            textDecorationLine = textDecorationLine,
            decorationColor = decorationColor,
            textDecorationStyle = textDecorationStyle,
            textDecorationThickness = textDecorationThickness,
            textUnderlineOffset = textUnderlineOffset,
            linkTarget = linkTarget,
            linkId = linkId,
        )
    }

    private fun wavyLinePath(left: Float, right: Float, y: Float, fontSize: Float): String {
        val halfWave = (fontSize * WAVY_HALF_WAVE_EM).coerceAtLeast(1f)
        val amplitude = fontSize * WAVY_AMPLITUDE_EM
        val path = StringBuilder("M $left $y")
        var x = left
        var up = true
        while (x < right - WAVY_ENDPOINT_EPSILON_PX) {
            val rawNextX = x + halfWave
            val nextX = if (rawNextX >= right - WAVY_ENDPOINT_EPSILON_PX) right else rawNextX
            val controlY = if (up) y - amplitude * 2f else y + amplitude * 2f
            path.append(" Q ${(x + nextX) / 2f} $controlY $nextX $y")
            x = nextX
            up = !up
        }
        return path.toString()
    }

    private fun colorAt(offset: Int, colorSpans: List<ColorSpan>): String =
        colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.let { argbToCss(it.argb) } ?: "currentColor"

    private val metricsCtx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    private fun Double.toFloatOrNull(): Float? =
        if (isFinite() && this > 0.0) toFloat() else null

    private fun resetEngineInline(element: HTMLElement) {
        element.setAttribute(GEOMETRY_SPAN_ATTRIBUTE, "true")
        element.style.setProperty("all", "unset", "important")
        element.style.setProperty("display", "inline", "important")
    }

    private fun applyEngineFlowConstraints(element: HTMLElement) {
        for ((property, value) in ENGINE_FLOW_STYLE_OVERRIDES) {
            element.style.setProperty(property, value, "important")
        }
    }

    /** ARGB Int → CSS `rgba(...)`. */
    private fun argbToCss(argb: Int): String {
        val a = ((argb ushr 24) and 0xFF) / 255.0
        val r = (argb ushr 16) and 0xFF
        val g = (argb ushr 8) and 0xFF
        val b = argb and 0xFF
        return "rgba($r, $g, $b, $a)"
    }

    /**
     * BrowserVerticalBopomofoToneGlyphMetrics:
     * CSS vertical text paints the correct TC `vert` glyph, but the web platform
     * does not expose that glyph's ink bounds to DOM/canvas. These ratios mirror
     * Skia's `Font.getBounds(vertGlyphIds(...))` path with HarfBuzz extents for
     * PingFang TC Regular/Semibold (UPEM 1000), the system TC face preferred by
     * [WebFontFamilies]. Weight interpolation only selects between those two
     * measured profiles; it is a renderer fallback, not a layout decision.
     */
    private fun browserVerticalBopomofoToneInkWidthEm(text: String, fontWeight: Int): Float {
        val regular = when (text) {
            "ˇ" -> BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR
            else -> BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR
        }
        val semibold = when (text) {
            "ˇ" -> BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD
            else -> BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD
        }
        val t = ((fontWeight - 400) / 300f).coerceIn(0f, 1f)
        return regular + (semibold - regular) * t
    }

    private const val INLINE_CODE_BACKGROUND = 0x1A000000
    private const val SPACING_EPSILON = 0.01f
    private const val LINK_GROUP_ATTRIBUTE = "data-tq-link-group"
    private const val LINK_HOVER_ATTRIBUTE = "data-tq-link-hover"
    private const val LINK_FOCUS_ATTRIBUTE = "data-tq-link-focus"
    private const val INLINE_OBJECT_ATTRIBUTE = "data-tq-inline-object"
    private const val SOURCE_SEMANTIC_ATTRIBUTE = "data-tq-source-semantic"
    private const val GEOMETRY_SPAN_ATTRIBUTE = "data-tq-geometry"
    private const val CJK_STRONG_ATTRIBUTE = "data-tq-cjk-emphasis"
    private const val DASH_STRATEGY_ATTRIBUTE = "data-tq-dash-strategy"
    private const val DASH_ADVANCE_ATTRIBUTE = "data-tq-dash-advance"
    private const val DASH_FONT_FAMILY_ATTRIBUTE = "data-tq-dash-font-family"
    private const val DASH_FACE_ATTRIBUTE = "data-tq-dash-face"
    private const val DASH_GLYPH_IDS_ATTRIBUTE = "data-tq-dash-glyph-ids"
    private const val DASH_EVIDENCE_ATTRIBUTE = "data-tq-dash-evidence"
    private const val PUNCTUATION_INK_FLOOR_ATTRIBUTE = "data-tq-punctuation-ink-floor"
    private const val PUNCTUATION_BODY_WIDTH_ATTRIBUTE = "data-tq-punctuation-body-width"
    private const val SVG_NS = "http://www.w3.org/2000/svg"
    private const val BASELINE_METRIC_PROBE = "中"
    private const val BOPOMOFO_LANG = "zh-Hant-TW"

    // Interlinear line geometry (ADR 0024/0030): the web underline sits at
    // baseline + 0.18em, with a slightly heavier 0.08em stroke so it reads at
    // browser text sizes while staying clear of the CJK face.
    private const val UNDERLINE_OFFSET_EM = 0.18f
    private const val LINE_THICKNESS_EM = 0.08f
    private const val EMPHASIS_DOT_SCALE = 0.85f
    private const val RUBY_ASCENT_RATIO = 0.8f // fallback 注文 ascent when font metrics are unavailable
    private const val BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE = 0.82f
    private const val BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR = 0.404f
    private const val BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD = 0.446f
    private const val BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR = 0.644f
    private const val BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD = 0.682f
    private const val WAVY_HALF_WAVE_EM = 0.2f
    private const val WAVY_AMPLITUDE_EM = 0.06f
    private const val WAVY_ENDPOINT_EPSILON_PX = 0.01f
    private const val DASH_DOM_ABSOLUTE_TOLERANCE_PX = 0.75f
    private const val DASH_DOM_RELATIVE_TOLERANCE = 0.03f

    private val ENGINE_FLOW_STYLE_OVERRIDES = listOf(
        "white-space-collapse" to "preserve",
        "overflow-wrap" to "normal",
        "text-autospace" to "no-autospace",
        "text-wrap-mode" to "nowrap",
        "-webkit-hyphens" to "manual",
        "hyphens" to "manual",
        "word-break" to "normal",
    )
}

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """() => typeof Intl !== 'undefined' && Intl.Segmenter
      ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
      : null""",
)
private external fun createGraphemeSegmenter(): JsAny?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(segmenter, text) => {
      if (segmenter) {
        let last = 0;
        for (const item of segmenter.segment(text)) last = item.index;
        return last;
      }
      const points = Array.from(text);
      return points.length === 0 ? 0 : text.length - points[points.length - 1].length;
    }""",
)
private external fun trailingGraphemeStart(segmenter: JsAny?, text: String): Int

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element, marginRight) => element.style.setProperty('margin-right', marginRight + 'px', 'important')")
private external fun setInlineObjectTrailingMargin(element: Element, marginRight: Float)

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => { const range = document.createRange(); range.selectNodeContents(element); return range.getBoundingClientRect().width; }")
private external fun domTextRangeWidth(element: HTMLElement): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(element) => getComputedStyle(element).fontFamily")
private external fun computedFontFamily(element: HTMLElement): String

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun(
    """(actual, expected) => {
      const first = (value) => {
        let quote = '', token = '';
        for (const char of String(value || '')) {
          if (quote) { if (char === quote) quote = ''; else token += char; continue; }
          if (char === '"' || char === "'") { quote = char; continue; }
          if (char === ',') break;
          token += char;
        }
        return token.trim();
      };
      return first(actual).toLocaleLowerCase() === first(expected).toLocaleLowerCase();
    }""",
)
private external fun sameLeadingCssFamily(actual: String, expected: String): Boolean

internal sealed interface DomRunSpacing {
    data object None : DomRunSpacing
    data class Letter(val px: Float) : DomRunSpacing
    data class TrailingLetter(val px: Float) : DomRunSpacing
    data class Overlap(val px: Float) : DomRunSpacing
}

internal fun resolveDomRunSpacing(display: String, trailingGap: Float): DomRunSpacing = when {
    trailingGap == 0f -> DomRunSpacing.None
    display.length == 1 -> DomRunSpacing.Letter(trailingGap)
    trailingGap > 0f -> DomRunSpacing.TrailingLetter(trailingGap)
    else -> DomRunSpacing.Overlap(trailingGap)
}
