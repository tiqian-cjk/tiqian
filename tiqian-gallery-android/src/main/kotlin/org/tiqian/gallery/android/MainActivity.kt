package org.tiqian.gallery.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.tiqian.compose.CjkBlock
import org.tiqian.compose.CjkParagraph
import org.tiqian.compose.CjkText
import org.tiqian.compose.CjkTextStyle
import org.tiqian.compose.ListMarker
import org.tiqian.compose.ParagraphIndent
import org.tiqian.compose.bookTitle
import org.tiqian.compose.emphasis
import org.tiqian.compose.properNoun
import org.tiqian.compose.ruby
import org.tiqian.compose.bopomofo
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.ic

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TiqianGalleryApp() }
    }
}

@Composable
private fun TiqianGalleryApp() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFAF8F2))
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 22.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        CjkParagraph(
            text = "提椠 Android Compose Gallery",
            modifier = Modifier.fillMaxWidth(),
            textStyle = CjkTextStyle(
                fontSize = 24.sp,
                lineHeight = 34.sp,
                color = Color(0xFF15130D),
                fontWeight = FontWeight.SemiBold,
            ),
            paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
        )

        CjkParagraph(
            text = buildAnnotatedString {
                append("这不是桌面截图：这段文字正在 Android Compose 里走 ")
                withStyle(SpanStyle(color = Color(0xFFB33A2B), fontWeight = FontWeight.Bold)) {
                    append("提椠自己的段落排版")
                }
                append("。")
                emphasis { append("标点挤压、禁则、双齐") }
                append(" 都由 layout engine 决定，前端只消费 LayoutResult。")
            },
            modifier = Modifier.fillMaxWidth(),
            textStyle = bodyStyle(),
        )

        CjkParagraph(
            text = buildAnnotatedString {
                append("行间注验证：")
                ruby("北京", "Běijīng")
                append(" 与 ")
                bopomofo("中", "ㄓㄨㄥ")
                append(" 字共处一行；")
                properNoun { append("王安石") }
                append(" 写 ")
                bookTitle { append("泊船瓜洲") }
                append("，")
                withStyle(SpanStyle(fontFamily = FontFamily.Serif)) {
                    append("春风又绿江南岸")
                }
                append("。")
            },
            modifier = Modifier.fillMaxWidth(),
            textStyle = bodyStyle(),
        )

        CjkText(
            blocks = listOf(
                CjkBlock.Paragraph(
                    "段落 gallery 使用 CjkText 的多段模型。首行缩进、整数行长、末行对齐和段内行距仍然来自同一个引擎——Android 只是给出真实字体测量与真实画布。",
                ),
                CjkBlock.List.ofStrings(
                    items = listOf(
                        "列表标记顶格，正文列缩进；续行必须落回同一正文列。",
                        "数字到 10. 之后，标记列宽会按真实字体宽度升到足够的 ic。",
                        "中西混排 English typography should wrap without leaking rules into Compose.",
                    ),
                    marker = ListMarker.Decimal,
                ),
                CjkBlock.Paragraph(
                    text = "这是一段块缩排引文。它用 Android target 的同一套公开 API 渲染，验证库消费者不需要知道 Skia 或 TextPaint 的内部差异。",
                    indent = ParagraphIndent.Block(indent = 2.ic),
                ),
            ),
            modifier = Modifier.fillMaxWidth(),
            textStyle = bodyStyle(),
        )

        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun bodyStyle(): CjkTextStyle =
    CjkTextStyle(
        fontSize = 17.sp,
        lineHeight = 29.sp,
        color = Color(0xFF242018),
        locale = "zh-Hans",
    )
