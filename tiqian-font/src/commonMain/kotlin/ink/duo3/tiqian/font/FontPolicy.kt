package ink.duo3.tiqian.font

import ink.duo3.tiqian.core.TextRange
import kotlin.text.CharCategory

data class FontRequest(
    val preferredFamilies: List<String>,
    val locale: String,
    val role: FontRole,
)

enum class FontRole {
    CjkText,
    CjkPunctuation,
    LatinText,
    Symbol,
    Emoji,
    Unknown,
}

data class FontCandidate(
    val key: String,
    val family: String,
    val role: FontRole,
)

data class FontDecision(
    val range: TextRange,
    val candidate: FontCandidate,
    val role: FontRole,
    val reason: String,
)

interface FallbackResolver {
    fun resolve(text: String, range: TextRange, request: FontRequest): FontDecision
}

data class FontRoleContext(
    val locale: String = "zh-Hans",
    val regionHint: String? = null,
)

interface FontRoleClassifier {
    fun classify(
        text: String,
        range: TextRange,
        context: FontRoleContext = FontRoleContext(),
    ): FontRole
}

class CjkFontRoleClassifier : FontRoleClassifier {
    override fun classify(text: String, range: TextRange, context: FontRoleContext): FontRole {
        val firstCodePoint = text.codePointAtCompat(range.start)
        return when {
            firstCodePoint.isCjkCodePoint() -> FontRole.CjkText
            firstCodePoint.isLatinTechnicalPunctuation(text, range) -> FontRole.LatinText
            firstCodePoint.isLatinCurlyQuote(text, range) -> FontRole.LatinText
            firstCodePoint.isCjkPunctuationCodePoint() -> FontRole.CjkPunctuation
            firstCodePoint.isLatinCodePoint() -> FontRole.LatinText
            firstCodePoint.isAsciiLatinPunctuation() -> FontRole.LatinText
            firstCodePoint.isEmojiCodePoint() -> FontRole.Emoji
            firstCodePoint.isSymbolCodePoint() -> FontRole.Symbol
            else -> FontRole.Unknown
        }
    }

    private fun Int.isCjkCodePoint(): Boolean =
        this in 0x3105..0x312F || // Bopomofo ㄅㄆㄇ (full-width CJK letters; body text, not just ruby)
            this in 0x31A0..0x31BF || // Bopomofo Extended
            this in 0x3400..0x4DBF ||
            this in 0x4E00..0x9FFF ||
            this in 0xF900..0xFAFF ||
            this in 0x20000..0x2A6DF ||
            this in 0x2A700..0x2B73F ||
            this in 0x2B740..0x2B81F ||
            this in 0x2B820..0x2CEAF ||
            this in 0x30000..0x3134F

    private fun Int.isCjkPunctuationCodePoint(): Boolean =
        this in 0x3000..0x303F ||
            this == 0x2014 ||
            isAmbiguousCurlyQuote() ||
            this == 0x2013 ||
            this == 0x203C ||
            this == 0x2047 ||
            this == 0x2026 ||
            this == 0x2027 ||
            this == 0x22EF ||
            this == 0x30FB ||
            this == 0x2E3A ||
            this == 0x00B7 ||
            this == 0x002D ||
            this == 0x002F ||
            this == 0x007E ||
            this == 0x2022 ||
            this == 0xFF01 ||
            this == 0xFF1F ||
            this == 0xFF0C ||
            this == 0xFF0E ||
            this == 0xFF0F ||
            this == 0xFF1A ||
            this == 0xFF1B ||
            this == 0xFF08 ||
            this == 0xFF09 ||
            this == 0xFF5E

    private fun Int.isLatinTechnicalPunctuation(text: String, range: TextRange): Boolean =
        isAmbiguousAsciiPunctuation() &&
            (
                text.previousCodePointBefore(range.start)?.isLatinTechnicalRunCodePoint() == true ||
                    text.nextCodePointAfter(range.end)?.isLatinTechnicalRunCodePoint() == true
                )

    private fun Int.isLatinCurlyQuote(text: String, range: TextRange): Boolean =
        isAmbiguousCurlyQuote() &&
            text.previousCodePointBefore(range.start)?.isLatinRunCodePoint() == true &&
            text.nextCodePointAfter(range.end)?.isLatinRunCodePoint() == true

    private fun Int.isAmbiguousCurlyQuote(): Boolean =
        this == 0x2018 || this == 0x2019 || this == 0x201C || this == 0x201D

    private fun Int.isAmbiguousAsciiPunctuation(): Boolean =
        this == 0x002D || this == 0x002F || this == 0x007E

    private fun Int.isLatinRunCodePoint(): Boolean =
        isLatinCodePoint() || isAmbiguousAsciiPunctuation() || isAmbiguousCurlyQuote() || this == 0x0020

    private fun Int.isLatinTechnicalRunCodePoint(): Boolean =
        isLatinCodePoint() || isAmbiguousAsciiPunctuation() || this == 0x002E || this == 0x003A || this == 0x005F

    private fun Int.isLatinCodePoint(): Boolean =
        this in 0x0041..0x005A ||
            this in 0x0061..0x007A ||
            this in 0x0030..0x0039 ||
            this in 0x00C0..0x024F

