package org.tiqian.text.clreq

import org.tiqian.text.core.BuiltInLayoutProfiles
import org.tiqian.text.core.LayoutProfileId

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
    val coalesceRepeatablePunctuation: Set<Int> = DefaultCoalesceRepeatablePunctuation,
    val hangingPunctuation: HangingPunctuationPolicy = HangingPunctuationPolicy.Disabled,
) {
    companion object {
        // CoalesceRepeatablePunctuation: codepoints that, when written as consecutive
        // repeats, form a single semantic punctuation cluster (CLREQ two-em dash and
        // ellipsis). Listed in profile so region overrides do not require engine code
        // changes. Must precede MainlandHorizontal so its constructor default resolves.
        val DefaultCoalesceRepeatablePunctuation: Set<Int> = setOf(
            0x2014,
            0x2026,
            0x22EF,
        )

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

/**
 * HangingPunctuationPolicy — controls whether and which punctuation is allowed
 * to hang past the line-end (悬挂).
 *
 * The default is [Disabled] per CLREQ commentary and JIS 4051 precedent:
 * hanging is an *optional, design-driven* refinement on top of the two
 * fundamental kinsoku operations (推入 PushIn / 推出 CarryPrevious), not a
 * generic fallback. See [ADR 0006](docs/adr/0006-hanging-punctuation-opt-in.md).
 *
 * When enabled, hanging is restricted to a small allowlist matching widespread
 * conventions:
 * - [EnabledForPauseStop]: only 。 and ，  (the JIS 4051 / InDesign default).
 * - [EnabledForExtendedCjk]: additionally hangs ！？： per mainland convention
 *   (these glyphs are visually offset in mainland fonts) and curly quotes.
 */
enum class HangingPunctuationPolicy {
    Disabled,
    EnabledForPauseStop,
    EnabledForExtendedCjk,
}

fun interface ClreqProfileResolver {
    fun resolve(profileId: LayoutProfileId): ClreqProfile
}

object BuiltInClreqProfileResolver : ClreqProfileResolver {
    override fun resolve(profileId: LayoutProfileId): ClreqProfile =
        when (profileId.value) {
            BuiltInLayoutProfiles.ClreqHorizontal.value,
            ClreqProfile.MainlandHorizontal.id,
            -> ClreqProfile.MainlandHorizontal

            else -> ClreqProfile.MainlandHorizontal
        }
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
    val defaultAdvanceEm: Float = 1f,
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
            defaultBodyEm = char.defaultPunctuationBodyEm(punctuationClass),
            defaultAdvanceEm = char.defaultPunctuationAdvanceEm(punctuationClass),
        )
    }

    private fun Char.defaultPunctuationBodyEm(punctuationClass: PunctuationClass): Float =
        when {
            this == '⸺' -> 2.0f
            punctuationClass == PunctuationClass.PauseOrStop -> 0.5f
            punctuationClass == PunctuationClass.Closing -> 0.5f
            punctuationClass == PunctuationClass.Opening -> 0.5f
            else -> 1.0f
        }

    private fun Char.defaultPunctuationAdvanceEm(punctuationClass: PunctuationClass): Float =
        when {
            this == '⸺' -> 2.0f
            punctuationClass == PunctuationClass.Other -> 1.0f
            else -> 1.0f
        }
}

object ClreqPunctuationAdvancePolicy {
    fun advanceEm(sourceText: String, displayText: String): Float =
        when {
            displayText == "⸺" -> 2.0f
            sourceText == "⸺" -> 2.0f
            else -> sourceText.codePointCount().toFloat()
        }

    private fun String.codePointCount(): Int {
        var count = 0
        var index = 0
        while (index < length) {
            index += codePointAtCompat(index).charCount()
            count += 1
        }
        return count
    }

    private fun String.codePointAtCompat(index: Int): Int {
        val high = this[index].code
        if (high !in 0xD800..0xDBFF || index + 1 >= length) return high

        val low = this[index + 1].code
        if (low !in 0xDC00..0xDFFF) return high

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun Int.charCount(): Int =
        if (this > 0xFFFF) 2 else 1
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
