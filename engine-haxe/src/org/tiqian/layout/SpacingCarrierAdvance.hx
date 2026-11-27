package org.tiqian.layout;

import std.SortedMap;
import org.tiqian.core.IllegalStateException;
import org.tiqian.core.SpacingCarrierAdvanceDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;

/** Shapes U+00A0 once per distinct font decision and style of the shaped segments; a segment whose faces lack U+00A0 gets no record. */
class SpacingCarrierAdvance {
    public static inline var CARRIER_TEXT:String = "\u00A0";
    static inline var CARRIER_UTF16_LENGTH:Int = 1;

    public static function measure(textShaper:TextShaper, segmentShaping:SortedMap<TextRange, ShapingResult>,
            fontDecisionByRange:SortedMap<TextRange, FontDecision>, styleAt:Int->TextStyle,
            emphasisItalicAt:Int->Bool):Array<SpacingCarrierAdvanceDecisionInfo> {
        final decisionRanges:Array<TextRange> = [];
        final decisionValues:Array<FontDecision> = [];
        for (i in 0...fontDecisionByRange.size()) {
            decisionRanges.push(fontDecisionByRange.keyAt(i));
            decisionValues.push(fontDecisionByRange.valueAt(i));
        }

        final measuredKeys:Array<String> = [];
        final measuredValues:Array<Null<Float>> = [];
        final out:Array<SpacingCarrierAdvanceDecisionInfo> = [];
        var lastKey:Null<String> = null;
        var decisionCursor = 0;
        for (i in 0...segmentShaping.size()) {
            final segment = segmentShaping.keyAt(i);
            // The covering font decision spans the whole role run.
            while (decisionCursor < decisionRanges.length && decisionRanges[decisionCursor].end <= segment.start)
                decisionCursor += 1;
            if (decisionCursor >= decisionRanges.length || decisionRanges[decisionCursor].start > segment.start
                    || segment.end > decisionRanges[decisionCursor].end)
                continue;
            final decision = decisionValues[decisionCursor];
            final style = segmentStyle(decision, styleAt(segment.start), emphasisItalicAt(segment.start));
            final key = measurementKey(decision, style);

            var advance:Null<Float> = null;
            var found = false;
            for (k in 0...measuredKeys.length) {
                if (measuredKeys[k] == key) {
                    advance = measuredValues[k];
                    found = true;
                    break;
                }
            }
            if (!found) {
                advance = shapeCarrier(textShaper, decision, style);
                measuredKeys.push(key);
                measuredValues.push(advance);
            }
            if (advance == null)
                continue;
            final value:Float = advance;

            if (out.length > 0 && lastKey == key && out[out.length - 1].range.end >= segment.start) {
                final last = out[out.length - 1];
                if (segment.end > last.range.end)
                    out[out.length - 1] = new SpacingCarrierAdvanceDecisionInfo(new TextRange(last.range.start, segment.end), last.fontKey,
                        last.advance, last.reason);
                continue;
            }
            if (out.length > 0 && out[out.length - 1].range.end > segment.start)
                continue;
            out.push(new SpacingCarrierAdvanceDecisionInfo(segment, decision.candidate.key, value));
            lastKey = key;
        }
        return out;
    }

    /** Mirrors the segment style ParagraphShapingStage.shapeSegment shapes with. */
    static function segmentStyle(decision:FontDecision, base:TextStyle, emphasisItalic:Bool):TextStyle {
        if (decision.role == FontRole.LatinText && emphasisItalic) {
            final families:Array<String> = [];
            for (i in 0...base.fontFamilies.length)
                families.push(base.fontFamilies[i]);
            return new TextStyle(families, base.fontSize, base.locale, base.fontWeight, true, base.baselineShift, base.inlineAttachment);
        }
        return base;
    }

    static function measurementKey(decision:FontDecision, style:TextStyle):String {
        final families:Array<String> = [];
        for (i in 0...style.fontFamilies.length)
            families.push(style.fontFamilies[i]);
        return decision.candidate.key + "\u001f" + Type.enumConstructor(decision.role) + "\u001f" + families.join("\u001e") + "\u001f"
            + Std.string(style.fontSize) + "\u001f" + style.locale + "\u001f" + Std.string(style.fontWeight) + "\u001f"
            + (style.italic ? "i" : "n");
    }

    static function shapeCarrier(textShaper:TextShaper, decision:FontDecision, style:TextStyle):Null<Float> {
        var shaped:Null<ShapingResult> = null;
        try {
            shaped = textShaper.shape(new ShapingInput(CARRIER_TEXT, new TextRange(0, CARRIER_UTF16_LENGTH), style, decision, CARRIER_TEXT));
        } catch (error:IllegalStateException) {
            return null;
        }
        if (shaped == null || shaped.clusters.length != 1)
            return null;
        final advance = shaped.clusters[0].advance;
        if (!Math.isFinite(advance) || advance < 0)
            return null;
        return advance;
    }
}
