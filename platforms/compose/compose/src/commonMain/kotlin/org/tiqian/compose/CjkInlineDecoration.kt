package org.tiqian.compose

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.tiqian.core.RichTextLinePattern
import org.tiqian.core.RichTextPaint
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan

/** A renderer-owned line decoration over an exact source range in [CjkText]. */
@Immutable
data class CjkInlineDecoration(
    val range: TextRange,
    val style: CjkInlineDecorationStyle,
) {
    init {
        require(!range.collapsed) { "CjkInlineDecoration range must not be empty" }
    }
}

@Immutable
sealed interface CjkInlineDecorationStyle {
    /** Dashed underline sharing Tiqian's normal underline position, glue trim and skip-ink rules. */
    data class DashedUnderline(
        val color: Color,
        val strokeWidth: Dp = 1.dp,
        val dashLength: Dp = 3.dp,
        val gapLength: Dp = 2.dp,
        val adjacentSameStyleClearance: Dp = 1.dp,
    ) : CjkInlineDecorationStyle {
        init {
            require(strokeWidth.value > 0f)
            require(dashLength.value > 0f)
            require(gapLength.value > 0f)
            require(adjacentSameStyleClearance.value >= 0f)
        }
    }


    /** Dotted underline sharing the same baseline, glue trim and skip-ink rules. */
    data class DottedUnderline(
        val color: Color = Color.Unspecified,
        val dotDiameter: Dp = 1.5.dp,
        val gapLength: Dp = 2.dp,
        val adjacentSameStyleClearance: Dp = 1.dp,
    ) : CjkInlineDecorationStyle {
        init {
            require(dotDiameter.value > 0f)
            require(gapLength.value > 0f)
            require(adjacentSameStyleClearance.value >= 0f)
        }
    }
}

internal fun CjkInlineDecoration.toCore(density: Density): RichTextSpan = when (val value = style) {
    is CjkInlineDecorationStyle.DashedUnderline -> RichTextSpan(
        range = org.tiqian.core.TextRange(range.start, range.end),
        role = org.tiqian.core.Underline.instance,
        paint = RichTextPaint(
            argb = value.color.toArgb(),
            linePattern = org.tiqian.core.Dashed(
                strokeWidth = with(density) { value.strokeWidth.toPx() },
                dashLength = with(density) { value.dashLength.toPx() },
                gapLength = with(density) { value.gapLength.toPx() },
            ),
            adjacentSameStyleClearance = with(density) { value.adjacentSameStyleClearance.toPx() },
        ),
    )
    is CjkInlineDecorationStyle.DottedUnderline -> RichTextSpan(
        range = org.tiqian.core.TextRange(range.start, range.end),
        role = org.tiqian.core.Underline.instance,
        paint = RichTextPaint(
            argb = value.color.takeUnless { it == Color.Unspecified }?.toArgb(),
            linePattern = org.tiqian.core.Dotted(
                dotDiameter = with(density) { value.dotDiameter.toPx() },
                gapLength = with(density) { value.gapLength.toPx() },
            ),
            adjacentSameStyleClearance = with(density) { value.adjacentSameStyleClearance.toPx() },
        ),
    )
}
