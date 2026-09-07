package org.tiqian.clreq;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

/**
 * Coverage for the ClreqProfile kinsoku policy arms, the ClreqKinsokuRule
 * empty-display guard, and every BopomofoParser tone arm.
 */
class ClreqPolicyTailCoverageTest {
    @:test
    public static function forbiddenAtLineStartCoversEveryPunctuationClass():Void {
        new TestTraceRecorder("ClreqPolicyTailCoverageTest").section("forbiddenAtLineStartCoversEveryPunctuationClass");
        // PauseOrStop / Closing / MiddleDot / Interpunct / Connector / Solidus
        // are forbidden at line start at every processed level.
        final levels:Array<KinsokuLevel> = [KinsokuLevel.Basic, KinsokuLevel.GbStyle, KinsokuLevel.Strict];
        var index:Int = 0;
        while (index < levels.length) {
            final level = levels[index];
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("，", level), "comma at " + level);
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("”", level), "closing quote at " + level);
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("·", level), "middle dot at " + level);
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("・", level), "interpunct at " + level);
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("～", level), "connector at " + level);
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("/", level), "solidus at " + level);
            index += 1;
        }
        // Dash and ellipsis are only forbidden under strict processing.
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("—", KinsokuLevel.Basic));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("—", KinsokuLevel.GbStyle));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("—", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("…", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("…", KinsokuLevel.Strict));
        // Other (plain CJK ideograph) is never forbidden at line start.
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("文", KinsokuLevel.Strict));
        // None short-circuits before classification.
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("，", KinsokuLevel.None));
    }

    @:test
    public static function forbiddenAtLineEndCoversOpeningSolidusAndOther():Void {
        new TestTraceRecorder("ClreqPolicyTailCoverageTest").section("forbiddenAtLineEndCoversOpeningSolidusAndOther");
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineEnd("“", KinsokuLevel.Basic));
        // Solidus is only forbidden at line end beyond the basic level.
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("/", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineEnd("/", KinsokuLevel.GbStyle));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineEnd("/", KinsokuLevel.Strict));
        // PauseOrStop falls through to the else arm at line end.
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("，", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("“", KinsokuLevel.None));
    }

    @:test
    public static function kinsokuRuleAllowsClustersWithoutDisplayText():Void {
        new TestTraceRecorder("ClreqPolicyTailCoverageTest").section("kinsokuRuleAllowsClustersWithoutDisplayText");
        final empty = new Cluster(new TextRange(0, 0), "", "stub", 0.0, "");
        final rule = new ClreqKinsokuRule();
        TracedAssertions.assertFalse(rule.forbiddenAtLineStart(empty));
        TracedAssertions.assertFalse(rule.forbiddenAtLineEnd(empty));
    }

    @:test
    public static function bopomofoParserCoversEveryToneArm():Void {
        new TestTraceRecorder("ClreqPolicyTailCoverageTest").section("bopomofoParserCoversEveryToneArm");
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, BopomofoParser.parse("ㄅㄚ").tone);
        TracedAssertions.assertEqualsStringArray(["ㄅ", "ㄚ"], BopomofoParser.parse("ㄅㄚ").symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yangping, BopomofoParser.parse("ㄅㄚˊ").tone);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Shang, BopomofoParser.parse("ㄅㄚˇ").tone);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Qu, BopomofoParser.parse("ㄅㄚˋ").tone);
        TracedAssertions.assertEqualsStringArray(["ㄅ", "ㄚ"], BopomofoParser.parse("ㄅㄚˋ").symbols);
        // Explicit macron keeps plain Yinping.
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, BopomofoParser.parse("ㄅㄚˉ").tone);
        // Prefixed neutral dot strips into the tone.
        final neutral = BopomofoParser.parse("˙ㄅㄚ");
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Neutral, neutral.tone);
        TracedAssertions.assertEqualsStringArray(["ㄅ", "ㄚ"], neutral.symbols);
        // Empty reading keeps the default tone with no symbols.
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, BopomofoParser.parse("").tone);
        // U+02C8 sits between the Shang and Yangping cases of the Kotlin
        // tone-mark tableswitch without being a tone mark: it lands on the
        // plain Yinping arm through the in-range default entry.
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, BopomofoParser.parse("ㄅㄚˈ").tone);
        // The vertical line is not a tone mark, so it stays inside the body
        // and appears as a third symbol.
        TracedAssertions.assertEqualsStringArray(["ㄅ", "ㄚ", "ˈ"], BopomofoParser.parse("ㄅㄚˈ").symbols);
        // U+02CC is outside the switch range entirely: range-miss default.
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, BopomofoParser.parse("ㄅㄚˌ").tone);
    }
}
