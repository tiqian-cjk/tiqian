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
)

