package org.tiqian.layout

import org.tiqian.clreq.AutoSpaceMode
import org.tiqian.clreq.AutoSpacePolicy
import org.tiqian.clreq.BuiltInClreqProfileResolver
import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.ClreqProfileResolver
import org.tiqian.clreq.ClreqPunctuationPolicies
import org.tiqian.clreq.HangingPunctuationStyle
import org.tiqian.clreq.KinsokuLevel
import org.tiqian.clreq.LineAdjustmentStrategy
import org.tiqian.clreq.LineEndPunctuationStyle
import org.tiqian.clreq.NumberSymbolCohesion
import org.tiqian.clreq.PunctuationClass
import org.tiqian.clreq.PunctuationGluePlacement
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.core.AutoSpaceDecisionInfo
import org.tiqian.core.BreakOpportunityDecisionInfo
import org.tiqian.core.Cluster
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo
import org.tiqian.core.EastAsianSpacingEdges
import org.tiqian.core.EastAsianSpacingValue
import org.tiqian.core.UnicodeEastAsianSpacing
import org.tiqian.core.ClusterGeometryDecisionInfo
import org.tiqian.core.ContextualKinsokuDecisionInfo
import org.tiqian.core.DecorationDecisionInfo
import org.tiqian.core.RubyDecisionInfo
import org.tiqian.clreq.BopomofoParser
import org.tiqian.clreq.BopomofoTone
import org.tiqian.core.RubyKind
import org.tiqian.core.RubyLineHeightDecisionInfo
import org.tiqian.core.RubyLineHeightMode
import org.tiqian.core.RubySpan
import org.tiqian.core.BopomofoDecisionInfo
import org.tiqian.core.BopomofoGlyphPlacement
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSegmentInfo
import org.tiqian.core.DecorationSpan
import org.tiqian.core.FontDecisionInfo
import org.tiqian.core.LineEdgeTrimDecisionInfo
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.JustificationAllocationInfo
import org.tiqian.core.JustificationDecisionInfo
import org.tiqian.core.LayoutDebugInfo
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.InlineBoxDecisionInfo
import org.tiqian.core.InlineBoxOuterSpacing
import org.tiqian.core.InlineBoxSpan
import org.tiqian.core.InlineAttachment
import org.tiqian.core.InlineObjectBoundaryAdjustment
import org.tiqian.core.InlineObjectDecisionInfo
import org.tiqian.core.InlineObjectLineHeightDecisionInfo
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo
import org.tiqian.core.InlineObjectPreferredStretch
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.LineBox
import org.tiqian.core.LineDebugInfo
import org.tiqian.core.LineDecisionInfo
import org.tiqian.core.LineEndReason
import org.tiqian.core.LineRepairAllocationInfo
import org.tiqian.core.LineRepairCandidateInfo
import org.tiqian.core.LineRepairDecisionInfo
import org.tiqian.core.MandatoryBreakDecisionInfo
import org.tiqian.core.ZeroWidthBreakDecisionInfo
import org.tiqian.core.MaxLinesDecisionInfo
import org.tiqian.core.MetricDecisionInfo
import org.tiqian.core.PunctuationDecisionInfo
import org.tiqian.core.Rect
import org.tiqian.core.RoleOverrideInfo
import org.tiqian.core.Size
import org.tiqian.core.SpacingDecisionInfo
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.core.LastLineAlignment
import org.tiqian.core.KinsokuDecisionInfo
import org.tiqian.core.LineLengthGridDecisionInfo
import org.tiqian.core.FirstLineIndentDecisionInfo
import kotlin.math.floor
import kotlin.text.CharCategory
import org.tiqian.core.LineSpacingDecisionInfo
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.sourceGraphemeBoundaries
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FallbackResolver
import org.tiqian.font.FontMetricsNormalizationInput
import org.tiqian.font.FontMetricsNormalizer
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRequest
import org.tiqian.font.FontRole
import org.tiqian.font.BaselineClass
import org.tiqian.font.MetricBox
import org.tiqian.font.FontRoleClassifier
import org.tiqian.font.FontRoleContext
import org.tiqian.font.LayoutFontMetrics
import org.tiqian.font.PreferCjkForAmbiguousPunctuationResolver
import org.tiqian.font.RawFontMetrics
import org.tiqian.font.ScriptAwareFontMetricsNormalizer
import org.tiqian.font.StubFontMetricsResolver
import org.tiqian.linebreak.Hyphenator
import org.tiqian.linebreak.isMandatoryBreakCodePoint
import org.tiqian.linebreak.isZeroWidthSpaceCodePoint
import org.tiqian.linebreak.NoHyphenator
import org.tiqian.shaping.ExplainableStubTextShaper
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
import org.tiqian.shaping.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE

internal data class ParagraphShapingStageResult(
    val shapingResults: List<ShapingResult>,
    val hyphenOffsets: Set<Int>,
    val hyphenAdvance: Float,
    val hyphenGlyphs: List<Glyph>,
    val substitutionRollbacks: Map<TextRange, String>,
    val breakOpportunityDecisions: List<BreakOpportunityDecisionInfo>,
    val emergencyTrackingEligibilityDecisions: List<EmergencyTrackingEligibilityDecisionInfo>,
    val progressiveBreakOffsets: Map<Int, ProgressiveBreakOpportunity>,
    val segmentShapingCache: Map<TextRange, ShapingResult> = emptyMap(),
)

