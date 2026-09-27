package org.tiqian.layout;

import org.tiqian.clreq.ClreqProfileResolver;
import org.tiqian.clreq.ClreqProfileResolver.BuiltInClreqProfileResolver;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.TextRange;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError.Message;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontPolicy.FallbackResolver;
import org.tiqian.font.FontMetrics.FontMetricsNormalizer;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import org.tiqian.font.FontMetrics.ScriptAwareFontMetricsNormalizer;
import org.tiqian.font.FontMetrics.StubFontMetricsResolver;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressor;
import org.tiqian.layout.QuotePairAnalyzer;
import org.tiqian.layout.LineBreaker;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.Justifier;
import org.tiqian.layout.DefaultHyphenator;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import std.SortedMap;
import std.SortedSet;
import org.tiqian.layout.WidthIndependentAnnotationCache;
import org.tiqian.layout.WidthIndependentAnnotationCache.LruWidthIndependentAnnotationCache;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentParagraphAnnotation;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.layout.LineBreakPlanningStage;
import org.tiqian.layout.LineAdjustmentStage;

class ParagraphLayoutEngineFns {
    public static final MANDATORY_BREAK_FONT_KEY:String = "mandatory-break";
}

interface ParagraphLayoutEngine {
    function layout(input:LayoutInput):LayoutResult;
}

class ExplainableStubParagraphLayoutEngine implements ParagraphLayoutEngine {
    public final fontRoleClassifier:FontRoleClassifier;
    public final fallbackResolver:FallbackResolver;
    public final clreqProfileResolver:ClreqProfileResolver;
    public final fontMetricsResolver:FontMetricsResolver;
    public final fontMetricsNormalizer:FontMetricsNormalizer;
    public final punctuationAtomBuilder:PunctuationAtomBuilder;
    public final punctuationSpacingCompressor:PunctuationSpacingCompressor;
    public final quotePairAnalyzer:QuotePairAnalyzer;
    public final lineBreaker:LineBreaker;
    public final justifier:Justifier;
    public final textShaper:ITextShaper;
    public final hyphenator:Hyphenator;
    public final annotationCache:WidthIndependentAnnotationCache;

    public function new(?fontRoleClassifier:FontRoleClassifier, ?fallbackResolver:FallbackResolver, ?clreqProfileResolver:ClreqProfileResolver,
            ?fontMetricsResolver:FontMetricsResolver, ?fontMetricsNormalizer:FontMetricsNormalizer, ?punctuationAtomBuilder:PunctuationAtomBuilder,
            ?punctuationSpacingCompressor:PunctuationSpacingCompressor, ?quotePairAnalyzer:QuotePairAnalyzer, ?lineBreaker:LineBreaker, ?justifier:Justifier,
            ?textShaper:ITextShaper, ?hyphenator:Hyphenator, ?annotationCache:WidthIndependentAnnotationCache) {
        this.fontRoleClassifier = fontRoleClassifier == null ? new CjkFontRoleClassifier() : fontRoleClassifier;
        this.fallbackResolver = fallbackResolver == null ? new ParagraphLayoutFallbackResolver() : fallbackResolver;
        this.clreqProfileResolver = clreqProfileResolver == null ? new BuiltInClreqProfileResolver() : clreqProfileResolver;
        this.fontMetricsResolver = fontMetricsResolver == null ? new StubFontMetricsResolver() : fontMetricsResolver;
        this.fontMetricsNormalizer = fontMetricsNormalizer == null ? new ScriptAwareFontMetricsNormalizer() : fontMetricsNormalizer;
        this.punctuationAtomBuilder = punctuationAtomBuilder == null ? new PunctuationAtomBuilder() : punctuationAtomBuilder;
        this.punctuationSpacingCompressor = punctuationSpacingCompressor == null ? new PunctuationSpacingCompressor() : punctuationSpacingCompressor;
        this.quotePairAnalyzer = quotePairAnalyzer == null ? new QuotePairAnalyzer() : quotePairAnalyzer;
        this.lineBreaker = lineBreaker == null ? new GreedyLineBreaker() : lineBreaker;
        this.justifier = justifier == null ? new Justifier() : justifier;
        this.textShaper = textShaper == null ? new ExplainableStubTextShaper() : textShaper;
        this.hyphenator = hyphenator == null ? DefaultHyphenator.defaultHyphenator() : hyphenator;
        this.annotationCache = annotationCache == null ? new LruWidthIndependentAnnotationCache() : annotationCache;
    }

