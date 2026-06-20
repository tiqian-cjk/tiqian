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
import androidx.compose.ui.unit.sp
import ink.duo3.tiqian.core.ic
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * `CjkText` stacks paragraphs and sections (CLREQ §6.2.1). PNGs are written for
 * eyeballing the 段首缩排/凸排/段落缩排 styles; the assertion guards the wiring.
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkTextRenderTest {

    private val article = listOf(
        "咖啡馆比咖啡更早地改变了城里人的作息与谈吐，读报、辩论、写作都在这里发生。",
        "最初它被当作药物出售，价格高得吓人，真正让它流行的是随后遍地开花的咖啡馆。",
        "有人说先有咖啡馆，后有启蒙运动。这话说得夸张，但也不算太离谱。",
    )

    private fun render(name: String, content: @androidx.compose.runtime.Composable () -> Unit): Int {
        var ink = 0
        ImageComposeScene(width = 380, height = 760) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) { content() }
        }.use { scene ->
            val image = scene.render()
            File("build/reports/tiqian-compose").apply { mkdirs() }
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File("build/reports/tiqian-compose", "cjk-text-$name.png").writeBytes(it)
            }
            val pixels = image.toComposeImageBitmap().toPixelMap()
            for (y in 0 until pixels.height) for (x in 0 until pixels.width) {
                val c = pixels[x, y]
                if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) ink++
            }
        }
        return ink
    }

    @Test
    fun eachLeadStyleRendersAllParagraphs() {
        for (style in ParagraphLeadStyle.entries) {
            val ink = render(style.name) {
                CjkText(
                    text = article.joinToString("\n"),
                    modifier = Modifier.width(320.dp),
                    textStyle = CjkTextStyle(fontSize = 30.sp),
                    leadStyle = style,
                )
            }
            assertTrue(ink > 2_000, "Expected substantial ink for $style, got $ink")
        }
    }

    @Test
    fun mixedBlocksRenderHangingQuoteAndSection() {
        val blocks = listOf(
            CjkBlock.Paragraph(
                "张三说道：今天天气不错，咱们出去走走吧，顺便买点咖啡豆回来配下午茶。",
                ParagraphIndent.Hanging(2.ic),
            ),
            CjkBlock.Section,
            CjkBlock.Paragraph(
                "他引用一句诗：采菊东篱下，悠然见南山，此中有真意，欲辨已忘言。",
                ParagraphIndent.Block(2.ic),
            ),
            CjkBlock.Paragraph(
                "回到正文，咖啡馆比咖啡更早地改变了城里人的作息与谈吐与往来。",
                ParagraphIndent.FirstLine,
            ),
        )
        val ink = render("mixed") {
            CjkText(blocks = blocks, modifier = Modifier.width(320.dp), textStyle = CjkTextStyle(fontSize = 30.sp))
        }
        assertTrue(ink > 2_000, "Expected substantial ink for mixed blocks, got $ink")
    }
}
