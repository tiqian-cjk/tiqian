package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationKey;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentParagraphAnnotation;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.font.FontPolicy.FontDecision;

using std.RecordCopy;

import std.SortedMap;
import std.SortedSet;

class WidthIndependentAnnotationCacheCoverageTestSupport {
    public static function emptyTiers():SortedMap<TextRange, SortedSet<Int>>
        return SortedMap.builder().build();

    public static function engine(?clreqProfileResolver:ClreqProfileResolver, ?textShaper:ITextShaper):ExplainableStubParagraphLayoutEngine
        return new ExplainableStubParagraphLayoutEngine(null, null, clreqProfileResolver, null, null, null, null, null, null, null, textShaper);

    public static function key(input:LayoutInput):WidthIndependentAnnotationKey
        return WidthIndependentAnnotationCacheFns.toWidthIndependentAnnotationKey(input);

    public static function tierSet(tiers:Array<ProgressiveBreakTier>):SortedSet<Int> {
        final b = SortedSet.builder();
        for (i in 0...tiers.length) {
            final tier:Int = tiers[i];
            b.put(tier);
        }
        return b.build();
    }

    public static function tierMap(range:TextRange, tiers:Array<ProgressiveBreakTier>):SortedMap<TextRange, SortedSet<Int>> {
        final b = SortedMap.builder();
        b.put(range, tierSet(tiers));
        return b.build();
    }

    /** Port of `List<Cluster>.containingItems`: for each cluster, the first item
     *  whose range contains the cluster, else null. The item range getter is the
     *  identity for TextRange items. */
    public static function containingItems(clusters:Array<Cluster>, items:Array<TextRange>):Array<Null<TextRange>> {
        final out:Array<Null<TextRange>> = [];
        var itemIndex = 0;
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].end <= cluster.range.start) {
                itemIndex += 1;
            }
            final item = itemIndex < items.length ? items[itemIndex] : null;
            final candidate = item != null && cluster.range.start >= item.start && cluster.range.end <= item.end ? item : null;
            out.push(candidate);
        }
        return out;
    }

    /** Port of `List<Cluster>.firstContainedItem`: the first item whose range
     *  is contained in the cluster, via monotonic inverse interval join. */
    public static function firstContainedItem(clusters:Array<Cluster>, items:Array<TextRange>):Array<Null<TextRange>> {
        final out:Array<Null<TextRange>> = [];
        var itemIndex = 0;
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].end <= cluster.range.start) {
                itemIndex += 1;
            }
            final item = itemIndex < items.length ? items[itemIndex] : null;
            final candidate = item != null && item.start >= cluster.range.start && item.end <= cluster.range.end ? item : null;
            out.push(candidate);
        }
        return out;
    }

    private static function copyAnnotation(a:WidthIndependentParagraphAnnotation, ?clreqProfile:ClreqProfile, ?fontDecisions:Array<FontDecision>,
            ?segmentShapingCache:SortedMap<TextRange, ShapingResult>):WidthIndependentParagraphAnnotation
        return new WidthIndependentParagraphAnnotation(a.text, a.fontSize, a.styleAt, a.fontSizeAt, a.bopomofoFontWeightAt, a.rubyFontSize, a.rubyStackGap,
            a.rubyFontWeight, a.pinyinSpans, clreqProfile == null ? a.clreqProfile : clreqProfile, a.punctuationGlyphSubstitutor, a.quotePairs,
            a.roleOverrideInfos, fontDecisions == null ? a.fontDecisions : fontDecisions, a.clusterRanges, a.fontDecisionByRange, a.inlineObjectByRange,
            segmentShapingCache == null ? a.segmentShapingCache : segmentShapingCache, a.substitutionRollbacks, a.rubyFontGeometryBySpan, a.baseShapingStage);

    /** Reconstruction of WidthIndependentParagraphAnnotation with a customized
     *  clreqProfile adjustment, matching the Kotlin data-class copy. */
    public static function withAdjustedProfile(annotation:WidthIndependentParagraphAnnotation, allowInlineStopCompression:Bool,
            allowSinoWesternGapAdjustment:Bool):WidthIndependentParagraphAnnotation {
        final source = annotation.clreqProfile;
        final customAdjustment = new AdjustmentStylePolicy(source.adjustment.lineEndPunctuation, allowInlineStopCompression, allowSinoWesternGapAdjustment,
            source.adjustment.lineAdjustment);
        final customProfile = new ClreqProfile(source.id, source.strictness, source.region, source.punctuationGlyphPolicy,
            source.coalesceRepeatablePunctuation, source.autoSpace, source.gluePlacement, customAdjustment, source.kinsokuMode, source.punctuationWidth);
        return copyAnnotation(annotation, customProfile);
    }

    /** Reconstruction keeping only the first font decision so the remaining
     *  clusters fall back to FontRole.Unknown. */
    public static function withFirstFontDecisionOnly(annotation:WidthIndependentParagraphAnnotation):WidthIndependentParagraphAnnotation {
        final firstOnly:Array<FontDecision> = [];
        for (i in 0...annotation.fontDecisions.length) {
            if (i == 0)
                firstOnly.push(annotation.fontDecisions[i]);
        }
        return copyAnnotation(annotation, null, firstOnly);
    }

    /** Reconstruction with an empty segmentShapingCache so dynamic shaping calls
     *  shapeSegment and invokes the emphasisItalicAt lambda. */
    public static function withEmptyShapingCache(annotation:WidthIndependentParagraphAnnotation):WidthIndependentParagraphAnnotation
        return copyAnnotation(annotation, null, null, SortedMap.builder().build());

    public static function nonGbResolver():ClreqProfileResolver
        return new TiqianClreqFixedResolver(ClreqProfile.TaiwanHorizontal);

    /** RubySpan positional constructor keeps fontFamilies between text and kind
     *  in this port; expose the Kotlin-style (range, text, kind, locale) shape. */
    public static function ruby(range:TextRange, text:String, kind:RubyKind, ?locale:Null<String>):RubySpan
        return new RubySpan(range, text, null, kind, locale);

    /** InlineObjectBoundaryAdjustment keeps optional leading positional args
     *  (participates, preferredStretch) before shrinkCapacity; here we forward
     *  the shrink-only shape used by the coverage fixture. */
    public static function boundaryShrink(shrinkCapacity:Float):InlineObjectBoundaryAdjustment
        return new InlineObjectBoundaryAdjustment(null, null, shrinkCapacity, 0.0, null);

    /** Minimal paragraph annotation whose text field matches [label]; the real
     *  LRU cache stores WidthIndependentParagraphAnnotation values, and the
     *  coverage trace observes them by their text. */
    public static function annotationForText(label:String):WidthIndependentParagraphAnnotation {
        final input = new LayoutInput(new TiqianTextContent(label), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(300));
        return WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(engine(), input, emptyTiers());
    }

    public static function textSpanList(text:String, fontSize:Float):Array<TextSpan> {
        final spans:Array<TextSpan> = [];
        for (i in 0...text.length)
            spans.push(new TextSpan(new TextRange(i, i + 1), new TextStyle(null, fontSize)));
        return spans;
    }

    /** Code-unit index of [needle] in [text]; avoids the subset's non-ASCII
     *  index-access rule by reading through std.UString.at. */
    public static function indexOf(text:String, needle:String):Int {
        final nl = needle.length;
        final limit = text.length - nl + 1;
        var i = 0;
        while (i < limit) {
            var match = true;
            var j = 0;
            while (j < nl) {
                if (std.UString.at(text, i + j) != std.UString.at(needle, j)) {
                    match = false;
                    break;
                }
                j += 1;
            }
            if (match)
                return i;
            i += 1;
        }
        return -1;
    }
}

