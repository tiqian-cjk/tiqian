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
            final unit = codes[i];
            // A high surrogate followed by a low surrogate forms one
            // scalar; emit it as a single fromCharCode so a target that
            // decodes one UTF-16 unit at a time keeps the pair intact.
            // A lone surrogate stays a unit (a target without unpaired
            // surrogates cannot represent it).
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < codes.length
                && codes[i + 1] >= 0xDC00 && codes[i + 1] <= 0xDFFF) {
                final low = codes[i + 1];
                result += String.fromCharCode(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
                i += 2;
            } else {
                result += String.fromCharCode(unit);
                i += 1;
            }
        }
        return result;
    }
}
