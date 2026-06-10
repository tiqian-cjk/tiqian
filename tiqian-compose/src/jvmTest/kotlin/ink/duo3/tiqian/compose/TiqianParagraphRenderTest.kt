package ink.duo3.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.unit.dp
import androidx.compose.ui.use
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextAlign
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Slice 7 acceptance: TiqianParagraph rendered offscreen must produce real
 * ink. The PNG is written to build/reports for eyeballing; the assertion
 * only checks a sane amount of non-background pixels (glyph forms are
 * already covered by the shaping goldens — this guards the compose wiring:
 * measure pass, canvas interop, blob drawing).
 */
@OptIn(ExperimentalComposeUiApi::class)
class TiqianParagraphRenderTest {

    private val paragraph =
        "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，" +
            "真正让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——" +
            "城市生活忽然多出一个公共客厅。"

    @Test
    fun offscreenRenderProducesInk() {
        ImageComposeScene(width = 380, height = 320) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) {
                TiqianParagraph(
                    text = paragraph,
                    modifier = Modifier.width(320.dp),
                    paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
                )
            }
        }.use { scene ->
            val image = scene.render()

            val reportDir = File("build/reports/tiqian-compose")
            reportDir.mkdirs()
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File(reportDir, "tiqian-paragraph.png").writeBytes(it)
            }

            val pixels = image.toComposeImageBitmap().toPixelMap()
            var inkPixels = 0
            for (y in 0 until pixels.height) {
                for (x in 0 until pixels.width) {
                    val c = pixels[x, y]
                    if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) inkPixels++
                }
            }
            assertTrue(
                inkPixels > 1_000,
                "Expected substantial ink from the rendered paragraph, got $inkPixels dark pixels",
            )
        }
    }
}
