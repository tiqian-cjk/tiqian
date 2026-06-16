package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Unit-level checks for the CLREQ stretch tiers, focused on the 中西间距
 * (tier ②) and the `TypedSinoWesternSpaceStretches` fix: an author-typed
 * U+0020 between an ideograph and a Latin word is the sino-western gap and
 * must stretch in tier ②, equally with a virtual CJK↔Latin boundary —
 * otherwise it falls through every tier and the line stretches unevenly.
 */
class JustifierTest {

    private val em = 16f
    private fun cjk(at: Int) = Cluster(TextRange(at, at + 1), "中", fontKey = "cjk", advance = em)
    private fun space(at: Int) = Cluster(TextRange(at, at + 1), " ", fontKey = "latin", advance = 0.25f * em)
    private fun latin(at: Int, w: Float) = Cluster(TextRange(at, at + 2), "Hi", fontKey = "latin", advance = w)

    @Test
    fun typedSinoWesternSpaceStretchesInTierTwo() {
        // 中 ⎵ Hi  — one ideograph, a typed space (0.25em), a Latin word.
        val clusters = listOf(cjk(0), space(1), latin(2, 2f * em))
        val roles = listOf(FontRole.CjkText, FontRole.LatinText, FontRole.LatinText)
        val natural = clusters.sumOf { it.advance.toDouble() }.toFloat() // 16+4+32 = 52
        val plan = Justifier().justify(
            adjustedClusters = clusters,
            clusterRoles = roles,
            lineClusterRange = clusters.indices,
            maxWidth = natural + 0.2f * em, // small deficit, within the gap's headroom
            fontSize = em,
            skip = false,
        )

        assertEquals(0f, plan.unfilledDeficit)
        val alloc = plan.allocations.single()
        // …landed on the typed space (index 1) as a CjkLatinSpace stretch,
        // not on a boundary and not unfilled.
        assertEquals(1, alloc.targetClusterIndex)
        assertEquals(GlueKind.CjkLatinSpace, alloc.kind)
        assertEquals(0.2f * em, alloc.delta, 0.001f)
    }

    @Test
    fun typedSinoWesternSpaceIsCappedAtHalfEm() {
        // A huge deficit: the typed space stretches only to 0.5em (+0.25em over
        // its 0.25em base); the rest falls to the CJK inter-char tier.
        val clusters = listOf(cjk(0), space(1), latin(2, 2f * em), cjk(3), cjk(4))
        val roles = listOf(
            FontRole.CjkText, FontRole.LatinText, FontRole.LatinText,
            FontRole.CjkText, FontRole.CjkText,
        )
        val natural = clusters.sumOf { it.advance.toDouble() }.toFloat()
        val plan = Justifier().justify(
            adjustedClusters = clusters,
            clusterRoles = roles,
            lineClusterRange = clusters.indices,
            maxWidth = natural + 2f * em,
            fontSize = em,
            skip = false,
        )

        // Two 中西间距 share tier ②: the typed space (idx 1) and the virtual
        // Hi↔中 boundary (idx 2). Both stretch by the SAME 0.25em to the 0.5em
        // cap (同时、同等量); the overflow falls to the CJK inter-char tier.
        val sino = plan.allocations.filter { it.kind == GlueKind.CjkLatinSpace }
        assertEquals(setOf(1, 2), sino.map { it.targetClusterIndex }.toSet())
        sino.forEach { assertEquals(0.25f * em, it.delta, 0.001f) }
        assertTrue(plan.allocations.any { it.kind == GlueKind.CjkInterChar }, "overflow spills to inter-char")
        assertEquals(0f, plan.unfilledDeficit)
    }
}