/**
 * Width-dependent shaping stage. It resolves display substitutions and
 * Western token break candidates, then returns source-faithful clusters and
 * glyph evidence for the later punctuation and line-layout stages.
 */
internal fun ExplainableStubParagraphLayoutEngine.shapeParagraph(
    input: LayoutInput,
    text: String,
    fontSize: Float,
    measure: Float,
    clusterRanges: List<ResolvedClusterRange>,
    fontDecisionByRange: Map<TextRange, FontDecision>,
    inlineObjectByRange: Map<TextRange, InlineObjectSpan>,
    punctuationGlyphSubstitutor: ClreqPunctuationGlyphSubstitutor,
    styleAt: (Int) -> TextStyle,
    emphasisItalicAt: (Int) -> Boolean,
    rejectedTechnicalTiersBySpan: Map<TextRange, Set<ProgressiveBreakTier>>,
    cachedSegmentShaping: Map<TextRange, ShapingResult> = emptyMap(),
    cachedSubstitutionRollbacks: Map<TextRange, String> = emptyMap(),
): ParagraphShapingStageResult {
    val segmentShapingCache = cachedSegmentShaping.toMutableMap()
    val substitutionRollbacks = cachedSubstitutionRollbacks.toMutableMap()
    fun ShapingResult.dashInkCoverageDeficient(displayText: String, segmentFontSize: Float): Boolean {
        if (!displayText.contains('\u2E3A')) return false
        val glyph = glyphRuns.flatMap { it.glyphs }.singleOrNull() ?: return false
        val ink = glyph.bounds ?: return false
        // `DashSubstitutionTwoEmInkCoverage`: compare with the CLREQ
        // target box, not the browser/font fallback's reported advance.
        // A missing U+2E3A commonly falls back to a perfectly filled 1em
        // glyph; dividing by that wrong 1em advance made the fallback look
        // valid and silently shrank a Chinese dash by half.
        val targetAdvance = DASH_SUBSTITUTION_TARGET_EM * segmentFontSize
        return (ink.right - ink.left) < targetAdvance * DASH_SUBSTITUTION_MIN_INK_COVERAGE
    }
    fun shapeSegment(decision: FontDecision, segmentRange: TextRange): ShapingResult {
        val cached = segmentShapingCache[segmentRange]
        if (cached != null) return cached
        val sourceText = text.substring(segmentRange.start, segmentRange.end)
        val substitution = punctuationGlyphSubstitutor.substituteForRole(sourceText, decision.role)
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
                openTypeFeatures = cjkPunctuationFullWidthFeatures(
                    role = decision.role,
                    displayText = substitution.displayText,
                ),
            ),
        )
        val rollbackCause = when {
            substitution.displayText == sourceText -> null
            shaped.decisions.any {
                it.capabilityIssue == UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE
            } -> "SubstitutionRollbackOnUnverifiedGlyphCoverage"
            shaped.decisions.any { it.missingGlyphs > 0 } -> "SubstitutionRollbackOnMissingGlyph"
            shaped.dashInkCoverageDeficient(substitution.displayText, segmentStyle.fontSize) ->
                "DashSubstitutionInkCoverageRollback"
            else -> null
        }
        val result = if (rollbackCause == null) {
            shaped
        } else {
            substitutionRollbacks[segmentRange] = rollbackCause
            textShaper.shape(
                ShapingInput(
                    text = text,
                    range = segmentRange,
                    style = segmentStyle,
                    fontDecision = decision,
                    displayText = sourceText,
                    openTypeFeatures = cjkPunctuationFullWidthFeatures(
                        role = decision.role,
                        displayText = sourceText,
                    ),
                ),
            )
        }
        segmentShapingCache[segmentRange] = result
        return result
    }
    fun shapeSegmentWithPointMarkPrefix(
        decision: FontDecision,
        segmentRange: TextRange,
    ): List<ShapingResult> {
        var prefixEnd = segmentRange.start
        while (
            prefixEnd < segmentRange.end &&
            ClreqPunctuationPolicies.isAsciiPointMark(text[prefixEnd])
        ) {
            prefixEnd += 1
        }
        return if (prefixEnd in (segmentRange.start + 1) until segmentRange.end) {
            // `PostCutAsciiPointMarkPrefixSegmentation`: opaque-token and
            // hard-cut passes can create a fresh `,A` piece after the
            // initial role segmentation. Re-shape its point-mark prefix
            // separately so kinsoku binds only the comma, not its suffix.
            listOf(
                shapeSegment(decision, TextRange(segmentRange.start, prefixEnd)),
                shapeSegment(decision, TextRange(prefixEnd, segmentRange.end)),
            )
        } else {
            listOf(shapeSegment(decision, segmentRange))
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
    // it. A break at one of these offsets earns a displayed trailing hyphen;
    // later geometry reserves that hyphen inside the measure when possible
    // and hangs only the residual that cannot fit. `hyphenOffsets` are the
    // absolute source offsets where the next line may continue the word.
    //
    // Cut points are (a) the [hyphenator]'s syllable points, plus (b)
    // `LatinForcedHyphenBreak`: for any word piece STILL wider than the
    // measure (hyphenation off, or a syllable/token that can't fit),
    // character-level fallback cuts that hard-break it — preferring 前二后三
    // (2/3) within the piece, breaking anywhere only when that can't be met
    // (满足不了就算了).
    //
    // `LatinStructuralSolidusBreak`: a solidus inside a Latin token
    // (`TeX/LaTeX`) is a clean separator boundary even when the whole token
    // would fit a fresh line. The slash stays with the previous piece, so
    // breaks read `TeX/` + `LaTeX`, never `/LaTeX`.
    //
    // `LatinOpaqueTokenBreak`: URL-like / identifier-like Latin tokens are
    // not words. They get clean breaks at ASCII separators; if a remaining
    // piece is still over-wide, it hard-breaks at character boundaries with
    // NO synthetic hyphen. This keeps links copy-faithful and avoids
    // inventing hyphens inside hashes, query strings, or mixed alpha/digit ids.
    //
    // `LatinLongUnhyphenatedLetterTokenBreak`: a very long all-letter run,
    // or a very long hyphenator-unexplained piece inside one, is also
    // opaque, not an English word. This covers pure-letter base64/hash
    // fragments and synthetic strings such as `ssss...herstory`; it uses
    // the same no-hyphen hard cuts.
    val hyphenOffsets = mutableSetOf<Int>()
    var hyphenAdvanceOrNull: Float? = null
    var hyphenGlyphs: List<Glyph> = emptyList()
    fun latinWordCuts(
        decision: FontDecision,
        wordRange: TextRange,
        syllable: List<Int>,
    ): List<Int> {
        val cuts = mutableSetOf<Int>()
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
        return cuts.sorted()
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
    // `TechnicalAlphaNumericTransitionBreak`: identifiers commonly encode a
    // semantic boundary at letter<->digit transitions (`Machine|2|Machine`).
    // These are structural clean cuts: no synthetic hyphen is displayed.
    fun alphaNumericTransitionCuts(wordRange: TextRange): List<Int> {
        val w = text.substring(wordRange.start, wordRange.end)
        return (1 until w.length).mapNotNull { index ->
            val left = w[index - 1]
            val right = w[index]
            if (
                (left.isLetter() && right.isDigit()) ||
                (left.isDigit() && right.isLetter())
            ) {
                wordRange.start + index
            } else {
                null
            }
        }
    }
    fun String.strongNonLexicalReason(): String? {
        if (length < EMERGENCY_TRACKING_TOKEN_MIN_LENGTH) return null
        if (all(Char::isLetter) && all { it.equals(first(), ignoreCase = true) }) {
            return "LongRepeatedLetterRun"
        }
        if (any(Char::isLetter) && all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
            return "LongHexIdentityRun"
        }
        if (any(Char::isLetter) && any(Char::isDigit)) {
            val transitions = zipWithNext().count { (left, right) ->
                (left.isLetter() && right.isDigit()) ||
                    (left.isDigit() && right.isLetter())
            }
            if (transitions >= 2) return "LongMixedAlphaNumericIdentifier"
        }
        return null
    }
    val breakOpportunityDecisions = mutableListOf<BreakOpportunityDecisionInfo>()
    val emergencyTrackingEligibilityDecisions = mutableListOf<EmergencyTrackingEligibilityDecisionInfo>()
    val emergencyTrackingEligibilityKeys = HashSet<Pair<TextRange, String>>()
    fun registerEmergencyTrackingEligibility(range: TextRange, reason: String) {
        if (!emergencyTrackingEligibilityKeys.add(range to reason)) return
        emergencyTrackingEligibilityDecisions += EmergencyTrackingEligibilityDecisionInfo(
            range = range,
            sourceText = text.substring(range.start, range.end),
            reason = reason,
        )
    }
    val progressiveBreakOffsets = mutableMapOf<Int, ProgressiveBreakOpportunity>()
    fun latinSeparatorCuts(
        tokenRange: TextRange,
        tokenAdvance: Float,
        forceOpaqueBreaks: Boolean,
    ): List<Int> {
        val token = text.substring(tokenRange.start, tokenRange.end)
        val urlLike = token.isUrlLikeLatinToken()
        val opaque = token.any { !it.isLetter() }
        val structuralSolidus = token.hasBreakableLatinSolidus()
        val bibliographicLocatorCuts = token.bibliographicNumericLocatorBreakOffsets()
        val opaqueSeparatorMode = urlLike || (opaque && (tokenAdvance > measure || forceOpaqueBreaks))
        if (!structuralSolidus && !opaqueSeparatorMode && bibliographicLocatorCuts.isEmpty()) {
            return emptyList()
        }
        val cuts = bibliographicLocatorCuts
            .mapTo(mutableListOf()) { tokenRange.start + it }
        if (bibliographicLocatorCuts.isNotEmpty()) {
            breakOpportunityDecisions += BreakOpportunityDecisionInfo(
                range = tokenRange,
                sourceText = token,
                breakOffsets = cuts.toList(),
                reason = "BibliographicNumericLocatorBreak",
            )
        }
        for (i in 0 until token.lastIndex) {
            val breakAfter = (structuralSolidus && !urlLike && token[i] == '/') ||
                (opaqueSeparatorMode && token.isLatinTokenBreakAfter(i, tokenAdvance <= measure))
            if (breakAfter) cuts += tokenRange.start + i + 1
        }
        return cuts
    }
    fun latinOpaqueHardCuts(
        decision: FontDecision,
        tokenRange: TextRange,
        cleanCuts: List<Int>,
        forceOpaqueBreaks: Boolean,
    ): List<Int> {
        val relBounds = (listOf(0) + cleanCuts.map { it - tokenRange.start } + listOf(tokenRange.length))
            .distinct()
            .sorted()
        val cuts = mutableSetOf<Int>()
        for (i in 0 until relBounds.size - 1) {
            val a = relBounds[i]
            val b = relBounds[i + 1]
            if (b - a <= 1) continue
            val pieceAdvance = shapeSegment(decision, TextRange(tokenRange.start + a, tokenRange.start + b))
                .clusters.singleOrNull()?.advance ?: 0f
            if (pieceAdvance <= measure && !(forceOpaqueBreaks && b - a >= LATIN_OPAQUE_TOKEN_MIN_LENGTH)) {
                continue
            }
            val pieceRange = TextRange(tokenRange.start + a, tokenRange.start + b)
            text.sourceGraphemeBoundaries(pieceRange)
                .filterTo(cuts) { it > pieceRange.start && it < pieceRange.end }
        }
        return cuts.sorted()
    }
    val progressiveSpanAdvanceCache = mutableMapOf<TextRange, Float>()
    fun progressiveSpanAdvance(spanRange: TextRange): Float =
        progressiveSpanAdvanceCache.getOrPut(spanRange) {
            clusterRanges.sumOf { resolvedRange ->
                if (
                    resolvedRange.mandatoryBreak || resolvedRange.zeroWidthSoftBreak ||
                    inlineObjectByRange.containsKey(resolvedRange.range)
                ) {
                    return@sumOf 0.0
                }
                val decision = fontDecisionByRange.getValue(resolvedRange.range)
                decision.shapingSegments(text).sumOf { candidate ->
                    val start = maxOf(candidate.start, spanRange.start)
                    val end = minOf(candidate.end, spanRange.end)
                    if (start >= end) {
                        0.0
                    } else {
                        shapeSegment(decision, TextRange(start, end))
                            .clusters.sumOf { it.advance.toDouble() }
                    }
                }
            }.toFloat()
        }
    val shapingResults = clusterRanges.flatMap { resolvedRange ->
        inlineObjectByRange[resolvedRange.range]?.let { inlineObject ->
            return@flatMap listOf(inlineObjectShapingResult(text, inlineObject))
        }
        if (resolvedRange.mandatoryBreak) {
            return@flatMap listOf(mandatoryBreakShapingResult(text, resolvedRange.range))
        }
        if (resolvedRange.zeroWidthSoftBreak) {
            return@flatMap listOf(zeroWidthSoftBreakShapingResult(text, resolvedRange.range))
        }
        val decision = fontDecisionByRange.getValue(resolvedRange.range)
        decision.shapingSegments(text).flatMap { segmentRange ->
            val shaped = shapeSegment(decision, segmentRange)
            val isLatin = decision.role == FontRole.LatinText && segmentRange.length > 0
            val w = if (isLatin) text.substring(segmentRange.start, segmentRange.end) else ""
            val progressiveSpan = input.content.lineBreakSpans.firstOrNull { span ->
                span.policy == LineBreakPolicy.ProgressiveTechnical &&
                    segmentRange.start >= span.range.start && segmentRange.end <= span.range.end
            }
            val allLetters = isLatin && w.all { it.isLetter() }
            // §9.4 全大写缩写不断词；驼峰式在驼峰处断（无连字符）；含 '-' 在
            // 已有连字符处断（§9.3，无新连字符）。以上都是 clean 断点（不进
            // hyphenOffsets）。其余全字母词走 §9.2 音节 + 硬断（加合成连字符）。
            val isAllCaps = allLetters && w.length >= 2 && w.none { it.isLowerCase() }
            val isAbbreviation = isAllCaps && w.length < LATIN_OPAQUE_TOKEN_MIN_LENGTH
            val isCamelCase = allLetters && !isAllCaps && !isAbbreviation &&
                (1 until w.length).any { w[it].isUpperCase() }
            val tokenAdvance = shaped.clusters.sumOf { it.advance.toDouble() }.toFloat()
            val strongNonLexicalReason = if (isLatin) w.strongNonLexicalReason() else null
            val syllableCuts = if (
                allLetters && !isAbbreviation && !isCamelCase && !w.contains('-') &&
                strongNonLexicalReason == null
            ) {
                hyphenator.hyphenate(w).distinct().sorted()
            } else {
                emptyList()
            }
            val longestUnhyphenatedLetterPiece = if (allLetters) {
                val bounds = (listOf(0) + syllableCuts + listOf(w.length)).distinct().sorted()
                bounds.zipWithNext().maxOfOrNull { (a, b) -> b - a } ?: w.length
            } else {
                0
            }
            val isLongUnhyphenatedLetterToken =
                allLetters && !isAbbreviation && !isCamelCase &&
                    longestUnhyphenatedLetterPiece >= LATIN_OPAQUE_TOKEN_MIN_LENGTH
            val isLongOpaqueLatinToken =
                strongNonLexicalReason != null || isLongUnhyphenatedLetterToken ||
                    (isLatin && !allLetters && w.length >= LATIN_OPAQUE_TOKEN_MIN_LENGTH)
            val technicalStructuralCuts = if (progressiveSpan != null && isLatin) {
                buildSet {
                    addAll(camelCaseCuts(segmentRange))
                    addAll(alphaNumericTransitionCuts(segmentRange))
                    for (i in 0 until w.lastIndex) {
                        if (w[i] in PROGRESSIVE_TECHNICAL_BREAK_AFTER_CHARS) {
                            add(segmentRange.start + i + 1)
                        }
                    }
                }.sorted()
            } else {
                emptyList()
            }
            val rawTechnicalSyllableCuts = if (progressiveSpan != null && isLatin) {
                buildList {
                    val preferredBounds = (
                        listOf(segmentRange.start) + technicalStructuralCuts + listOf(segmentRange.end)
                        ).distinct().sorted()
                    preferredBounds.zipWithNext().forEach { (pieceStart, pieceEnd) ->
                        val piece = text.substring(pieceStart, pieceEnd)
                        if (piece.strongNonLexicalReason() != null) return@forEach
                        var runStart = pieceStart
                        while (runStart < pieceEnd) {
                            while (runStart < pieceEnd && !text[runStart].isLetter()) runStart += 1
                            var runEnd = runStart
                            while (runEnd < pieceEnd && text[runEnd].isLetter()) runEnd += 1
                            if (runEnd > runStart) {
                                val word = text.substring(runStart, runEnd)
                                addAll(
                                    hyphenator.hyphenate(word)
                                        .filter { it in 1 until word.length }
                                        .map { runStart + it },
                                )
                            }
                            runStart = maxOf(runEnd, runStart + 1)
                        }
                    }
                }.distinct().sorted()
            } else {
                emptyList()
            }
            val technicalSyllableCuts = rawTechnicalSyllableCuts
                .filterNot { it in technicalStructuralCuts }
            val technicalEmergencyCuts = if (progressiveSpan != null && isLatin) {
                val rejectedTiers = rejectedTechnicalTiersBySpan[progressiveSpan.range].orEmpty()
                val exposedForCurrentLine = rejectedTiers.isNotEmpty()
                val preferredBounds = (
                    listOf(segmentRange.start) + technicalStructuralCuts + technicalSyllableCuts +
                        listOf(segmentRange.end)
                    ).distinct().sorted()
                val interiorEmergencyCuts = preferredBounds.zipWithNext().flatMap { (start, end) ->
                    val pieceRange = TextRange(start, end)
                    val pieceAdvance = shapeSegment(decision, pieceRange)
                        .clusters.sumOf { it.advance.toDouble() }.toFloat()
                    // `ProgressiveTechnicalEmergencyExposure`: an over-measure technical span
                    // needs grapheme-safe cuts immediately. A span that fits the full measure
                    // receives the same final tier only after the post-adjustment plan rejects a
                    // clean tier for requiring tracking (`CurrentLineTechnicalTierRejection`).
                    // Structural/syllable candidates still win while bounded spacing fills the
                    // current line without tracking.
                    if (
                        !exposedForCurrentLine &&
                        pieceAdvance <= measure &&
                        progressiveSpanAdvance(progressiveSpan.range) <= measure
                    ) {
                        emptyList()
                    } else {
                        text.sourceGraphemeBoundaries(pieceRange)
                            .filter { it > start && it < end }
                    }
                }
                val rejectedCleanBoundaries = buildList {
                    if (ProgressiveBreakTier.Structural in rejectedTiers) {
                        addAll(technicalStructuralCuts)
                    }
                    if (ProgressiveBreakTier.Syllable in rejectedTiers) {
                        addAll(technicalSyllableCuts)
                    }
                }
                (interiorEmergencyCuts + rejectedCleanBoundaries).distinct().sorted()
            } else {
                emptyList()
            }
            if (progressiveSpan != null) {
                if (technicalEmergencyCuts.isNotEmpty()) {
                    registerEmergencyTrackingEligibility(
                        progressiveSpan.range,
                        if (rejectedTechnicalTiersBySpan[progressiveSpan.range].orEmpty().isNotEmpty()) {
                            "CurrentLineTechnicalTierRejection:" +
                                rejectedTechnicalTiersBySpan.getValue(progressiveSpan.range)
                                    .sortedBy(ProgressiveBreakTier::priority)
                                    .joinToString("+") { it.name }
                        } else {
                            "ProgressiveTechnicalSpan"
                        },
                    )
                }
                listOf(
                    ProgressiveBreakTier.Structural to technicalStructuralCuts,
                    ProgressiveBreakTier.Syllable to technicalSyllableCuts,
                    ProgressiveBreakTier.Emergency to technicalEmergencyCuts,
                ).forEach { (tier, offsets) ->
                    if (tier in rejectedTechnicalTiersBySpan[progressiveSpan.range].orEmpty()) {
                        return@forEach
                    }
                    val uniqueOffsets = offsets.distinct().sorted()
                    if (uniqueOffsets.isNotEmpty()) {
                        breakOpportunityDecisions += BreakOpportunityDecisionInfo(
                            range = segmentRange,
                            sourceText = w,
                            breakOffsets = uniqueOffsets,
                            reason = if (
                                tier == ProgressiveBreakTier.Emergency &&
                                rejectedTechnicalTiersBySpan[progressiveSpan.range].orEmpty().isNotEmpty()
                            ) {
                                "CurrentLineTechnicalEmergencyBreak"
                            } else {
                                "ProgressiveTechnicalBreak"
                            },
                            tier = tier.name,
                        )
                    }
                    uniqueOffsets.forEach { offset ->
                        val current = progressiveBreakOffsets[offset]
                        if (current == null || tier.priority < current.tier.priority) {
                            progressiveBreakOffsets[offset] = ProgressiveBreakOpportunity(
                                tier,
                                progressiveSpan.range,
                            )
                        }
                    }
                }
                val boundaryTier = if (
                    segmentRange.start > progressiveSpan.range.start &&
                    text[segmentRange.start - 1].isWhitespace()
                ) {
                    ProgressiveBreakTier.Whitespace
                } else {
                    ProgressiveBreakTier.WholeToken
                }
                if (boundaryTier !in rejectedTechnicalTiersBySpan[progressiveSpan.range].orEmpty()) {
                    val wholeToken = ProgressiveBreakOpportunity(boundaryTier, progressiveSpan.range)
                    val currentAtStart = progressiveBreakOffsets[segmentRange.start]
                    if (currentAtStart == null || wholeToken.tier.priority < currentAtStart.tier.priority) {
                        progressiveBreakOffsets[segmentRange.start] = wholeToken
                    }
                    breakOpportunityDecisions += BreakOpportunityDecisionInfo(
                        range = segmentRange,
                        sourceText = w,
                        breakOffsets = listOf(segmentRange.start),
                        reason = if (boundaryTier == ProgressiveBreakTier.Whitespace) {
                            "ProgressiveTechnicalWhitespaceBreak"
                        } else {
                            "ProgressiveTechnicalWholeTokenWrap"
                        },
                        tier = boundaryTier.name,
                    )
                }
            }
            val cleanCuts = when {
                progressiveSpan != null ->
                    technicalStructuralCuts + technicalSyllableCuts + technicalEmergencyCuts
                !isLatin -> emptyList()
                w.contains('-') -> existingHyphenCuts(segmentRange) +
                    latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken)
                isCamelCase -> camelCaseCuts(segmentRange)
                !allLetters -> latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken)
                else -> emptyList()
            }
            val hyphenCuts = if (
                progressiveSpan == null && allLetters && !isAbbreviation && !isCamelCase &&
                    !isLongUnhyphenatedLetterToken && !w.contains('-') && cleanCuts.isEmpty()
            ) {
                latinWordCuts(decision, segmentRange, syllableCuts)
            } else {
                emptyList()
            }
            val opaqueHardCuts = if (
                progressiveSpan == null && isLatin &&
                (!allLetters || isLongUnhyphenatedLetterToken) &&
                (tokenAdvance > measure || isLongOpaqueLatinToken)
            ) {
                latinOpaqueHardCuts(decision, segmentRange, cleanCuts, isLongOpaqueLatinToken)
            } else {
                emptyList()
            }
            if (progressiveSpan == null && opaqueHardCuts.isNotEmpty()) {
                val cleanBounds = (listOf(segmentRange.start) + cleanCuts + listOf(segmentRange.end))
                    .distinct().sorted()
                cleanBounds.zipWithNext().forEach { (pieceStart, pieceEnd) ->
                    val pieceHardCuts = opaqueHardCuts.filter { it > pieceStart && it < pieceEnd }
                    if (pieceHardCuts.isEmpty()) return@forEach
                    val pieceRange = TextRange(pieceStart, pieceEnd)
                    val pieceReason = text.substring(pieceStart, pieceEnd).strongNonLexicalReason()
                        ?: return@forEach
                    registerEmergencyTrackingEligibility(pieceRange, pieceReason)
                }
            }
            val allCuts = (cleanCuts + hyphenCuts + opaqueHardCuts).distinct().sorted()
            if (allCuts.isEmpty()) {
                listOf(shaped)
            } else {
                if (hyphenCuts.isNotEmpty()) {
                    hyphenOffsets += hyphenCuts
                    if (hyphenAdvanceOrNull == null) {
                        val hyphenShaped = textShaper.shape(
                            ShapingInput(
                                text = "-",
                                range = TextRange(0, 1),
                                style = input.textStyle,
                                fontDecision = decision,
                                displayText = "-",
                            ),
                        )
                        hyphenAdvanceOrNull = hyphenShaped.clusters.singleOrNull()?.advance ?: (0.5f * fontSize)
                        hyphenGlyphs = hyphenShaped.glyphRuns.flatMap { it.glyphs }
                    }
                }
                val bounds = listOf(segmentRange.start) + allCuts + listOf(segmentRange.end)
                (0 until bounds.size - 1).flatMap { k ->
                    shapeSegmentWithPointMarkPrefix(
                        decision,
                        TextRange(bounds[k], bounds[k + 1]),
                    )
                }
            }
        }
    }
    val hyphenAdvance = hyphenAdvanceOrNull ?: 0f
    return ParagraphShapingStageResult(
        shapingResults = shapingResults,
        hyphenOffsets = hyphenOffsets.toSet(),
        hyphenAdvance = hyphenAdvance,
        hyphenGlyphs = hyphenGlyphs,
        // Map-typed fields render key-ascending (key-order rule: Int natural
        // order; TextRange by (start, end); RubySpan by (baseRange.start,
        // baseRange.end, text); other key types by their fields in declaration
        // order). The value lookups above are unchanged; only the rendered
        // iteration order is pinned. buildMap yields a LinkedHashMap in
        // insertion order; TreeMap and toSortedMap are JVM-only in the
        // Kotlin 2.3 stdlib, so commonMain cannot use them.
        substitutionRollbacks = buildMap {
            for (key in substitutionRollbacks.keys.sortedWith(compareBy({ it.start }, { it.end }))) {
                put(key, substitutionRollbacks.getValue(key))
            }
        },
        breakOpportunityDecisions = breakOpportunityDecisions.toList(),
        emergencyTrackingEligibilityDecisions = emergencyTrackingEligibilityDecisions.toList(),
        progressiveBreakOffsets = buildMap {
            for (key in progressiveBreakOffsets.keys.sorted()) {
                put(key, progressiveBreakOffsets.getValue(key))
            }
        },
        segmentShapingCache = buildMap {
            for (key in segmentShapingCache.keys.sortedWith(compareBy({ it.start }, { it.end }))) {
                put(key, segmentShapingCache.getValue(key))
            }
        },
    )
}

