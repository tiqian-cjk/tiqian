package org.tiqian.shaping.android.nativefont

import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.fonts.Font
import android.os.Build
import org.tiqian.core.Glyph
import org.tiqian.core.Rect
import org.tiqian.shaping.android.AndroidGlyphReplay
import org.tiqian.shaping.android.AndroidReplayPlatformFont
import java.util.LinkedHashMap

/** FreeType outline replay for API 23+, consuming only glyph ids/origins emitted by LayoutResult. */
object AndroidNativeGlyphReplay : AndroidGlyphReplay {
    private const val MaxCachedScaledOutlines = 4096
    private val cacheLock = Any()
    private val scaledOutlineCache = object : LinkedHashMap<OutlineKey, Path>(128, 0.75f, true) {}

    override fun ownsFont(renderFontKey: String): Boolean =
        TiqianAndroidFontBackend.replayFace(renderFontKey) != null

    override fun providesItalic(renderFontKey: String): Boolean =
        TiqianAndroidFontBackend.replayFace(renderFontKey)?.let { it.syntheticItalic || it.italic } == true

    /** API 31+ only; the retained platform Font carries the synthesis the platform selected it with. */
    override fun platformFont(renderFontKey: String): AndroidReplayPlatformFont? {
        if (Build.VERSION.SDK_INT < 31) return null
        val face = TiqianAndroidFontBackend.replayFace(renderFontKey) ?: return null
        val font = face.platformFont ?: return null
        return AndroidReplayPlatformFont(
            font = font,
            fakeBold = face.syntheticBold,
            textSkewX = when {
                face.syntheticItalic -> SyntheticItalicSkewX
                face.italic -> 0f
                else -> null
            },
        )
    }

    override fun drawGlyphs(
        canvas: Canvas,
        glyphs: List<Glyph>,
        originX: Float,
        originY: Float,
        fontSize: Float,
        paint: Paint,
        scratch: Path,
    ): Boolean {
        // Faces are resolved once per distinct key, and nothing is drawn until every glyph is
        // known to have an outline: a platform fake-bold face (API 31+ Font) has none here.
        val faces = HashMap<String, ReplayFace>()
        for (glyph in glyphs) {
            val key = glyph.renderFontKey ?: return false
            val face = faces.getOrPut(key) { TiqianAndroidFontBackend.replayFace(key) ?: return false }
            if (face.syntheticBold && face.platformFont != null) return false
        }
        val (stroked, plain) = glyphs.partition { glyph -> faces.getValue(glyph.renderFontKey!!).syntheticBold }
        val plainPath = if (plain.isEmpty()) null else glyphPath(plain, originX, originY, fontSize, scratch) ?: return false
        val strokedPath = if (stroked.isEmpty()) null else glyphPath(stroked, originX, originY, fontSize) ?: return false
        if (plainPath != null && !plainPath.isEmpty) canvas.drawPath(plainPath, paint)
        if (strokedPath != null && !strokedPath.isEmpty) canvas.drawPath(strokedPath, strokeSyntheticBoldPaint(paint, fontSize))
        return true
    }

    /** StrokeSyntheticBold: fill plus a stroke of Skia's fake-bold width (1/24 em at 9 px to 1/32 em at 36 px). */
    private fun strokeSyntheticBoldPaint(paint: Paint, fontSize: Float): Paint {
        val ratio = when {
            fontSize <= 9f -> 1f / 24f
            fontSize >= 36f -> 1f / 32f
            else -> 1f / 24f + (1f / 32f - 1f / 24f) * (fontSize - 9f) / 27f
        }
        return Paint(paint).apply {
            style = Paint.Style.FILL_AND_STROKE
            strokeWidth = fontSize * ratio
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
        }
    }

    fun drawGlyphs(
        canvas: Canvas,
        glyphs: List<Glyph>,
        originX: Float,
        originY: Float,
        fontSize: Float,
        paint: Paint,
    ): Boolean = drawGlyphs(canvas, glyphs, originX, originY, fontSize, paint, Path())

    /** True when these glyph ids were produced by faces retained by this backend. */
    fun ownsGlyphs(glyphs: List<Glyph>): Boolean =
        glyphs.isNotEmpty() && glyphs.all { glyph -> glyph.renderFontKey?.let(::ownsFont) == true }

