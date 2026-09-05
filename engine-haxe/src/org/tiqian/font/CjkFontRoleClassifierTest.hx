package org.tiqian.font;

import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class CjkFontRoleClassifierTest {
    @:test public static function classifiesAsciiBracketsAsLatin():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesAsciiBracketsAsLatin");
        var xs = ["(", ")", "[", "]", "{", "}", "中(文"];
        var xi = 0;
        while (xi < xs.length) {
            var x = xs[xi];
            TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c(x, x == "中(文" ? 1 : 0, x == "中(文" ? 2 : 1)));
            xi++;
        }
    }

    @:test public static function classifiesAsciiHyphenSlashTildeAsLatinRegardlessOfContext():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesAsciiHyphenSlashTildeAsLatinRegardlessOfContext");
        var xs = [
            "well-known",
            "https://example",
            "https://example",
            "中文/TERFism",
            "中文-中文",
            "中文~中文"
        ];
        var xi = 0;
        while (xi < xs.length) {
            var x = xs[xi];
            var p = xi == 0 ? 4 : (xi == 1 ? 6 : (xi == 2 ? 7 : 2));
            TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c(x, p, p + 1)));
            xi++;
        }
    }

    @:test public static function classifiesAsciiSymbolsAndPunctuationAsLatin():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesAsciiSymbolsAndPunctuationAsLatin");
        var xs = [
            "%", ".", ",", ":", ";", "!", "?", "#", "@", "&", "*", "+", "=", "<", ">", "|", "^", "_", "$", "'", "\""
        ];
        var xi = 0;
        while (xi < xs.length) {
            var x = xs[xi];
            TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c(x, 0, 1)), "char=" + x);
            xi++;
        }
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("中%文", 1, 2)));
    }

    @:test public static function classifiesCjkPunctuation():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCjkPunctuation");
        var a = ["……", "⋯⋯", "——", "⸺", "。", "・", "‧", "～", "／"];
        var i = 0;
        while (i < a.length) {
            var x = a[i];
            TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c(x, 0, 1)));
            i++;
        }
    }

    @:test public static function classifiesCjkText():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCjkText");
        TracedAssertions.assertEqualsRendered("CjkText", Std.string(CjkFontRoleClassifierTestSupport.c("提", 0, 1)));
    }

    @:test public static function classifiesCurlyQuotesAsCjkAtTextBoundary():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCurlyQuotesAsCjkAtTextBoundary");
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("“你好”", 0, 1)));
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("“你好”", 3, 4)));
    }

    @:test public static function classifiesCurlyQuotesAsCjkInMixedContext():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCurlyQuotesAsCjkInMixedContext");
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说“hello”", 2, 3)));
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说“hello”", 8, 9)));
    }

    @:test public static function classifiesCurlyQuotesAsCjkWhenSurroundedByCjk():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCurlyQuotesAsCjkWhenSurroundedByCjk");
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说“你好”", 2, 3)));
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说“你好”", 5, 6)));
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说‘你好’", 2, 3)));
        TracedAssertions.assertEqualsRendered("CjkPunctuation", Std.string(CjkFontRoleClassifierTestSupport.c("他说‘你好’", 5, 6)));
    }

    @:test public static function classifiesCurlyQuotesAsLatinWhenSurroundedByLatin():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesCurlyQuotesAsLatinWhenSurroundedByLatin");
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("said “hello” end", 5, 6)));
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("said “hello” end", 11, 12)));
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("it’s", 2, 3)));
    }

    @:test public static function classifiesLatinText():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesLatinText");
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("English", 0, 1)));
    }

    @:test public static function classifiesUnicodeEmojiPresentationWithoutReclassifyingPlainKeycapBases():Void {
        new TestTraceRecorder("CjkFontRoleClassifierTest").section("classifiesUnicodeEmojiPresentationWithoutReclassifyingPlainKeycapBases");
        var xs = ["⌚", "🀄", "🫪"];
        var xi = 0;
        while (xi < xs.length) {
            var x = xs[xi];
            TracedAssertions.assertEqualsRendered("Emoji", Std.string(CjkFontRoleClassifierTestSupport.c(x, 0, x.length)), x);
            xi++;
        }
        TracedAssertions.assertEqualsRendered("LatinText", Std.string(CjkFontRoleClassifierTestSupport.c("1", 0, 1)));
        TracedAssertions.assertEqualsRendered("Symbol", Std.string(CjkFontRoleClassifierTestSupport.c("❤", 0, 1)));
    }
}
