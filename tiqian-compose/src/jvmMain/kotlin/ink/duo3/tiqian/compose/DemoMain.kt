package ink.duo3.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.TextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.singleWindowApplication
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextStyle

private const val PARAGRAPH =
    "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
    "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
    "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
    "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
    "，但也不算太离谱。"

fun main() = singleWindowApplication(title = "Tiqian Compose Demo") {
    // Engine units are physical pixels; map dp at the TextStyle boundary
    // (ADR 0017) so the demo reads at 15dp on any density.
    val fontSizePx = with(LocalDensity.current) { 15.dp.toPx() }
    val textStyle = TextStyle(fontSize = fontSizePx)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        var text by remember { mutableStateOf("") }

        TextField(
            value = text,
            modifier = Modifier.fillMaxWidth(),
            onValueChange = { text = it },
        )
        CjkParagraph(
            text = text,
            modifier = Modifier.fillMaxWidth(),
            textStyle = textStyle,
            paragraphStyle = ParagraphStyle().copy(firstLineIndent = ink.duo3.tiqian.core.Ic(0f))
        )
        CjkParagraph(
            text = PARAGRAPH,
            modifier = Modifier.fillMaxWidth(),
            textStyle = textStyle,
        )
        CjkParagraph(
            text = "他说：“你好，世界。”中文……English——中文。",
            modifier = Modifier.fillMaxWidth(),
            textStyle = textStyle,
        )
        CjkParagraph(
            text = buildAnnotatedString {
                append("他强调：")
                cjkEmphasis { append("豆子新鲜最要紧") }
                append("，烘焙其次。")
            },
            modifier = Modifier.fillMaxWidth(),
            textStyle = textStyle,
        )
    }
}
