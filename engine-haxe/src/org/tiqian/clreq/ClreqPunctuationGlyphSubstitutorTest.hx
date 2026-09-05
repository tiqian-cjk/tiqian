package org.tiqian.clreq;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ClreqPunctuationGlyphSubstitutorTest {
    @:test
    public static function preferPolicyUsesClreqRecommendedDisplayCodepoints():Void {
        new TestTraceRecorder("ClreqPunctuationGlyphSubstitutorTest").section("preferPolicyUsesClreqRecommendedDisplayCodepoints");
        final substitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints);

        TracedAssertions.assertEqualsString("⋯⋯", substitutor.substitute("……").displayText);
        TracedAssertions.assertEqualsString("⸺", substitutor.substitute("——").displayText);
        TracedAssertions.assertEqualsString("·", substitutor.substitute("・").displayText);
        TracedAssertions.assertEqualsString("·", substitutor.substitute("‧").displayText);
        TracedAssertions.assertEqualsString("·", substitutor.substitute("•").displayText);
    }

    @:test
    public static function preservePolicyKeepsInputDisplayCodepoints():Void {
        new TestTraceRecorder("ClreqPunctuationGlyphSubstitutorTest").section("preservePolicyKeepsInputDisplayCodepoints");
        final substitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.PreserveInput);

        TracedAssertions.assertEqualsString("……", substitutor.substitute("……").displayText);
        TracedAssertions.assertEqualsString("——", substitutor.substitute("——").displayText);
        TracedAssertions.assertEqualsString("・", substitutor.substitute("・").displayText);
    }

    @:test
    public static function preferPolicyDoesNotRewriteAmbiguousConnectorOrSolidusForms():Void {
        new TestTraceRecorder("ClreqPunctuationGlyphSubstitutorTest").section("preferPolicyDoesNotRewriteAmbiguousConnectorOrSolidusForms");
        final substitutor = new ClreqPunctuationGlyphSubstitutor(CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints);

        TracedAssertions.assertEqualsString("～", substitutor.substitute("～").displayText);
        TracedAssertions.assertEqualsString("-", substitutor.substitute("-").displayText);
        TracedAssertions.assertEqualsString("/", substitutor.substitute("/").displayText);
        TracedAssertions.assertEqualsString("／", substitutor.substitute("／").displayText);
        TracedAssertions.assertEqualsString("．", substitutor.substitute("．").displayText);
    }

    @:test
    public static function recommendedDashCodepointOccupiesTwoEm():Void {
        new TestTraceRecorder("ClreqPunctuationGlyphSubstitutorTest").section("recommendedDashCodepointOccupiesTwoEm");
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationPolicies.policyFor("⸺").defaultBodyEm);
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationPolicies.policyFor("⸺").defaultAdvanceEm);
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationAdvancePolicy.advanceEm("⸺", "⸺"));
        TracedAssertions.assertEqualsFloat(2.0, ClreqPunctuationAdvancePolicy.advanceEm("——", "⸺"));
    }
}
