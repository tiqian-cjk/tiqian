package ink.duo3.tiqian.androidview

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.ParagraphLayoutEngine

data class TiqianTextViewState(
    val text: String,
    val constraints: LayoutConstraints,
    val lastLayout: LayoutResult? = null,
)

class TiqianTextViewLayoutAdapter(
    private val engine: ParagraphLayoutEngine = ExplainableStubParagraphLayoutEngine(),
) {
    fun layout(state: TiqianTextViewState): LayoutResult =
        engine.layout(
            LayoutInput(
                content = TiqianTextContent(state.text),
                constraints = state.constraints,
            ),
        )
}

