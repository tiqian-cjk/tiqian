package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class AutoSpaceSingleGapTest {
    @:test public static function attachedReferenceBetweenCjkTextDoesNotInventAnAutospaceGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("attachedReferenceBetweenCjkTextDoesNotInventAnAutospaceGap");
        final r = AutoSpaceSingleGapTestSupport.layout("正文1后文", [
            new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ]);
        TracedAssertions.assertTrue(r.debug.autoSpaceDecisions.length == 0, AutoSpaceSingleGapTestSupport.renderAutoSpaceDecisions(r.debug.autoSpaceDecisions));
    }

    @:test public static function attachedReferenceBeforeLatinTextGetsTheVirtualCjkLatinGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("attachedReferenceBeforeLatinTextGetsTheVirtualCjkLatinGap");
        final r = AutoSpaceSingleGapTestSupport.layout("正文1ABC", [
            new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ]);
        final d = r.debug.autoSpaceDecisions[0];
        TracedAssertions.assertEqualsString("trailing", d.side);
        TracedAssertions.assertEqualsString("InlineAttachment.Previous", d.boundaryRole);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualAutoSpace:east-asian-spacing-W-N", d.reason);
    }

    @:test public static function attachedReferenceAtParagraphEndHasNoAutospaceGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("attachedReferenceAtParagraphEndHasNoAutospaceGap");
        final r = AutoSpaceSingleGapTestSupport.layout("正文1", [
            new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ]);
        TracedAssertions.assertTrue(r.debug.autoSpaceDecisions.length == 0, AutoSpaceSingleGapTestSupport.renderAutoSpaceDecisions(r.debug.autoSpaceDecisions));
    }

    @:test public static function oneTypedSpaceBecomesOneAutospaceGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("oneTypedSpaceBecomesOneAutospaceGap");
        final r = AutoSpaceSingleGapTestSupport.layout("中文 CJK 段落", []);
        final s = AutoSpaceSingleGapTestSupport.clustersWithText(r, " ");
        TracedAssertions.assertEqualsInt(2, s.length);
        var all = true;
        for (i in 0...s.length)
            if (s[i].advance != 2.0)
                all = false;
        TracedAssertions.assertTrue(all);
        TracedAssertions.assertEqualsFloat(48, AutoSpaceSingleGapTestSupport.clustersWithText(r, "CJK")[0].advance);
    }

    @:test public static function twoTypedSpacesAtBoundaryStillCollapseToOneGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("twoTypedSpacesAtBoundaryStillCollapseToOneGap");
        final r = AutoSpaceSingleGapTestSupport.layout("中文  CJK 段落", []);
        TracedAssertions.assertEqualsFloat(2, AutoSpaceSingleGapTestSupport.clustersWithText(r, "  ")[0].advance);
        TracedAssertions.assertEqualsFloat(2, AutoSpaceSingleGapTestSupport.clustersWithText(r, " ")[0].advance);
    }

    @:test public static function threeTypedSpacesStillOneGap():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("threeTypedSpacesStillOneGap");
        final r = AutoSpaceSingleGapTestSupport.layout("中文   CJK段落", []);
        TracedAssertions.assertEqualsFloat(2, AutoSpaceSingleGapTestSupport.clustersWithText(r, "   ")[0].advance);
        TracedAssertions.assertEqualsFloat(50, AutoSpaceSingleGapTestSupport.clustersWithText(r, "CJK")[0].advance);
    }

    @:test public static function zeroSpacesGetInsertedGaps():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("zeroSpacesGetInsertedGaps");
        final r = AutoSpaceSingleGapTestSupport.layout("中文CJK段落", []);
        TracedAssertions.assertEqualsFloat(52, AutoSpaceSingleGapTestSupport.clustersWithText(r, "CJK")[0].advance);
        TracedAssertions.assertEqualsInt(2, r.debug.autoSpaceDecisions.length);
        var modes = true;
        var reductions = true;
        var reasons = true;
        for (i in 0...r.debug.autoSpaceDecisions.length) {
            final x = r.debug.autoSpaceDecisions[i];
            if (x.mode != "Insert" || x.charactersAffected != 0)
                modes = false;
            if (x.totalReduction != -2.0)
                reductions = false;
            if (x.reason.indexOf("TextAutoSpaceInsert") != 0)
                reasons = false;
        }
        TracedAssertions.assertTrue(modes);
        TracedAssertions.assertTrue(reductions);
        TracedAssertions.assertTrue(reasons);
    }

    @:test public static function unicodeEastAsianSpacingCoversNarrowScriptsWithoutScriptWhitelists():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("unicodeEastAsianSpacingCoversNarrowScriptsWithoutScriptWhitelists");
        for (si in 0...3) {
            final sample = ["α", "я", "ա"][si];
            final r = AutoSpaceSingleGapTestSupport.layout("中" + sample + "文", []);
            final n = AutoSpaceSingleGapTestSupport.clustersWithText(r, sample)[0];
            TracedAssertions.assertEqualsFloat(20, n.advance, "sample=" + sample);
            TracedAssertions.assertEqualsInt(2, r.debug.autoSpaceDecisions.length, "sample=" + sample);
            var all = false;
            if (r.debug.autoSpaceDecisions.length > 0) {
                all = true;
                for (i in 0...r.debug.autoSpaceDecisions.length)
                    if (!AutoSpaceSingleGapTestSupport.sameRange(r.debug.autoSpaceDecisions[i].clusterRange, n.range))
                        all = false;
            }
            TracedAssertions.assertTrue(all, "sample=" + sample);
            var rr = true;
            for (i in 0...r.debug.autoSpaceDecisions.length)
                if (r.debug.autoSpaceDecisions[i].reason != "TextAutoSpaceInsert:east-asian-spacing-W-N")
                    rr = false;
            TracedAssertions.assertTrue(rr, "sample=" + sample);
        }
    }

    @:test public static function conditionalPunctuationFollowsChineseLanguageResolution():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("conditionalPunctuationFollowsChineseLanguageResolution");
        final r = AutoSpaceSingleGapTestSupport.layout("中%文", []);
        TracedAssertions.assertEqualsInt(2, r.debug.autoSpaceDecisions.length);
        var ok = true;
        for (i in 0...r.debug.autoSpaceDecisions.length)
            if (r.debug.autoSpaceDecisions[i].boundaryRole != "EastAsianSpacing.Wide")
                ok = false;
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function autospaceDoesNotFireBetweenLatinAndCjkPunctuation():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("autospaceDoesNotFireBetweenLatinAndCjkPunctuation");
        TracedAssertions.assertEqualsInt(0, AutoSpaceSingleGapTestSupport.layout("Tiqian ）说明", []).debug.autoSpaceDecisions.length);
    }

    @:test public static function autospaceDoesNotFireBeforeSlashLedLatinTechnicalRun():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("autospaceDoesNotFireBeforeSlashLedLatinTechnicalRun");
        final r = AutoSpaceSingleGapTestSupport.layout("恐跨/TERFism。如果", []);
        final c = AutoSpaceSingleGapTestSupport.clustersWithText(r, "/TERFism")[0];
        var saw = false;
        for (i in 0...r.debug.autoSpaceDecisions.length)
            if (AutoSpaceSingleGapTestSupport.sameRange(r.debug.autoSpaceDecisions[i].clusterRange, c.range)
                && r.debug.autoSpaceDecisions[i].side == "leading")
                saw = true;
        TracedAssertions.assertTrue(!saw,
            "slash-led Latin technical run must not receive leading autospace: " +
            AutoSpaceSingleGapTestSupport.renderAutoSpaceDecisions(r.debug.autoSpaceDecisions));
    }

    @:test public static function autospaceStillFiresBetweenLatinAndCjkTextEvenWithPunctuationNearby():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("autospaceStillFiresBetweenLatinAndCjkTextEvenWithPunctuationNearby");
        final r = AutoSpaceSingleGapTestSupport.layout("中文 shaping 之后", []);
        TracedAssertions.assertEqualsInt(2, r.debug.autoSpaceDecisions.length);
        var role = true;
        var side = true;
        for (i in 0...r.debug.autoSpaceDecisions.length) {
            if (r.debug.autoSpaceDecisions[i].boundaryRole != "EastAsianSpacing.Wide")
                role = false;
            if (r.debug.autoSpaceDecisions[i].side != "gap")
                side = false;
        }
        TracedAssertions.assertTrue(role);
        TracedAssertions.assertTrue(side);
    }

    @:test public static function autospaceDistinguishesLetterFromDigitAtBoundary():Void {
        final t = new TestTraceRecorder("AutoSpaceSingleGapTest");
        t.section("autospaceDistinguishesLetterFromDigitAtBoundary");
        final r = AutoSpaceSingleGapTestSupport.letterDigit();
        final a = AutoSpaceSingleGapTestSupport.clustersWithText(r, "A")[0].range;
        final n = AutoSpaceSingleGapTestSupport.clustersWithText(r, "9")[0].range;
        var all = true;
        for (i in 0...r.debug.autoSpaceDecisions.length)
            if (!AutoSpaceSingleGapTestSupport.sameRange(r.debug.autoSpaceDecisions[i].clusterRange, a))
                all = false;
        TracedAssertions.assertTrue(r.debug.autoSpaceDecisions.length > 0 && all,
            "only the letter fires: " + AutoSpaceSingleGapTestSupport.renderAutoSpaceDecisions(r.debug.autoSpaceDecisions));
        var saw = false;
        for (i in 0...r.debug.autoSpaceDecisions.length)
            if (AutoSpaceSingleGapTestSupport.sameRange(r.debug.autoSpaceDecisions[i].clusterRange, n))
                saw = true;
        TracedAssertions.assertTrue(!saw, "digit boundary must not fire when cjkDigit disabled");
    }
}
