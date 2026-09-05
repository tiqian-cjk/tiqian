package org.tiqian.layout;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.core.Glyph;
import org.tiqian.core.Cluster;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.LineBreakPolicy;
import org.tiqian.core.SourceInteractionBoundaries;
import org.tiqian.core.UnicodeWordCharacterData;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontPolicy.FontRequest;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.clreq.ClreqPunctuationPolicies;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.ParagraphLayoutEngine.ParagraphLayoutEngineFns;
import org.tiqian.layout.ContextualPunctuationDisplaySubstitution.ContextualPunctuationDisplaySubstitutionFns;
import std.SortedSet;
import std.SortedMap;

@:dataClass class ParagraphShapingStageResult {
    public final shapingResults:Array<ShapingResult>;
    public final hyphenOffsets:SortedSet<Int>;
    public final hyphenAdvance:Float;
    public final hyphenGlyphs:Array<Glyph>;
    public final substitutionRollbacks:SortedMap<TextRange, String>;
    public final breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>;
    public final emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>;
    public final progressiveBreakOffsets:SortedMap<Int, ProgressiveBreakOpportunity>;
    public final segmentShapingCache:SortedMap<TextRange, ShapingResult>;

    public function new(shapingResults:Array<ShapingResult>, hyphenOffsets:SortedSet<Int>, hyphenAdvance:Float, hyphenGlyphs:Array<Glyph>,
            substitutionRollbacks:SortedMap<TextRange, String>, breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>,
            emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>,
            progressiveBreakOffsets:SortedMap<Int, ProgressiveBreakOpportunity>, ?segmentShapingCache:SortedMap<TextRange, ShapingResult>) {
        this.shapingResults = shapingResults;
        this.hyphenOffsets = hyphenOffsets;
        this.hyphenAdvance = hyphenAdvance;
        this.hyphenGlyphs = hyphenGlyphs;
        this.substitutionRollbacks = substitutionRollbacks;
        this.breakOpportunityDecisions = breakOpportunityDecisions;
        this.emergencyTrackingEligibilityDecisions = emergencyTrackingEligibilityDecisions;
        this.progressiveBreakOffsets = progressiveBreakOffsets;
        this.segmentShapingCache = segmentShapingCache == null ? SortedMap.builder().build() : segmentShapingCache;
    }
}

class ParagraphShapingStage {
    public static inline final ZERO_WIDTH_SOFT_BREAK_FONT_KEY:String = "zero-width-space";
    public static inline final INLINE_OBJECT_FONT_KEY:String = "inline-object";
    public static inline final DASH_SUBSTITUTION_MIN_INK_COVERAGE:Float = 0.85;
    public static inline final DASH_SUBSTITUTION_TARGET_EM:Float = 2.0;
    public static inline final HYPHEN_MIN_LEFT:Int = 2;
    public static inline final HYPHEN_MIN_RIGHT:Int = 3;
    public static inline final LATIN_OPAQUE_TOKEN_MIN_LENGTH:Int = 24;
    public static inline final EMERGENCY_TRACKING_TOKEN_MIN_LENGTH:Int = 12;

    public static function isDigit(c:Int):Bool {
        return c >= 48 && c <= 57;
    }

    public static function isLetter(c:Int):Bool {
        return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (UnicodeWordCharacterData.contains(c) && !isDigit(c));
    }

    public static function isLetterOrDigit(c:Int):Bool {
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || UnicodeWordCharacterData.contains(c);
    }

    public static function isUpperCase(c:Int):Bool {
        return c >= 65 && c <= 90;
    }

    public static function isLowerCase(c:Int):Bool {
        return c >= 97 && c <= 122;
    }

    public static function isWhitespace(c:Int):Bool {
        return (c >= 0x0009 && c <= 0x000D) || c == 0x0020 || c == 0x00A0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
            || c == 0x202F || c == 0x205F || c == 0x3000;
    }

    public static function isAllDigits(s:String):Bool {
        if (s.length == 0)
            return false;
        for (i in 0...s.length) {
            final c = s.charCodeAt(i);
            if (c < 48 || c > 57)
                return false;
        }
        return true;
    }

    public static function isSharedCurlyQuote(c:Int):Bool {
        return c == 0x2018 || c == 0x2019 || c == 0x201C || c == 0x201D;
    }

    public static function isProgressiveTechnicalBreakAfterChar(c:Int):Bool {
        return c == 47 || c == 92 || c == 46 || c == 45 || c == 95 || c == 58 || c == 59 || c == 44 || c == 63 || c == 38 || c == 61 || c == 35 || c == 37
            || c == 126 || c == 43 || c == 42 || c == 124 || c == 41 || c == 93 || c == 125;
    }

    public static function sortInts(arr:Array<Int>):Void {
        var i = 1;
        while (i < arr.length) {
            final current = arr[i];
            var j = i - 1;
            while (j >= 0 && arr[j] > current) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = current;
            i++;
        }
    }

    public static function tierName(tier:ProgressiveBreakTier):String {
        if (tier == ProgressiveBreakTier.Whitespace)
            return "Whitespace";
        if (tier == ProgressiveBreakTier.Structural)
            return "Structural";
        if (tier == ProgressiveBreakTier.Syllable)
            return "Syllable";
        if (tier == ProgressiveBreakTier.WholeToken)
            return "WholeToken";
        if (tier == ProgressiveBreakTier.Emergency)
            return "Emergency";
        return "Unknown";
    }

    public static function cjkPunctuationFullWidthFeatures(role:FontRole, displayText:String):Array<String> {
        if (role == FontRole.CjkPunctuation) {
            for (i in 0...displayText.length) {
                final c = displayText.charCodeAt(i);
                if (isSharedCurlyQuote(c)) {
                    return ["fwid=1"];
                }
            }
        }
        return [];
    }

    public static function isUrlLikeLatinToken(token:String):Bool {
        final lower = token.toLowerCase();
        return token.indexOf("://") >= 0 || StringTools.startsWith(lower, "www.") || hasDomainLikeDot(token);
    }

