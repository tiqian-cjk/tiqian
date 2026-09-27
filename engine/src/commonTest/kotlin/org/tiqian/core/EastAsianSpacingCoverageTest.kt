package org.tiqian.core

import org.tiqian.core.TiqianIllegalArgumentException

import kotlin.test.Test
import org.tiqian.test.trace.assertEquals
import org.tiqian.test.trace.assertFailsWith
import org.tiqian.test.trace.assertFalse
import org.tiqian.test.trace.assertNotNull
import org.tiqian.test.trace.assertTrue
import kotlin.test.AfterTest
import org.tiqian.test.trace.TestTraceRecorder

// A lone surrogate written inside a string literal is replaced with '?' when
// the JS test bundle re-serializes its sources, so inputs that carry one are
// built from char codes at runtime to keep the code unit intact everywhere.
private fun surrogateText(vararg codes: Int): String =
    CharArray(codes.size) { codes[it].toChar() }.concatToString()

class EastAsianSpacingCoverageTest {
    private val testTrace = TestTraceRecorder("EastAsianSpacingCoverageTest")


    @Test
    fun testUnicodeWordCharacter() {
        testTrace.section("testUnicodeWordCharacter")
        assertEquals("17.0.0", UnicodeWordCharacter.DATA_REVISION)
        assertTrue(UnicodeWordCharacter.DATA_SOURCE.isNotEmpty())
        assertTrue(UnicodeWordCharacter.DATA_SHA256.isNotEmpty())

        assertFailsWith<TiqianIllegalArgumentException> {
            UnicodeWordCharacter.contains(-1)
        }
        assertFailsWith<TiqianIllegalArgumentException> {
            UnicodeWordCharacter.contains(0x110000)
        }
        assertFailsWith<TiqianIllegalArgumentException> {
            UnicodeWordCharacter.contains(0xD800)
        }
        assertFailsWith<TiqianIllegalArgumentException> {
            UnicodeWordCharacter.contains(0xDFFF)
        }

        assertTrue(UnicodeWordCharacter.contains('A'.code))
        assertTrue(UnicodeWordCharacter.contains('中'.code))
        assertFalse(UnicodeWordCharacter.contains(' '.code))
        assertFalse(UnicodeWordCharacter.contains('!'.code))
    }

    @Test
    fun testUnicodeScriptEvidence() {
        testTrace.section("testUnicodeScriptEvidence")
        for (item in UnicodeScriptEvidence.entries) {
            assertNotNull(UnicodeScriptEvidence.valueOf(item.name))
        }

        assertEquals("17.0.0", UnicodeScriptEvidenceClassifier.DATA_REVISION)
        assertTrue(UnicodeScriptEvidenceClassifier.DATA_SOURCE.isNotEmpty())
        assertTrue(UnicodeScriptEvidenceClassifier.DATA_SHA256.isNotEmpty())

        assertFailsWith<IllegalArgumentException> {
            UnicodeScriptEvidenceClassifier.classify(-1)
        }
        assertFailsWith<IllegalArgumentException> {
            UnicodeScriptEvidenceClassifier.classify(0x110000)
        }
        assertFailsWith<IllegalArgumentException> {
            UnicodeScriptEvidenceClassifier.classify(0xD800)
        }
        assertFailsWith<IllegalArgumentException> {
            UnicodeScriptEvidenceClassifier.classify(0xDFFF)
        }

        assertEquals(UnicodeScriptEvidence.EastAsian, UnicodeScriptEvidenceClassifier.classify(0x4E00))
        assertEquals(UnicodeScriptEvidence.Other, UnicodeScriptEvidenceClassifier.classify(0x0041))
        assertEquals(UnicodeScriptEvidence.Neutral, UnicodeScriptEvidenceClassifier.classify(0x0020))
    }

    @Test
    fun testEastAsianSpacingDataAndValues() {
        testTrace.section("testEastAsianSpacingDataAndValues")
        for (value in EastAsianSpacingValue.entries) {
            assertNotNull(EastAsianSpacingValue.valueOf(value.name))
        }

        // Test EastAsianSpacingData lookup
        assertEquals(EastAsianSpacingValue.Wide, EastAsianSpacingData.lookup(0x02C7))
        assertEquals(EastAsianSpacingValue.Narrow, EastAsianSpacingData.lookup(0x0030))
        assertEquals(EastAsianSpacingValue.Conditional, EastAsianSpacingData.lookup(0x0021))
        assertEquals(EastAsianSpacingValue.Other, EastAsianSpacingData.lookup(0x0000))
        assertEquals(EastAsianSpacingValue.Other, EastAsianSpacingData.lookup(0x10FFFF))
    }

