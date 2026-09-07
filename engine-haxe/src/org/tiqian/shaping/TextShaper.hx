package org.tiqian.shaping;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.GlyphRun;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.IllegalStateException;
import org.tiqian.font.FontPolicy.FontDecision;

@:dataClass
class ShapingInput {
    public final text:String;
    public final range:TextRange;
    public final style:TextStyle;
    public final fontDecision:FontDecision;
    public final displayText:String;
    public final openTypeFeatures:Array<String>;

    public function new(text:String, range:TextRange, style:TextStyle, fontDecision:FontDecision, ?displayText:Null<String>, ?openTypeFeatures:Array<String>) {
        this.text = text;
        this.range = range;
        this.style = style;
        this.fontDecision = fontDecision;
        this.displayText = displayText == null ? text.substring(range.start, range.end) : displayText;
        this.openTypeFeatures = openTypeFeatures == null ? [] : openTypeFeatures;
    }
}

@:dataClass
class ShapingResult {
    public final clusters:Array<Cluster>;
    public final glyphRuns:Array<GlyphRun>;
    public final decisions:Array<ShapingDecisionInfo>;

    public function new(clusters:Array<Cluster>, glyphRuns:Array<GlyphRun>, ?decisions:Array<ShapingDecisionInfo>) {
        this.clusters = clusters;
        this.glyphRuns = glyphRuns;
        this.decisions = decisions == null ? [] : decisions;
    }
}

class TextShaper {
    public static final UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE:String = "UnverifiedDisplaySubstitutionCoverage";
    public static final PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE:String = "PlatformMultiFaceStringDraw";
}

interface ITextShaper {
    function shape(input:ShapingInput):ShapingResult;
}

enum ShapingSource {
    Stub;
    JvmAwt;
    AndroidPaint;
    Skia;
    HarfBuzz;
    CoreText;
}

class ExplainableStubTextShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        var sourceText = input.text.substring(input.range.start, input.range.end);
        var glyphCount = codePointCount(input.displayText);
        if (glyphCount < 1)
            glyphCount = 1;
        var advance = input.style.fontSize * nominalAdvanceEm(sourceText, input.displayText);
        var cluster = new Cluster(input.range, sourceText, input.fontDecision.candidate.key, advance, input.displayText);
        var glyphAdvance = advance / glyphCount;
        var glyphs:Array<Glyph> = [];
        var glyphId = 0;
        while (glyphId < glyphCount) {
            glyphs.push(new Glyph(glyphId, input.range, glyphAdvance, glyphAdvance * glyphId));
            glyphId++;
        }
        var run = new GlyphRun(input.range, input.fontDecision.candidate.key, glyphs, advance, input.openTypeFeatures);
        var decision = new ShapingDecisionInfo(input.range, sourceText, input.displayText, input.fontDecision.candidate.key, glyphCount, advance,
            Type.enumConstructor(ShapingSource.Stub), "ExplainableStubTextShaper:nominal-em-advance", glyphCount);
        return new ShapingResult([cluster], [run], [decision]);
    }

    private static function nominalAdvanceEm(source:String, displayText:String):Float {
        if (source == "\u2E3A" || displayText == "\u2E3A")
            return 2.0;
        if (source.length > 0) {
            var allSpaces = true;
            var i = 0;
            while (i < source.length) {
                if (source.charCodeAt(i) != 0x20)
                    allSpaces = false;
                i++;
            }
            if (allSpaces)
                return 0.5 * source.length;
        }
        var a = codePointCount(source);
        var b = codePointCount(displayText);
        return (a > b ? a : b);
    }

    private static function codePointCount(value:String):Int {
        var count = 0;
        var index = 0;
        while (index < value.length) {
            var code = value.charCodeAt(index);
            if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
                var next = value.charCodeAt(index + 1);
                if (next >= 0xDC00 && next <= 0xDFFF)
                    index += 2;
                else
                    index++;
            } else
                index++;
            count++;
        }
        return count;
    }
}

class UnimplementedTextShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        throw new IllegalStateException("Text shaping is platform-specific and has not been wired for this target yet.");
    }
}
