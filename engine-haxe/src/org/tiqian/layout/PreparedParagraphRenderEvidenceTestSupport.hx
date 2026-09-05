package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;

class PreparedParagraphRenderEvidenceTestSupport {
    public static function layout(input:LayoutInput):LayoutResult
        return new ExplainableStubParagraphLayoutEngine(new LookaheadLineBreaker()).layout(input);

    public static function evidence(r:LayoutResult):String
        return PreparedParagraphFns.toPreparedParagraphJson(r, true);

    public static function plain(r:LayoutResult):String
        return PreparedParagraphFns.toPreparedParagraphJson(r, false);

    public static function contains(s:String, x:String, msg:String):Void
        if (s.indexOf(x) < 0)
            TracedAssertions.fail(msg);
}
