package org.tiqian.layout;

using org.tiqian.layout.ProgressiveBreakTierPriority;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.core.Glyph;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.font.FontPolicy.FallbackResolver;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontPolicy.FontRequest;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingIssue;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.clreq.ClreqPunctuationPolicies;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.ContextualPunctuationDisplaySubstitution.ContextualPunctuationDisplaySubstitutionFns;
import org.tiqian.layout.ParagraphShapingStage.ParagraphShapingStageResult;
import std.SortedSet;
import std.SortedMap;

/**
 * `ParagraphShapingSession`: the state of one `ParagraphShapingStage.shapeParagraph` call. The
 * fields hold the call's inputs, the segment shaping cache and substitution rollbacks seeded from
 * the previous call, and the results collected while the clusters are shaped (shaping results,
 * hyphen offsets and glyphs, break-opportunity and emergency-tracking decisions, progressive break
 * offsets). The methods were local functions of `shapeParagraph` that read and wrote those values.
 *
 * `run` shapes every resolved cluster range in order and returns the stage result;
 * `LatinSegmentBreakPlanner` computes the break offsets of each segment and calls back the public
 * methods. The session keeps the engine's text shaper and fallback resolver instead of the
 * engine; see `LineAdjustmentStage` for boring's Rust field projection of functions that receive
 * the engine.
 *
 * Each method copies the read-only fields it reads into locals of the same name before its first
 * statement. boring's Rust target renders a field used as a method receiver or mutated in place
 * as `this.borrow_mut().field` (`RustExpr.hx` near line 9887 at generator revision 4a87c173) and
 * keeps that guard for the whole statement, so a field read in the same statement panicked with
 * "RefCell already borrowed". The mutable collections stay fields: Rust copies an array read
 * into a local.
 */
class ParagraphShapingSession {
    public final textShaper:TextShaper;
    public final fallbackResolver:FallbackResolver;
    public final input:LayoutInput;
    public final text:String;
    public final fontSize:Float;
    public final measure:Float;
    public final clusterRanges:Array<ResolvedClusterRange>;
    public final fontDecisionByRange:SortedMap<TextRange, FontDecision>;
    public final inlineObjectByRange:SortedMap<TextRange, InlineObjectSpan>;
    public final punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor;
    public final styleAt:Int->TextStyle;
    public final emphasisItalicAt:Int->Bool;
    public final rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>;

    final segmentShapingCacheKeys:Array<TextRange>;
    final segmentShapingCacheValues:Array<ShapingResult>;
    final substitutionRollbackKeys:Array<TextRange>;
    final substitutionRollbackValues:Array<String>;
    final hyphenOffsets:Array<Int>;
    var hyphenAdvanceOrNull:Null<Float>;
    var hyphenGlyphs:Array<Glyph>;
    final breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>;
    final emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>;
    final progBreakKeys:Array<Int>;
    final progBreakValues:Array<ProgressiveBreakOpportunity>;
    final spanAdvanceCacheKeys:Array<TextRange>;
    final spanAdvanceCacheValues:Array<Float>;
    final shapingResults:Array<ShapingResult>;

