package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

/**
    The legacy suite declares this class inside
    engine/src/commonTest/kotlin/org/tiqian/layout/AttachedInlineBoundaryRelocationTest.kt:19,
    a file whose name differs from the class it holds. The Kotlin runner reports a
    test id as module path plus method name
    (packages/compiler/reflaxe/kotlin/kotlincompiler/Compiler.hx:159), so the module
    and the class here carry the legacy class name; naming them after the legacy
    file name leaves these six ids on the legacy side only.
**/
class AttachedInlineVirtualAdjacencyTest {
    @:test public static function attachedRunExposesTheProseClustersOnItsTwoSides():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("attachedRunExposesTheProseClustersOnItsTwoSides");
        var result = AttachedInlineVirtualAdjacencyTestSupport.resolve([
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
        var result = AttachedInlineVirtualAdjacencyTestSupport.resolve([
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
        var result = AttachedInlineVirtualAdjacencyTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]\uFF0C\u540E\u6587");
        var virtualBoundary = AttachedInlineVirtualAdjacencyTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation", virtualBoundary.reason);
        TracedAssertions.assertTrue(virtualBoundary.naturalInnerGlue > 0);
        TracedAssertions.assertEqualsFloat(0, virtualBoundary.adjustedInnerGlue);
    }

    @:test public static function closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("closingQuoteBeforeFootnoteAndBodyKeepsItsNaturalTrailingGlue");
        var result = AttachedInlineVirtualAdjacencyTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]\u540E\u6587");
        var virtualBoundary = AttachedInlineVirtualAdjacencyTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:natural", virtualBoundary.reason);
        TracedAssertions.assertEqualsFloat(virtualBoundary.naturalInnerGlue, virtualBoundary.adjustedInnerGlue);
        TracedAssertions.assertTrue(virtualBoundary.adjustedInnerGlue > 0);
    }

    @:test public static function closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("closingQuoteBeforeParagraphEndFootnoteHasNoTrailingGlue");
        var result = AttachedInlineVirtualAdjacencyTestSupport.layoutAttachedReference("\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]");
        var virtualBoundary = AttachedInlineVirtualAdjacencyTestSupport.virtualBoundary(result);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:line-end", virtualBoundary.reason);
        TracedAssertions.assertEqualsFloat(0, virtualBoundary.adjustedInnerGlue);
    }

    @:test public static function attachedReferenceNeverStartsAWrappedLine():Void {
        var t = new TestTraceRecorder("AttachedInlineVirtualAdjacencyTest");
        t.section("attachedReferenceNeverStartsAWrappedLine");
        var text = "\u7532\u4E591\u4E19";
        var referenceRange = new TextRange(2, 3);
        var breakers = AttachedInlineVirtualAdjacencyTestSupport.breakers();
        for (bi in 0...breakers.length) {
            var choice = breakers[bi];
            var result = AttachedInlineVirtualAdjacencyTestSupport.layoutWithBreaker(text, choice.breaker);
            TracedAssertions.assertTrue(result.lines.length > 1,
                choice.breaker.strategyName + ": test must wrap: " + AttachedInlineVirtualAdjacencyTestSupport.renderLines(result.lines));
            var started = false;
            for (i in 0...result.lines.length) {
                var s = result.lines[i].range.start;
                if (s >= referenceRange.start && s < referenceRange.end)
                    started = true;
            }
            TracedAssertions.assertTrue(!started,
                choice.breaker.strategyName + ": attached reference started a line: " + AttachedInlineVirtualAdjacencyTestSupport.renderRanges(result.lines));
            var attached = false;
            for (i in 0...result.lines.length) {
                var line = result.lines[i];
                if (line.range.start < referenceRange.start && line.range.end >= referenceRange.end)
                    attached = true;
            }
            TracedAssertions.assertTrue(attached,
                choice.breaker.strategyName + ": reference detached from prose: " + AttachedInlineVirtualAdjacencyTestSupport.renderRanges(result.lines));
        }
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("AttachedInlineVirtualAdjacencyTest");
    }
}
