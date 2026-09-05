package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ZeroWidthBreakControlLayoutTest {
    @:test public static function zeroWidthSpaceIsUnshapedAndProvidesASoftBreakAfterIt():Void {
        final t = new TestTraceRecorder("ZeroWidthBreakControlLayoutTest");
        t.section("zeroWidthSpaceIsUnshapedAndProvidesASoftBreakAfterIt");
        final breakers:Array<LineBreaker> = [new GreedyLineBreaker(), new LookaheadLineBreaker()];
        for (i in 0...breakers.length) {
            final breaker = breakers[i];
            final result = ZeroWidthBreakControlLayoutTestSupport.layout("foo\u200Bbar", 48.0, breaker);
            var control:Cluster = null;
            for (i in 0...result.clusters.length) {
                final c = result.clusters[i];
                if (c.text == "\u200B")
                    control = c;
            }
            TracedAssertions.assertEqualsString("", control.displayText, breaker.strategyName);
            TracedAssertions.assertEqualsFloatTolerance(0.0, control.advance, 0.001, breaker.strategyName);
            var shaped = false;
            for (ri in 0...result.glyphRuns.length) {
                final run = result.glyphRuns[ri];
                for (gi in 0...run.glyphs.length)
                    if (run.glyphs[gi].clusterRange == control.range)
                        shaped = true;
            }
            TracedAssertions.assertTrue(!shaped, breaker.strategyName);
            TracedAssertions.assertEqualsRendered("TextRange(start=0, end=4)", Std.string(result.lines[0].range), breaker.strategyName);
            TracedAssertions.assertEqualsRendered("TextRange(start=4, end=7)", Std.string(result.lines[1].range), breaker.strategyName);
            var reason = "";
            for (i in 0...result.debug.shapingDecisions.length) {
                final d = result.debug.shapingDecisions[i];
                if (d.range == control.range)
                    reason = d.reason;
            }
            TracedAssertions.assertEqualsString("ZeroWidthSpaceSoftBreakNoShape", reason, breaker.strategyName);
            TracedAssertions.assertEqualsRendered(Std.string(control.range), Std.string(result.debug.zeroWidthBreakDecisions[0].range), breaker.strategyName);
        }
    }

    @:test public static function leadingZeroWidthSpaceCannotCreateAnEmptyAutoWrappedLine():Void {
        final t = new TestTraceRecorder("ZeroWidthBreakControlLayoutTest");
        t.section("leadingZeroWidthSpaceCannotCreateAnEmptyAutoWrappedLine");
        final breakers:Array<LineBreaker> = [new GreedyLineBreaker(), new LookaheadLineBreaker()];
        for (i in 0...breakers.length) {
            final breaker = breakers[i];
            final result = ZeroWidthBreakControlLayoutTestSupport.layout("\u200B中", 8.0, breaker);
            TracedAssertions.assertEqualsInt(1, result.lines.length, breaker.strategyName);
            TracedAssertions.assertEqualsRendered("TextRange(start=0, end=2)", Std.string(result.lines[0].range), breaker.strategyName);
        }
    }
}
