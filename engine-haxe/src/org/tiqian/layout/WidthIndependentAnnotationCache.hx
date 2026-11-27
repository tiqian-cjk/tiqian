package org.tiqian.layout;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.AccurateSum;
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
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteRoleDecision;
import org.tiqian.layout.QuotePairAnalyzer.QuotePairAwareFontRoleClassifier;
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
import org.tiqian.core.Glyph;
import org.tiqian.clreq.KinsokuLevel;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.ParagraphPrepParts.KinsokuDependentPrep;
import org.tiqian.layout.ParagraphPrepParts.ShapedParagraphBase;
import std.SortedSet;
import std.SortedMap;
import std.HashMap;

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
    /** Width-independent planning and debug values derived from `baseShapingStage`, filled on first use. */
    public final layoutMemo:WidthIndependentLayoutMemo;

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
        this.layoutMemo = new WidthIndependentLayoutMemo();
    }
}

interface WidthIndependentAnnotationCache {
    function get(key:WidthIndependentAnnotationKey):Null<WidthIndependentParagraphAnnotation>;
    function put(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation):Void;
    function clear():Void;
    public var size(get, never):Int;
}

/**
 * One cached annotation, its key and the slot it occupies in `LruWidthIndependentAnnotationCache`.
 * The class is public: boring's Kotlin target emitted no declaration for it as a module-private
 * class, and the cache's references to it did not resolve.
 */
class LruAnnotationEntry {
    public final key:WidthIndependentAnnotationKey;
    public final annotation:WidthIndependentParagraphAnnotation;
    public final slot:Int;

    public function new(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation, slot:Int) {
        this.key = key;
        this.annotation = annotation;
        this.slot = slot;
    }
}

/**
 * `LruWidthIndependentAnnotationCache`: at most `maxEntries` annotations; a put into a full cache
 * evicts the least recently used key. Every get and put takes the next value of a use counter and
 * stores it in `lastUse` at the slot of its key, so a hit costs one hash lookup and one array
 * write. A put into a full cache scans `lastUse` for the smallest value, the least recently used
 * key, and gives its slot to the new key. The former implementation kept the keys in recency
 * order and moved a key on every hit, which compared the key with each earlier key in turn.
 *
 * `slots` and the map hold separate entry objects with the same contents: boring's Rust target
 * moves a value assigned to an array element or put into the map, so one object cannot reach both.
 * Each write stores the slot's entry first and puts the map's entry last, the last use of `key`.
 */
class LruWidthIndependentAnnotationCache implements WidthIndependentAnnotationCache {
    public final maxEntries:Int;

    private final map:HashMap<WidthIndependentAnnotationKey, LruAnnotationEntry> = new HashMap();
    private final slots:Array<LruAnnotationEntry> = [];
    private final lastUse:Array<Int> = [];
    private var useCount:Int = 0;

    public var size(get, never):Int;

    public function new(maxEntries:Int = 512) {
        this.maxEntries = maxEntries;
    }

    public function get(key:WidthIndependentAnnotationKey):Null<WidthIndependentParagraphAnnotation> {
        final entry = map.get(key);
        if (entry == null)
            return null;
        useCount++;
        final now = useCount;
        lastUse[entry.slot] = now;
        return entry.annotation;
    }

    public function put(key:WidthIndependentAnnotationKey, annotation:WidthIndependentParagraphAnnotation):Void {
        useCount++;
        final now = useCount;
        final existing = map.get(key);
        if (existing != null) {
            final slot = existing.slot;
            lastUse[slot] = now;
            slots[slot] = new LruAnnotationEntry(key, annotation, slot);
            final entry = new LruAnnotationEntry(key, annotation, slot);
            map.set(key, entry);
            return;
        }
        if (slots.length >= maxEntries && slots.length > 0) {
            var oldest = 0;
            final count = lastUse.length;
            for (i in 1...count) {
                if (lastUse[i] < lastUse[oldest])
                    oldest = i;
            }
            final evicted = slots[oldest];
            map.remove(evicted.key);
            lastUse[oldest] = now;
            slots[oldest] = new LruAnnotationEntry(key, annotation, oldest);
            final entry = new LruAnnotationEntry(key, annotation, oldest);
            map.set(key, entry);
            return;
        }
        final slot = slots.length;
        lastUse.push(now);
        slots.push(new LruAnnotationEntry(key, annotation, slot));
        final entry = new LruAnnotationEntry(key, annotation, slot);
        map.set(key, entry);
    }

