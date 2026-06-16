package ink.duo3.tiqian.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextStyle

/**
 * Lays out MULTIPLE paragraphs (CLREQ §6.2.1 段落调整). Each paragraph runs the
 * engine independently via [CjkParagraph] — `CjkText` makes no layout decisions
 * of its own; it only splits the source into paragraphs, picks the per-paragraph
 * 段首缩排 style, and stacks them.
 *
 * **Consistent 行距 across paragraphs (CLREQ:「前段落末行、后段落首行与段落内
 * 行距一致」)** falls out for free with zero `Column` spacing: every line box
 * carries half its leading above and half below the baseline, so abutting two
 * paragraph blocks puts the cross-paragraph baseline gap at exactly one
 * `lineHeight` — same as inside a paragraph. Only [ParagraphLeadStyle.NoIndentSpaced]
 * adds a real 段间距.
 */
@Composable
fun CjkText(
    text: String,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    leadStyle: ParagraphLeadStyle = ParagraphLeadStyle.AllIndent,
    paragraphSpacing: Dp = 12.dp,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(profile),
) {
    // `\n` separates paragraphs; a blank line (CLREQ 节/section) is dropped for
    // now — pass an explicit List to control section structure precisely.
    val paragraphs = remember(text) {
        text.split('\n').map { it.trim('\r') }.filter { it.isNotBlank() }
    }
    CjkText(paragraphs, modifier, textStyle, paragraphStyle, profile, leadStyle, paragraphSpacing, measurer)
}

@Composable
fun CjkText(
    paragraphs: List<String>,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    leadStyle: ParagraphLeadStyle = ParagraphLeadStyle.AllIndent,
    paragraphSpacing: Dp = 12.dp,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(profile),
) {
    val gap = if (leadStyle == ParagraphLeadStyle.NoIndentSpaced) paragraphSpacing else 0.dp
    Column(modifier, verticalArrangement = Arrangement.spacedBy(gap)) {
        paragraphs.forEachIndexed { index, paragraph ->
            // leadStyle only chooses WHICH first lines indent; the indent amount
            // itself stays the engine's MeasureAdaptiveFirstLineIndent decision
            // (null = adaptive default).
            val indentEm = when (leadStyle) {
                ParagraphLeadStyle.AllIndent -> paragraphStyle.firstLineIndentEm
                ParagraphLeadStyle.FirstParagraphFlush ->
                    if (index == 0) 0f else paragraphStyle.firstLineIndentEm
                ParagraphLeadStyle.NoIndentSpaced -> 0f
            }
            CjkParagraph(
                text = paragraph,
                textStyle = textStyle,
                paragraphStyle = paragraphStyle.copy(firstLineIndentEm = indentEm),
                profile = profile,
                measurer = measurer,
            )
        }
    }
}

/**
 * CLREQ §6.2.1.1 段首缩排 的跨段风格。行内缩进量仍由引擎的
 * `MeasureAdaptiveFirstLineIndent` 决定，这里只选「哪些段首缩 / 段间是否留白」。
 * 凸排（首行不缩、次行起缩）与 §6.2.1.2 段落缩排（整段块缩进）需引擎/标注支持，
 * 列为后续。
 */
enum class ParagraphLeadStyle {
    /** ① 全段首行缩进（书刊默认）。 */
    AllIndent,

    /** ② 首段不缩、其余段缩进（西文书习惯）。 */
    FirstParagraphFlush,

    /** ③ 全不缩进、段间加 [CjkText] 的 `paragraphSpacing` 区分段。 */
    NoIndentSpaced,
}
