package org.tiqian.linebreak;

import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.linebreak.LineBreakAnalyzer.SimpleCharacterLineBreakAnalyzer;
import org.tiqian.linebreak.UnicodePunctuationLineBreak.UnicodePunctuationLineBreakClass;
import org.tiqian.linebreak.BreakOpportunity.ForbiddenBreak;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.test.trace.TracedAssertions;

class LineBreakCoverageTest {
    @:test public static function testBundledHyphenationResource():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testBundledHyphenationResource");
        final p = EnglishHyphenationPatterns.load();
        TracedAssertions.assertTrue(p.length > 0);
        TracedAssertions.assertTrue(p.indexOf("\\patterns") >= 0);
    }

    @:test public static function testLineBreakModelsAndEnums():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testLineBreakModelsAndEnums");
        final o = new BreakOpportunity(5, BreakKind.Allowed, "TestReason", 10);
        TracedAssertions.assertEqualsInt(5, o.index);
        TracedAssertions.assertEqualsRendered(Std.string(o.kind), Std.string(BreakKind.Allowed));
        TracedAssertions.assertEqualsInt(10, o.penalty);
        TracedAssertions.assertEqualsString("TestReason", o.reason);
        final c = new BreakOpportunity(5, BreakKind.Problematic, "TestReason", 10);
        TracedAssertions.assertEqualsRendered(Std.string(c.kind), Std.string(BreakKind.Problematic));
        final oc = new BreakOpportunity(5, BreakKind.Allowed, "TestReason", 10);
        TracedAssertions.assertEqualsRendered(o.toString(), oc.toString());
        TracedAssertions.assertTrue(o.toString() == oc.toString());
        TracedAssertions.assertTrue(o.toString().indexOf("BreakOpportunity") >= 0);
        var i = 0;
        final kinds:Array<BreakKind> = [Allowed, Forbidden, Required, Problematic];
        while (i < kinds.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(kinds[i]));
            i++;
        }
        final f = new ForbiddenBreak(new TextRange(2, 6), "ForbiddenReason");
        TracedAssertions.assertEqualsRendered(f.range.toString(), new TextRange(2, 6).toString());
        TracedAssertions.assertEqualsString("ForbiddenReason", f.reason);
        final fc = new ForbiddenBreak(new TextRange(2, 6), "ForbiddenReason");
        TracedAssertions.assertEqualsRendered(f.toString(), fc.toString());
        TracedAssertions.assertTrue(f.toString() == fc.toString());
        TracedAssertions.assertTrue(f.toString().indexOf("ForbiddenBreak") >= 0);
    }

    @:test public static function testMandatoryBreakAndZeroWidthSpaceCodePoints():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testMandatoryBreakAndZeroWidthSpaceCodePoints");
        final yes:Array<Int> = [10, 11, 12, 13, 133, 8232, 8233];
        var i = 0;
        while (i < yes.length) {
            TracedAssertions.assertTrue(LineBreakFns.isMandatoryBreakCodePoint(yes[i]), "Code point " + yes[i] + " should be mandatory break");
            i++;
        }
        final no:Array<Int> = [32, 65, 0, 8203, 8234];
        i = 0;
        while (i < no.length) {
            TracedAssertions.assertFalse(LineBreakFns.isMandatoryBreakCodePoint(no[i]), "Code point " + no[i] + " should not be mandatory break");
            i++;
        }
        TracedAssertions.assertTrue(LineBreakFns.isZeroWidthSpaceCodePoint(8203));
        TracedAssertions.assertFalse(LineBreakFns.isZeroWidthSpaceCodePoint(8204));
        TracedAssertions.assertFalse(LineBreakFns.isZeroWidthSpaceCodePoint(8288));
        TracedAssertions.assertFalse(LineBreakFns.isZeroWidthSpaceCodePoint(65279));
        TracedAssertions.assertFalse(LineBreakFns.isZeroWidthSpaceCodePoint(32));
    }

    @:test public static function testSimpleCharacterLineBreakAnalyzer():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testSimpleCharacterLineBreakAnalyzer");
        final a = new SimpleCharacterLineBreakAnalyzer();
        final e = a.analyze("");
        TracedAssertions.assertEqualsRendered("[]", LineBreakCoverageTestHelpers.renderBreaks(e));
        final s = a.analyze("A");
        TracedAssertions.assertEqualsInt(1, s.length);
        TracedAssertions.assertEqualsInt(1, s[0].index);
        TracedAssertions.assertEqualsRendered("Required", Std.string(s[0].kind));
        TracedAssertions.assertEqualsString("SimpleCharacterLineBreakAnalyzer", s[0].reason);
        final m = a.analyze("abc");
        TracedAssertions.assertEqualsInt(3, m.length);
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(m[0].kind));
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(m[1].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(m[2].kind));
        final l = a.analyze("a\nb");
        TracedAssertions.assertEqualsInt(3, l.length);
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(l[0].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(l[1].kind));
        TracedAssertions.assertEqualsString("MandatoryBreak", l[1].reason);
        TracedAssertions.assertEqualsRendered("Required", Std.string(l[2].kind));
        final cr = a.analyze("a\r\nb");
        TracedAssertions.assertEqualsInt(4, cr.length);
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(cr[0].kind));
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(cr[1].kind));
        TracedAssertions.assertEqualsString("SimpleCharacterLineBreakAnalyzer", cr[1].reason);
        TracedAssertions.assertEqualsRendered("Required", Std.string(cr[2].kind));
        TracedAssertions.assertEqualsString("MandatoryBreak", cr[2].reason);
        TracedAssertions.assertEqualsRendered("Required", Std.string(cr[3].kind));
        final co = a.analyze("a\rb");
        TracedAssertions.assertEqualsInt(3, co.length);
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(co[0].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(co[1].kind));
        TracedAssertions.assertEqualsString("MandatoryBreak", co[1].reason);
        TracedAssertions.assertEqualsRendered("Required", Std.string(co[2].kind));
        final ce = a.analyze("a\r");
        TracedAssertions.assertEqualsInt(2, ce.length);
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(ce[0].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(ce[1].kind));
        TracedAssertions.assertEqualsString("MandatoryBreak", ce[1].reason);
    }

    @:test public static function testHyphenationComponents():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testHyphenationComponents");
        final h = new LiangHyphenator(LiangHyphenatorTest.LiangHyphenatorTestHelpers.table(["hyp", "phen"], [[0, 0, 1, 0], [0, 0, 2, 0, 0]]),
            LiangHyphenatorTest.LiangHyphenatorTestHelpers.table(["specialword"], [[1, 4, 10]]), 2, 3);
        TracedAssertions.assertEqualsIntArray([], new NoHyphenator().hyphenate("word"));
        TracedAssertions.assertEqualsIntArray([], h.hyphenate("test"));
        TracedAssertions.assertEqualsIntArray([4], h.hyphenate("SpecialWord"));
        TracedAssertions.assertEqualsIntArray([], h.hyphenate("zzzzzz"));
        final e = ParseTexHyphenationPatterns.parse("% only comments\n   ");
        TracedAssertions.assertEqualsInt(0, e.patterns.size());
        TracedAssertions.assertEqualsInt(0, e.exceptions.size());
        final m = ParseTexHyphenationPatterns.parse("\\patterns no braces \\hyphenation no braces");
        TracedAssertions.assertEqualsInt(0, m.patterns.size());
        TracedAssertions.assertEqualsInt(0, m.exceptions.size());
        final u = ParseTexHyphenationPatterns.parse("\\patterns { abc \n\\hyphenation { def");
        TracedAssertions.assertEqualsInt(0, u.patterns.size());
        TracedAssertions.assertEqualsInt(0, u.exceptions.size());
        final v = ParseTexHyphenationPatterns.parse("\\patterns{ .ab3cd. e1f }\\hyphenation{ as-so-ciate dis-allow- }");
        TracedAssertions.assertTrue(v.patterns.get(".abcd.") != null);
        TracedAssertions.assertTrue(v.exceptions.get("associate") != null);
        TracedAssertions.assertEqualsIntArray([2, 4], v.exceptions.get("associate"));
    }

    @:test public static function testUnicodePunctuationLineBreak():Void {
        new TestTraceRecorder("LineBreakCoverageTest").section("testUnicodePunctuationLineBreak");
        TracedAssertions.assertEqualsString("17.0.0", UnicodePunctuationLineBreak.DATA_REVISION);
        TracedAssertions.assertTrue(UnicodePunctuationLineBreak.DATA_SOURCE.length > 0);
        TracedAssertions.assertTrue(UnicodePunctuationLineBreak.DATA_SHA256.length > 0);
        var i = 0;
        final kinds:Array<UnicodePunctuationLineBreakClass> = [
            BreakAfter,
            BreakBoth,
            ClosePunctuation,
            CloseParenthesis,
            Exclamation,
            HyphenHH,
            Hyphen,
            Inseparable,
            InfixNumericSeparator,
            Nonstarter,
            OpenPunctuation,
            Quotation,
            SymbolsAllowingBreakAfter,
            Other
        ];
        while (i < kinds.length) {
            TracedAssertions.assertNotNullRendered(true, Std.string(kinds[i]));
            i++;
        }
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(-1);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(0x110000);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(0xD800);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(0xDFFF);
        });
        var cps:Array<Int> = [
            9, 0x2014, 0x7D, 0x29, 0x21, 0x58A, 0x2D, 0x2025, 0x2C, 0x3005, 0x28, 0x22, 0x2F, 0x41
        ];
        i = 0;
        while (i < cps.length) {
            TracedAssertions.assertEqualsRendered(Std.string(kinds[i]), Std.string(UnicodePunctuationLineBreak.classOf(cps[i])));
            i++;
        }
    }
}

class LineBreakCoverageTestHelpers {
    public static function renderBreaks(values:std.ReadOnlyArray<BreakOpportunity>):String {
        final b = new StringBuf();
        b.add("[");
        var i = 0;
        while (i < values.length) {
            if (i > 0)
                b.add(", ");
            b.add(values[i].toString());
            i++;
        }
        b.add("]");
        return b.toString();
    }
}
