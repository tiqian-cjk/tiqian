package org.tiqian.shaping;

import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ShapingInput;

class ExplainableStubTextShaperTestSupport {
    public static function input(text:String, role:FontRole, ?displayText:Null<String>):ShapingInput {
        var range = new TextRange(0, text.length);
        return new ShapingInput(text, range, new TextStyle(null, 16.0),
            new FontDecision(range, new FontCandidate("test-font", "test-font", role), role, "test"), displayText == null ? text : displayText);
    }
}
