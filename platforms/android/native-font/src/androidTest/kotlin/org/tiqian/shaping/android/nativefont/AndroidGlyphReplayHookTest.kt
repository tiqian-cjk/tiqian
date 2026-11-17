package org.tiqian.shaping.android.nativefont

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.Glyph
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import org.tiqian.shaping.ReplayableFontFaceRequest
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.android.AndroidGlyphReplayRegistry
import java.io.File
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidGlyphReplayHookTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun installingACatalogRegistersTheNativeGlyphReplay() {
        val cjk = cjkFontFile()
        assumeTrue("No system CJK font", cjk != null)
        try {
            TiqianAndroidFontBackend.install(context, AndroidFontCatalog.host(listOf(cjkSpec(cjk!!))))
            assertTrue(AndroidNativeGlyphReplay in AndroidGlyphReplayRegistry.registered)

            val shaped = AndroidNativeTextShaper(context).shape(input("中文", FontRole.CjkText, 32f))
            val glyphs = shaped.glyphRuns.single().glyphs
            val key = checkNotNull(glyphs.first().renderFontKey)
            val replay = checkNotNull(AndroidGlyphReplayRegistry.replayFor(key))
            assertSame(AndroidNativeGlyphReplay, replay)
            assertTrue(replay.ownsFont(key))
            assertNull(replay.platformFont(key))

            val bitmap = Bitmap.createBitmap(120, 60, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF000000.toInt() }
            assertTrue(replay.drawGlyphs(Canvas(bitmap), glyphs, 4f, 44f, 32f, paint, Path()))
            assertTrue(inkPixels(bitmap) > 0, "Replay through the hook produced no ink")
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun mixedCoverageFamilyFallsToNextFamilyAtTheMatchedStyle() {
        val cjk = cjkFontFile()
        val roboto = File("/system/fonts/Roboto-Regular.ttf")
        assumeTrue("No system CJK font", cjk != null)
        assumeTrue("No Roboto", roboto.isFile)
        // Same file, index and axes share one FontFaceId; the two CJK faces use different indices.
        assumeTrue("System CJK font is not a collection", cjk!!.name.endsWith(".ttc"))
        val bodyIndex = 2
        val fallbackIndex = 0
        val allRoles = FontRole.entries.toSet()
        try {
            val report = TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    faceSpecs = listOf(
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(roboto),
                            familyKey = "body",
                            familyAliases = setOf("body"),
                            roles = allRoles,
                            weight = 400,
                        ),
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(cjk),
                            collectionIndex = bodyIndex,
                            familyKey = "body",
                            familyAliases = setOf("body"),
                            roles = allRoles,
                            weight = 700,
                        ),
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(cjk),
                            collectionIndex = fallbackIndex,
                            familyKey = "fallback",
                            familyAliases = setOf("fallback"),
                            roles = allRoles,
                            weight = 400,
                        ),
                    ),
                    fallbackChains = FontRole.entries.associateWith { listOf("body", "fallback") },
                ),
            )
            val bodyBoldId = report.faces
                .first { it.sourceLabel == cjk.absolutePath && it.collectionIndex == bodyIndex && it.weight == 700 }
                .id.value
            val fallbackId = report.faces
                .first { it.sourceLabel == cjk.absolutePath && it.collectionIndex == fallbackIndex && it.weight == 400 }
                .id.value
            assertNotEquals(bodyBoldId, fallbackId, "the two CJK faces must be distinguishable")

            val shaper = AndroidNativeTextShaper(context)
            val atRegular = shaper.shape(input("中", FontRole.CjkText, 32f, fontWeight = 400)).glyphRuns.single().glyphs
            assertEquals(
                fallbackId,
                checkNotNull(atRegular.first().renderFontKey),
                "the body's weight-400 matched face (Latin) does not cover Han, so the fallback family wins",
            )
            val atBold = shaper.shape(input("中", FontRole.CjkText, 32f, fontWeight = 700)).glyphRuns.single().glyphs
            assertEquals(
                bodyBoldId,
                checkNotNull(atBold.first().renderFontKey),
                "the body's weight-700 matched face covers Han, so the body family wins",
            )
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun systemCatalogIsDiscoverableWithoutInstalling() {
        val revisionBefore = TiqianAndroidFontBackend.catalogRevision(context)
        val catalog = AndroidFontCatalog.system(context)
        assertTrue(catalog.faceSpecs.isNotEmpty(), "system catalog must declare faces")
        assertTrue(catalog.fallbackChains.containsKey(FontRole.CjkText), "system catalog must chain CjkText")
        assertTrue(catalog.fallbackChains.containsKey(FontRole.LatinText), "system catalog must chain LatinText")
        assertTrue(catalog.sourceKind.isNotBlank(), "system catalog must name its source kind")
        assertEquals(
            revisionBefore,
            TiqianAndroidFontBackend.catalogRevision(context),
            "discovery must not install a catalog",
        )
    }

    @Test
    fun opticalSizeFollowsFontSizeWithinTheDeclaredAxisRange() {
        val cjk = cjkFontFile()
        val flex = File("/system/fonts/RobotoFlex-Regular.ttf")
        assumeTrue("No system CJK font", cjk != null)
        assumeTrue("No Roboto Flex", flex.isFile)
        try {
            val report = TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    listOf(
                        cjkSpec(cjk!!),
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(flex),
                            familyKey = "flex",
                            familyAliases = setOf("roboto flex"),
                            roles = setOf(FontRole.LatinText),
                            opticalSize = AndroidOpticalSizeRule(pointsPerPixel = 1f),
                        ),
                    ),
                ),
            )
            assertTrue(report.issues.none { it.code == "OpticalSizeAxisUnavailable" }, report.toString())
            val before = TiqianAndroidFontBackend.resourceStatsForTesting()

            val small = resolveLatin(12f)
            val large = resolveLatin(72f)
            val range = checkNotNull(small.nativeFace.axisRange("opsz"))
            val huge = resolveLatin(range.endInclusive * 4f)
            assertEquals(12f, small.descriptor.variationAxes["opsz"])
            assertEquals(72f, large.descriptor.variationAxes["opsz"])
            assertEquals(range.endInclusive, huge.descriptor.variationAxes["opsz"])
            assertNotEquals(small.descriptor.id, large.descriptor.id)
            assertEquals(12f, resolveLatin(12.1f).descriptor.variationAxes["opsz"])
            assertEquals(13f, resolveLatin(12.6f).descriptor.variationAxes["opsz"])
            assertSame(small.nativeFace, resolveLatin(12f).nativeFace)
            assertSame(small.nativeFace, resolveLatin(12.4f).nativeFace)

            val after = TiqianAndroidFontBackend.resourceStatsForTesting()
            assertEquals(before.sourceCount, after.sourceCount)
            assertTrue(after.faceCount >= before.faceCount + 3, "$before -> $after")

            val shaper = AndroidNativeTextShaper(context)
            val smallAdvance = shaper.shape(latinInput("Hamburgefonstiv", 12f)).clusters.single().advance
            val largeAdvance = shaper.shape(latinInput("Hamburgefonstiv", 72f)).clusters.single().advance
            assertTrue(abs(largeAdvance - smallAdvance * 6f) > 0.5f, "opsz instance did not change the advance: $smallAdvance vs $largeAdvance")
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun opticalSizeRuleWithoutAnOpszAxisIsReportedAndIgnored() {
        val cjk = cjkFontFile()
        assumeTrue("No system CJK font", cjk != null)
        try {
            val report = TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(listOf(cjkSpec(cjk!!).copy(opticalSize = AndroidOpticalSizeRule()))),
            )
            assertTrue(report.issues.any { it.code == "OpticalSizeAxisUnavailable" }, report.toString())
            val resolved = TiqianAndroidFontBackend.resolveFace(context, request(FontRole.CjkText, emptyList(), 24f, "中"))
            assertNull(resolved.descriptor.variationAxes["opsz"])
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun uncoveredTextDegradesToThePlatformTextStack() {
        val cjk = cjkFontFile()
        val latin = File("/system/fonts/Roboto-Regular.ttf")
        assumeTrue("No system CJK font", cjk != null)
        assumeTrue("No Roboto", latin.isFile)
        try {
            TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    listOf(
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(latin),
                            familyKey = "latin",
                            familyAliases = setOf("roboto"),
                            roles = setOf(FontRole.CjkText, FontRole.CjkPunctuation, FontRole.LatinText),
                        ),
                        cjkSpec(cjk!!),
                    ),
                    fallbackChains = mapOf(
                        FontRole.CjkText to listOf("latin", "cjk"),
                        FontRole.CjkPunctuation to listOf("latin", "cjk"),
                        FontRole.LatinText to listOf("cjk", "latin"),
                        FontRole.Symbol to listOf("cjk"),
                        FontRole.Unknown to listOf("cjk"),
                    ),
                ),
            )
            val shaper = AndroidNativeTextShaper(context)
            val han = shaper.shape(input("中", FontRole.CjkText, 24f)).decisions.single()
            assertEquals("HarfBuzz", han.source)
            assertEquals(0, han.missingGlyphs)

            val uncovered = shaper.shape(input("\uD83E\uDD14", FontRole.CjkText, 24f))
            val decision = uncovered.decisions.single()
            assertEquals("AndroidPaint", decision.source)
            assertEquals("NoCoveringFacePlatformDegrade", decision.reason)
            assertEquals(NO_COVERING_FACE_STRING_DRAW_ISSUE, decision.capabilityIssue)
            assertTrue(decision.advance > 0f, decision.toString())
            assertNull(uncovered.glyphRuns.single().glyphs.single().renderFontKey)
            assertEquals(cjkSpecId(cjk), checkNotNull(decision.resolvedFace).substringBefore(":axes:"))
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun replayReportsWhichFacesAlreadyProvideTheItalic() {
        val cjk = cjkFontFile()
        val upright = listOf("NotoSerif-Regular.ttf", "Roboto-Regular.ttf").map { File("/system/fonts/$it") }.firstOrNull(File::isFile)
        val italic = listOf("NotoSerif-Italic.ttf", "Roboto-Italic.ttf").map { File("/system/fonts/$it") }.firstOrNull(File::isFile)
        assumeTrue("No system CJK font", cjk != null)
        assumeTrue("No system italic font", upright != null && italic != null)
        try {
            TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    listOf(
                        cjkSpec(cjk!!),
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(upright!!),
                            familyKey = "latin",
                            familyAliases = setOf("serif"),
                            roles = setOf(FontRole.LatinText),
                        ),
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(italic!!),
                            familyKey = "latin",
                            familyAliases = setOf("serif"),
                            roles = setOf(FontRole.LatinText),
                            italic = true,
                        ),
                    ),
                ),
            )
            val shaper = AndroidNativeTextShaper(context)
            val slanted = shaper.shape(latinInput("Hamburg", 24f, italic = true, family = "serif")).glyphRuns.single().glyphs
            val regular = shaper.shape(latinInput("Hamburg", 24f, family = "serif")).glyphRuns.single().glyphs
            val cjkItalic = shaper.shape(input("中文", FontRole.CjkText, 24f, italic = true)).glyphRuns.single().glyphs
            assertTrue(AndroidNativeGlyphReplay.providesItalic(checkNotNull(slanted.first().renderFontKey)))
            assertTrue(!AndroidNativeGlyphReplay.providesItalic(checkNotNull(regular.first().renderFontKey)))
            assertTrue(
                !AndroidNativeGlyphReplay.providesItalic(checkNotNull(cjkItalic.first().renderFontKey)),
                "an upright CJK face still needs the renderer's slant",
            )
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun platformDefaultChainShapesHanWithSystemFacesAndKeepsHostLatin() {
        val roboto = File("/system/fonts/Roboto-Regular.ttf")
        assumeTrue("No Roboto", roboto.isFile)
        try {
            TiqianAndroidFontBackend.install(context, platformDefaultHostCatalog(roboto))
            val shaper = AndroidNativeTextShaper(context)

            val han = shaper.shape(input("中", FontRole.CjkText, 32f)).glyphRuns.single()
            assertTrue(han.glyphs.isNotEmpty(), "Han run must not be empty")
            val hanKey = checkNotNull(han.glyphs.first().renderFontKey) { "Han glyph must carry a render key" }
            val hanLabel = checkNotNull(TiqianAndroidFontBackend.replayFaceDescriptor(hanKey)).sourceLabel
            assertTrue(
                hanLabel.contains("NotoSansCJK") || !hanLabel.endsWith("Roboto-Regular.ttf"),
                "Han must be shaped with a system CJK face, not the host Roboto: $hanLabel",
            )
            assertTrue(AndroidNativeGlyphReplay.ownsGlyphs(han.glyphs), "system CJK glyphs must be replayable")

            val latin = shaper.shape(input("A", FontRole.LatinText, 32f)).glyphRuns.single()
            val latinKey = checkNotNull(latin.glyphs.first().renderFontKey)
            assertTrue(
                checkNotNull(TiqianAndroidFontBackend.replayFaceDescriptor(latinKey)).sourceLabel.endsWith("Roboto-Regular.ttf"),
                "Latin must stay on the host family",
            )

            val punct = shaper.shape(input("。", FontRole.CjkPunctuation, 32f)).glyphRuns.single()
            assertNotNull(punct.glyphs.first().renderFontKey, "CJK punctuation must resolve to a face")

            val emoji = shaper.shape(input("😀", FontRole.Emoji, 32f))
            assertEquals(1, emoji.glyphRuns.size, "emoji must produce exactly one run")

            val issues = TiqianAndroidFontBackend.capabilityReport(context).issues
            assertTrue(issues.none { it.code == "MissingControlledFontFace" }, issues.toString())
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun platformDefaultChainOnApi31UsesTheOracle() {
        assumeTrue("Requires API 31+ platform read-back", Build.VERSION.SDK_INT >= 31)
        val roboto = File("/system/fonts/Roboto-Regular.ttf")
        assumeTrue("No Roboto", roboto.isFile)
        try {
            TiqianAndroidFontBackend.install(context, platformDefaultHostCatalog(roboto))
            val revisionBefore = TiqianAndroidFontBackend.catalogRevision(context)
            val key = checkNotNull(
                AndroidNativeTextShaper(context).shape(input("中", FontRole.CjkText, 32f))
                    .glyphRuns.single().glyphs.first().renderFontKey,
            )
            val label = checkNotNull(TiqianAndroidFontBackend.replayFaceDescriptor(key)).sourceLabel
            assertFalse(label.startsWith("platform-default:"), label)
            assertFalse(label.startsWith("DeclaredFontConfig:"), label)
            assertEquals(
                revisionBefore,
                TiqianAndroidFontBackend.catalogRevision(context),
                "shaping must not install a new catalog",
            )
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun platformDefaultChainBelowApi31ExpandsDeclaredFamilies() {
        assumeTrue("Requires API < 31 declared-config expansion", Build.VERSION.SDK_INT < 31)
        val roboto = File("/system/fonts/Roboto-Regular.ttf")
        assumeTrue("No Roboto", roboto.isFile)
        try {
            val report = TiqianAndroidFontBackend.install(context, platformDefaultHostCatalog(roboto))
            val key = checkNotNull(
                AndroidNativeTextShaper(context).shape(input("中", FontRole.CjkText, 32f))
                    .glyphRuns.single().glyphs.first().renderFontKey,
            )
            val label = checkNotNull(TiqianAndroidFontBackend.replayFaceDescriptor(key)).sourceLabel
            assertTrue(label.startsWith("DeclaredFontConfig:"), label)
            assertTrue(
                report.issues.any { it.code == "RuntimeFontSelectionUnobservableBelowApi31" },
                report.issues.toString(),
            )
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun strokeSyntheticBoldWhenTheFamilyHasNoBoldFace() {
        val cjk = cjkFontFile()
        assumeTrue("No system CJK font", cjk != null)
        try {
            TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    faceSpecs = listOf(
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(cjk!!),
                            collectionIndex = if (cjk.name.endsWith(".ttc")) 2 else 0,
                            familyKey = "cjk",
                            familyAliases = setOf("sans-serif", "noto sans cjk sc"),
                            roles = FontRole.entries.toSet(),
                            weight = 400,
                        ),
                    ),
                    fallbackChains = FontRole.entries.associateWith { listOf("cjk") },
                ),
            )
            val shaper = AndroidNativeTextShaper(context)

            val bold = shaper.shape(input("中", FontRole.CjkText, 40f, fontWeight = 700))
            val boldRun = bold.glyphRuns.single()
            val boldKey = checkNotNull(boldRun.glyphs.first().renderFontKey)
            val regular = shaper.shape(input("中", FontRole.CjkText, 40f, fontWeight = 400))
            val regularRun = regular.glyphRuns.single()
            val regularKey = checkNotNull(regularRun.glyphs.first().renderFontKey)

            assertTrue(boldKey.endsWith(":syntheticBold=stroke"), boldKey)
            assertTrue(
                checkNotNull(TiqianAndroidFontBackend.replayFaceDescriptor(boldKey))
                    .sourceLabel.endsWith(":syntheticBold=stroke"),
            )
            assertTrue(TiqianAndroidFontBackend.isSyntheticBoldFace(boldKey))
            assertFalse(regularKey.endsWith(":syntheticBold=stroke"), regularKey)
            assertEquals(regularKey + ":syntheticBold=stroke", boldKey, "keys differ only by the stroke suffix")
            assertEquals(regularRun.advance, boldRun.advance, "synthetic bold keeps the same native advance")
            assertTrue(
                bold.decisions.single().reason.contains("FakeBoldWhenNoBoldFace"),
                bold.decisions.single().reason,
            )

            val boldInk = drawnInkPixels(boldRun.glyphs)
            val regularInk = drawnInkPixels(regularRun.glyphs)
            assertTrue(
                boldInk > regularInk,
                "stroke synthetic bold must ink more pixels: bold=$boldInk regular=$regularInk",
            )
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    /** Host declares only a Latin family; every other role delegates to the platform default. */
    private fun platformDefaultHostCatalog(roboto: File): AndroidFontCatalog {
        val marker = AndroidFontCatalog.PLATFORM_DEFAULT_FAMILY
        return AndroidFontCatalog(
            faceSpecs = listOf(
                AndroidFontFaceSpec(
                    source = AndroidFontSource.file(roboto),
                    familyKey = "host-latin",
                    familyAliases = setOf("host-latin", "roboto"),
                    roles = setOf(FontRole.LatinText, FontRole.Symbol, FontRole.Unknown),
                    weight = 400,
                ),
            ),
            fallbackChains = mapOf(
                FontRole.CjkText to listOf(marker),
                FontRole.CjkPunctuation to listOf(marker),
                FontRole.LatinText to listOf("host-latin", marker),
                FontRole.Symbol to listOf(marker, "host-latin"),
                FontRole.Emoji to listOf(marker),
                FontRole.Unknown to listOf(marker, "host-latin"),
            ),
        )
    }

    private fun drawnInkPixels(glyphs: List<Glyph>): Int {
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF000000.toInt() }
        AndroidNativeGlyphReplay.drawGlyphs(Canvas(bitmap), glyphs, 4f, 48f, 40f, paint)
        return inkPixels(bitmap)
    }

    private fun cjkSpecId(file: File): String =
        TiqianAndroidFontBackend.capabilityReport(context).faces
            .first { it.sourceLabel == file.absolutePath }
            .id.value

    private fun resolveLatin(fontSize: Float): ResolvedNativeFontFace =
        TiqianAndroidFontBackend.resolveFace(context, request(FontRole.LatinText, listOf("roboto flex"), fontSize, "Hamburg"))

    private fun request(
        role: FontRole,
        families: List<String>,
        fontSize: Float,
        selectionText: String,
    ) = ReplayableFontFaceRequest(
        role = role,
        preferredFamilies = families.toMutableList(),
        fontSize = fontSize,
        weight = 400,
        italic = false,
        locale = "zh-Hans",
        selectionText = selectionText,
    )

    private fun latinInput(
        text: String,
        fontSize: Float,
        italic: Boolean = false,
        family: String = "roboto flex",
    ): ShapingInput =
        ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(fontFamilies = listOf(family), fontSize = fontSize, locale = "en", italic = italic),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate("test-latin", "roboto flex", FontRole.LatinText),
                role = FontRole.LatinText,
                reason = "NativeInstrumentationFixture",
            ),
        )

    private fun input(
        text: String,
        role: FontRole,
        fontSize: Float,
        italic: Boolean = false,
        fontWeight: Int = 400,
    ): ShapingInput =
        ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(fontSize = fontSize, locale = "zh-Hans", fontWeight = fontWeight, italic = italic),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate("test-$role", "sans-serif", role),
                role = role,
                reason = "NativeInstrumentationFixture",
            ),
        )

    private fun cjkSpec(file: File) = AndroidFontFaceSpec(
        source = AndroidFontSource.file(file),
        collectionIndex = if (file.name.endsWith(".ttc")) 2 else 0,
        familyKey = "cjk",
        familyAliases = setOf("sans-serif", "noto sans cjk sc"),
        roles = setOf(FontRole.CjkText, FontRole.CjkPunctuation, FontRole.LatinText, FontRole.Symbol, FontRole.Unknown),
    )

    private fun inkPixels(bitmap: Bitmap): Int {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.count { pixel -> (pixel ushr 24) >= 0x40 }
    }

    private fun cjkFontFile(): File? = listOf(
        File("/system/fonts/NotoSansCJK-Regular.ttc"),
        File("/system/fonts/NotoSansSC-Regular.otf"),
        File("/system/fonts/NotoSansCJKsc-Regular.otf"),
    ).firstOrNull(File::isFile)
}
