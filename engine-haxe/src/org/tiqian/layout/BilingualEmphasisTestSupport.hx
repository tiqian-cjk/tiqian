package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class BilingualEmphasisTestSupport {
    public static function layout():LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("强调中A中"), null, null, new LayoutConstraints(400.0),
            null, [new DecorationSpan(new TextRange(2, 5), DecorationKind.Emphasis)]));
    }
}
