package org.tiqian.layout;

import org.tiqian.core.TextRange;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class QuotePairAnalyzerTestSupport {
    public static function rec(name:String):Void
        new TestTraceRecorder("QuotePairAnalyzerTest").section(name);

    public static function a():QuotePairAnalyzer
        return new QuotePairAnalyzer();

    public static function sig(text:String, roles:std.SortedMap<Int, FontRole>):String {
        var out = "";
        var i = 0;
        while (i < text.length) {
            var c = text.charCodeAt(i);
            if (c == 0x2018 || c == 0x2019 || c == 0x201C || c == 0x201D) {
                var r = roles.get(i);
                out += r == FontRole.LatinText ? "L" : r == FontRole.CjkPunctuation ? "C" : "?";
            }
            i++;
        }
        return out;
    }

    public static function role(label:String, text:String, expected:String):Void {
        TracedAssertions.assertEqualsString(expected, sig(text, a().classifyPairs(text, a().analyze(text))), label);
    }

    public static function decisions(text:String):Array<QuotePairAnalyzer.QuoteRoleDecision>
        return a().classifyQuoteRoles(text, a().analyze(text));

    public static function renderDecisions(values:Array<QuotePairAnalyzer.QuoteRoleDecision>):String {
        var out = "[";
        var i = 0;
        while (i < values.length) {
            if (i > 0)
                out += ", ";
            out += values[i].toString();
            i++;
        }
        return out + "]";
    }

    public static function pairRole(name:String, text:String, indexes:Array<Int>, expected:FontRole):Void {
        rec(name);
        var r = a().classifyPairs(text, a().analyze(text));
        var i = 0;
        while (i < indexes.length) {
            TracedAssertions.assertEqualsFontRole(expected, r.get(indexes[i]));
            i++;
        }
    }
}
