package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.TextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.singleWindowApplication

fun main() = singleWindowApplication(title = "Tiqian Compose Demo") {
    // CjkTextStyle: `.sp` is lowered to engine px via density inside the composable.
    val textStyle = CjkTextStyle(fontSize = 15.sp)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // 实时重排：在输入框打字，下面这段会跟着重新排版（measure+draw Modifier.Node）。
        var draft by remember { mutableStateOf("在这里打字，看我实时重排……") }
        TextField(
            value = draft,
            modifier = Modifier.fillMaxWidth(),
            onValueChange = { draft = it },
        )
        CjkText(text = draft, modifier = Modifier.fillMaxWidth(), textStyle = textStyle)

        // 小品文：把目前的排版能力一次用全。
        CjkText(
            blocks = remember { essayBlocks() },
            modifier = Modifier.fillMaxWidth(),
            textStyle = textStyle,
        )
    }
}

private val ACCENT_RED = Color(0xFFB00020)
private val ACCENT_GREEN = Color(0xFF1A6E3C)

/** A playful self-portrait of the engine that exercises every current capability. */
private fun essayBlocks(): List<CjkBlock> = listOf(
    // 标题：大字 + 粗体，不缩进。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            withStyle(SpanStyle(fontSize = 1.9.em, fontWeight = FontWeight.Bold)) {
                append("一台排版引擎的自述")
            }
        },
        indent = ParagraphIndent.Flush,
    ),

    // 开场：拼音 ruby、着重号、中西自动间距、标点。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("诸位好。我叫")
            ruby("提椠", "tíqiàn")
            append("，一台对中文正文")
            emphasis { append("斤斤计较") }
            append("的排版引擎。别家把 espresso 和汉字一锅乱炖，我偏要在中西之间留出")
            emphasis { append("四分之一个字") }
            append("的体面距离——你瞧，连这句里的 OpenType，我都没让它贴脸。")
        },
    ),

    CjkBlock.Section,

    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("我的")
            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("家规") }
            append("不多，列在下面：")
        },
        indent = ParagraphIndent.Flush,
    ),

    // 编号列表（汉字编号）：富文本表项 + 字体族。
    CjkBlock.List(
        items = listOf(
            buildAnnotatedString {
                append("标点不许在行首撒野：逗号句号一律")
                emphasis { append("避头尾") }
                append("，该挤就挤，该悬就悬。")
            },
            buildAnnotatedString {
                append("字体随你挑——")
                withStyle(SpanStyle(fontFamily = FontFamily.Serif)) { append("宋体的雅") }
                append("、")
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append("等宽的拙") }
                append("，按角色各取所需。")
            },
            buildAnnotatedString {
                append("注音拼音都伺候，连")
                ruby("生僻字", "shēngpì zì")
                append("也给你标得明明白白。")
            },
        ),
        marker = ListMarker.CjkNumber(),
    ),

    CjkBlock.Section,

    // 示亡号：悼念上轮删掉的 printingSides（自嘲）。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("上周我还痛失一员旧部：")
            mourning { append("双面印刷") }
            append("。它本为纸张正反透印而生，奈何屏幕没有背面，只好请它")
            emphasis { append("先走一步") }
            append("。")
        },
    ),

    // 注音：右侧竖排 ㄅㄆㄇ + 声调。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("台湾来的朋友也照顾周到——")
            bopomofo("您", "ㄋㄧㄣˊ")
            bopomofo("好", "ㄏㄠˇ")
            append("，")
            bopomofo("请", "ㄑㄧㄥˇ")
            append("坐：ㄅㄆㄇ 竖在字旁，平上去入标得")
            emphasis { append("分毫不差") }
            append("。")
        },
    ),

    CjkBlock.Section,

    // 整段缩排（引用）+ 专名号 + 书名号。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("我奉")
            properNoun { append("CLREQ") }
            append("——也就是")
            bookTitle { append("《中文排版需求》") }
            append("——为圭臬，闲来也翻翻")
            properNoun { append("Unicode") }
            append("的家底。")
        },
        indent = ParagraphIndent.Block(),
    ),

    CjkBlock.Paragraph(
        buildAnnotatedString { append("顺带一提，这些我也顺手包办：") },
        indent = ParagraphIndent.Flush,
    ),

    // 项目符号列表：点名几条全自动的引擎活儿。
    CjkBlock.List(
        items = listOf(
            buildAnnotatedString { append("整数字格行长，正文严丝合缝落在格子上；") },
            buildAnnotatedString { append("行尾标点悬挂、中西自动间距，统统全自动；") },
            buildAnnotatedString { append("挤一挤放得下的，绝不硬把一整行拉稀。") },
        ),
        marker = ListMarker.Bullet(),
    ),

    CjkBlock.Section,

    // 收尾：斜体 + 颜色 + 大字粗体。
    CjkBlock.Paragraph(
        buildAnnotatedString {
            append("有人嫌我")
            withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append("龟毛") }
            append("，我只当是")
            withStyle(SpanStyle(color = ACCENT_RED)) { append("褒奖") }
            append("。毕竟，好看的中文，是")
            withStyle(SpanStyle(fontSize = 1.3.em, fontWeight = FontWeight.Bold, color = ACCENT_GREEN)) {
                append("一个字一个字")
            }
            append("抠出来的。")
        },
    ),
)
