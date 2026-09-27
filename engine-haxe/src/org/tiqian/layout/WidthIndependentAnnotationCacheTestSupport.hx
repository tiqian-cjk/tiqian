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
import org.tiqian.test.trace.TestTrace;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TracedAssertions;

using std.RecordCopy;

class CountingTextShaper implements ITextShaper {
    public var shapeCallCount:Int = 0;

    final delegate:Null<ITextShaper>;

    public function new(?delegate:ITextShaper) {
        this.delegate = delegate;
    }

    public function shape(input:ShapingInput):ShapingResult {
        shapeCallCount += 1;
        final d = delegate == null ? new ExplainableStubTextShaper() : delegate;
        return d.shape(input);
    }
}

class WidthIndependentAnnotationCacheTestSupport {
    public static function layoutWithCache(cache:WidthIndependentAnnotationCache, text:String, maxWidth:Float, ?firstLineIndent:Ic):LayoutResult {
        final indent = firstLineIndent != null ? firstLineIndent : Ic.Zero;
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null, cache);
        return engine.layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, indent), new LayoutConstraints(maxWidth)));
    }

    public static function annotationKey(input:LayoutInput):WidthIndependentAnnotationKey {
        return WidthIndependentAnnotationCacheFns.toWidthIndependentAnnotationKey(input);
    }

    public static function floatText(value:Float):String {
        return TestTraceRender.floatText(value);
    }

    public static function generateSweepWidths(start:Float, step:Float, max:Float):Array<Float> {
        final widths:Array<Float> = [];
        var w = TestHelpers.f32Literal(start);
        final f32Step = TestHelpers.f32Literal(step);
        while (w <= max) {
            widths.push(w);
            w = TestHelpers.f32Literal(w + f32Step);
        }
        return widths;
    }

    public static function assertEqualsNullableAnnotation(expected:Null<WidthIndependentParagraphAnnotation>,
            actual:Null<WidthIndependentParagraphAnnotation>, ?message:String):Void {
        final recorder = TestTrace.currentRecorder();
        if (recorder != null) {
            final e = expected == null ? "-" : "<annotation>";
            final a = actual == null ? "-" : "<annotation>";
            var line = "eq expected=" + e + " actual=" + a;
            if (message != null)
                line += " msg='" + TestTraceRender.escapeOperand(message) + "'";
            recorder.record(line);
        }
        if (expected != actual)
            TracedAssertions.fail(message == null ? "Annotation mismatch" : message);
    }

    public static function assertEqualsTextRange(expected:TextRange, actual:TextRange, ?message:String):Void {
        final e = TestTraceRender.canonicalNumbers(Std.string(expected));
        final a = TestTraceRender.canonicalNumbers(Std.string(actual));
        final recorder = TestTrace.currentRecorder();
        if (recorder != null) {
            var line = "eq expected=" + e + " actual=" + a;
            if (message != null)
                line += " msg='" + TestTraceRender.escapeOperand(message) + "'";
            recorder.record(line);
        }
        if (expected.start != actual.start || expected.end != actual.end)
            TracedAssertions.fail(message == null ? "TextRange mismatch" : message);
    }
}