/**
 * `CjkContextCurlyQuoteFullWidthVariant`: ask the font for its full-width
 * form before layout synthesizes a missing full-width punctuation cell.
 * Some fonts advertise `fwid` but do not map U+2018..U+201D, so the
 * punctuation model must still validate the shaped advance.
 */
private fun cjkPunctuationFullWidthFeatures(role: FontRole, displayText: String): List<String> =
    if (role == FontRole.CjkPunctuation && displayText.any { it.isSharedCurlyQuote() }) {
        listOf("fwid=1")
    } else {
        emptyList()
    }

private fun Char.isSharedCurlyQuote(): Boolean =
    this == '\u2018' || this == '\u2019' || this == '\u201C' || this == '\u201D'

private fun String.isUrlLikeLatinToken(): Boolean {
    val lower = lowercase()
    return "://" in this || lower.startsWith("www.") || hasDomainLikeDot()
}

private fun String.hasDomainLikeDot(): Boolean =
    indices.any { i ->
        if (this[i] != '.' || i == 0 || i + 2 >= length) return@any false
        if (!this[i - 1].isLetterOrDigit() || !this[i + 1].isLetterOrDigit()) return@any false
        var tld = 0
        var j = i + 1
        while (j < length && this[j].isLetter()) {
            tld += 1
            j += 1
        }
        tld >= 2
    }