class TiqianClreqFixedResolver implements ClreqProfileResolver {
    final profile:ClreqProfile;

    public function new(p:ClreqProfile)
        profile = p;

    public function resolve(profileId:LayoutProfileId):ClreqProfile
        return profile;
}

/** Shaper emitting two glyph runs with distinct OpenType features, which the
 *  engine rejects as conflicting. */
class ConflictingOpenTypeFeaturesShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        final cluster = new Cluster(input.range, input.text.substring(input.range.start, input.range.end), "test", 16.0, input.displayText);
        final glyph1 = new Glyph(1, input.range, 8.0, 0.0);
        final glyph2 = new Glyph(2, input.range, 8.0, 8.0);
        final run1 = new GlyphRun(input.range, "test", [glyph1], 8.0, ["feat1"]);
        final run2 = new GlyphRun(input.range, "test", [glyph2], 8.0, ["feat2"]);
        return new ShapingResult([cluster], [run1, run2]);
    }
}

/** Shaper that narrows every glyph's ink bounds; used to force a centered
 *  punctuation boundary to degenerate to zero paired capacity. */
class NarrowInkShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new()
        delegate = new ExplainableStubTextShaper();

    public function shape(input:ShapingInput):ShapingResult {
        final r = delegate.shape(input);
        final runs:Array<GlyphRun> = [];
        for (ri in 0...r.glyphRuns.length) {
            final run = r.glyphRuns[ri];
            final glyphs:Array<Glyph> = [];
            for (gi in 0...run.glyphs.length) {
                final g = run.glyphs[gi];
                glyphs.push(new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey, new Rect(4.0, 2.0, 12.0, 10.0), g.haltAdvance,
                    g.haltPlacementX));
            }
            runs.push(new GlyphRun(run.range, run.fontKey, glyphs, run.advance));
        }
        return new ShapingResult(r.clusters, runs, r.decisions);
    }
}
