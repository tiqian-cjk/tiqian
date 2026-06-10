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
    val textAlign: TextAlign = TextAlign.Start,
    val writingMode: WritingMode = WritingMode.HorizontalTb,
    val lineHeight: Float? = null,
)

enum class TextAlign {
    Start,
    End,
    Center,
    Justify,
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

