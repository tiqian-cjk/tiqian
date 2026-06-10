package ink.duo3.tiqian.font

import ink.duo3.tiqian.core.TextRange
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

    @Test
    fun keepsAsciiPunctuationInsideLatinTechnicalRuns() {
        assertEquals(FontRole.LatinText, classifier.classify("well-known", TextRange(4, 5)))
        assertEquals(FontRole.LatinText, classifier.classify("https://example", TextRange(6, 7)))
        assertEquals(FontRole.LatinText, classifier.classify("https://example", TextRange(7, 8)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4E2D\u6587/\u4E2D\u6587", TextRange(2, 3)))
    }

    @Test
    fun classifiesCurlyQuotesAsCjkWhenSurroundedByCjk() {
        // U+201C/201D between CJK text -> CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u201C\u4F60\u597D\u201D", TextRange(2, 3)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u201C\u4F60\u597D\u201D", TextRange(5, 6)))
        // U+2018/2019 between CJK text -> CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u2018\u4F60\u597D\u2019", TextRange(2, 3)))
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u2018\u4F60\u597D\u2019", TextRange(5, 6)))
    }

    @Test
    fun classifiesCurlyQuotesAsLatinWhenSurroundedByLatin() {
        // said "hello" -> quotes between Latin chars are LatinText
        assertEquals(FontRole.LatinText, classifier.classify("said \u201Chello\u201D end", TextRange(5, 6)))
        assertEquals(FontRole.LatinText, classifier.classify("said \u201Chello\u201D end", TextRange(11, 12)))
        // it's -> apostrophe between Latin chars is LatinText
        assertEquals(FontRole.LatinText, classifier.classify("it\u2019s", TextRange(2, 3)))
    }

    @Test
    fun classifiesCurlyQuotesAsCjkInMixedContext() {
        // CJK"Latin" -> opening quote has CJK on left, so CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u201Chello\u201D", TextRange(2, 3)))
        // CJK"Latin" -> closing quote has Latin on left but nothing/end on right, so CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u4ED6\u8BF4\u201Chello\u201D", TextRange(8, 9)))
    }

    @Test
    fun classifiesAsciiBracketsAsLatin() {
        // ASCII parens/brackets do not share a code point with CJK fullwidth
        // forms, so they are classified as Latin regardless of context. (For
        // context-aware classification of genuinely shared code points see
        // U+201C/201D curly quotes above.)
        assertEquals(FontRole.LatinText, classifier.classify("(", TextRange(0, 1)))
        assertEquals(FontRole.LatinText, classifier.classify(")", TextRange(0, 1)))
        assertEquals(FontRole.LatinText, classifier.classify("[", TextRange(0, 1)))
        assertEquals(FontRole.LatinText, classifier.classify("]", TextRange(0, 1)))
        assertEquals(FontRole.LatinText, classifier.classify("{", TextRange(0, 1)))
        assertEquals(FontRole.LatinText, classifier.classify("}", TextRange(0, 1)))
        // Inside CJK content the role does not change — code point alone
        // determines classification for these characters.
        assertEquals(FontRole.LatinText, classifier.classify("中(文", TextRange(1, 2)))
    }

    @Test
    fun classifiesCurlyQuotesAsCjkAtTextBoundary() {
        // Quote at start of text -> no left neighbor -> CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u201C\u4F60\u597D\u201D", TextRange(0, 1)))
        // Quote at end of text -> no right neighbor -> CjkPunctuation
        assertEquals(FontRole.CjkPunctuation, classifier.classify("\u201C\u4F60\u597D\u201D", TextRange(3, 4)))
    }
}
