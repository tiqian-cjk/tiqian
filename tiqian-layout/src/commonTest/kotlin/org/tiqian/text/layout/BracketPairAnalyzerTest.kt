package org.tiqian.text.layout

import org.tiqian.text.font.CjkFontRoleClassifier
import org.tiqian.text.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BracketPairAnalyzerTest {
    private val analyzer = BracketPairAnalyzer()
    private val classifier = CjkFontRoleClassifier()

    // -- Pair matching --

    @Test
    fun matchesAsciiParenthesisPair() {
        val pairs = analyzer.analyze("a(b)c")
        assertEquals(1, pairs.size)
        assertEquals(BracketPair(1, 3, BracketKind.Parenthesis), pairs[0])
    }

    @Test
    fun matchesNestedDifferentKinds() {
        // a([b])c → outer (1,4) Parenthesis, inner [2,3] Square
        val pairs = analyzer.analyze("a([b])c")
        assertEquals(2, pairs.size)
        assertTrue(pairs.any { it == BracketPair(2, 4, BracketKind.Square) })
        assertTrue(pairs.any { it == BracketPair(1, 5, BracketKind.Parenthesis) })
    }

    @Test
    fun matchesSquareAndCurly() {
        val pairs = analyzer.analyze("[x]{y}")
        assertEquals(2, pairs.size)
        assertEquals(BracketPair(0, 2, BracketKind.Square), pairs[0])
        assertEquals(BracketPair(3, 5, BracketKind.Curly), pairs[1])
    }

    @Test
    fun unmatchedBracketsProduceNoPairs() {
        assertEquals(0, analyzer.analyze("a(b").size)
        assertEquals(0, analyzer.analyze("b)").size)
    }

    @Test
    fun mismatchedKindsAreSkipped() {
        // a(b] — close ] has no open square, so dropped. Open ( never closes.
        assertEquals(0, analyzer.analyze("a(b]").size)
    }

    // -- Pair classification --

    @Test
    fun classifiesPairAsCjkWhenOuterContextIsCjk() {
        // 中文(English)中文
        val text = "中文(English)中文"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[2])
        assertEquals(FontRole.CjkPunctuation, roles[10])
    }

    @Test
    fun classifiesPairAsLatinWhenOuterContextIsLatin() {
        val text = "he said (hello) world"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[8])
        assertEquals(FontRole.LatinText, roles[14])
    }

    @Test
    fun classifiesTextStartPairFromInnerContent() {
        // (Hello) world → no left context, inner is Latin → LatinText.
        val text = "(Hello) world"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[0])
        assertEquals(FontRole.LatinText, roles[6])
    }

    @Test
    fun classifiesTextStartCjkInnerAsCjkPunctuation() {
        // (中文)Latin → no left context, inner is CJK → CjkPunctuation.
        val text = "(中文)Latin"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[0])
        assertEquals(FontRole.CjkPunctuation, roles[3])
    }

    @Test
    fun classifiesTextBoundaryPairAsLatinByDefault() {
        // ()  → no context anywhere; ASCII brackets default to LatinText.
        val text = "()"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[0])
        assertEquals(FontRole.LatinText, roles[1])
    }

    @Test
    fun skipsNeutralPunctuationWhenResolvingContext() {
        // English: (hello) — colon and space neutral, scan back finds 'h'.
        val text = "English: (hello)"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[9])
        assertEquals(FontRole.LatinText, roles[15])
    }

    @Test
    fun mixedOuterPicksLeftContext() {
        // 中文(English) — left is CJK, so both brackets become CJK.
        val text = "中文(English)"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[2])
        assertEquals(FontRole.CjkPunctuation, roles[10])
    }
}