    @Test
    fun testEastAsianSpacingEdgesModel() {
        testTrace.section("testEastAsianSpacingEdgesModel")
        val edges = EastAsianSpacingEdges(
            leading = EastAsianSpacingValue.Wide,
            trailing = EastAsianSpacingValue.Narrow,
            containsWide = true,
        )
        assertEquals(EastAsianSpacingValue.Wide, edges.leading)
        assertEquals(EastAsianSpacingValue.Narrow, edges.trailing)
        assertTrue(edges.containsWide)
        assertEquals(edges, edges.copy())
        assertTrue(edges.hashCode() == edges.copy().hashCode())
        assertTrue(edges.toString().contains("EastAsianSpacingEdges"))
    }

    @Test
    fun testUnicodeEastAsianSpacing() {
        testTrace.section("testUnicodeEastAsianSpacing")
        assertEquals("draft-2024-12-16", UnicodeEastAsianSpacing.DATA_REVISION)
        assertTrue(UnicodeEastAsianSpacing.DATA_SOURCE.isNotEmpty())
        assertTrue(UnicodeEastAsianSpacing.DATA_SHA256.isNotEmpty())
        assertEquals("2026-06-14", UnicodeEastAsianSpacing.LANGUAGE_REGISTRY_REVISION)
        assertTrue(UnicodeEastAsianSpacing.LANGUAGE_REGISTRY_SOURCE.isNotEmpty())

        // Chinese language context checking
        val chineseLocales = listOf(
            "zh", "zh-Hans", "zh-Hant", "zh-CN", "zh_TW", "cdo", "cjy", "cmn", "cnp", "cpx",
            "csp", "czh", "czo", "gan", "hak", "hnm", "hsn", "luh", "lzh", "mnp", "nan",
            "sjc", "wuu", "yue", "yue-HK", "cmn-Hans-CN",
        )
        for (loc in chineseLocales) {
            assertTrue(UnicodeEastAsianSpacing.isChineseLanguageContext(loc), "Locale $loc should be Chinese")
        }

        val nonChineseLocales = listOf("en", "en-US", "ja", "ko", "fr", "de", "es")
        for (loc in nonChineseLocales) {
            assertFalse(UnicodeEastAsianSpacing.isChineseLanguageContext(loc), "Locale $loc should not be Chinese")
        }

        // propertyOf validation
        assertFailsWith<IllegalArgumentException> { UnicodeEastAsianSpacing.propertyOf(-1) }
        assertFailsWith<IllegalArgumentException> { UnicodeEastAsianSpacing.propertyOf(0x110000) }
        assertFailsWith<IllegalArgumentException> { UnicodeEastAsianSpacing.propertyOf(0xD800) }
        assertFailsWith<IllegalArgumentException> { UnicodeEastAsianSpacing.propertyOf(0xDFFF) }

        // resolvedForGraphemeCluster
        assertEquals(EastAsianSpacingValue.Other, UnicodeEastAsianSpacing.resolvedForGraphemeCluster("", "zh"))
        assertEquals(
            EastAsianSpacingValue.Other,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("A\u20DD", "zh"), // Enclosing mark
        )
        assertEquals(
            EastAsianSpacingValue.Narrow,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("!", "zh-CN"), // Conditional in Chinese
        )
        assertEquals(
            EastAsianSpacingValue.Other,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("!", "en-US"), // Conditional in non-Chinese
        )
        assertEquals(
            EastAsianSpacingValue.Wide,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("中", "zh"),
        )
        assertEquals(
            EastAsianSpacingValue.Narrow,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("A", "zh"),
        )
        assertEquals(
            EastAsianSpacingValue.Other,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("\u0000", "zh"),
        )

        // resolvedEdges
        val emptyEdges = UnicodeEastAsianSpacing.resolvedEdges("", "zh")
        assertEquals(EastAsianSpacingValue.Other, emptyEdges.leading)
        assertEquals(EastAsianSpacingValue.Other, emptyEdges.trailing)
        assertFalse(emptyEdges.containsWide)

        val mixedEdges = UnicodeEastAsianSpacing.resolvedEdges("中a文", "zh")
        assertEquals(EastAsianSpacingValue.Wide, mixedEdges.leading)
        assertEquals(EastAsianSpacingValue.Wide, mixedEdges.trailing)
        assertTrue(mixedEdges.containsWide)

        val westernEdges = UnicodeEastAsianSpacing.resolvedEdges("hello", "en")
        assertEquals(EastAsianSpacingValue.Narrow, westernEdges.leading)
        assertEquals(EastAsianSpacingValue.Narrow, westernEdges.trailing)
        assertFalse(westernEdges.containsWide)

        // Grapheme cluster with surrogate pairs
        assertEquals(
            EastAsianSpacingValue.Other,
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster("\uD83D\uDE00", "zh"), // Emoji (Other)
        )

        // Invalid surrogate in resolvedForGraphemeCluster throws IllegalArgumentException
        assertFailsWith<IllegalArgumentException> {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800), "zh")
        }
        assertFailsWith<IllegalArgumentException> {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800, 'A'.code), "zh") // low < 0xDC00
        }
        assertFailsWith<IllegalArgumentException> {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800, 0xE000), "zh") // low > 0xDFFF
        }
    }

    @AfterTest
    fun flushTestTrace() {
        testTrace.flush()
    }
}