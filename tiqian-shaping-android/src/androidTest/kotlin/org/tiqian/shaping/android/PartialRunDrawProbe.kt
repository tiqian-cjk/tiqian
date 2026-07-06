package org.tiqian.shaping.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.text.TextPaint
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.font.FontRole
import java.util.Locale

/**
 * Guards the platform invariant `FullBufferClippedPunctuationDraw` relies on:
 * drawing the WHOLE `中<punct>中` buffer preserves context-driven GSUB (locl 2em
 * dash), while a sub-range draw may fall back to the context-free narrow form.
 * The renderer draws CjkPunctuation clusters full-buffer + clipped, so the
 * full-buffer ink MUST stay ≥ the sub-range ink (and near 2em for `⸺`).
 */
@RunWith(AndroidJUnit4::class)
class PartialRunDrawProbe {
    @Test
    fun scan() {
        val typefaces = SystemAndroidTypefaceResolver()
        val em = 56f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = em
            color = Color.BLACK
            textLocale = Locale.forLanguageTag("zh-Hans")
            typeface = typefaces.resolve(FontRole.CjkPunctuation, emptyList(), 400, false)
        }
        val buffer = "中⸺中"
        fun inkOf(draw: (Canvas) -> Unit): Pair<Int, Int> {
            val bmp = Bitmap.createBitmap(420, 120, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            c.drawColor(Color.WHITE)
            draw(c)
            var l = -1; var r = -1
            for (x in 0 until 420) {
                var ink = false
                for (y in 0 until 120) if (Color.red(bmp.getPixel(x, y)) < 128) { ink = true; break }
                if (ink) { if (l < 0) l = x; r = x }
            }
            return l to r
        }
        val pen1 = paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, 1)

        // A: 子区间绘制(渲染器现状):只画 [1,2),带上下文
        val (al, ar) = inkOf { c -> c.drawTextRun(buffer, 1, 2, 0, buffer.length, 100f, 90f, false, paint) }
        println("PRD partial: ink=$al..$ar w=${ar - al} (${"%.2f".format((ar - al) / em)}em)")

        // B: 整串绘制 + 平移到 cluster 原点 + 裁剪到 cluster 盒
        val (bl, br) = inkOf { c ->
            c.save()
            c.clipRect(100f, 0f, 100f + 2f * em, 120f)
            c.drawTextRun(buffer, 0, buffer.length, 0, buffer.length, 100f - pen1, 90f, false, paint)
            c.restore()
        }
        println("PRD clipped-full: ink=$bl..$br w=${br - bl} (${"%.2f".format((br - bl) / em)}em)")
        kotlin.test.assertTrue(
            (br - bl) >= (ar - al),
            "full-buffer draw must not lose context GSUB: full=${br - bl} partial=${ar - al}",
        )
        kotlin.test.assertTrue(
            (br - bl) >= 1.6f * em,
            "two-em dash drawn full-buffer should ink ≥1.6em, got ${(br - bl) / em}em",
        )
    }
}
