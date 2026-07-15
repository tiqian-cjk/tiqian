package org.tiqian.shaping.web

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import org.tiqian.core.Rect

class WebCanvasTextShaperTest {

    @Test
    fun clampsSubpixelPunctuationOverhangAtBothAdvanceEdges() {
        val normalized = normalizeSubpixelCanvasInkOverhang(
            bounds = Rect(left = -0.46f, top = -12f, right = 18.46f, bottom = 2f),
            advance = 18f,
        )

        assertEquals(0f, normalized.bounds.left)
        assertEquals(18f, normalized.bounds.right)
        assertEquals(-12f, normalized.bounds.top)
        assertEquals(2f, normalized.bounds.bottom)
        assertNotNull(normalized.adjustment)
    }

    @Test
    fun preservesRealCanvasInkOverhangAtOrAboveOnePixel() {
        val normalized = normalizeSubpixelCanvasInkOverhang(
            bounds = Rect(left = -1f, top = -12f, right = 19.25f, bottom = 2f),
            advance = 18f,
        )

        assertEquals(-1f, normalized.bounds.left)
        assertEquals(19.25f, normalized.bounds.right)
        assertNull(normalized.adjustment)
    }

    @Test
    fun leavesContainedCanvasInkBoundsUntouched() {
        val bounds = Rect(left = 0.5f, top = -12f, right = 17.5f, bottom = 2f)

        val normalized = normalizeSubpixelCanvasInkOverhang(bounds, advance = 18f)

        assertEquals(bounds, normalized.bounds)
        assertNull(normalized.adjustment)
    }

    @Test
    fun onlyEllipsisDisplayReplacementRequiresExactCoverageEvidence() {
        assertEquals(true, isUnverifiedEllipsisDisplaySubstitution("……", "⋯⋯"))
        assertEquals(false, isUnverifiedEllipsisDisplaySubstitution("……", "……"))
        assertEquals(false, isUnverifiedEllipsisDisplaySubstitution("——", "⸺"))
        assertEquals(false, isUnverifiedEllipsisDisplaySubstitution("…", "⋯⋯"))
    }
}
