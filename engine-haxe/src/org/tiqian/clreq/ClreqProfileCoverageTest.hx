package org.tiqian.clreq;

import org.tiqian.core.BuiltInLayoutProfiles;
import org.tiqian.core.LayoutProfileId;
import org.tiqian.clreq.ClreqProfileResolver.BuiltInClreqProfileResolver;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.ReadOnlyArray;
import std.StringBuf;

class ClreqProfileCoverageTest {
    @:test
    public static function testBopomofoModelsAndParser():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testBopomofoModelsAndParser");
        final tones:Array<BopomofoTone> = [
            BopomofoTone.Yinping,
            BopomofoTone.Yangping,
            BopomofoTone.Shang,
            BopomofoTone.Qu,
            BopomofoTone.Neutral,
            BopomofoTone.Ru
        ];
        var toneIndex:Int = 0;
        while (toneIndex < tones.length) {
            final tone = tones[toneIndex];
            TracedAssertions.assertNotNullRendered(tone != null, tone == null ? "-" : Std.string(tone));
            toneIndex += 1;
        }

        final reading = new BopomofoReading(["ㄅ", "ㄚ"], BopomofoTone.Yangping);
        TracedAssertions.assertEqualsStringArray(["ㄅ", "ㄚ"], reading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yangping, reading.tone);
        TracedAssertions.assertEqualsBopomofoReading(reading, reading.copy());
        TracedAssertions.assertTrue(reading.hashCode() == reading.copy().hashCode());
        TracedAssertions.assertTrue(reading.toString().indexOf("BopomofoReading") >= 0);

        // BopomofoParser
        final emptyReading = BopomofoParser.parse("");
        TracedAssertions.assertEqualsStringArray([], emptyReading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, emptyReading.tone);

        final neutralReading = BopomofoParser.parse("˙ㄇㄚ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], neutralReading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Neutral, neutralReading.tone);

        final yangpingReading = BopomofoParser.parse("ㄇㄚˊ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], yangpingReading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yangping, yangpingReading.tone);

        final shangReading = BopomofoParser.parse("ㄇㄚˇ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], shangReading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Shang, shangReading.tone);

        final quReading = BopomofoParser.parse("ㄇㄚˋ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], quReading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Qu, quReading.tone);

        final explicitYinping = BopomofoParser.parse("ㄇㄚˉ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], explicitYinping.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, explicitYinping.tone);

        final defaultYinping = BopomofoParser.parse("ㄇㄚ");
        TracedAssertions.assertEqualsStringArray(["ㄇ", "ㄚ"], defaultYinping.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, defaultYinping.tone);
    }

    @:test
    public static function testClreqProfileAndResolver():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testClreqProfileAndResolver");
        final strictnesses:Array<ClreqStrictness> = [ClreqStrictness.Loose, ClreqStrictness.Normal, ClreqStrictness.Strict];
        var strictnessIndex:Int = 0;
        while (strictnessIndex < strictnesses.length) {
            final strictness = strictnesses[strictnessIndex];
            TracedAssertions.assertNotNullRendered(strictness != null, strictness == null ? "-" : Std.string(strictness));
            strictnessIndex += 1;
        }
        final regions:Array<ClreqRegion> = [
            ClreqRegion.Mainland,
            ClreqRegion.Taiwan,
            ClreqRegion.HongKong,
            ClreqRegion.Custom
        ];
        var regionIndex:Int = 0;
        while (regionIndex < regions.length) {
            final region = regions[regionIndex];
            TracedAssertions.assertNotNullRendered(region != null, region == null ? "-" : Std.string(region));
            regionIndex += 1;
        }
        final glyphPolicies:Array<CjkPunctuationGlyphPolicy> = [
            CjkPunctuationGlyphPolicy.PreserveInput,
            CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
            CjkPunctuationGlyphPolicy.ForceClreqRecommendedCodepoints
        ];
        var policyIndex:Int = 0;
        while (policyIndex < glyphPolicies.length) {
            final policy = glyphPolicies[policyIndex];
            TracedAssertions.assertNotNullRendered(policy != null, policy == null ? "-" : Std.string(policy));
            policyIndex += 1;
        }
        final classes:Array<PunctuationClass> = [
            PunctuationClass.Opening,
            PunctuationClass.Closing,
            PunctuationClass.PauseOrStop,
            PunctuationClass.MiddleDot,
            PunctuationClass.Interpunct,
            PunctuationClass.Connector,
            PunctuationClass.Solidus,
            PunctuationClass.Ellipsis,
            PunctuationClass.Dash,
            PunctuationClass.Other
        ];
        var classIndex:Int = 0;
        while (classIndex < classes.length) {
            final cls = classes[classIndex];
            TracedAssertions.assertNotNullRendered(cls != null, cls == null ? "-" : Std.string(cls));
            classIndex += 1;
        }

        TracedAssertions.assertTrue(ClreqProfileCoverageTestHelpers.containsInt(ClreqProfile.DefaultCoalesceRepeatablePunctuation, 0x2014));
        TracedAssertions.assertEqualsString("clreq-mainland-horizontal", ClreqProfile.MainlandHorizontal.id);
        TracedAssertions.assertEqualsString("clreq-taiwan-horizontal", ClreqProfile.TaiwanHorizontal.id);
        TracedAssertions.assertEqualsString("clreq-hongkong-horizontal", ClreqProfile.HongKongHorizontal.id);

        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.MainlandSimplified,
            PunctuationGluePlacements.forRegion(ClreqRegion.Mainland));
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, PunctuationGluePlacements.forRegion(ClreqRegion.Taiwan));
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, PunctuationGluePlacements.forRegion(ClreqRegion.HongKong));
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.MainlandSimplified,
            PunctuationGluePlacements.forRegion(ClreqRegion.Custom));

