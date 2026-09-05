package org.tiqian.clreq;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

/**
 * CLREQ section 6 kinsoku levels, one test per tightening step: None /
 * Basic (recommended) / GbStyle / Strict.
 */
class KinsokuLevelTest {
    @:test
    public static function noneForbidsNothing():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("noneForbidsNothing");
        final chars:Array<String> = ["。", "，", "、", "”", "）", "·", "／", "—", "…", "“", "（"];
        var index:Int = 0;
        while (index < chars.length) {
            final c = chars[index];
            TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start(c, KinsokuLevel.None), c + " start@None");
            TracedAssertions.assertFalse(KinsokuLevelTestHelpers.end(c, KinsokuLevel.None), c + " end@None");
            index += 1;
        }
    }

    @:test
    public static function basicForbidsPauseStopsClosingConnectorsAtStartAndOpeningAtEnd():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("basicForbidsPauseStopsClosingConnectorsAtStartAndOpeningAtEnd");
        // Pause marks, closing brackets, connectors, middle dots, and
        // separators are forbidden at line start.
        final startChars:Array<String> = ["。", "，", "、", "：", "；", "！", "？", "”", "）", "】", "·", "～", "／"];
        var index:Int = 0;
        while (index < startChars.length) {
            final c = startChars[index];
            TracedAssertions.assertTrue(KinsokuLevelTestHelpers.start(c, KinsokuLevel.Basic), c + " start@Basic");
            index += 1;
        }
        // Opening brackets are forbidden at line end.
        final endChars:Array<String> = ["“", "（", "《", "「", "【"];
        index = 0;
        while (index < endChars.length) {
            final c = endChars[index];
            TracedAssertions.assertTrue(KinsokuLevelTestHelpers.end(c, KinsokuLevel.Basic), c + " end@Basic");
            index += 1;
        }
        // Dashes and ellipses may open a line under Basic; separators may
        // close a line.
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start("—", KinsokuLevel.Basic));
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start("…", KinsokuLevel.Basic));
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.end("／", KinsokuLevel.Basic));
    }

    @:test
    public static function gbStyleAddsSeparatorAtLineEnd():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("gbStyleAddsSeparatorAtLineEnd");
        // GbStyle = Basic + separators also forbidden at line end.
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.end("／", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.end("／", KinsokuLevel.GbStyle));
        // Dashes and ellipses may still open a line under GbStyle.
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start("—", KinsokuLevel.GbStyle));
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start("…", KinsokuLevel.GbStyle));
    }

    @:test
    public static function strictAddsDashAndEllipsisAtLineStart():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("strictAddsDashAndEllipsisAtLineStart");
        // Strict = GbStyle + dashes and ellipses forbidden at line start.
        TracedAssertions.assertFalse(KinsokuLevelTestHelpers.start("—", KinsokuLevel.GbStyle));
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.start("—", KinsokuLevel.Strict));
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.start("…", KinsokuLevel.Strict));
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.start("⋯", KinsokuLevel.Strict));
        // The GbStyle separator rule at line end stays.
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.end("／", KinsokuLevel.Strict));
    }

    @:test
    public static function profileDefaultsToMeasureAdaptive():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("profileDefaultsToMeasureAdaptive");
        TracedAssertions.assertTrue(KinsokuLevelTestHelpers.isMeasureAdaptive(ClreqProfile.MainlandHorizontal.kinsokuMode));
    }

    @:test
    public static function cjkBracketVariantsClassifyAsOpeningAndClosing():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("cjkBracketVariantsClassifyAsOpeningAndClosing");
        final opening:Array<String> = ["【", "〔", "〖", "〘", "〚"];
        var index:Int = 0;
        while (index < opening.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Opening, ClreqPunctuationPolicies.classify(opening[index]), opening[index]);
            index += 1;
        }
        final closing:Array<String> = ["】", "〕", "〗", "〙", "〛"];
        index = 0;
        while (index < closing.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Closing, ClreqPunctuationPolicies.classify(closing[index]), closing[index]);
            index += 1;
        }
    }

    @:test
    public static function exposesUnambiguousAsciiPointMarksWithoutGuessingQuotesOrConnectors():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("exposesUnambiguousAsciiPointMarksWithoutGuessingQuotesOrConnectors");
        final included:Array<String> = [",", ".", ":", ";", "!", "?"];
        var index:Int = 0;
        while (index < included.length) {
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.isAsciiPointMark(included[index]), included[index] + " point mark");
            index += 1;
        }
        final excluded:Array<String> = ["\"", "'", "-", "/", "~", "%"];
        index = 0;
        while (index < excluded.length) {
            TracedAssertions.assertFalse(ClreqPunctuationPolicies.isAsciiPointMark(excluded[index]), excluded[index] + " excluded");
            index += 1;
        }
    }

    @:test
    public static function measureAdaptiveResolvesPerLineWidth():Void {
        new TestTraceRecorder("KinsokuLevelTest").section("measureAdaptiveResolvesPerLineWidth");
        final m = KinsokuMode.MeasureAdaptive(14.0, 24.0, 32.0);
        // Below 14 em: Basic + hanging.
        final narrow = KinsokuModes.resolve(m, 10.0);
        TracedAssertions.assertEqualsKinsokuLevel(KinsokuLevel.Basic, narrow.level);
        TracedAssertions.assertEqualsHangingPunctuationStyle(HangingPunctuationStyle.PauseStops, narrow.hanging);
        // 14-24 em: Basic, no hanging.
        final medium = KinsokuModes.resolve(m, 20.0);
        TracedAssertions.assertEqualsKinsokuLevel(KinsokuLevel.Basic, medium.level);
        TracedAssertions.assertEqualsHangingPunctuationStyle(HangingPunctuationStyle.Disabled, medium.hanging);
        // Above 24 em: GbStyle.
        TracedAssertions.assertEqualsKinsokuLevel(KinsokuLevel.GbStyle, KinsokuModes.resolve(m, 28.0).level);
        // Above 32 em: Strict.
        TracedAssertions.assertEqualsKinsokuLevel(KinsokuLevel.Strict, KinsokuModes.resolve(m, 40.0).level);
    }
}

class KinsokuLevelTestHelpers {
    public static function start(char:String, level:KinsokuLevel):Bool {
        return ClreqPunctuationPolicies.forbiddenAtLineStart(char, level);
    }

    public static function end(char:String, level:KinsokuLevel):Bool {
        return ClreqPunctuationPolicies.forbiddenAtLineEnd(char, level);
    }

    public static function isMeasureAdaptive(mode:KinsokuMode):Bool {
        return switch (mode) {
            case KinsokuMode.MeasureAdaptive(_, _, _):
                true;
            case KinsokuMode.Fixed(_, _):
                false;
        };
    }
}
