package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextAlign
import ink.duo3.tiqian.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * The additive punctuation model's hard floor (ADR 0004): a punctuation
 * atom's minimum width is its half-width `bodyWidth` (the `halt`-style
 * 0.5em). Every consumer — spacing compression, PushIn, line-edge trim,
 * justification — may only ever spend GLUE; the body is untouchable.
 *
 * This test sweeps punctuation-dense fixtures through narrow, justified
 * layouts (maximising compression pressure) and asserts the invariant
 * `resolvedAdvance >= bodyWidth` for every punctuation cluster on every
 * line. If any future consumer starts eating into the body, this fails.
 */
class PunctuationBodyFloorInvariantTest {

    private val fixtures = listOf(
        "中文，中文。",
        "他说：“你好，世界。”！！",
        "中（中文）文中文中文中",
        "换句话说，「功能可以窄，模型必须真」。第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、编辑器、IME……这些不是被遗忘。",
        "量、标点、修复、对齐——做出一个可观察、可调试、可扩展的物理模型。",
    )

    private val widths = listOf(48f, 64f, 80f, 100f, 160f, 320f)

    @Test
    fun punctuationNeverResolvesBelowItsBodyWidth() {
        val engine = ExplainableStubParagraphLayoutEngine()
        for (text in fixtures) {
            for (maxWidth in widths) {
                for (align in listOf(TextAlign.Start, TextAlign.Justify)) {
                    val result = engine.layout(
                        LayoutInput(
                            content = TiqianTextContent(text),
                            constraints = LayoutConstraints(maxWidth = maxWidth),
                            paragraphStyle = ParagraphStyle(textAlign = align),
                        ),
                    )
                    result.debug.geometryDecisions.forEach { geometry ->
                        assertTrue(
                            geometry.resolvedAdvance >= geometry.bodyWidth - 1e-3f,
                            "Body floor violated for '${geometry.sourceText}' " +
                                "(${geometry.range.start}-${geometry.range.end}) in \"$text\" " +
                                "@maxWidth=$maxWidth align=$align: " +
                                "resolved=${geometry.resolvedAdvance} < body=${geometry.bodyWidth}",
                        )
                    }
                }
            }
        }
    }
}
