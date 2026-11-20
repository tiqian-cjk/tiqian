package org.tiqian.compose

import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.font.FontRole
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Real Desktop Skia coverage for contextual U+2014/U+2026 face selection. */
class ContextualDashEllipsisRoleTest {
    private val engine = ExplainableStubParagraphLayoutEngine(
        textShaper = SkiaTextShaper(),
        fontMetricsResolver = SkiaFontMetricsResolver(),
    )

    @Test
    fun westernMarkCountDoesNotSwitchToTheCjkFace() {
        val text = "English — next; ellipsis… A——B; Wait……what?"
        val result = layout(text)

        text.markIndices().forEach { index ->
            val decision = result.fontDecisionAt(index)
            assertEquals(FontRole.LatinText.name, decision.role, "index=$index $decision")
            assertEquals(decision.sourceText, decision.displayText, "index=$index $decision")
        }
        assertTrue(result.debug.punctuationDecisions.none { it.char == "—" || it.char == "…" })
        assertTrue(
            result.debug.shapingDecisions
                .filter { it.sourceText.any { char -> char.isContextualDashOrEllipsis() } }
                .all { it.source == "Skia" && it.missingGlyphs == 0 },
            result.debug.shapingDecisions.toString(),
        )
    }

    @Test
    fun cjkMarkCountDoesNotSwitchToTheLatinFace() {
        val text = "中文—下句；等…真；中文——下句；省略号……。"
        val result = layout(text)

        text.markIndices().forEach { index ->
            assertEquals(FontRole.CjkPunctuation.name, result.fontDecisionAt(index).role)
        }
        assertTrue(result.debug.punctuationDecisions.any { it.char == "—" })
        assertTrue(result.debug.punctuationDecisions.any { it.char == "…" || it.char == "⋯" })
        assertTrue(
            result.debug.shapingDecisions
                .filter { it.sourceText.any { char -> char.isContextualDashOrEllipsis() } }
                .all { it.source == "Skia" },
            result.debug.shapingDecisions.toString(),
        )
    }

    private fun layout(text: String): LayoutResult = engine.layout(
        LayoutInput(
            content = TiqianTextContent(text),
            textStyle = TextStyle(locale = "zh-Hans"),
            paragraphStyle = ParagraphStyle(firstLineIndent = org.tiqian.core.Ic(0f)),
            constraints = LayoutConstraints(maxWidth = 1000f),
        ),
    )

    private fun String.markIndices(): List<Int> = indices.filter { this[it].isContextualDashOrEllipsis() }

    private fun Char.isContextualDashOrEllipsis(): Boolean = this == '—' || this == '…'

    private fun LayoutResult.fontDecisionAt(index: Int) = debug.fontDecisions.single { decision ->
        index >= decision.range.start && index < decision.range.end
    }
}
