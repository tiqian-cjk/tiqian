package org.tiqian.text.androidview

import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.layout.ParagraphLayoutEngine

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