    public function new(textShaper:TextShaper, fallbackResolver:FallbackResolver, input:LayoutInput, text:String, fontSize:Float, measure:Float,
            clusterRanges:Array<ResolvedClusterRange>, fontDecisionByRange:SortedMap<TextRange, FontDecision>,
            inlineObjectByRange:SortedMap<TextRange, InlineObjectSpan>, punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor, styleAt:Int->TextStyle,
            emphasisItalicAt:Int->Bool, rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>,
            cachedSegmentShaping:Null<SortedMap<TextRange, ShapingResult>>, cachedSubstitutionRollbacks:Null<SortedMap<TextRange, String>>) {
        this.textShaper = textShaper;
        this.fallbackResolver = fallbackResolver;
        this.input = input;
        this.text = text;
        this.fontSize = fontSize;
        this.measure = measure;
        this.clusterRanges = clusterRanges;
        this.fontDecisionByRange = fontDecisionByRange;
        this.inlineObjectByRange = inlineObjectByRange;
        this.punctuationGlyphSubstitutor = punctuationGlyphSubstitutor;
        this.styleAt = styleAt;
        this.emphasisItalicAt = emphasisItalicAt;
        this.rejectedTechnicalTiersBySpan = rejectedTechnicalTiersBySpan;

        final segmentShapingCacheKeys = new Array<TextRange>();
        final segmentShapingCacheValues = new Array<ShapingResult>();
        if (cachedSegmentShaping != null) {
            for (i in 0...cachedSegmentShaping.size()) {
                segmentShapingCacheKeys.push(cachedSegmentShaping.keyAt(i));
                segmentShapingCacheValues.push(cachedSegmentShaping.valueAt(i));
            }
        }
        this.segmentShapingCacheKeys = segmentShapingCacheKeys;
        this.segmentShapingCacheValues = segmentShapingCacheValues;

        final substitutionRollbackKeys = new Array<TextRange>();
        final substitutionRollbackValues = new Array<String>();
        if (cachedSubstitutionRollbacks != null) {
            for (i in 0...cachedSubstitutionRollbacks.size()) {
                substitutionRollbackKeys.push(cachedSubstitutionRollbacks.keyAt(i));
                substitutionRollbackValues.push(cachedSubstitutionRollbacks.valueAt(i));
            }
        }
        this.substitutionRollbackKeys = substitutionRollbackKeys;
        this.substitutionRollbackValues = substitutionRollbackValues;

        this.hyphenOffsets = new Array<Int>();
        this.hyphenAdvanceOrNull = null;
        this.hyphenGlyphs = new Array<Glyph>();
        this.breakOpportunityDecisions = new Array<BreakOpportunityDecisionInfo>();
        this.emergencyTrackingEligibilityDecisions = new Array<EmergencyTrackingEligibilityDecisionInfo>();
        this.progBreakKeys = new Array<Int>();
        this.progBreakValues = new Array<ProgressiveBreakOpportunity>();
        this.spanAdvanceCacheKeys = new Array<TextRange>();
        this.spanAdvanceCacheValues = new Array<Float>();
        this.shapingResults = new Array<ShapingResult>();
    }

    /** Records one break-opportunity decision; `LatinSegmentBreakPlanner` reports through it. */
    public function recordBreakOpportunity(decision:BreakOpportunityDecisionInfo):Void {
        breakOpportunityDecisions.push(decision);
    }


    // Segments are shaped in text order, so the entry a range needs is the
    // last one, and a range past it is new. Both cases are constant; only an
    // out-of-order range falls back to the scan. The unconditional scans
    // cost segments x keys.
    function getCachedSegmentShaping(r:TextRange):Null<ShapingResult> {
        final keyCount = segmentShapingCacheKeys.length;
        if (keyCount > 0) {
            final lastKey = segmentShapingCacheKeys[keyCount - 1];
            if (lastKey.start == r.start && lastKey.end == r.end)
                return segmentShapingCacheValues[keyCount - 1];
            if (r.start > lastKey.start)
                return null;
        }
        for (i in 0...segmentShapingCacheKeys.length) {
            final k = segmentShapingCacheKeys[i];
            if (k.start == r.start && k.end == r.end)
                return segmentShapingCacheValues[i];
        }
        return null;
    }

    function putCachedSegmentShaping(r:TextRange, v:ShapingResult):Void {
        final keyCount = segmentShapingCacheKeys.length;
        if (keyCount > 0) {
            final lastKey = segmentShapingCacheKeys[keyCount - 1];
            if (lastKey.start == r.start && lastKey.end == r.end) {
                segmentShapingCacheValues[keyCount - 1] = v;
                return;
            }
            if (r.start > lastKey.start) {
                segmentShapingCacheKeys.push(r);
                segmentShapingCacheValues.push(v);
                return;
            }
        }
        // boring Rust: a loop range that reads a field keeps `this.borrow()` for the whole loop, so a
        // loop whose body writes a field iterates over the length read before it.
        for (i in 0...keyCount) {
            final k = segmentShapingCacheKeys[i];
            if (k.start == r.start && k.end == r.end) {
                segmentShapingCacheValues[i] = v;
                return;
            }
        }
        segmentShapingCacheKeys.push(r);
        segmentShapingCacheValues.push(v);
    }

    function putSubstitutionRollback(r:TextRange, v:String):Void {
        final keyCount = substitutionRollbackKeys.length;
        if (keyCount > 0) {
            final lastKey = substitutionRollbackKeys[keyCount - 1];
            if (lastKey.start == r.start && lastKey.end == r.end) {
                substitutionRollbackValues[keyCount - 1] = v;
                return;
            }
            if (r.start > lastKey.start) {
                substitutionRollbackKeys.push(r);
                substitutionRollbackValues.push(v);
                return;
            }
        }
        // boring Rust: a loop range that reads a field keeps `this.borrow()` for the whole loop, so a
        // loop whose body writes a field iterates over the length read before it.
        for (i in 0...keyCount) {
            final k = substitutionRollbackKeys[i];
            if (k.start == r.start && k.end == r.end) {
                substitutionRollbackValues[i] = v;
                return;
            }
        }
        substitutionRollbackKeys.push(r);
        substitutionRollbackValues.push(v);
    }

