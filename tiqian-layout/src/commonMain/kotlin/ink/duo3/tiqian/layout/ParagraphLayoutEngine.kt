package ink.duo3.tiqian.layout

import ink.duo3.tiqian.clreq.AutoSpaceMode
import ink.duo3.tiqian.clreq.AutoSpacePolicy
import ink.duo3.tiqian.clreq.BuiltInClreqProfileResolver
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.clreq.ClreqProfileResolver
import ink.duo3.tiqian.clreq.HangingPunctuationStyle
import ink.duo3.tiqian.clreq.LineAdjustmentStrategy
import ink.duo3.tiqian.clreq.LineEndPunctuationStyle
import ink.duo3.tiqian.clreq.NumberSymbolCohesion
import ink.duo3.tiqian.clreq.PunctuationClass
import ink.duo3.tiqian.clreq.PunctuationGluePlacement
import ink.duo3.tiqian.clreq.ClreqPunctuationGlyphSubstitutor
import ink.duo3.tiqian.core.AutoSpaceDecisionInfo
import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.ClusterGeometryDecisionInfo
import ink.duo3.tiqian.core.DecorationDecisionInfo
import ink.duo3.tiqian.core.RubyDecisionInfo
import ink.duo3.tiqian.clreq.ZhuyinParser
import ink.duo3.tiqian.clreq.ZhuyinTone
import ink.duo3.tiqian.core.RubyKind
import ink.duo3.tiqian.core.RubySpan
import ink.duo3.tiqian.core.ZhuyinDecisionInfo
import ink.duo3.tiqian.core.ZhuyinGlyphPlacement
import ink.duo3.tiqian.core.ZhuyinGlyphRole
import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.DecorationSegmentInfo
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.FontDecisionInfo
import ink.duo3.tiqian.core.LineEdgeTrimDecisionInfo
import ink.duo3.tiqian.core.Glyph
import ink.duo3.tiqian.core.GlyphRun
import ink.duo3.tiqian.core.JustificationAllocationInfo
import ink.duo3.tiqian.core.JustificationDecisionInfo
import ink.duo3.tiqian.core.LayoutDebugInfo
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.LineBox
import ink.duo3.tiqian.core.LineDebugInfo
import ink.duo3.tiqian.core.LineDecisionInfo
import ink.duo3.tiqian.core.LineRepairAllocationInfo
import ink.duo3.tiqian.core.LineRepairCandidateInfo
import ink.duo3.tiqian.core.LineRepairDecisionInfo
import ink.duo3.tiqian.core.MetricDecisionInfo
import ink.duo3.tiqian.core.PunctuationDecisionInfo
import ink.duo3.tiqian.core.Rect
import ink.duo3.tiqian.core.RoleOverrideInfo
import ink.duo3.tiqian.core.Size
import ink.duo3.tiqian.core.SpacingDecisionInfo
import ink.duo3.tiqian.core.LastLineAlignment
import ink.duo3.tiqian.core.KinsokuDecisionInfo
import ink.duo3.tiqian.core.LineLengthGridDecisionInfo
import ink.duo3.tiqian.core.FirstLineIndentDecisionInfo
import kotlin.math.floor
import ink.duo3.tiqian.core.LineSpacingDecisionInfo
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.font.CjkFontRoleClassifier
import ink.duo3.tiqian.font.FallbackResolver
import ink.duo3.tiqian.font.FontMetricsNormalizationInput
import ink.duo3.tiqian.font.FontMetricsNormalizer
import ink.duo3.tiqian.font.FontMetricsRequest
import ink.duo3.tiqian.font.FontMetricsResolver
import ink.duo3.tiqian.font.FontDecision
import ink.duo3.tiqian.font.FontRequest
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.font.FontRoleClassifier
import ink.duo3.tiqian.font.FontRoleContext
import ink.duo3.tiqian.font.LayoutFontMetrics
import ink.duo3.tiqian.font.PreferCjkForAmbiguousPunctuationResolver
import ink.duo3.tiqian.font.RawFontMetrics
import ink.duo3.tiqian.font.ScriptAwareFontMetricsNormalizer
import ink.duo3.tiqian.font.StubFontMetricsResolver
import ink.duo3.tiqian.linebreak.Hyphenator
import ink.duo3.tiqian.linebreak.NoHyphenator
import ink.duo3.tiqian.shaping.ExplainableStubTextShaper
import ink.duo3.tiqian.shaping.ShapingInput
import ink.duo3.tiqian.shaping.ShapingResult
import ink.duo3.tiqian.shaping.TextShaper

interface ParagraphLayoutEngine {
    fun layout(input: LayoutInput): LayoutResult
}

