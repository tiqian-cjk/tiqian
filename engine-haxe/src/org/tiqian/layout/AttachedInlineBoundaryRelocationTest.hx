package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class AttachedInlineBoundaryRelocationTest {
    @:test public static function attachedRunExposesTheProseClustersOnItsTwoSides():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("attachedRunExposesTheProseClustersOnItsTwoSides");
        var result = AttachedInlineBoundaryRelocationTestSupport.resolve([
            InlineAttachment.None,
            InlineAttachment.None,
            InlineAttachment.Previous,
            InlineAttachment.Previous,
            InlineAttachment.Previous,
            InlineAttachment.None
        ]);
        TracedAssertions.assertEquals(1, result[0].previousClusterIndex);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 4), result[0].attachedClusterRange);
        TracedAssertions.assertEquals(5, result[0].nextClusterIndex);
    }

    @:test public static function attachedRunAtParagraphEndHasNoVirtualRightNeighbor():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("attachedRunAtParagraphEndHasNoVirtualRightNeighbor");
        var result = AttachedInlineBoundaryRelocationTestSupport.resolve([
            InlineAttachment.None,
            InlineAttachment.None,
            InlineAttachment.Previous,
            InlineAttachment.Previous,
            InlineAttachment.Previous
        ]);
        TracedAssertions.assertNullRendered(result[0].nextClusterIndex == null, result[0].nextClusterIndex == null ? "-" : "" + result[0].nextClusterIndex);
    }

    @:test public static function punctuationAfterFootnoteIsJudgedAgainstThePrecedingPunctuation():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("punctuationAfterFootnoteIsJudgedAgainstThePrecedingPunctuation");
        var result = AttachedInlineBoundaryRelocationTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]\uFF0C\u540E\u6587");
        var virtualBoundary = AttachedInlineBoundaryRelocationTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation", virtualBoundary.reason);
        TracedAssertions.assertTrue(virtualBoundary.naturalInnerGlue > 0);
        TracedAssertions.assertEqualsFloat(0, virtualBoundary.adjustedInnerGlue);
    }

    @:test public static function closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue");
        var result = AttachedInlineBoundaryRelocationTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]\u540E\u6587");
        var virtualBoundary = AttachedInlineBoundaryRelocationTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:natural", virtualBoundary.reason);
        TracedAssertions.assertEqualsFloat(virtualBoundary.naturalInnerGlue, virtualBoundary.adjustedInnerGlue);
        TracedAssertions.assertTrue(virtualBoundary.adjustedInnerGlue > 0);
    }

    @:test public static function closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue");
        var result = AttachedInlineBoundaryRelocationTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]");
        var virtualBoundary = AttachedInlineBoundaryRelocationTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:line-end", virtualBoundary.reason);
        TracedAssertions.assertEqualsFloat(0, virtualBoundary.adjustedInnerGlue);
    }

    @:test public static function attachedReferenceNeverStartsAWrappedLine():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("attachedReferenceNeverStartsAWrappedLine");
        var text = "\u7532\u4E591\u4E19";
        var referenceRange = new TextRange(2, 3);
        var breakers = AttachedInlineBoundaryRelocationTestSupport.breakers();
        for (bi in 0...breakers.length) {
            var choice = breakers[bi];
            var result = AttachedInlineBoundaryRelocationTestSupport.layoutWithBreaker(text, choice.breaker);
            TracedAssertions.assertTrue(result.lines.length > 1,
                choice.breaker.strategyName + ": test must wrap: " + AttachedInlineBoundaryRelocationTestSupport.renderLines(result.lines));
            var started = false;
            for (i in 0...result.lines.length) {
                var s = result.lines[i].range.start;
                if (s >= referenceRange.start && s < referenceRange.end)
                    started = true;
            }
            TracedAssertions.assertTrue(!started,
                choice.breaker.strategyName + ": attached reference started a line: " + AttachedInlineBoundaryRelocationTestSupport.renderRanges(result.lines));
            var attached = false;
            for (i in 0...result.lines.length) {
                var line = result.lines[i];
                if (line.range.start < referenceRange.start && line.range.end >= referenceRange.end)
                    attached = true;
            }
            TracedAssertions.assertTrue(attached,
                choice.breaker.strategyName + ": reference detached from prose: " + AttachedInlineBoundaryRelocationTestSupport.renderRanges(result.lines));
        }
    }
}
