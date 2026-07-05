package org.tiqian.clreq

import org.tiqian.core.BuiltInLayoutProfiles
import org.tiqian.core.LayoutProfileId

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
    val autoSpace: AutoSpacePolicy = AutoSpacePolicy.Default,
    val gluePlacement: PunctuationGluePlacement = PunctuationGluePlacement.forRegion(region),
    val adjustment: AdjustmentStylePolicy = AdjustmentStylePolicy(),
    /**
     * 行首行尾禁则档 + 行尾悬挂的解析方式。默认 [KinsokuMode.MeasureAdaptive]
     * ——按行长（字数）自适应；[KinsokuMode.Fixed] 固定一档。
     */
    val kinsokuMode: KinsokuMode = KinsokuMode.MeasureAdaptive(),
    /** 标点宽度风格（全身式 / 开明式；GB 固定半宽连接号等）. */
    val punctuationWidth: PunctuationWidthPolicy = PunctuationWidthPolicy(),
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
    val cjkLatin: AutoSpaceMode = AutoSpaceMode.Insert,
    val cjkDigit: AutoSpaceMode = AutoSpaceMode.Insert,
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

/**
 * 行内调整（挤压/拉伸）的风格开关。CLREQ 的调整程序是默认侧；每个开关都
 * 对应原文点名的「部分排版风格」变体。
 */
data class AdjustmentStylePolicy(
    /**
     * 严格风格（默认）：行尾标点无条件削成半宽（`LineEndHalfWidthPunctuation`）。
     * 宽松风格：行尾标点保留全宽，其空白只在需要挤压时按需消耗——字身网格
     * 在行尾保持完整，墨迹缘允许参差。
     */
    val lineEndPunctuation: LineEndPunctuationStyle = LineEndPunctuationStyle.ForceHalfWidth,
    /**
     * CLREQ 挤压第④档：「位于行内的句号、问号、感叹号……最小挤为半个汉字
     * 字宽」。「有些排版风格禁止此项调整，而保持句号、问号、惊叹号固定一个
     * 字宽」→ false 时这些标点不进挤压容量。
     */
    val allowInlineStopCompression: Boolean = true,
    /**
     * 「在一些排版风格中，中西间距固定默认宽度……被排除在行内调整对象之外，
     * 不允许被挤压（/拉伸）」→ false 时 sino-western gap 既不进挤压容量，
     * 也不参与 justify 的 CjkLatinSpace 拉伸档。
     */
    val allowSinoWesternGapAdjustment: Boolean = true,
    /**
     * CLREQ 拉伸第②档中西间距的拉伸上限（final width，单位 em）。原文上限是半个
     * 汉字宽（`0.5`），注②记「很多排版风格在实际处理上，只允许最大拉伸到三分之
     * 一汉字宽」→ 设 `1f / 3f`。仅影响 justify 的 CjkLatinSpace 档上限，不改默认
     * 间距（`autoSpace.gapEm`）。
     */
    val sinoWesternStretchMaxEm: Float = 0.5f,
    /**
     * 行尾越界字的「推入/推出」取舍（CLREQ §6.2.2「先挤进、后推出」+ 行内
     * 「先挤压、后拉伸」）。默认 [LineAdjustmentStrategy.PushInFirst]——固定
     * 顺序；曾有过「偏差最小化」的 Auto 档，实际观感差，已删（ADR 0031 修订）。
     */
    val lineAdjustment: LineAdjustmentStrategy = LineAdjustmentStrategy.PushInFirst,
)

/**
 * 行尾越界那一字落在本行还是下一行的取舍——压缩(推入)与拉伸(推出)的方向选择。
 * 压缩/拉伸的「档内分配」始终按 §6.2.2.3/§6.2.2.4 的 tier 顺序，本枚举只决定**方向**。
 */
enum class LineAdjustmentStrategy {
    /** 先推入：压得动就把越界字挤进来（CLREQ「先挤进」的字面顺序），压不动才推出。默认。 */
    PushInFirst,

    /** 先推出：能断就把越界字推到下一行拉伸本行，只有推出会触发均排兜底时才回头推入。 */
    PushOutFirst,

    /** 仅推出：永不为容纳越界字而压缩——一律断行、拉伸（旧行为）。 */
    PushOutOnly,
}

enum class LineEndPunctuationStyle {
    ForceHalfWidth,
    AllowFullWidth,
}

/**
 * CLREQ 第六节「行首行尾禁则」四档（逐档收紧）。命名对齐 CLREQ 原文：
 *
 * - [None]（不处理）——完全不处理行首行尾禁则。常见于台港报刊。
 * - [Basic]（基本处理）——点号、结束引号/括号/书名号乙式、连接号、
 *   间隔号、分隔号不得居行首；开始引号/括号/书名号乙式不得居行尾。
 *   CLREQ「这是最推荐的方法」，本项目默认。
 * - [GbStyle]（GB 法）——在基本处理上追加：分隔号也不得居行尾。
 * - [Strict]（严格处理）——在 GB 法上追加：破折号、省略号不得居行首。
 */
