package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import std.ReadOnlyArray;

class LayoutDebugRecordingTestSupport {
    /** A three-line paragraph with CJK punctuation, quotes and a Latin word. */
    public static function layout(recordsDebugInfo:Bool):LayoutResult {
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, null, null,
            recordsDebugInfo);
        return engine.layout(new LayoutInput(new TiqianTextContent("中文，“提椠”排版English。再来一句话。"), null, null, new LayoutConstraints(120.0)));
    }

    /** `result` with the debug record and every line's `LineBox.debug` replaced by their defaults. */
    public static function withoutDebug(result:LayoutResult):LayoutResult {
        final lines = new Array<LineBox>();
        for (i in 0...result.lines.length) {
            final l = result.lines[i];
            final hyphenGlyphs = new Array<Glyph>();
            for (g in 0...l.hyphenGlyphs.length)
                hyphenGlyphs.push(l.hyphenGlyphs[g]);
            lines.push(new LineBox(l.range, l.clusterRange, l.baseline, l.top, l.bottom, l.naturalWidth, l.adjustedWidth, l.visualWidth,
                l.hangingPunctuationAdvance, l.indent, l.endReason, l.hyphenAdvance, hyphenGlyphs, null));
        }
        return new LayoutResult(result.input, result.size, result.clusters, result.glyphRuns, lines, null, result.presentation);
    }

    public static function lineSpacingText(value:Null<LineSpacingDecisionInfo>):String {
        return value == null ? "null" : value.toString();
    }

    public static function joinFontDecisions(values:ReadOnlyArray<FontDecisionInfo>):String {
        final out = new StringBuf();
        for (i in 0...values.length)
            out.add(values[i].toString() + "\n");
        return out.toString();
    }

    public static function joinMetricDecisions(values:ReadOnlyArray<MetricDecisionInfo>):String {
        final out = new StringBuf();
        for (i in 0...values.length)
            out.add(values[i].toString() + "\n");
        return out.toString();
    }

    public static function joinPunctuationDecisions(values:ReadOnlyArray<PunctuationDecisionInfo>):String {
        final out = new StringBuf();
        for (i in 0...values.length)
            out.add(values[i].toString() + "\n");
        return out.toString();
    }

    public static function joinGeometryDecisions(values:ReadOnlyArray<ClusterGeometryDecisionInfo>):String {
        final out = new StringBuf();
        for (i in 0...values.length)
            out.add(values[i].toString() + "\n");
        return out.toString();
    }

    public static function joinShapingDecisions(values:ReadOnlyArray<ShapingDecisionInfo>):String {
        final out = new StringBuf();
        for (i in 0...values.length)
            out.add(values[i].toString() + "\n");
        return out.toString();
    }
}
