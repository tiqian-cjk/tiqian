package ink.duo3.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.singleWindowApplication
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextAlign

private const val PARAGRAPH =
    "提椠（Tiqian）是一个面向中文正文的 CJK 段落排版引擎。第一阶段的目标不是复刻浏览器级文本系统，" +
        "而是在 shaping 之后、绘制之前的薄薄一层里——字体 fallback、CJK 度量、标点 atom、避头尾修复、" +
        "两端对齐——做出一个可观察、可调试、可扩展的物理模型。换句话说，「功能可以窄，模型必须真」。" +
        "第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、编辑器、IME……这些不是被遗忘，" +
        "而是被故意推后到模型稳定之后。"

fun main() = singleWindowApplication(title = "Tiqian Compose Demo") {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        TiqianParagraph(
            text = PARAGRAPH,
            modifier = Modifier.width(320.dp),
            paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
        )
        TiqianParagraph(
            text = "他说：“你好，世界。”中文……English——中文。",
            modifier = Modifier.width(320.dp),
        )
        TiqianParagraph(
            text = "他强调：模型必须真，不能靠魔法。",
            modifier = Modifier.width(320.dp),
            decorations = listOf(
                ink.duo3.tiqian.core.DecorationSpan(
                    range = ink.duo3.tiqian.core.TextRange(4, 15),
                    kind = ink.duo3.tiqian.core.DecorationKind.Emphasis,
                ),
            ),
        )
    }
}
