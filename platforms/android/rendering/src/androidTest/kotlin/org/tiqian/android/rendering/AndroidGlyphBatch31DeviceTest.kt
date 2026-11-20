package org.tiqian.android.rendering

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.fonts.SystemFonts
import androidx.annotation.RequiresApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals

@RunWith(AndroidJUnit4::class)
@RequiresApi(31)
class AndroidGlyphBatch31DeviceTest {
    @Test
    @SdkSuppress(minSdkVersion = 31)
    fun flushingPreviousBatchPreservesPendingRunPaint() {
        val canvas = Canvas(Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888))
        val font = SystemFonts.getAvailableFonts().first()
        val paint = Paint().apply {
            color = Color.BLACK
            textSize = 36f
        }
        val batch = AndroidGlyphBatch31()

        batch.append(canvas, paint, font, glyphId = 0, x = 0f, y = 36f)
        paint.apply {
            color = Color.BLUE
            textSize = 18f
            isFakeBoldText = true
            textSkewX = -0.25f
        }

        batch.append(canvas, paint, font, glyphId = 0, x = 18f, y = 36f)

        assertEquals(Color.BLUE, paint.color)
        assertEquals(18f, paint.textSize)
        assertEquals(true, paint.isFakeBoldText)
        assertEquals(-0.25f, paint.textSkewX)
    }
}