    public function clear():Void {
        map.clear();
        slots.splice(0, slots.length);
        lastUse.splice(0, lastUse.length);
        useCount = 0;
    }

    public function get_size():Int {
        return slots.length;
    }
}

class WidthIndependentAnnotationCacheFns {
    private static function renderNullableLastLineAlignment(value:Null<LastLineAlignment>):String
        return value == null ? "null" : renderLastLineAlignment(value);

    private static function renderLastLineAlignment(value:LastLineAlignment):String
        return Std.string(value);

    private static inline final RUBY_FONT_EM:Float = 0.5;
    private static inline final RUBY_FONT_WEIGHT_BOOST:Int = 100;
    private static inline final BOPOMOFO_FONT_WEIGHT_BOOST:Int = 300;
    private static inline final RUBY_STACK_GAP_EM:Float = 0.0;

    private static function copyFontFamilies(families:std.ReadOnlyArray<String>):Array<String> {
        final result = new Array<String>();
        for (i in 0...families.length) {
            result.push(families[i]);
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
            final rubyWidthTerms:Array<Float> = [];
            final glyphList = new Array<Glyph>();
            if (shaped != null) {
                for (c in 0...shaped.clusters.length) {
                    rubyWidthTerms.push(shaped.clusters[c].advance);
                }
                for (r in 0...shaped.glyphRuns.length) {
                    final run = shaped.glyphRuns[r];
                    for (g in 0...run.glyphs.length) {
                        glyphList.push(run.glyphs[g]);
                    }
                }
            }
            final rubyWidth = AccurateSum.of(rubyWidthTerms);
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

    /** `KinsokuLevelMemoKey`: the integer key of a kinsoku level in `WidthIndependentLayoutMemo.kinsokuDependent`. */
    /** The number of keys `kinsokuLevelMemoKey` returns, one per `KinsokuLevel` constructor; `WidthIndependentLayoutMemo` keeps this many slots per kinsoku-dependent value. */
    public static inline final KINSOKU_LEVEL_MEMO_KEY_COUNT:Int = 4;

    /** The `AccurateSum` of the cluster advances of each shaping result of `stage`, in order. */
    static function baseShapingResultWidths(stage:ParagraphShapingStageResult):Array<Float> {
        final widths = new Array<Float>();
        for (i in 0...stage.shapingResults.length) {
            final res = stage.shapingResults[i];
            final resTerms:Array<Float> = [];
            for (c in 0...res.clusters.length)
                resTerms.push(res.clusters[c].advance);
            widths.push(AccurateSum.of(resTerms));
        }
        return widths;
    }

    public static function kinsokuLevelMemoKey(level:KinsokuLevel):Int {
        return switch (level) {
            case KinsokuLevel.None: 0;
            case KinsokuLevel.Basic: 1;
            case KinsokuLevel.GbStyle: 2;
            case KinsokuLevel.Strict: 3;
        };
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
            grid.enabled ? gridCellsInt : Std.int(measure / fontSize), measure, gridSlack, renderNullableLastLineAlignment(gridBodyAlignment), gridBodyOffset,
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
        // The width of each base shaping result depends only on the annotation, so the annotation's
        // own memo keeps it; only the comparison with the measure runs per layout.
        final widthsSlot = annotation.layoutMemo.baseShapingResultWidths;
        final cachedWidths = widthsSlot.value;
        final shapingResultWidths = cachedWidths != null ? cachedWidths : baseShapingResultWidths(annotation.baseShapingStage);
        if (cachedWidths == null)
            widthsSlot.value = shapingResultWidths;
        var hasOverMeasureToken = false;
        for (i in 0...shapingResultWidths.length) {
            if (shapingResultWidths[i] > measure) {
                hasOverMeasureToken = true;
                break;
            }
        }
        final needsDynamicShaping = (rejectedTechnicalTiersBySpan != null && rejectedTechnicalTiersBySpan.size() > 0)
            || hasProgSpan
            || hasOverMeasureToken;

        // `WidthIndependentLayoutMemo`: values derived from the base shaping stage are computed once
        // per annotation; a prep shaped for this measure gets a memo of its own.
        final layoutMemo:WidthIndependentLayoutMemo = needsDynamicShaping ? new WidthIndependentLayoutMemo() : annotation.layoutMemo;
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

        final cachedBase = layoutMemo.shapedBase.value;
        final base:ShapedParagraphBase = cachedBase != null ? cachedBase
            : ParagraphPrepPartsBuilder.buildShapedParagraphBase(engine.punctuationAtomBuilder, engine.punctuationSpacingCompressor, input, annotation, shapingStage);
        if (cachedBase == null)
            layoutMemo.shapedBase.value = base;
        final kinsokuKey = kinsokuLevelMemoKey(resolvedKinsoku.level);
        final kinsokuSlot = layoutMemo.kinsokuDependent[kinsokuKey];
        final cachedKinsokuPart = kinsokuSlot.value;
        final kinsokuPart:KinsokuDependentPrep = cachedKinsokuPart != null ? cachedKinsokuPart
            : ParagraphPrepPartsBuilder.buildKinsokuDependentPrep(input, annotation, base, resolvedKinsoku, kinsokuRule);
        if (cachedKinsokuPart == null)
            kinsokuSlot.value = kinsokuPart;

        return new ParagraphLayoutPrep(input, rejectedTechnicalTiersBySpan, text, fontSize, annotation.styleAt, annotation.fontSizeAt,
            annotation.bopomofoFontWeightAt, annotation.rubyFontSize, annotation.rubyStackGap, annotation.rubyFontWeight, annotation.pinyinSpans,
            annotation.clreqProfile, annotation.punctuationGlyphSubstitutor, measure, measureEm, gridBodyOffset, lineLengthGridDecision,
            annotation.quotePairs, annotation.roleOverrideInfos, annotation.fontDecisions, shapingStage.hyphenOffsets, shapingStage.hyphenAdvance,
            shapingStage.hyphenGlyphs, shapingStage.substitutionRollbacks, shapingStage.breakOpportunityDecisions,
            shapingStage.emergencyTrackingEligibilityDecisions, shapingStage.progressiveBreakOffsets, base.shapedGlyphsByClusterRange,
            base.openTypeFeaturesByClusterRange, base.shapingDecisions, base.eastAsianSpacingEdges, base.autoSpaceDecisions, base.inlineBoxResult,
            base.naturalClusters, base.inlineObjectByClusterIndex, base.uniformInlineObjectBoundaryAfterClusters,
            base.preferredInlineObjectBoundaryAfterClusters, base.inlineObjectBoundaryUnbreakableRanges, base.clusterRoles, resolvedKinsoku,
            kinsokuRule, kinsokuPart.inlineObjectAttachedMarks, kinsokuPart.inlineObjectSeparatorSpaceTrims,
            kinsokuPart.inlineObjectAttachmentNoStretchBoundaries, kinsokuPart.inlineObjectPunctuationAttachmentDecisions, base.mandatoryBreakClusters,
            base.zeroWidthBreakClusters, base.mandatoryBreakDecisions, base.zeroWidthBreakDecisions, base.punctuationAtoms, base.spacingPlan,
            annotation.rubyFontGeometryBySpan, base.rubyAndBopomofoSpread, kinsokuPart.naturalInlineAttachments,
            kinsokuPart.attachedPunctuationBoundary, kinsokuPart.baseGeometry, kinsokuPart.attachedPunctuationTrailingGlueByCluster,
            kinsokuPart.clusters, annotation.clreqProfile.adjustment, kinsokuPart.atomClassByRange, kinsokuPart.shrinkOpportunities, layoutMemo);
    }
}
