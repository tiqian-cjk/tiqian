package org.tiqian.font

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Guards `LatinVsCjkFaceSelection` — the single rule shaping, metrics, and rendering
 * share to pick the Latin vs CJK face. If it drifts, a missing glyph measured in one
 * face but drawn in the other overflows its slot.
 */
class UsesLatinFaceTest {
    @Test
    fun onlyLatinTextUsesLatinFace() {
        assertTrue(FontRole.LatinText.usesLatinFace())
        FontRole.entries.filter { it != FontRole.LatinText }.forEach {
            assertFalse(it.usesLatinFace(), "$it must fall back to the CJK face")
        }
    }

    @Test
    fun nameOverloadAgreesWithEnum() {
        FontRole.entries.forEach { role ->
            assertEquals(
                role.usesLatinFace(),
                fontRoleNameUsesLatinFace(role.name),
                "name overload must match the enum for $role",
            )
        }
        assertFalse(fontRoleNameUsesLatinFace(null))
        assertFalse(fontRoleNameUsesLatinFace("NotARole"))
    }
}