private fun String.isLatinTokenBreakAfter(index: Int, keepUrlScheme: Boolean): Boolean {
    if (index !in 0 until lastIndex) return false
    return when (this[index]) {
        '/' -> !keepUrlScheme || getOrNull(index - 1) != ':'
        '.', '-', '_', '?', '&', '=', '#', '%', '~' -> true
        else -> false
    }
}

/**
 * `BibliographicNumericLocatorBreak`: a volume(issue):page-range locator is
 * structured Western text, not one indivisible opaque token. Expose clean
 * breaks before the issue group and after the colon while keeping every
 * digit run and the page range itself intact.
 *
 * This is deliberately narrower than a general numeric parser: ordinary
 * decimals, thousands separators, dates, times, and short identifiers keep
 * their existing cohesion rules.
 */
private fun String.bibliographicNumericLocatorBreakOffsets(): List<Int> {
    val open = indexOf('(')
    if (open <= 0 || this[0].isDigit().not()) return emptyList()
    val close = indexOf(')', startIndex = open + 1)
    if (close <= open + 1) return emptyList()
    val colon = indexOf(':', startIndex = close + 1)
    if (colon != close + 1 || colon >= lastIndex) return emptyList()

    val volume = substring(0, open)
    val issue = substring(open + 1, close)
    val pages = substring(colon + 1).removeSuffix(".")
    if (volume.isEmpty() || issue.isEmpty() || pages.isEmpty()) return emptyList()
    if (!volume.all(Char::isDigit) || !issue.all(Char::isDigit)) return emptyList()

    val rangeSeparator = pages.indexOfFirst { it == '-' || it == '\u2013' || it == '\u2014' }
    val pagesAreNumeric = if (rangeSeparator < 0) {
        pages.all(Char::isDigit)
    } else {
        rangeSeparator > 0 &&
            rangeSeparator < pages.lastIndex &&
            pages.substring(0, rangeSeparator).all(Char::isDigit) &&
            pages.substring(rangeSeparator + 1).all(Char::isDigit)
    }
    if (!pagesAreNumeric) return emptyList()

    return listOf(open, colon + 1)
}

