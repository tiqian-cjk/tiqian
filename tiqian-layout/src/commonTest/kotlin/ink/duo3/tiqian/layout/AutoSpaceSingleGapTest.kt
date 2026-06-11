package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `text-autospace: replace` per CSS Text 4 + ADR 0009 must collapse ALL
 * typed U+0020 at a CJK ↔ Latin boundary into a SINGLE autospace gap of
 * `gapEm × fontSize`, regardless of how many spaces the author typed.
 *
 * The earlier implementation multiplied the gap by the typed-space count
 * (`count × gapEm × fontSize`), so doubling the typed spaces also doubled
 * the boundary width. That violates the spec and the project's intent.
 */
class AutoSpaceSingleGapTest {

    @Test
    fun oneTypedSpaceBecomesOneAutospaceGap() {
        // `中文 CJK 段落` — LatinWordSegmentation makes each space its own
        // cluster. CJK-adjacent space clusters ARE the sino-western gap:
        // their advance normalises from 1em (stub) to 0.25em.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val spaces = result.clusters.filter { it.text == " " }
        assertEquals(2, spaces.size)
        assertTrue(spaces.all { it.advance == 4f })
        val word = result.clusters.single { it.text == "CJK" }
        assertEquals(48f, word.advance)
    }

    @Test
    fun twoTypedSpacesAtBoundaryStillCollapseToOneGap() {
        // `中文  CJK 段落` — the 2-space run is ONE cluster and still
        // normalises to a single 0.25em gap, same as one typed space.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文  CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val doubleSpace = result.clusters.single { it.text == "  " }
        assertEquals(4f, doubleSpace.advance)
        val singleSpace = result.clusters.single { it.text == " " }
        assertEquals(4f, singleSpace.advance)
    }

    @Test
    fun threeTypedSpacesStillOneGap() {
        // 3 leading spaces, 0 trailing — the 3-space run normalises to one
        // 4 px gap, and the space-less trailing boundary CJK→段 gains an
        // Insert gap inside the word cluster (48 + 4 = 52).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文   CJK段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val tripleSpace = result.clusters.single { it.text == "   " }
        assertEquals(4f, tripleSpace.advance)
        val word = result.clusters.single { it.text == "CJK" }
        assertEquals(52f, word.advance)
    }

    @Test
    fun zeroSpacesGetInsertedQuarterEmGaps() {
        // TextAutoSpaceInsert (CLREQ:「汉字与西文字母、数字间使用不多于四分
        // 之一个汉字宽的字距或空白」): boundaries WITHOUT typed spaces gain
        // a 0.25em gap on each side. "CJK" nominal 48 → 48 + 4 + 4 = 56.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文CJK段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val cluster = result.clusters.single { it.text == "CJK" }
        assertEquals(56f, cluster.advance)

        val decisions = result.debug.autoSpaceDecisions
        assertEquals(2, decisions.size)
        assertTrue(decisions.all { it.mode == "Insert" && it.charactersAffected == 0 })
        assertTrue(decisions.all { it.totalReduction == -4f })
        assertTrue(decisions.all { it.reason.startsWith("TextAutoSpaceInsert") })
    }

    @Test
    fun autospaceDoesNotFireBetweenLatinAndCjkPunctuation() {
        // Per CSS Text 4, `text-autospace` fires at ideograph ↔ alpha/numeric
        // boundaries only. Punctuation has its own spacing model. The text
        // `Tiqian ）说明` has a typed space between Latin and a closing
        // bracket: there must be no autospace decision for that boundary.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("Tiqian ）说明"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        // The boundary at the right of the Latin cluster is CjkPunctuation
        // (the closing bracket), which should NOT trigger autospace. The
        // left of the Latin cluster is text boundary, also no autospace.
        assertEquals(0, result.debug.autoSpaceDecisions.size)
    }

    @Test
    fun autospaceStillFiresBetweenLatinAndCjkTextEvenWithPunctuationNearby() {
        // The boundary is between Latin "shaping" and the CjkText `之`. The
        // closing bracket `）` next to it does not cancel the firing.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文 shaping 之后"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        assertEquals(2, result.debug.autoSpaceDecisions.size) // one per space cluster
        assertTrue(result.debug.autoSpaceDecisions.all { it.boundaryRole == "CjkText" })
        assertTrue(result.debug.autoSpaceDecisions.all { it.side == "gap" })
    }
}