    public static function hasDomainLikeDot(token:String):Bool {
        for (i in 0...token.length) {
            if (token.charCodeAt(i) != 46 || i == 0 || i + 2 >= token.length) {
                continue;
            }
            if (!isLetterOrDigit(token.charCodeAt(i - 1)) || !isLetterOrDigit(token.charCodeAt(i + 1))) {
                continue;
            }
            var tld = 0;
            var j = i + 1;
            while (j < token.length && isLetter(token.charCodeAt(j))) {
                tld += 1;
                j += 1;
            }
            if (tld >= 2) {
                return true;
            }
        }
        return false;
    }

    public static function isLatinTokenBreakAfter(token:String, index:Int, keepUrlScheme:Bool):Bool {
        if (index < 0 || index >= token.length - 1)
            return false;
        final c = token.charCodeAt(index);
        if (c == 47) {
            return !keepUrlScheme || (index == 0 || token.charCodeAt(index - 1) != 58);
        }
        if (c == 46 || c == 45 || c == 95 || c == 63 || c == 38 || c == 61 || c == 35 || c == 37 || c == 126) {
            return true;
        }
        return false;
    }

    public static function bibliographicNumericLocatorBreakOffsets(token:String):Array<Int> {
        final open = token.indexOf("(");
        if (open <= 0 || !isDigit(token.charCodeAt(0)))
            return [];
        final close = token.indexOf(")", open + 1);
        if (close <= open + 1)
            return [];
        final colon = token.indexOf(":", close + 1);
        if (colon != close + 1 || colon >= token.length - 1)
            return [];

        final volume = token.substring(0, open);
        final issue = token.substring(open + 1, close);
        var pages = token.substring(colon + 1);
        if (StringTools.endsWith(pages, ".")) {
            pages = pages.substring(0, pages.length - 1);
        }
        if (volume.length == 0 || issue.length == 0 || pages.length == 0)
            return [];
        if (!isAllDigits(volume) || !isAllDigits(issue))
            return [];

        var rangeSeparator = -1;
        for (i in 0...pages.length) {
            final c = pages.charCodeAt(i);
            if (c == 45 || c == 0x2013 || c == 0x2014) {
                rangeSeparator = i;
                break;
            }
        }
        final pagesAreNumeric = if (rangeSeparator < 0) {
            isAllDigits(pages);
        } else {
            rangeSeparator > 0
            && rangeSeparator < pages.length - 1
            && isAllDigits(pages.substring(0, rangeSeparator))
            && isAllDigits(pages.substring(rangeSeparator + 1));
        };
        if (!pagesAreNumeric)
            return [];

        return [open, colon + 1];
    }

    public static function hasBreakableLatinSolidus(token:String):Bool {
        for (i in 1...(token.length - 1)) {
            if (token.charCodeAt(i) == 47 && isLetterOrDigit(token.charCodeAt(i - 1)) && isLetterOrDigit(token.charCodeAt(i + 1))) {
                return true;
            }
        }
        return false;
    }

    public static function existingHyphenCuts(text:String, wordRange:TextRange):Array<Int> {
        final w = text.substring(wordRange.start, wordRange.end);
        final cuts = new Array<Int>();
        for (i in 0...w.length) {
            if (w.charCodeAt(i) != 45)
                continue;
            var before = 0;
            var j = i - 1;
            while (j >= 0 && isLetter(w.charCodeAt(j))) {
                before += 1;
                j -= 1;
            }
            var after = 0;
            var k = i + 1;
            while (k < w.length && isLetter(w.charCodeAt(k))) {
                after += 1;
                k += 1;
            }
            if (before >= 2 && after >= 2)
                cuts.push(wordRange.start + i + 1);
        }
        return cuts;
    }

    public static function camelCaseCuts(text:String, wordRange:TextRange):Array<Int> {
        final w = text.substring(wordRange.start, wordRange.end);
        final humps = new Array<Int>();
        for (i in 1...w.length) {
            final c = w.charCodeAt(i);
            final prev = w.charCodeAt(i - 1);
            if (isUpperCase(c) && (isLowerCase(prev) || (isUpperCase(prev) && i + 1 < w.length && isLowerCase(w.charCodeAt(i + 1))))) {
                humps.push(i);
            }
        }
        final bounds = [0];
        for (h in 0...humps.length)
            bounds.push(humps[h]);
        bounds.push(w.length);

        final result = new Array<Int>();
        for (idx in 0...humps.length) {
            final h = humps[idx];
            var lastBefore = 0;
            for (b in 0...bounds.length) {
                if (bounds[b] < h)
                    lastBefore = bounds[b];
            }
            var firstAfter = w.length;
            for (b in 0...bounds.length) {
                if (bounds[b] > h) {
                    firstAfter = bounds[b];
                    break;
                }
            }
            if (h - lastBefore >= 2 && firstAfter - h >= 2) {
                result.push(wordRange.start + h);
            }
        }
        return result;
    }

    public static function alphaNumericTransitionCuts(text:String, wordRange:TextRange):Array<Int> {
        final w = text.substring(wordRange.start, wordRange.end);
        final cuts = new Array<Int>();
        for (index in 1...w.length) {
            final left = w.charCodeAt(index - 1);
            final right = w.charCodeAt(index);
            if ((isLetter(left) && isDigit(right)) || (isDigit(left) && isLetter(right))) {
                cuts.push(wordRange.start + index);
            }
        }
        return cuts;
    }

    public static function strongNonLexicalReason(w:String):Null<String> {
        if (w.length < EMERGENCY_TRACKING_TOKEN_MIN_LENGTH)
            return null;
        var allLetters = true;
        final firstCharLower = w.charAt(0).toLowerCase();
        var allSameLetter = true;
        for (i in 0...w.length) {
            final c = w.charCodeAt(i);
            if (!isLetter(c)) {
                allLetters = false;
                allSameLetter = false;
            } else if (w.charAt(i).toLowerCase() != firstCharLower) {
                allSameLetter = false;
            }
        }
        if (allLetters && allSameLetter) {
            return "LongRepeatedLetterRun";
        }

        var anyLetter = false;
        var allHexOrDigit = true;
        for (i in 0...w.length) {
            final c = w.charCodeAt(i);
            if (isLetter(c))
                anyLetter = true;
            final isHexDigit = isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
            if (!isHexDigit) {
                allHexOrDigit = false;
            }
        }
        if (anyLetter && allHexOrDigit) {
            return "LongHexIdentityRun";
        }

        var anyDigit = false;
        for (i in 0...w.length) {
            if (isDigit(w.charCodeAt(i))) {
                anyDigit = true;
                break;
            }
        }
        if (anyLetter && anyDigit) {
            var transitions = 0;
            for (i in 0...(w.length - 1)) {
                final left = w.charCodeAt(i);
                final right = w.charCodeAt(i + 1);
                if ((isLetter(left) && isDigit(right)) || (isDigit(left) && isLetter(right))) {
                    transitions++;
                }
            }
            if (transitions >= 2) {
                return "LongMixedAlphaNumericIdentifier";
            }
        }
        return null;
    }

