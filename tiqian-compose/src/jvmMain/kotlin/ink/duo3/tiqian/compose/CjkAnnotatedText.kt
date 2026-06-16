package ink.duo3.tiqian.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.withAnnotation
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.core.TextStyle

/** Annotation tag carrying a [DecorationKind] name over an AnnotatedString range. */
const val CjkDecorationTag = "ink.duo3.tiqian.decoration"

/**
 * Authors decorations as attributed text. Instead of counting source offsets
 * into a [DecorationSpan] (`TextRange(4, 16)`), wrap the span in [cjkEmphasis] /
 * [properNoun] / [mourning] / [bookTitle] inside `buildAnnotatedString { … }`:
 *
 * ```
 * CjkParagraph(buildAnnotatedString {
 *     append("他强调：")
 *     cjkEmphasis { append("豆子新鲜最要紧") }
 *     append("，烘焙其次。")
 * })
 * ```
 *
 * [AnnotatedString.text] is the unchanged source (复制/搜索保真). Rich-text
 * [androidx.compose.ui.text.SpanStyle]s are ignored for now — they slot in when
 * the engine consumes `TiqianTextContent.spans` (see roadmap 富文本).
 */
@Composable
fun CjkParagraph(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = TextStyle(),
    paragraphStyle: ParagraphStyle = ParagraphStyle(),
    profile: ClreqProfile = ClreqProfile.MainlandHorizontal,
    measurer: ParagraphMeasurer = rememberParagraphMeasurer(profile),
) {
    CjkParagraph(
        text = text.text,
        modifier = modifier,
        textStyle = textStyle,
        paragraphStyle = paragraphStyle,
        profile = profile,
        decorations = text.cjkDecorations(),
        measurer = measurer,
    )
}

/** Extracts [DecorationSpan]s from the [CjkDecorationTag] annotations. */
fun AnnotatedString.cjkDecorations(): List<DecorationSpan> =
    getStringAnnotations(CjkDecorationTag, 0, length).map {
        DecorationSpan(TextRange(it.start, it.end), DecorationKind.valueOf(it.item))
    }

/** 着重号 over [block]'s text. */
inline fun AnnotatedString.Builder.cjkEmphasis(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Emphasis.name) { block() }
}

/** 专名号（straight underline）over [block]'s text. */
inline fun AnnotatedString.Builder.properNoun(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.ProperNoun.name) { block() }
}

/** 示亡号（mourning frame）over [block]'s text. */
inline fun AnnotatedString.Builder.mourning(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.Mourning.name) { block() }
}

/** 书名号甲式（wavy underline）over [block]'s text. */
inline fun AnnotatedString.Builder.bookTitle(crossinline block: AnnotatedString.Builder.() -> Unit) {
    withAnnotation(CjkDecorationTag, DecorationKind.BookTitle.name) { block() }
}
