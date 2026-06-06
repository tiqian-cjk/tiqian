package org.tiqian.text.font

import org.tiqian.text.core.TextRange

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
    val reason: String,
)

interface FallbackResolver {
    fun resolve(text: String, range: TextRange, request: FontRequest): FontDecision
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
)

data class LayoutFontMetrics(
    val ascent: Float,
    val descent: Float,
    val baselineOffset: Float,
    val policy: FontMetricsPolicy,
    val baselinePolicy: BaselinePolicy,
)

enum class PunctuationFontPolicy {
    PreferCjkForAmbiguousPunctuation,
    PreferLatinForAscii,
    PreserveRunFont,
    CustomMap,
}

