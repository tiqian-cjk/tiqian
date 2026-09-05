package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class BopomofoLayoutTestSupport {
    public static function layout(bopomofo:Array<RubySpan>, ?spans:Array<TextSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文", spans), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(4000.0), null, null, bopomofo));
    }

    public static function plain():LayoutResult {
        return layout([]);
    }
}