    function dashInkCoverageDeficient(shaped:ShapingResult, displayText:String, segmentFontSize:Float):Bool {
        if (displayText.indexOf("\u2E3A") < 0)
            return false;
        var totalGlyphs = 0;
        var singleGlyph:Null<Glyph> = null;
        for (i in 0...shaped.glyphRuns.length) {
            final r = shaped.glyphRuns[i];
            for (j in 0...r.glyphs.length) {
                totalGlyphs++;
                singleGlyph = r.glyphs[j];
            }
        }
        if (totalGlyphs != 1 || singleGlyph == null)
            return false;
        final ink = singleGlyph.bounds;
        if (ink == null)
            return false;
        final targetAdvance = ParagraphShapingStage.DASH_SUBSTITUTION_TARGET_EM * segmentFontSize;
        return (ink.right - ink.left) < targetAdvance * ParagraphShapingStage.DASH_SUBSTITUTION_MIN_INK_COVERAGE;
    }

    public function shapeSegment(decision:FontDecision, segmentRange:TextRange):ShapingResult {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final textShaper = this.textShaper;
        final text = this.text;
        final punctuationGlyphSubstitutor = this.punctuationGlyphSubstitutor;
        final styleAt = this.styleAt;
        final emphasisItalicAt = this.emphasisItalicAt;
        final cached = getCachedSegmentShaping(segmentRange);
        if (cached != null)
            return cached;
        final sourceText = text.substring(segmentRange.start, segmentRange.end);
        final substitution = ContextualPunctuationDisplaySubstitutionFns.substituteForRole(punctuationGlyphSubstitutor, sourceText, decision.role);
        final baseSegmentStyle = styleAt(segmentRange.start);
        var segmentStyle = baseSegmentStyle;
        if (decision.role == FontRole.LatinText && emphasisItalicAt(segmentRange.start)) {
            segmentStyle = new TextStyle(ParagraphShapingStage.copyFontFamilies(baseSegmentStyle.fontFamilies), baseSegmentStyle.fontSize, baseSegmentStyle.locale,
                baseSegmentStyle.fontWeight, true, baseSegmentStyle.baselineShift, baseSegmentStyle.inlineAttachment);
        }
        final shaped = textShaper.shape(new ShapingInput(text, segmentRange, segmentStyle, decision, substitution.displayText,
            ParagraphShapingStage.cjkPunctuationFullWidthFeatures(decision.role, substitution.displayText)));
        var rollbackCause:Null<String> = null;
        if (substitution.displayText != sourceText) {
            var hasUnverified = false;
            var hasMissing = false;
            for (i in 0...shaped.decisions.length) {
                final d = shaped.decisions[i];
                if (d.capabilityIssue == ShapingIssue.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE) {
                    hasUnverified = true;
                }
                if (d.missingGlyphs > 0) {
                    hasMissing = true;
                }
            }
            if (hasUnverified) {
                rollbackCause = "SubstitutionRollbackOnUnverifiedGlyphCoverage";
            } else if (hasMissing) {
                rollbackCause = "SubstitutionRollbackOnMissingGlyph";
            } else if (dashInkCoverageDeficient(shaped, substitution.displayText, segmentStyle.fontSize)) {
                rollbackCause = "DashSubstitutionInkCoverageRollback";
            }
        }
        var result:ShapingResult = shaped;
        if (rollbackCause != null) {
            putSubstitutionRollback(segmentRange, rollbackCause);
            result = textShaper.shape(new ShapingInput(text, segmentRange, segmentStyle, decision, sourceText,
                ParagraphShapingStage.cjkPunctuationFullWidthFeatures(decision.role, sourceText)));
        }
        putCachedSegmentShaping(segmentRange, result);
        return result;
    }

