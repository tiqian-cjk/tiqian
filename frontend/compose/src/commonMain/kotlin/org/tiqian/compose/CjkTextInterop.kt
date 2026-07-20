package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import org.tiqian.core.Ic
import org.tiqian.core.LastLineAlignment
import org.tiqian.core.ParagraphStyle

internal val ComposeTextParagraphStyle = ParagraphStyle(firstLineIndent = Ic.Zero)

internal data class LoweredComposeText(
    val text: AnnotatedString,
    val textStyle: CjkTextStyle,
    val paragraphStyle: ParagraphStyle,
)

internal fun resolveComposeTextStyle(
    style: ComposeTextStyle,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
): ComposeTextStyle =
    style.merge(
        ComposeTextStyle(
            color = color,
            fontSize = fontSize,
            fontStyle = fontStyle,
            fontWeight = fontWeight,
            fontFamily = fontFamily,
            textDecoration = textDecoration,
            textAlign = textAlign ?: TextAlign.Unspecified,
            lineHeight = lineHeight,
        ),
    )

internal fun lowerComposeText(
    text: AnnotatedString,
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle,
): LoweredComposeText =
    LoweredComposeText(
        text = text.withParagraphRenderStyle(style),
        textStyle = style.toCjkTextStyle(),
        paragraphStyle = lowerComposeParagraphStyle(style, paragraphStyle),
    )

internal fun lowerComposeParagraphStyle(
    style: ComposeTextStyle,
    paragraphStyle: ParagraphStyle,
): ParagraphStyle =
    paragraphStyle.withComposeTextAlign(style.textAlign)

internal fun ParagraphStyle.withCjkTextStyleLineHeight(
    textStyle: CjkTextStyle,
    density: Density,
): ParagraphStyle =
    copy(lineHeight = textStyle.lineHeightPxOrNull(density) ?: lineHeight)

private fun AnnotatedString.withParagraphRenderStyle(style: ComposeTextStyle): AnnotatedString {
    val spanStyle = style.toSpanStyle()
    val renderStyle = SpanStyle(
        background = spanStyle.background,
        baselineShift = spanStyle.baselineShift,
        textDecoration = spanStyle.textDecoration,
    )
    if (renderStyle.background == Color.Unspecified &&
        (renderStyle.baselineShift == null || renderStyle.baselineShift == BaselineShift.None) &&
        (renderStyle.textDecoration == null || renderStyle.textDecoration == TextDecoration.None)
    ) {
        return this
    }
    return buildAnnotatedString {
        withStyle(renderStyle) {
            append(this@withParagraphRenderStyle)
        }
    }
}

private fun ParagraphStyle.withComposeTextAlign(textAlign: TextAlign?): ParagraphStyle =
    when (textAlign) {
        null, TextAlign.Unspecified -> this
        TextAlign.Start, TextAlign.Left, TextAlign.Justify -> this.copy(lastLineAlignment = LastLineAlignment.Start)
        TextAlign.Center -> this.copy(lastLineAlignment = LastLineAlignment.Center)
        TextAlign.End, TextAlign.Right -> this.copy(lastLineAlignment = LastLineAlignment.End)
        else -> this
    }
