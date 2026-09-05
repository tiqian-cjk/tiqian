package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;

class ZeroWidthBreakControlLayoutTestSupport {
    public static function layout(text:String, maxWidth:Float, breaker:LineBreaker):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, breaker, null, null,
            new NoHyphenator()).layout(new LayoutInput(new TiqianTextContent(text), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(maxWidth)));
    }
}
