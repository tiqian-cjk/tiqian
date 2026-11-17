package org.tiqian.android.view

import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.text.style.ImageSpan
import android.text.style.QuoteSpan
import android.text.style.RelativeSizeSpan
import android.text.style.ScaleXSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.URLSpan
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.ColorSpan
import org.tiqian.core.LineThrough
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.Underline
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class TiqianSpannedContentTest {
    @Test
    fun lowersPlatformRichTextVocabulary() {
        val source = SpannableString("粗体色删链接").apply {
            setSpan(StyleSpan(Typeface.BOLD), 0, 2, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(ForegroundColorSpan(Color.RED), 2, 3, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(StrikethroughSpan(), 3, 4, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(URLSpan("https://example.com"), 4, 6, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

        val content = CjkTextContent(source, TextStyle(fontSize = 32f))

        assertEquals("粗体色删链接", content.content.text)
        assertEquals(
            listOf(TextSpan(TextRange(0, 2), TextStyle(fontSize = 32f, fontWeight = 700))),
            content.content.spans,
        )
        assertEquals(listOf(ColorSpan(2, 3, Color.RED)), content.colorSpans)
        assertTrue(RichTextSpan(TextRange(3, 4), LineThrough.instance) in content.richTextSpans)
        assertTrue(
            RichTextSpan(TextRange(4, 6), Link("https://example.com")) in
                content.richTextSpans,
        )
        assertTrue(RichTextSpan(TextRange(4, 6), Underline.instance) in content.richTextSpans)
        assertTrue(source.cjkSpannedCompatibility().canPreserveAllKnownSemantics)
    }

    @Test
    fun overlappingStyleSpansFlattenIntoResolvedSegments() {
        val base = TextStyle(fontSize = 20f)
        val source = SpannableString("甲乙丙丁戊己").apply {
            setSpan(StyleSpan(Typeface.BOLD), 0, 4, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(RelativeSizeSpan(1.5f), 2, 6, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

        val spans = CjkTextContent(source, base).content.spans

        assertEquals(
            listOf(
                TextSpan(TextRange(0, 2), base.copy(fontWeight = 700)),
                TextSpan(TextRange(2, 4), base.copy(fontWeight = 700, fontSize = 30f)),
                TextSpan(TextRange(4, 6), base.copy(fontSize = 30f)),
            ),
            spans,
        )
    }

    @Test
    fun reportsSpansTheFrontendCannotPreserve() {
        val source = SpannableString("报告未保真区间").apply {
            setSpan(QuoteSpan(), 0, 2, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) = Unit
                },
                2,
                3,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            setSpan(
                ImageSpan(InstrumentationRegistry.getInstrumentation().targetContext, android.R.drawable.ic_delete),
                3,
                4,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            setSpan(ScaleXSpan(2f), 4, 5, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

        val compatibility = source.cjkSpannedCompatibility()

        assertEquals(
            setOf(
                CjkSpannedCapabilityIssue.ParagraphSpans,
                CjkSpannedCapabilityIssue.ClickableSpanCallbacks,
                CjkSpannedCapabilityIssue.ReplacementSpans,
                CjkSpannedCapabilityIssue.UnknownSpans,
            ),
            compatibility.issues,
        )
        // Lowering still accepts the input and keeps the source text.
        assertEquals("报告未保真区间", CjkTextContent(source).content.text)
    }
}
