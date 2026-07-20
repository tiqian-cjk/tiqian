package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.sp
import org.tiqian.core.TextStyle

/**
 * Compose-facing text style (ADR 0030 follow-up): the frontend's idiomatic style,
 * in Compose units (`TextUnit`/`Color`/`FontFamily`). **Narrow + honest** — it
 * exposes ONLY the knobs Tiqian actually consumes, so a caller never silently sets
 * an unsupported attribute (the reason we do NOT reuse Compose's 30-field
 * `androidx…TextStyle`). Lowered to the engine's px [TextStyle] via
 * [toCoreTextStyle] at the composable boundary using `LocalDensity` — the caller
 * no longer hand-multiplies density.
 *
 * [fontSize] is ABSOLUTE → use `.sp` (density + fontScale aware). The Compose
 * [TextStyle][androidx.compose.ui.text.TextStyle] bridge resolves paragraph-level
 * `.em` against its explicit [toCjkTextStyle] default before constructing this
 * style. [lineHeight] `Unspecified` = engine default (1.5em); when set it
 * overrides `ParagraphStyle.lineHeight`. Span-level sizes
 * (`SpanStyle.fontSize` inside an `AnnotatedString`) may be `.em` (relative to this
 * base) or `.sp` — both resolved with the same density.
 */
data class CjkTextStyle(
    val fontSize: TextUnit = 16.sp,
    val lineHeight: TextUnit = TextUnit.Unspecified,
    val color: Color = Color.Unspecified,
    val fontFamily: FontFamily? = null,
    val fontWeight: FontWeight = FontWeight.Normal,
    val fontStyle: FontStyle = FontStyle.Normal,
    val locale: String = "zh-Hans",
)

/** Lower to the engine's px [TextStyle]; [CjkTextStyle.fontSize] must be `.sp`. */
fun CjkTextStyle.toCoreTextStyle(density: Density): TextStyle = TextStyle(
    fontFamilies = (fontFamily as? GenericFontFamily)?.let { listOf(it.name) } ?: emptyList(),
    fontSize = fontSize.toFontSizePx(density),
    locale = locale,
    fontWeight = fontWeight.weight,
    italic = fontStyle == FontStyle.Italic,
)

/**
 * Migration bridge from Compose's full [androidx.compose.ui.text.TextStyle] to Tiqian's explicit
 * [CjkTextStyle]. Unsupported Compose-only fields are not silently interpreted here; pair this with
 * [cjkTextCompatibility] when deciding whether a rich paragraph can be rendered by Tiqian.
 */
fun ComposeTextStyle.toCjkTextStyle(default: CjkTextStyle = CjkTextStyle()): CjkTextStyle =
    CjkTextStyle(
        fontSize = fontSize.toParagraphFontSize(default.fontSize),
        lineHeight = lineHeight.takeUnless { it == TextUnit.Unspecified } ?: default.lineHeight,
        color = color.takeUnless { it == Color.Unspecified } ?: default.color,
        fontFamily = fontFamily ?: default.fontFamily,
        fontWeight = fontWeight ?: default.fontWeight,
        fontStyle = fontStyle ?: default.fontStyle,
        locale = default.locale,
    )

/** Base draw color as ARGB, or null when unspecified (renderer default = black). */
internal fun CjkTextStyle.colorArgbOrNull(): Int? =
    if (color == Color.Unspecified) null else color.toArgb()

/** [CjkTextStyle.lineHeight] in px, or null when unspecified (engine default). */
internal fun CjkTextStyle.lineHeightPxOrNull(density: Density): Float? =
    when {
        lineHeight == TextUnit.Unspecified -> null
        lineHeight.type == TextUnitType.Em -> fontSize.toFontSizePx(density) * lineHeight.value
        else -> with(density) { lineHeight.toPx() }
    }

private fun TextUnit.toParagraphFontSize(defaultFontSize: TextUnit): TextUnit =
    when {
        this == TextUnit.Unspecified -> defaultFontSize.requireSpFontSize("default.fontSize")
        type == TextUnitType.Em -> defaultFontSize.requireSpFontSize("default.fontSize") * value
        else -> this.requireSpFontSize("TextStyle.fontSize")
    }

private fun TextUnit.toFontSizePx(density: Density): Float =
    with(density) { requireSpFontSize("CjkTextStyle.fontSize").toPx() }

private fun TextUnit.requireSpFontSize(label: String): TextUnit {
    require(type == TextUnitType.Sp) {
        "$label must be an Sp TextUnit. Use Compose TextStyle.toCjkTextStyle(default = ...) to resolve paragraph em."
    }
    return this
}
