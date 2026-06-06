package org.tiqian.text.clreq

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
}
