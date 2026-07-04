package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CjkTextCompatibilityTest {

    @Test
    fun composeTextStyleLowersToCjkTextStyle() {
        val style = ComposeTextStyle(
            color = Color.Blue,
            fontSize = 18.sp,
            lineHeight = 1.5.em,
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.Medium,
            fontStyle = FontStyle.Italic,
        )

        val cjk = style.toCjkTextStyle()

        assertEquals(Color.Blue, cjk.color)
        assertEquals(18.sp, cjk.fontSize)
        assertEquals(1.5.em, cjk.lineHeight)
        assertEquals(FontFamily.Serif, cjk.fontFamily)
        assertEquals(FontWeight.Medium, cjk.fontWeight)
        assertEquals(FontStyle.Italic, cjk.fontStyle)
        assertEquals(27f, cjk.lineHeightPxOrNull(Density(1f)))
    }

    @Test
    fun composeParagraphEmFontSizeResolvesAgainstBridgeDefault() {
        val style = ComposeTextStyle(
            fontSize = 1.25.em,
            lineHeight = 1.2.em,
        )

        val cjk = style.toCjkTextStyle(default = CjkTextStyle(fontSize = 20.sp))

        assertEquals(25.sp, cjk.fontSize)
        assertEquals(30f, cjk.lineHeightPxOrNull(Density(1f)) ?: -1f, 0.001f)
        assertEquals(25f, cjk.toCoreTextStyle(Density(1f)).fontSize)
    }

    @Test
    fun supportedAnnotatedStringHasNoCapabilityIssues() {
        val text = buildAnnotatedString {
            append("正文")
            withStyle(
                SpanStyle(
                    color = Color.Red,
                    background = Color.Yellow,
                    fontSize = 1.2.em,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Serif,
                    textDecoration = TextDecoration.Underline,
                ),
            ) {
                append("强调")
            }
            ruby("字", "zi")
            inlineCode { append("code") }
        }

        val compatibility = text.cjkTextCompatibility(
            ComposeTextStyle(fontSize = 1.25.em, color = Color.Black, fontFamily = FontFamily.Serif),
        )

        assertTrue(compatibility.canPreserveAllKnownSemantics)
        assertEquals(emptySet(), compatibility.issues)
    }

    @Test
    fun richAnnotationsNeedingTiqianWorkAreReported() {
        val text = buildAnnotatedString {
            withLink(LinkAnnotation.Url("https://example.com")) {
                append("链接")
            }
            append("图")
            val placeholderStart = length
            append('\uFFFC')
            addStringAnnotation(
                tag = "markdown-inline-placeholder",
                annotation = "image",
                start = placeholderStart,
                end = placeholderStart + 1,
            )
        }

        val issues = text.cjkTextCompatibility().issues

        assertFalse(issues.isEmpty())
        assertTrue(CjkTextCapabilityIssue.LinkAnnotations in issues)
        assertTrue(CjkTextCapabilityIssue.InlinePlaceholders in issues)
        assertTrue(CjkTextCapabilityIssue.UnknownStringAnnotations in issues)
    }

    @Test
    fun linkStyledTextReportsOnlyLinkActionGap() {
        val text = buildAnnotatedString {
            withLink(LinkAnnotation.Url("https://example.com")) {
                withStyle(SpanStyle(color = Color.Blue, textDecoration = TextDecoration.Underline)) {
                    append("链接")
                }
            }
        }

        val issues = text.cjkTextCompatibility().issues

        // Underline/color are preserved (RichTextSpan/ColorSpan); the only gap is the click action.
        assertEquals(setOf(CjkTextCapabilityIssue.LinkAnnotations), issues)
    }

    @Test
    fun remainingComposeStyleCapabilityIssuesAreReported() {
        val text = buildAnnotatedString {
            withStyle(SpanStyle(background = Color.Yellow, letterSpacing = 0.1.em)) {
                append("高亮")
            }
        }

        val issues = text.cjkTextCompatibility(
            ComposeTextStyle(textAlign = TextAlign.Center),
        ).issues

        // background is preserved (RichTextSpan.Background); letterSpacing/textAlign remain gaps.
        assertEquals(setOf(CjkTextCapabilityIssue.LetterSpacing, CjkTextCapabilityIssue.TextAlign), issues)
    }

    @Test
    fun overflowEllipsisIsReportedAsAMissingOverflowMarkerModel() {
        val issues = AnnotatedString("正文").cjkTextCompatibility(
            overflow = TextOverflow.Ellipsis,
        ).issues

        assertTrue(CjkTextCapabilityIssue.OverflowEllipsis in issues)
    }
}
