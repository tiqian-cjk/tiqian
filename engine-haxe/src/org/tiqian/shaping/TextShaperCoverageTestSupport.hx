package org.tiqian.shaping;

import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ShapingInput;

class TextShaperCoverageTestSupport {
    public static function input(text:String, ?role:Null<FontRole>, ?displayText:Null<String>, ?features:Array<String>):ShapingInput {
        var actualRole = role == null ? FontRole.LatinText : role;
        var range = new TextRange(0, text.length);
        return new ShapingInput(text, range, new TextStyle(null, 16.0),
            new FontDecision(range, new FontCandidate("test-font", "test-font", actualRole), actualRole, "coverage-test"),
            displayText == null ? text : displayText, features == null ? [] : features);
    }

    public static function surrogateText(codes:Array<Int>):String {
        var result = "";
        var i = 0;
        while (i < codes.length) {
            result += String.fromCharCode(codes[i]);
            i++;
        }
        return result;
    }
}