enum class KinsokuLevel {
    None,
    Basic,
    GbStyle,
    Strict,
}

/**
 * 标点宽度风格——标点的默认占宽，落到加法模型上即「字面 + 空隙」中空隙
 * 是否默认归零（半字、不可调）。
 *
 * - [interior] 全身式（默认）vs 开明式：开明式下**句中点号**（逗号、顿号、
 *   分号、冒号）与**夹注/括号/引号**占半字，**句末点号**（句号、问号、
 *   感叹号）仍占一字。CLREQ issue #572：「句中点号、夹注号半字，句末点号
 *   （除行末外）一字」。
 * - [gbFixedSeparators] GB 式固定半宽：连接号、间隔号、分隔号固定半字、
 *   不可调整（CLREQ「不可调整的标点……固定半个字宽」）。
 */
data class PunctuationWidthPolicy(
    val interior: InteriorPunctuationStyle = InteriorPunctuationStyle.FullWidth,
    val gbFixedSeparators: Boolean = false,
)

enum class InteriorPunctuationStyle {
    FullWidth,
    Kaiming,
}

/** Resolved kinsoku level + hanging style for a given measure. */
data class ResolvedKinsoku(
    val level: KinsokuLevel,
    val hanging: HangingPunctuationStyle,
    val reason: String,
)

/**
 * How禁则档 + 悬挂 are chosen. [Fixed] pins them; [MeasureAdaptive] keys on
 * the line measure in 字（汉字数）, per the wiki/lit corpus experiment:
 *
 * - 行长 < 14 字：启用行尾悬挂——窄行（手机正文）悬挂消灭无法修复的行、
 *   腰斩 CarryPrevious 的整字推出（收益在此区间最明显）；
 * - 行长 > 24 字：用 GB 法（追加分隔号禁行尾）；
 * - 行长 > 32 字：用严格处理（追加破折号/省略号禁行首）——宽行可负担
 *   更严的禁则（实验：宽行下更严档的代价趋零）；
 * - 其余：基本处理（CLREQ「最推荐」）。
 *
 * 注：CLREQ 主张「一份文档内禁则级别应统一」；自适应是面向响应式/移动端
 * 重排（measure 随容器变）的现代扩展，决策记入 dump。
 */
sealed interface KinsokuMode {
    fun resolve(measureEm: Float): ResolvedKinsoku

    data class Fixed(
        val level: KinsokuLevel,
        val hanging: HangingPunctuationStyle = HangingPunctuationStyle.Disabled,
    ) : KinsokuMode {
        override fun resolve(measureEm: Float): ResolvedKinsoku =
            ResolvedKinsoku(level, hanging, "Fixed:$level${if (hanging != HangingPunctuationStyle.Disabled) "+Hang" else ""}")
    }

    data class MeasureAdaptive(
        val hangBelowEm: Float = 14f,
        val gbAboveEm: Float = 24f,
        val strictAboveEm: Float = 32f,
    ) : KinsokuMode {
        override fun resolve(measureEm: Float): ResolvedKinsoku {
            val level = when {
                measureEm > strictAboveEm -> KinsokuLevel.Strict
                measureEm > gbAboveEm -> KinsokuLevel.GbStyle
                else -> KinsokuLevel.Basic
            }
            val hanging = if (measureEm < hangBelowEm) {
                HangingPunctuationStyle.PauseStops
            } else {
                HangingPunctuationStyle.Disabled
            }
            val tag = "MeasureAdaptiveKinsoku:${measureEm.toInt()}字→$level" +
                if (hanging != HangingPunctuationStyle.Disabled) "+Hang" else ""
            return ResolvedKinsoku(level, hanging, tag)
        }
    }
}

enum class HangingPunctuationStyle {
    /** 不悬挂（默认）：行尾点号走挤进/推出修复链。 */
    Disabled,

    /**
     * 悬挂顿号、逗号、句号（CLREQ「适合行尾悬挂的标点符号有顿号、逗号及
     * 句号」）。行尾只悬挂一个。
     */
    PauseStops,
}

/**
 * CLREQ:「原则上，汉字与西文字母、数字间使用不多于四分之一个汉字宽的字距
 * 或空白。」The gap exists whether or not the author typed U+0020.
 */
enum class AutoSpaceMode {
    Disabled,

    /**
     * Only normalise TYPED spaces at the boundary down to [AutoSpacePolicy.gapEm]
     * (`TextAutoSpaceReplace`); boundaries without a typed space get nothing.
     * Conservative pre-Insert behaviour, kept for styles that treat missing
     * spaces as authorial intent.
     */
    Replace,

    /**
     * Full CLREQ behaviour, superset of [Replace]: boundaries WITHOUT a typed
     * space additionally gain a [AutoSpacePolicy.gapEm] gap
     * (`TextAutoSpaceInsert`). Default.
     */
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

