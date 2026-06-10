package ink.duo3.tiqian.compose

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.ParagraphLayoutEngine

data class TiqianTextRequest(
    val text: String,
    val textStyle: TextStyle = TextStyle(),
    val paragraphStyle: ParagraphStyle = ParagraphStyle(),
    val constraints: LayoutConstraints,
)

class TiqianTextMeasurer(
    private val engine: ParagraphLayoutEngine = ExplainableStubParagraphLayoutEngine(),
) {
    fun measure(request: TiqianTextRequest): LayoutResult =
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(request.text),
                textStyle = request.textStyle,
                paragraphStyle = request.paragraphStyle,
                constraints = request.constraints,
            ),
        )
}

