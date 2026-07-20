package org.tiqian.layout

import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.TextRange
import org.tiqian.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `BilingualEmphasisWesternItalic` (着重号惯例): inside an Emphasis span, Han
 * clusters carry dots, Western clusters do NOT (they shape italic instead). This
 * pins the dot side — the same Latin∩Emphasis predicate drives the italic.
 */
class BilingualEmphasisTest {

    @Test
    fun emphasisDotsHanButNotWestern() {
        // 强调[中A中] — Emphasis over offsets 2..5 (中=2, A=3, 中=4).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("强调中A中"),
                constraints = LayoutConstraints(maxWidth = 400f),
                decorations = listOf(DecorationSpan(TextRange(2, 5), DecorationKind.Emphasis)),
            ),
        )
        val byStart = result.debug.decorationDecisions.associateBy { it.clusterRange.start }

        assertTrue(byStart.getValue(2).applied, "Han 中 gets a 着重号 dot")
        assertTrue(byStart.getValue(4).applied, "Han 中 gets a 着重号 dot")
        // Western A inside the span: no dot — it is italicised at shaping instead.
        val western = byStart.getValue(3)
        assertTrue(!western.applied, "Western A must not get a dot")
        assertEquals("no-dot-on-non-han", western.reason)
        assertEquals(0f, western.dotDiameter)
    }
}