    fun requiresPlatformSyntheticBold(glyphs: List<Glyph>): Boolean =
        glyphs.any { glyph ->
            glyph.renderFontKey?.let(TiqianAndroidFontBackend::replayFace)?.syntheticBold == true
        }

    fun usesSyntheticItalic(glyphs: List<Glyph>): Boolean =
        glyphs.any { glyph ->
            glyph.renderFontKey?.let(TiqianAndroidFontBackend::replayFace)?.syntheticItalic == true
        }

    /** API 31+: the retained platform Font behind a render key, or null. */
    fun platformFontFor(renderFontKey: String): Font? =
        if (Build.VERSION.SDK_INT >= 31) TiqianAndroidFontBackend.platformFontFor(renderFontKey) else null

    /**
     * Absolute path used by both paint and decoration skip-ink interception. Faces are resolved
     * once per distinct render key; a platform synthetic-bold face (API 31+ Font) has no outline
     * replay, a stroke synthetic-bold face replays its unstroked outline.
     */
    fun glyphPath(
        glyphs: List<Glyph>,
        originX: Float,
        originY: Float,
        fontSize: Float,
        reusablePath: Path? = null,
    ): Path? {
        if (glyphs.isEmpty()) return null
        val result = (reusablePath ?: Path()).apply {
            reset()
            fillType = Path.FillType.WINDING
        }
        var lastKey: String? = null
        var lastFace: ReplayFace? = null
        for (glyph in glyphs) {
            val key = glyph.renderFontKey ?: return null
            if (key != lastKey) {
                lastKey = key
                lastFace = TiqianAndroidFontBackend.replayFace(key) ?: return null
            }
            val face = checkNotNull(lastFace)
            if (face.syntheticBold && face.platformFont != null) return null
            val outline = scaledOutline(
                faceId = key,
                face = face.face,
                glyphId = glyph.id,
                fontSize = fontSize,
                syntheticItalic = face.syntheticItalic,
            ) ?: return null
            result.addPath(outline, originX + glyph.x, originY + glyph.y)
        }
        return result
    }

    private fun scaledOutline(
        faceId: String,
        face: NativeFontFace,
        glyphId: Int,
        fontSize: Float,
        syntheticItalic: Boolean,
    ): Path? {
        val key = OutlineKey(faceId, glyphId, fontSize.toRawBits())
        synchronized(cacheLock) {
            scaledOutlineCache[key]?.let { return it }
        }
        val commands = face.outline(glyphId) ?: return null
        val scale = fontSize / face.unitsPerEm
        val path = decodeOutline(commands, scale).apply {
            if (syntheticItalic) transform(SyntheticItalicMatrix)
        }
        synchronized(cacheLock) {
            scaledOutlineCache[key] = path
            while (scaledOutlineCache.size > MaxCachedScaledOutlines) {
                val iterator = scaledOutlineCache.entries.iterator()
                if (!iterator.hasNext()) break
                iterator.next()
                iterator.remove()
            }
        }
        return path
    }

    private fun decodeOutline(commands: FloatArray, scale: Float): Path {
        val path = Path().apply { fillType = Path.FillType.WINDING }
        var index = 0
        fun x(): Float = commands[index++] * scale
        fun y(): Float = -commands[index++] * scale
        while (index < commands.size) {
            when (commands[index++].toInt()) {
                0 -> path.moveTo(x(), y())
                1 -> path.lineTo(x(), y())
                2 -> path.quadTo(x(), y(), x(), y())
                3 -> path.cubicTo(x(), y(), x(), y(), x(), y())
                4 -> path.close()
                else -> error("Unknown FreeType outline command")
            }
        }
        return path
    }

    private data class OutlineKey(
        val faceId: String,
        val glyphId: Int,
        val fontSizeBits: Int,
    )

    internal fun transformInkBounds(bounds: Rect, syntheticItalic: Boolean): Rect {
        if (!syntheticItalic) return bounds
        val topShift = SyntheticItalicSkewX * bounds.top
        val bottomShift = SyntheticItalicSkewX * bounds.bottom
        return Rect(
            left = minOf(bounds.left + topShift, bounds.left + bottomShift),
            top = bounds.top,
            right = maxOf(bounds.right + topShift, bounds.right + bottomShift),
            bottom = bounds.bottom,
        )
    }

    private const val SyntheticItalicSkewX = -0.25f
    private val SyntheticItalicMatrix = Matrix().apply { setSkew(SyntheticItalicSkewX, 0f) }
}