    public static function mandatoryBreakShapingResult(text:String, range:TextRange):ShapingResult {
        final sourceText = text.substring(range.start, range.end);
        final cluster = new Cluster(range, sourceText, ParagraphLayoutEngineFns.MANDATORY_BREAK_FONT_KEY, 0.0, "");
        return new ShapingResult([cluster], [], []);
    }

    public static function zeroWidthSoftBreakShapingResult(text:String, range:TextRange):ShapingResult {
        final sourceText = text.substring(range.start, range.end);
        final cluster = new Cluster(range, sourceText, ZERO_WIDTH_SOFT_BREAK_FONT_KEY, 0.0, "");
        final decision = new ShapingDecisionInfo(range, sourceText, "", ZERO_WIDTH_SOFT_BREAK_FONT_KEY, 0, 0.0, "StructuralControl",
            "ZeroWidthSpaceSoftBreakNoShape");
        return new ShapingResult([cluster], [], [decision]);
    }

    public static function inlineObjectShapingResult(text:String, inlineObject:InlineObjectSpan):ShapingResult {
        final sourceText = text.substring(inlineObject.range.start, inlineObject.range.end);
        final cluster = new Cluster(inlineObject.range, sourceText, INLINE_OBJECT_FONT_KEY, inlineObject.advance, "");
        final decision = new ShapingDecisionInfo(inlineObject.range, sourceText, "", INLINE_OBJECT_FONT_KEY, 0, inlineObject.advance, "InlineObject",
            "MeasurableOpaqueInlineObject:no-font-shaping");
        return new ShapingResult([cluster], [], [decision]);
    }

    public static function mapToClusterRange(glyphs:Array<Glyph>, cluster:Cluster):Array<Glyph> {
        var sourceAdvance = 0.0;
        for (i in 0...glyphs.length) {
            sourceAdvance += glyphs[i].advance;
        }
        if (sourceAdvance <= 0.0) {
            final count = glyphs.length > 1 ? glyphs.length : 1;
            final fallbackAdvance = cluster.advance / count;
            final result = new Array<Glyph>();
            for (i in 0...glyphs.length) {
                final g = glyphs[i];
                result.push(new Glyph(g.id, cluster.range, fallbackAdvance, g.x, g.y, g.renderFontKey, g.bounds, g.haltAdvance, g.haltPlacementX));
            }
            return result;
        }
        final result = new Array<Glyph>();
        for (i in 0...glyphs.length) {
            final g = glyphs[i];
            result.push(new Glyph(g.id, cluster.range, g.advance, g.x, g.y, g.renderFontKey, g.bounds, g.haltAdvance, g.haltPlacementX));
        }
        return result;
    }

    public static function isMandatoryBreakCluster(cluster:Cluster):Bool {
        return cluster.fontKey == ParagraphLayoutEngineFns.MANDATORY_BREAK_FONT_KEY && cluster.displayText.length == 0;
    }

    public static function isZeroWidthSoftBreakCluster(cluster:Cluster):Bool {
        return cluster.fontKey == ZERO_WIDTH_SOFT_BREAK_FONT_KEY && cluster.displayText.length == 0;
    }

    public static function isInlineObjectCluster(cluster:Cluster):Bool {
        return cluster.fontKey == INLINE_OBJECT_FONT_KEY;
    }

    public static function shapingSegments(decision:FontDecision, text:String):Array<TextRange> {
        if (decision.role != FontRole.LatinText)
            return [decision.range];
        final segments = new Array<TextRange>();
        var segStart = decision.range.start;
        var inSpace = text.charCodeAt(decision.range.start) == 32;
        var i = decision.range.start + 1;
        while (i < decision.range.end) {
            final isSpace = text.charCodeAt(i) == 32;
            if (isSpace != inSpace) {
                segments.push(new TextRange(segStart, i));
                segStart = i;
                inSpace = isSpace;
            }
            i++;
        }
        segments.push(new TextRange(segStart, decision.range.end));
        return segments;
    }

    private static function copyFontFamilies(families:std.ReadOnlyArray<String>):Array<String> {
        final result = new Array<String>();
        for (i in 0...families.length) {
            result.push(families[i]);
        }
        return result;
    }

    private static function copyInts(arr:Array<Int>):Array<Int> {
        final result = new Array<Int>();
        for (i in 0...arr.length) {
            result.push(arr[i]);
        }
        return result;
    }

