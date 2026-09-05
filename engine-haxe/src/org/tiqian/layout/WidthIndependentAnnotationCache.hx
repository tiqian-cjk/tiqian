package org.tiqian.layout;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextSpan;
import org.tiqian.core.LineBreakSpan;
import org.tiqian.core.TextStyle;
import org.tiqian.core.DecorationSpan;
import org.tiqian.core.RubySpan;
import org.tiqian.core.InlineBoxSpan;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.LayoutProfileId;
import org.tiqian.clreq.ClreqProfile;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.clreq.KinsokuModes;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontPolicy.FontRequest;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteRoleDecision;
import org.tiqian.layout.QuotePairAnalyzer.QuotePairAwareFontRoleClassifier;
import org.tiqian.core.IllegalStateException;
import org.tiqian.layout.ContextualDashEllipsisRoleResolver;
import org.tiqian.layout.ContextualDashEllipsisRoleResolver.ContextualDashEllipsisRoles;
import org.tiqian.layout.ContextualDashEllipsisRoleResolver.ContextualDashEllipsisAwareFontRoleClassifier;
import org.tiqian.layout.ClusterRoleResolution;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.ParagraphShapingStage;
import org.tiqian.layout.ParagraphShapingStage.ParagraphShapingStageResult;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.core.DecorationKind;
import org.tiqian.core.RubyKind;
import org.tiqian.core.InlineBoxOuterSpacing;
import org.tiqian.core.LineLengthGridDecisionInfo;
import org.tiqian.core.LastLineAlignment;
import org.tiqian.core.LineBreakPolicy;
import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.UnicodeEastAsianSpacing;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.clreq.AutoSpaceMode;
import org.tiqian.layout.PunctuationGeometryStage;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.layout.PunctuationGeometryLedger;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.core.MandatoryBreakDecisionInfo;
import org.tiqian.core.ZeroWidthBreakDecisionInfo;
import org.tiqian.core.InlineObjectBoundaryAdjustment;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo;
import org.tiqian.core.IntRange;
import org.tiqian.core.InlineAttachment;
import std.SortedSet;
import std.SortedMap;
import std.RecordEq;

@:dataClass class WidthIndependentAnnotationKey {
    public final text:String;
    public final spans:std.ReadOnlyArray<TextSpan>;
    public final lineBreakSpans:std.ReadOnlyArray<LineBreakSpan>;
    public final sourceBoundaries:std.ReadOnlyArray<Int>;
    public final textStyle:TextStyle;
    public final decorations:std.ReadOnlyArray<DecorationSpan>;
    public final rubySpans:std.ReadOnlyArray<RubySpan>;
    public final inlineBoxes:std.ReadOnlyArray<InlineBoxSpan>;
    public final inlineObjects:std.ReadOnlyArray<InlineObjectSpan>;
    public final profileId:LayoutProfileId;
    public final emphasisDotGapEm:Float;
    public final rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>;

    public function new(text:String, spans:std.ReadOnlyArray<TextSpan>, lineBreakSpans:std.ReadOnlyArray<LineBreakSpan>,
            sourceBoundaries:std.ReadOnlyArray<Int>, textStyle:TextStyle, decorations:std.ReadOnlyArray<DecorationSpan>,
            rubySpans:std.ReadOnlyArray<RubySpan>, inlineBoxes:std.ReadOnlyArray<InlineBoxSpan>, inlineObjects:std.ReadOnlyArray<InlineObjectSpan>,
            profileId:LayoutProfileId, emphasisDotGapEm:Float, rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>) {
        this.text = text;
        this.spans = spans;
        this.lineBreakSpans = lineBreakSpans;
        this.sourceBoundaries = sourceBoundaries;
        this.textStyle = textStyle;
        this.decorations = decorations;
        this.rubySpans = rubySpans;
        this.inlineBoxes = inlineBoxes;
        this.inlineObjects = inlineObjects;
        this.profileId = profileId;
        this.emphasisDotGapEm = emphasisDotGapEm;
        this.rejectedTechnicalTiersBySpan = rejectedTechnicalTiersBySpan;
    }
}

class WidthIndependentParagraphAnnotation {
    public final text:String;
    public final fontSize:Float;
    public final styleAt:Int->TextStyle;
    public final fontSizeAt:Int->Float;
    public final bopomofoFontWeightAt:Int->Int;
    public final rubyFontSize:Float;
    public final rubyStackGap:Float;
    public final rubyFontWeight:Int;
    public final pinyinSpans:Array<RubySpan>;
    public final clreqProfile:ClreqProfile;
    public final punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor;
    public final quotePairs:Array<QuotePair>;
    public final roleOverrideInfos:Array<RoleOverrideInfo>;
    public final fontDecisions:Array<FontDecision>;
    public final clusterRanges:Array<ResolvedClusterRange>;
    public final fontDecisionByRange:SortedMap<TextRange, FontDecision>;
    public final inlineObjectByRange:SortedMap<TextRange, InlineObjectSpan>;
    public final segmentShapingCache:SortedMap<TextRange, ShapingResult>;
    public final substitutionRollbacks:SortedMap<TextRange, String>;
    public final rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>;
    public final baseShapingStage:ParagraphShapingStageResult;

    public function new(text:String, fontSize:Float, styleAt:Int->TextStyle, fontSizeAt:Int->Float, bopomofoFontWeightAt:Int->Int, rubyFontSize:Float,
            rubyStackGap:Float, rubyFontWeight:Int, pinyinSpans:Array<RubySpan>, clreqProfile:ClreqProfile,
            punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor, quotePairs:Array<QuotePair>, roleOverrideInfos:Array<RoleOverrideInfo>,
            fontDecisions:Array<FontDecision>, clusterRanges:Array<ResolvedClusterRange>, fontDecisionByRange:SortedMap<TextRange, FontDecision>,
            inlineObjectByRange:SortedMap<TextRange, InlineObjectSpan>, segmentShapingCache:SortedMap<TextRange, ShapingResult>,
            substitutionRollbacks:SortedMap<TextRange, String>, rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>,
            baseShapingStage:ParagraphShapingStageResult) {
        this.text = text;
        this.fontSize = fontSize;
        this.styleAt = styleAt;
        this.fontSizeAt = fontSizeAt;
        this.bopomofoFontWeightAt = bopomofoFontWeightAt;
        this.rubyFontSize = rubyFontSize;
        this.rubyStackGap = rubyStackGap;
        this.rubyFontWeight = rubyFontWeight;
        this.pinyinSpans = pinyinSpans;
        this.clreqProfile = clreqProfile;
        this.punctuationGlyphSubstitutor = punctuationGlyphSubstitutor;
        this.quotePairs = quotePairs;
        this.roleOverrideInfos = roleOverrideInfos;
        this.fontDecisions = fontDecisions;
        this.clusterRanges = clusterRanges;
        this.fontDecisionByRange = fontDecisionByRange;
        this.inlineObjectByRange = inlineObjectByRange;
        this.segmentShapingCache = segmentShapingCache;
        this.substitutionRollbacks = substitutionRollbacks;
        this.rubyFontGeometryBySpan = rubyFontGeometryBySpan;
        this.baseShapingStage = baseShapingStage;
    }
}

interface WidthIndependentAnnotationCache {
    function get(key:WidthIndependentAnnotationKey):Null<WidthIndependentParagraphAnnotation>;
    function put(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation):Void;
    function clear():Void;
    public var size(get, never):Int;
}

class LruWidthIndependentAnnotationCache implements WidthIndependentAnnotationCache {
    public final maxEntries:Int;

    private final keys:Array<WidthIndependentAnnotationKey> = [];
    private final values:Array<WidthIndependentParagraphAnnotation> = [];

    public var size(get, never):Int;

    public function new(maxEntries:Int = 512) {
        this.maxEntries = maxEntries;
    }

    private static function textRangeEquals(a:TextRange, b:TextRange):Bool {
        return a == b || (a != null && b != null && RecordEq.eq(a, b));
    }

    private static function textStyleEquals(a:TextStyle, b:TextStyle):Bool {
        if (a == b)
            return true;
        if (a == null || b == null)
            return false;
        return a.fontSize == b.fontSize
            && a.locale == b.locale
            && a.fontWeight == b.fontWeight
            && a.italic == b.italic
            && a.baselineShift == b.baselineShift
            && a.inlineAttachment == b.inlineAttachment
            && stringsEqual(a.fontFamilies, b.fontFamilies);
    }

