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

enum class DecorationKind {
    /** CLREQ 着重号 — a solid dot under each emphasised Han character. */
    Emphasis,

    /**
     * 示亡号 — a solid black frame around a (deceased person's) name.
     * The span is kept unbroken across line breaks whenever it fits on one
     * line; when it cannot fit it splits into per-line open-ended segments.
     */
    Mourning,
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
    val lineHeight: Float? = null,
    /**
     * 段首缩进, in ems of the paragraph font size. CLREQ: 「段首缩排以两个
     * 汉字的空间为标准」— hence the default 2. Multi-column magazine styles
     * commonly use 1; 0 disables the indent. The indent insets the FIRST
     * line's start edge only (in vertical writing this becomes a block-start
     * inset of the first column). A first line opening with a bracket or
     * quote needs no special casing: the additive glue model already trims
     * the opening punctuation's leading blank at every line start, which IS
     * CLREQ's「缩减该符号始侧二分之一个汉字大小的空白」.
     */
    val firstLineIndentEm: Float = 2f,
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
)

