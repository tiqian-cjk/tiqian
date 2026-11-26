package org.tiqian.shared.layout;

import org.tiqian.core.DecorationKind;
import org.tiqian.core.DecorationSpan;
import org.tiqian.core.InlineBoxOuterSpacing;
import org.tiqian.core.InlineBoxSpan;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.LineBreakPolicy;
import org.tiqian.core.LineBreakSpan;
import org.tiqian.core.LineLengthGrid;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextSpan;
import org.tiqian.core.TextStyle;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.PlanLowering;
import org.tiqian.layout.PreparedParagraph.PlanWithDiagnostics;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.layout.WidthIndependentAnnotationCache.LruWidthIndependentAnnotationCache;
import org.tiqian.protocol.ParagraphRequest;
import org.tiqian.protocol.Plan;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;

typedef PreparedParagraphCallbacks = {
    shape:ShapingInput->ShapingResult,
    resolve:FontMetricsRequest->RawFontMetrics
}

class CallbackTextShaper implements TextShaper {
    final shapeFn:ShapingInput->ShapingResult;

    public function new(shapeFn:ShapingInput->ShapingResult) {
        this.shapeFn = shapeFn;
    }

    public function shape(input:ShapingInput):ShapingResult {
        return shapeFn(input);
    }
}

class CallbackFontMetricsResolver implements FontMetricsResolver {
    final resolveFn:FontMetricsRequest->RawFontMetrics;

    public function new(resolveFn:FontMetricsRequest->RawFontMetrics) {
        this.resolveFn = resolveFn;
    }

    public function resolve(request:FontMetricsRequest):RawFontMetrics {
        return resolveFn(request);
    }
}

/**
    The prepared-paragraph entries shared by the web client and its workers:
    request normalization, LayoutInput assembly, the layout call and the two
    plan serializations. Host shaping and font metrics arrive as callbacks.
**/
class PreparedParagraphLayout {
    public static function toPlanWithDiagnostics(request:ParagraphRequest, zeroAdvanceEpsilonPx:Float,
            callbacks:PreparedParagraphCallbacks, cache:LruWidthIndependentAnnotationCache,
            renderEvidenceOverride:Null<Bool>):PlanWithDiagnostics {
        final model = PreparedParagraphRequest.normalize(request);
        PreparedParagraphRequest.validate(model);
        final result = layout(model, callbacks, cache);
        final renderEvidence = renderEvidenceOverride == null ? shouldRenderEvidence(model, result) : renderEvidenceOverride;
        return PreparedParagraphFns.toPlanWithDiagnostics(result, renderEvidence, zeroAdvanceEpsilonPx);
    }

    public static function toPlan(request:ParagraphRequest, callbacks:PreparedParagraphCallbacks,
            cache:LruWidthIndependentAnnotationCache, renderEvidenceOverride:Null<Bool>):Plan {
        final model = PreparedParagraphRequest.normalize(request);
        PreparedParagraphRequest.validate(model);
        final result = layout(model, callbacks, cache);
        final renderEvidence = renderEvidenceOverride == null ? shouldRenderEvidence(model, result) : renderEvidenceOverride;
        return PlanLowering.toPlan(result, renderEvidence);
    }

    static function layout(model:ParagraphRequest, callbacks:PreparedParagraphCallbacks,
            cache:LruWidthIndependentAnnotationCache):LayoutResult {
        final textSpans = [];
        for (span in model.textSpans) {
            textSpans.push(new TextSpan(new TextRange(span.start, span.end), new TextStyle(nonBlank(span.families),
                span.fontSizePx, model.locale, span.fontWeight, span.italic, span.baselineShift)));
        }
        final lineBreakSpans = [];
        for (span in model.lineBreakSpans) {
            lineBreakSpans.push(new LineBreakSpan(new TextRange(span.start, span.end), lineBreakPolicy(span.policy)));
        }
        final content = new TiqianTextContent(model.text, textSpans, model.sourceBoundaries, lineBreakSpans);
        final decorations = [];
        for (decoration in model.decorations) {
            decorations.push(new DecorationSpan(new TextRange(decoration.start, decoration.end), decorationKind(decoration.kind)));
        }
        final inlineBoxes = [];
        for (box in model.inlineBoxes) {
            inlineBoxes.push(new InlineBoxSpan(new TextRange(box.start, box.end), box.inlineStart, box.inlineEnd,
                inlineBoxOuterSpacing(box.outerSpacing)));
        }
        final inlineObjects = [];
        for (object in model.inlineObjects) {
            inlineObjects.push(new InlineObjectSpan(new TextRange(object.start, object.end), object.advance, object.ascent,
                object.descent));
        }
        final gapEm = model.emphasisDotGapEm == null ? 0.1 : model.emphasisDotGapEm;
        final input = new LayoutInput(
            content,
            new TextStyle(nonBlank(model.fontFamilies), model.fontSizePx, model.locale, model.fontWeight, model.italic),
            new ParagraphStyle(null, null, model.lineHeightPx, model.firstLineIndentIc, null, null,
                new LineLengthGrid(model.lineLengthGridEnabled), null, null, gapEm),
            new LayoutConstraints(model.maxWidthPx),
            null,
            decorations,
            null,
            inlineBoxes,
            inlineObjects
        );
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null,
            new CallbackFontMetricsResolver(callbacks.resolve), null, null, null, null, new LookaheadLineBreaker(), null,
            new CallbackTextShaper(callbacks.shape), null, cache);
        return engine.layout(input);
    }

    static function shouldRenderEvidence(model:ParagraphRequest, result:LayoutResult):Bool {
        return model.textSpans.length > 0 || model.inlineBoxes.length > 0 || model.decorations.length > 0
            || result.input.inlineObjects.length > 0;
    }

    static function nonBlank(families:Array<String>):Array<String> {
        final out:Array<String> = [];
        for (family in families) {
            if (StringTools.trim(family).length > 0) out.push(family);
        }
        return out;
    }

    static function lineBreakPolicy(name:String):LineBreakPolicy {
        if (name == "ProgressiveTechnical") return ProgressiveTechnical;
        throw invalidEnum("org.tiqian.core.LineBreakPolicy.", name);
    }

    static function decorationKind(name:String):DecorationKind {
        if (name == "Emphasis") return Emphasis;
        if (name == "Mourning") return Mourning;
        if (name == "ProperNoun") return ProperNoun;
        if (name == "BookTitle") return BookTitle;
        throw invalidEnum("org.tiqian.core.DecorationKind.", name);
    }

    static function inlineBoxOuterSpacing(name:String):InlineBoxOuterSpacing {
        if (name == "Narrow") return Narrow;
        if (name == "Source") return Source;
        throw invalidEnum("org.tiqian.core.InlineBoxOuterSpacing.", name);
    }

    static function invalidEnum(qualified:String, name:String):TiqianIllegalArgumentException {
        return new TiqianIllegalArgumentException(TextRangeError.Message("No enum constant " + qualified + name));
    }
}
