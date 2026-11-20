package org.tiqian.android.rendering

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.Glyph
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.toReplayIndex
import org.tiqian.font.FontRole
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.android.AndroidGlyphReplay
import org.tiqian.shaping.android.AndroidGlyphReplayRegistry
import org.tiqian.shaping.android.AndroidReplayPlatformFont
import org.tiqian.shaping.android.nativefont.AndroidFontCatalog
import org.tiqian.shaping.android.nativefont.AndroidFontFaceSpec
import org.tiqian.shaping.android.nativefont.AndroidFontSource
import org.tiqian.shaping.android.nativefont.AndroidNativeFontMetricsResolver
import org.tiqian.shaping.android.nativefont.AndroidNativeGlyphReplay
import org.tiqian.shaping.android.nativefont.AndroidNativeTextShaper
import org.tiqian.shaping.android.nativefont.TiqianAndroidFontBackend
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class AndroidGlyphReplayRendererTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun nativeBackendGlyphsAreDrawnThroughTheHostReplayHook() {
        val cjk = listOf(
            File("/system/fonts/NotoSansCJK-Regular.ttc"),
            File("/system/fonts/NotoSansSC-Regular.otf"),
        ).firstOrNull(File::isFile)
        assumeTrue("No system CJK font", cjk != null)
        val counting = CountingReplay(AndroidNativeGlyphReplay)
        try {
            TiqianAndroidFontBackend.install(
                context,
                AndroidFontCatalog.host(
                    listOf(
                        AndroidFontFaceSpec(
                            source = AndroidFontSource.file(cjk!!),
                            collectionIndex = if (cjk.name.endsWith(".ttc")) 2 else 0,
                            familyKey = "cjk",
                            familyAliases = setOf("sans-serif"),
                            roles = FontRole.entries.toSet(),
                        ),
                    ),
                ),
            )
            // The counting wrapper must answer before the backend's own registration.
            AndroidGlyphReplayRegistry.unregister(AndroidNativeGlyphReplay)
            AndroidGlyphReplayRegistry.register(counting)

            val engine = ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                textShaper = AndroidNativeTextShaper(context),
                fontMetricsResolver = AndroidNativeFontMetricsResolver(context),
                clreqProfileResolver = object : org.tiqian.clreq.ClreqProfileResolver {
                    override fun resolve(profileId: org.tiqian.core.LayoutProfileId): ClreqProfile =
                        ClreqProfile.MainlandHorizontal
                },
            )
            val result = engine.layout(
                LayoutInput(
                    content = TiqianTextContent("提椠中文，English 混排。"),
                    textStyle = TextStyle(fontSize = 28f, locale = "zh-Hans"),
                    paragraphStyle = ParagraphStyle(),
                    constraints = LayoutConstraints(maxWidth = 400f),
                ),
            )
            val glyphs = result.glyphRuns.flatMap { it.glyphs }
            assertTrue(glyphs.isNotEmpty())
            assertTrue(glyphs.all { it.renderFontKey?.startsWith("tiqian-font:sha256:") == true })

            val bitmap = Bitmap.createBitmap(420, 120, Bitmap.Config.ARGB_8888)
            AndroidParagraphRenderer().use { renderer ->
                renderer.draw(Canvas(bitmap), result, result.toReplayIndex(emptyList()), 0xFF000000.toInt())
            }
            assertEquals(glyphs.size, counting.drawnGlyphs, "every glyph must be drawn by the host replay")
            assertTrue(inkPixels(bitmap) > 0)
        } finally {
            AndroidGlyphReplayRegistry.unregister(counting)
            AndroidGlyphReplayRegistry.register(AndroidNativeGlyphReplay)
        }
    }

    private class CountingReplay(
        private val delegate: AndroidGlyphReplay,
    ) : AndroidGlyphReplay {
        var drawnGlyphs = 0

        override fun ownsFont(renderFontKey: String): Boolean = delegate.ownsFont(renderFontKey)

        override fun providesItalic(renderFontKey: String): Boolean = delegate.providesItalic(renderFontKey)

        override fun platformFont(renderFontKey: String): AndroidReplayPlatformFont? = delegate.platformFont(renderFontKey)

        override fun drawGlyphs(
            canvas: Canvas,
            glyphs: List<Glyph>,
            originX: Float,
            originY: Float,
            fontSize: Float,
            paint: Paint,
            scratch: Path,
        ): Boolean {
            val drawn = delegate.drawGlyphs(canvas, glyphs, originX, originY, fontSize, paint, scratch)
            if (drawn) drawnGlyphs += glyphs.size
            return drawn
        }
    }

    private fun inkPixels(bitmap: Bitmap): Int {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.count { pixel -> (pixel ushr 24) >= 0x40 }
    }
}
