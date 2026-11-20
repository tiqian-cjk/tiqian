package org.tiqian.shaping.android.nativefont

import kotlin.test.Test
import kotlin.test.assertEquals
import org.tiqian.shaping.ReplayableFontFaceRequest
import org.tiqian.font.FontRole

class AndroidPlatformFontOracleContractTest {
    @Test
    fun cjkPunctuationUsesTheHanFaceProbeInsteadOfTheSharedCharacter() {
        for (punctuation in listOf("“", "”", "‘", "’", "—", "——")) {
            assertEquals(
                "中",
                platformFaceProbeText(
                    ReplayableFontFaceRequest(
                        role = FontRole.CjkPunctuation,
                        preferredFamilies = mutableListOf(),
                        fontSize = 32f,
                        weight = 400,
                        italic = false,
                        locale = "zh-Hans",
                        selectionText = punctuation,
                    ),
                ),
                punctuation,
            )
        }
    }

    @Test
    fun platformOverridesReplaceOnlyTheirCorrespondingAxes() {
        assertEquals(
            mapOf(
                "ital" to 1f,
                "opsz" to 32f,
                "wdth" to 100f,
                "wght" to 412f,
            ),
            applyPlatformStyleOverrides(
                fontAxes = mapOf(
                    "opsz" to 32f,
                    "wdth" to 100f,
                    "wght" to 400f,
                ),
                overrides = PlatformStyleOverrides(weight = 412f, italic = 1f),
            ),
        )
    }

    @Test
    fun absentOverridesPreserveTheCompleteReportedAxisInstance() {
        val axes = mapOf("opsz" to 14f, "wdth" to 75f, "wght" to 310f)

        assertEquals(
            axes.toSortedMap(),
            applyPlatformStyleOverrides(axes, PlatformStyleOverrides()),
        )
    }

    @Test
    fun syntheticItalicIsPartOfTheReplayInstanceIdentity() {
        val physical = "tiqian-font:sha256:abc:0:axes="

        assertEquals(
            physical,
            platformReplayFaceId(physical, syntheticBold = false, syntheticItalic = false),
        )
        assertEquals(
            "tiqian-font:sha256:abc:0:axes=:syntheticItalic=-0.25",
            platformReplayFaceId(physical, syntheticBold = false, syntheticItalic = true),
        )
        assertEquals(
            "tiqian-font:sha256:abc:0:axes=:syntheticBold=platform:syntheticItalic=-0.25",
            platformReplayFaceId(physical, syntheticBold = true, syntheticItalic = true),
        )
    }
}
