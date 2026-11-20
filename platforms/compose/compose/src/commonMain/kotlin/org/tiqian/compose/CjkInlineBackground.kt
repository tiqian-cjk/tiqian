package org.tiqian.compose

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.tiqian.core.RichTextBackgroundMetricPolicy
import org.tiqian.core.RichTextBackgroundDrawStyle
import org.tiqian.core.RichTextBackgroundPaint
import org.tiqian.core.RichTextPaint
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan

/** Renderer-owned inline box over an exact source range in [CjkText]. */
@Immutable
data class CjkInlineBackground(
    val range: TextRange,
    val color: Color,
    val horizontalPadding: Dp = 0.dp,
    val verticalPadding: Dp = 3.dp,
    val cornerRadius: Dp = 3.dp,
    /** Radius on a side where the same background continues on another visual line. */
    val continuationCornerRadius: Dp = cornerRadius,
    val adjacentSameStyleClearance: Dp = 1.dp,
    val drawStyle: CjkInlineBackgroundDrawStyle = CjkInlineBackgroundDrawStyle.Fill,
    val metricPolicy: CjkInlineBackgroundMetricPolicy = CjkInlineBackgroundMetricPolicy.SpanTextStyle,
) {
    init {
        require(!range.collapsed) { "CjkInlineBackground range must not be empty" }
        require(horizontalPadding.value >= 0f)
        require(verticalPadding.value >= 0f)
        require(cornerRadius.value >= 0f)
        require(continuationCornerRadius.value >= 0f)
        require(adjacentSameStyleClearance.value >= 0f)
    }
}

@Immutable
enum class CjkInlineBackgroundMetricPolicy {
    /** Resolve the box from the font metrics of the marked run itself. */
    SpanTextStyle,

    /** Resolve the box from the surrounding paragraph style, independently of inline font scaling. */
    ParagraphTextStyle,
}

@Immutable
sealed interface CjkInlineBackgroundDrawStyle {
    data object Fill : CjkInlineBackgroundDrawStyle

    data class Border(val strokeWidth: Dp = 1.dp) : CjkInlineBackgroundDrawStyle {
        init {
            require(strokeWidth.value > 0f)
        }
    }
}

internal fun CjkInlineBackground.toCore(density: Density): RichTextSpan = RichTextSpan(
    range = org.tiqian.core.TextRange(range.start, range.end),
    role = org.tiqian.core.Background.instance,
    paint = RichTextPaint(
        argb = color.toArgb(),
        background = RichTextBackgroundPaint(
            horizontalPadding = with(density) { horizontalPadding.toPx() },
            verticalPadding = with(density) { verticalPadding.toPx() },
            cornerRadius = with(density) { cornerRadius.toPx() },
            continuationCornerRadius = with(density) { continuationCornerRadius.toPx() },
            metricPolicy = when (metricPolicy) {
                CjkInlineBackgroundMetricPolicy.SpanTextStyle ->
                    RichTextBackgroundMetricPolicy.UniformTextStyle
                CjkInlineBackgroundMetricPolicy.ParagraphTextStyle ->
                    RichTextBackgroundMetricPolicy.UniformParagraphStyle
            },
            drawStyle = when (val style = drawStyle) {
                CjkInlineBackgroundDrawStyle.Fill -> org.tiqian.core.Fill.instance
                is CjkInlineBackgroundDrawStyle.Border -> org.tiqian.core.Border(
                    strokeWidth = with(density) { style.strokeWidth.toPx() },
                )
            },
        ),
        adjacentSameStyleClearance = with(density) { adjacentSameStyleClearance.toPx() },
    ),
)

internal fun defaultInlineCodePaint(density: Density): RichTextPaint = RichTextPaint(
    background = RichTextBackgroundPaint(
        horizontalPadding = with(density) { 4.dp.toPx() },
        verticalPadding = with(density) { 3.dp.toPx() },
        cornerRadius = with(density) { 3.dp.toPx() },
        continuationCornerRadius = with(density) { 1.dp.toPx() },
        metricPolicy = RichTextBackgroundMetricPolicy.UniformParagraphStyle,
    ),
    adjacentSameStyleClearance = with(density) { 1.dp.toPx() },
)