private fun String.hasBreakableLatinSolidus(): Boolean =
    indices.any { i ->
        this[i] == '/' &&
            i > 0 &&
            i < lastIndex &&
            this[i - 1].isLetterOrDigit() &&
            this[i + 1].isLetterOrDigit()
    }

private fun mandatoryBreakShapingResult(text: String, range: TextRange): ShapingResult {
    val sourceText = text.substring(range.start, range.end)
    val cluster = Cluster(
        range = range,
        text = sourceText,
        displayText = "",
        fontKey = MANDATORY_BREAK_FONT_KEY,
        advance = 0f,
    )
    return ShapingResult(
        clusters = listOf(cluster),
        glyphRuns = emptyList(),
        decisions = emptyList(),
    )
}

private fun zeroWidthSoftBreakShapingResult(text: String, range: TextRange): ShapingResult {
    val sourceText = text.substring(range.start, range.end)
    val cluster = Cluster(
        range = range,
        text = sourceText,
        displayText = "",
        fontKey = ZERO_WIDTH_SOFT_BREAK_FONT_KEY,
        advance = 0f,
    )
    return ShapingResult(
        clusters = listOf(cluster),
        glyphRuns = emptyList(),
        decisions = listOf(
            ShapingDecisionInfo(
                range = range,
                sourceText = sourceText,
                displayText = "",
                fontKey = ZERO_WIDTH_SOFT_BREAK_FONT_KEY,
                glyphCount = 0,
                advance = 0f,
                source = "StructuralControl",
                reason = "ZeroWidthSpaceSoftBreakNoShape",
            ),
        ),
    )
}

