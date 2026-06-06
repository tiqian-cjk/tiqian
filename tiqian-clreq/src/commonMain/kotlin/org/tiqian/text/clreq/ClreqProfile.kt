package org.tiqian.text.clreq

enum class ClreqStrictness {
    Loose,
    Normal,
    Strict,
}

data class ClreqProfile(
    val id: String,
    val strictness: ClreqStrictness,
    val region: ClreqRegion,
    val punctuationGlyphPolicy: CjkPunctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
) {
    companion object {
        val MainlandHorizontal = ClreqProfile(
            id = "clreq-mainland-horizontal",
            strictness = ClreqStrictness.Normal,
            region = ClreqRegion.Mainland,
        )
    }
}

enum class ClreqRegion {
    Mainland,
    Taiwan,
    HongKong,
    Custom,
}

enum class CjkPunctuationGlyphPolicy {
    PreserveInput,
    PreferClreqRecommendedCodepoints,
    ForceClreqRecommendedCodepoints,
}

enum class PunctuationClass {
    Opening,
    Closing,
    PauseOrStop,
    MiddleDot,
    Interpunct,
    Connector,
    Solidus,
    Ellipsis,
    Dash,
    Quote,
    Other,
}

data class PunctuationPolicy(
    val punctuationClass: PunctuationClass,
    val allowAtLineStart: Boolean,
    val allowAtLineEnd: Boolean,
    val defaultBodyEm: Float,
)

object ClreqPunctuationPolicies {
    fun classify(char: Char): PunctuationClass =
        when (char) {
            '“', '‘', '（', '《', '〈', '「', '『' -> PunctuationClass.Opening
            '”', '’', '）', '》', '〉', '」', '』' -> PunctuationClass.Closing
            '，', '、', '。', '；', '：', '！', '？' -> PunctuationClass.PauseOrStop
            '·' -> PunctuationClass.MiddleDot
            '・', '‧', '•' -> PunctuationClass.Interpunct
            '～', '~', '-', '–' -> PunctuationClass.Connector
            '/', '／' -> PunctuationClass.Solidus
            '…', '⋯' -> PunctuationClass.Ellipsis
            '—', '⸺' -> PunctuationClass.Dash
            else -> PunctuationClass.Other
        }

    fun policyFor(char: Char): PunctuationPolicy {
        val punctuationClass = classify(char)
        return PunctuationPolicy(
            punctuationClass = punctuationClass,
            allowAtLineStart = punctuationClass == PunctuationClass.Opening || punctuationClass == PunctuationClass.Other,
            allowAtLineEnd = punctuationClass != PunctuationClass.Opening,
            defaultBodyEm = when (punctuationClass) {
                PunctuationClass.PauseOrStop,
                PunctuationClass.Closing,
                PunctuationClass.Opening,
                -> 0.5f

                PunctuationClass.Ellipsis,
                PunctuationClass.Dash,
                -> 1.0f

                PunctuationClass.MiddleDot,
                PunctuationClass.Interpunct,
                PunctuationClass.Connector,
                PunctuationClass.Solidus,
                PunctuationClass.Quote,
                PunctuationClass.Other,
                -> 1.0f
            },
        )
    }
}

data class CjkPunctuationGlyphSubstitution(
    val sourceText: String,
    val displayText: String,
    val reason: String,
)

class ClreqPunctuationGlyphSubstitutor(
    private val policy: CjkPunctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
) {
    fun substitute(sourceText: String): CjkPunctuationGlyphSubstitution {
        val displayText = when (policy) {
            CjkPunctuationGlyphPolicy.PreserveInput -> sourceText
            CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints,
            CjkPunctuationGlyphPolicy.ForceClreqRecommendedCodepoints,
            -> sourceText.toClreqRecommendedDisplayText()
        }

        val reason = if (displayText == sourceText) {
            "CjkPunctuationGlyphPolicy:$policy:preserve"
        } else {
            "CjkPunctuationGlyphPolicy:$policy:${sourceText.toCodePointLabels()}->${displayText.toCodePointLabels()}"
        }

        return CjkPunctuationGlyphSubstitution(
            sourceText = sourceText,
            displayText = displayText,
            reason = reason,
        )
    }

    private fun String.toClreqRecommendedDisplayText(): String =
        when {
            all { it == '…' } -> "⋯".repeat(length)
            this == "——" -> "⸺"
            this == "・" || this == "‧" || this == "•" -> "·"
            else -> this
        }

    private fun String.toCodePointLabels(): String =
        map { char -> "U+${char.code.toString(16).uppercase().padStart(4, '0')}" }.joinToString("+")
}
