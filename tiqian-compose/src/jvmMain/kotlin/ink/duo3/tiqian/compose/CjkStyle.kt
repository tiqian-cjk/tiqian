package ink.duo3.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.GenericFontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import ink.duo3.tiqian.core.TextStyle

/**
 * Compose-facing text style (ADR 0030 follow-up): the frontend's idiomatic style,
 * in Compose units (`TextUnit`/`Color`/`FontFamily`). **Narrow + honest** — it
 * exposes ONLY the knobs Tiqian actually consumes, so a caller never silently sets
 * an unsupported attribute (the reason we do NOT reuse Compose's 30-field
 * `androidx…TextStyle`). Lowered to the engine's px [TextStyle] via
 * [toCoreTextStyle] at the composable boundary using `LocalDensity` — the caller
 * no longer hand-multiplies density.
 *
 * [fontSize] is ABSOLUTE → use `.sp` (density + fontScale aware; `.em` has no base
 * to resolve against and will throw). [lineHeight] `Unspecified` = engine default
 * (1.5em); when set it overrides `ParagraphStyle.lineHeight`. Span-level sizes
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
    fontSize = with(density) { fontSize.toPx() },
    locale = locale,
    fontWeight = fontWeight.weight,
    italic = fontStyle == FontStyle.Italic,
)

/** Base draw color as ARGB, or null when unspecified (renderer default = black). */
internal fun CjkTextStyle.colorArgbOrNull(): Int? =
    if (color == Color.Unspecified) null else color.toArgb()

/** [CjkTextStyle.lineHeight] in px, or null when unspecified (engine default). */
internal fun CjkTextStyle.lineHeightPxOrNull(density: Density): Float? =
    if (lineHeight == TextUnit.Unspecified) null else with(density) { lineHeight.toPx() }
