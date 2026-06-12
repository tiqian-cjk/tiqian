package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
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
        "有人说：「先有咖啡馆，后有启蒙运动」。每座城市、每条街巷、每个清晨都有人在等一杯 espresso……这并不是巧合。",
        "读报、辩论、下棋、写作——城市生活忽然多出一个公共客厅。",
    )

    private val widths = listOf(48f, 64f, 80f, 100f, 160f, 320f)

    @Test
    fun punctuationNeverResolvesBelowItsBodyWidth() {
        val engine = ExplainableStubParagraphLayoutEngine()
        for (text in fixtures) {
            for (maxWidth in widths) {
                val result = engine.layout(
                    LayoutInput(
                        content = TiqianTextContent(text),
                        constraints = LayoutConstraints(maxWidth = maxWidth),
                        paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                    ),
                )
                result.debug.geometryDecisions.forEach { geometry ->
                    assertTrue(
                        geometry.resolvedAdvance >= geometry.bodyWidth - 1e-3f,
                        "Body floor violated for '${geometry.sourceText}' " +
                            "(${geometry.range.start}-${geometry.range.end}) in \"$text\" " +
                            "@maxWidth=$maxWidth: " +
                            "resolved=${geometry.resolvedAdvance} < body=${geometry.bodyWidth}",
                    )
                }
            }
        }
    }
}
