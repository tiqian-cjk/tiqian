package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class InlineBoxLayoutTestSupport {
    public static function layout(outer:InlineBoxOuterSpacing):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中./中"), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(400.0), null, null, null,
            [new InlineBoxSpan(new TextRange(1, 3), 3.0, 5.0, outer)]));
    }

    public static function plain():LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中。"), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(400.0)));
    }

    public static function boxedEdges():LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中。"), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(400.0), null, null, null,
            [new InlineBoxSpan(new TextRange(1, 2), 3.0, 5.0, InlineBoxOuterSpacing.Source)]));
    }
}
