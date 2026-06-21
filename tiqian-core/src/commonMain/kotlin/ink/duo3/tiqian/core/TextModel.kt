package ink.duo3.tiqian.core

data class TiqianTextContent(
    val text: String,
    val spans: List<TextSpan> = emptyList(),
)

data class TextSpan(
    val range: TextRange,
    val style: TextStyle,
)

data class TextStyle(
    val fontFamilies: List<String> = emptyList(),
    val fontSize: Float = 16f,
    val locale: String = "zh-Hans",
    /** OpenType weight axis (400 = Regular, 700 = Bold); drives the shaped typeface. */
    val fontWeight: Int = 400,
    /** Slant axis: italic/oblique typeface when the family offers one (ADR 0030 B 档). */
    val italic: Boolean = false,
)

/**
 * Inline decoration over a SOURCE text range (ADR 0018). Display
 * substitutions do not affect span semantics. Decorations are pure
 * render-geometry: they never participate in metrics, line breaking or
 * justification.
 */
data class DecorationSpan(
    val range: TextRange,
    val kind: DecorationKind,
)

/**
 * Per-span text color (ARGB) over a SOURCE range — rich-text 颜色 (ADR 0030 A 档).
 * Render-only: like [DecorationSpan] it never affects metrics, breaking or
 * justification, so it rides beside the layout model rather than inside it.
 * Platform-neutral (`argb` Int) so the frontend contract carries no Skia type.
 */
data class ColorSpan(val start: Int, val end: Int, val argb: Int)

/**
 * 行间注 (ruby, ADR 0032): small-size annotation [text] over a base SOURCE
 * [baseRange] — 拼音 above the base (this slice). Unlike [DecorationSpan], ruby
 * DOES affect layout: it reserves line height and keeps the base unbreakable.
 * [text] is NOT part of the source (拼音 不进源；复制/搜索保真) — it lives only here.
 */
data class RubySpan(
    val baseRange: TextRange,
    val text: String,
    /**
     * 注文专用字体（family 名优先列表）。注音需含 ㄅㄆㄇ 字形的字体、拼音/释义可
     * 用各自的字体——注文字体本就该独立于正文（ADR 0032）。空 = 渲染器默认。
     */
    val fontFamilies: List<String> = emptyList(),
    /** 拼音（上方，ADR 0032）或 注音（右侧竖排 ㄅㄆㄇ，ADR 0033）。 */
    val kind: RubyKind = RubyKind.Pinyin,
)

enum class RubyKind {
    /** 罗马拼音：注文在基字**上方**、水平居中（ADR 0032）。 */
    Pinyin,

    /** 注音符号：注文在基字**右侧**、ㄅㄆㄇ 竖排 + 调号、纵横对齐（ADR 0033）。 */
    Zhuyin,
}

enum class DecorationKind {
    /** CLREQ 着重号 — a solid dot under each emphasised Han character. */
    Emphasis,

    /**
     * 示亡号 — a solid black frame around a (deceased person's) name.
     * The span is kept unbroken across line breaks whenever it fits on one
     * line; when it cannot fit it splits into per-line open-ended segments.
     */
    Mourning,

    /**
     * 专名号 — a straight underline below a proper noun (horizontal
     * writing). One of the CLREQ 行间线: one continuous segment per
     * annotated item, length matching the text's outer frame, never split
     * or pieced together within a line; adjacent items shorten their
     * ADJACENT sides only (≤1/8 em) so the two marks read separately.
     */
    ProperNoun,

    /**
     * 书名号（甲式）— a wavy underline below a work's title (horizontal
     * writing). Same 行间线 segment rules as [ProperNoun].
     */
    BookTitle,
}