class ExplainableStubParagraphLayoutEngine(
    private val fontRoleClassifier: FontRoleClassifier = CjkFontRoleClassifier(),
    private val fallbackResolver: FallbackResolver = PreferCjkForAmbiguousPunctuationResolver(),
    private val clreqProfileResolver: ClreqProfileResolver = BuiltInClreqProfileResolver,
    private val fontMetricsResolver: FontMetricsResolver = StubFontMetricsResolver(),
    private val fontMetricsNormalizer: FontMetricsNormalizer = ScriptAwareFontMetricsNormalizer(),
    private val punctuationAtomBuilder: PunctuationAtomBuilder = PunctuationAtomBuilder(),
    private val punctuationSpacingCompressor: PunctuationSpacingCompressor = PunctuationSpacingCompressor(),
    private val quotePairAnalyzer: QuotePairAnalyzer = QuotePairAnalyzer(),
    private val lineBreaker: LineBreaker = GreedyLineBreaker(),
    private val justifier: Justifier = Justifier(),
    private val textShaper: TextShaper = ExplainableStubTextShaper(),
    /**
     * Western syllable hyphenation source (CLREQ「可使用连字符处」). Defaults to
     * the platform hyphenator ([defaultHyphenator]: en-US on JVM) so
     * `LineEndHangingHyphen` is ON by default; pass [NoHyphenator] to opt out.
     * (`LatinForcedHyphenBreak` over-long hard-break fires regardless.)
     */
    private val hyphenator: Hyphenator = defaultHyphenator(),
) : ParagraphLayoutEngine {
    override fun layout(input: LayoutInput): LayoutResult {
        val text = input.content.text
        val fontSize = input.textStyle.fontSize
        // Rich-text per-span style (ADR 0030 B 档): a cluster covered by a span
        // SHAPES at that span's size + weight + slant, and is MEASURED at its
        // size; the paragraph base still owns the structural em decisions (grid /
        // 段首缩进) per the mixed-size 归属 rule. The boundary em decisions
        // (中西间距、标点 glue) stay at base for now — per-owner is the follow-up.
        // Each span's TextStyle is the FULLY-RESOLVED style (base + overrides),
        // so unset fields already equal base.
        val sizedSpans = input.content.spans.filter { it.range.start < it.range.end }
        fun styleAt(offset: Int) =
            sizedSpans.lastOrNull { offset >= it.range.start && offset < it.range.end }?.style ?: input.textStyle
        fun fontSizeAt(offset: Int): Float = styleAt(offset).fontSize
        // BilingualEmphasisWesternItalic (ADR 0030/着重号惯例): 着重号 marks Han with
        // dots, but Western emphasis is ITALIC, not dots. A Latin run inside an
        // Emphasis span shapes italic (and gets no dot — see computeDecorationDecisions).
        val emphasisRanges = input.decorations.filter { it.kind == DecorationKind.Emphasis }.map { it.range }
        fun emphasisItalicAt(offset: Int): Boolean =
            emphasisRanges.any { offset >= it.start && offset < it.end }
        // 行间注 (ruby, ADR 0032): 注文 above the base; the band reserved in the line
        // height is the注文 font's REAL ascent+descent stacked over the base 字身顶
        // (computed after metricDecisions below). advance handled by 避让.
        val rubyFontSize = fontSize * RUBY_FONT_EM
        // 注文 (拼音/注音) is set 100 weight units heavier than the base text: at the
        // small ruby size a step up in weight keeps it legible (clamped to 900).
        val rubyFontWeight = (input.textStyle.fontWeight + 100).coerceIn(1, 900)
        // 拼音 (above-base) ruby only; 注音 (RubyKind.Zhuyin, right-side) is parsed +
        // carried but its geometry/advance is the next slice (ADR 0033) — inert here.
        val pinyinSpans = input.rubySpans.filter { it.kind == RubyKind.Pinyin }
        // Span edges force cluster splits so no cluster straddles a style change
        // (a Latin word / coalesced 标点 run otherwise swallows the boundary).
        val spanBoundaries: Set<Int> = sizedSpans.flatMapTo(mutableSetOf()) { listOf(it.range.start, it.range.end) }
        val clreqProfile = clreqProfileResolver.resolve(input.profileId)
        val context = FontRoleContext(
            locale = input.textStyle.locale,
            regionHint = clreqProfile.region.name,
        )
        val punctuationGlyphSubstitutor = ClreqPunctuationGlyphSubstitutor(
            policy = clreqProfile.punctuationGlyphPolicy,
        )

        // LineLengthGridQuantization (grid-first, ADR 0028): floor the
        // container to an integer number of 字 (N×fontSize) so the body lands
        // on the grid; the sub-字 leftover places the whole body within the
        // container by bodyAlignment. Bypassable for known-exact widths.
        // Computed up front because LatinForcedHyphenBreak (below) needs the
        // measure to decide which Latin pieces can never fit on a line.
        val grid = input.paragraphStyle.lineLengthGrid
        val containerWidth = input.constraints.maxWidth
        val gridCells = floor(containerWidth / fontSize).toInt().coerceAtLeast(1)
        val measure = if (grid.enabled) {
            (gridCells * fontSize).coerceAtMost(containerWidth)
        } else {
            containerWidth
        }
        val gridSlack = containerWidth - measure
        val gridBodyAlignment = grid.bodyAlignment ?: input.paragraphStyle.lastLineAlignment
        val gridBodyOffset = if (!grid.enabled) {
            0f
        } else {
            when (gridBodyAlignment) {
                LastLineAlignment.Start -> 0f
                LastLineAlignment.Center -> gridSlack / 2f
                LastLineAlignment.End -> gridSlack
            }
        }
        val lineLengthGridDecision = LineLengthGridDecisionInfo(
            enabled = grid.enabled,
            containerWidth = containerWidth,
            fontSize = fontSize,
            cells = if (grid.enabled) gridCells else (measure / fontSize).toInt(),
            measure = measure,
            slack = gridSlack,
            bodyAlignment = gridBodyAlignment.name,
            bodyOffset = gridBodyOffset,
            reason = if (grid.enabled) "LineLengthGridQuantization" else "GridBypassed",
        )
        val measureEm = measure / fontSize

        val quotePairs = quotePairAnalyzer.analyze(text)
        val quoteRoleOverrides = quotePairAnalyzer.classifyPairs(text, quotePairs, fontRoleClassifier, context)
        val roleOverrideInfos = quoteRoleOverrides.toRoleOverrideInfos(
            text = text,
            baseClassifier = fontRoleClassifier,
            context = context,
            source = "QuotePairAwareLatinContext",
            reason = "quote-pair-outer-context",
        )
        val effectiveClassifier: FontRoleClassifier = if (quoteRoleOverrides.isNotEmpty()) {
            QuotePairAwareFontRoleClassifier(fontRoleClassifier, quoteRoleOverrides)
        } else {
            fontRoleClassifier
        }

        val clusterRanges = clusterRanges(text, effectiveClassifier, context, clreqProfile, spanBoundaries)
        val fontDecisions = clusterRanges.map { range ->
            val role = effectiveClassifier.classify(text, range, context)
            fallbackResolver.resolve(
                text = text,
                range = range,
                request = FontRequest(
                    preferredFamilies = input.textStyle.fontFamilies,
                    locale = input.textStyle.locale,
                    role = role,
                ),
            )
        }

        // SubstitutionRollbackOnMissingGlyph: a CLREQ display substitution
        // (ADR 0003, e.g. `——` → `⸺`) is only an improvement if the resolved
        // font actually covers the substituted codepoint — `⸺` U+2E3A is
        // absent from PingFang SC / Hiragino / Heiti and would render tofu.
        // When the shaper reports .notdef glyphs for a substituted cluster,
        // re-shape with the source text and record the rollback.
        val substitutionRollbackRanges = mutableSetOf<TextRange>()
        fun shapeSegment(decision: FontDecision, segmentRange: TextRange): ShapingResult {
            val sourceText = text.substring(segmentRange.start, segmentRange.end)
            val substitution = punctuationGlyphSubstitutor.substitute(sourceText)
            val baseSegmentStyle = styleAt(segmentRange.start)
            val segmentStyle = if (decision.role == FontRole.LatinText && emphasisItalicAt(segmentRange.start)) {
                baseSegmentStyle.copy(italic = true)
            } else {
                baseSegmentStyle
            }
            val shaped = textShaper.shape(
                ShapingInput(
                    text = text,
                    range = segmentRange,
                    style = segmentStyle,
                    fontDecision = decision,
                    displayText = substitution.displayText,
                ),
            )
            return if (substitution.displayText == sourceText || shaped.decisions.none { it.missingGlyphs > 0 }) {
                shaped
            } else {
                substitutionRollbackRanges += segmentRange
                textShaper.shape(
                    ShapingInput(
                        text = text,
                        range = segmentRange,
                        style = segmentStyle,
                        fontDecision = decision,
                        displayText = sourceText,
                    ),
                )
            }
        }
        // LatinWordSegmentation (gap audit 缺口 2): Latin runs are shaped per
        // word/space segment so each word and each space run becomes its own
        // cluster — line breaks happen at word boundaries, word spaces become
        // first-class adjustable clusters (CLREQ 西文词距). Cross-segment
        // kerning at a space boundary is negligible.
        //
        // LineEndHangingHyphen (CLREQ §换行与断词连字「可使用连字符处」, ADR 0029):
        // an all-letter Latin word is additionally split so the breaker may wrap
        // it; the hyphen HANGS at the line end (like 行尾点号悬挂) — never reserved
        // in the measure — so the content's 行尾对齐 holds. `hyphenOffsets` are the
        // absolute source offsets a break at which earns a trailing hyphen.
        //
        // Cut points are (a) the [hyphenator]'s syllable points, plus (b)
        // `LatinForcedHyphenBreak`: for any piece STILL wider than the measure
        // (hyphenation off, or a syllable/token that can't fit), character-level
        // fallback cuts that hard-break it — preferring 前二后三 (2/3) within the
        // piece, breaking anywhere only when that can't be met (满足不了就算了).
        val hyphenOffsets = mutableSetOf<Int>()
        var hyphenAdvanceOrNull: Float? = null
        fun latinWordCuts(decision: FontDecision, wordRange: TextRange): List<Int> {
            val syllable = hyphenator.hyphenate(text.substring(wordRange.start, wordRange.end))
            val cuts = sortedSetOf<Int>()
            cuts += syllable.map { wordRange.start + it }
            val relBounds = (listOf(0) + syllable + listOf(wordRange.length)).distinct()
            for (i in 0 until relBounds.size - 1) {
                val a = relBounds[i]
                val b = relBounds[i + 1]
                val pieceAdvance = shapeSegment(decision, TextRange(wordRange.start + a, wordRange.start + b))
                    .clusters.singleOrNull()?.advance ?: 0f
                if (pieceAdvance <= measure) continue
                val lo = a + HYPHEN_MIN_LEFT
                val hi = b - HYPHEN_MIN_RIGHT
                val range = if (lo <= hi) lo..hi else (a + 1) until b
                for (off in range) cuts += wordRange.start + off
            }
            return cuts.toList()
        }
        // ExistingHyphenBreak (CY/T 154-2017 §9.3): a hyphenated compound breaks
        // AT its existing hyphens — no NEW hyphen added, the existing one sits at
        // the line end. Keeps ≥2 letters on each side (§9.4「不要把单个字母放在
        // 一行的行末或行首」), which also leaves number ranges / abbreviation-number
        // tokens (3-4, COVID-19) unbroken. These are clean break boundaries, not
        // synthetic-hyphen points, so they never enter `hyphenOffsets`.
        fun existingHyphenCuts(wordRange: TextRange): List<Int> {
            val w = text.substring(wordRange.start, wordRange.end)
            val cuts = mutableListOf<Int>()
            for (i in w.indices) {
                if (w[i] != '-') continue
                var before = 0
                var j = i - 1
                while (j >= 0 && w[j].isLetter()) { before += 1; j -= 1 }
                var after = 0
                var k = i + 1
                while (k < w.length && w[k].isLetter()) { after += 1; k += 1 }
                if (before >= 2 && after >= 2) cuts += wordRange.start + i + 1
            }
            return cuts
        }
        // CamelCaseBreak: a camelCase/PascalCase product token (internal capital)
        // breaks at its humps — lowercase→uppercase, or an acronym boundary
        // Upper→Upper-then-lower (XML|Http) — with NO hyphen (the capital signals
        // the break). ≥2 letters each side (§9.4). Clean breaks, not hyphenOffsets.
        fun camelCaseCuts(wordRange: TextRange): List<Int> {
            val w = text.substring(wordRange.start, wordRange.end)
            val humps = (1 until w.length).filter { i ->
                w[i].isUpperCase() && (
                    w[i - 1].isLowerCase() ||
                        (w[i - 1].isUpperCase() && i + 1 < w.length && w[i + 1].isLowerCase())
                    )
            }
            val bounds = listOf(0) + humps + listOf(w.length)
            return humps.filter { h ->
                h - bounds.last { it < h } >= 2 && bounds.first { it > h } - h >= 2
            }.map { wordRange.start + it }
        }
        val shapingResults = fontDecisions.flatMap { decision ->
            decision.shapingSegments(text).flatMap { segmentRange ->
                val shaped = shapeSegment(decision, segmentRange)
                val word = shaped.clusters.singleOrNull()
                val isLatin = decision.role == FontRole.LatinText && word != null && word.text.isNotEmpty()
                val w = if (isLatin) word!!.text else ""
                val allLetters = isLatin && w.all { it.isLetter() }
                // §9.4 全大写缩写不断词；驼峰式在驼峰处断（无连字符）；含 '-' 在
                // 已有连字符处断（§9.3，无新连字符）。以上都是 clean 断点（不进
                // hyphenOffsets）。其余全字母词走 §9.2 音节 + 硬断（加合成连字符）。
                val isAbbreviation = allLetters && w.length >= 2 && w.none { it.isLowerCase() }
                val isCamelCase = allLetters && !isAbbreviation && (1 until w.length).any { w[it].isUpperCase() }
                val cleanCuts = when {
                    !isLatin -> emptyList()
                    w.contains('-') -> existingHyphenCuts(segmentRange)
                    isCamelCase -> camelCaseCuts(segmentRange)
                    else -> emptyList()
                }
                val hyphenCuts = if (
                    allLetters && !isAbbreviation && !isCamelCase && !w.contains('-') && cleanCuts.isEmpty()
                ) {
                    latinWordCuts(decision, segmentRange)
                } else {
                    emptyList()
                }
                val allCuts = (cleanCuts + hyphenCuts).distinct().sorted()
                if (allCuts.isEmpty()) {
                    listOf(shaped)
                } else {
                    if (hyphenCuts.isNotEmpty()) {
                        hyphenOffsets += hyphenCuts
                        if (hyphenAdvanceOrNull == null) {
                            hyphenAdvanceOrNull = textShaper.shape(
                                ShapingInput(
                                    text = "-",
                                    range = TextRange(0, 1),
                                    style = input.textStyle,
                                    fontDecision = decision,
                                    displayText = "-",
                                ),
                            ).clusters.singleOrNull()?.advance ?: (0.5f * fontSize)
                        }
                    }
                    val bounds = listOf(segmentRange.start) + allCuts + listOf(segmentRange.end)
                    (0 until bounds.size - 1).map { k ->
                        shapeSegment(decision, TextRange(bounds[k], bounds[k + 1]))
                    }
                }
            }
        }
        val hyphenAdvance = hyphenAdvanceOrNull ?: 0f
        val rawNaturalClusters = shapingResults.flatMap { it.clusters }
        val shapedGlyphsByClusterRange = shapingResults
            .flatMap { it.glyphRuns }
            .flatMap { it.glyphs }
            .groupBy { it.clusterRange }
        val shapingDecisions = shapingResults.flatMap { it.decisions }
        rawNaturalClusters.requireCoveredBy(fontDecisions)

        val autoSpaceResult = rawNaturalClusters.applyAutoSpacePolicy(
            fontDecisions = fontDecisions,
            policy = clreqProfile.autoSpace,
            fontSize = fontSize,
        )
        val naturalClusters = autoSpaceResult.clusters
        val autoSpaceDecisions = autoSpaceResult.decisions
        val clusterRoles = naturalClusters.map { cluster ->
            fontDecisions.first { cluster.range.isInside(it.range) }.role
        }

        // Punctuation atoms are a CJK-text concern: a LatinText cluster's ASCII
        // punctuation ('-', '/', ',') is part of the Latin glyph run (an English
        // hyphen, not a CJK 连接号), so it must NOT get a 短横线/标点 atom that
        // would collapse the cluster to half-width.
        val punctuationAtoms = naturalClusters.mapIndexedNotNull { idx, cluster ->
            if (clusterRoles[idx] == FontRole.LatinText) null else cluster
        }.flatMap { cluster ->
            cluster.punctuationAtoms(
                em = fontSize,
                builder = punctuationAtomBuilder,
                shapedGlyphs = shapedGlyphsByClusterRange[cluster.range].orEmpty(),
                gluePlacement = clreqProfile.gluePlacement,
                widthPolicy = clreqProfile.punctuationWidth,
            )
        }
        val spacingPlan = punctuationSpacingCompressor.compress(punctuationAtoms, em = fontSize)
        // Measure a 注文's width in ITS OWN font at the ruby size (拼音 is variable-width).
        fun measureRubyWidth(rubyText: String, families: List<String>): Float {
            if (rubyText.isEmpty()) return 0f
            val range = TextRange(0, rubyText.length)
            val decision = fallbackResolver.resolve(
                text = rubyText,
                range = range,
                request = FontRequest(
                    preferredFamilies = families.ifEmpty { input.textStyle.fontFamilies },
                    locale = input.textStyle.locale,
                    role = FontRole.LatinText,
                ),
            )
            return textShaper.shape(
                ShapingInput(
                    text = rubyText,
                    range = range,
                    style = input.textStyle.copy(fontSize = rubyFontSize, fontFamilies = families, fontWeight = rubyFontWeight),
                    fontDecision = decision,
                    displayText = rubyText,
                ),
            ).clusters.sumOf { it.advance.toDouble() }.toFloat()
        }
        // 避让: left→right, push a 注文 (and everything after) right by the MINIMAL
        // amount that restores the word-space gap to the previous 注文; record it as
        // trailing 字距 on the cluster just before the span. Narrow 注文 (gap already
        // ok) get nothing → they overhang freely (CLREQ「只要不侵犯最小间距，可允许
        // 注文伸展到相邻基字上方」). The first span is never pushed.
        fun computeRubySpread(natural: List<Cluster>, rubySize: Float): Map<Int, Float> {
            if (pinyinSpans.isEmpty()) return emptyMap()
            val wordSpace = rubySize * RUBY_MIN_GAP_EM_OF_RUBY
            val leftX = FloatArray(natural.size)
            var acc = 0f
            for (i in natural.indices) { leftX[i] = acc; acc += natural[i].advance }
            val measures = pinyinSpans.mapNotNull { ruby ->
                val idxRange = natural.clusterIndexRangeFor(ruby.baseRange) ?: return@mapNotNull null
                val center = (leftX[idxRange.first] + leftX[idxRange.last] + natural[idxRange.last].advance) / 2f
                Triple(idxRange.first, center, measureRubyWidth(ruby.text, ruby.fontFamilies))
            }.sortedBy { it.first }
            val spread = HashMap<Int, Float>()
            var shift = 0f
            var prevRight = Float.NEGATIVE_INFINITY
            for ((firstCluster, centerNatural, rw) in measures) {
                var center = centerNatural + shift
                val needed = prevRight + wordSpace - (center - rw / 2f)
                if (needed > 0f && firstCluster > 0) {
                    spread.merge(firstCluster - 1, needed) { a, b -> a + b }
                    shift += needed
                    center += needed
                }
                prevRight = center + rw / 2f
            }
            return spread
        }
        // 行间注 避让 (ADR 0032): adjacent 注文 keep ≥ one 注文 word-space — add the
        // MINIMAL trailing 字距 where they'd crowd (narrower 注文 just overhang).
        // STRUCTURAL spread baked into baseGeometry so the breaker + final geometry
        // both see the widened advances.
        val rubySpread = computeRubySpread(naturalClusters, rubyFontSize)
        // 注音 (ADR 0033): reserve the 0.5em 注音 column ONLY on each annotated base
        // char's right side (its last cluster). The uniform every-char reservation is
        // 繁体中文 纵横对齐 — not built yet — so it stays OUT: the 注音 sits in its own
        // base's trailing space and adjacent unannotated text keeps normal spacing.
        val zhuyinSpans = input.rubySpans.filter { it.kind == RubyKind.Zhuyin }
        val rubyAndZhuyinSpread = if (zhuyinSpans.isEmpty()) {
            rubySpread
        } else {
            HashMap(rubySpread).apply {
                zhuyinSpans.forEach { z ->
                    val r = naturalClusters.clusterIndexRangeFor(z.baseRange) ?: return@forEach
                    merge(r.last, 0.5f * fontSize) { a, b -> a + b }
                }
            }
        }
        val baseGeometry = PunctuationGeometryLedger.from(
            naturalClusters = naturalClusters,
            punctuationAtoms = punctuationAtoms,
            spacingPlan = spacingPlan,
        ).withRubySpread(rubyAndZhuyinSpread)
        val clusters = baseGeometry.resolveClusters()
        // CLREQ 挤压处理优先顺序 (ADR 0020): tiered shrink resources for
        // PushIn. Punctuation classes map to tiers; style knobs gate the
        // inline-stop and sino-western tiers.
        val adjustmentStyle = clreqProfile.adjustment
        val glueCaps = baseGeometry.glueCapacities()
        val gapClusterRanges = autoSpaceDecisions
            .filter { it.side == "gap" }
            .map { it.clusterRange }
            .toSet()
        val atomClassByRange = punctuationAtoms.associate { it.range to it.punctuationClass }
        val shrinkOpportunities = buildList {
            naturalClusters.forEachIndexed { idx, cluster ->
                val caps = glueCaps[idx]
                if (caps != null) {
                    val cls = atomClassByRange[cluster.range]
                    when (cls) {
                        PunctuationClass.Interpunct,
                        PunctuationClass.MiddleDot,
                        -> {
                            // CLREQ ③ 间隔号：双侧同时、同等量，最小挤到 0。
                            val both = caps.leading + caps.trailing
                            if (both > 0f) {
                                add(ShrinkOpportunity(idx, tier = 3, capacity = both, channel = ShrinkChannel.LeadingAndTrailingGlue))
                            }
                        }

                        // CLREQ ④ 夹注符号：开始夹注的前侧、结束夹注的
                        // 后侧，最小挤到半个汉字字宽（= glue 全部可压）。
                        // Quote 经 pair 分析后开/闭各持一侧 glue，两个分支
                        // 自然各取其有的一侧。
                        PunctuationClass.Opening,
                        PunctuationClass.Closing,
                        PunctuationClass.Quote,
                        -> {
                            if (caps.leading > 0f) {
                                add(ShrinkOpportunity(idx, tier = 4, capacity = caps.leading, channel = ShrinkChannel.LeadingGlue))
                            }
                            if (caps.trailing > 0f) {
                                add(ShrinkOpportunity(idx, tier = 4, capacity = caps.trailing, channel = ShrinkChannel.TrailingGlue))
                            }
                        }

                        PunctuationClass.PauseOrStop -> {
                            // CLREQ ⑤ 行内逗、顿、分号（冒号原文未尽列，
                            // 按同档处理）；⑦ 行内句问叹排最后，且部分
                            // 风格禁止（knob）。
                            val isStop = cluster.displayText.firstOrNull() in INLINE_STOPS
                            val tier = if (isStop) 7 else 5
                            // Knob off: 行内句问叹 keep full width — their glue
                            // is only reachable via the tier-1 line-end
                            // promotion (行末削半 is a separate rule).
                            val lineEndOnly = isStop && !adjustmentStyle.allowInlineStopCompression
                            if (caps.trailing > 0f) {
                                add(
                                    ShrinkOpportunity(
                                        idx,
                                        tier = tier,
                                        capacity = caps.trailing,
                                        channel = ShrinkChannel.TrailingGlue,
                                        lineEndOnly = lineEndOnly,
                                    ),
                                )
                            }
                        }

                        // CLREQ 未列其余带 glue 的标点：按 ⑤ 档兜底。
                        else -> if (caps.trailing > 0f) {
                            add(ShrinkOpportunity(idx, tier = 5, capacity = caps.trailing, channel = ShrinkChannel.TrailingGlue))
                        }
                    }
                } else if (cluster.isSpaceRun()) {
                    if (cluster.range in gapClusterRanges) {
                        // CLREQ ⑥ 中西间距：最小挤为八分之一汉字宽（不是 0）；
                        // 部分风格禁止（knob）。
                        val capacity = cluster.advance - SINO_WESTERN_GAP_MIN_EM * fontSize
                        if (adjustmentStyle.allowSinoWesternGapAdjustment && capacity > 0f) {
                            add(ShrinkOpportunity(idx, tier = 6, capacity = capacity, channel = ShrinkChannel.RawAdvance))
                        }
                    } else {
                        // CLREQ ② 西文词距：最小挤到 1/4em。
                        val capacity = cluster.advance - WORD_SPACE_MIN_EM * fontSize
                        if (capacity > 0f) {
                            add(ShrinkOpportunity(idx, tier = 2, capacity = capacity, channel = ShrinkChannel.RawAdvance))
                        }
                    }
                }
            }
        }

        val metricDecisions = fontDecisions.map { decision ->
            val request = FontMetricsRequest(
                fontKey = decision.candidate.key,
                fontSize = fontSizeAt(decision.range.start),
                role = decision.role,
                locale = input.textStyle.locale,
            )
            val rawMetrics = fontMetricsResolver.resolve(request)
            val layoutMetrics = fontMetricsNormalizer.normalize(
                FontMetricsNormalizationInput(
                    request = request,
                    rawMetrics = rawMetrics,
                ),
            )
            ClusterMetricDecision(
                range = decision.range,
                sourceText = text.substring(decision.range.start, decision.range.end),
                request = request,
                rawMetrics = rawMetrics,
                layoutMetrics = layoutMetrics,
            )
        }

        // 行间注 vertical placement (ADR 0032): stack the 注文 font's REAL 字身框
        // (ascent/descent at the ruby size, ADR 0002 amendment — no synthesized em)
        // on top of the base 字身顶, with a small clearance. The band reserved in the
        // line height = 注文 ascent+descent+gap; the注文 baseline drops below the base
        // baseline by 基字 ascent + 注文 descent + gap.
        val baseAscent = metricDecisions.maxOfOrNull { it.layoutMetrics.ascent } ?: (fontSize * 0.88f)
        val baseDescent = metricDecisions.maxOfOrNull { it.layoutMetrics.descent } ?: (fontSize * 0.12f)
        // 字身框 alignment reference (ADR 0030 follow-up): the 字身框 centre of the BASE
        // CJK font at the base size (so base body text keeps its baseline, shift 0). Each
        // cluster shifts so its 字身框 centre meets this line — mixed fonts/sizes align by
        // the ideographic box, not the alphabetic baseline.
        val baseRefMetrics = metricDecisions
            .firstOrNull { it.request.role == FontRole.CjkText && it.request.fontSize == fontSize }
            ?.layoutMetrics
        val baseBoxHalf = if (baseRefMetrics != null) {
            (baseRefMetrics.ascent - baseRefMetrics.descent) / 2f
        } else {
            (baseAscent - baseDescent) / 2f
        }
        val rubyLayoutMetrics = if (pinyinSpans.isEmpty()) {
            null
        } else {
            val rubyDecision = fallbackResolver.resolve(
                text = "x",
                range = TextRange(0, 1),
                request = FontRequest(preferredFamilies = emptyList(), locale = input.textStyle.locale, role = FontRole.LatinText),
            )
            val req = FontMetricsRequest(
                fontKey = rubyDecision.candidate.key,
                fontSize = rubyFontSize,
                role = FontRole.LatinText,
                locale = input.textStyle.locale,
            )
            fontMetricsNormalizer.normalize(FontMetricsNormalizationInput(request = req, rawMetrics = fontMetricsResolver.resolve(req)))
        }
        val rubyStackGap = fontSize * RUBY_STACK_GAP_EM
        val rubyBand = if (rubyLayoutMetrics == null) 0f else rubyLayoutMetrics.ascent + rubyLayoutMetrics.descent + rubyStackGap
        val rubyBaselineDrop = baseAscent + (rubyLayoutMetrics?.descent ?: 0f) + rubyStackGap

        // InterlinearMarkLineSpacingFloor (CLREQ 5.6.1.1): with 行间标点
        // (着重号、示亡号 etc.) present, line spacing (height − 字身高) must not
        // drop below 1/2 字号 — a tight line height would collide the marks with
        // the next line. (双面装 5/8 is print-only — show-through — deferred to a
        // print backend, like 竖排.)
        val interlinearSpacingFloor = if (input.decorations.isEmpty()) 0f else 0.5f * fontSize
        val defaultBodyLineHeight = fontSize * DEFAULT_BODY_LINE_HEIGHT_EM
        // Base line metrics WITHOUT the ruby band — the band is added PER LINE below
        // (only lines that carry 拼音 ruby get it, unless `rubyUniformBand`), so a
        // single ruby no longer inflates the whole paragraph's line height (ADR 0032).
        val baseLineMetrics = metricDecisions.lineMetrics(
            explicitLineHeight = input.paragraphStyle.lineHeight,
            defaultLineHeight = defaultBodyLineHeight,
            spacingFloor = interlinearSpacingFloor,
        )
        val lineSpacingDecision = if (baseLineMetrics.height <= 0f) {
            null
        } else {
            val natural = baseLineMetrics.height - baseLineMetrics.extraLeading
            val requested = input.paragraphStyle.lineHeight
            // Did the mark floor raise the line above what the explicit/default
            // height alone would give? (The 0.5em floor is subsumed by the 1.5em
            // body default, so it only binds against an explicit tight lineHeight.)
            val markFloorBinds = interlinearSpacingFloor > 0f &&
                natural + interlinearSpacingFloor > (requested ?: defaultBodyLineHeight) + 0.001f
            LineSpacingDecisionInfo(
                naturalHeight = natural,
                requestedLineHeight = requested,
                resolvedHeight = baseLineMetrics.height,
                spacingFloor = interlinearSpacingFloor,
                floorApplied = markFloorBinds,
                reason = when {
                    requested != null && !markFloorBinds -> "ExplicitLineHeight"
                    markFloorBinds -> "InterlinearMarkLineSpacingFloor"
                    else -> "CjkBodyLineHeightDefault"
                },
            )
        }
        // ParagraphFirstLineIndent (CLREQ 段首缩排): the first line's usable
        // measure shrinks by the indent; rendering shifts its start edge.
        // MeasureAdaptiveFirstLineIndent: the indent default narrows to 1 字 on
        // short measures (< shortBelowEm 字); an explicit firstLineIndent (ic)
        // overrides. Threshold defaults to 14 字 like MeasureAdaptiveKinsoku's
        // hanging but is an INDEPENDENT knob (ADR 0021 amendment).
        val explicitIndentEm = input.paragraphStyle.firstLineIndent?.count
        val indentPolicy = input.paragraphStyle.firstLineIndentPolicy
        // 段落缩排 (block indent) insets EVERY line; 段首缩进 (firstLine) stacks on
        // top, relative to the block, and MAY be negative (凸排：首行退回字头).
        // Adaptive default is ≥0; an explicit value flows through as-is (incl.
        // negative). The effective per-line indent is clamped ≥0 at use.
        // `ic` resolves against the paragraph base 字身框 = fontSize (ADR 0034 段级锚点).
        val blockIndent = input.paragraphStyle.blockIndent.toPx(fontSize)
        val resolvedIndentEm = explicitIndentEm ?: indentPolicy.resolveEm(measureEm)
        val firstLineIndent = (blockIndent + resolvedIndentEm * fontSize).coerceAtLeast(0f)
        val firstLineIndentDecision = FirstLineIndentDecisionInfo(
            source = if (explicitIndentEm != null) "Explicit" else "MeasureAdaptiveFirstLineIndent",
            measureEm = measureEm,
            thresholdEm = indentPolicy.shortBelowEm,
            resolvedEm = resolvedIndentEm,
        )
        // Resolve 禁则档 + 悬挂 from the kinsoku mode and the measure in 字
        // (MeasureAdaptiveKinsoku default keys on measure/fontSize).
        val resolvedKinsoku = clreqProfile.kinsokuMode.resolve(measureEm)
        val kinsokuDecision = KinsokuDecisionInfo(
            measureEm = measureEm,
            level = resolvedKinsoku.level.name,
            hanging = resolvedKinsoku.hanging.name,
            reason = resolvedKinsoku.reason,
        )
        // LineEndHangingPunctuation (CLREQ 行尾点号悬挂, ADR 0006): which
        // clusters may hang past the measure. 顿/逗/句 only.
        val hangableClusters: Set<Int> = when (resolvedKinsoku.hanging) {
            HangingPunctuationStyle.Disabled -> emptySet()
            HangingPunctuationStyle.PauseStops -> naturalClusters.indices.filterTo(mutableSetOf()) { idx ->
                naturalClusters[idx].displayText.singleOrNull() in HANGABLE_PUNCTUATION
            }
        }
        // 行首/行尾禁则按解析出的 KinsokuLevel（CLREQ 四档）；空集 = 不处理档.
        val kinsokuRule = ClreqKinsokuRule(resolvedKinsoku.level)
        val forbiddenLineStartClusters: Set<Int> = naturalClusters.indices.filterTo(mutableSetOf()) { idx ->
            kinsokuRule.forbiddenAtLineStart(naturalClusters[idx])
        }
        val forbiddenLineEndClusters: Set<Int> = naturalClusters.indices.filterTo(mutableSetOf()) { idx ->
            kinsokuRule.forbiddenAtLineEnd(naturalClusters[idx])
        }
        // LineEndHangingHyphen as a LAST resort (ADR 0029 amendment): a break
        // before one of these clusters is a syllable/hard-break continuation —
        // the breaker prefers whole-word wrap + justification and only takes it
        // when the line would otherwise stretch 汉字间距 past the threshold.
        val hyphenBreakClusters: Set<Int> = if (hyphenOffsets.isEmpty()) {
            emptySet()
        } else {
            naturalClusters.indices.filterTo(mutableSetOf()) {
                naturalClusters[it].range.start in hyphenOffsets
            }
        }
        // CJK↔CJK boundaries — the stretchable 汉字间距 the breaker gauges line
        // looseness against.
        val cjkInterCharBoundaries: Set<Int> = (1 until naturalClusters.size).filterTo(mutableSetOf()) {
            clusterRoles[it - 1] == FontRole.CjkText && clusterRoles[it] == FontRole.CjkText
        }
        // CJK↔Latin boundaries — 中西间距 absorbs deficit BEFORE 汉字间距 (CLREQ
        // 拉伸顺序), so the breaker discounts their capacity from the looseness.
        val sinoWesternBoundaries: Set<Int> = (1 until naturalClusters.size).filterTo(mutableSetOf()) {
            val a = clusterRoles[it - 1]
            val b = clusterRoles[it]
            (a == FontRole.CjkText && b == FontRole.LatinText) ||
                (a == FontRole.LatinText && b == FontRole.CjkText)
        }
        val lineSolution = if (text.isEmpty()) {
            LineSolution(emptyList())
        } else {
            lineBreaker.breakLines(
                naturalClusters = naturalClusters,
                adjustedClusters = clusters,
                // The breaker only needs per-line USABLE widths (via lineLimit):
                // feed it the body width (measure − blockIndent) and a first-line
                // indent relative to it. Rest lines then get the body width, line 0
                // gets `measure − firstLineIndent`. Identical to before when
                // blockIndent = 0; enables 段落缩排/凸排 with zero breaker changes.
                maxWidth = measure - blockIndent,
                firstLineIndent = firstLineIndent - blockIndent,
                shrinkOpportunities = shrinkOpportunities,
                // MourningSpanKeptUnbroken: 示亡号 spans stay on one line
                // whenever they fit (ADR 0018). NumberSymbolCohesion: CLREQ
                // 符号分离禁则 keeps 数字 + 前后缀符号/货币 on one line — but only
                // when the group actually fits the measure; a number wider than
                // the column can't be kept whole, so it falls back to normal
                // breaking instead of forcing an impossible constraint.
                unbreakableRanges = (
                    input.decorations
                        .filter { it.kind == DecorationKind.Mourning }
                        .mapNotNull { span -> naturalClusters.clusterIndexRangeFor(span.range) } +
                        // 行间注 (ADR 0032): 基文+注文不可拆 (CLREQ §注释符号).
                        pinyinSpans.mapNotNull { naturalClusters.clusterIndexRangeFor(it.baseRange) } +
                        NumberSymbolCohesion.unbreakableRanges(text)
                            .mapNotNull { r ->
                                naturalClusters.clusterIndexRangeFor(TextRange(r.first, r.last + 1))
                            }
                            .filter { idxRange ->
                                idxRange.sumOf { naturalClusters[it].advance.toDouble() } <= measure
                            }
                    ),
                hangableClusters = hangableClusters,
                forbiddenLineStartClusters = forbiddenLineStartClusters,
                forbiddenLineEndClusters = forbiddenLineEndClusters,
                hyphenBreakClusters = hyphenBreakClusters,
                cjkInterCharBoundaries = cjkInterCharBoundaries,
                maxCjkStretchPerGap = HYPHEN_LAST_RESORT_CJK_STRETCH_EM * fontSize,
                sinoWesternBoundaries = sinoWesternBoundaries,
                sinoWesternStretchCap = HYPHEN_SINO_WESTERN_STRETCH_CAP_EM * fontSize,
                // LineAdjustmentStrategy (ADR 0031): 推入/推出 方向取舍。仅 PushOutOnly
                // 不推入（= 旧行为）；其余以 bias = Ws/Wc 表达「先挤压」力度。
                lineAdjustmentPushIn = adjustmentStyle.lineAdjustment != LineAdjustmentStrategy.PushOutOnly,
                lineAdjustmentCompressBias = when (adjustmentStyle.lineAdjustment) {
                    LineAdjustmentStrategy.Auto -> adjustmentStyle.lineAdjustmentCompressBias
                    LineAdjustmentStrategy.PushInFirst -> 1_000_000f
                    LineAdjustmentStrategy.PushOutFirst -> 0.5f
                    LineAdjustmentStrategy.PushOutOnly -> 0f
                },
            )
        }
        val pushInAllocations = lineSolution.lines
            .mapNotNull { it.repair as? RepairOption.PushIn }
            .flatMap { it.allocations }
        val pushInTrailing = HashMap<Int, Float>()
        val pushInLeading = HashMap<Int, Float>()
        val pushInRawTrims = HashMap<Int, Float>()
        for (alloc in pushInAllocations) {
            when (alloc.channel) {
                ShrinkChannel.TrailingGlue ->
                    pushInTrailing.merge(alloc.clusterIndex, alloc.shrink) { a, b -> a + b }
                ShrinkChannel.LeadingGlue ->
                    // 开夹注符号前侧（CLREQ 挤压④）；渲染层按 consumed
                    // leading 左移字形原点（ADR 0017 amendment）。
                    pushInLeading.merge(alloc.clusterIndex, alloc.shrink) { a, b -> a + b }
                ShrinkChannel.LeadingAndTrailingGlue -> {
                    // CLREQ: 间隔号挤压必须同时从字面两侧、同等量处理.
                    pushInLeading.merge(alloc.clusterIndex, alloc.shrink / 2f) { a, b -> a + b }
                    pushInTrailing.merge(alloc.clusterIndex, alloc.shrink / 2f) { a, b -> a + b }
                }
                ShrinkChannel.RawAdvance ->
                    pushInRawTrims.merge(alloc.clusterIndex, alloc.shrink) { a, b -> a + b }
            }
        }
        // LineEndHangingHyphen 标点挤压 (ADR 0029 amend): a reserved hyphen that
        // would overflow the measure first squeezes the line's compressible glue
        // (the same `shrinkOpportunities`, in CLREQ 挤压 tier order, minus what
        // PushIn already took); only the residual it cannot recover hangs past
        // the edge. Augments the PushIn consume maps so the geometry applies both.
        fun lineHyphenAdvanceAt(lineIndex: Int): Float {
            if (hyphenOffsets.isEmpty() || lineIndex >= lineSolution.lines.lastIndex) return 0f
            val nextFirst = lineSolution.lines[lineIndex + 1].clusterRange.first
            return if (naturalClusters[nextFirst].range.start in hyphenOffsets) hyphenAdvance else 0f
        }
        if (hyphenOffsets.isNotEmpty()) {
            lineSolution.lines.forEachIndexed { lineIndex, line ->
                val hyphen = lineHyphenAdvanceAt(lineIndex)
                if (hyphen <= 0f) return@forEachIndexed
                val lineLimit = if (line.clusterRange.first == 0) measure - firstLineIndent else measure - blockIndent
                val content = line.clusterRange.sumOf { clusters[it].advance.toDouble() }.toFloat()
                var shortfall = content + hyphen - lineLimit
                if (shortfall <= 0.001f) return@forEachIndexed
                for (opp in shrinkOpportunities.filter { it.clusterIndex in line.clusterRange && !it.lineEndOnly }.sortedBy { it.tier }) {
                    if (shortfall <= 0.001f) break
                    val used = when (opp.channel) {
                        ShrinkChannel.TrailingGlue -> pushInTrailing[opp.clusterIndex] ?: 0f
                        ShrinkChannel.LeadingGlue -> pushInLeading[opp.clusterIndex] ?: 0f
                        ShrinkChannel.RawAdvance -> pushInRawTrims[opp.clusterIndex] ?: 0f
                        ShrinkChannel.LeadingAndTrailingGlue ->
                            (pushInLeading[opp.clusterIndex] ?: 0f) + (pushInTrailing[opp.clusterIndex] ?: 0f)
                    }
                    val take = minOf(shortfall, (opp.capacity - used).coerceAtLeast(0f))
                    if (take <= 0f) continue
                    when (opp.channel) {
                        ShrinkChannel.TrailingGlue -> pushInTrailing.merge(opp.clusterIndex, take) { a, b -> a + b }
                        ShrinkChannel.LeadingGlue -> pushInLeading.merge(opp.clusterIndex, take) { a, b -> a + b }
                        ShrinkChannel.LeadingAndTrailingGlue -> {
                            pushInLeading.merge(opp.clusterIndex, take / 2f) { a, b -> a + b }
                            pushInTrailing.merge(opp.clusterIndex, take / 2f) { a, b -> a + b }
                        }
                        ShrinkChannel.RawAdvance -> pushInRawTrims.merge(opp.clusterIndex, take) { a, b -> a + b }
                    }
                    shortfall -= take
                }
            }
        }
        val pushInGeometry = baseGeometry
            .consumeTrailingByCluster(pushInTrailing)
            .consumeLeadingByCluster(pushInLeading)
        val pushInClusters = pushInGeometry.resolveClusters()
        val edgeTrimResult = pushInGeometry.consumeLineEdgeGlue(
            lines = lineSolution.lines,
            forceLineEndHalfWidth = adjustmentStyle.lineEndPunctuation ==
                LineEndPunctuationStyle.ForceHalfWidth,
        )
        // TextAutoSpaceLineEdgeTrim: the autospace replacement gap lives in
        // the Latin cluster's advance, not in punctuation glue, so the edge
        // trim above can't see it. A typed-space boundary gap landing on a
        // line edge must disappear like any other line-edge blank — without
        // this, justified lines stop one gap short of the right edge.
        val autoSpaceGap = clreqProfile.autoSpace.gapEm * fontSize
        val autoSpaceEdgeTrims = HashMap<Int, Float>()
        val autoSpaceEdgeDecisions = mutableListOf<LineEdgeTrimDecisionInfo>()
        lineSolution.lines.forEach { line ->
            fun trimEdge(clusterIdx: Int, side: String) {
                val decision = autoSpaceDecisions.firstOrNull {
                    it.clusterRange == naturalClusters[clusterIdx].range && it.side == side
                } ?: return
                autoSpaceEdgeTrims.merge(clusterIdx, autoSpaceGap) { a, b -> a + b }
                autoSpaceEdgeDecisions += LineEdgeTrimDecisionInfo(
                    lineRange = line.sourceRange,
                    clusterRange = decision.clusterRange,
                    side = side,
                    trimAmount = autoSpaceGap,
                    consumedBefore = 0f,
                    naturalGlue = autoSpaceGap,
                    reason = "TextAutoSpaceLineEdgeTrim",
                )
            }
            trimEdge(line.clusterRange.last, "trailing")
            trimEdge(line.clusterRange.first, "leading")

            // LineEdgeWordSpaceCollapse: a space-run cluster landing on a
            // line edge collapses entirely (CSS-like line-edge space
            // removal; also CLREQ — no sino-western gap at line edges).
            fun collapseEdgeSpace(clusterIdx: Int, side: String) {
                val cluster = naturalClusters[clusterIdx]
                if (!cluster.isSpaceRun()) return
                val advance = naturalClusters[clusterIdx].advance
                if (advance <= 0f) return
                autoSpaceEdgeTrims.merge(clusterIdx, advance) { a, b -> a + b }
                autoSpaceEdgeDecisions += LineEdgeTrimDecisionInfo(
                    lineRange = line.sourceRange,
                    clusterRange = cluster.range,
                    side = side,
                    trimAmount = advance,
                    consumedBefore = 0f,
                    naturalGlue = advance,
                    reason = "LineEdgeWordSpaceCollapse",
                )
            }
            collapseEdgeSpace(line.clusterRange.last, "trailing")
            collapseEdgeSpace(line.clusterRange.first, "leading")
        }
        val rawTrims = HashMap<Int, Float>(autoSpaceEdgeTrims)
        pushInRawTrims.forEach { (idx, amount) -> rawTrims.merge(idx, amount) { a, b -> a + b } }
        val trimmedGeometry = edgeTrimResult.geometry.withRawEdgeTrims(rawTrims)
        val trimmedClusters = trimmedGeometry.resolveClusters()
        val edgeTrimDecisions = edgeTrimResult.decisions + autoSpaceEdgeDecisions

        // AvoidStretchAroundConnectors（CLREQ 拉伸限制②）：连接号、分隔号
        // 与其前后字符之间避免拉伸。
        val avoidStretchClusters: Set<Int> = naturalClusters.indices.filterTo(mutableSetOf()) { idx ->
            when (atomClassByRange[naturalClusters[idx].range]) {
                PunctuationClass.Connector, PunctuationClass.Solidus -> true
                else -> false
            }
        }
        // LineEndHangingHyphen reserved width (ADR 0029 amend): a line that ends
        // mid-word at a hyphenation point gives the trailing hyphen real width
        // inside the measure — like a line-end punctuation mark, NOT hung by
        // default. The content therefore fills only `measure − hyphen`; when the
        // content can't be squeezed that far (over-long words with no room) the
        // hyphen falls past the edge (hangs) as a last resort, automatically.
        // CLREQ:「中文排版特别是书籍正文排版极少使用左齐右不齐，原则上
        // 应该进行两端对齐」— justification is the baseline, not an option:
        // every non-last line goes through the justify chain. The last line
        // is positioned by ParagraphStyle.lastLineAlignment instead.
        val justificationPlans: List<JustificationPlan?> = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val isLast = lineIndex == lineSolution.lines.lastIndex
            if (isLast) {
                null
            } else {
                // A hung mark sits beyond the measure: justify fills the
                // CONTENT (range minus the hanging mark) to maxWidth.
                val justifyRange = if (lineCandidate.hangingClusterIndex != null) {
                    lineCandidate.clusterRange.first until lineCandidate.clusterRange.last
                } else {
                    lineCandidate.clusterRange
                }
                justifier.justify(
                    adjustedClusters = trimmedClusters,
                    clusterRoles = clusterRoles,
                    lineClusterRange = justifyRange,
                    maxWidth = (if (lineCandidate.clusterRange.first == 0) {
                        measure - firstLineIndent
                    } else {
                        measure - blockIndent
                    }) - lineHyphenAdvanceAt(lineIndex),
                    fontSize = fontSize,
                    skip = false,
                    allowSinoWesternGapStretch = adjustmentStyle.allowSinoWesternGapAdjustment,
                    cjkLatinSpaceMaxEm = adjustmentStyle.sinoWesternStretchMaxEm,
                    avoidStretchClusters = avoidStretchClusters,
                )
            }
        }
        val justifyDeltaByCluster = HashMap<Int, Float>().apply {
            justificationPlans.filterNotNull()
                .flatMap { it.allocations }
                .forEach { alloc -> merge(alloc.targetClusterIndex, alloc.delta) { a, b -> a + b } }
        }
        val finalGeometry = trimmedGeometry.addJustificationDeltas(justifyDeltaByCluster)
        val finalClusters = finalGeometry.resolveClusters().map { c ->
            // 字身框 centre alignment: shift so this cluster's ideographic box centre meets
            // the base box centre (0 for base font/size — the common case).
            val m = metricDecisions.firstOrNull {
                c.range.start >= it.range.start && c.range.end <= it.range.end
            }?.layoutMetrics ?: return@map c
            val shift = (m.ascent - m.descent) / 2f - baseBoxHalf
            if (shift > -0.01f && shift < 0.01f) c else c.copy(baselineShift = shift)
        }
        val geometryDecisions = finalGeometry.toDecisionInfo()

        val glyphRuns = finalClusters.groupAdjacentBy { it.fontKey }.map { runClusters ->
            GlyphRun(
                range = TextRange(runClusters.first().range.start, runClusters.last().range.end),
                fontKey = runClusters.first().fontKey,
                glyphs = runClusters.flatMapIndexed { fallbackGlyphId, cluster ->
                    shapedGlyphsByClusterRange[cluster.range]
                        ?.mapToResolvedAdvance(cluster)
                        ?: listOf(
                            Glyph(
                                id = fallbackGlyphId.toUInt(),
                                clusterRange = cluster.range,
                                advance = cluster.advance,
                            ),
                        )
                },
                advance = runClusters.sumOf { it.advance.toDouble() }.toFloat(),
            )
        }

        // 行间注 band per line (ADR 0032): only the line(s) that carry 拼音 ruby reserve
        // the 注文 band; `rubyUniformBand` opts every line in (uniform spacing, taller
        // whole paragraph). 注音 (side ㄅㄆㄇ) never reserves line height. Tops accumulate
        // so a ruby line pushes the lines below it down, the rest stay put.
        val pinyinClusterRanges = pinyinSpans.mapNotNull { naturalClusters.clusterIndexRangeFor(it.baseRange) }
        val lineExtra = lineSolution.lines.map { lc ->
            val hasRuby = pinyinClusterRanges.any { it.first <= lc.clusterRange.last && it.last >= lc.clusterRange.first }
            if (rubyBand > 0f && (input.paragraphStyle.rubyUniformBand || hasRuby)) rubyBand else 0f
        }
        val lineTop = FloatArray(lineSolution.lines.size)
        run { var acc = 0f; for (i in lineExtra.indices) { lineTop[i] = acc; acc += baseLineMetrics.height + lineExtra[i] } }

        val lines = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            // LineEndHangingPunctuation: the hung mark is excluded from the
            // measure-fill width (adjustedWidth) but kept in visualWidth —
            // it overflows the measure (突出版心).
            val fillRange = if (lineCandidate.hangingClusterIndex != null) {
                lineCandidate.clusterRange.first until lineCandidate.clusterRange.last
            } else {
                lineCandidate.clusterRange
            }
            val adjustedWidth = fillRange
                .sumOf { trimmedClusters[it].advance.toDouble() }
                .toFloat()
            val visualWidth = lineCandidate.clusterRange
                .sumOf { finalClusters[it].advance.toDouble() }
                .toFloat()
            val baseIndent = if (lineCandidate.clusterRange.first == 0) firstLineIndent else blockIndent
            // LastLineAlignment: the last line is the paragraph's only
            // alignment degree of freedom (CLREQ 双齐 baseline). Center/End
            // express as an extra start-edge inset within the line's usable
            // measure — renderers and decoration geometry consume
            // LineBox.indent unchanged.
            val isLast = lineIndex == lineSolution.lines.lastIndex
            // LineEndHangingHyphen: this line ends mid-word when the NEXT line
            // begins at a hyphenation source offset (reserved in the justify
            // measure above; renderers draw it at indent + visualWidth).
            val lineHyphenAdvance = lineHyphenAdvanceAt(lineIndex)
            val limit = measure - baseIndent
            val alignmentInset = if (!isLast) {
                0f
            } else {
                when (input.paragraphStyle.lastLineAlignment) {
                    LastLineAlignment.Start -> 0f
                    LastLineAlignment.Center -> ((limit - visualWidth) / 2f).coerceAtLeast(0f)
                    LastLineAlignment.End -> (limit - visualWidth).coerceAtLeast(0f)
                }
            }
            LineBox(
                range = lineCandidate.sourceRange,
                baseline = lineTop[lineIndex] + lineExtra[lineIndex] + baseLineMetrics.baseline,
                top = lineTop[lineIndex],
                bottom = lineTop[lineIndex] + lineExtra[lineIndex] + baseLineMetrics.height,
                naturalWidth = lineCandidate.naturalWidth,
                adjustedWidth = adjustedWidth,
                visualWidth = visualWidth,
                // GridBodyAlignment: the whole body shifts by the container
                // slack offset; per-line indent (段首缩进 + 末行对齐) stacks on top.
                indent = gridBodyOffset + baseIndent + alignmentInset,
                hyphenAdvance = lineHyphenAdvance,
                debug = LineDebugInfo(
                    repair = lineCandidate.repair?.let { "${it::class.simpleName}:${it.reason}" },
                    notes = listOf(
                        "line:${lineIndex}:clusters=${lineCandidate.clusterRange.first}-${lineCandidate.clusterRange.last}",
                        "natural=${lineCandidate.naturalWidth},adjusted=${lineCandidate.adjustedWidth},visual=$visualWidth",
                    ),
                ),
            )
        }
        // Ink-edge insets so 行间线/着重号 hug the text, not the edge blanks: the leading
        // autospace gap + consumed 开标点 leading glue (mirrors the renderer's glyph
        // shift, SkiaTextBlobs.forEachPositionedCluster). The trailing justify stretch
        // is already excluded at use; the LEADING side was being missed (CLREQ「两侧」).
        val autoSpaceGapPx = 0.25f * fontSize
        val geometryByRange = geometryDecisions.associateBy { it.range }
        val leadingGapRanges = autoSpaceDecisions.filter { it.side == "leading" }.map { it.clusterRange }.toSet()
        val trailingGapRanges = autoSpaceDecisions.filter { it.side == "trailing" }.map { it.clusterRange }.toSet()
        val decorationDecisions = computeDecorationDecisions(
            decorations = input.decorations,
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            clusterRoles = clusterRoles,
            justifyDeltaByCluster = justifyDeltaByCluster,
            rubySpreadByCluster = rubyAndZhuyinSpread,
            fontSize = fontSize,
        )
        val decorationSegments = computeDecorationSegments(
            decorations = input.decorations,
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            justifyDeltaByCluster = justifyDeltaByCluster,
            geometryByRange = geometryByRange,
            leadingGapRanges = leadingGapRanges,
            trailingGapRanges = trailingGapRanges,
            autoSpaceGapPx = autoSpaceGapPx,
            fontSize = fontSize,
        )
        val rubyDecisions = computeRubyDecisions(
            rubySpans = pinyinSpans,
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            naturalClusters = naturalClusters,
            rubyBaselineDrop = rubyBaselineDrop,
            rubyFontSize = rubyFontSize,
            rubyFontWeight = rubyFontWeight,
        )
        val zhuyinDecisions = computeZhuyinDecisions(
            rubySpans = input.rubySpans.filter { it.kind == RubyKind.Zhuyin },
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            naturalClusters = naturalClusters,
            baseAscent = baseAscent,
            baseDescent = baseDescent,
            fontSize = fontSize,
            rubyFontWeight = rubyFontWeight,
        )

        val widestLine = lines.maxOfOrNull { it.indent + it.visualWidth + it.hyphenAdvance } ?: 0f
        val totalHeight = lines.lastOrNull()?.bottom ?: baseLineMetrics.height
        val resultWidth = widestLine.coerceAtMost(input.constraints.maxWidth)

        return LayoutResult(
            input = input,
            size = Size(
                width = resultWidth,
                height = totalHeight,
            ),
            clusters = finalClusters,
            glyphRuns = glyphRuns,
            lines = lines,
            debug = LayoutDebugInfo(
                fontDecisions = fontDecisions.map { decision ->
                    val clusterText = text.substring(decision.range.start, decision.range.end)
                    val substitution = punctuationGlyphSubstitutor.substitute(clusterText)
                    val rolledBack = substitutionRollbackRanges.any { it.isInside(decision.range) }
                    FontDecisionInfo(
                        range = decision.range,
                        sourceText = clusterText,
                        displayText = if (rolledBack) clusterText else substitution.displayText,
                        role = decision.role.name,
                        fontKey = decision.candidate.key,
                        reason = decision.reason,
                        substitutionReason = if (rolledBack) {
                            "${substitution.reason}:SubstitutionRollbackOnMissingGlyph"
                        } else {
                            substitution.reason
                        },
                    )
                },
                shapingDecisions = shapingDecisions,
                metricDecisions = metricDecisions.map { decision ->
                    MetricDecisionInfo(
                        range = decision.range,
                        sourceText = decision.sourceText,
                        role = decision.request.role.name,
                        fontKey = decision.request.fontKey,
                        rawAscent = decision.rawMetrics.ascent,
                        rawDescent = decision.rawMetrics.descent,
                        rawLeading = decision.rawMetrics.leading,
                        rawSource = decision.rawMetrics.source.name,
                        layoutAscent = decision.layoutMetrics.ascent,
                        layoutDescent = decision.layoutMetrics.descent,
                        baselineClass = decision.layoutMetrics.baselineClass.name,
                        metricBox = decision.layoutMetrics.metricBox.name,
                        layoutSource = decision.layoutMetrics.source.name,
                        reason = decision.layoutMetrics.reason,
                    )
                },
                punctuationDecisions = punctuationAtoms.map { atom ->
                    PunctuationDecisionInfo(
                        range = atom.range,
                        char = atom.char,
                        punctuationClass = atom.punctuationClass.name,
                        advance = atom.advance,
                        bodyWidth = atom.bodyWidth,
                        leadingGlueNatural = atom.leadingGlue.natural,
                        trailingGlueNatural = atom.trailingGlue.natural,
                        anchor = atom.anchor.name,
                        inkBounds = atom.inkBounds,
                        geometrySource = atom.geometrySource,
                        policyBodyFloor = atom.policyBodyFloor,
                        inkWidth = atom.inkWidth,
                        inkCenter = atom.inkCenter,
                        inkBoundsFallback = atom.inkBoundsFallback,
                        haltAdvance = atom.haltAdvance,
                        haltValidation = atom.haltValidation,
                    )
                },
                geometryDecisions = geometryDecisions,
                spacingDecisions = spacingPlan.adjustments.map { adjustment ->
                    SpacingDecisionInfo(
                        range = adjustment.range,
                        leftChar = adjustment.leftChar,
                        rightChar = adjustment.rightChar,
                        naturalInnerGlue = adjustment.naturalInnerGlue,
                        adjustedInnerGlue = adjustment.adjustedInnerGlue,
                        reduction = adjustment.reduction,
                        reductionTargetRange = adjustment.reductionTargetRange,
                        reason = adjustment.reason,
                    )
                },
                roleOverrides = roleOverrideInfos,
                lineDecisions = lines.zip(lineSolution.lines).mapIndexed { lineIndex, (line, candidate) ->
                    LineDecisionInfo(
                        range = line.range,
                        kind = lineBreaker.strategyName,
                        repair = candidate.repair?.let { "${it::class.simpleName}" },
                        repairPenalty = candidate.repair?.penalty ?: 0,
                        repairDecision = candidate.repair?.toDecisionInfo(clusters),
                        repairCandidates = candidate.repairCandidates.map { it.toDecisionInfo(clusters) },
                        notes = listOf(
                            "index:$lineIndex",
                            "natural:${line.naturalWidth}",
                            "adjusted:${line.adjustedWidth}",
                            "visual:${line.visualWidth}",
                        ) + listOfNotNull(candidate.repair?.let { "repair-reason:${it.reason}" }),
                    )
                },
                justificationDecisions = justificationPlans.zip(lineSolution.lines)
                    .mapNotNull { (plan, candidate) ->
                        plan
                            ?.takeIf { it.allocations.isNotEmpty() || it.deficitBefore > 0f }
                            ?.let {
                                JustificationDecisionInfo(
                                    lineRange = candidate.sourceRange,
                                    deficitBefore = it.deficitBefore,
                                    deficitAfter = it.unfilledDeficit,
                                    allocations = it.allocations.map { alloc ->
                                        JustificationAllocationInfo(
                                            clusterRange = clusters[alloc.targetClusterIndex].range,
                                            kind = alloc.kind.name,
                                            priority = alloc.priority,
                                            delta = alloc.delta,
                                            reason = alloc.reason,
                                        )
                                    },
                                )
                            }
                    },
                autoSpaceDecisions = autoSpaceDecisions,
                lineEdgeTrimDecisions = edgeTrimDecisions,
                decorationDecisions = decorationDecisions,
                decorationSegments = decorationSegments,
                rubyDecisions = rubyDecisions,
                zhuyinDecisions = zhuyinDecisions,
                lineSpacingDecision = lineSpacingDecision,
                kinsokuDecision = kinsokuDecision,
                lineLengthGridDecision = lineLengthGridDecision,
                firstLineIndentDecision = firstLineIndentDecision,
            ),
        )
    }

    /**
     * Named heuristic: `EmphasisDotOnHanText` (ADR 0018, CLREQ 着重号).
     *
     * Resolves decoration spans into per-cluster dot anchors AFTER all
     * geometry is final — decorations never feed back into metrics, breaks
     * or justification. Per CLREQ, only Han text carries a dot: punctuation
     * inside the span is skipped (`clreq-no-dot-on-punctuation`), and
     * non-Han clusters are skipped (`no-dot-on-non-han`; western emphasis is
     * italics instead — `BilingualEmphasisWesternItalic`, applied at shaping).
     *
     * Anchor = the point the dot INK CENTRE must land on: x is the glyph
     * centre (final position minus the trailing justification delta), y is
     * `baseline + EMPHASIS_DOT_CENTER_EM·em`. The drop is baseline-relative,
     * NOT descent-relative: real Han ink ends ≈0.12em below the baseline (the
     * font-declared typo descent, ADR 0002 amendment), so anchoring the dot to
     * the box bottom would land it inside the NEXT line's ink. 0.45em keeps
     * clear daylight under the character face (字身底 baseline+0.12em; ≈2px
     * clearance at 16px) and clears the next line even at lineHeight 1.0. Renderers
     * measure their dot glyph's ink and align its centre here, so font
     * differences stay in the render layer.
     */
    private fun computeDecorationDecisions(
        decorations: List<DecorationSpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        justifyDeltaByCluster: Map<Int, Float>,
        rubySpreadByCluster: Map<Int, Float>,
        fontSize: Float,
    ): List<DecorationDecisionInfo> {
        if (decorations.isEmpty()) return emptyList()

        val decisions = mutableListOf<DecorationDecisionInfo>()
        for (span in decorations) {
            if (span.kind != DecorationKind.Emphasis) continue
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    val coveredBySpan = cluster.range.start >= span.range.start &&
                        cluster.range.end <= span.range.end
                    if (coveredBySpan) {
                        val role = clusterRoles[idx]
                        val applied = role == FontRole.CjkText
                        // Centre on the base BODY: drop the trailing justify stretch AND
                        // the 注音 column reservation (着重号 belongs under 基文, not 基文+注音).
                        val glyphAdvance = cluster.advance -
                            (justifyDeltaByCluster[idx] ?: 0f) - (rubySpreadByCluster[idx] ?: 0f)
                        decisions += DecorationDecisionInfo(
                            clusterRange = cluster.range,
                            sourceText = cluster.text,
                            kind = span.kind.name,
                            applied = applied,
                            reason = when {
                                applied -> "EmphasisDotOnHanText"
                                role == FontRole.CjkPunctuation -> "clreq-no-dot-on-punctuation"
                                else -> "no-dot-on-non-han"
                            },
                            anchorX = x + glyphAdvance / 2f,
                            anchorY = lineBoxes[lineIndex].baseline + fontSize * EMPHASIS_DOT_CENTER_EM,
                            dotDiameter = if (applied) fontSize * EMPHASIS_DOT_DIAMETER_EM else 0f,
                        )
                    }
                    x += cluster.advance
                }
            }
        }
        return decisions
    }

    /**
     * 示亡号 frame geometry (ADR 0018). One rectangle per line the span
     * touches. Vertical bounds are the conventional CJK CHARACTER FACE
     * (字面): `baseline - 0.88em .. baseline + 0.12em`, hugging the face
     * with NO margin. Neither layout em box (artificial 0.5/0.5 split that
     * real ink overflows), nor raw line metrics (include inter-line air),
     * nor per-glyph ink (varies with glyph shape — `一` would collapse the
     * frame and break uniformity across a name list) describe the face;
     * the 0.88/0.12 split encodes the standard CJK design box. Replacing
     * it with font-reported ideographic metrics (BASE table) is follow-up.
     * `openStart`/`openEnd` mark continuation edges when the span had to
     * split across lines (only when wider than the measure —
     * `MourningSpanKeptUnbroken` otherwise prevents the split at break
     * time).
     */
    private fun computeDecorationSegments(
        decorations: List<DecorationSpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        justifyDeltaByCluster: Map<Int, Float>,
        geometryByRange: Map<TextRange, ClusterGeometryDecisionInfo>,
        leadingGapRanges: Set<TextRange>,
        trailingGapRanges: Set<TextRange>,
        autoSpaceGapPx: Float,
        fontSize: Float,
    ): List<DecorationSegmentInfo> {
        // Remaining edge blank to strip off a covered cluster so 行间线 hugs the ink/body
        // (CLREQ 避两侧空白): the autospace gap + the punctuation glue still present
        // (开/闭标点 half-width), mirroring how the renderer positions the glyph.
        fun leadingBlank(range: TextRange, atLineStart: Boolean): Float {
            val g = geometryByRange[range]
            val glue = if (g != null) g.leadingGlueNatural - g.leadingGlueConsumed else 0f
            val auto = if (range in leadingGapRanges && !atLineStart) autoSpaceGapPx else 0f
            return glue + auto
        }
        fun trailingBlank(range: TextRange, atLineEnd: Boolean): Float {
            val g = geometryByRange[range]
            val glue = if (g != null) g.trailingGlueNatural - g.trailingGlueConsumed else 0f
            val auto = if (range in trailingGapRanges && !atLineEnd) autoSpaceGapPx else 0f
            return glue + auto
        }
        val boxSpans = decorations.filter {
            it.kind == DecorationKind.Mourning ||
                it.kind == DecorationKind.ProperNoun ||
                it.kind == DecorationKind.BookTitle
        }
        if (boxSpans.isEmpty()) return emptyList()

        val segments = mutableListOf<DecorationSegmentInfo>()
        for (span in boxSpans) {
            val spanSegments = mutableListOf<DecorationSegmentInfo>()
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                var left: Float? = null
                var right = 0f
                var segStart = -1
                var segEnd = -1
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    val covered = cluster.range.start >= span.range.start &&
                        cluster.range.end <= span.range.end
                    if (covered) {
                        if (left == null) {
                            // Start at the first covered cluster's ink/body left: skip the
                            // leading blank (autospace + 开标点 glue), CLREQ 避两侧空白.
                            left = x + leadingBlank(cluster.range, idx == clusterRange.first)
                            segStart = cluster.range.start
                        }
                        // End at the last covered cluster's ink/body right: drop the
                        // trailing justify stretch AND the trailing blank (autospace +
                        // 闭标点 glue) — 长度与文字外框一致, both sides.
                        right = x + cluster.advance - (justifyDeltaByCluster[idx] ?: 0f) -
                            trailingBlank(cluster.range, idx == clusterRange.last)
                        segEnd = cluster.range.end
                    }
                    x += cluster.advance
                }
                val leftEdge = left ?: return@forEachIndexed
                val baseline = lineBoxes[lineIndex].baseline
                val isLine = span.kind != DecorationKind.Mourning
                // 行间线贴字：face bottom (+0.12em) plus a hairline of air;
                // 先线后点 holds because the emphasis dot ink starts at
                // +0.34em, below the line.
                val lineY = baseline + fontSize * INTERLINEAR_LINE_Y_EM
                spanSegments += DecorationSegmentInfo(
                    sourceRange = TextRange(segStart, segEnd),
                    kind = span.kind.name,
                    lineIndex = lineIndex,
                    left = leftEdge,
                    top = if (isLine) lineY else baseline - fontSize * MOURNING_FRAME_FACE_ASCENT_EM,
                    right = right,
                    bottom = if (isLine) lineY else baseline + fontSize * MOURNING_FRAME_FACE_DESCENT_EM,
                    openStart = segStart > span.range.start,
                    openEnd = segEnd < span.range.end,
                    reason = "",
                )
            }
            val reason = when {
                span.kind == DecorationKind.Mourning && spanSegments.size <= 1 -> "MourningSpanKeptUnbroken"
                span.kind == DecorationKind.Mourning -> "mourning-span-split-across-lines"
                else -> "InterlinearLinePerAnnotatedItem"
            }
            segments += spanSegments.map { it.copy(reason = reason) }
        }
        return shortenAdjacentInterlinearLines(segments, fontSize)
    }

    /**
     * `AdjacentInterlinearLineShortening` (CLREQ 行间标点通则): adjacent
     * 专名号/书名号 marks shorten their ADJACENT sides only, so two
     * annotated items read as two — the outer sides keep the text's outer
     * frame. Each adjacent edge pulls back 1/16 em (the visible gap is
     * 1/8 em, within the ≤1/8 em-per-side cap).
     */
    private fun shortenAdjacentInterlinearLines(
        segments: List<DecorationSegmentInfo>,
        fontSize: Float,
    ): List<DecorationSegmentInfo> {
        val lineKinds = setOf(DecorationKind.ProperNoun.name, DecorationKind.BookTitle.name)
        val result = segments.toMutableList()
        val byLine = result.withIndex()
            .filter { it.value.kind in lineKinds }
            .groupBy { it.value.lineIndex }
        for ((_, entries) in byLine) {
            val ordered = entries.sortedBy { it.value.left }
            for (i in 0 until ordered.size - 1) {
                val a = ordered[i]
                val b = ordered[i + 1]
                if (b.value.left - a.value.right > ADJACENT_LINE_EPSILON * fontSize) continue
                val pullback = fontSize * ADJACENT_LINE_SHORTEN_EM
                result[a.index] = result[a.index].copy(
                    right = result[a.index].right - pullback,
                    reason = result[a.index].reason + ";AdjacentInterlinearLineShortening",
                )
                result[b.index] = result[b.index].copy(
                    left = result[b.index].left + pullback,
                    reason = result[b.index].reason + ";AdjacentInterlinearLineShortening",
                )
            }
        }
        return result
    }

    private fun Map<Int, FontRole>.toRoleOverrideInfos(
        text: String,
        baseClassifier: FontRoleClassifier,
        context: FontRoleContext,
        source: String,
        reason: String,
    ): List<RoleOverrideInfo> =
        entries
            .sortedBy { it.key }
            .map { (index, overriddenRole) ->
                val sourceText = text.substring(index, (index + 1).coerceAtMost(text.length))
                val originalRole = baseClassifier
                    .classify(text, TextRange(index, index + 1), context)
                RoleOverrideInfo(
                    range = TextRange(index, index + 1),
                    sourceText = sourceText,
                    originalRole = originalRole.name,
                    overriddenRole = overriddenRole.name,
                    source = source,
                    reason = reason,
                )
            }

    private fun clusterRanges(
        text: String,
        classifier: FontRoleClassifier,
        context: FontRoleContext,
        profile: ClreqProfile,
        spanBoundaries: Set<Int> = emptySet(),
    ): List<TextRange> {
        val coalesceSet = profile.coalesceRepeatablePunctuation
        val ranges = mutableListOf<TextRange>()
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAtCompat(index)
            val charCount = codePoint.charCount()
            val start = index
            val firstRange = TextRange(start, start + charCount)
            val role = classifier.classify(text, firstRange, context)

            index += charCount
            if (role == FontRole.LatinText) {
                // A sized-span edge inside a Latin run / coalesced 标点 run ends the
                // cluster there so each cluster carries a single font size (ADR 0030).
                while (index < text.length && index !in spanBoundaries) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    val nextCharCount = nextCodePoint.charCount()
                    val nextRange = TextRange(index, index + nextCharCount)
                    if (classifier.classify(text, nextRange, context) != FontRole.LatinText) break
                    index += nextCharCount
                }
            } else if (role == FontRole.CjkPunctuation && codePoint in coalesceSet) {
                while (index < text.length && index !in spanBoundaries) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    if (nextCodePoint != codePoint) break
                    index += nextCodePoint.charCount()
                }
            }

            ranges.add(TextRange(start, index))
        }
        return ranges
    }

    private fun String.codePointAtCompat(index: Int): Int {
        val high = this[index].code
        if (high !in 0xD800..0xDBFF || index + 1 >= length) return high

        val low = this[index + 1].code
        if (low !in 0xDC00..0xDFFF) return high

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun Int.charCount(): Int =
        if (this > 0xFFFF) 2 else 1

    private fun Cluster.punctuationAtoms(
        em: Float,
        builder: PunctuationAtomBuilder,
        shapedGlyphs: List<Glyph>,
        gluePlacement: PunctuationGluePlacement,
        widthPolicy: ink.duo3.tiqian.clreq.PunctuationWidthPolicy,
    ): List<PunctuationAtom> {
        if (displayText.isEmpty()) return emptyList()

        return displayText.mapIndexedNotNull { index, char ->
            builder.build(
                char = char,
                range = displayCharSourceRange(index),
                em = em,
                inkInput = punctuationInkInputFor(index, shapedGlyphs),
                gluePlacement = gluePlacement,
                widthPolicy = widthPolicy,
            )
        }
    }

    /**
     * Named heuristic: `MissingInkBoundsFallback` (recording side).
     *
     * Returns null only when no shaping information exists at all — the
     * expected pure-policy path. When shaping ran but ink cannot be
     * attributed, this returns a [PunctuationInkInput] carrying a
     * `boundsFallbackReason` so the punctuation decision records *why*
     * geometry degraded instead of silently looking like the policy path.
     */
    private fun Cluster.punctuationInkInputFor(displayIndex: Int, shapedGlyphs: List<Glyph>): PunctuationInkInput? {
        if (shapedGlyphs.isEmpty()) return null
        val glyph = when {
            shapedGlyphs.size == displayText.length -> shapedGlyphs.getOrNull(displayIndex)
            displayText.length == 1 -> shapedGlyphs.unionAsSingleGlyph()
            else -> null
        } ?: return PunctuationInkInput(
            // Glyph count does not line up with display characters, so per-
            // character advance/ink cannot be attributed. Advance 0 keeps the
            // builder on the policy advance; only the reason is recorded.
            advance = 0f,
            inkBounds = null,
            boundsFallbackReason = "glyph-cluster-mapping-ambiguous",
        )
        return PunctuationInkInput(
            advance = glyph.advance,
            inkBounds = glyph.bounds,
            boundsFallbackReason = if (glyph.bounds == null) "shaper-no-ink-bounds" else null,
            haltAdvance = glyph.haltAdvance,
            haltPlacementX = glyph.haltPlacementX,
        )
    }

    private fun List<Glyph>.unionAsSingleGlyph(): Glyph? {
        if (isEmpty()) return null
        val first = first()
        val bounds = mapNotNull { it.bounds }
        if (bounds.isEmpty()) return first
        return first.copy(
            advance = sumOf { it.advance.toDouble() }.toFloat(),
            // halt metrics are per-glyph; a union pseudo-glyph has none.
            haltAdvance = null,
            haltPlacementX = null,
            bounds = Rect(
                left = bounds.minOf { it.left.toDouble() }.toFloat(),
                top = bounds.minOf { it.top.toDouble() }.toFloat(),
                right = bounds.maxOf { it.right.toDouble() }.toFloat(),
                bottom = bounds.maxOf { it.bottom.toDouble() }.toFloat(),
            ),
        )
    }

    private fun Cluster.displayCharSourceRange(displayIndex: Int): TextRange =
        if (displayText.length == text.length) {
            TextRange(
                start = range.start + displayIndex,
                end = range.start + displayIndex + 1,
            )
        } else {
            range
        }

    /**
     * Named heuristic: `LatinWordSegmentation`. A LatinText font decision is
     * shaped per alternating word / space-run segment; every other role
     * shapes as one segment. Spaces become standalone clusters: break
     * opportunities, sino-western gaps (when CJK-adjacent) or stretchable
     * word spaces (when between two Latin words).
     */
    private fun FontDecision.shapingSegments(text: String): List<TextRange> {
        if (role != FontRole.LatinText) return listOf(range)
        val segments = mutableListOf<TextRange>()
        var segStart = range.start
        var inSpace = text[range.start] == ' '
        for (i in (range.start + 1) until range.end) {
            val isSpace = text[i] == ' '
            if (isSpace != inSpace) {
                segments += TextRange(segStart, i)
                segStart = i
                inSpace = isSpace
            }
        }
        segments += TextRange(segStart, range.end)
        return segments
    }

    private fun Cluster.isSpaceRun(): Boolean =
        text.isNotEmpty() && text.all { it == ' ' }

    private fun TextRange.isInside(other: TextRange): Boolean =
        start >= other.start && end <= other.end

    private fun List<Cluster>.requireCoveredBy(fontDecisions: List<FontDecision>) {
        fontDecisions.forEach { decision ->
            val coveringClusters = filter { cluster -> cluster.range.isInside(decision.range) }
                .sortedBy { it.range.start }
            var cursor = decision.range.start
            for (cluster in coveringClusters) {
                require(cluster.range.start == cursor) {
                    "TextShaper returned non-contiguous clusters for ${decision.range}: $coveringClusters"
                }
                cursor = cluster.range.end
            }
            require(cursor == decision.range.end) {
                "TextShaper must return clusters covering ${decision.range}; coveredUntil=$cursor"
            }
        }
    }

    private fun List<Glyph>.mapToResolvedAdvance(cluster: Cluster): List<Glyph> {
        val sourceAdvance = sumOf { it.advance.toDouble() }.toFloat()
        if (sourceAdvance <= 0f) {
            val fallbackAdvance = cluster.advance / size.coerceAtLeast(1)
            return map { it.copy(advance = fallbackAdvance, clusterRange = cluster.range) }
        }

        val scale = cluster.advance / sourceAdvance
        return map { glyph ->
            glyph.copy(
                clusterRange = cluster.range,
                advance = glyph.advance * scale,
            )
        }
    }

    /**
     * Applies `AutoSpacePolicy` to (word-segmented) natural clusters.
     *
     * Post `LatinWordSegmentation`, U+0020 runs are standalone clusters and
     * the model is per-cluster (CSS Text 4 + ADR 0009; CLREQ:「原则上，汉字
     * 与西文字母、数字间使用不多于四分之一个汉字宽的字距或空白」):
     *
     * - **space-run cluster with a CjkText neighbour** — the cluster IS the
     *   sino-western gap: its advance normalises to `gapEm`
     *   (`TextAutoSpaceReplace`, decision side="gap"; renderers need no
     *   offsets, the cluster width is the gap).
     * - **space-run cluster between two Latin words** — a word space
     *   (CLREQ 西文词距): untouched here; justification stretches it.
     * - **word cluster directly adjacent to CjkText** (no space cluster in
     *   between) — `TextAutoSpaceInsert`: the gap is added into the word
     *   cluster's advance on that side; renderers offset glyphs by the
     *   recorded side decision. Only under [AutoSpaceMode.Insert];
     *   [AutoSpaceMode.Replace] keeps the conservative behaviour.
     *
     * Punctuation neighbours never produce a gap (their spacing is the
     * punctuation glue model's job).
     */
    private fun List<Cluster>.applyAutoSpacePolicy(
        fontDecisions: List<FontDecision>,
        policy: AutoSpacePolicy,
        fontSize: Float,
    ): AutoSpaceApplicationResult {
        if (isEmpty()) return AutoSpaceApplicationResult(emptyList(), emptyList())

        val roles = map { cluster -> fontDecisions.firstOrNull { cluster.range.isInside(it.range) }?.role }
        val decisions = mutableListOf<AutoSpaceDecisionInfo>()
        val gap = policy.gapEm * fontSize
        // CLREQ distinguishes 字母 from 数字: the mode is chosen by the
        // BOUNDARY-adjacent western character (`cjkDigit` for a digit,
        // `cjkLatin` for a letter). Default they are identical (both Insert).
        fun modeForWestern(boundaryChar: Char?): AutoSpaceMode =
            if (boundaryChar != null && boundaryChar.isDigit()) policy.cjkDigit else policy.cjkLatin

        val updated = mapIndexed { idx, cluster ->
            if (roles[idx] != FontRole.LatinText) return@mapIndexed cluster
            val prevRole = if (idx > 0) roles[idx - 1] else null
            val nextRole = if (idx < lastIndex) roles[idx + 1] else null

            if (cluster.isSpaceRun()) {
                val cjkAdjacent = prevRole == FontRole.CjkText || nextRole == FontRole.CjkText
                if (!cjkAdjacent) return@mapIndexed cluster
                // The western token sits on the non-CJK side of the space; its
                // boundary char (nearest the space) selects digit vs letter.
                val westernChar = when {
                    prevRole == FontRole.CjkText -> getOrNull(idx + 1)?.text?.firstOrNull()
                    else -> getOrNull(idx - 1)?.text?.lastOrNull()
                }
                if (modeForWestern(westernChar) == AutoSpaceMode.Disabled) return@mapIndexed cluster
                val reduction = cluster.advance - gap
                if (reduction == 0f) return@mapIndexed cluster
                decisions += AutoSpaceDecisionInfo(
                    clusterRange = cluster.range,
                    side = "gap",
                    boundaryRole = FontRole.CjkText.name,
                    mode = AutoSpaceMode.Replace.name,
                    charactersAffected = cluster.text.length,
                    reductionPerChar = reduction / cluster.text.length,
                    totalReduction = reduction,
                    reason = "TextAutoSpaceReplace:space-cluster-to-gap",
                )
                cluster.copy(advance = gap)
            } else {
                var added = 0f
                // Each side keys on the cluster's own boundary char.
                if (prevRole == FontRole.CjkText &&
                    modeForWestern(cluster.text.firstOrNull()) == AutoSpaceMode.Insert
                ) {
                    added += gap
                    decisions += AutoSpaceDecisionInfo(
                        clusterRange = cluster.range,
                        side = "leading",
                        boundaryRole = FontRole.CjkText.name,
                        mode = AutoSpaceMode.Insert.name,
                        charactersAffected = 0,
                        reductionPerChar = 0f,
                        totalReduction = -gap,
                        reason = "TextAutoSpaceInsert:ideograph-alpha:quarter-em",
                    )
                }
                if (nextRole == FontRole.CjkText &&
                    modeForWestern(cluster.text.lastOrNull()) == AutoSpaceMode.Insert
                ) {
                    added += gap
                    decisions += AutoSpaceDecisionInfo(
                        clusterRange = cluster.range,
                        side = "trailing",
                        boundaryRole = FontRole.CjkText.name,
                        mode = AutoSpaceMode.Insert.name,
                        charactersAffected = 0,
                        reductionPerChar = 0f,
                        totalReduction = -gap,
                        reason = "TextAutoSpaceInsert:ideograph-alpha:quarter-em",
                    )
                }
                if (added == 0f) cluster else cluster.copy(advance = cluster.advance + added)
            }
        }
        return AutoSpaceApplicationResult(updated, decisions)
    }

    private fun RepairCandidate.toDecisionInfo(clusters: List<Cluster>): LineRepairCandidateInfo =
        LineRepairCandidateInfo(
            kind = kind,
            reasonCode = reasonCode,
            offenderRange = clusters[offenderClusterIndex].range,
            penalty = penalty,
            accepted = accepted,
            rejectionReason = rejectionReason,
            targetClusterIndex = targetClusterIndex,
            carriedClusterIndex = carriedClusterIndex,
            shrink = shrink,
            requiredShrink = requiredShrink,
            availableCapacity = availableCapacity,
        )

    private fun RepairOption.toDecisionInfo(clusters: List<Cluster>): LineRepairDecisionInfo =
        when (this) {
            is RepairOption.PushIn -> LineRepairDecisionInfo(
                // 避头尾 PushIn vs LineAdjustmentPushIn (ADR 0031) — the real
                // trigger lives in `reason`; don't hardcode it away.
                kind = "PushIn",
                reasonCode = reason.substringBefore(':'),
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
                targetClusterIndex = offenderClusterIndex,
                shrink = totalShrink,
                availableCapacity = totalAvailableCapacity,
                pushInAllocations = allocations.map { alloc ->
                    LineRepairAllocationInfo(
                        clusterRange = clusters[alloc.clusterIndex].range,
                        shrink = alloc.shrink,
                        availableCapacity = alloc.availableCapacity,
                    )
                },
            )

            is RepairOption.CarryPrevious -> LineRepairDecisionInfo(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
                carriedClusterIndex = carriedClusterIndex,
            )

            is RepairOption.LeaveRagged -> LineRepairDecisionInfo(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
            )

            is RepairOption.Hang -> LineRepairDecisionInfo(
                kind = "Hang",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
            )

            is RepairOption.CarryNext -> LineRepairDecisionInfo(
                kind = "CarryNext",
                reasonCode = "ForbiddenAtLineEnd",
                offenderRange = clusters[movedClusterIndex].range,
                penalty = penalty,
                carriedClusterIndex = movedClusterIndex,
            )
        }

    /**
     * 行间注 geometry (ruby, ADR 0032): centre each注文 over the x-span of its
     * base clusters on the line they land. `advance` is untouched (注文 overhangs
     * if wider — diagnostic [RubyDecisionInfo.overhang]); the renderer measures
     * the real注文 width and centres on [RubyDecisionInfo.centerX]. A base split
     * across lines yields one decision per line (each over its on-line fragment).
     */
    private fun computeRubyDecisions(
        rubySpans: List<RubySpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        naturalClusters: List<Cluster>,
        rubyBaselineDrop: Float,
        rubyFontSize: Float,
        rubyFontWeight: Int,
    ): List<RubyDecisionInfo> {
        if (rubySpans.isEmpty()) return emptyList()
        val out = mutableListOf<RubyDecisionInfo>()
        for (ruby in rubySpans) {
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                var baseLeft = Float.NaN
                var contentWidth = 0f
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    if (cluster.range.start >= ruby.baseRange.start && cluster.range.end <= ruby.baseRange.end) {
                        if (baseLeft.isNaN()) baseLeft = x
                        // Centre on the base CONTENT (natural width), NOT the 避让-widened
                        // slot — the spread is trailing space the注文 must not centre over.
                        contentWidth += naturalClusters[idx].advance
                    }
                    x += cluster.advance
                }
                if (!baseLeft.isNaN()) {
                    val estRubyWidth = ruby.text.length * rubyFontSize * 0.5f // diagnostic only
                    out += RubyDecisionInfo(
                        baseRange = ruby.baseRange,
                        text = ruby.text,
                        lineIndex = lineIndex,
                        centerX = baseLeft + contentWidth / 2f,
                        baselineY = lineBoxes[lineIndex].baseline - rubyBaselineDrop,
                        fontSize = rubyFontSize,
                        overhang = ((estRubyWidth - contentWidth) / 2f).coerceAtLeast(0f),
                        fontFamilies = ruby.fontFamilies,
                        fontWeight = rubyFontWeight,
                    )
                }
            }
        }
        return out
    }

    /**
     * 注音 geometry (ADR 0033): for each Zhuyin span, lay the ㄅㄆㄇ symbols (9×9 份)
     * and the 调号 (5×5 份 / 轻声) in the base's right-side 15-份 zone, mapping the
     * 30-份 grid onto the base 字身框 (typo box). `ZhuyinParser` derives the tone.
     */
    private fun computeZhuyinDecisions(
        rubySpans: List<RubySpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        naturalClusters: List<Cluster>,
        baseAscent: Float,
        baseDescent: Float,
        fontSize: Float,
        rubyFontWeight: Int,
    ): List<ZhuyinDecisionInfo> {
        if (rubySpans.isEmpty()) return emptyList()
        val hUnit = fontSize / 30f
        val vUnit = (baseAscent + baseDescent) / 30f
        val out = mutableListOf<ZhuyinDecisionInfo>()
        for (ruby in rubySpans) {
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                var contentLeft = Float.NaN
                var contentWidth = 0f
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    if (cluster.range.start >= ruby.baseRange.start && cluster.range.end <= ruby.baseRange.end) {
                        if (contentLeft.isNaN()) contentLeft = x
                        contentWidth += naturalClusters[idx].advance
                    }
                    x += cluster.advance
                }
                if (contentLeft.isNaN()) return@forEachIndexed
                val zoneLeft = contentLeft + contentWidth // 注音 zone = right of base content
                val boxTop = lineBoxes[lineIndex].baseline - baseAscent
                val parsed = ZhuyinParser.parse(ruby.text)
                val n = parsed.symbols.size.coerceIn(1, 3)
                val neutral = parsed.tone == ZhuyinTone.Neutral
                fun box(leftU: Float, widthU: Float, topU: Int, botU: Int, role: ZhuyinGlyphRole, text: String) =
                    ZhuyinGlyphPlacement(
                        text = text,
                        left = zoneLeft + leftU * hUnit,
                        top = boxTop + topU * vUnit,
                        width = widthU * hUnit,
                        height = (botU - topU) * vUnit,
                        role = role,
                    )
                val placements = buildList {
                    // ㄅㄆㄇ symbols: 9-份 column at [1,10]份.
                    val rows = zhuyinSymbolRows(n, neutral)
                    parsed.symbols.take(3).forEachIndexed { i, sym ->
                        val (topU, botU) = rows[i]
                        add(box(1f, 9f, topU, botU, ZhuyinGlyphRole.Symbol, sym))
                    }
                    when (parsed.tone) {
                        // 轻声: full-width vert-alt drawn at the 9-份 column size; the box
                        // is the DOT's target rect (column-wide × the 2-份 neutral row) —
                        // the renderer h-centres + ink-positions the dot into it.
                        ZhuyinTone.Neutral -> {
                            val (topU, botU) = zhuyinNeutralRow(n)
                            add(box(1f, 9f, topU, botU, ZhuyinGlyphRole.Neutral, "˙"))
                        }
                        // 平上去: 5×5 in the 调号 column [10,15]份, upper-right.
                        ZhuyinTone.Yangping, ZhuyinTone.Shang, ZhuyinTone.Qu -> {
                            val (topU, botU) = zhuyinRegularToneRow(n)
                            add(box(10f, 5f, topU, botU, ZhuyinGlyphRole.Tone, zhuyinToneGlyph(parsed.tone)))
                        }
                        // 入声: 5×5 lower-right (parser does not emit it in v1).
                        ZhuyinTone.Ru -> {
                            val (topU, botU) = zhuyinRuToneRow(n)
                            add(box(10f, 5f, topU, botU, ZhuyinGlyphRole.Tone, zhuyinToneGlyph(parsed.tone)))
                        }
                        ZhuyinTone.Yinping -> Unit // no mark
                    }
                }
                if (placements.isNotEmpty()) {
                    out += ZhuyinDecisionInfo(ruby.baseRange, lineIndex, placements, ruby.fontFamilies, rubyFontWeight)
                }
            }
        }
        return out
    }

    /** ㄅㄆㄇ vertical rows [顶,底]份 by symbol count (ADR 0033 表), with/without 轻声. */
    private fun zhuyinSymbolRows(n: Int, neutral: Boolean): List<Pair<Int, Int>> = when {
        n <= 1 -> listOf(11 to 20)
        n == 2 -> listOf(6 to 15, 17 to 26)
        else -> if (neutral) listOf(3 to 12, 12 to 21, 21 to 30) else listOf(2 to 11, 11 to 20, 20 to 29)
    }

    private fun zhuyinNeutralRow(n: Int): Pair<Int, Int> = when (n) {
        1 -> 8 to 10
        2 -> 3 to 5
        else -> 0 to 2
    }

    private fun zhuyinRegularToneRow(n: Int): Pair<Int, Int> = when (n) {
        1 -> 9 to 14
        2 -> 15 to 20
        else -> 18 to 23
    }

    private fun zhuyinRuToneRow(n: Int): Pair<Int, Int> = when (n) {
        1 -> 16 to 21
        2 -> 21 to 26
        else -> 24 to 29
    }

    private fun zhuyinToneGlyph(tone: ZhuyinTone): String = when (tone) {
        ZhuyinTone.Yangping -> "ˊ" // ˊ
        ZhuyinTone.Shang -> "ˇ"    // ˇ
        ZhuyinTone.Qu -> "ˋ"       // ˋ
        ZhuyinTone.Neutral -> "˙"  // ˙
        else -> ""
    }

    private fun List<ClusterMetricDecision>.lineMetrics(
        explicitLineHeight: Float?,
        defaultLineHeight: Float,
        spacingFloor: Float = 0f,
        rubyBand: Float = 0f,
    ): ResolvedLineMetrics {
        if (isEmpty()) {
            val height = explicitLineHeight ?: 0f
            return ResolvedLineMetrics(
                baseline = 0f,
                height = height,
            )
        }

        // 行间注 (ADR 0032): the注文 band sits ABOVE the base 字面, so it adds to
        // the ascent — the baseline drops to leave room above and the line grows.
        val ascent = maxOf { it.layoutMetrics.ascent } + rubyBand
        val descent = maxOf { it.layoutMetrics.descent }
        val naturalHeight = ascent + descent
        // Height = the explicit value, else the CjkBodyLineHeightDefault, but
        // never below naturalHeight + InterlinearMarkLineSpacingFloor — that
        // minimum keeps glyph ink and 行间标点 from overlapping the next line
        // (CLREQ「不应小于」). So an explicit lineHeight overrides the body
        // default downward, but is still clamped up to the no-overlap minimum.
        val minHeight = naturalHeight + spacingFloor
        val height = (explicitLineHeight ?: defaultLineHeight).coerceAtLeast(minHeight)
        val extraLeading = (height - naturalHeight).coerceAtLeast(0f)

        return ResolvedLineMetrics(
            baseline = extraLeading / 2f + ascent,
            height = height,
            extraLeading = extraLeading,
        )
    }

    private inline fun <T, K> List<T>.groupAdjacentBy(keySelector: (T) -> K): List<List<T>> {
        if (isEmpty()) return emptyList()

        val groups = mutableListOf<MutableList<T>>()
        var currentKey = keySelector(first())
        var currentGroup = mutableListOf(first())

        for (item in drop(1)) {
            val key = keySelector(item)
            if (key == currentKey) {
                currentGroup.add(item)
            } else {
                groups.add(currentGroup)
                currentKey = key
                currentGroup = mutableListOf(item)
            }
        }

        groups.add(currentGroup)
        return groups
    }
}

