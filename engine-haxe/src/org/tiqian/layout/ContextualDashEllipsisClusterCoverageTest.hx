package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ContextualDashEllipsisClusterCoverageTestSupport {
    public static function singleMark(d:std.ReadOnlyArray<FontDecisionInfo>):FontDecisionInfo {
        for (i in 0...d.length)
            if (d[i].sourceText.indexOf("\u2014") >= 0)
                return d[i];
        throw new TiqianIllegalArgumentException(Message("no fontDecision with sourceText containing dash"));
    }

    public static function dashSingles(d:std.ReadOnlyArray<FontDecisionInfo>):Array<FontDecisionInfo> {
        var a:Array<FontDecisionInfo> = [];
        for (i in 0...d.length)
            if (d[i].sourceText == "\u2014")
                a.push(d[i]);
        return a;
    }

    public static function layout(text:String, ?spans:Array<TextSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text, spans == null ? [] : spans), new TextStyle(),
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(1000.0)));
    }
}

class ContextualDashEllipsisClusterCoverageTest {
    @:test public static function latinDashRunAtParagraphEndStaysOneCluster():Void {
        var t = new TestTraceRecorder("ContextualDashEllipsisClusterCoverageTest");
        t.section("latinDashRunAtParagraphEndStaysOneCluster");
        var d = ContextualDashEllipsisClusterCoverageTestSupport.singleMark(ContextualDashEllipsisClusterCoverageTestSupport.layout("End\u2014\u2014")
            .debug.fontDecisions);
        if (d.sourceText != "\u2014\u2014" || d.role != Type.enumConstructor(FontRole.LatinText))
            throw new TiqianIllegalArgumentException(Message("latin dash cluster"));
    }

    @:test public static function styleSpanInsideLatinDashRunSplitsTheCluster():Void {
        var t = new TestTraceRecorder("ContextualDashEllipsisClusterCoverageTest");
        t.section("styleSpanInsideLatinDashRunSplitsTheCluster");
        var r = ContextualDashEllipsisClusterCoverageTestSupport.layout("A\u2014\u2014B",
            [new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, 700))]);
        var ds = ContextualDashEllipsisClusterCoverageTestSupport.dashSingles(r.debug.fontDecisions);
        if (ds.length != 2)
            throw new TiqianIllegalArgumentException(Message("dash split count"));
        for (i in 0...ds.length)
            if (ds[i].role != Type.enumConstructor(FontRole.LatinText))
                throw new TiqianIllegalArgumentException(Message("dash split role"));
    }
}