    private static function textSpanEquals(a:TextSpan, b:TextSpan):Bool {
        return a == b || (a != null && b != null && textRangeEquals(a.range, b.range) && textStyleEquals(a.style, b.style));
    }

    private static function lineBreakSpanEquals(a:LineBreakSpan, b:LineBreakSpan):Bool {
        return a == b || (a != null && b != null && textRangeEquals(a.range, b.range) && a.policy == b.policy);
    }

    private static function decorationEquals(a:DecorationSpan, b:DecorationSpan):Bool {
        return a == b || (a != null && b != null && textRangeEquals(a.range, b.range) && a.kind == b.kind);
    }

    private static function rubyEquals(a:RubySpan, b:RubySpan):Bool {
        if (a == b)
            return true;
        if (a == null
            || b == null
            || !textRangeEquals(a.baseRange, b.baseRange)
            || a.text != b.text
            || a.kind != b.kind
            || a.locale != b.locale)
            return false;
        return stringsEqual(a.fontFamilies, b.fontFamilies);
    }

    private static function inlineBoxEquals(a:InlineBoxSpan, b:InlineBoxSpan):Bool {
        return a == b
            || (a != null && b != null && textRangeEquals(a.range, b.range) && a.inlineStart == b.inlineStart && a.inlineEnd == b.inlineEnd
                && a.outerSpacing == b.outerSpacing);
    }

    private static function preferredStretchEquals(a:InlineObjectPreferredStretch, b:InlineObjectPreferredStretch):Bool {
        if (a == b)
            return true;
        if (a == null || b == null)
            return false;
        return a.kind == b.kind && a.naturalWidth == b.naturalWidth && a.targetWidth == b.targetWidth;
    }

    private static function boundaryAdjustmentEquals(a:InlineObjectBoundaryAdjustment, b:InlineObjectBoundaryAdjustment):Bool {
        if (a == b)
            return true;
        if (a == null || b == null)
            return false;
        return a.participatesInUniformStretch == b.participatesInUniformStretch
            && preferredStretchEquals(a.preferredStretch, b.preferredStretch)
            && a.shrinkCapacity == b.shrinkCapacity
            && a.lineEndDiscardableAdvance == b.lineEndDiscardableAdvance
            && a.preventsLineBreak == b.preventsLineBreak;
    }

    private static function inlineObjectEquals(a:InlineObjectSpan, b:InlineObjectSpan):Bool {
        return a == b
            || (a != null
                && b != null
                && textRangeEquals(a.range, b.range)
                && a.advance == b.advance
                && a.ascent == b.ascent
                && a.descent == b.descent
                && boundaryAdjustmentEquals(a.leadingBoundary, b.leadingBoundary)
                && boundaryAdjustmentEquals(a.trailingBoundary, b.trailingBoundary));
    }

    private static function stringsEqual(a:std.ReadOnlyArray<String>, b:std.ReadOnlyArray<String>):Bool {
        if (a == b)
            return true;
        if (a == null || b == null || a.length != b.length)
            return false;
        for (i in 0...a.length)
            if (a[i] != b[i])
                return false;
        return true;
    }

    private static function intsEqual(a:std.ReadOnlyArray<Int>, b:std.ReadOnlyArray<Int>):Bool {
        if (a == b)
            return true;
        if (a == null || b == null || a.length != b.length)
            return false;
        for (i in 0...a.length)
            if (a[i] != b[i])
                return false;
        return true;
    }

    private static function mapEquals(a:SortedMap<TextRange, SortedSet<Int>>, b:SortedMap<TextRange, SortedSet<Int>>):Bool {
        if (a == b)
            return true;
        if (a == null || b == null || a.size() != b.size())
            return false;
        for (i in 0...a.size()) {
            final ak = a.keyAt(i);
            var matched = false;
            for (j in 0...b.size()) {
                final bk = b.keyAt(j);
                if (textRangeEquals(ak, bk)) {
                    final av = a.valueAt(i);
                    final bv = b.valueAt(j);
                    if (av == bv)
                        matched = true;
                    else if (av == null || bv == null || av.size() != bv.size())
                        return false;
                    else {
                        matched = true;
                        for (k in 0...av.size())
                            if (av.at(k) != bv.at(k)) {
                                matched = false;
                                break;
                            }
                    }
                    break;
                }
            }
            if (!matched)
                return false;
        }
        return true;
    }

    private static function keyEquals(a:WidthIndependentAnnotationKey, b:WidthIndependentAnnotationKey):Bool {
        if (a == b)
            return true;
        if (a == null
            || b == null
            || a.text != b.text
            || !RecordEq.eq(a.profileId, b.profileId)
            || a.emphasisDotGapEm != b.emphasisDotGapEm
            || !textStyleEquals(a.textStyle, b.textStyle))
            return false;
        if (a.spans.length != b.spans.length
            || a.lineBreakSpans.length != b.lineBreakSpans.length
            || a.decorations.length != b.decorations.length
            || a.rubySpans.length != b.rubySpans.length
            || a.inlineBoxes.length != b.inlineBoxes.length
            || a.inlineObjects.length != b.inlineObjects.length)
            return false;
        for (i in 0...a.spans.length)
            if (!textSpanEquals(a.spans[i], b.spans[i]))
                return false;
        for (i in 0...a.lineBreakSpans.length)
            if (!lineBreakSpanEquals(a.lineBreakSpans[i], b.lineBreakSpans[i]))
                return false;
        for (i in 0...a.decorations.length)
            if (!decorationEquals(a.decorations[i], b.decorations[i]))
                return false;
        for (i in 0...a.rubySpans.length)
            if (!rubyEquals(a.rubySpans[i], b.rubySpans[i]))
                return false;
        for (i in 0...a.inlineBoxes.length)
            if (!inlineBoxEquals(a.inlineBoxes[i], b.inlineBoxes[i]))
                return false;
        for (i in 0...a.inlineObjects.length)
            if (!inlineObjectEquals(a.inlineObjects[i], b.inlineObjects[i]))
                return false;
        return intsEqual(a.sourceBoundaries, b.sourceBoundaries)
            && mapEquals(a.rejectedTechnicalTiersBySpan, b.rejectedTechnicalTiersBySpan);
    }

    public function get(key:WidthIndependentAnnotationKey):Null<WidthIndependentParagraphAnnotation> {
        var foundIndex = -1;
        for (i in 0...keys.length) {
            if (keyEquals(keys[i], key)) {
                foundIndex = i;
                break;
            }
        }
        if (foundIndex < 0)
            return null;
        final k = keys[foundIndex];
        final v = values[foundIndex];
        keys.splice(foundIndex, 1);
        values.splice(foundIndex, 1);
        keys.push(k);
        values.push(v);
        return v;
    }

    public function put(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation):Void {
        var foundIndex = -1;
        for (i in 0...keys.length) {
            if (keyEquals(keys[i], key)) {
                foundIndex = i;
                break;
            }
        }
        if (foundIndex >= 0) {
            keys.splice(foundIndex, 1);
            values.splice(foundIndex, 1);
        } else if (keys.length >= maxEntries) {
            keys.shift();
            values.shift();
        }
        keys.push(key);
        values.push(annotation);
    }

    public function clear():Void {
        while (keys.length > 0) {
            keys.pop();
            values.pop();
        }
    }

    public function get_size():Int {
        return keys.length;
    }
}

class WidthIndependentAnnotationCacheFns {
    private static inline final RUBY_FONT_EM:Float = 0.5;
    private static inline final RUBY_FONT_WEIGHT_BOOST:Int = 100;
    private static inline final BOPOMOFO_FONT_WEIGHT_BOOST:Int = 300;
    private static inline final RUBY_MIN_GAP_EM_OF_RUBY:Float = 0.25;
    private static inline final RUBY_STACK_GAP_EM:Float = 0.0;
    private static inline final WORD_SPACE_MIN_EM:Float = 0.25;
    private static inline final SINO_WESTERN_GAP_MIN_EM:Float = 0.125;

    private static function copyFontFamilies(families:std.ReadOnlyArray<String>):Array<String> {
        final result = new Array<String>();
        for (i in 0...families.length) {
            result.push(families[i]);
        }
        return result;
    }

    private static function isFixedBoundary(b:InlineObjectBoundaryAdjustment):Bool {
        return !b.participatesInUniformStretch && b.preferredStretch == null && b.shrinkCapacity == 0.0 && b.lineEndDiscardableAdvance == 0.0
            && !b.preventsLineBreak;
    }