private data class ClusterMetricDecision(
    val range: TextRange,
    val sourceText: String,
    val request: FontMetricsRequest,
    val rawMetrics: RawFontMetrics,
    val layoutMetrics: LayoutFontMetrics,
)

private data class ResolvedLineMetrics(
    val baseline: Float,
    val height: Float,
    val extraLeading: Float = 0f,
)

private data class AutoSpaceApplicationResult(
    val clusters: List<Cluster>,
    val decisions: List<AutoSpaceDecisionInfo>,
)

private data class PunctuationGeometryLedger(
    private val naturalClusters: List<Cluster>,
    private val geometries: Map<Int, PunctuationClusterGeometry>,
    private val budgets: Map<Int, GlueBudget>,
    private val justificationDeltaByCluster: Map<Int, Float> = emptyMap(),
    /**
     * Raw advance reductions that are NOT punctuation glue — currently only
     * `TextAutoSpaceLineEdgeTrim` (the autospace replacement gap baked into a
     * Latin cluster's advance, removed again when the boundary lands on a
     * line edge). Applied unconditionally in [resolvedAdvance].
     */
    private val rawEdgeTrimByCluster: Map<Int, Float> = emptyMap(),
    /**
     * 行间注 避让 (ADR 0032): trailing advance ADDED to a base cluster so adjacent
     * 注文 keep ≥ one 注文 word-space between them (CLREQ §罗马拼音). STRUCTURAL —
     * applied unconditionally, BEFORE breaking, and survives the chain (so the
     * breaker + final render both see it). Distinct from justify deltas (those
     * are post-break and get replaced).
     */
    private val rubySpreadByCluster: Map<Int, Float> = emptyMap(),
) {
    companion object {
        fun from(
            naturalClusters: List<Cluster>,
            punctuationAtoms: List<PunctuationAtom>,
            spacingPlan: PunctuationSpacingCompressionResult,
        ): PunctuationGeometryLedger {
            val geometries = buildPunctuationClusterGeometries(
                naturalClusters = naturalClusters,
                punctuationAtoms = punctuationAtoms,
            )
            val budgets = geometries.mapValues { (_, geometry) ->
                GlueBudget(
                    leadingNatural = geometry.leadingGlueNatural,
                    leadingConsumed = 0f,
                    trailingNatural = geometry.trailingGlueNatural,
                    trailingConsumed = 0f,
                )
            }
            return PunctuationGeometryLedger(
                naturalClusters = naturalClusters,
                geometries = geometries,
                budgets = budgets,
            ).consumeSpacing(spacingPlan)
        }

        private fun buildPunctuationClusterGeometries(
            naturalClusters: List<Cluster>,
            punctuationAtoms: List<PunctuationAtom>,
        ): Map<Int, PunctuationClusterGeometry> {
            if (punctuationAtoms.isEmpty()) return emptyMap()

            return naturalClusters.mapIndexedNotNull { index, cluster ->
                val atomsForCluster = punctuationAtoms.filter { it.range.isInside(cluster.range) }
                if (atomsForCluster.isEmpty()) return@mapIndexedNotNull null
                index to PunctuationClusterGeometry(
                    range = cluster.range,
                    sourceText = cluster.text,
                    displayText = cluster.displayText,
                    baseAdvance = cluster.advance,
                    bodyWidth = atomsForCluster.sumOf { it.bodyWidth.toDouble() }.toFloat(),
                    leadingGlueNatural = atomsForCluster.first().leadingGlue.natural,
                    trailingGlueNatural = atomsForCluster.last().trailingGlue.natural,
                    reason = atomsForCluster.first().geometrySource,
                )
            }.toMap()
        }
    }

    fun resolveClusters(): List<Cluster> =
        naturalClusters.mapIndexed { index, cluster ->
            val resolved = resolvedAdvance(index, cluster)
            if (resolved == cluster.advance) cluster else cluster.copy(advance = resolved)
        }

    fun consumeTrailingByCluster(consumptionByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consume(consumptionByCluster) { budget, amount ->
                budget.copy(
                    trailingConsumed = (budget.trailingConsumed + amount)
                        .coerceAtMost(budget.trailingNatural),
                )
            },
        )

    fun consumeLeadingByCluster(consumptionByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consume(consumptionByCluster) { budget, amount ->
                budget.copy(
                    leadingConsumed = (budget.leadingConsumed + amount)
                        .coerceAtMost(budget.leadingNatural),
                )
            },
        )

    /** Remaining leading/trailing glue per punctuation cluster index. */
    fun glueCapacities(): Map<Int, GlueCapacity> =
        budgets.mapNotNull { (index, budget) ->
            val leading = budget.leadingRemaining
            val trailing = budget.trailingRemaining
            if (leading > 0f || trailing > 0f) index to GlueCapacity(leading, trailing) else null
        }.toMap()

    fun addJustificationDeltas(deltaByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(justificationDeltaByCluster = deltaByCluster)

    /** 行间注 避让 structural spread (ADR 0032) — applied before breaking, kept through the chain. */
    fun withRubySpread(spreadByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        if (spreadByCluster.isEmpty()) this else copy(rubySpreadByCluster = spreadByCluster)

    fun withRawEdgeTrims(trimByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        if (trimByCluster.isEmpty()) this else copy(rawEdgeTrimByCluster = trimByCluster)

    fun consumeLineEdgeGlue(
        lines: List<LineCandidate>,
        forceLineEndHalfWidth: Boolean = true,
    ): LineEdgeTrimResult {
        if (lines.isEmpty() || budgets.isEmpty()) {
            return LineEdgeTrimResult(this, emptyList())
        }

        val decisions = mutableListOf<LineEdgeTrimDecisionInfo>()
        val leadingConsumptionByCluster = HashMap<Int, Float>()
        val trailingConsumptionByCluster = HashMap<Int, Float>()
        lines.forEach { line ->
            val lastIdx = line.clusterRange.last
            // 宽松风格 (AllowFullWidth): the unconditional line-end half-width
            // trim is skipped; the blank was only available as on-demand
            // shrink capacity during PushIn.
            val trailingBudget = if (forceLineEndHalfWidth) budgets[lastIdx] else null
            trailingBudget?.let { budget ->
                val remaining = budget.trailingRemaining
                if (remaining > 0f) {
                    trailingConsumptionByCluster.merge(lastIdx, remaining) { a, b -> a + b }
                    decisions += LineEdgeTrimDecisionInfo(
                        lineRange = line.sourceRange,
                        clusterRange = naturalClusters[lastIdx].range,
                        side = "trailing",
                        trimAmount = remaining,
                        consumedBefore = budget.trailingConsumed,
                        naturalGlue = budget.trailingNatural,
                        reason = "LineEndHalfWidthPunctuation",
                    )
                }
            }

            val firstIdx = line.clusterRange.first
            budgets[firstIdx]?.let { budget ->
                val remaining = budget.leadingRemaining
                if (remaining > 0f) {
                    leadingConsumptionByCluster.merge(firstIdx, remaining) { a, b -> a + b }
                    decisions += LineEdgeTrimDecisionInfo(
                        lineRange = line.sourceRange,
                        clusterRange = naturalClusters[firstIdx].range,
                        side = "leading",
                        trimAmount = remaining,
                        consumedBefore = budget.leadingConsumed,
                        naturalGlue = budget.leadingNatural,
                        reason = "LineStartHalfWidthPunctuation",
                    )
                }
            }
        }

        val updated = copy(
            budgets = budgets
                .consume(leadingConsumptionByCluster) { budget, amount ->
                    budget.copy(
                        leadingConsumed = (budget.leadingConsumed + amount)
                            .coerceAtMost(budget.leadingNatural),
                    )
                }
                .consume(trailingConsumptionByCluster) { budget, amount ->
                    budget.copy(
                        trailingConsumed = (budget.trailingConsumed + amount)
                            .coerceAtMost(budget.trailingNatural),
                    )
                },
        )
        return LineEdgeTrimResult(updated, decisions)
    }

    fun toDecisionInfo(): List<ClusterGeometryDecisionInfo> =
        geometries.map { (index, geometry) ->
            val budget = budgets.getValue(index)
            val delta = justificationDeltaByCluster[index] ?: 0f
            ClusterGeometryDecisionInfo(
                range = geometry.range,
                sourceText = geometry.sourceText,
                displayText = geometry.displayText,
                baseAdvance = geometry.baseAdvance,
                bodyWidth = geometry.bodyWidth,
                leadingGlueNatural = budget.leadingNatural,
                leadingGlueConsumed = budget.leadingConsumed,
                trailingGlueNatural = budget.trailingNatural,
                trailingGlueConsumed = budget.trailingConsumed,
                justificationDelta = delta,
                resolvedAdvance = resolvedAdvance(index, naturalClusters[index]),
                source = "PunctuationGeometryLedger",
                reason = geometry.reason,
            )
        }

    private fun consumeSpacing(
        spacingPlan: PunctuationSpacingCompressionResult,
    ): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consumeByRange(
                clusters = naturalClusters,
                adjustments = spacingPlan.adjustments,
            ),
        )

    private fun resolvedAdvance(index: Int, cluster: Cluster): Float {
        val rawTrim = rawEdgeTrimByCluster[index] ?: 0f
        val spread = rubySpreadByCluster[index] ?: 0f
        val geometry = geometries[index] ?: run {
            val delta = justificationDeltaByCluster[index] ?: 0f
            return (cluster.advance + delta + spread - rawTrim).coerceAtLeast(0f)
        }
        val budget = budgets[index]
            ?: return (geometry.bodyWidth + (justificationDeltaByCluster[index] ?: 0f) + spread - rawTrim).coerceAtLeast(0f)
        val delta = justificationDeltaByCluster[index] ?: 0f
        return (
            geometry.bodyWidth +
                budget.leadingRemaining +
                budget.trailingRemaining +
                delta +
                spread -
                rawTrim
            ).coerceAtLeast(0f)
    }
}

private data class PunctuationClusterGeometry(
    val range: TextRange,
    val sourceText: String,
    val displayText: String,
    val baseAdvance: Float,
    val bodyWidth: Float,
    val leadingGlueNatural: Float,
    val trailingGlueNatural: Float,
    val reason: String,
)

private data class GlueBudget(
    val leadingNatural: Float,
    val leadingConsumed: Float,
    val trailingNatural: Float,
    val trailingConsumed: Float,
) {
    val leadingRemaining: Float get() = (leadingNatural - leadingConsumed).coerceAtLeast(0f)
    val trailingRemaining: Float get() = (trailingNatural - trailingConsumed).coerceAtLeast(0f)
}

private data class LineEdgeTrimResult(
    val geometry: PunctuationGeometryLedger,
    val decisions: List<LineEdgeTrimDecisionInfo>,
)

/**
 * ADR 0018: 着重号 dot ink centre sits this far below the BASELINE. Sized for
 * the tight case — the minimum 着重号 line height (natural + 0.5em floor) —
 * so an [EMPHASIS_DOT_DIAMETER_EM] dot seats roughly midway between the
 * character face below the baseline and the next line's ink, clearing both.
 * (The old 0.45 + a full-size `•` glyph overlapped the next line by ~1px on
 * real fonts — measured by `EmphasisClearanceProbe`.)
 */
private const val EMPHASIS_DOT_CENTER_EM = 0.34f

/**
 * ADR 0018: 着重号 dot diameter, as a fraction of em. CLREQ 着重号 is a small
 * solid dot, much smaller than the font's `•` glyph (~0.375em); renderers draw
 * a filled circle of this size so it fits the line gap. Matches the AWT raster.
 */
private const val EMPHASIS_DOT_DIAMETER_EM = 0.22f

/**
 * `CjkBodyLineHeightDefault`: 中文正文默认行高 1.5em(行距约 0.5em),无显式
 * [ParagraphStyle.lineHeight] 时生效。1.0em 实贴会让真墨迹(ascent≈0.94em)与
 * 相邻行碰头,且正文常规需要行距呼吸。CLREQ 的标点 floor 是「有行间标点时的
 * 下限」,与本默认取 max:单面装 0.5em floor 正好被本默认吸收,双面装 0.625em
 * 仍可顶高。显式 lineHeight 可向下覆盖本默认(仍不低于不重叠下限)。
 */
private const val DEFAULT_BODY_LINE_HEIGHT_EM = 1.5f

/** 行间注 (ruby, ADR 0032): 注文常用基文 1/2 字号 (CLREQ 振假名惯例). */
private const val RUBY_FONT_EM = 0.5f
/**
 * 避让 最小间距 (CLREQ §罗马拼音「相邻注文的间距不应小于西文词间空格」): one 注文
 * word space ≈ 1/4 of the 注文 em. Measured in 注文 units, NOT base 字宽.
 */
private const val RUBY_MIN_GAP_EM_OF_RUBY = 0.25f
/**
 * Extra clearance between the注文 字身框底 and the base 字身框顶 — **default 0**:
 * the typo boxes already carry ink margins (汉字墨迹不顶字身顶、西文降部不到 descent
 * 底), so flush-stacking the real font 字身框 (ADR 0002「用字体声明度量」) already
 * separates the ink. Bump only if a style wants looser ruby. (Placement itself is
 * the REAL ascent/descent, not a synthesized em.)
 */
private const val RUBY_STACK_GAP_EM = 0f

/** `LatinForcedHyphenBreak` 硬断时尽量满足的左右边界（前二后三，同 en-US 连字）. */
private const val HYPHEN_MIN_LEFT = 2
private const val HYPHEN_MIN_RIGHT = 3

/**
 * 连字作为最后一档（ADR 0029 amendment）：整词换行后，若填满版心需要给每个汉字
 * 间距加超过此值（半个字宽）才回头连字；以下则宁可拉伸汉字间距、不连字。
 */
private const val HYPHEN_LAST_RESORT_CJK_STRETCH_EM = 0.5f

/** 中西间距可拉伸余量（justify CjkLatinSpace cap 0.5em − 自然 0.25em），算松紧时先扣它. */
private const val HYPHEN_SINO_WESTERN_STRETCH_CAP_EM = 0.25f

/** CLREQ 挤压第②档：西文词距最小压至四分之一汉字宽. */
private const val WORD_SPACE_MIN_EM = 0.25f

/** CLREQ 挤压⑥：行内中西间距「最小挤为八分之一汉字宽」. */
private const val SINO_WESTERN_GAP_MIN_EM = 0.125f

/** CLREQ 行尾悬挂适配标点：顿号、逗号、句号. */
private val HANGABLE_PUNCTUATION = setOf('、', '，', '。')

/** CLREQ 挤压第④档对象：「位于行内的句号、问号、感叹号」. */
private val INLINE_STOPS = setOf('。', '！', '？', '．')

/** Remaining glue per side, input to the tiered shrink model (ADR 0020). */
internal data class GlueCapacity(val leading: Float, val trailing: Float)

/**
 * ADR 0018: 示亡号 frame hugs the CJK character face (字面) with no margin.
 * The face spans baseline-0.88em..baseline+0.12em in conventional CJK
 * design; font-reported ideographic metrics are a follow-up.
 */
private const val MOURNING_FRAME_FACE_ASCENT_EM = 0.88f
private const val MOURNING_FRAME_FACE_DESCENT_EM = 0.12f

/**
 * 行间线（专名号/书名号甲式）的横排 y：字身底 (+0.12em) 下方留一线空气
 * （行间标点应尽量紧贴所标注汉字一侧），与着重号同现时点墨水上缘在
 * +0.34em——先线后点成立。
 */
private const val INTERLINEAR_LINE_Y_EM = 0.18f

/** 相邻行间线各自回缩量（可见间隙 1/8em，单侧 ≤1/8em 上限内）. */
private const val ADJACENT_LINE_SHORTEN_EM = 0.0625f

/** 相邻判定：间距小于此值视为相邻（密排时为 0）. */
private const val ADJACENT_LINE_EPSILON = 0.01f

/**
 * Contiguous cluster-index range whose clusters are fully covered by
 * [sourceRange]; null when no cluster is covered.
 */
private fun List<Cluster>.clusterIndexRangeFor(sourceRange: TextRange): IntRange? {
    var first = -1
    var last = -1
    forEachIndexed { idx, cluster ->
        if (cluster.range.start >= sourceRange.start && cluster.range.end <= sourceRange.end) {
            if (first == -1) first = idx
            last = idx
        }
    }
    return if (first == -1) null else first..last
}

private fun Map<Int, GlueBudget>.consume(
    consumptionByCluster: Map<Int, Float>,
    apply: (GlueBudget, Float) -> GlueBudget,
): Map<Int, GlueBudget> {
    if (consumptionByCluster.isEmpty()) return this

    return toMutableMap().also { updated ->
        consumptionByCluster.forEach { (index, amount) ->
            if (amount <= 0f) return@forEach
            updated[index]?.let { budget -> updated[index] = apply(budget, amount) }
        }
    }
}

private fun Map<Int, GlueBudget>.consumeByRange(
    clusters: List<Cluster>,
    adjustments: List<PunctuationSpacingAdjustment>,
): Map<Int, GlueBudget> {
    if (adjustments.isEmpty()) return this

    return toMutableMap().also { updated ->
        adjustments.forEach { adjustment ->
            val targetIdx = clusters.indexOfFirst { adjustment.reductionTargetRange.isInside(it.range) }
            if (targetIdx < 0) return@forEach
            updated[targetIdx]?.let { current ->
                // Consume reduction from whichever side has remaining capacity.
                // With class-based single-sided glue, all glue may be on one
                // side (e.g. PauseOrStop → trailing only, Opening → leading only).
                val leadingRemaining = current.leadingNatural - current.leadingConsumed
                val trailingRemaining = current.trailingNatural - current.trailingConsumed
                updated[targetIdx] = if (trailingRemaining >= leadingRemaining) {
                    current.copy(
                        trailingConsumed = (current.trailingConsumed + adjustment.reduction)
                            .coerceAtMost(current.trailingNatural),
                    )
                } else {
                    current.copy(
                        leadingConsumed = (current.leadingConsumed + adjustment.reduction)
                            .coerceAtMost(current.leadingNatural),
                    )
                }
            }
        }
    }
}

private fun TextRange.isInside(other: TextRange): Boolean =
    start >= other.start && end <= other.end
