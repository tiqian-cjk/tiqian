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
        // `中文 CJK 段落` — 1 space on each Latin-CJK boundary.
        // Stub assigns 1em per typed space; gapEm=0.25; fontSize=16.
        // Each space worth 16 collapsed to a single 4 → reduction 12 per boundary.
        // " CJK " cluster nominal = 5*16=80; after 2 boundary collapses = 80 - 12 - 12 = 56.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val cluster = result.clusters.single { it.text == " CJK " }
        assertEquals(56f, cluster.advance)
    }

    @Test
    fun twoTypedSpacesAtBoundaryStillCollapseToOneGap() {
        // `中文  CJK 段落` — 2 leading spaces, 1 trailing space.
        // Leading: 2 typed * 16 = 32 → collapsed to ONE 4 gap = reduction 28.
        // Trailing: 1 typed * 16 = 16 → ONE 4 gap = reduction 12.
        // Cluster nominal = 6*16=96; after collapses = 96 - 28 - 12 = 56.
        // Crucially: same 56 px regardless of typed space count on leading side.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文  CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val cluster = result.clusters.single { it.text == "  CJK " }
        assertEquals(56f, cluster.advance)
    }

    @Test
    fun threeTypedSpacesStillOneGap() {
        // 3 leading spaces, 0 trailing — boundary still gets ONE 4 px gap.
        // Cluster `   CJK段落` doesn't exist as "段落" follows directly.
        // Use `中文   CJK段落`: leading 3 typed × 16 = 48, replaced by 1 × 4. Reduction 44.
        // Cluster nominal = 6*16 = 96 (3 spaces + "CJK"); after collapse = 96 - 44 = 52.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文   CJK段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val cluster = result.clusters.single { it.text == "   CJK" }
        assertEquals(52f, cluster.advance)
    }

    @Test
    fun zeroSpacesProducesNoAutospaceDecision() {
        // No typed spaces → no autospace decision. Different from above.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文CJK段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        assertEquals(0, result.debug.autoSpaceDecisions.size)
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
        assertEquals(2, result.debug.autoSpaceDecisions.size) // leading + trailing
        assertTrue(result.debug.autoSpaceDecisions.all { it.boundaryRole == "CjkText" })
        assertTrue(result.debug.autoSpaceDecisions.all { it.reason.contains("ideograph-alpha") })
    }
}