    function shapeSegmentWithPointMarkPrefix(decision:FontDecision, segmentRange:TextRange):Array<ShapingResult> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final text = this.text;
        var prefixEnd = segmentRange.start;
        while (prefixEnd < segmentRange.end && ClreqPunctuationPolicies.isAsciiPointMark(text.charAt(prefixEnd))) {
            prefixEnd += 1;
        }
        if (prefixEnd > segmentRange.start && prefixEnd < segmentRange.end) {
            return [
                shapeSegment(decision, new TextRange(segmentRange.start, prefixEnd)),
                shapeSegment(decision, new TextRange(prefixEnd, segmentRange.end))
            ];
        } else {
            return [shapeSegment(decision, segmentRange)];
        }
    }

    public function registerEmergencyTrackingEligibility(range:TextRange, reason:String):Void {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final text = this.text;
        for (i in 0...emergencyTrackingEligibilityDecisions.length) {
            final d = emergencyTrackingEligibilityDecisions[i];
            if (d.range.start == range.start && d.range.end == range.end && d.reason == reason) {
                return;
            }
        }
        emergencyTrackingEligibilityDecisions.push(new EmergencyTrackingEligibilityDecisionInfo(range, text.substring(range.start, range.end), reason));
    }

    public function putProgressiveBreak(offset:Int, opp:ProgressiveBreakOpportunity):Void {
        // boring Rust: a loop range that reads a field keeps `this.borrow()` for the whole loop, so a
        // loop whose body writes a field iterates over the length read before it.
        final keyCount = progBreakKeys.length;
        for (i in 0...keyCount) {
            if (progBreakKeys[i] == offset) {
                final current = progBreakValues[i];
                if (opp.tier.priority() < current.tier.priority()) {
                    progBreakValues[i] = opp;
                }
                return;
            }
        }
        progBreakKeys.push(offset);
        progBreakValues.push(opp);
    }

    function getInlineObject(range:TextRange):Null<InlineObjectSpan> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final inlineObjectByRange = this.inlineObjectByRange;
        if (inlineObjectByRange == null)
            return null;
        for (i in 0...inlineObjectByRange.size()) {
            final k = inlineObjectByRange.keyAt(i);
            if (k.start == range.start && k.end == range.end)
                return inlineObjectByRange.valueAt(i);
        }
        return null;
    }

    function getFontDecision(range:TextRange):Null<FontDecision> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final fontDecisionByRange = this.fontDecisionByRange;
        if (fontDecisionByRange == null)
            return null;
        for (i in 0...fontDecisionByRange.size()) {
            final k = fontDecisionByRange.keyAt(i);
            if (k.start == range.start && k.end == range.end)
                return fontDecisionByRange.valueAt(i);
        }
        return null;
    }

    public function getRejectedTiers(range:TextRange):Null<SortedSet<Int>> {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final rejectedTechnicalTiersBySpan = this.rejectedTechnicalTiersBySpan;
        if (rejectedTechnicalTiersBySpan == null)
            return null;
        for (i in 0...rejectedTechnicalTiersBySpan.size()) {
            final k = rejectedTechnicalTiersBySpan.keyAt(i);
            if (k.start == range.start && k.end == range.end)
                return rejectedTechnicalTiersBySpan.valueAt(i);
        }
        return null;
    }

    public function progressiveSpanAdvance(spanRange:TextRange):Float {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final text = this.text;
        final clusterRanges = this.clusterRanges;
        for (i in 0...spanAdvanceCacheKeys.length) {
            final k = spanAdvanceCacheKeys[i];
            if (k.start == spanRange.start && k.end == spanRange.end)
                return spanAdvanceCacheValues[i];
        }
        final advanceTerms:Array<Float> = [];
        for (crIdx in 0...clusterRanges.length) {
            final resolvedRange = clusterRanges[crIdx];
            if (resolvedRange.mandatoryBreak || resolvedRange.zeroWidthSoftBreak || getInlineObject(resolvedRange.range) != null) {
                continue;
            }
            final decision = getFontDecision(resolvedRange.range);
            if (decision == null)
                continue;
            final candidates = ParagraphShapingStage.shapingSegments(decision, text);
            for (cIdx in 0...candidates.length) {
                final candidate = candidates[cIdx];
                final start = candidate.start > spanRange.start ? candidate.start : spanRange.start;
                final end = candidate.end < spanRange.end ? candidate.end : spanRange.end;
                if (start < end) {
                    final pieceShaped = shapeSegment(decision, new TextRange(start, end));
                    for (clIdx in 0...pieceShaped.clusters.length) {
                        advanceTerms.push(pieceShaped.clusters[clIdx].advance);
                    }
                }
            }
        }
        final totalAdvance = AccurateSum.of(advanceTerms);
        spanAdvanceCacheKeys.push(spanRange);
        spanAdvanceCacheValues.push(totalAdvance);
        return totalAdvance;
    }

    /** Shapes every resolved cluster range in order and returns the collected stage result. */
    public function run(planner:LatinSegmentBreakPlanner):ParagraphShapingStageResult {
        // boring Rust: a statement that mutates a field of `this` holds `this.borrow_mut()`, so the
        // read-only fields it reads are copied to locals first (see the class comment).
        final textShaper = this.textShaper;
        final fallbackResolver = this.fallbackResolver;
        final input = this.input;
        final text = this.text;
        final fontSize = this.fontSize;
        final clusterRanges = this.clusterRanges;
        for (crIdx in 0...clusterRanges.length) {
            final resolvedRange = clusterRanges[crIdx];
            final inlineObj = getInlineObject(resolvedRange.range);
            if (inlineObj != null) {
                shapingResults.push(ParagraphShapingStage.inlineObjectShapingResult(text, inlineObj));
                continue;
            }
            if (resolvedRange.mandatoryBreak) {
                shapingResults.push(ParagraphShapingStage.mandatoryBreakShapingResult(text, resolvedRange.range));
                continue;
            }
            if (resolvedRange.zeroWidthSoftBreak) {
                shapingResults.push(ParagraphShapingStage.zeroWidthSoftBreakShapingResult(text, resolvedRange.range));
                continue;
            }
            var decision = getFontDecision(resolvedRange.range);
            if (decision == null) {
                decision = fallbackResolver.resolve(text, resolvedRange.range,
                    new FontRequest(input.textStyle.fontFamilies, input.textStyle.locale, resolvedRange.role));
            }
            final segments = ParagraphShapingStage.shapingSegments(decision, text);
            for (segIdx in 0...segments.length) {
                final segmentRange = segments[segIdx];
                final shaped = shapeSegment(decision, segmentRange);
                final segmentCuts = planner.plan(decision, segmentRange, shaped);
                final allCuts = segmentCuts.allCuts;
                final hyphenCuts = segmentCuts.hyphenCuts;

                if (allCuts.length == 0) {
                    shapingResults.push(shaped);
                } else {
                    if (hyphenCuts.length > 0) {
                        for (c in 0...hyphenCuts.length) {
                            final cut = hyphenCuts[c];
                            var exists = false;
                            for (q in 0...hyphenOffsets.length) {
                                if (hyphenOffsets[q] == cut) {
                                    exists = true;
                                    break;
                                }
                            }
                            if (!exists)
                                hyphenOffsets.push(cut);
                        }
                        if (hyphenAdvanceOrNull == null) {
                            final hyphenShaped = textShaper.shape(new ShapingInput("-", new TextRange(0, 1), input.textStyle, decision, "-"));
                            hyphenAdvanceOrNull = hyphenShaped.clusters.length == 1 ? hyphenShaped.clusters[0].advance : (0.5 * fontSize);
                            hyphenGlyphs = new Array<Glyph>();
                            for (r in 0...hyphenShaped.glyphRuns.length) {
                                final run = hyphenShaped.glyphRuns[r];
                                for (g in 0...run.glyphs.length) {
                                    hyphenGlyphs.push(run.glyphs[g]);
                                }
                            }
                        }
                    }
                    final bounds = [segmentRange.start];
                    for (c in 0...allCuts.length)
                        bounds.push(allCuts[c]);
                    bounds.push(segmentRange.end);

                    for (k in 0...(bounds.length - 1)) {
                        final pieces = shapeSegmentWithPointMarkPrefix(decision, new TextRange(bounds[k], bounds[k + 1]));
                        for (p in 0...pieces.length) {
                            shapingResults.push(pieces[p]);
                        }
                    }
                }
            }
        }

        final hyphenAdvance = hyphenAdvanceOrNull != null ? hyphenAdvanceOrNull : 0.0;

        final hyphenOffsetsBuilder = SortedSet.builder();
        for (i in 0...hyphenOffsets.length)
            hyphenOffsetsBuilder.put(hyphenOffsets[i]);
        final hyphenOffsetsSet = hyphenOffsetsBuilder.build();

        final rollbacksBuilder = SortedMap.builder();
        for (i in 0...substitutionRollbackKeys.length)
            rollbacksBuilder.put(substitutionRollbackKeys[i], substitutionRollbackValues[i]);
        final rollbacksMap = rollbacksBuilder.build();

        final progOffsetsBuilder = SortedMap.builder();
        for (i in 0...progBreakKeys.length)
            progOffsetsBuilder.put(progBreakKeys[i], progBreakValues[i]);
        final progOffsetsMap = progOffsetsBuilder.build();

        final segmentCacheBuilder = SortedMap.builder();
        for (i in 0...segmentShapingCacheKeys.length)
            segmentCacheBuilder.put(segmentShapingCacheKeys[i], segmentShapingCacheValues[i]);
        final segmentCacheMap = segmentCacheBuilder.build();

        return new ParagraphShapingStageResult(shapingResults, hyphenOffsetsSet, hyphenAdvance, hyphenGlyphs, rollbacksMap, breakOpportunityDecisions,
            emergencyTrackingEligibilityDecisions, progOffsetsMap, segmentCacheMap);
    }
}
