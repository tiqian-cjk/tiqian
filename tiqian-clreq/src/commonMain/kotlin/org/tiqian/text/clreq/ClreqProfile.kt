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

enum class PunctuationClass {
    Opening,
    Closing,
    PauseOrStop,
    MiddleDot,
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
            '…' -> PunctuationClass.Ellipsis
            '—' -> PunctuationClass.Dash
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
                PunctuationClass.Quote,
                PunctuationClass.Other,
                -> 1.0f
            },
        )
    }
}

