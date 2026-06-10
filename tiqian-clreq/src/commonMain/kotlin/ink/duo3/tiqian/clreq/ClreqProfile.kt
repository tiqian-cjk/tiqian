package ink.duo3.tiqian.clreq

import ink.duo3.tiqian.core.BuiltInLayoutProfiles
import ink.duo3.tiqian.core.LayoutProfileId

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
    val autoSpace: AutoSpacePolicy = AutoSpacePolicy.Default,
    val gluePlacement: PunctuationGluePlacement = PunctuationGluePlacement.forRegion(region),
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

        val TaiwanHorizontal = ClreqProfile(
            id = "clreq-taiwan-horizontal",
            strictness = ClreqStrictness.Normal,
            region = ClreqRegion.Taiwan,
        )

        val HongKongHorizontal = ClreqProfile(
            id = "clreq-hongkong-horizontal",
            strictness = ClreqStrictness.Normal,
            region = ClreqRegion.HongKong,
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

/**
 * Where the half-width body of a punctuation atom sits within its em box,
 * and therefore which side(s) receive the rest as glue. Per CLREQ 3.1.3
 * (Punctuation Position) the same character can sit in different positions
 * depending on region:
 *
 * - 简体中文 (Mainland): 句号 / 逗号 居于格内左下 → body anchored leading,
 *   glue all trailing → [TrailingOnly].
 * - 繁体中文 (Taiwan / Hong Kong): 句号 / 逗号 居于格内中央 → body centered,
 *   glue split on both sides → [BothSides].
 * - Opening marks (`「（《〈『`) mirror this: body anchored trailing under
 *   Mainland; centered under Traditional. Leading-only is the regional
 *   default for Mainland opening marks → [LeadingOnly].
 *
 * Per ADR 0014, this is a typography decision driven by region/profile,
 * not by the font's glyph position. Low-quality fonts that draw all
 * punctuation glyphs centered regardless of region (early Microsoft YaHei,
 * some Founder fonts) are handled by the rendering layer using ink bounds
 * to translate the glyph into the position the profile asks for; the
 * additive glue model continues to derive its directions from here.
 */
enum class PunctuationGluePlacement {
    /** Mainland / Simplified convention. */
    MainlandSimplified,

    /** Traditional Chinese convention (Taiwan, Hong Kong). */
    Traditional;

    companion object {
        fun forRegion(region: ClreqRegion): PunctuationGluePlacement =
            when (region) {
                ClreqRegion.Mainland -> MainlandSimplified
                ClreqRegion.Taiwan, ClreqRegion.HongKong -> Traditional
                ClreqRegion.Custom -> MainlandSimplified
            }
    }
}

/** Where the glue sits relative to the body for a given punctuation class. */
enum class GlueSide {
    LeadingOnly,
    TrailingOnly,
    BothSides,
}

fun PunctuationGluePlacement.glueSideFor(punctuationClass: PunctuationClass): GlueSide =
    when (this) {
        PunctuationGluePlacement.MainlandSimplified -> when (punctuationClass) {
            PunctuationClass.Opening -> GlueSide.LeadingOnly
            PunctuationClass.Closing,
            PunctuationClass.PauseOrStop,
            -> GlueSide.TrailingOnly

            else -> GlueSide.BothSides
        }

        PunctuationGluePlacement.Traditional -> when (punctuationClass) {
            // Per CLREQ 3.1.3, Traditional places 。 ， etc. at the centre,
            // so both Opening and Closing/PauseOrStop become BothSides.
            // The "anchor to one side" behaviour is a Simplified-only style.
            else -> GlueSide.BothSides
        }
    }


/**
 * AutoSpacePolicy — controls how spacing between CJK ideographs and Latin /
 * digit runs is materialised. Mirrors the CSS Text Module Level 4
 * `text-autospace` model (per-boundary mode + a configurable gap width)
 * rather than the project's earlier ad-hoc approach of treating typed
 * U+0020 spaces as opaque clusters.
 *
 * See [ADR 0009](docs/adr/0009-autospace-policy.md).
 *
 * Per-boundary [AutoSpaceMode] decides:
 * - `Disabled`: no engine-inserted space; typed U+0020 renders at its
 *    nominal 1em advance (i.e. classic stub behaviour).
 * - `Replace` (default): typed U+0020 at a CJK ↔ Latin / digit boundary is
 *    absorbed into the autospace gap. The space cluster's advance shrinks
 *    from 1em to [gapEm] so the visible result is a single configurable gap,
 *    not 1em + autospace double-count.
 * - `Insert`: typed U+0020 is preserved at full 1em AND an autospace gap is
 *    added on top. Used by editorial workflows that need the U+0020 to
 *    round-trip through copy/paste. Reserved; not implemented in current
 *    slice (requires virtual cluster injection).
 *
 * [gapEm] is the autospace gap width in em, applied uniformly across both
 * boundary types unless overridden. CSS default `text-autospace: normal`
 * lands around 0.125–0.25 em depending on font; we pick `0.25` to match the
 * existing `Justifier.cjkLatinSpaceEm` so the same number governs typed-
 * space replacement and justification stretch capacity.
 */
data class AutoSpacePolicy(
    val cjkLatin: AutoSpaceMode = AutoSpaceMode.Replace,
    val cjkDigit: AutoSpaceMode = AutoSpaceMode.Replace,
    val gapEm: Float = 0.25f,
) {
    companion object {
        val Default = AutoSpacePolicy()
        val Disabled = AutoSpacePolicy(
            cjkLatin = AutoSpaceMode.Disabled,
            cjkDigit = AutoSpaceMode.Disabled,
        )
    }
}

enum class AutoSpaceMode {
    Disabled,
    Replace,
    Insert,
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
            // CLREQ forbids 点号 / closing marks / centred separators at line
            // start, but Dash and Ellipsis are only protected from being
            // SPLIT（「破折号/省略号不得以适配分行之由断开或拆至两行」）—
            // starting a line with —— is legitimate (dialogue dashes do it
            // by construction). See clreq-punctuation-audit.md.
            allowAtLineStart = punctuationClass == PunctuationClass.Opening ||
                punctuationClass == PunctuationClass.Other ||
                punctuationClass == PunctuationClass.Dash ||
                punctuationClass == PunctuationClass.Ellipsis,
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
