package org.tiqian.demo.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.android.view.cjkSpannedCompatibility
import org.tiqian.core.ColorSpan
import org.tiqian.core.Link
import org.tiqian.core.Underline
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class TiqianViewDemoDocumentTest {
    @Test
    fun articleParagraphLowersCleanlyFromPlatformRichText() {
        val source = tiqianViewDemoParagraphSource(index = 0)
        assertTrue(source.cjkSpannedCompatibility().canPreserveAllKnownSemantics)

        val paragraph = tiqianViewDemoParagraph(index = 0, textSize = 17f, lineHeight = 27f)
        val link = paragraph.richTextSpans.single { it.role is Link }
        val underline = paragraph.richTextSpans.single { it.role == Underline.instance }

        assertEquals(link.range, underline.range)
        assertEquals(
            listOf(ColorSpan(link.range.start, link.range.end, VIEW_DEMO_LINK_COLOR)),
            paragraph.colorSpans,
        )
        assertTrue(paragraph.content.spans.any { it.style.fontWeight == 700 })
        assertTrue(paragraph.content.spans.any { it.style.italic })
    }
}
