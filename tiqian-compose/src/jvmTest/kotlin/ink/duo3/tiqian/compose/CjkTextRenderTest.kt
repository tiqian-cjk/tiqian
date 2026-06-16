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
import ink.duo3.tiqian.core.TextStyle
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * `CjkText` stacks multiple paragraphs (CLREQ §6.2.1). The PNGs are written for
 * eyeballing the 段首缩排 styles; the assertion guards the wiring — each lead
 * style renders all paragraphs with substantial ink.
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkTextRenderTest {

    private val article = listOf(
        "咖啡馆比咖啡更早地改变了城里人的作息与谈吐，读报、辩论、写作都在这里发生。",
        "最初它被当作药物出售，价格高得吓人，真正让它流行的是随后遍地开花的咖啡馆。",
        "有人说先有咖啡馆，后有启蒙运动。这话说得夸张，但也不算太离谱。",
    )

    private fun render(name: String, style: ParagraphLeadStyle): Int {
        var inkPixels = 0
        ImageComposeScene(width = 380, height = 720) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) {
                CjkText(
                    paragraphs = article,
                    modifier = Modifier.width(320.dp),
                    textStyle = TextStyle(fontSize = 30f),
                    leadStyle = style,
                )
            }
        }.use { scene ->
            val image = scene.render()
            val reportDir = File("build/reports/tiqian-compose").apply { mkdirs() }
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File(reportDir, "cjk-text-$name.png").writeBytes(it)
            }
            val pixels = image.toComposeImageBitmap().toPixelMap()
            for (y in 0 until pixels.height) {
                for (x in 0 until pixels.width) {
                    val c = pixels[x, y]
                    if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) inkPixels++
                }
            }
        }
        return inkPixels
    }

    @Test
    fun eachLeadStyleRendersAllParagraphs() {
        for (style in ParagraphLeadStyle.entries) {
            val ink = render(style.name, style)
            assertTrue(ink > 2_000, "Expected substantial ink for $style, got $ink")
        }
    }
}