private fun inlineObjectShapingResult(text: String, inlineObject: InlineObjectSpan): ShapingResult {
    val sourceText = text.substring(inlineObject.range.start, inlineObject.range.end)
    return ShapingResult(
        clusters = listOf(
            Cluster(
                range = inlineObject.range,
                text = sourceText,
                displayText = "",
                fontKey = INLINE_OBJECT_FONT_KEY,
                advance = inlineObject.advance,
            ),
        ),
        glyphRuns = emptyList(),
        decisions = listOf(
            ShapingDecisionInfo(
                range = inlineObject.range,
                sourceText = sourceText,
                displayText = "",
                fontKey = INLINE_OBJECT_FONT_KEY,
                glyphCount = 0,
                advance = inlineObject.advance,
                source = "InlineObject",
                reason = "MeasurableOpaqueInlineObject:no-font-shaping",
            ),
        ),
    )
}

internal fun Cluster.isMandatoryBreakCluster(): Boolean =
    fontKey == MANDATORY_BREAK_FONT_KEY && displayText.isEmpty()

internal fun Cluster.isZeroWidthSoftBreakCluster(): Boolean =
    fontKey == ZERO_WIDTH_SOFT_BREAK_FONT_KEY && displayText.isEmpty()

internal fun Cluster.isInlineObjectCluster(): Boolean = fontKey == INLINE_OBJECT_FONT_KEY

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

