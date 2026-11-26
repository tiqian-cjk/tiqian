package org.tiqian.layout;

using org.tiqian.layout.ProgressiveBreakTierPriority;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.core.Glyph;
import org.tiqian.core.Cluster;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.UnicodeWordCharacterData;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.ParagraphLayoutEngine.ParagraphLayoutEngineFns;
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
        final sourceTerms:Array<Float> = [];
        for (i in 0...glyphs.length) {
            sourceTerms.push(glyphs[i].advance);
        }
        final sourceAdvance = AccurateSum.of(sourceTerms);
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

    public static function copyFontFamilies(families:std.ReadOnlyArray<String>):Array<String> {
        final result = new Array<String>();
        for (i in 0...families.length) {
            result.push(families[i]);
        }
        return result;
    }

    public static function copyInts(arr:Array<Int>):Array<Int> {
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
        final session = new ParagraphShapingSession(engine.textShaper, engine.fallbackResolver, input, text, fontSize, measure, clusterRanges,
            fontDecisionByRange, inlineObjectByRange, punctuationGlyphSubstitutor, styleAt, emphasisItalicAt, rejectedTechnicalTiersBySpan,
            cachedSegmentShaping, cachedSubstitutionRollbacks);
        return session.run(new LatinSegmentBreakPlanner(session, engine.hyphenator, input, text, measure));
    }
}