    public static function shapeParagraph(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput, text:String, fontSize:Float, measure:Float,
            clusterRanges:Array<ResolvedClusterRange>, fontDecisionByRange:SortedMap<TextRange, FontDecision>,
            inlineObjectByRange:SortedMap<TextRange, InlineObjectSpan>, punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor, styleAt:Int->TextStyle,
            emphasisItalicAt:Int->Bool, rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>,
            ?cachedSegmentShaping:SortedMap<TextRange, ShapingResult>, ?cachedSubstitutionRollbacks:SortedMap<TextRange, String>):ParagraphShapingStageResult {
        final segmentShapingCacheKeys = new Array<TextRange>();
        final segmentShapingCacheValues = new Array<ShapingResult>();
        if (cachedSegmentShaping != null) {
            for (i in 0...cachedSegmentShaping.size()) {
                segmentShapingCacheKeys.push(cachedSegmentShaping.keyAt(i));
                segmentShapingCacheValues.push(cachedSegmentShaping.valueAt(i));
            }
        }

        final substitutionRollbackKeys = new Array<TextRange>();
        final substitutionRollbackValues = new Array<String>();
        if (cachedSubstitutionRollbacks != null) {
            for (i in 0...cachedSubstitutionRollbacks.size()) {
                substitutionRollbackKeys.push(cachedSubstitutionRollbacks.keyAt(i));
                substitutionRollbackValues.push(cachedSubstitutionRollbacks.valueAt(i));
            }
        }

        function getCachedSegmentShaping(r:TextRange):Null<ShapingResult> {
            for (i in 0...segmentShapingCacheKeys.length) {
                final k = segmentShapingCacheKeys[i];
                if (k.start == r.start && k.end == r.end)
                    return segmentShapingCacheValues[i];
            }
            return null;
        }

        function putCachedSegmentShaping(r:TextRange, v:ShapingResult):Void {
            for (i in 0...segmentShapingCacheKeys.length) {
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
            for (i in 0...substitutionRollbackKeys.length) {
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
            final targetAdvance = DASH_SUBSTITUTION_TARGET_EM * segmentFontSize;
            return (ink.right - ink.left) < targetAdvance * DASH_SUBSTITUTION_MIN_INK_COVERAGE;
        }

        function shapeSegment(decision:FontDecision, segmentRange:TextRange):ShapingResult {
            final cached = getCachedSegmentShaping(segmentRange);
            if (cached != null)
                return cached;
            final sourceText = text.substring(segmentRange.start, segmentRange.end);
            final substitution = ContextualPunctuationDisplaySubstitutionFns.substituteForRole(punctuationGlyphSubstitutor, sourceText, decision.role);
            final baseSegmentStyle = styleAt(segmentRange.start);
            var segmentStyle = baseSegmentStyle;
            if (decision.role == FontRole.LatinText && emphasisItalicAt(segmentRange.start)) {
                segmentStyle = new TextStyle(copyFontFamilies(baseSegmentStyle.fontFamilies), baseSegmentStyle.fontSize, baseSegmentStyle.locale,
                    baseSegmentStyle.fontWeight, true, baseSegmentStyle.baselineShift, baseSegmentStyle.inlineAttachment);
            }
            final shaped = engine.textShaper.shape(new ShapingInput(text, segmentRange, segmentStyle, decision, substitution.displayText,
                cjkPunctuationFullWidthFeatures(decision.role, substitution.displayText)));
            var rollbackCause:Null<String> = null;
            if (substitution.displayText != sourceText) {
                var hasUnverified = false;
                var hasMissing = false;
                for (i in 0...shaped.decisions.length) {
                    final d = shaped.decisions[i];
                    if (d.capabilityIssue == TextShaper.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE) {
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
                result = engine.textShaper.shape(new ShapingInput(text, segmentRange, segmentStyle, decision, sourceText,
                    cjkPunctuationFullWidthFeatures(decision.role, sourceText)));
            }
            putCachedSegmentShaping(segmentRange, result);
            return result;
        }

        function shapeSegmentWithPointMarkPrefix(decision:FontDecision, segmentRange:TextRange):Array<ShapingResult> {
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

        final hyphenOffsets = new Array<Int>();
        var hyphenAdvanceOrNull:Null<Float> = null;
        var hyphenGlyphs = new Array<Glyph>();

        function latinWordCuts(decision:FontDecision, wordRange:TextRange, syllable:Array<Int>):Array<Int> {
            final cuts = new Array<Int>();
            for (i in 0...syllable.length) {
                cuts.push(wordRange.start + syllable[i]);
            }
            final relBounds = [0];
            for (i in 0...syllable.length) {
                final s = syllable[i];
                var exists = false;
                for (j in 0...relBounds.length) {
                    if (relBounds[j] == s) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    relBounds.push(s);
            }
            var lenExists = false;
            for (j in 0...relBounds.length) {
                if (relBounds[j] == wordRange.length) {
                    lenExists = true;
                    break;
                }
            }
            if (!lenExists)
                relBounds.push(wordRange.length);
            sortInts(relBounds);

            for (i in 0...(relBounds.length - 1)) {
                final a = relBounds[i];
                final b = relBounds[i + 1];
                final pieceShaped = shapeSegment(decision, new TextRange(wordRange.start + a, wordRange.start + b));
                final pieceAdvance = pieceShaped.clusters.length == 1 ? pieceShaped.clusters[0].advance : 0.0;
                if (pieceAdvance <= measure)
                    continue;
                final lo = a + HYPHEN_MIN_LEFT;
                final hi = b - HYPHEN_MIN_RIGHT;
                var off = lo <= hi ? lo : (a + 1);
                final endOff = lo <= hi ? (hi + 1) : b;
                while (off < endOff) {
                    final c = wordRange.start + off;
                    var exists = false;
                    for (k in 0...cuts.length) {
                        if (cuts[k] == c) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists)
                        cuts.push(c);
                    off++;
                }
            }
            sortInts(cuts);
            return cuts;
        }

        final breakOpportunityDecisions = new Array<BreakOpportunityDecisionInfo>();
        final emergencyTrackingEligibilityDecisions = new Array<EmergencyTrackingEligibilityDecisionInfo>();

        function registerEmergencyTrackingEligibility(range:TextRange, reason:String):Void {
            for (i in 0...emergencyTrackingEligibilityDecisions.length) {
                final d = emergencyTrackingEligibilityDecisions[i];
                if (d.range.start == range.start && d.range.end == range.end && d.reason == reason) {
                    return;
                }
            }
            emergencyTrackingEligibilityDecisions.push(new EmergencyTrackingEligibilityDecisionInfo(range, text.substring(range.start, range.end), reason));
        }

        final progBreakKeys = new Array<Int>();
        final progBreakValues = new Array<ProgressiveBreakOpportunity>();

        function putProgressiveBreak(offset:Int, opp:ProgressiveBreakOpportunity):Void {
            for (i in 0...progBreakKeys.length) {
                if (progBreakKeys[i] == offset) {
                    final current = progBreakValues[i];
                    if (opp.tier.priority < current.tier.priority) {
                        progBreakValues[i] = opp;
                    }
                    return;
                }
            }
            progBreakKeys.push(offset);
            progBreakValues.push(opp);
        }

        function latinSeparatorCuts(tokenRange:TextRange, tokenAdvance:Float, forceOpaqueBreaks:Bool):Array<Int> {
            final token = text.substring(tokenRange.start, tokenRange.end);
            final urlLike = isUrlLikeLatinToken(token);
            var opaque = false;
            for (i in 0...token.length) {
                if (!isLetter(token.charCodeAt(i))) {
                    opaque = true;
                    break;
                }
            }
            final structuralSolidus = hasBreakableLatinSolidus(token);
            final bibliographicLocatorCuts = bibliographicNumericLocatorBreakOffsets(token);
            final opaqueSeparatorMode = urlLike || (opaque && (tokenAdvance > measure || forceOpaqueBreaks));
            if (!structuralSolidus && !opaqueSeparatorMode && bibliographicLocatorCuts.length == 0) {
                return [];
            }
            final cuts = new Array<Int>();
            for (i in 0...bibliographicLocatorCuts.length) {
                cuts.push(tokenRange.start + bibliographicLocatorCuts[i]);
            }
            if (bibliographicLocatorCuts.length > 0) {
                breakOpportunityDecisions.push(new BreakOpportunityDecisionInfo(tokenRange, token, copyInts(cuts), "BibliographicNumericLocatorBreak"));
            }
            for (i in 0...(token.length - 1)) {
                final breakAfter = (structuralSolidus && !urlLike && token.charCodeAt(i) == 47)
                    || (opaqueSeparatorMode && isLatinTokenBreakAfter(token, i, tokenAdvance <= measure));
                if (breakAfter) {
                    cuts.push(tokenRange.start + i + 1);
                }
            }
            return cuts;
        }

        function latinOpaqueHardCuts(decision:FontDecision, tokenRange:TextRange, cleanCuts:Array<Int>, forceOpaqueBreaks:Bool):Array<Int> {
            final relBounds = [0];
            for (i in 0...cleanCuts.length) {
                final rel = cleanCuts[i] - tokenRange.start;
                var exists = false;
                for (j in 0...relBounds.length) {
                    if (relBounds[j] == rel) {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                    relBounds.push(rel);
            }
            var lenExists = false;
            for (j in 0...relBounds.length) {
                if (relBounds[j] == tokenRange.length) {
                    lenExists = true;
                    break;
                }
            }
            if (!lenExists)
                relBounds.push(tokenRange.length);
            sortInts(relBounds);

            final cuts = new Array<Int>();
            for (i in 0...(relBounds.length - 1)) {
                final a = relBounds[i];
                final b = relBounds[i + 1];
                if (b - a <= 1)
                    continue;
                final pieceRange = new TextRange(tokenRange.start + a, tokenRange.start + b);
                final pieceShaped = shapeSegment(decision, pieceRange);
                final pieceAdvance = pieceShaped.clusters.length == 1 ? pieceShaped.clusters[0].advance : 0.0;
                if (pieceAdvance <= measure && !(forceOpaqueBreaks && (b - a) >= LATIN_OPAQUE_TOKEN_MIN_LENGTH)) {
                    continue;
                }
                final graphemes = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, pieceRange);
                for (g in 0...graphemes.length) {
                    final pos = graphemes[g];
                    if (pos > pieceRange.start && pos < pieceRange.end) {
                        var exists = false;
                        for (k in 0...cuts.length) {
                            if (cuts[k] == pos) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            cuts.push(pos);
                    }
                }
            }
            sortInts(cuts);
            return cuts;
        }

        function getInlineObject(range:TextRange):Null<InlineObjectSpan> {
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
            if (fontDecisionByRange == null)
                return null;
            for (i in 0...fontDecisionByRange.size()) {
                final k = fontDecisionByRange.keyAt(i);
                if (k.start == range.start && k.end == range.end)
                    return fontDecisionByRange.valueAt(i);
            }
            return null;
        }

        function getRejectedTiers(range:TextRange):Null<SortedSet<ProgressiveBreakTier>> {
            if (rejectedTechnicalTiersBySpan == null)
                return null;
            for (i in 0...rejectedTechnicalTiersBySpan.size()) {
                final k = rejectedTechnicalTiersBySpan.keyAt(i);
                if (k.start == range.start && k.end == range.end)
                    return rejectedTechnicalTiersBySpan.valueAt(i);
            }
            return null;
        }

        final spanAdvanceCacheKeys = new Array<TextRange>();
        final spanAdvanceCacheValues = new Array<Float>();

        function progressiveSpanAdvance(spanRange:TextRange):Float {
            for (i in 0...spanAdvanceCacheKeys.length) {
                final k = spanAdvanceCacheKeys[i];
                if (k.start == spanRange.start && k.end == spanRange.end)
                    return spanAdvanceCacheValues[i];
            }
            var totalAdvance = 0.0;
            for (crIdx in 0...clusterRanges.length) {
                final resolvedRange = clusterRanges[crIdx];
                if (resolvedRange.mandatoryBreak || resolvedRange.zeroWidthSoftBreak || getInlineObject(resolvedRange.range) != null) {
                    continue;
                }
                final decision = getFontDecision(resolvedRange.range);
                if (decision == null)
                    continue;
                final candidates = shapingSegments(decision, text);
                for (cIdx in 0...candidates.length) {
                    final candidate = candidates[cIdx];
                    final start = candidate.start > spanRange.start ? candidate.start : spanRange.start;
                    final end = candidate.end < spanRange.end ? candidate.end : spanRange.end;
                    if (start < end) {
                        final pieceShaped = shapeSegment(decision, new TextRange(start, end));
                        for (clIdx in 0...pieceShaped.clusters.length) {
                            totalAdvance += pieceShaped.clusters[clIdx].advance;
                        }
                    }
                }
            }
            spanAdvanceCacheKeys.push(spanRange);
            spanAdvanceCacheValues.push(totalAdvance);
            return totalAdvance;
        }

        final shapingResults = new Array<ShapingResult>();
        for (crIdx in 0...clusterRanges.length) {
            final resolvedRange = clusterRanges[crIdx];
            final inlineObj = getInlineObject(resolvedRange.range);
            if (inlineObj != null) {
                shapingResults.push(inlineObjectShapingResult(text, inlineObj));
                continue;
            }
            if (resolvedRange.mandatoryBreak) {
                shapingResults.push(mandatoryBreakShapingResult(text, resolvedRange.range));
                continue;
            }
            if (resolvedRange.zeroWidthSoftBreak) {
                shapingResults.push(zeroWidthSoftBreakShapingResult(text, resolvedRange.range));
                continue;
            }
            var decision = getFontDecision(resolvedRange.range);
            if (decision == null) {
                decision = engine.fallbackResolver.resolve(text, resolvedRange.range,
                    new FontRequest(input.textStyle.fontFamilies, input.textStyle.locale, resolvedRange.role));
            }
            final segments = shapingSegments(decision, text);
            for (segIdx in 0...segments.length) {
                final segmentRange = segments[segIdx];
                final shaped = shapeSegment(decision, segmentRange);
                final isLatin = decision.role == FontRole.LatinText && segmentRange.length > 0;
                final w = isLatin ? text.substring(segmentRange.start, segmentRange.end) : "";

                var progressiveSpan:Null<org.tiqian.core.LineBreakSpan> = null;
                for (sIdx in 0...input.content.lineBreakSpans.length) {
                    final s = input.content.lineBreakSpans[sIdx];
                    if (s.policy == LineBreakPolicy.ProgressiveTechnical
                        && segmentRange.start >= s.range.start
                        && segmentRange.end <= s.range.end) {
                        progressiveSpan = s;
                        break;
                    }
                }

                var allLetters = isLatin && w.length > 0;
                if (isLatin) {
                    for (cIdx in 0...w.length) {
                        if (!isLetter(w.charCodeAt(cIdx))) {
                            allLetters = false;
                            break;
                        }
                    }
                }

                var isAllCaps = allLetters && w.length >= 2;
                if (isAllCaps) {
                    for (cIdx in 0...w.length) {
                        if (isLowerCase(w.charCodeAt(cIdx))) {
                            isAllCaps = false;
                            break;
                        }
                    }
                }
                final isAbbreviation = isAllCaps && w.length < LATIN_OPAQUE_TOKEN_MIN_LENGTH;
                var hasInternalUpper = false;
                if (allLetters && !isAllCaps && !isAbbreviation) {
                    for (cIdx in 1...w.length) {
                        if (isUpperCase(w.charCodeAt(cIdx))) {
                            hasInternalUpper = true;
                            break;
                        }
                    }
                }
                final isCamelCase = allLetters && !isAllCaps && !isAbbreviation && hasInternalUpper;

                var tokenAdvance = 0.0;
                for (clIdx in 0...shaped.clusters.length) {
                    tokenAdvance += shaped.clusters[clIdx].advance;
                }
                final strongReason = isLatin ? strongNonLexicalReason(w) : null;

                var syllableCuts = new Array<Int>();
                if (allLetters && !isAbbreviation && !isCamelCase && w.indexOf("-") < 0 && strongReason == null) {
                    final hyphenPoints = engine.hyphenator.hyphenate(w);
                    final uniquePoints = new Array<Int>();
                    for (p in 0...hyphenPoints.length) {
                        final pt = hyphenPoints[p];
                        var exists = false;
                        for (q in 0...uniquePoints.length) {
                            if (uniquePoints[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniquePoints.push(pt);
                    }
                    sortInts(uniquePoints);
                    syllableCuts = uniquePoints;
                }

                var longestUnhyphenatedLetterPiece = 0;
                if (allLetters) {
                    final bounds = [0];
                    for (p in 0...syllableCuts.length)
                        bounds.push(syllableCuts[p]);
                    bounds.push(w.length);
                    var maxLen = 0;
                    for (p in 0...(bounds.length - 1)) {
                        final diff = bounds[p + 1] - bounds[p];
                        if (diff > maxLen)
                            maxLen = diff;
                    }
                    longestUnhyphenatedLetterPiece = maxLen;
                }

                final isLongUnhyphenatedLetterToken = allLetters
                    && !isAbbreviation
                    && !isCamelCase
                    && longestUnhyphenatedLetterPiece >= LATIN_OPAQUE_TOKEN_MIN_LENGTH;
                final isLongOpaqueLatinToken = strongReason != null
                    || isLongUnhyphenatedLetterToken
                    || (isLatin && !allLetters && w.length >= LATIN_OPAQUE_TOKEN_MIN_LENGTH);

                var technicalStructuralCuts = new Array<Int>();
                if (progressiveSpan != null && isLatin) {
                    final cutsSet = new Array<Int>();
                    final cc = camelCaseCuts(text, segmentRange);
                    for (c in 0...cc.length)
                        cutsSet.push(cc[c]);
                    final at = alphaNumericTransitionCuts(text, segmentRange);
                    for (c in 0...at.length) {
                        final v = at[c];
                        var exists = false;
                        for (q in 0...cutsSet.length) {
                            if (cutsSet[q] == v) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            cutsSet.push(v);
                    }
                    for (i in 0...(w.length - 1)) {
                        if (isProgressiveTechnicalBreakAfterChar(w.charCodeAt(i))) {
                            final v = segmentRange.start + i + 1;
                            var exists = false;
                            for (q in 0...cutsSet.length) {
                                if (cutsSet[q] == v) {
                                    exists = true;
                                    break;
                                }
                            }
                            if (!exists)
                                cutsSet.push(v);
                        }
                    }
                    sortInts(cutsSet);
                    technicalStructuralCuts = cutsSet;
                }

                var rawTechnicalSyllableCuts = new Array<Int>();
                if (progressiveSpan != null && isLatin) {
                    final preferredBounds = [segmentRange.start];
                    for (c in 0...technicalStructuralCuts.length)
                        preferredBounds.push(technicalStructuralCuts[c]);
                    preferredBounds.push(segmentRange.end);
                    final uniqueBounds = new Array<Int>();
                    for (p in 0...preferredBounds.length) {
                        final pt = preferredBounds[p];
                        var exists = false;
                        for (q in 0...uniqueBounds.length) {
                            if (uniqueBounds[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniqueBounds.push(pt);
                    }
                    sortInts(uniqueBounds);

                    final cutsList = new Array<Int>();
                    for (p in 0...(uniqueBounds.length - 1)) {
                        final pieceStart = uniqueBounds[p];
                        final pieceEnd = uniqueBounds[p + 1];
                        final piece = text.substring(pieceStart, pieceEnd);
                        if (strongNonLexicalReason(piece) != null)
                            continue;
                        var runStart = pieceStart;
                        while (runStart < pieceEnd) {
                            while (runStart < pieceEnd && !isLetter(text.charCodeAt(runStart)))
                                runStart++;
                            var runEnd = runStart;
                            while (runEnd < pieceEnd && isLetter(text.charCodeAt(runEnd)))
                                runEnd++;
                            if (runEnd > runStart) {
                                final word = text.substring(runStart, runEnd);
                                final wordHyphs = engine.hyphenator.hyphenate(word);
                                for (h in 0...wordHyphs.length) {
                                    final off = wordHyphs[h];
                                    if (off >= 1 && off < word.length) {
                                        cutsList.push(runStart + off);
                                    }
                                }
                            }
                            runStart = runEnd > runStart ? runEnd : (runStart + 1);
                        }
                    }
                    final uniqueCuts = new Array<Int>();
                    for (p in 0...cutsList.length) {
                        final pt = cutsList[p];
                        var exists = false;
                        for (q in 0...uniqueCuts.length) {
                            if (uniqueCuts[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniqueCuts.push(pt);
                    }
                    sortInts(uniqueCuts);
                    rawTechnicalSyllableCuts = uniqueCuts;
                }

                final technicalSyllableCuts = new Array<Int>();
                for (i in 0...rawTechnicalSyllableCuts.length) {
                    final cut = rawTechnicalSyllableCuts[i];
                    var inStructural = false;
                    for (j in 0...technicalStructuralCuts.length) {
                        if (technicalStructuralCuts[j] == cut) {
                            inStructural = true;
                            break;
                        }
                    }
                    if (!inStructural) {
                        technicalSyllableCuts.push(cut);
                    }
                }

                var technicalEmergencyCuts = new Array<Int>();
                if (progressiveSpan != null && isLatin) {
                    final rejectedTiers = getRejectedTiers(progressiveSpan.range);
                    final exposedForCurrentLine = rejectedTiers != null && rejectedTiers.size() > 0;
                    final preferredBounds = [segmentRange.start];
                    for (c in 0...technicalStructuralCuts.length)
                        preferredBounds.push(technicalStructuralCuts[c]);
                    for (c in 0...technicalSyllableCuts.length)
                        preferredBounds.push(technicalSyllableCuts[c]);
                    preferredBounds.push(segmentRange.end);
                    final uniqueBounds = new Array<Int>();
                    for (p in 0...preferredBounds.length) {
                        final pt = preferredBounds[p];
                        var exists = false;
                        for (q in 0...uniqueBounds.length) {
                            if (uniqueBounds[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniqueBounds.push(pt);
                    }
                    sortInts(uniqueBounds);

                    final interiorEmergencyCuts = new Array<Int>();
                    for (p in 0...(uniqueBounds.length - 1)) {
                        final pStart = uniqueBounds[p];
                        final pEnd = uniqueBounds[p + 1];
                        final pieceRange = new TextRange(pStart, pEnd);
                        final pieceShaped = shapeSegment(decision, pieceRange);
                        var pieceAdvance = 0.0;
                        for (clIdx in 0...pieceShaped.clusters.length) {
                            pieceAdvance += pieceShaped.clusters[clIdx].advance;
                        }
                        if (!exposedForCurrentLine
                            && pieceAdvance <= measure
                            && progressiveSpanAdvance(progressiveSpan.range) <= measure) {
                            // nothing
                        } else {
                            final graphemes = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, pieceRange);
                            for (g in 0...graphemes.length) {
                                final pt = graphemes[g];
                                if (pt > pStart && pt < pEnd) {
                                    interiorEmergencyCuts.push(pt);
                                }
                            }
                        }
                    }
                    final rejectedCleanBoundaries = new Array<Int>();
                    if (rejectedTiers != null) {
                        if (rejectedTiers.has(ProgressiveBreakTier.Structural)) {
                            for (c in 0...technicalStructuralCuts.length)
                                rejectedCleanBoundaries.push(technicalStructuralCuts[c]);
                        }
                        if (rejectedTiers.has(ProgressiveBreakTier.Syllable)) {
                            for (c in 0...technicalSyllableCuts.length)
                                rejectedCleanBoundaries.push(technicalSyllableCuts[c]);
                        }
                    }
                    final combined = new Array<Int>();
                    for (c in 0...interiorEmergencyCuts.length)
                        combined.push(interiorEmergencyCuts[c]);
                    for (c in 0...rejectedCleanBoundaries.length)
                        combined.push(rejectedCleanBoundaries[c]);
                    final uniqueCombined = new Array<Int>();
                    for (p in 0...combined.length) {
                        final pt = combined[p];
                        var exists = false;
                        for (q in 0...uniqueCombined.length) {
                            if (uniqueCombined[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniqueCombined.push(pt);
                    }
                    sortInts(uniqueCombined);
                    technicalEmergencyCuts = uniqueCombined;
                }

                if (progressiveSpan != null) {
                    if (technicalEmergencyCuts.length > 0) {
                        final rej = getRejectedTiers(progressiveSpan.range);
                        var reason = "ProgressiveTechnicalSpan";
                        if (rej != null && rej.size() > 0) {
                            final tiers = new Array<ProgressiveBreakTier>();
                            for (i in 0...rej.size())
                                tiers.push(rej.at(i));
                            var tIdx = 1;
                            while (tIdx < tiers.length) {
                                final curr = tiers[tIdx];
                                var j = tIdx - 1;
                                while (j >= 0 && tiers[j].priority > curr.priority) {
                                    tiers[j + 1] = tiers[j];
                                    j--;
                                }
                                tiers[j + 1] = curr;
                                tIdx++;
                            }
                            var joined = "";
                            for (i in 0...tiers.length) {
                                if (i > 0)
                                    joined += "+";
                                joined += tierName(tiers[i]);
                            }
                            reason = "CurrentLineTechnicalTierRejection:" + joined;
                        }
                        registerEmergencyTrackingEligibility(progressiveSpan.range, reason);
                    }

                    final tierArrays = [technicalStructuralCuts, technicalSyllableCuts, technicalEmergencyCuts];
                    final tierTypes = [
                        ProgressiveBreakTier.Structural,
                        ProgressiveBreakTier.Syllable,
                        ProgressiveBreakTier.Emergency
                    ];
                    for (tIdx in 0...3) {
                        final tier = tierTypes[tIdx];
                        final offsets = tierArrays[tIdx];
                        final rej = getRejectedTiers(progressiveSpan.range);
                        if (rej != null && rej.has(tier)) {
                            continue;
                        }
                        final uniqueOffsets = new Array<Int>();
                        for (p in 0...offsets.length) {
                            final pt = offsets[p];
                            var exists = false;
                            for (q in 0...uniqueOffsets.length) {
                                if (uniqueOffsets[q] == pt) {
                                    exists = true;
                                    break;
                                }
                            }
                            if (!exists)
                                uniqueOffsets.push(pt);
                        }
                        sortInts(uniqueOffsets);
                        if (uniqueOffsets.length > 0) {
                            final rejNotEmpty = rej != null && rej.size() > 0;
                            final breakReason = (tier == ProgressiveBreakTier.Emergency
                                && rejNotEmpty) ? "CurrentLineTechnicalEmergencyBreak" : "ProgressiveTechnicalBreak";
                            breakOpportunityDecisions.push(new BreakOpportunityDecisionInfo(segmentRange, w, copyInts(uniqueOffsets), breakReason,
                                tierName(tier)));
                        }
                        for (oIdx in 0...uniqueOffsets.length) {
                            final offset = uniqueOffsets[oIdx];
                            putProgressiveBreak(offset, new ProgressiveBreakOpportunity(tier, progressiveSpan.range));
                        }
                    }

                    var boundaryTier = ProgressiveBreakTier.WholeToken;
                    if (segmentRange.start > progressiveSpan.range.start && isWhitespace(text.charCodeAt(segmentRange.start - 1))) {
                        boundaryTier = ProgressiveBreakTier.Whitespace;
                    }
                    final rej = getRejectedTiers(progressiveSpan.range);
                    if (rej == null || !rej.has(boundaryTier)) {
                        final wholeToken = new ProgressiveBreakOpportunity(boundaryTier, progressiveSpan.range);
                        putProgressiveBreak(segmentRange.start, wholeToken);
                        final wrapReason = boundaryTier == ProgressiveBreakTier.Whitespace ? "ProgressiveTechnicalWhitespaceBreak" : "ProgressiveTechnicalWholeTokenWrap";
                        breakOpportunityDecisions.push(new BreakOpportunityDecisionInfo(segmentRange, w, [segmentRange.start], wrapReason,
                            tierName(boundaryTier)));
                    }
                }

                var cleanCuts = new Array<Int>();
                if (progressiveSpan != null) {
                    for (c in 0...technicalStructuralCuts.length)
                        cleanCuts.push(technicalStructuralCuts[c]);
                    for (c in 0...technicalSyllableCuts.length)
                        cleanCuts.push(technicalSyllableCuts[c]);
                    for (c in 0...technicalEmergencyCuts.length)
                        cleanCuts.push(technicalEmergencyCuts[c]);
                } else if (!isLatin) {
                    // empty
                } else if (w.indexOf("-") >= 0) {
                    final existing = existingHyphenCuts(text, segmentRange);
                    for (c in 0...existing.length)
                        cleanCuts.push(existing[c]);
                    final sep = latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken);
                    for (c in 0...sep.length)
                        cleanCuts.push(sep[c]);
                } else if (isCamelCase) {
                    cleanCuts = camelCaseCuts(text, segmentRange);
                } else if (!allLetters) {
                    cleanCuts = latinSeparatorCuts(segmentRange, tokenAdvance, isLongOpaqueLatinToken);
                }

                var hyphenCuts = new Array<Int>();
                if (progressiveSpan == null && allLetters && !isAbbreviation && !isCamelCase && !isLongUnhyphenatedLetterToken && w.indexOf("-") < 0
                    && cleanCuts.length == 0) {
                    hyphenCuts = latinWordCuts(decision, segmentRange, syllableCuts);
                }

                var opaqueHardCuts = new Array<Int>();
                if (progressiveSpan == null
                    && isLatin
                    && (!allLetters || isLongUnhyphenatedLetterToken)
                    && (tokenAdvance > measure || isLongOpaqueLatinToken)) {
                    opaqueHardCuts = latinOpaqueHardCuts(decision, segmentRange, cleanCuts, isLongOpaqueLatinToken);
                }

                if (progressiveSpan == null && opaqueHardCuts.length > 0) {
                    final cleanBounds = [segmentRange.start];
                    for (c in 0...cleanCuts.length)
                        cleanBounds.push(cleanCuts[c]);
                    cleanBounds.push(segmentRange.end);
                    final uniqueBounds = new Array<Int>();
                    for (p in 0...cleanBounds.length) {
                        final pt = cleanBounds[p];
                        var exists = false;
                        for (q in 0...uniqueBounds.length) {
                            if (uniqueBounds[q] == pt) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists)
                            uniqueBounds.push(pt);
                    }
                    sortInts(uniqueBounds);

                    for (p in 0...(uniqueBounds.length - 1)) {
                        final pieceStart = uniqueBounds[p];
                        final pieceEnd = uniqueBounds[p + 1];
                        var hasPieceHardCuts = false;
                        for (k in 0...opaqueHardCuts.length) {
                            final cut = opaqueHardCuts[k];
                            if (cut > pieceStart && cut < pieceEnd) {
                                hasPieceHardCuts = true;
                                break;
                            }
                        }
                        if (!hasPieceHardCuts)
                            continue;
                        final pieceRange = new TextRange(pieceStart, pieceEnd);
                        final pieceReason = strongNonLexicalReason(text.substring(pieceStart, pieceEnd));
                        if (pieceReason != null) {
                            registerEmergencyTrackingEligibility(pieceRange, pieceReason);
                        }
                    }
                }

                final allCutsCombined = new Array<Int>();
                for (c in 0...cleanCuts.length)
                    allCutsCombined.push(cleanCuts[c]);
                for (c in 0...hyphenCuts.length)
                    allCutsCombined.push(hyphenCuts[c]);
                for (c in 0...opaqueHardCuts.length)
                    allCutsCombined.push(opaqueHardCuts[c]);

                final allCuts = new Array<Int>();
                for (p in 0...allCutsCombined.length) {
                    final pt = allCutsCombined[p];
                    var exists = false;
                    for (q in 0...allCuts.length) {
                        if (allCuts[q] == pt) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists)
                        allCuts.push(pt);
                }
                sortInts(allCuts);

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
                            final hyphenShaped = engine.textShaper.shape(new ShapingInput("-", new TextRange(0, 1), input.textStyle, decision, "-"));
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