        final resolver = new BuiltInClreqProfileResolver();
        final resolvedBuiltIn = resolver.resolve(BuiltInLayoutProfiles.ClreqHorizontal);
        TracedAssertions.assertEqualsClreqProfile(ClreqProfile.MainlandHorizontal, resolvedBuiltIn);

        final resolvedMainlandId = resolver.resolve(new LayoutProfileId("clreq-mainland-horizontal"));
        TracedAssertions.assertEqualsClreqProfile(ClreqProfile.MainlandHorizontal, resolvedMainlandId);

        final resolvedOtherId = resolver.resolve(new LayoutProfileId("other-profile"));
        TracedAssertions.assertEqualsClreqProfile(ClreqProfile.MainlandHorizontal, resolvedOtherId);
    }

    @:test
    public static function testClreqPunctuationPoliciesAndClassification():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testClreqPunctuationPoliciesAndClassification");
        final pointMarks:Array<String> = [",", ".", ":", ";", "!", "?"];
        var pointIndex:Int = 0;
        while (pointIndex < pointMarks.length) {
            TracedAssertions.assertTrue(ClreqPunctuationPolicies.isAsciiPointMark(pointMarks[pointIndex]));
            pointIndex += 1;
        }
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.isAsciiPointMark("a"));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.isAsciiPointMark("，"));

        // Test every branch in classify
        final openingChars:Array<String> = ["“", "‘", "（", "《", "〈", "「", "『", "【", "〔", "〖", "〘", "〚"];
        var index:Int = 0;
        while (index < openingChars.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Opening, ClreqPunctuationPolicies.classify(openingChars[index]));
            index += 1;
        }

        final closingChars:Array<String> = ["”", "’", "）", "》", "〉", "」", "』", "】", "〕", "〗", "〙", "〛"];
        index = 0;
        while (index < closingChars.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Closing, ClreqPunctuationPolicies.classify(closingChars[index]));
            index += 1;
        }

        final pauseOrStopChars:Array<String> = ["，", "、", "。", "；", "：", "！", "？"];
        index = 0;
        while (index < pauseOrStopChars.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.PauseOrStop, ClreqPunctuationPolicies.classify(pauseOrStopChars[index]));
            index += 1;
        }

        TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.MiddleDot, ClreqPunctuationPolicies.classify("·"));
        final interpuncts:Array<String> = ["・", "‧", "•"];
        index = 0;
        while (index < interpuncts.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Interpunct, ClreqPunctuationPolicies.classify(interpuncts[index]));
            index += 1;
        }
        final connectors:Array<String> = ["～", "~", "-", "–"];
        index = 0;
        while (index < connectors.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Connector, ClreqPunctuationPolicies.classify(connectors[index]));
            index += 1;
        }
        final solidi:Array<String> = ["/", "／"];
        index = 0;
        while (index < solidi.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Solidus, ClreqPunctuationPolicies.classify(solidi[index]));
            index += 1;
        }
        final ellipses:Array<String> = ["…", "⋯"];
        index = 0;
        while (index < ellipses.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Ellipsis, ClreqPunctuationPolicies.classify(ellipses[index]));
            index += 1;
        }
        final dashes:Array<String> = ["—", "⸺"];
        index = 0;
        while (index < dashes.length) {
            TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Dash, ClreqPunctuationPolicies.classify(dashes[index]));
            index += 1;
        }
        TracedAssertions.assertEqualsPunctuationClass(PunctuationClass.Other, ClreqPunctuationPolicies.classify("中"));
    }

    @:test
    public static function testForcedHalfWidthAndPolicyFor():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testForcedHalfWidthAndPolicyFor");
        // Hyphens are always forced half width
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("-", new PunctuationWidthPolicy(null, null)));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("–", new PunctuationWidthPolicy(null, null)));

        // gbFixedSeparators
        final gbPolicy = new PunctuationWidthPolicy(null, true);
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("～", gbPolicy));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("·", gbPolicy));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("•", gbPolicy));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("/", gbPolicy));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("，", gbPolicy));

        // Kaiming interior style
        final kaimingPolicy = new PunctuationWidthPolicy(InteriorPunctuationStyle.Kaiming, false);
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("（", kaimingPolicy)); // Opening
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("）", kaimingPolicy)); // Closing
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("，", kaimingPolicy)); // Pause not sentence end
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forcedHalfWidth("；", kaimingPolicy)); // Pause not sentence end
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("。", kaimingPolicy)); // Sentence end stop (full width)
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("！", kaimingPolicy)); // Sentence end stop
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("？", kaimingPolicy)); // Sentence end stop
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("．", kaimingPolicy)); // Sentence end stop
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forcedHalfWidth("中", kaimingPolicy)); // Other

        // policyFor
        final dash2Policy = ClreqPunctuationPolicies.policyFor("⸺");
        TracedAssertions.assertEqualsFloat(2.0, dash2Policy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(2.0, dash2Policy.defaultAdvanceEm);

        final hyphenPolicy = ClreqPunctuationPolicies.policyFor("-");
        TracedAssertions.assertEqualsFloat(0.5, hyphenPolicy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(0.5, hyphenPolicy.defaultAdvanceEm);

        final commaPolicy = ClreqPunctuationPolicies.policyFor("，");
        TracedAssertions.assertEqualsFloat(0.5, commaPolicy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(1.0, commaPolicy.defaultAdvanceEm);

        final openPolicy = ClreqPunctuationPolicies.policyFor("（");
        TracedAssertions.assertEqualsFloat(0.5, openPolicy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(1.0, openPolicy.defaultAdvanceEm);

        final closePolicy = ClreqPunctuationPolicies.policyFor("）");
        TracedAssertions.assertEqualsFloat(0.5, closePolicy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(1.0, closePolicy.defaultAdvanceEm);

        final hanPolicy = ClreqPunctuationPolicies.policyFor("字");
        TracedAssertions.assertEqualsFloat(1.0, hanPolicy.defaultBodyEm);
        TracedAssertions.assertEqualsFloat(1.0, hanPolicy.defaultAdvanceEm);
    }

    @:test
    public static function testForbiddenAtLineStartAndEnd():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testForbiddenAtLineStartAndEnd");
        // None level allows everywhere
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("，", KinsokuLevel.None));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("（", KinsokuLevel.None));

        // forbiddenAtLineStart
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("，", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("）", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("～", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("·", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("•", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("/", KinsokuLevel.Basic));

        // Dash & Ellipsis only forbidden at line start in Strict level
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("—", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("—", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("…", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineStart("…", KinsokuLevel.Strict));

        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("（", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineStart("字", KinsokuLevel.Strict));

        // forbiddenAtLineEnd
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineEnd("（", KinsokuLevel.Basic));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("/", KinsokuLevel.Basic));
        TracedAssertions.assertTrue(ClreqPunctuationPolicies.forbiddenAtLineEnd("/", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("）", KinsokuLevel.Strict));
        TracedAssertions.assertFalse(ClreqPunctuationPolicies.forbiddenAtLineEnd("字", KinsokuLevel.Strict));
    }

    @:test
    public static function testPunctuationAdvanceAndSubstitutor():Void {
        new TestTraceRecorder("ClreqProfileCoverageTest").section("testPunctuationAdvanceAndSubstitutor");
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationAdvancePolicy.advanceEm("⸺", "⸺"));
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationAdvancePolicy.advanceEm("—", "⸺"));
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationAdvancePolicy.advanceEm("⸺", "——"));
        TracedAssertions.assertEqualsFloat(3.0, ClreqPunctuationAdvancePolicy.advanceEm("abc", "abc"));

        // String with surrogate pair
        TracedAssertions.assertEqualsFloat(1.0, ClreqPunctuationAdvancePolicy.advanceEm("😀", "dummy"));
        // Lone surrogates and non-surrogate combinations. A lone surrogate
        // written inside a string literal is replaced with '?' when the JS
        // test bundle re-serializes its sources, so these inputs are built
        // from code units at runtime to keep each unit intact everywhere.
        TracedAssertions.assertEqualsFloat(1.0, ClreqPunctuationAdvancePolicy.advanceEm(ClreqProfileCoverageTestHelpers.surrogateText([0xD800]), "dummy"));
        TracedAssertions.assertEqualsFloat(2.0,
            ClreqPunctuationAdvancePolicy.advanceEm(ClreqProfileCoverageTestHelpers.surrogateText([0xD800, 0x41]), "dummy")); // low < 0xDC00
        TracedAssertions.assertEqualsFloat(2.0,
            ClreqPunctuationAdvancePolicy.advanceEm(ClreqProfileCoverageTestHelpers.surrogateText([0xD800, 0xE000]), "dummy")); // low > 0xDFFF

        // Substitutors
        final preserveSubstitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.PreserveInput);
        final preserveRes = preserveSubstitutor.substitute("……");
        TracedAssertions.assertEqualsString("……", preserveRes.displayText);
        TracedAssertions.assertTrue(preserveRes.reason.indexOf("preserve") >= 0);

        final preferSubstitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints);
        final preferRes = preferSubstitutor.substitute("——");
        TracedAssertions.assertEqualsString("——", preferRes.sourceText);

        final forceSubstitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.ForceClreqRecommendedCodepoints);
        final forceRes = forceSubstitutor.substitute("abc");
        TracedAssertions.assertEqualsString("abc", forceRes.displayText);
        TracedAssertions.assertTrue(forceRes.reason.indexOf("preserve") >= 0);
    }
}

class ClreqProfileCoverageTestHelpers {
    public static function surrogateText(codes:Array<Int>):String {
        final output = new StringBuf();
        var index:Int = 0;
        while (index < codes.length) {
            // Runtime code unit, not a literal: lone surrogates must survive
            // every re-serialization of the sources.
            output.add(String.fromCharCode(codes[index]));
            index += 1;
        }
        return output.toString();
    }

    public static function containsInt(values:ReadOnlyArray<Int>, value:Int):Bool {
        var index:Int = 0;
        while (index < values.length) {
            if (values[index] == value) {
                return true;
            }
            index += 1;
        }
        return false;
    }
}