    public function layout(input:LayoutInput):LayoutResult {
        return layoutWithRejectedTechnicalTiers(input, SortedMap.builder().build());
    }

    public function layoutWithRejectedTechnicalTiers(input:LayoutInput, rejectedTechnicalTiersBySpan:SortedMap<TextRange, SortedSet<Int>>):LayoutResult {
        validateLayoutInput(input);
        final cacheKey = WidthIndependentAnnotationCacheFns.toWidthIndependentAnnotationKey(input, rejectedTechnicalTiersBySpan);
        final cached = annotationCache.get(cacheKey);
        var annotation:WidthIndependentParagraphAnnotation;
        if (Std.isOfType(cached, WidthIndependentParagraphAnnotation)) {
            annotation = cast(cached, WidthIndependentParagraphAnnotation);
        } else {
            annotation = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(this, input, rejectedTechnicalTiersBySpan);
            annotationCache.put(cacheKey, annotation);
        }
        final prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(this, input, annotation, rejectedTechnicalTiersBySpan);
        return LineAdjustmentStage.finishParagraphLayout(this, prep, LineBreakPlanningStage.planParagraphLines(this, prep));
    }

    private function validateLayoutInput(input:LayoutInput):Void {
        final text = input.content.text;
        if (!Math.isFinite(input.paragraphStyle.emphasisDotGapEm) || input.paragraphStyle.emphasisDotGapEm < 0) {
            throw new TiqianIllegalArgumentException(Message("ParagraphStyle.emphasisDotGapEm must be finite and non-negative"));
        }
        if (!Math.isFinite(input.paragraphStyle.inlineObjectMinimumClearanceEm)
            || input.paragraphStyle.inlineObjectMinimumClearanceEm < 0) {
            throw new TiqianIllegalArgumentException(Message("ParagraphStyle.inlineObjectMinimumClearanceEm must be finite and non-negative"));
        }
        var surrogateScan = 0;
        while (surrogateScan < text.length) {
            final code = text.charCodeAt(surrogateScan);
            if (code >= 0xD800 && code <= 0xDBFF) {
                if (!(surrogateScan + 1 < text.length
                    && text.charCodeAt(surrogateScan + 1) >= 0xDC00
                    && text.charCodeAt(surrogateScan + 1) <= 0xDFFF)) {
                    throw new TiqianIllegalArgumentException(Message("SourceText has an unpaired high surrogate at char " + surrogateScan));
                }
                surrogateScan += 2;
            } else {
                if (code >= 0xDC00 && code <= 0xDFFF) {
                    throw new TiqianIllegalArgumentException(Message("SourceText has an unpaired low surrogate at char " + surrogateScan));
                }
                surrogateScan += 1;
            }
        }
        for (i in 0...input.inlineBoxes.length) {
            final inlineBox = input.inlineBoxes[i];
            if (!(inlineBox.range.start >= 0 && inlineBox.range.start < inlineBox.range.end && inlineBox.range.end <= text.length)) {
                throw new TiqianIllegalArgumentException(Message("InlineBoxSpan " + Std.string(inlineBox.range) + " must be a non-empty source range"));
            }
            if (!(Math.isFinite(inlineBox.inlineStart) && Math.isFinite(inlineBox.inlineEnd))) {
                throw new TiqianIllegalArgumentException(Message("InlineBoxSpan " + Std.string(inlineBox.range) + " must have finite inline edges"));
            }
        }
        for (i in 0...input.content.lineBreakSpans.length) {
            final span = input.content.lineBreakSpans[i];
            if (!(span.range.start >= 0 && span.range.start < span.range.end && span.range.end <= text.length)) {
                throw new TiqianIllegalArgumentException(Message("LineBreakSpan " + Std.string(span.range) + " must be a non-empty source range"));
            }
        }
        for (i in 0...input.content.autoSpaceSuppressedRanges.length) {
            final range = input.content.autoSpaceSuppressedRanges[i];
            if (!(range.start >= 0 && range.start < range.end && range.end <= text.length)) {
                throw new TiqianIllegalArgumentException(Message("Auto-space suppressed range " + Std.string(range) + " must be a non-empty source range"));
            }
        }
        final seenRanges = new Array<TextRange>();
        for (i in 0...input.inlineObjects.length) {
            final inlineObject = input.inlineObjects[i];
            for (j in 0...seenRanges.length) {
                final seen = seenRanges[j];
                if (seen.start == inlineObject.range.start && seen.end == inlineObject.range.end) {
                    throw new TiqianIllegalArgumentException(Message("InlineObjectSpan ranges must be unique"));
                }
            }
            seenRanges.push(inlineObject.range);
        }
        final sortedObjects = new Array<InlineObjectSpan>();
        for (i in 0...input.inlineObjects.length) {
            sortedObjects.push(input.inlineObjects[i]);
        }
        var i = 1;
        while (i < sortedObjects.length) {
            final item = sortedObjects[i];
            var j = i - 1;
            while (j >= 0 && sortedObjects[j].range.start > item.range.start) {
                sortedObjects[j + 1] = sortedObjects[j];
                j--;
            }
            sortedObjects[j + 1] = item;
            i++;
        }
        for (idx in 0...(sortedObjects.length - 1)) {
            final prevObj = sortedObjects[idx];
            final nextObj = sortedObjects[idx + 1];
            if (prevObj.range.end > nextObj.range.start) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan ranges must not overlap: " + Std.string(prevObj.range) + " and "
                    + Std.string(nextObj.range)));
            }
        }
        for (k in 0...input.inlineObjects.length) {
            final inlineObject = input.inlineObjects[k];
            if (!(inlineObject.range.start >= 0
                && inlineObject.range.start < inlineObject.range.end
                && inlineObject.range.end <= text.length)) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range) +
                    " must cover a non-empty source range"));
            }
            if (!(Math.isFinite(inlineObject.advance) && inlineObject.advance > 0 && Math.isFinite(inlineObject.ascent) && inlineObject.ascent >= 0
                && Math.isFinite(inlineObject.descent) && inlineObject.descent >= 0)) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range) + " must have finite positive geometry"));
            }
            if (inlineObject.leadingBoundary.shrinkCapacity != 0) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range) + " cannot shrink its leading boundary"));
            }
            if (inlineObject.leadingBoundary.lineEndDiscardableAdvance != 0) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range)
                    + " cannot discard advance at its leading boundary"));
            }
            if (inlineObject.trailingBoundary.shrinkCapacity > inlineObject.advance) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range)
                    + " trailing shrink capacity must not exceed its advance"));
            }
            if (inlineObject.trailingBoundary.lineEndDiscardableAdvance > inlineObject.advance) {
                throw new TiqianIllegalArgumentException(Message("InlineObjectSpan " + Std.string(inlineObject.range)
                    + " trailing line-end discard must not exceed its advance"));
            }
        }
    }
}

