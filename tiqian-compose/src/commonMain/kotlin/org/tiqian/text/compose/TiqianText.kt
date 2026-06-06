package org.tiqian.text.compose

import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.ParagraphStyle
import org.tiqian.text.core.TextStyle
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.layout.ParagraphLayoutEngine

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

