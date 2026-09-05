package org.tiqian.font;

import org.tiqian.font.FontPolicy.FontRequest;
import org.tiqian.font.FontPolicy.FontRoleFns;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.StubFontMetricsResolver;
import org.tiqian.font.FontMetrics.ScriptAwareFontMetricsNormalizer;
import org.tiqian.font.FontMetrics.FontMetricsNormalizationInput;

class FontPolicyCoverageTest {
    @:test public static function testCjkFontRoleClassifierAllRanges():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testCjkFontRoleClassifierAllRanges");
        final classifier = new CjkFontRoleClassifier();
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify("\u3105", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify("\u31A0", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify("\u3400", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify("\u4E00", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify("\uF900", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD840, 0xDC00]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD869, 0xDF00]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD86D, 0xDF40]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD86E, 0xDC20]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(CjkText, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD880, 0xDC00]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD888, 0xDC00]), new TextRange(0, 2)));
        final punct = [
            "\u3000", "\u2014", "\u2013", "\u203C", "\u2047", "\u2026", "\u2027", "\u22EF", "\u30FB", "\u2E3A", "\u00B7", "\u2022", "\uFF01", "\uFF1F",
            "\uFF0C", "\uFF0E", "\uFF0F", "\uFF1A", "\uFF1B", "\uFF08", "\uFF09", "\uFF5E"
        ];
        var i = 0;
        while (i < punct.length) {
            var ch = punct[i];
            TracedAssertions.assertEqualsFontRole(CjkPunctuation, classifier.classify(ch, new TextRange(0, ch.length)), "Expected CjkPunctuation for " + ch);
            i++;
        }
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("a\u2019b", new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("a\u201Db", new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation, classifier.classify("\u2019b", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation, classifier.classify("a\u2019", new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation, classifier.classify("\u4E2D\u2019\u6587", new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD83D, 0xDE00, 0x2019, 'b'.code]), new TextRange(2, 3)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText(['A'.code, 0xDC00, 0x2019, 'b'.code]), new TextRange(2, 3)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xE000, 0xDC00, 0x2019, 'b'.code]), new TextRange(2, 3)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xDC00, 0x2019, 'b'.code]), new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation, classifier.classify("\uE000\u2019b", new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(CjkPunctuation,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText(['a'.code, 0x2019, 0xD83D, 0xDE00]), new TextRange(1, 2)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify("\uE000", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD800]), new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Unknown,
            classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD800, 'A'.code]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD800, 0xE000]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD804, 0xDC00]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("A", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("z", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("0", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify(" ", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("+", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("\u00C0", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(LatinText, classifier.classify("\u0150", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Emoji, classifier.classify(FontPolicyCoverageTestSupport.surrogateText([0xD83D, 0xDE00]), new TextRange(0, 2)));
        TracedAssertions.assertEqualsFontRole(Symbol, classifier.classify("\u2260", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Symbol, classifier.classify("\u20AC", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Symbol, classifier.classify("\u02D8", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Symbol, classifier.classify("\u00A9", new TextRange(0, 1)));
        TracedAssertions.assertEqualsFontRole(Unknown, classifier.classify("\u0001", new TextRange(0, 1)));
    }

    @:test public static function testFontEnumsAndModels():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testFontEnumsAndModels");
        final metricsPolicies = Type.allEnums(FontMetricsPolicy);
        var i = 0;
        while (i < metricsPolicies.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(metricsPolicies[i]));
            i++;
        }
        final baselinePolicies = Type.allEnums(BaselinePolicy);
        i = 0;
        while (i < baselinePolicies.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(baselinePolicies[i]));
            i++;
        }
        final punctuationPolicies = Type.allEnums(PunctuationFontPolicy);
        i = 0;
        while (i < punctuationPolicies.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(punctuationPolicies[i]));
            i++;
        }
        final raw = new RawFontMetrics(16, 4, 2, RawTables, 14, 2);
        TracedAssertions.assertEqualsFloat(16, raw.ascent);
        TracedAssertions.assertEqualsFloat(4, raw.descent);
        TracedAssertions.assertEqualsFloat(2, raw.leading);
        TracedAssertions.assertEqualsFloat(14, raw.typoAscent);
        TracedAssertions.assertEqualsFloat(2, raw.typoDescent);
        final rawCopy = new RawFontMetrics(raw.ascent, raw.descent, raw.leading, raw.source, raw.typoAscent, raw.typoDescent);
        TracedAssertions.assertEqualsRendered(Std.string(raw), Std.string(rawCopy));
        TracedAssertions.assertTrue(Std.string(raw) == Std.string(rawCopy));
        final layout = new LayoutFontMetrics(14, 2, 0, IdeographicBox, Ideographic, IdeographicLow, IdeographicEmBox, RawTables, "test");
        TracedAssertions.assertEqualsFloat(14, layout.ascent);
        final layoutCopy = new LayoutFontMetrics(layout.ascent, layout.descent, layout.baselineOffset, layout.policy, layout.baselinePolicy,
            layout.baselineClass, layout.metricBox, layout.source, layout.reason);
        TracedAssertions.assertEqualsRendered(Std.string(layout), Std.string(layoutCopy));
        TracedAssertions.assertTrue(Std.string(layout) == Std.string(layoutCopy));
    }

    @:test public static function testFontMetricsRequestAndResolvers():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testFontMetricsRequestAndResolvers");
        final request = new FontMetricsRequest("key1", 16, CjkText, "zh-Hans", ["FontA"], 700, true, "\u6D4B\u8BD5");
        TracedAssertions.assertEqualsString("key1", request.fontKey);
        TracedAssertions.assertEqualsFloat(16, request.fontSize);
        TracedAssertions.assertEqualsFontRole(CjkText, request.role);
        TracedAssertions.assertEqualsString("zh-Hans", request.locale);
        TracedAssertions.assertEqualsStringArray(["FontA"], request.fontFamilies);
        TracedAssertions.assertEqualsInt(700, request.fontWeight);
        TracedAssertions.assertTrue(request.italic);
        TracedAssertions.assertEqualsString("\u6D4B\u8BD5", request.faceSelectionText);
        final requestCopy = new FontMetricsRequest(request.fontKey, request.fontSize, request.role, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText);
        TracedAssertions.assertEqualsRendered(Std.string(request), Std.string(requestCopy));
        TracedAssertions.assertTrue(Std.string(request) == Std.string(requestCopy));
        final resolver = new StubFontMetricsResolver();
        final cjk = resolver.resolve(request);
        TracedAssertions.assertEqualsFloat(16 * 1.16, cjk.ascent);
        TracedAssertions.assertEqualsFloat(16 * 0.88, cjk.typoAscent == null ? 0 : cjk.typoAscent);
        final punct = resolver.resolve(new FontMetricsRequest(request.fontKey, request.fontSize, CjkPunctuation, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText));
        TracedAssertions.assertEqualsFloat(16 * 1.16, punct.ascent);
        final latin = resolver.resolve(new FontMetricsRequest(request.fontKey, request.fontSize, LatinText, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText));
        TracedAssertions.assertEqualsFloat(16 * 0.8, latin.ascent);
        final symbol = resolver.resolve(new FontMetricsRequest(request.fontKey, request.fontSize, Symbol, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText));
        TracedAssertions.assertEqualsFloat(16 * 0.9, symbol.ascent);
        final emoji = resolver.resolve(new FontMetricsRequest(request.fontKey, request.fontSize, Emoji, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText));
        TracedAssertions.assertEqualsFloat(16 * 0.9, emoji.ascent);
        final unknown = resolver.resolve(new FontMetricsRequest(request.fontKey, request.fontSize, Unknown, request.locale,
            FontPolicyCoverageTestSupport.copyStrings(request.fontFamilies), request.fontWeight, request.italic, request.faceSelectionText));
        TracedAssertions.assertEqualsFloat(16 * 0.9, unknown.ascent);
    }

    @:test public static function testFontRequestAndRoles():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testFontRequestAndRoles");
        final request = new FontRequest(["Source Han Sans"], "zh-Hans", CjkText);
        TracedAssertions.assertEqualsStringArray(["Source Han Sans"], request.preferredFamilies);
        TracedAssertions.assertEqualsString("zh-Hans", request.locale);
        TracedAssertions.assertEqualsFontRole(CjkText, request.role);
        final requestCopy = new FontRequest(request.preferredFamilies, request.locale, request.role);
        TracedAssertions.assertEqualsRendered(Std.string(request), Std.string(requestCopy));
        TracedAssertions.assertTrue(Std.string(request) == Std.string(requestCopy));
        final roles = Type.allEnums(FontRole);
        var i = 0;
        while (i < roles.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(roles[i]));
            i++;
        }
        TracedAssertions.assertTrue(FontRoleFns.usesLatinFace(LatinText));
        TracedAssertions.assertFalse(FontRoleFns.usesLatinFace(CjkText));
        TracedAssertions.assertFalse(FontRoleFns.usesLatinFace(CjkPunctuation));
        TracedAssertions.assertFalse(FontRoleFns.usesLatinFace(Symbol));
        TracedAssertions.assertFalse(FontRoleFns.usesLatinFace(Emoji));
        TracedAssertions.assertFalse(FontRoleFns.usesLatinFace(Unknown));
        TracedAssertions.assertTrue(FontRoleFns.fontRoleNameUsesLatinFace("LatinText"));
        TracedAssertions.assertFalse(FontRoleFns.fontRoleNameUsesLatinFace("CjkText"));
        TracedAssertions.assertFalse(FontRoleFns.fontRoleNameUsesLatinFace("Unknown"));
        TracedAssertions.assertFalse(FontRoleFns.fontRoleNameUsesLatinFace(null));
        TracedAssertions.assertFalse(FontRoleFns.fontRoleNameUsesLatinFace("NotARole"));
        final candidate = new FontCandidate("cjk-key", "Source Han Sans", CjkText);
        TracedAssertions.assertEqualsString("cjk-key", candidate.key);
        TracedAssertions.assertEqualsString("Source Han Sans", candidate.family);
        TracedAssertions.assertEqualsFontRole(CjkText, candidate.role);
        final candidateCopy = new FontCandidate(candidate.key, candidate.family, candidate.role);
        TracedAssertions.assertEqualsRendered(Std.string(candidate), Std.string(candidateCopy));
        TracedAssertions.assertTrue(Std.string(candidate) == Std.string(candidateCopy));
        final decision = new FontDecision(new TextRange(0, 1), candidate, CjkText, "reason");
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", Std.string(decision.range));
        TracedAssertions.assertEqualsRendered(Std.string(candidate), Std.string(decision.candidate));
        TracedAssertions.assertEqualsFontRole(CjkText, decision.role);
        TracedAssertions.assertEqualsString("reason", decision.reason);
        final decisionCopy = new FontDecision(decision.range, decision.candidate, decision.role, decision.reason);
        TracedAssertions.assertEqualsRendered(Std.string(decision), Std.string(decisionCopy));
        TracedAssertions.assertTrue(Std.string(decision) == Std.string(decisionCopy));
        final context = new FontRoleContext("zh-TW", "TW");
        TracedAssertions.assertEqualsString("zh-TW", context.locale);
        TracedAssertions.assertEqualsString("TW", context.regionHint);
        final contextCopy = new FontRoleContext(context.locale, context.regionHint);
        TracedAssertions.assertEqualsRendered(Std.string(context), Std.string(contextCopy));
        TracedAssertions.assertTrue(Std.string(context) == Std.string(contextCopy));
    }

    @:test public static function testPreferCjkForAmbiguousPunctuationResolver():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testPreferCjkForAmbiguousPunctuationResolver");
        final resolver = new PreferCjkForAmbiguousPunctuationResolver("cjk-key", "latin-key", "symbol-key");
        var d = resolver.resolve("\u4E2D", new TextRange(0, 1), new FontRequest(["CustomCjk"], "zh-Hans", CjkText));
        TracedAssertions.assertEqualsString("cjk-key", d.candidate.key);
        TracedAssertions.assertEqualsString("CustomCjk", d.candidate.family);
        d = resolver.resolve("\u4E2D", new TextRange(0, 1), new FontRequest([], "zh-Hans", CjkPunctuation));
        TracedAssertions.assertEqualsString("cjk-key", d.candidate.family);
        d = resolver.resolve("A", new TextRange(0, 1), new FontRequest([], "en", LatinText));
        TracedAssertions.assertEqualsString("latin-key", d.candidate.key);
        d = resolver.resolve("\u00A9", new TextRange(0, 1), new FontRequest([], "en", Symbol));
        TracedAssertions.assertEqualsString("symbol-key", d.candidate.key);
        d = resolver.resolve(FontPolicyCoverageTestSupport.surrogateText([0xD83D, 0xDE00]), new TextRange(0, 2), new FontRequest([], "en", Emoji));
        TracedAssertions.assertEqualsString("symbol-key", d.candidate.key);
        d = resolver.resolve("\u0001", new TextRange(0, 1), new FontRequest([], "en", Unknown));
        TracedAssertions.assertEqualsString("symbol-key", d.candidate.key);
    }

    @:test public static function testScriptAwareFontMetricsNormalizerBranches():Void {
        final t = new TestTraceRecorder("FontPolicyCoverageTest");
        t.section("testScriptAwareFontMetricsNormalizerBranches");
        final normalizer = new ScriptAwareFontMetricsNormalizer();
        final base = new FontMetricsRequest("key", 16, CjkText, "zh-Hans");
        final inputWithTypo = new FontMetricsNormalizationInput(base, new RawFontMetrics(18, 5, 0, RawTables, 14, 2));
        final typo = normalizer.normalize(inputWithTypo);
        TracedAssertions.assertEqualsFloat(14, typo.ascent);
        TracedAssertions.assertEqualsFloat(2, typo.descent);
        TracedAssertions.assertEqualsRendered("IdeographicBox", Std.string(typo.policy));
        TracedAssertions.assertTrue(typo.reason.indexOf("font-typo-box") >= 0);
        final inputPartialTypo1 = new FontMetricsNormalizationInput(base, new RawFontMetrics(18, 5, 0, RawTables, 14, null));
        final partial1 = normalizer.normalize(inputPartialTypo1);
        TracedAssertions.assertEqualsFloat(14, partial1.ascent);
        TracedAssertions.assertEqualsFloat(5, partial1.descent);
        TracedAssertions.assertEqualsRendered("Raw", Std.string(partial1.policy));
        TracedAssertions.assertTrue(partial1.reason.indexOf("hhea-fallback-no-os2") >= 0);
        final inputPartialTypo2 = new FontMetricsNormalizationInput(base, new RawFontMetrics(18, 5, 0, RawTables, null, 2));
        final partial2 = normalizer.normalize(inputPartialTypo2);
        TracedAssertions.assertEqualsFloat(18, partial2.ascent);
        TracedAssertions.assertEqualsFloat(2, partial2.descent);
        TracedAssertions.assertEqualsRendered("Raw", Std.string(partial2.policy));
        final inputNoTypo = new FontMetricsNormalizationInput(base, new RawFontMetrics(18, 5, 0, RawTables, null, null));
        final noTypo = normalizer.normalize(inputNoTypo);
        TracedAssertions.assertEqualsFloat(18, noTypo.ascent);
        TracedAssertions.assertEqualsFloat(5, noTypo.descent);
        TracedAssertions.assertEqualsRendered("Raw", Std.string(noTypo.policy));
        final inputLatin = new FontMetricsNormalizationInput(new FontMetricsRequest("key", 16, LatinText, "zh-Hans"), new RawFontMetrics(13, 3));
        final latin = normalizer.normalize(inputLatin);
        TracedAssertions.assertEqualsFloat(13, latin.ascent);
        TracedAssertions.assertEqualsFloat(3, latin.descent);
        TracedAssertions.assertEqualsRendered("Raw", Std.string(latin.policy));
        TracedAssertions.assertEqualsRendered("Alphabetic", Std.string(latin.baselinePolicy));
        final inputSymbol = new FontMetricsNormalizationInput(new FontMetricsRequest("key", 16, Symbol, "zh-Hans"), new RawFontMetrics(14, 4));
        final symbol = normalizer.normalize(inputSymbol);
        TracedAssertions.assertEqualsFloat(14, symbol.ascent);
        TracedAssertions.assertEqualsRendered("Raw", Std.string(symbol.policy));
        final inputCopy = new FontMetricsNormalizationInput(inputWithTypo.request, inputWithTypo.rawMetrics);
        TracedAssertions.assertEqualsRendered(Std.string(inputWithTypo), Std.string(inputCopy));
        TracedAssertions.assertTrue(Std.string(inputWithTypo) == Std.string(inputCopy));
    }
}
