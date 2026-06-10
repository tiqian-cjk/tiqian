package ink.duo3.tiqian.clreq

import kotlin.test.Test
import kotlin.test.assertEquals

class ClreqPunctuationGlyphSubstitutorTest {
    @Test
    fun preferPolicyUsesClreqRecommendedDisplayCodepoints() {
        val substitutor = ClreqPunctuationGlyphSubstitutor(
            policy = CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
        )

        assertEquals("⋯⋯", substitutor.substitute("……").displayText)
        assertEquals("⸺", substitutor.substitute("——").displayText)
        assertEquals("·", substitutor.substitute("・").displayText)
        assertEquals("·", substitutor.substitute("‧").displayText)
        assertEquals("·", substitutor.substitute("•").displayText)
    }

    @Test
    fun preservePolicyKeepsInputDisplayCodepoints() {
        val substitutor = ClreqPunctuationGlyphSubstitutor(
            policy = CjkPunctuationGlyphPolicy.PreserveInput,
        )

        assertEquals("……", substitutor.substitute("……").displayText)
        assertEquals("——", substitutor.substitute("——").displayText)
        assertEquals("・", substitutor.substitute("・").displayText)
    }

    @Test
    fun preferPolicyDoesNotRewriteAmbiguousConnectorOrSolidusForms() {
        val substitutor = ClreqPunctuationGlyphSubstitutor(
            policy = CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
        )

        assertEquals("～", substitutor.substitute("～").displayText)
        assertEquals("-", substitutor.substitute("-").displayText)
        assertEquals("/", substitutor.substitute("/").displayText)
        assertEquals("／", substitutor.substitute("／").displayText)
        assertEquals("．", substitutor.substitute("．").displayText)
    }

    @Test
    fun recommendedDashCodepointOccupiesTwoEm() {
        assertEquals(2.0f, ClreqPunctuationPolicies.policyFor('⸺').defaultBodyEm)
        assertEquals(2.0f, ClreqPunctuationPolicies.policyFor('⸺').defaultAdvanceEm)
        assertEquals(2.0f, ClreqPunctuationAdvancePolicy.advanceEm(sourceText = "⸺", displayText = "⸺"))
        assertEquals(2.0f, ClreqPunctuationAdvancePolicy.advanceEm(sourceText = "——", displayText = "⸺"))
    }
}
