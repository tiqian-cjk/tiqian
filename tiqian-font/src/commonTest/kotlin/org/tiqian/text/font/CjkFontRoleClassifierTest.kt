package org.tiqian.text.font

import org.tiqian.text.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals

class CjkFontRoleClassifierTest {
    private val classifier = CjkFontRoleClassifier()

    @Test
    fun classifiesCjkText() {
        assertEquals(FontRole.CjkText, classifier.classify("提", TextRange(0, 1)))
    }

    @Test
    fun classifiesCjkPunctuation() {
        assertEquals(FontRole.CjkPunctuation, classifier.classify("……", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("⋯⋯", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("——", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("⸺", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("。", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("・", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("‧", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("～", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("-", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("/", TextRange(0, 1)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("／", TextRange(0, 1)))
    }

    @Test
    fun classifiesLatinText() {
        assertEquals(FontRole.LatinText, classifier.classify("English", TextRange(0, 1)))
    }
}