data class ParagraphStyle(
    /**
     * Alignment of the paragraph's LAST line only. CLREQ:「与西文排版不同，
     * 中文排版特别是书籍正文排版极少使用左齐右不齐，原则上应该进行两端
     * 对齐」— justification is the baseline behaviour, not an option: every
     * non-last line is always justified (挤压/拉伸已使行长一致). The only
     * degree of freedom is the last line — start (default), centered, or
     * end-aligned (落款、引文出处等特殊用法). A single-line paragraph is its
     * own last line, so headings and labels are never stretched.
     */
    val lastLineAlignment: LastLineAlignment = LastLineAlignment.Start,
    val writingMode: WritingMode = WritingMode.HorizontalTb,
    /**
     * Baseline-to-baseline line height, in **the same units as
     * [TextStyle.fontSize] (engine pixels), not a multiplier**. `null` = the
     * `CjkBodyLineHeightDefault` (1.5em — 中文正文 leading). A value overrides
     * that default in either direction, but is still **clamped up** to the
     * no-overlap minimum (字面 + any [InterlinearMarkLineSpacingFloor]) — a line
     * shorter than the content would overlap glyphs/marks, so values below ~1em
     * have no effect (the resolution is recorded in `LineSpacingDecisionInfo`).
     * To set 1.5× of a 16px font, pass `24f`, not `1.5f`.
     */
    val lineHeight: Float? = null,
    /**
     * 段首缩进的**显式覆盖**，单位 `ic`（字身框，ADR 0034）。`0.ic` disables
     * the indent; any non-null value pins it regardless of measure. `null`
     * (default) means「不指定」→ 由 [firstLineIndentPolicy] 按行长自适应决定
     * （CLREQ「段首缩排以两个汉字的空间为标准」，窄行缩一字）。The indent
     * insets the FIRST line's start edge only (in vertical writing this
     * becomes a block-start inset of the first column). A first line opening
     * with a bracket or quote needs no special casing: the additive glue model
     * already trims the opening punctuation's leading blank at every line
     * start, which IS CLREQ's「缩减该符号始侧二分之一个汉字大小的空白」.
     */
    val firstLineIndent: Ic? = null,
    /**
     * 整段缩进（CLREQ §6.2.1.2 段落缩排），单位 `ic`：**所有行**的始端都内移这么多
     * （引用、诗词、标题块）。[firstLineIndent] 叠加在它之上、且**相对于它**，
     * 可为负——`blockIndent = H.ic, firstLineIndent = (-H).ic` 即「凸排」（首行齐头、
     * 次行起缩 H）。每行有效缩进 = `(blockIndent + 该行 firstLine 部分)`，钳到 ≥0。
     */
    val blockIndent: Ic = Ic.Zero,
    /**
     * 段首缩进随行长自适应的默认策略（仅当 [firstLineIndent] 为 null 时
     * 生效）. See [MeasureAdaptiveFirstLineIndent].
     */
    val firstLineIndentPolicy: MeasureAdaptiveFirstLineIndent = MeasureAdaptiveFirstLineIndent(),
    /**
     * 行长字号整数倍量化（grid-first, ADR 0007 的完整形态）. See [LineLengthGrid].
     */
    val lineLengthGrid: LineLengthGrid = LineLengthGrid(),
)

/**
 * `MeasureAdaptiveFirstLineIndent`（ADR 0021 amendment）：段首缩进随行长
 * 自适应——窄行（measure < [shortBelowEm] 字）缩 [shortEm] 字，宽行缩
 * [longEm] 字。窄栏（多栏杂志、手机正文）里 2 字缩进占比过重，CLREQ 也记
 * 多栏常缩一字，故默认窄行缩一字。
 *
 * 阈值默认 14 字，与 `MeasureAdaptiveKinsoku` 的悬挂阈值同值但**独立**——
 * 两者回答不同问题（悬挂：整字下移是否过松；缩进：2 字是否过重），可分别
 * 调，且本策略在 `KinsokuMode.Fixed` 下仍生效（不依赖悬挂信号）。
 *
 * 与行长无关地固定缩进，用 [ParagraphStyle.firstLineIndent]（显式值，含
 * 0 关闭）覆盖。
 */
data class MeasureAdaptiveFirstLineIndent(
    val shortBelowEm: Float = 14f,
    val shortEm: Float = 1f,
    val longEm: Float = 2f,
) {
    fun resolveEm(measureEm: Float): Float = if (measureEm < shortBelowEm) shortEm else longEm
}

/**
 * 把可用行长向下取整到字号的整数倍（N 字宽），让正文严格落在字格上
 * （grid-first, ADR 0007）. 响应式 / 实际容器宽度几乎不会恰好是字号的整数
 * 倍；引擎不能要求调用方在排版前就给出对齐字格的精确值，因此默认**向下
 * 取整**得到版心，余下不足一字的空白（slack ∈ [0, fontSize)）按
 * [bodyAlignment] 在容器内左右摆放整块正文。
 *
 * 某些边缘情形——已知精确像素行长、非中文正文、或调用方自己做了字格
 * 对齐——可 `enabled = false` 绕过，直接用原始 maxWidth。
 */
data class LineLengthGrid(
    val enabled: Boolean = true,
    /**
     * 正文块在容器内（量化后余量上）的横向对齐。CLREQ 双齐正文的唯一对齐
     * 自由度是末行（[ParagraphStyle.lastLineAlignment]）；正文块在容器内
     * 的摆放默认**跟随**该末行对齐（`null`），也可在此独立 override。
     */
    val bodyAlignment: LastLineAlignment? = null,
)

enum class LastLineAlignment {
    Start,
    Center,
    End,
}

enum class WritingMode {
    HorizontalTb,
    VerticalRl,
}

data class LayoutProfileId(
    val value: String,
)

object BuiltInLayoutProfiles {
    val ClreqHorizontal = LayoutProfileId("clreq-horizontal")
}

data class LayoutInput(
    val content: TiqianTextContent,
    val textStyle: TextStyle = TextStyle(),
    val paragraphStyle: ParagraphStyle = ParagraphStyle(),
    val constraints: LayoutConstraints,
    val profileId: LayoutProfileId = BuiltInLayoutProfiles.ClreqHorizontal,
    val decorations: List<DecorationSpan> = emptyList(),
    val rubySpans: List<RubySpan> = emptyList(),
)