class ParagraphLayoutFallbackResolver implements FallbackResolver {
    public final cjkFontKey:String;
    public final latinFontKey:String;
    public final symbolFontKey:String;

    public function new(?cjkFontKey:Null<String>, ?latinFontKey:Null<String>, ?symbolFontKey:Null<String>) {
        this.cjkFontKey = cjkFontKey == null ? "cjk-primary" : cjkFontKey;
        this.latinFontKey = latinFontKey == null ? "latin-primary" : latinFontKey;
        this.symbolFontKey = symbolFontKey == null ? "symbol-fallback" : symbolFontKey;
    }

    public function resolve(text:String, range:org.tiqian.core.TextRange,
            request:org.tiqian.font.FontPolicy.FontRequest):org.tiqian.font.FontPolicy.FontDecision {
        var c:org.tiqian.font.FontPolicy.FontCandidate;
        switch (request.role) {
            case CjkText | CjkPunctuation:
                c = new org.tiqian.font.FontPolicy.FontCandidate(cjkFontKey,
                    request.preferredFamilies.length == 0 ? cjkFontKey : request.preferredFamilies[0], request.role);
            case LatinText:
                c = new org.tiqian.font.FontPolicy.FontCandidate(latinFontKey, latinFontKey, request.role);
            case Symbol | Emoji | Unknown:
                c = new org.tiqian.font.FontPolicy.FontCandidate(symbolFontKey, symbolFontKey, request.role);
        }
        return new org.tiqian.font.FontPolicy.FontDecision(range, c, request.role, "PreferCjkForAmbiguousPunctuationResolver:" + request.role);
    }
}