    public static function isContainedIn(r:TextRange, other:TextRange):Bool {
        return r.start >= other.start && r.end <= other.end;
    }

    public static function containingFontDecisions(clusters:Array<Cluster>, items:Array<FontDecision>):Array<Null<FontDecision>> {
        var itemIndex = 0;
        final result = new Array<Null<FontDecision>>();
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].range.end <= cluster.range.start) {
                itemIndex += 1;
            }
            if (itemIndex < items.length) {
                final item = items[itemIndex];
                if (cluster.range.start >= item.range.start && cluster.range.end <= item.range.end) {
                    result.push(item);
                } else {
                    result.push(null);
                }
            } else {
                result.push(null);
            }
        }
        return result;
    }

    public static function firstContainedAtom(clusters:Array<Cluster>, items:Array<PunctuationAtom>):Array<Null<PunctuationAtom>> {
        var itemIndex = 0;
        final result = new Array<Null<PunctuationAtom>>();
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].range.end <= cluster.range.start) {
                itemIndex += 1;
            }
            if (itemIndex < items.length) {
                final item = items[itemIndex];
                if (item.range.start >= cluster.range.start && item.range.end <= cluster.range.end) {
                    result.push(item);
                } else {
                    result.push(null);
                }
            } else {
                result.push(null);
            }
        }
        return result;
    }

    private static function quoteToRoleOverrideInfos(decisions:Array<QuoteRoleDecision>, text:String, baseClassifier:FontRoleClassifier,
            context:FontRoleContext):Array<RoleOverrideInfo> {
        final sorted = new Array<QuoteRoleDecision>();
        for (i in 0...decisions.length)
            sorted.push(decisions[i]);
        var rIdx = 1;
        while (rIdx < sorted.length) {
            final curr = sorted[rIdx];
            var j = rIdx - 1;
            while (j >= 0 && sorted[j].index > curr.index) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = curr;
            rIdx++;
        }
        final result = new Array<RoleOverrideInfo>();
        for (i in 0...sorted.length) {
            final decision = sorted[i];
            final index = decision.index;
            final endIdx = (index + 1 < text.length) ? (index + 1) : text.length;
            final sourceText = text.substring(index, endIdx);
            final originalRole = baseClassifier.classify(text, new TextRange(index, index + 1), context);
            result.push(new RoleOverrideInfo(new TextRange(index, index + 1), sourceText, Std.string(originalRole), Std.string(decision.role),
                decision.source, decision.reason));
        }
        return result;
    }

    public static function toWidthIndependentAnnotationKey(input:LayoutInput,
            ?rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>):WidthIndependentAnnotationKey {
        final tiers = rejectedTechnicalTiersBySpan != null ? rejectedTechnicalTiersBySpan : SortedMap.builder().build();
        return new WidthIndependentAnnotationKey(input.content.text, input.content.spans, input.content.lineBreakSpans, input.content.sourceBoundaries,
            input.textStyle, input.decorations, input.rubySpans, input.inlineBoxes, input.inlineObjects, input.profileId,
            input.paragraphStyle.emphasisDotGapEm, tiers);
    }

    private static function clampInt(val:Int, min:Int, max:Int):Int {
        return val < min ? min : (val > max ? max : val);
    }

    private static function isInlineStop(code:Int):Bool {
        return code == 0x3002 || code == 0xFF01 || code == 0xFF1F || code == 0xFF0E;
    }

    public static function prepareWidthIndependentAnnotation(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput,
            rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>):WidthIndependentParagraphAnnotation {
        final text = input.content.text;
        final fontSize = input.textStyle.fontSize;

        final inlineObjectByRangeBuilder = SortedMap.builder();
        for (i in 0...input.inlineObjects.length) {
            final obj = input.inlineObjects[i];
            inlineObjectByRangeBuilder.put(obj.range, obj);
        }
        final inlineObjectByRange = inlineObjectByRangeBuilder.build();

        final sizedSpans = new Array<TextSpan>();
        for (i in 0...input.content.spans.length) {
            final sp = input.content.spans[i];
            if (sp.range.start < sp.range.end)
                sizedSpans.push(sp);
        }

        function styleAt(offset:Int):TextStyle {
            var lastSpan:Null<TextSpan> = null;
            for (i in 0...sizedSpans.length) {
                final sp = sizedSpans[i];
                if (offset >= sp.range.start && offset < sp.range.end) {
                    lastSpan = sp;
                }
            }
            return lastSpan != null ? lastSpan.style : input.textStyle;
        }

        function fontSizeAt(offset:Int):Float {
            return styleAt(offset).fontSize;
        }

        final emphasisRanges = new Array<TextRange>();
        for (i in 0...input.decorations.length) {
            final d = input.decorations[i];
            if (d.kind == DecorationKind.Emphasis) {
                emphasisRanges.push(d.range);
            }
        }

        function emphasisItalicAt(offset:Int):Bool {
            for (i in 0...emphasisRanges.length) {
                final r = emphasisRanges[i];
                if (offset >= r.start && offset < r.end)
                    return true;
            }
            return false;
        }

        final rubyFontSize = fontSize * RUBY_FONT_EM;
        final rubyStackGap = fontSize * RUBY_STACK_GAP_EM;
        final rubyFontWeight = clampInt(input.textStyle.fontWeight + RUBY_FONT_WEIGHT_BOOST, 1, 900);

        function bopomofoFontWeightAt(offset:Int):Int {
            return clampInt(styleAt(offset).fontWeight + BOPOMOFO_FONT_WEIGHT_BOOST, 1, 900);
        }

        final pinyinSpans = new Array<RubySpan>();
        for (i in 0...input.rubySpans.length) {
            final rs = input.rubySpans[i];
            if (rs.kind == RubyKind.Pinyin)
                pinyinSpans.push(rs);
        }

        final spanBoundariesBuilder = SortedSet.builder();
        function addSpanBoundary(offset:Int):Void {
            if (offset > 0 && offset < text.length)
                spanBoundariesBuilder.put(offset);
        }
        function addSpanRange(range:TextRange):Void {
            addSpanBoundary(range.start);
            addSpanBoundary(range.end);
        }
        for (i in 0...sizedSpans.length)
            addSpanRange(sizedSpans[i].range);
        for (i in 0...input.decorations.length)
            addSpanRange(input.decorations[i].range);
        for (i in 0...input.rubySpans.length)
            addSpanRange(input.rubySpans[i].baseRange);
        for (i in 0...input.inlineBoxes.length)
            addSpanRange(input.inlineBoxes[i].range);
        for (i in 0...input.inlineObjects.length)
            addSpanRange(input.inlineObjects[i].range);
        for (i in 0...input.content.lineBreakSpans.length)
            addSpanRange(input.content.lineBreakSpans[i].range);
        for (i in 0...input.content.sourceBoundaries.length)
            addSpanBoundary(input.content.sourceBoundaries[i]);
        final spanBoundaries = spanBoundariesBuilder.build();

        final emojiShapingBoundariesBuilder = SortedSet.builder();
        function addEmojiBoundary(offset:Int):Void {
            if (offset > 0 && offset < text.length)
                emojiShapingBoundariesBuilder.put(offset);
        }
        function addEmojiRange(range:TextRange):Void {
            addEmojiBoundary(range.start);
            addEmojiBoundary(range.end);
        }
        for (i in 0...sizedSpans.length)
            addEmojiRange(sizedSpans[i].range);
        for (i in 0...input.inlineBoxes.length) {
            final box = input.inlineBoxes[i];
            if (box.inlineStart != 0.0 || box.inlineEnd != 0.0 || box.outerSpacing == InlineBoxOuterSpacing.Narrow) {
                addEmojiRange(box.range);
            }
        }
        for (i in 0...input.inlineObjects.length)
            addEmojiRange(input.inlineObjects[i].range);
        final emojiShapingBoundaries = emojiShapingBoundariesBuilder.build();

        final clreqProfile = engine.clreqProfileResolver.resolve(input.profileId);
        final context = new FontRoleContext(input.textStyle.locale, Std.string(clreqProfile.region));
        final punctuationGlyphSubstitutor = new ClreqPunctuationGlyphSubstitutor(clreqProfile.punctuationGlyphPolicy);

        final quotePairs = engine.quotePairAnalyzer.analyze(text);
        final quoteRoleDecisions = engine.quotePairAnalyzer.classifyQuoteRoles(text, quotePairs, context);
        final quoteRoleOverridesBuilder = SortedMap.builder();
        for (i in 0...quoteRoleDecisions.length) {
            quoteRoleOverridesBuilder.put(quoteRoleDecisions[i].index, quoteRoleDecisions[i].role);
        }
        final quoteRoleOverrides = quoteRoleOverridesBuilder.build();
        final quoteRoleOverrideInfos = quoteToRoleOverrideInfos(quoteRoleDecisions, text, engine.fontRoleClassifier, context);
        final quoteAwareClassifier:FontRoleClassifier = quoteRoleOverrides.size() > 0 ? new QuotePairAwareFontRoleClassifier(engine.fontRoleClassifier,
            quoteRoleOverrides) : engine.fontRoleClassifier;

        final dashEllipsisRoleDecisions = new ContextualDashEllipsisRoleResolver().resolve(text, context);
        final dashEllipsisRoleOverrideInfos = ContextualDashEllipsisRoles.toRoleOverrideInfos(dashEllipsisRoleDecisions, text, quoteAwareClassifier, context);
        final effectiveClassifier:FontRoleClassifier = dashEllipsisRoleDecisions.length > 0 ? new ContextualDashEllipsisAwareFontRoleClassifier(quoteAwareClassifier,
            dashEllipsisRoleDecisions) : quoteAwareClassifier;

        final inlineObjectByStartBuilder = SortedMap.builder();
        for (i in 0...input.inlineObjects.length) {
            final obj = input.inlineObjects[i];
            inlineObjectByStartBuilder.put(obj.range.start, obj);
        }
        final clusterRanges = ClusterRoleResolution.clusterRoleRanges(text, effectiveClassifier, context, clreqProfile, spanBoundaries,
            emojiShapingBoundaries, inlineObjectByStartBuilder.build());

        final allRoleOverrides = new Array<RoleOverrideInfo>();
        for (i in 0...quoteRoleOverrideInfos.length)
            allRoleOverrides.push(quoteRoleOverrideInfos[i]);
        for (i in 0...dashEllipsisRoleOverrideInfos.length)
            allRoleOverrides.push(dashEllipsisRoleOverrideInfos[i]);
        for (i in 0...clusterRanges.length) {
            final ro = clusterRanges[i].roleOverride;
            if (ro != null)
                allRoleOverrides.push(ro);
        }
        var rIdx = 1;
        while (rIdx < allRoleOverrides.length) {
            final curr = allRoleOverrides[rIdx];
            var j = rIdx - 1;
            while (j >= 0 && allRoleOverrides[j].range.start > curr.range.start) {
                allRoleOverrides[j + 1] = allRoleOverrides[j];
                j--;
            }
            allRoleOverrides[j + 1] = curr;
            rIdx++;
        }
        final roleOverrideInfos = allRoleOverrides;

        final shapeableRanges = new Array<ResolvedClusterRange>();
        for (i in 0...clusterRanges.length) {
            final cr = clusterRanges[i];
            if (!cr.mandatoryBreak && !cr.zeroWidthSoftBreak && !inlineObjectByRange.has(cr.range)) {
                shapeableRanges.push(cr);
            }
        }
        final fontDecisions = new Array<FontDecision>();
        final fontDecisionByRangeBuilder = SortedMap.builder();
        for (i in 0...shapeableRanges.length) {
            final resolvedRange = shapeableRanges[i];
            final decision = engine.fallbackResolver.resolve(text, resolvedRange.range,
                new FontRequest(input.textStyle.fontFamilies, input.textStyle.locale, resolvedRange.role));
            fontDecisions.push(decision);
            fontDecisionByRangeBuilder.put(resolvedRange.range, decision);
        }
        final fontDecisionByRange = fontDecisionByRangeBuilder.build();

        final baseShapingStage = ParagraphShapingStage.shapeParagraph(engine, input, text, fontSize, 1e9, clusterRanges, fontDecisionByRange,
            inlineObjectByRange, punctuationGlyphSubstitutor, styleAt, emphasisItalicAt, rejectedTechnicalTiersBySpan);

        final rubyFontGeometryBuilder = SortedMap.builder();
        for (i in 0...pinyinSpans.length) {
            final ruby = pinyinSpans[i];
            final metricText = ruby.text.length == 0 ? "x" : ruby.text;
            final range = new TextRange(0, metricText.length);
            final preferredFamilies = ruby.fontFamilies;
            final rubyLocale = ruby.locale != null ? ruby.locale : input.textStyle.locale;
            final decision = engine.fallbackResolver.resolve(metricText, range, new FontRequest(preferredFamilies, rubyLocale, FontRole.LatinText));
            final raw = engine.fontMetricsResolver.resolve(new FontMetricsRequest(decision.candidate.key, rubyFontSize, FontRole.LatinText, rubyLocale,
                copyFontFamilies(preferredFamilies), rubyFontWeight, input.textStyle.italic, metricText));
            final declaredAscent = raw.typoAscent != null ? raw.typoAscent : raw.ascent;
            final declaredDescent = raw.typoDescent != null ? raw.typoDescent : raw.descent;
            var shaped:Null<ShapingResult> = null;
            if (ruby.text.length > 0) {
                shaped = engine.textShaper.shape(new ShapingInput(ruby.text, new TextRange(0, ruby.text.length),
                    new TextStyle(copyFontFamilies(ruby.fontFamilies), rubyFontSize, rubyLocale, rubyFontWeight, input.textStyle.italic,
                        input.textStyle.baselineShift, input.textStyle.inlineAttachment),
                    decision, ruby.text));
            }
            var rubyWidth = 0.0;
            final glyphList = new Array<Glyph>();
            if (shaped != null) {
                for (c in 0...shaped.clusters.length) {
                    rubyWidth += shaped.clusters[c].advance;
                }
                for (r in 0...shaped.glyphRuns.length) {
                    final run = shaped.glyphRuns[r];
                    for (g in 0...run.glyphs.length) {
                        glyphList.push(run.glyphs[g]);
                    }
                }
            }
            final requiredExtent = ruby.text.length == 0 ? 0.0 : (declaredAscent + declaredDescent + rubyStackGap);
            final ascent = ruby.text.length == 0 ? 0.0 : declaredAscent;
            final descent = ruby.text.length == 0 ? 0.0 : declaredDescent;
            final geom = new RubyFontGeometry(rubyWidth, ascent, descent, requiredExtent, glyphList);
            rubyFontGeometryBuilder.put(ruby, geom);
        }
        final rubyFontGeometryBySpan = rubyFontGeometryBuilder.build();

        return new WidthIndependentParagraphAnnotation(text, fontSize, styleAt, fontSizeAt, bopomofoFontWeightAt, rubyFontSize, rubyStackGap, rubyFontWeight,
            pinyinSpans, clreqProfile, punctuationGlyphSubstitutor, quotePairs, roleOverrideInfos, fontDecisions, clusterRanges, fontDecisionByRange,
            inlineObjectByRange, baseShapingStage.segmentShapingCache, baseShapingStage.substitutionRollbacks, rubyFontGeometryBySpan, baseShapingStage);
    }

    private static function computeRubySpread(natural:Array<Cluster>, rubySize:Float, pinyinSpans:Array<RubySpan>,
            rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>):SortedMap<Int, Float> {
        if (pinyinSpans.length == 0)
            return SortedMap.builder().build();
        final wordSpace = rubySize * RUBY_MIN_GAP_EM_OF_RUBY;
        final leftX = new Array<Float>();
        var acc = 0.0;
        for (i in 0...natural.length) {
            leftX.push(acc);
            acc += natural[i].advance;
        }

        final measuresFirstCluster = new Array<Int>();
        final measuresCenter = new Array<Float>();
        final measuresRw = new Array<Float>();
        for (i in 0...pinyinSpans.length) {
            final ruby = pinyinSpans[i];
            final idxRange = PunctuationGeometryLedger.clusterIndexRangeFor(natural, ruby.baseRange);
            if (idxRange == null)
                continue;
            final center = (leftX[idxRange.start] + leftX[idxRange.end] + natural[idxRange.end].advance) / 2.0;
            final geom = rubyFontGeometryBySpan.get(ruby);
            measuresFirstCluster.push(idxRange.start);
            measuresCenter.push(center);
            measuresRw.push(geom.width);
        }
        var mIdx = 1;
        while (mIdx < measuresFirstCluster.length) {
            final currFc = measuresFirstCluster[mIdx];
            final currCenter = measuresCenter[mIdx];
            final currRw = measuresRw[mIdx];
            var j = mIdx - 1;
            while (j >= 0 && measuresFirstCluster[j] > currFc) {
                measuresFirstCluster[j + 1] = measuresFirstCluster[j];
                measuresCenter[j + 1] = measuresCenter[j];
                measuresRw[j + 1] = measuresRw[j];
                j--;
            }
            measuresFirstCluster[j + 1] = currFc;
            measuresCenter[j + 1] = currCenter;
            measuresRw[j + 1] = currRw;
            mIdx++;
        }

        final spreadBuilder = SortedMap.builder();
        final spreadKeys = new Array<Int>();
        final spreadValues = new Array<Float>();
        function getSpread(key:Int):Float {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key)
                    return spreadValues[i];
            }
            return 0.0;
        }
        function putSpread(key:Int, val:Float):Void {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key) {
                    spreadValues[i] = val;
                    return;
                }
            }
            spreadKeys.push(key);
            spreadValues.push(val);
        }

        var shift = 0.0;
        var prevRight = -1e9;
        for (m in 0...measuresFirstCluster.length) {
            final firstCluster = measuresFirstCluster[m];
            final rw = measuresRw[m];
            var center = measuresCenter[m] + shift;
            final needed = prevRight + wordSpace - (center - rw / 2.0);
            if (needed > 0.0 && firstCluster > 0) {
                final key = firstCluster - 1;
                putSpread(key, getSpread(key) + needed);
                shift += needed;
                center += needed;
            }
            prevRight = center + rw / 2.0;
        }
        for (i in 0...spreadKeys.length) {
            spreadBuilder.put(spreadKeys[i], spreadValues[i]);
        }
        return spreadBuilder.build();
    }

    private static function addGeometryAwareOpportunity(shrinkOpportunities:Array<ShrinkOpportunity>,
            caps:org.tiqian.layout.PunctuationGeometryLedger.GlueCapacity, idx:Int, tier:Int, lineEndOnly:Bool = false):Void {
        if (caps.paired) {
            final minGlue = caps.leading < caps.trailing ? caps.leading : caps.trailing;
            final pairedCapacity = 2.0 * minGlue;
            if (pairedCapacity > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, pairedCapacity, ShrinkChannel.LeadingAndTrailingGlue, lineEndOnly));
            }
        } else {
            if (caps.leading > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, caps.leading, ShrinkChannel.LeadingGlue, lineEndOnly));
            }
            if (caps.trailing > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, caps.trailing, ShrinkChannel.TrailingGlue, lineEndOnly));
            }
        }
    }

    public static function buildParagraphLayoutPrep(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput,
            annotation:WidthIndependentParagraphAnnotation, rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>):ParagraphLayoutPrep {
        final text = annotation.text;
        final fontSize = input.textStyle.fontSize;
        final grid = input.paragraphStyle.lineLengthGrid;
        final containerWidth = input.constraints.maxWidth;
        var gridCells = Math.floor(containerWidth / fontSize);
        if (gridCells < 1)
            gridCells = 1;
        final gridCellsInt = Std.int(gridCells);
        var measure = containerWidth;
        if (grid.enabled) {
            measure = gridCellsInt * fontSize;
            if (measure > containerWidth)
                measure = containerWidth;
        }
        final gridSlack = containerWidth - measure;
        final gridBodyAlignment = grid.bodyAlignment != null ? grid.bodyAlignment : input.paragraphStyle.lastLineAlignment;
        var gridBodyOffset = 0.0;
        if (grid.enabled) {
            if (gridBodyAlignment == LastLineAlignment.Center) {
                gridBodyOffset = gridSlack / 2.0;
            } else if (gridBodyAlignment == LastLineAlignment.End) {
                gridBodyOffset = gridSlack;
            }
        }
        final lineLengthGridDecision = new LineLengthGridDecisionInfo(grid.enabled, containerWidth, fontSize,
            grid.enabled ? gridCellsInt : Std.int(measure / fontSize), measure, gridSlack, Std.string(gridBodyAlignment), gridBodyOffset,
            grid.enabled ? "LineLengthGridQuantization" : "GridBypassed");
        final measureEm = measure / fontSize;
        final resolvedKinsoku = KinsokuModes.resolve(annotation.clreqProfile.kinsokuMode, measureEm);
        final kinsokuRule = new ClreqKinsokuRule(resolvedKinsoku.level);

        var hasProgSpan = false;
        for (i in 0...input.content.lineBreakSpans.length) {
            if (input.content.lineBreakSpans[i].policy == LineBreakPolicy.ProgressiveTechnical) {
                hasProgSpan = true;
                break;
            }
        }
        var hasOverMeasureToken = false;
        for (i in 0...annotation.baseShapingStage.shapingResults.length) {
            final res = annotation.baseShapingStage.shapingResults[i];
            var resAdv = 0.0;
            for (c in 0...res.clusters.length)
                resAdv += res.clusters[c].advance;
            if (resAdv > measure) {
                hasOverMeasureToken = true;
                break;
            }
        }
        final needsDynamicShaping = (rejectedTechnicalTiersBySpan != null && rejectedTechnicalTiersBySpan.size() > 0)
            || hasProgSpan
            || hasOverMeasureToken;

        var shapingStage = annotation.baseShapingStage;
        if (needsDynamicShaping) {
            shapingStage = ParagraphShapingStage.shapeParagraph(engine, input, text, fontSize, measure, annotation.clusterRanges,
                annotation.fontDecisionByRange, annotation.inlineObjectByRange, annotation.punctuationGlyphSubstitutor, annotation.styleAt,
                function(offset:Int):Bool {
                    for (i in 0...input.decorations.length) {
                        final d = input.decorations[i];
                        if (d.kind == DecorationKind.Emphasis && offset >= d.range.start && offset < d.range.end) {
                            return true;
                        }
                    }
                    return false;
                }, rejectedTechnicalTiersBySpan, annotation.segmentShapingCache,
                annotation.substitutionRollbacks);
        }

        final shapingResults = shapingStage.shapingResults;
        final rawNaturalClusters = new Array<Cluster>();
        for (i in 0...shapingResults.length) {
            final res = shapingResults[i];
            for (c in 0...res.clusters.length)
                rawNaturalClusters.push(res.clusters[c]);
        }

        final shapedGlyphsByClusterRangeBuilder = SortedMap.builder();
        final openTypeFeaturesByClusterRangeBuilder = SortedMap.builder();

        final glyphsByClusterRangeKeys = new Array<TextRange>();
        final glyphsByClusterRangeValues = new Array<Array<Glyph>>();
        final openTypeFeatureKeys = new Array<TextRange>();
        final openTypeFeatureValues = new Array<Array<String>>();
        function addGlyphToClusterRange(range:TextRange, g:Glyph):Void {
            for (i in 0...glyphsByClusterRangeKeys.length) {
                if (glyphsByClusterRangeKeys[i].start == range.start && glyphsByClusterRangeKeys[i].end == range.end) {
                    glyphsByClusterRangeValues[i].push(g);
                    return;
                }
            }
            glyphsByClusterRangeKeys.push(range);
            glyphsByClusterRangeValues.push([g]);
        }

        for (i in 0...shapingResults.length) {
            final res = shapingResults[i];
            for (r in 0...res.glyphRuns.length) {
                final run = res.glyphRuns[r];
                final seenRanges = new Array<TextRange>();
                for (g in 0...run.glyphs.length) {
                    final glyph = run.glyphs[g];
                    addGlyphToClusterRange(glyph.clusterRange, glyph);
                    var rangeSeen = false;
                    for (sr in 0...seenRanges.length) {
                        if (seenRanges[sr].start == glyph.clusterRange.start && seenRanges[sr].end == glyph.clusterRange.end) {
                            rangeSeen = true;
                            break;
                        }
                    }
                    if (!rangeSeen)
                        seenRanges.push(glyph.clusterRange);
                }
                for (sr in 0...seenRanges.length) {
                    final range = seenRanges[sr];
                    final featCopy = new Array<String>();
                    for (fi in 0...run.openTypeFeatures.length)
                        featCopy.push(run.openTypeFeatures[fi]);
                    var previousFeatures:Array<String> = null;
                    for (pi in 0...openTypeFeatureKeys.length) {
                        if (openTypeFeatureKeys[pi].start == range.start && openTypeFeatureKeys[pi].end == range.end) {
                            previousFeatures = openTypeFeatureValues[pi];
                            break;
                        }
                    }
                    if (previousFeatures != null) {
                        var sameFeatures = previousFeatures.length == featCopy.length;
                        if (sameFeatures) {
                            for (fi in 0...previousFeatures.length) {
                                if (previousFeatures[fi] != featCopy[fi]) {
                                    sameFeatures = false;
                                    break;
                                }
                            }
                        }
                        if (!sameFeatures)
                            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Conflicting OpenType features for shaped cluster "
                                + Std.string(range)));
                    }
                    openTypeFeatureKeys.push(range);
                    openTypeFeatureValues.push(featCopy);
                    openTypeFeaturesByClusterRangeBuilder.put(range, featCopy);
                }
            }
        }
        for (i in 0...glyphsByClusterRangeKeys.length) {
            shapedGlyphsByClusterRangeBuilder.put(glyphsByClusterRangeKeys[i], glyphsByClusterRangeValues[i]);
        }
        final shapedGlyphsByClusterRange = shapedGlyphsByClusterRangeBuilder.build();
        final openTypeFeaturesByClusterRange = openTypeFeaturesByClusterRangeBuilder.build();

        ClusterRoleResolution.requireCoveredBy(rawNaturalClusters, annotation.fontDecisions);

        final inlineObjectRanges = new Array<TextRange>();
        for (i in 0...input.inlineObjects.length)
            inlineObjectRanges.push(input.inlineObjects[i].range);

        final narrowInlineBoxRanges = new Array<TextRange>();
        for (i in 0...input.inlineBoxes.length) {
            final box = input.inlineBoxes[i];
            if (box.outerSpacing == InlineBoxOuterSpacing.Narrow) {
                narrowInlineBoxRanges.push(box.range);
            }
        }

        final narrowInlineBoxLeadingClustersBuilder = SortedSet.builder();
        final narrowInlineBoxTrailingClustersBuilder = SortedSet.builder();
        for (idx in 0...rawNaturalClusters.length) {
            final cl = rawNaturalClusters[idx];
            for (j in 0...narrowInlineBoxRanges.length) {
                if (narrowInlineBoxRanges[j].start == cl.range.start) {
                    narrowInlineBoxLeadingClustersBuilder.put(idx);
                }
                if (narrowInlineBoxRanges[j].end == cl.range.end) {
                    narrowInlineBoxTrailingClustersBuilder.put(idx);
                }
            }
        }
        final narrowInlineBoxLeadingClusters = narrowInlineBoxLeadingClustersBuilder.build();
        final narrowInlineBoxTrailingClusters = narrowInlineBoxTrailingClustersBuilder.build();

        final resolvedSpacingEdges = new Array<EastAsianSpacingEdges>();
        for (index in 0...rawNaturalClusters.length) {
            final cluster = rawNaturalClusters[index];
            var isContained = false;
            for (j in 0...inlineObjectRanges.length) {
                if (isContainedIn(cluster.range, inlineObjectRanges[j])) {
                    isContained = true;
                    break;
                }
            }
            if (isContained
                || (PunctuationGeometryStage.isAttachedAsciiPointMarkAt(rawNaturalClusters, index)
                    && !narrowInlineBoxLeadingClusters.has(index))) {
                resolvedSpacingEdges.push(new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false));
            } else {
                final resolved = UnicodeEastAsianSpacing.resolvedEdges(cluster.text, input.textStyle.locale);
                final leadingVal = narrowInlineBoxLeadingClusters.has(index) ? EastAsianSpacingValue.Narrow : resolved.leading;
                final trailingVal = narrowInlineBoxTrailingClusters.has(index) ? EastAsianSpacingValue.Narrow : resolved.trailing;
                resolvedSpacingEdges.push(new EastAsianSpacingEdges(leadingVal, trailingVal, resolved.containsWide));
            }
        }

        final verbatimRanges = input.content.autoSpaceSuppressedRanges;
        function verbatimSuppressedBoundary(offset:Int):Bool {
            for (i in 0...verbatimRanges.length) {
                final vr = verbatimRanges[i];
                if (vr.start < offset && offset < vr.end)
                    return true;
            }
            return false;
        }

        var eastAsianSpacingEdges = resolvedSpacingEdges;
        if (verbatimRanges.length > 0) {
            final list = new Array<EastAsianSpacingEdges>();
            for (index in 0...resolvedSpacingEdges.length) {
                final edges = resolvedSpacingEdges[index];
                final cluster = rawNaturalClusters[index];
                final leadingSuppressed = !narrowInlineBoxLeadingClusters.has(index) && verbatimSuppressedBoundary(cluster.range.start);
                final trailingSuppressed = !narrowInlineBoxTrailingClusters.has(index) && verbatimSuppressedBoundary(cluster.range.end);
                if (!leadingSuppressed && !trailingSuppressed) {
                    list.push(edges);
                } else {
                    list.push(new EastAsianSpacingEdges(leadingSuppressed ? EastAsianSpacingValue.Other : edges.leading,
                        trailingSuppressed ? EastAsianSpacingValue.Other : edges.trailing, edges.containsWide));
                }
            }
            eastAsianSpacingEdges = list;
        }

        final verbatimSuppressionDecisions = new Array<AutoSpaceDecisionInfo>();
        if (verbatimRanges.length > 0) {
            for (index in 1...rawNaturalClusters.length) {
                final offset = rawNaturalClusters[index].range.start;
                if (!verbatimSuppressedBoundary(offset))
                    continue;
                final left = resolvedSpacingEdges[index - 1].trailing;
                final right = resolvedSpacingEdges[index].leading;
                final wideNarrowPair = (left == EastAsianSpacingValue.Wide && right == EastAsianSpacingValue.Narrow)
                    || (left == EastAsianSpacingValue.Narrow && right == EastAsianSpacingValue.Wide);
                if (!wideNarrowPair)
                    continue;
                verbatimSuppressionDecisions.push(new AutoSpaceDecisionInfo(rawNaturalClusters[index].range, "leading", "EastAsianSpacing.Wide",
                    Std.string(AutoSpaceMode.Disabled), 0, 0.0, 0.0, "VerbatimRangeAutoSpace:east-asian-spacing-W-N-suppressed"));
            }
        }

        final naturalInlineAttachments = new Array<InlineAttachment>();
        for (i in 0...rawNaturalClusters.length) {
            naturalInlineAttachments.push(annotation.styleAt(rawNaturalClusters[i].range.start).inlineAttachment);
        }

        final autoSpaceResult = PunctuationGeometryStage.applyAutoSpacePolicy(rawNaturalClusters, eastAsianSpacingEdges, naturalInlineAttachments,
            annotation.clreqProfile.autoSpace, fontSize, narrowInlineBoxLeadingClusters, narrowInlineBoxTrailingClusters);

        final inlineBoxesCopy = new Array<InlineBoxSpan>();
        for (i in 0...input.inlineBoxes.length)
            inlineBoxesCopy.push(input.inlineBoxes[i]);
        final inlineBoxResult = PunctuationGeometryStage.applyInlineBoxSpans(autoSpaceResult.clusters, inlineBoxesCopy);
        final naturalClusters = inlineBoxResult.clusters;

        final inlineObjectByClusterIndexBuilder = SortedMap.builder();
        final boundaryIndices = new Array<Int>();
        final boundaryAdjustments = new Array<InlineObjectBoundaryAdjustment>();

        function getRegisteredBoundary(leftClusterIndex:Int):Null<InlineObjectBoundaryAdjustment> {
            for (i in 0...boundaryIndices.length) {
                if (boundaryIndices[i] == leftClusterIndex)
                    return boundaryAdjustments[i];
            }
            return null;
        }

        function setRegisteredBoundary(leftClusterIndex:Int, boundary:InlineObjectBoundaryAdjustment):Void {
            for (i in 0...boundaryIndices.length) {
                if (boundaryIndices[i] == leftClusterIndex) {
                    boundaryAdjustments[i] = boundary;
                    return;
                }
            }
            boundaryIndices.push(leftClusterIndex);
            boundaryAdjustments.push(boundary);
        }

        function registerInlineObjectBoundary(leftClusterIndex:Int, boundary:InlineObjectBoundaryAdjustment):Void {
            final previous = getRegisteredBoundary(leftClusterIndex);
            if (previous == null) {
                setRegisteredBoundary(leftClusterIndex, boundary);
                return;
            }
            var prevKind = previous.preferredStretch != null ? previous.preferredStretch.kind : null;
            var boundKind = boundary.preferredStretch != null ? boundary.preferredStretch.kind : null;
            if (prevKind != null && boundKind != null && prevKind != boundKind) {
                throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Conflicting inline-object stretch classes at cluster boundary "
                    + leftClusterIndex));
            }
            var preferred:Null<InlineObjectPreferredStretch> = null;
            if (previous.preferredStretch != null && boundary.preferredStretch != null) {
                preferred = previous.preferredStretch.capacity >= boundary.preferredStretch.capacity ? previous.preferredStretch : boundary.preferredStretch;
            } else if (previous.preferredStretch != null) {
                preferred = previous.preferredStretch;
            } else {
                preferred = boundary.preferredStretch;
            }
            setRegisteredBoundary(leftClusterIndex,
                new InlineObjectBoundaryAdjustment(previous.participatesInUniformStretch
                    || boundary.participatesInUniformStretch, preferred,
                    Math.max(previous.shrinkCapacity, boundary.shrinkCapacity),
                    Math.max(previous.lineEndDiscardableAdvance, boundary.lineEndDiscardableAdvance), previous.preventsLineBreak || boundary.preventsLineBreak));
        }

        for (clusterIndex in 0...naturalClusters.length) {
            final cluster = naturalClusters[clusterIndex];
            if (annotation.inlineObjectByRange.has(cluster.range)) {
                final inlineObject = annotation.inlineObjectByRange.get(cluster.range);
                inlineObjectByClusterIndexBuilder.put(clusterIndex, inlineObject);
                if (clusterIndex > 0 && !isFixedBoundary(inlineObject.leadingBoundary)) {
                    registerInlineObjectBoundary(clusterIndex - 1, inlineObject.leadingBoundary);
                }
                if (clusterIndex < naturalClusters.length - 1 && !isFixedBoundary(inlineObject.trailingBoundary)) {
                    registerInlineObjectBoundary(clusterIndex, inlineObject.trailingBoundary);
                }
            }
        }
        final inlineObjectByClusterIndex = inlineObjectByClusterIndexBuilder.build();

        final uniformInlineObjectBoundaryBuilder = SortedSet.builder();
        final preferredInlineObjectBoundaryBuilder = SortedMap.builder();
        final inlineObjectBoundaryUnbreakableRanges = new Array<IntRange>();

        for (i in 0...boundaryIndices.length) {
            final bIdx = boundaryIndices[i];
            final bAdj = boundaryAdjustments[i];
            if (bAdj.participatesInUniformStretch) {
                uniformInlineObjectBoundaryBuilder.put(bIdx);
            }
            if (bAdj.preferredStretch != null) {
                preferredInlineObjectBoundaryBuilder.put(bIdx, bAdj.preferredStretch);
            }
            if (bAdj.preventsLineBreak) {
                inlineObjectBoundaryUnbreakableRanges.push(new IntRange(bIdx, bIdx + 1));
            }
        }
        final uniformInlineObjectBoundaryAfterClusters = uniformInlineObjectBoundaryBuilder.build();
        final preferredInlineObjectBoundaryAfterClusters = preferredInlineObjectBoundaryBuilder.build();

        final autoSpaceDecisions = new Array<AutoSpaceDecisionInfo>();
        for (i in 0...autoSpaceResult.decisions.length)
            autoSpaceDecisions.push(autoSpaceResult.decisions[i]);
        for (i in 0...verbatimSuppressionDecisions.length)
            autoSpaceDecisions.push(verbatimSuppressionDecisions[i]);

        final clusterRolesDecisions = containingFontDecisions(naturalClusters, annotation.fontDecisions);
        final clusterRoles = new Array<FontRole>();
        for (i in 0...clusterRolesDecisions.length) {
            final d = clusterRolesDecisions[i];
            clusterRoles.push(d != null ? d.role : FontRole.Unknown);
        }

        final inlineObjectAttachedMarks = PunctuationGeometryStage.inlineObjectAttachedMarks(naturalClusters, clusterRoles, resolvedKinsoku.level, kinsokuRule);

        final inlineObjectSeparatorSpaceTrimsBuilder = SortedMap.builder();
        final inlineObjectAttachmentNoStretchBoundariesBuilder = SortedSet.builder();
        final inlineObjectPunctuationAttachmentDecisions = new Array<InlineObjectPunctuationAttachmentDecisionInfo>();

        for (a in 0...inlineObjectAttachedMarks.length) {
            final attachment = inlineObjectAttachedMarks[a];
            for (s in 0...attachment.separatorClusterIndices.length) {
                final clusterIndex = attachment.separatorClusterIndices[s];
                inlineObjectSeparatorSpaceTrimsBuilder.put(clusterIndex, naturalClusters[clusterIndex].advance);
            }
            for (idx in attachment.objectClusterIndex...attachment.markClusterIndex) {
                inlineObjectAttachmentNoStretchBoundariesBuilder.put(idx);
            }
            if (attachment.separatorClusterIndices.length > 0) {
                final separatorFirst = naturalClusters[attachment.separatorClusterIndices[0]];
                final separatorLast = naturalClusters[
                    attachment.separatorClusterIndices[attachment.separatorClusterIndices.length - 1]
                ];
                final mark = naturalClusters[attachment.markClusterIndex];
                var collapsedAdv = 0.0;
                for (s in 0...attachment.separatorClusterIndices.length) {
                    collapsedAdv += naturalClusters[attachment.separatorClusterIndices[s]].advance;
                }
                inlineObjectPunctuationAttachmentDecisions.push(new InlineObjectPunctuationAttachmentDecisionInfo(naturalClusters[attachment.objectClusterIndex].range,
                    new TextRange(separatorFirst.range.start, separatorLast.range.end), mark.range,
                    mark.text, new TextRange(naturalClusters[attachment.objectClusterIndex].range.start, mark.range.end), collapsedAdv));
            }
        }
        final inlineObjectSeparatorSpaceTrims = inlineObjectSeparatorSpaceTrimsBuilder.build();
        final inlineObjectAttachmentNoStretchBoundaries = inlineObjectAttachmentNoStretchBoundariesBuilder.build();

        final mandatoryBreakClustersBuilder = SortedSet.builder();
        final zeroWidthBreakClustersBuilder = SortedSet.builder();
        final mandatoryBreakDecisions = new Array<MandatoryBreakDecisionInfo>();
        final zeroWidthBreakDecisions = new Array<ZeroWidthBreakDecisionInfo>();

        for (idx in 0...naturalClusters.length) {
            final cluster = naturalClusters[idx];
            if (ParagraphShapingStage.isMandatoryBreakCluster(cluster)) {
                mandatoryBreakClustersBuilder.put(idx);
                mandatoryBreakDecisions.push(new MandatoryBreakDecisionInfo(cluster.range, cluster.text, idx, "MandatoryBreakNoShape"));
            }
            if (ParagraphShapingStage.isZeroWidthSoftBreakCluster(cluster)) {
                zeroWidthBreakClustersBuilder.put(idx);
                zeroWidthBreakDecisions.push(new ZeroWidthBreakDecisionInfo(cluster.range, cluster.text, idx));
            }
        }
        final mandatoryBreakClusters = mandatoryBreakClustersBuilder.build();
        final zeroWidthBreakClusters = zeroWidthBreakClustersBuilder.build();

        final punctuationAtoms = new Array<PunctuationAtom>();
        for (idx in 0...naturalClusters.length) {
            if (clusterRoles[idx] == FontRole.LatinText)
                continue;
            final cluster = naturalClusters[idx];
            final shapedGlyphs = shapedGlyphsByClusterRange.has(cluster.range) ? shapedGlyphsByClusterRange.get(cluster.range) : [];
            final atoms = PunctuationGeometryStage.punctuationAtoms(cluster, fontSize, engine.punctuationAtomBuilder, shapedGlyphs,
                annotation.clreqProfile.gluePlacement, annotation.clreqProfile.punctuationWidth);
            for (a in 0...atoms.length)
                punctuationAtoms.push(atoms[a]);
        }

        final adjacentPunctuationSpacingPlan = engine.punctuationSpacingCompressor.compress(punctuationAtoms, fontSize);
        final cjkClosingBeforeAsciiPointMarkPlan = engine.punctuationSpacingCompressor.compressCjkClosingBeforeAsciiPointMark(punctuationAtoms, text, fontSize);
        final allAdjustments = new Array<org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment>();
        for (i in 0...adjacentPunctuationSpacingPlan.adjustments.length)
            allAdjustments.push(adjacentPunctuationSpacingPlan.adjustments[i]);
        for (i in 0...cjkClosingBeforeAsciiPointMarkPlan.adjustments.length)
            allAdjustments.push(cjkClosingBeforeAsciiPointMarkPlan.adjustments[i]);
        final spacingPlan = new PunctuationSpacingCompressionResult(allAdjustments);

        final rubySpread = computeRubySpread(naturalClusters, annotation.rubyFontSize, annotation.pinyinSpans, annotation.rubyFontGeometryBySpan);

        final bopomofoSpans = new Array<RubySpan>();
        for (i in 0...input.rubySpans.length) {
            final rs = input.rubySpans[i];
            if (rs.kind == RubyKind.Bopomofo)
                bopomofoSpans.push(rs);
        }

        var rubyAndBopomofoSpread = rubySpread;
        if (bopomofoSpans.length > 0) {
            final mergedBuilder = SortedMap.builder();
            final mergedKeys = new Array<Int>();
            final mergedVals = new Array<Float>();
            for (i in 0...rubySpread.size()) {
                mergedKeys.push(rubySpread.keyAt(i));
                mergedVals.push(rubySpread.valueAt(i));
            }
            for (i in 0...bopomofoSpans.length) {
                final z = bopomofoSpans[i];
                final r = PunctuationGeometryLedger.clusterIndexRangeFor(naturalClusters, z.baseRange);
                if (r == null)
                    continue;
                final lastIdx = r.end;
                var found = false;
                for (j in 0...mergedKeys.length) {
                    if (mergedKeys[j] == lastIdx) {
                        mergedVals[j] += 0.5 * fontSize;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    mergedKeys.push(lastIdx);
                    mergedVals.push(0.5 * fontSize);
                }
            }
            for (i in 0...mergedKeys.length) {
                mergedBuilder.put(mergedKeys[i], mergedVals[i]);
            }
            rubyAndBopomofoSpread = mergedBuilder.build();
        }

        final adjustmentStyle = annotation.clreqProfile.adjustment;

        final punctuationBaseGeometry = PunctuationGeometryLedger.from(naturalClusters, punctuationAtoms, spacingPlan)
            .withInlineBoxAdvances(inlineBoxResult.advanceByCluster)
            .withRubySpread(rubyAndBopomofoSpread)
            .withRawEdgeTrims(inlineObjectSeparatorSpaceTrims);

        final finalNaturalInlineAttachments = new Array<InlineAttachment>();
        for (i in 0...naturalClusters.length) {
            finalNaturalInlineAttachments.push(annotation.styleAt(naturalClusters[i].range.start).inlineAttachment);
        }

        final attachedPunctuationBoundary = punctuationBaseGeometry.resolveAttachedInlinePunctuationBoundaries(finalNaturalInlineAttachments,
            punctuationAtoms, fontSize);

        final baseGeometry = attachedPunctuationBoundary.geometry;
        final attachedPunctuationTrailingGlueByCluster = attachedPunctuationBoundary.trailingGlueByCluster;
        final clusters = baseGeometry.resolveClusters();

        final glueCaps = baseGeometry.glueCapacities();

        final gapClusterRanges = new Array<TextRange>();
        for (i in 0...autoSpaceDecisions.length) {
            final d = autoSpaceDecisions[i];
            if (d.side == "gap")
                gapClusterRanges.push(d.clusterRange);
        }

        final containedAtoms = firstContainedAtom(naturalClusters, punctuationAtoms);
        final atomClassByRangeBuilder = SortedMap.builder();
        for (i in 0...naturalClusters.length) {
            final atom = containedAtoms[i];
            if (atom != null) {
                atomClassByRangeBuilder.put(naturalClusters[i].range, atom.punctuationClass);
            }
        }
        final atomClassByRange = atomClassByRangeBuilder.build();

        final shrinkOpportunities = new Array<ShrinkOpportunity>();

        for (idx in 0...naturalClusters.length) {
            final cluster = naturalClusters[idx];
            if (glueCaps.has(idx)) {
                final caps = glueCaps.get(idx);
                final cls = atomClassByRange.has(cluster.range) ? atomClassByRange.get(cluster.range) : null;

                if (cls == PunctuationClass.Interpunct || cls == PunctuationClass.MiddleDot) {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 3);
                } else if (cls == PunctuationClass.Opening || cls == PunctuationClass.Closing) {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 4);
                } else if (cls == PunctuationClass.PauseOrStop) {
                    final firstChar = cluster.displayText.length > 0 ? cluster.displayText.charCodeAt(0) : 0;
                    final isStop = isInlineStop(firstChar);
                    final tier = isStop ? 7 : 5;
                    final lineEndOnly = isStop && !adjustmentStyle.allowInlineStopCompression;
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, tier, lineEndOnly);
                } else {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 5);
                }
            } else if (PunctuationGeometryStage.isSpaceRun(cluster) && !inlineObjectSeparatorSpaceTrims.has(idx)) {
                var inGap = false;
                for (g in 0...gapClusterRanges.length) {
                    final gr = gapClusterRanges[g];
                    if (gr.start == cluster.range.start && gr.end == cluster.range.end) {
                        inGap = true;
                        break;
                    }
                }
                if (inGap) {
                    final cap = cluster.advance - SINO_WESTERN_GAP_MIN_EM * fontSize;
                    if (adjustmentStyle.allowSinoWesternGapAdjustment && cap > 0.0) {
                        shrinkOpportunities.push(new ShrinkOpportunity(idx, 6, cap, ShrinkChannel.RawAdvance));
                    }
                } else {
                    final cap = cluster.advance - WORD_SPACE_MIN_EM * fontSize;
                    if (cap > 0.0) {
                        shrinkOpportunities.push(new ShrinkOpportunity(idx, 2, cap, ShrinkChannel.RawAdvance));
                    }
                }
            }
        }

        for (i in 0...inlineObjectByClusterIndex.size()) {
            final idx = inlineObjectByClusterIndex.keyAt(i);
            final inlineObject = inlineObjectByClusterIndex.valueAt(i);
            final trailing = inlineObject.trailingBoundary.shrinkCapacity;
            if (trailing > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, 8, trailing, ShrinkChannel.RawAdvance));
            }
        }

        final shapingDecisionsList = new Array<ShapingDecisionInfo>();
        for (srIdx in 0...shapingStage.shapingResults.length) {
            final sr = shapingStage.shapingResults[srIdx];
            for (dIdx in 0...sr.decisions.length) {
                shapingDecisionsList.push(sr.decisions[dIdx]);
            }
        }

        return new ParagraphLayoutPrep(input, rejectedTechnicalTiersBySpan, text, fontSize, annotation.styleAt, annotation.fontSizeAt,
            annotation.bopomofoFontWeightAt, annotation.rubyFontSize, annotation.rubyStackGap, annotation.rubyFontWeight, annotation.pinyinSpans,
            annotation.clreqProfile, annotation.punctuationGlyphSubstitutor, measure, measureEm, gridBodyOffset, lineLengthGridDecision,
            annotation.quotePairs, annotation.roleOverrideInfos, annotation.fontDecisions, shapingStage.hyphenOffsets, shapingStage.hyphenAdvance,
            shapingStage.hyphenGlyphs, shapingStage.substitutionRollbacks, shapingStage.breakOpportunityDecisions,
            shapingStage.emergencyTrackingEligibilityDecisions, shapingStage.progressiveBreakOffsets, shapedGlyphsByClusterRange,
            openTypeFeaturesByClusterRange, shapingDecisionsList, eastAsianSpacingEdges, autoSpaceDecisions, inlineBoxResult, naturalClusters,
            inlineObjectByClusterIndex, uniformInlineObjectBoundaryAfterClusters, preferredInlineObjectBoundaryAfterClusters,
            inlineObjectBoundaryUnbreakableRanges, clusterRoles, resolvedKinsoku, kinsokuRule, inlineObjectAttachedMarks, inlineObjectSeparatorSpaceTrims,
            inlineObjectAttachmentNoStretchBoundaries, inlineObjectPunctuationAttachmentDecisions, mandatoryBreakClusters, zeroWidthBreakClusters,
            mandatoryBreakDecisions, zeroWidthBreakDecisions, punctuationAtoms, spacingPlan, annotation.rubyFontGeometryBySpan, rubyAndBopomofoSpread,
            finalNaturalInlineAttachments, attachedPunctuationBoundary, baseGeometry, attachedPunctuationTrailingGlueByCluster, clusters, adjustmentStyle,
            atomClassByRange, shrinkOpportunities);
    }
}
