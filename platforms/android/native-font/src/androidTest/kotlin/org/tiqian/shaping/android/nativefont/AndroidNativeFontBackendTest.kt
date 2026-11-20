package org.tiqian.shaping.android.nativefont

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.fonts.SystemFonts
import android.os.Build
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.linebreak.EnglishHyphenation
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.android.AndroidFontMetricsResolver
import org.tiqian.shaping.android.AndroidPaintTextShaper
import org.tiqian.shaping.android.AndroidTypefaceResolver
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidNativeFontBackendTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun defaultCatalogUsesTheStrongestObservableSystemSelectionContract() {
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        val report = TiqianAndroidFontBackend.capabilityReport(context)
        if (Build.VERSION.SDK_INT >= 31) {
            assertEquals("AndroidPlatformTextRunOracleApi31", report.sourceKind)
        } else {
            assertEquals("DeclaredAndroidFontConfigApi23To30", report.sourceKind)
            assertTrue(report.issues.any { it.code == "RuntimeFontSelectionUnobservableBelowApi31" })
        }
    }

    @Test
    fun platformDefaultOraclePreservesConcreteFallbackAndAxisInstance() {
        if (Build.VERSION.SDK_INT < 31) return
        fun request(text: String) = org.tiqian.shaping.ReplayableFontFaceRequest(
            role = FontRole.CjkText,
            preferredFamilies = mutableListOf(),
            fontSize = 32f,
            weight = 400,
            italic = false,
            locale = "zh-Hans",
            selectionText = text,
        )

        val commonRequest = request("中")
        val extensionRequest = request("𠮷")
        val commonPlatform = AndroidPlatformFontOracle.select(commonRequest)
        val extensionPlatform = AndroidPlatformFontOracle.select(extensionRequest)
        val commonNative = TiqianAndroidFontBackend.resolveFace(context, commonRequest)
        val extensionNative = TiqianAndroidFontBackend.resolveFace(context, extensionRequest)

        assertEquals(commonPlatform.source.label, commonNative.descriptor.sourceLabel)
        assertEquals(commonPlatform.collectionIndex, commonNative.descriptor.collectionIndex)
        assertEquals(commonPlatform.variationAxes, commonNative.descriptor.variationAxes)
        assertEquals(extensionPlatform.source.label, extensionNative.descriptor.sourceLabel)
        assertEquals(extensionPlatform.collectionIndex, extensionNative.descriptor.collectionIndex)
        assertEquals(extensionPlatform.variationAxes, extensionNative.descriptor.variationAxes)
        if (commonPlatform.instanceKey != extensionPlatform.instanceKey) {
            assertNotEquals(commonNative.descriptor.id, extensionNative.descriptor.id)
        }
    }

    @Test
    fun cjkQuotesAndDashesUseTheSameConcreteFaceAsHanText() {
        if (Build.VERSION.SDK_INT < 31) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        fun resolve(role: FontRole, text: String) = TiqianAndroidFontBackend.resolveFace(
            context,
            org.tiqian.shaping.ReplayableFontFaceRequest(
                role = role,
                preferredFamilies = mutableListOf(),
                fontSize = 32f,
                weight = 400,
                italic = false,
                locale = "zh-Hans",
                selectionText = text,
            ),
        ).descriptor

        val han = resolve(FontRole.CjkText, "中")
        for (punctuation in listOf("“", "”", "‘", "’", "—", "——")) {
            val actual = resolve(FontRole.CjkPunctuation, punctuation)
            assertEquals(han.id.sourceDigest(), actual.id.sourceDigest(), punctuation)
            assertEquals(han.collectionIndex, actual.collectionIndex, punctuation)
            assertEquals(han.variationAxes, actual.variationAxes, punctuation)
        }
    }

    @Test
    fun multiFaceSegmentsDegradeToPlatformStringDrawInsteadOfCrashing() {
        if (Build.VERSION.SDK_INT < 31) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        // Repro of the zhplus.lite crash: runs the platform itemizes across two physical faces
        // (a non-CJK script base+mark, and a Han base with a combining mark its CJK face lacks).
        // Before the fix the oracle's single-face check threw PlatformSelectionSpansMultipleFaces
        // during Compose measure. Only assert on a device that actually splits the run.
        val candidates = listOf(
            "กิ" to FontRole.Unknown, // กิ — Thai base + vowel mark
            "中҉" to FontRole.CjkText, // 中 + combining Cyrillic millions sign
        )
        var exercised = 0
        for ((text, role) in candidates) {
            val request = org.tiqian.shaping.ReplayableFontFaceRequest(
                role = role,
                preferredFamilies = mutableListOf(),
                fontSize = 32f,
                weight = 400,
                italic = false,
                locale = "zh-Hans",
                selectionText = text,
            )
            if (!AndroidPlatformFontOracle.select(request).spansMultipleFaces) continue
            exercised += 1

            val shaped = AndroidNativeTextShaper(context).shape(input(text, role, 32f))
            val cluster = shaped.clusters.single()
            assertEquals(text, cluster.displayText)
            assertEquals(text, cluster.text, "source text must be preserved")
            assertTrue(cluster.advance > 0f, "$text degraded advance was ${cluster.advance}")

            val glyphs = shaped.glyphRuns.single().glyphs
            assertTrue(
                glyphs.all { it.renderFontKey == null },
                "$text multi-face segment must be non-replayable so the renderer platform-draws it",
            )
            assertTrue(
                !AndroidNativeGlyphReplay.ownsGlyphs(glyphs),
                "$text degraded glyphs must not claim a retained native face",
            )
            assertEquals(
                org.tiqian.shaping.ShapingIssue.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE,
                shaped.decisions.single().capabilityIssue,
                text,
            )
        }
        android.util.Log.i(
            "TiqianMultiFace",
            "sdk=${Build.VERSION.SDK_INT} model=${Build.MODEL} multiFaceCasesExercised=$exercised",
        )
    }

    @Test
    fun platformSyntheticItalicCjkRemainsReplayable() {
        if (Build.VERSION.SDK_INT < 35) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        val request = org.tiqian.shaping.ReplayableFontFaceRequest(
            role = FontRole.CjkText,
            preferredFamilies = mutableListOf(),
            fontSize = 32f,
            weight = 400,
            italic = true,
            locale = "zh-Hans",
            selectionText = "拉",
        )
        val platform = AndroidPlatformFontOracle.select(request)
        if (!platform.syntheticItalic) return

        val resolved = TiqianAndroidFontBackend.resolveFace(context, request)
        assertTrue(resolved.descriptor.italic)
        assertTrue(resolved.descriptor.id.value.endsWith(":syntheticItalic=-0.25"))
        assertTrue(TiqianAndroidFontBackend.isSyntheticItalicFace(resolved.descriptor.id.value))
        assertTrue(AndroidNativeGlyphReplay.providesItalic(resolved.descriptor.id.value))
        assertEquals(-0.25f, AndroidNativeGlyphReplay.platformFont(resolved.descriptor.id.value)?.textSkewX)

        val regular = AndroidNativeTextShaper(context).shape(
            input("拉", FontRole.CjkText, 32f, italic = false),
        )
        val italic = AndroidNativeTextShaper(context).shape(
            input("拉", FontRole.CjkText, 32f, italic = true),
        )
        assertEquals(
            regular.glyphRuns.single().glyphs.map { it.id },
            italic.glyphRuns.single().glyphs.map { it.id },
            "Platform synthetic italic must preserve the selected physical glyphs",
        )
        assertNotEquals(
            regular.glyphRuns.single().glyphs.single().bounds,
            italic.glyphRuns.single().glyphs.single().bounds,
            "Synthetic italic ink bounds must replay the same baseline shear as drawing",
        )
        assertTrue(replayInkPixels(italic.glyphRuns.single().glyphs, 32f) > 0)
    }

    @Test
    fun platformSyntheticBoldRemainsDrawableByTheSelectedAndroidFont() {
        if (Build.VERSION.SDK_INT < 35) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        val request = org.tiqian.shaping.ReplayableFontFaceRequest(
            role = FontRole.LatinText,
            preferredFamilies = mutableListOf(),
            fontSize = 32f,
            weight = 700,
            italic = false,
            locale = "zh-Hans",
            selectionText = "\\aleph_0",
        )
        val platform = AndroidPlatformFontOracle.select(request)
        if (!platform.syntheticBold) return

        val resolved = TiqianAndroidFontBackend.resolveFace(context, request)
        assertEquals(700, resolved.descriptor.weight)
        assertTrue(resolved.descriptor.id.value.contains(":syntheticBold=platform"))
        assertTrue(TiqianAndroidFontBackend.isSyntheticBoldFace(resolved.descriptor.id.value))
        assertNotNull(AndroidNativeGlyphReplay.platformFontFor(resolved.descriptor.id.value))
        assertTrue(checkNotNull(AndroidNativeGlyphReplay.platformFont(resolved.descriptor.id.value)).fakeBold)

        val shaped = AndroidNativeTextShaper(context).shape(
            input("\\aleph_0", FontRole.LatinText, 32f, fontWeight = 700),
        )
        val glyphs = shaped.glyphRuns.single().glyphs
        assertTrue(AndroidNativeGlyphReplay.requiresPlatformSyntheticBold(glyphs))
        assertTrue(glyphs.all { it.renderFontKey == resolved.descriptor.id.value })
        val font = requireNotNull(AndroidNativeGlyphReplay.platformFontFor(resolved.descriptor.id.value))
        val regularInk = platformGlyphInkPixels(glyphs, font, 32f, fakeBold = false)
        val boldInk = platformGlyphInkPixels(glyphs, font, 32f, fakeBold = true)
        assertTrue(regularInk > 0)
        assertTrue(
            boldInk > regularInk,
            "Canvas.drawGlyphs must apply the platform fake-bold paint to the exact selected glyphs",
        )
    }

    @Test
    fun platformRegularFaceRetainsTheSelectedAndroidFontForGlyphReplay() {
        if (Build.VERSION.SDK_INT < 31) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        val request = org.tiqian.shaping.ReplayableFontFaceRequest(
            role = FontRole.CjkText,
            preferredFamilies = mutableListOf(),
            fontSize = 32f,
            weight = 400,
            italic = false,
            locale = "zh-Hans",
            selectionText = "普通正文",
        )

        val resolved = TiqianAndroidFontBackend.resolveFace(context, request)

        assertNotNull(
            AndroidNativeGlyphReplay.platformFontFor(resolved.descriptor.id.value),
            "Regular platform-default faces must retain the exact Font used to create native shaping bytes",
        )
    }

    @Test
    fun nativeFaceInstancesShareOneFileMappingAndKeepItAlive() {
        val file = File("/system/fonts/Roboto-Regular.ttf").takeIf(File::isFile) ?: return
        val before = nativeFontResourceStats()
        val sourceHandle = NativeFontBridge.nativeRegisterFileSource(file.canonicalPath)
        assertNotEquals(0L, sourceHandle)
        val afterSource = nativeFontResourceStats()
        assertEquals(before.sourceCount + 1, afterSource.sourceCount)
        assertEquals(before.sourceBytes + file.length(), afterSource.sourceBytes)

        val firstFace = NativeFontBridge.nativeCreateFace(sourceHandle, 0, intArrayOf(), floatArrayOf())
        val secondFace = NativeFontBridge.nativeCreateFace(sourceHandle, 0, intArrayOf(), floatArrayOf())
        assertNotEquals(0L, firstFace)
        assertNotEquals(0L, secondFace)
        try {
            val withFaces = nativeFontResourceStats()
            assertEquals(afterSource.sourceCount, withFaces.sourceCount)
            assertEquals(afterSource.sourceBytes, withFaces.sourceBytes)
            assertEquals(afterSource.faceCount + 2, withFaces.faceCount)

            NativeFontBridge.nativeReleaseSource(sourceHandle)
            assertTrue(NativeFontBridge.nativeHasGlyphs(firstFace, "A"))
            val retained = nativeFontResourceStats()
            assertEquals(afterSource.sourceCount, retained.sourceCount)
            assertEquals(afterSource.sourceBytes, retained.sourceBytes)
        } finally {
            NativeFontBridge.nativeReleaseFace(firstFace)
            NativeFontBridge.nativeReleaseFace(secondFace)
        }
        assertEquals(before, nativeFontResourceStats())
    }

    @Test
    fun nativeFaceInstancesShareOneDirectBufferAndKeepItAlive() {
        val file = File("/system/fonts/Roboto-Regular.ttf").takeIf(File::isFile) ?: return
        val bytes = file.readBytes()
        val buffer = ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            position(0)
        }
        val before = nativeFontResourceStats()
        val sourceHandle = NativeFontBridge.nativeRegisterBufferSource(buffer, bytes.size.toLong())
        assertNotEquals(0L, sourceHandle)
        val firstFace = NativeFontBridge.nativeCreateFace(sourceHandle, 0, intArrayOf(), floatArrayOf())
        val secondFace = NativeFontBridge.nativeCreateFace(sourceHandle, 0, intArrayOf(), floatArrayOf())
        try {
            val withFaces = nativeFontResourceStats()
            assertEquals(before.sourceCount + 1, withFaces.sourceCount)
            assertEquals(before.sourceBytes + bytes.size, withFaces.sourceBytes)
            assertEquals(before.faceCount + 2, withFaces.faceCount)

            NativeFontBridge.nativeReleaseSource(sourceHandle)
            assertTrue(NativeFontBridge.nativeHasGlyphs(secondFace, "A"))
            assertEquals(withFaces.copy(faceCount = before.faceCount + 2), nativeFontResourceStats())
        } finally {
            NativeFontBridge.nativeReleaseFace(firstFace)
            NativeFontBridge.nativeReleaseFace(secondFace)
        }
        assertEquals(before, nativeFontResourceStats())
    }

    @Test
    fun platformAxisInstancesDoNotDuplicateTheirFontSource() {
        if (Build.VERSION.SDK_INT < 31) return
        TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        fun request(weight: Int) = org.tiqian.shaping.ReplayableFontFaceRequest(
            role = FontRole.CjkText,
            preferredFamilies = mutableListOf(),
            fontSize = 32f,
            weight = weight,
            italic = false,
            locale = "zh-Hans",
            selectionText = "中",
        )

        val regular = TiqianAndroidFontBackend.resolveFace(context, request(400))
        val afterRegular = TiqianAndroidFontBackend.resourceStatsForTesting()
        val bold = TiqianAndroidFontBackend.resolveFace(context, request(700))
        val afterBold = TiqianAndroidFontBackend.resourceStatsForTesting()
        val regularDigest = regular.descriptor.id.sourceDigest()
        val boldDigest = bold.descriptor.id.sourceDigest()
        val regularLocator = regular.descriptor.sourceLabel.substringBefore('#')
        val boldLocator = bold.descriptor.sourceLabel.substringBefore('#')
        android.util.Log.i(
            "TiqianNativeSource",
            "model=${Build.MODEL} regular=${regular.descriptor.sourceLabel} " +
                "bold=${bold.descriptor.sourceLabel} afterRegular=$afterRegular afterBold=$afterBold",
        )
        if (regularLocator == boldLocator) {
            assertEquals(regularDigest, boldDigest, "The same platform font file must identify one source")
        }
        if (regularDigest == boldDigest) {
            assertEquals(afterRegular.sourceCount, afterBold.sourceCount)
            assertEquals(afterRegular.sourceBytes, afterBold.sourceBytes)
        }
        if (regular.descriptor.variationAxes != bold.descriptor.variationAxes) {
            assertNotEquals(regular.descriptor.id, bold.descriptor.id)
        }
    }

    @Test
    fun approximateSystemCatalogPreservesEnumeratedInstancesAndNamesItsLimitation() {
        if (Build.VERSION.SDK_INT < 29) return
        val availableFonts = SystemFonts.getAvailableFonts().toList()
        val catalog = ApproximatePublicSystemFontsCatalog.createOrNull(availableFonts) ?: return
        val reversedCatalog = assertNotNull(
            ApproximatePublicSystemFontsCatalog.createOrNull(availableFonts.reversed()),
        )
        fun signatures(value: AndroidFontCatalog) = value.faceSpecs.map { spec ->
            listOf(
                spec.familyKey,
                spec.source.label,
                spec.collectionIndex,
                spec.weight,
                spec.italic,
                spec.variationAxes,
                spec.roles.sortedBy(FontRole::ordinal),
            )
        }
        assertEquals(signatures(catalog), signatures(reversedCatalog))
        assertEquals("ApproximateAndroidPublicSystemFontsApi29", catalog.sourceKind)
        assertTrue(catalog.declaredIssues.any { it.code == "ApproximateSystemFontSelection" })

        catalog.faceSpecs.forEach { spec ->
            val sourcePath = spec.source.label.removePrefix("SystemFonts:").substringBefore('#')
            val enumerated = availableFonts.firstOrNull { font ->
                val enumeratedAxes = font.axes.orEmpty()
                    .associate { axis -> axis.tag to axis.styleValue }
                    .toSortedMap()
                font.file?.absolutePath == sourcePath &&
                    font.ttcIndex == spec.collectionIndex &&
                    font.style.weight == spec.weight &&
                    (font.style.slant == android.graphics.fonts.FontStyle.FONT_SLANT_ITALIC) == spec.italic &&
                    enumeratedAxes == spec.variationAxes
            }
            assertNotNull(enumerated, "Approximate catalog must preserve one exact enumerated instance")
            val enumeratedAxes = enumerated.axes.orEmpty()
                .associate { axis -> axis.tag to axis.styleValue }
                .toSortedMap()
            assertEquals(
                enumeratedAxes,
                spec.variationAxes,
                "Approximate catalog must preserve the enumerated instance instead of manufacturing wght=400/700",
            )
        }

        val latinRegular = catalog.faceSpecs
            .filter { FontRole.LatinText in it.roles && !it.italic }
            .minByOrNull { abs(it.weight - 400) }
            ?: return
        if (latinRegular.familyAliases.any { "roboto" in it }) {
            assertEquals(
                100f,
                latinRegular.variationAxes["wdth"] ?: 100f,
                "The generic sans face must not resolve to Roboto Condensed",
            )
        }
    }

    @Test
    fun controlledBytesShapeMetricsInkAndOutlineReplay() {
        val report = TiqianAndroidFontBackend.capabilityReport(context)
        assertTrue(report.canReplayFromControlledBytes, report.toString())
        assertTrue(report.backend.contains("harfbuzz="), report.backend)
        assertTrue(report.backend.contains("freetype="), report.backend)

        val shaper = AndroidNativeTextShaper(context)
        val cjk = shaper.shape(input("中文。", FontRole.CjkText, 32f))
        assertEquals("HarfBuzz", cjk.decisions.single().source)
        assertEquals(0, cjk.decisions.single().missingGlyphs)
        assertTrue(cjk.clusters.single().advance > 80f)
        assertTrue(cjk.glyphRuns.single().glyphs.all { it.renderFontKey?.startsWith("tiqian-font:sha256:") == true })
        assertTrue(cjk.glyphRuns.single().glyphs.all { it.bounds != null })

        val metrics = AndroidNativeFontMetricsResolver(context).resolve(
            org.tiqian.font.FontMetricsRequest(
                fontKey = "cjk-primary",
                fontSize = 32f,
                role = FontRole.CjkText,
                locale = "zh-Hans",
                faceSelectionText = "中",
            ),
        )
        assertTrue(metrics.ascent > 0f)
        assertTrue(metrics.descent >= 0f)
        assertNotNull(metrics.typoAscent)

        val bitmap = Bitmap.createBitmap(160, 80, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF000000.toInt() }
        assertTrue(
            AndroidNativeGlyphReplay.drawGlyphs(
                canvas = canvas,
                glyphs = cjk.glyphRuns.single().glyphs,
                originX = 8f,
                originY = 48f,
                fontSize = 32f,
                paint = paint,
            ),
        )
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        assertTrue(pixels.any { it != 0 }, "FreeType outline replay produced no ink")
    }

    @Test
    fun cjkLoclAndAnyHaltEvidenceComesFromTheSameFace() {
        val shaper = AndroidNativeTextShaper(context)
        val punctuation = shaper.shape(input("。", FontRole.CjkPunctuation, 32f))
        val glyph = punctuation.glyphRuns.single().glyphs.single()
        assertTrue("locl=1" in punctuation.glyphRuns.single().openTypeFeatures)
        glyph.haltAdvance?.let { haltAdvance ->
            assertTrue(haltAdvance < punctuation.clusters.single().advance)
        }
        assertEquals(punctuation.decisions.single().resolvedFace, glyph.renderFontKey)

        val dash = shaper.shape(input("—", FontRole.CjkPunctuation, 32f))
        assertEquals("Hani", dash.decisions.single().script)
        assertTrue(dash.decisions.single().featureEvidence?.contains("locl=1") == true)
        assertEquals(0, dash.decisions.single().missingGlyphs)
    }

    @Test
    fun nativeBackendLaysOutMixedLongBodyWithinBoundedTime() {
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = AndroidNativeTextShaper(context),
            fontMetricsResolver = AndroidNativeFontMetricsResolver(context),
            clreqProfileResolver = object : org.tiqian.clreq.ClreqProfileResolver {
                override fun resolve(profileId: org.tiqian.core.LayoutProfileId): ClreqProfile =
                    ClreqProfile.MainlandHorizontal
            },
            hyphenator = EnglishHyphenation.enUs(),
        )
        val paragraph = buildString {
            repeat(80) {
                append("提椠以同一字体字节处理中文……English typography——与链接 https://example.com/a-b。")
            }
        }
        val start = SystemClock.elapsedRealtimeNanos()
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(paragraph),
                textStyle = TextStyle(fontSize = 28f, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(),
                constraints = LayoutConstraints(maxWidth = 560f),
            ),
        )
        val elapsedMs = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000
        assertTrue(result.lines.size > 80)
        assertTrue(result.glyphRuns.isNotEmpty())
        android.util.Log.i(
            "TiqianNativePerf",
            "sdk=${Build.VERSION.SDK_INT} chars=${paragraph.length} longBodyMs=$elapsedMs " +
                "lines=${result.lines.size} glyphRuns=${result.glyphRuns.size}",
        )
        assertTrue(elapsedMs < 20_000, "80-repeat long paragraph took ${elapsedMs}ms")
    }

    @Test
    fun nativeAndApi31AdapterAgreeForTheSameFontBytes() {
        if (Build.VERSION.SDK_INT < 31) return
        val fontFile = cjkFontFile() ?: return
        val ttcIndex = if (fontFile.name.endsWith(".ttc")) 2 else 0
        try {
            TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    listOf(
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.bytes(fontFile.readBytes(), "comparison:${fontFile.absolutePath}"),
                            collectionIndex = ttcIndex,
                            familyKey = "comparison",
                            familyAliases = setOf("sans", "sans-serif", "comparison-cjk"),
                            roles = FontRole.entries.toSet(),
                        ),
                    ),
                ),
            )
            val typeface = Typeface.Builder(fontFile).setTtcIndex(ttcIndex).build()
            val resolver = object : AndroidTypefaceResolver {
                override fun resolve(
                    role: FontRole,
                    fontFamilies: List<String>,
                    fontWeight: Int,
                    italic: Boolean,
                ): Typeface = typeface

                override fun resolve(input: ShapingInput): Typeface = typeface
            }
            val native = AndroidNativeTextShaper(context)
            val platform = AndroidPaintTextShaper(typefaceResolver = resolver)
            for ((text, role) in listOf("中文" to FontRole.CjkText, "English" to FontRole.LatinText, "。" to FontRole.CjkPunctuation)) {
                val input = input(text, role, 32f)
                val nativeResult = native.shape(input)
                val platformResult = platform.shape(input)
                assertTrue(
                    abs(nativeResult.clusters.single().advance - platformResult.clusters.single().advance) <= 1.25f,
                    "$text advance native=${nativeResult.clusters.single().advance} platform=${platformResult.clusters.single().advance}",
                )
                assertEquals(
                    platformResult.glyphRuns.single().glyphs.map { it.id },
                    nativeResult.glyphRuns.single().glyphs.map { it.id },
                    "$text glyph ids",
                )
                val nativeInk = nativeResult.glyphRuns.single().glyphs.mapNotNull { it.bounds }
                val platformInk = platformResult.glyphRuns.single().glyphs.mapNotNull { it.bounds }
                assertEquals(platformInk.size, nativeInk.size, "$text ink count")
            }

            val style = TextStyle(fontSize = 32f, locale = "zh-Hans")
            val text = "中文……English——中文。"
            val input = LayoutInput(
                content = TiqianTextContent(text),
                textStyle = style,
                constraints = LayoutConstraints(maxWidth = 224f),
            )
            val nativeEngine = ExplainableStubParagraphLayoutEngine(
                textShaper = native,
                fontMetricsResolver = AndroidNativeFontMetricsResolver(context),
            )
            val platformEngine = ExplainableStubParagraphLayoutEngine(
                textShaper = platform,
                // Hold metrics constant so this is a shaping/layout geometry comparison.
                fontMetricsResolver = AndroidNativeFontMetricsResolver(context),
            )
            val nativeLayout = nativeEngine.layout(input)
            val platformLayout = platformEngine.layout(input)
            assertEquals(platformLayout.lines.map { it.range }, nativeLayout.lines.map { it.range })
            assertEquals(platformLayout.lines.size, nativeLayout.lines.size)
            nativeLayout.lines.zip(platformLayout.lines).forEach { (a, b) ->
                assertTrue(abs(a.visualWidth - b.visualWidth) <= 1.5f, "line width native=${a.visualWidth} platform=${b.visualWidth}")
            }
        } finally {
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    @Test
    fun catalogRevisionOrderedFallbackAndOldReplayRemainCoherent() {
        val cjkFile = cjkFontFile() ?: return
        val latinFile = File("/system/fonts/Roboto-Regular.ttf").takeIf(File::isFile) ?: return
        val allRoles = FontRole.entries.toSet()
        fun spec(file: File, familyKey: String, index: Int = 0) = AndroidFontFaceSpec(
            source = AndroidFontSource.bytes(file.readBytes(), "$familyKey:${file.absolutePath}"),
            collectionIndex = index,
            familyKey = familyKey,
            familyAliases = setOf("sans", "sans-serif", familyKey),
            roles = allRoles,
        )
        val cjkIndex = if (cjkFile.name.endsWith(".ttc")) 2 else 0
        val faces = listOf(spec(cjkFile, "primary-cjk", cjkIndex), spec(latinFile, "secondary-latin"))
        fun catalog(order: List<String>) = AndroidFontCatalog.host(
            faceSpecs = faces,
            fallbackChains = FontRole.entries.associateWith { order },
        )

        val observedRevisions = mutableListOf<Long>()
        val registration = TiqianAndroidFontBackend.addCatalogRevisionListener(context, observedRevisions::add)
        try {
            // API 23's NotoSansSC subset intentionally omits basic Latin letters. Space is a
            // real mapped glyph in both controlled faces, so it isolates family ordering from
            // the separate and already-covered "fall through on missing glyph" contract.
            val sharedGlyphText = " "
            val firstReport = TiqianAndroidFontBackend.install(
                context,
                catalog(listOf("primary-cjk", "secondary-latin")),
            )
            val firstRevision = TiqianAndroidFontBackend.catalogRevision(context)
            val first = AndroidNativeTextShaper(context).shape(input(sharedGlyphText, FontRole.Symbol, 32f))
            val firstKey = first.glyphRuns.single().glyphs.single().renderFontKey
            val cjkKey = firstReport.faces.first { it.sourceLabel.startsWith("primary-cjk:") }.id.value
            assertEquals(cjkKey, firstKey, "The first covering family in the role chain must win")

            val secondReport = TiqianAndroidFontBackend.install(
                context,
                catalog(listOf("secondary-latin", "primary-cjk")),
            )
            val secondRevision = TiqianAndroidFontBackend.catalogRevision(context)
            val second = AndroidNativeTextShaper(context).shape(input(sharedGlyphText, FontRole.Symbol, 32f))
            val secondKey = second.glyphRuns.single().glyphs.single().renderFontKey
            val latinKey = secondReport.faces.first { it.sourceLabel.startsWith("secondary-latin:") }.id.value

            assertTrue(secondRevision > firstRevision)
            assertEquals(latinKey, secondKey, "Reversing the family chain must change new shaping")
            assertNotEquals(firstKey, secondKey)
            assertTrue(
                AndroidNativeGlyphReplay.ownsGlyphs(first.glyphRuns.single().glyphs),
                "A catalog replacement must retain faces used by an old LayoutResult",
            )
            assertEquals(secondRevision, observedRevisions.last())
        } finally {
            registration.close()
            TiqianAndroidFontBackend.resetDefaultCatalogForTesting(context)
        }
    }

    private fun input(
        text: String,
        role: FontRole,
        fontSize: Float,
        fontWeight: Int = 400,
        italic: Boolean = false,
    ): ShapingInput =
        ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(
                fontSize = fontSize,
                locale = "zh-Hans",
                fontWeight = fontWeight,
                italic = italic,
            ),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate("test-$role", "sans-serif", role),
                role = role,
                reason = "NativeInstrumentationFixture",
            ),
        )

    private fun replayInkPixels(glyphs: List<org.tiqian.core.Glyph>, fontSize: Float): Int {
        val bitmap = Bitmap.createBitmap(112, 112, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF000000.toInt() }
        assertTrue(
            AndroidNativeGlyphReplay.drawGlyphs(
                canvas = Canvas(bitmap),
                glyphs = glyphs,
                originX = 20f,
                originY = 80f,
                fontSize = fontSize,
                paint = paint,
            ),
        )
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.count { pixel -> (pixel ushr 24) >= 0x40 }
    }

    // `font` is typed as Any so reflection over this class loads below API 29.
    @android.annotation.TargetApi(31)
    private fun platformGlyphInkPixels(
        glyphs: List<org.tiqian.core.Glyph>,
        font: Any,
        fontSize: Float,
        fakeBold: Boolean,
    ): Int {
        val bitmap = Bitmap.createBitmap(320, 112, Bitmap.Config.ARGB_8888)
        val ids = IntArray(glyphs.size) { index -> glyphs[index].id.toInt() }
        val positions = FloatArray(glyphs.size * 2) { index ->
            val glyph = glyphs[index / 2]
            if (index % 2 == 0) 20f + glyph.x else 80f + glyph.y
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF000000.toInt()
            textSize = fontSize
            isFakeBoldText = fakeBold
        }
        Canvas(bitmap).drawGlyphs(ids, 0, positions, 0, glyphs.size, font as android.graphics.fonts.Font, paint)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.count { pixel -> (pixel ushr 24) >= 0x40 }
    }

    private fun cjkFontFile(): File? = listOf(
        File("/system/fonts/NotoSansCJK-Regular.ttc"),
        File("/system/fonts/NotoSansSC-Regular.otf"),
        File("/system/fonts/NotoSansCJKsc-Regular.otf"),
    ).firstOrNull(File::isFile)

    private fun org.tiqian.shaping.FontFaceId.sourceDigest(): String =
        value.removePrefix("tiqian-font:sha256:").substringBefore(':')
}