    /** 句末点号（句号、问号、感叹号）——开明式下仍占一字. */
    private val SentenceEndStops = setOf('。', '！', '？', '．')

    /**
     * Whether [char] is forced to a fixed half-width (body only, no
     * adjustable glue) by the punctuation-width [policy]. Drives the atom
     * builder's advance override.
     */
    fun forcedHalfWidth(char: Char, policy: PunctuationWidthPolicy): Boolean {
        // 短横线占半个字位置（CLREQ 5.1.6，与风格无关；grid 占位，覆盖
        // 字体 glyph advance）.
        if (char in ShortHyphenConnectors) return true
        val cls = classify(char)
        if (policy.gbFixedSeparators &&
            cls in setOf(
                PunctuationClass.Connector,
                PunctuationClass.MiddleDot,
                PunctuationClass.Interpunct,
                PunctuationClass.Solidus,
            )
        ) {
            return true
        }
        if (policy.interior == InteriorPunctuationStyle.Kaiming) {
            // 句中点号(，、；：) + 夹注/括号/引号 半字；句末点号(。！？) 全字.
            if (cls == PunctuationClass.Opening || cls == PunctuationClass.Closing) return true
            if (cls == PunctuationClass.PauseOrStop && char !in SentenceEndStops) return true
        }
        return false
    }

    fun policyFor(char: Char): PunctuationPolicy {
        val punctuationClass = classify(char)
        return PunctuationPolicy(
            punctuationClass = punctuationClass,
            // The boolean fields hold the CLREQ 基本处理 (Basic) level —
            // the「最推荐」default. KinsokuLevel applies deltas on top
            // (see forbiddenAtLineStart/End below).
            allowAtLineStart = !forbiddenAtLineStart(char, KinsokuLevel.Basic),
            allowAtLineEnd = !forbiddenAtLineEnd(char, KinsokuLevel.Basic),
            defaultBodyEm = char.defaultPunctuationBodyEm(punctuationClass),
            defaultAdvanceEm = char.defaultPunctuationAdvanceEm(punctuationClass),
        )
    }

    /**
     * 行首行尾禁则，按 CLREQ 第六节四档（[KinsokuLevel]）逐档收紧。CLREQ:
     * 「行首行尾禁则规定属于排版风格，用户代理实现时可以根据自身实际情况，
     * 选择或者自定义……更宽松或者严格的禁则」。
     *
     * 破折号/省略号在 基本处理 / GB 法 下**不**禁于行首——它们只被保护
     * 不被拆行（见 clreq-punctuation-audit.md），对话破折号本就以行首
     * 开头；只有 严格处理 才追加此禁则。
     */
    fun forbiddenAtLineStart(char: Char, level: KinsokuLevel): Boolean {
        if (level == KinsokuLevel.None) return false
        return when (classify(char)) {
            // 点号、结束引号/括号/书名号乙式、连接号、间隔号、分隔号.
            PunctuationClass.PauseOrStop,
            PunctuationClass.Closing,
            PunctuationClass.Quote,
            PunctuationClass.Connector,
            PunctuationClass.MiddleDot,
            PunctuationClass.Interpunct,
            PunctuationClass.Solidus,
            -> true
            // 破折号、省略号：仅 严格处理 追加禁于行首.
            PunctuationClass.Dash,
            PunctuationClass.Ellipsis,
            -> level == KinsokuLevel.Strict
            else -> false
        }
    }

    fun forbiddenAtLineEnd(char: Char, level: KinsokuLevel): Boolean {
        if (level == KinsokuLevel.None) return false
        return when (classify(char)) {
            // 开始引号/括号/书名号乙式.
            PunctuationClass.Opening -> true
            // 分隔号：GB 法 / 严格处理 追加禁于行尾.
            PunctuationClass.Solidus -> level != KinsokuLevel.Basic
            else -> false
        }
    }

    /**
     * 短横线（连接号的一种）占半个字位置（CLREQ / GB/T 15834 5.1.6），与
     * 浪纹线 ～（一字）区别。U+002D HYPHEN-MINUS、U+2013 EN DASH。
     */
    private val ShortHyphenConnectors = setOf('-', '–')

    private fun Char.defaultPunctuationBodyEm(punctuationClass: PunctuationClass): Float =
        when {
            this == '⸺' -> 2.0f
            this in ShortHyphenConnectors -> 0.5f
            punctuationClass == PunctuationClass.PauseOrStop -> 0.5f
            punctuationClass == PunctuationClass.Closing -> 0.5f
            punctuationClass == PunctuationClass.Opening -> 0.5f
            else -> 1.0f
        }

    private fun Char.defaultPunctuationAdvanceEm(punctuationClass: PunctuationClass): Float =
        when {
            this == '⸺' -> 2.0f
            this in ShortHyphenConnectors -> 0.5f
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