// Glyph advances stay the shaper's NATURAL values — cluster-level spacing
// (autospace / justify / push-in) lives at the positioning layer, never
// smeared across interior glyphs (that smearing was the bug squeezing the
// letters of slash-led runs like `/TERFism`). The one exception is the
// degenerate no-ink fallback (missing-glyph fonts return 0 advance): there
// we distribute the cluster body so glyphs don't stack at one x.
internal fun List<Glyph>.mapToClusterRange(cluster: Cluster): List<Glyph> {
    val sourceAdvance = sumOf { it.advance.toDouble() }.toFloat()
    if (sourceAdvance <= 0f) {
        val fallbackAdvance = cluster.advance / size.coerceAtLeast(1)
        return map { it.copy(advance = fallbackAdvance, clusterRange = cluster.range) }
    }
    return map { glyph -> glyph.copy(clusterRange = cluster.range) }
}

private const val ZERO_WIDTH_SOFT_BREAK_FONT_KEY = "zero-width-space"

private const val INLINE_OBJECT_FONT_KEY = "inline-object"

/** `DashSubstitutionInkCoverageRollback`: keep `⸺` only if its ink fills ≥85% of the 2em advance (Pixel Noto ≈80% rolls back; Source Han ≈94% keeps). */
private const val DASH_SUBSTITUTION_MIN_INK_COVERAGE = 0.85f

private const val DASH_SUBSTITUTION_TARGET_EM = 2f

/** `LatinForcedHyphenBreak` 硬断时尽量满足的左右边界（前二后三，同 en-US 连字）. */
private const val HYPHEN_MIN_LEFT = 2

private const val HYPHEN_MIN_RIGHT = 3

/** `LatinOpaqueTokenBreak`: long non-lexical Latin tokens expose clean no-hyphen breakpoints. */
private const val LATIN_OPAQUE_TOKEN_MIN_LENGTH = 24

/** Strong non-lexical evidence threshold for emergency tracking authorization. */
private const val EMERGENCY_TRACKING_TOKEN_MIN_LENGTH = 12

/** `ProgressiveTechnicalStructuralBreak`: separators that stay on the previous line. */
private val PROGRESSIVE_TECHNICAL_BREAK_AFTER_CHARS: Set<Char> =
    setOf('/', '\\', '.', '-', '_', ':', ';', ',', '?', '&', '=', '#', '%', '~', '+', '*', '|', ')', ']', '}')