    /**
     * ASCII punctuation that does NOT share a code point with CJK fullwidth
     * forms. These are always Latin by typed intent — if the author wanted
     * fullwidth they would have typed U+FF08 / U+FF09 / etc. Listed here so
     * they classify as [FontRole.LatinText] (and aggregate with adjacent
     * Latin runs) instead of falling through to [FontRole.Unknown] and
     * landing on the symbol fallback font.
     *
     * U+0020 SPACE is also included: per ADR 0009 it joins the Latin run for
     * cluster aggregation and its advance is later adjusted by
     * `ClreqProfile.autoSpace` when it sits at a CJK ↔ Latin boundary
     * (typed-space-as-autospace).
     *
     * Pair-aware analyzers ([QuotePairAnalyzer]) are reserved for genuinely
     * shared code points (U+2018–201D curly quotes), not for these.
     */
    private fun Int.isAsciiLatinPunctuation(): Boolean =
        this == 0x0020 || // SPACE
            this == 0x0028 || // (
            this == 0x0029 || // )
            this == 0x005B || // [
            this == 0x005D || // ]
            this == 0x007B || // {
            this == 0x007D // }

    private fun Int.isEmojiCodePoint(): Boolean =
        this in 0x1F300..0x1FAFF

    private fun Int.isSymbolCodePoint(): Boolean =
        this.toCharOrNull()?.category.let { category ->
            category == CharCategory.MATH_SYMBOL ||
                category == CharCategory.CURRENCY_SYMBOL ||
                category == CharCategory.MODIFIER_SYMBOL ||
                category == CharCategory.OTHER_SYMBOL
        }

    private fun String.codePointAtCompat(index: Int): Int {
        val high = this[index].code
        if (high !in 0xD800..0xDBFF || index + 1 >= length) return high

        val low = this[index + 1].code
        if (low !in 0xDC00..0xDFFF) return high

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun Int.toCharOrNull(): Char? =
        if (this in 0..0xFFFF) this.toChar() else null

    private fun String.previousCodePointBefore(index: Int): Int? {
        if (index <= 0) return null
        val low = this[index - 1].code
        if (low !in 0xDC00..0xDFFF || index - 2 < 0) return low

        val high = this[index - 2].code
        if (high !in 0xD800..0xDBFF) return low

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun String.nextCodePointAfter(index: Int): Int? =
        if (index >= length) null else codePointAtCompat(index)
}

class PreferCjkForAmbiguousPunctuationResolver(
    private val cjkFontKey: String = "cjk-primary",
    private val latinFontKey: String = "latin-primary",
    private val symbolFontKey: String = "symbol-fallback",
) : FallbackResolver {
    override fun resolve(text: String, range: TextRange, request: FontRequest): FontDecision {
        val role = request.role
        val candidate = when (role) {
            FontRole.CjkText,
            FontRole.CjkPunctuation,
            -> FontCandidate(cjkFontKey, request.preferredFamilies.firstOrNull() ?: cjkFontKey, role)

            FontRole.LatinText -> FontCandidate(latinFontKey, latinFontKey, role)
            FontRole.Symbol,
            FontRole.Emoji,
            FontRole.Unknown,
            -> FontCandidate(symbolFontKey, symbolFontKey, role)
        }

        return FontDecision(
            range = range,
            candidate = candidate,
            role = role,
            reason = "PreferCjkForAmbiguousPunctuationResolver:$role",
        )
    }
}

enum class FontMetricsPolicy {
    Raw,
    IdeographicBox,
    GlyphBoundsSampled,
    ManualOverride,
}

enum class BaselinePolicy {
    Alphabetic,
    Ideographic,
    CenteredCjkVisual,
}

data class RawFontMetrics(
    val ascent: Float,
    val descent: Float,
    val leading: Float = 0f,
    val source: FontMetricSource = FontMetricSource.RawTables,
    /**
     * Font-declared typographic box (OpenType `OS/2` sTypoAscender/Descender),
     * as positive magnitudes above/below the baseline. For CJK fonts this is
     * the clean ideographic em (e.g. Source Han 0.88 / 0.12 = 1.000em), unlike
     * the inflated hhea-derived [ascent]/[descent]. `null` when the font has no
     * `OS/2` table → the normalizer falls back to [ascent]/[descent].
     * See ADR 0002 amendment.
     */
    val typoAscent: Float? = null,
    val typoDescent: Float? = null,
)

data class LayoutFontMetrics(
    val ascent: Float,
    val descent: Float,
    val baselineOffset: Float,
    val policy: FontMetricsPolicy,
    val baselinePolicy: BaselinePolicy,
    val baselineClass: BaselineClass = BaselineClass.Roman,
    val metricBox: MetricBox = MetricBox.RawFontBox,
    val source: FontMetricSource = FontMetricSource.RawTables,
    val reason: String = "",
)

enum class PunctuationFontPolicy {
    PreferCjkForAmbiguousPunctuation,
    PreferLatinForAscii,
    PreserveRunFont,
    CustomMap,
}
