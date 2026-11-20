package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PixelMap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RichTextLineSegment
import org.tiqian.core.Size
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.fittedDottedLineCenters
import org.tiqian.core.ic
import org.tiqian.core.richTextDecorationLineY
import org.tiqian.core.toReplayIndex
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaSystemTypefaces
import org.tiqian.shaping.skia.SkiaTextShaper
import org.tiqian.shaping.skia.lineInkSkipIntervals
import org.jetbrains.skia.Font
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.shaper.Shaper
import kotlin.math.floor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `text-decoration-skip-ink` (Compose lacks it): the 行间线 must break around
 * glyph ink that crosses it. Skia's `getIntercepts` finds those crossings — a
 * Western descender does, the CJK face (which sits above the line) does not.
 */
class SkipInkTest {

    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = SkiaTextShaper(),
        fontMetricsResolver = SkiaFontMetricsResolver(),
    )
    private val size = 40f
    private val cjkFont = Font(SkiaSystemTypefaces.typeface(false, "serif", FontStyle.NORMAL), size)
    private val latinFont = Font(requireNotNull(SkiaSystemTypefaces.typeface(true, "serif", FontStyle.NORMAL)), size)
    private val shaper = Shaper.makeShaperDrivenWrapper()

    private fun properNounSkips(text: String): FloatArray {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = TextStyle(fontSize = size, fontFamilies = listOf("serif")),
                constraints = LayoutConstraints(maxWidth = 9999f),
                decorations = listOf(DecorationSpan(TextRange(0, text.length), DecorationKind.ProperNoun)),
            ),
        )
        val seg = result.debug.decorationSegments.first { it.kind == "ProperNoun" }
        return result.lineInkSkipIntervals(
            result.lines[seg.lineIndex], cjkFont, latinFont, shaper, seg.top - 2f, seg.top + 2f,
        )
    }

    @Test
    fun westernDescenderBreaksTheUnderline() {
        assertTrue(properNounSkips("Page").isNotEmpty(), "the g descender must cross the 专名号 line")
    }

    @Test
    fun pureCjkUnderlineStaysContinuous() {
        assertTrue(properNounSkips("中文名").isEmpty(), "CJK face is above the line — nothing to skip")
    }

    @Test
    fun dottedFixturePlacesRealInkOnlyInTheOversizedBand() {
        val fixture = dottedFixture(inkOverlapsDot = false)
        assertTrue(fixture.narrowSkips.isEmpty(), "ink must be outside the dot's actual vertical band")
        assertTrue(fixture.wideSkips.isNotEmpty(), "ink must cross the old oversized vertical band")
        assertTrue(
            fixture.centers.any { overlapsInk(it, fixture.wideSkips, DOT_DIAMETER / 2f) },
            "the oversized band must intersect a complete candidate dot",
        )
        assertTrue(
            fixture.centers.all { it >= 0f && it < fixture.pixels.width } &&
                fixture.lineY >= 0f && fixture.lineY < fixture.pixels.height,
            "all candidate dots must be inside the captured image",
        )
    }

    @Test
    fun dottedFixturePlacesRealInkInTheActualDotBand() {
        val fixture = dottedFixture(inkOverlapsDot = true)
        assertTrue(fixture.narrowSkips.isNotEmpty(), "ink must cross the dot's actual vertical band")
        assertTrue(
            fixture.centers.any { overlapsInk(it, fixture.narrowSkips, DOT_DIAMETER / 2f) },
            "the actual band must intersect a complete candidate dot",
        )
        assertTrue(
            fixture.centers.any { !overlapsInk(it, fixture.narrowSkips, DOT_DIAMETER * 2f) },
            "the fixture must also contain candidate dots away from the ink",
        )
    }

    @Test
    fun dottedUnderlinePaintsCompleteDotsWhenActualBandHasNoInk() {
        val fixture = dottedFixture(inkOverlapsDot = false)
        assertTrue(fixture.centers.size >= 3, "the marked range must fit several complete dots")
        val missing = fixture.centers.filterNot { fixture.pixels.hasDotAt(it, fixture.lineY) }
        assertTrue(
            missing.isEmpty(),
            "dots with no ink in their real vertical band must be painted: missing=$missing " +
                "centers=${fixture.centers.toList()} lineY=${fixture.lineY}",
        )
    }

    @Test
    fun dottedUnderlineStillSkipsRealInkAndPaintsAwayFromIt() {
        val fixture = dottedFixture(inkOverlapsDot = true)
        val intersecting = fixture.centers.filter { overlapsInk(it, fixture.narrowSkips, DOT_DIAMETER / 2f) }
        val clear = fixture.centers.filterNot { overlapsInk(it, fixture.narrowSkips, DOT_DIAMETER * 2f) }
        assertTrue(intersecting.isNotEmpty(), "fixture must contain a dot crossing actual glyph ink")
        assertTrue(clear.isNotEmpty(), "fixture must contain a dot sufficiently far from glyph ink")
        assertTrue(
            intersecting.none { fixture.pixels.hasDotAt(it, fixture.lineY) },
            "dots crossing glyph ink must remain skipped: $intersecting",
        )
        assertTrue(
            clear.all { fixture.pixels.hasDotAt(it, fixture.lineY) },
            "dots away from glyph ink must remain visible: $clear",
        )
    }

    private data class DottedFixture(
        val pixels: PixelMap,
        val lineY: Float,
        val centers: FloatArray,
        val narrowSkips: FloatArray,
        val wideSkips: FloatArray,
    )

    /**
     * A real serif Skia glyph supplies the ink. The system's default Latin candidates may be
     * absent, so shaping, outline queries and CjkText all use the same resolved serif family.
     * A positioned inline span moves the glyph relative to an underline on the preceding space;
     * its vertical position is derived from that font's ink bounds, not a presumed descent.
     */
    @OptIn(ExperimentalComposeUiApi::class)
    private fun dottedFixture(inkOverlapsDot: Boolean): DottedFixture {
        val fontSize = 40f
        val text = " g"
        val density = Density(1f)
        val fixtureStyle = CjkTextStyle(fontSize = fontSize.sp, color = Color.Black, fontFamily = FontFamily.Serif)
        val coreStyle = fixtureStyle.toCoreTextStyle(density)
        assertEquals(listOf("serif"), coreStyle.fontFamilies, "fixture must use the renderer's serif mapping")
        val serifTypeface = requireNotNull(
            SkiaSystemTypefaces.typeface(isLatin = true, family = coreStyle.fontFamilies.single(), style = FontStyle.NORMAL),
        ) { "fixture requires an installed serif typeface containing 'g'" }
        val serifFont = Font(serifTypeface, fontSize)
        val initial = createPlatformParagraphMeasurer().measure(
            text = text,
            constraints = LayoutConstraints(maxWidth = 320f),
            textStyle = coreStyle,
            paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
            sourceBoundaries = setOf(1),
        )
        val decorationRight = 84f
        val radius = DOT_DIAMETER / 2f
        val decoration = CjkInlineDecoration(
            range = androidx.compose.ui.text.TextRange(0, 1),
            style = CjkInlineDecorationStyle.DottedUnderline(
                color = Color.Magenta,
                dotDiameter = DOT_DIAMETER.dp,
                gapLength = DOT_GAP.dp,
            ),
        )
        val spaceRange = TextRange(0, 1)
        val glyphRange = TextRange(1, 2)
        assertEquals(0f, initial.lines.single().indent, "fixture must start at x=0")
        assertEquals("LatinText", initial.debug.fontDecisions.single { it.range == glyphRange }.role)
        // The widened synthetic space must fit in the measured node, not just the parent scene.
        val baseResult = initial.copy(
            size = Size(width = 120f, height = initial.size.height),
            clusters = initial.clusters.map { cluster ->
                when (cluster.range) {
                    spaceRange -> cluster.copy(advance = decorationRight)
                    glyphRange -> cluster.copy(glyphInlineShift = 36f - decorationRight)
                    else -> cluster
                }
            },
            debug = initial.debug.copy(geometryDecisions = emptyList(), autoSpaceDecisions = emptyList()),
        )
        val initialSegment = baseResult.toReplayIndex(listOf(decoration.toCore(density)))
            .richTextDecorationSegments.single()
        val initialLineY = baseResult.richTextDecorationLineY(initialSegment, DOT_DIAMETER)
        val targetInkBottom = initialLineY - if (inkOverlapsDot) radius * 0.25f else radius * 1.5f
        val glyph = serifFont.getUTF32Glyph('g'.code)
        assertTrue(glyph.toInt() != 0, "fixture typeface ${serifTypeface.familyName} must contain 'g'")
        assertEquals(
            glyph.toUShort().toUInt(),
            initial.glyphRuns.flatMap { it.glyphs }.single { it.clusterRange == glyphRange }.id,
            "the measured glyph must come from the same serif face used by the renderer",
        )
        val bounds = serifFont.getBounds(shortArrayOf(glyph)).single()
        assertTrue(
            bounds.bottom > bounds.top && bounds.right > bounds.left,
            "fixture typeface ${serifTypeface.familyName} requires a nonempty 'g' outline: $bounds",
        )
        val shift = targetInkBottom - initial.lines.single().baseline - bounds.bottom
        val annotated = buildAnnotatedString {
            append(" ")
            withStyle(SpanStyle(baselineShift = BaselineShift(-shift / fontSize))) {
                append("g")
            }
        }
        val spans = annotated.cjkStyleSpans(baseResult.input.textStyle, density)
        val result = baseResult.copy(
            input = baseResult.input.copy(content = baseResult.input.content.copy(spans = spans)),
            clusters = baseResult.clusters.map { cluster ->
                if (cluster.range == glyphRange) cluster.copy(baselineShift = shift) else cluster
            },
        )
        val segment: RichTextLineSegment = result.toReplayIndex(listOf(decoration.toCore(density)))
            .richTextDecorationSegments.single()
        assertTrue(segment.right + radius <= result.size.width, "the whole dotted span must fit inside the text node")
        val lineY = result.richTextDecorationLineY(segment, DOT_DIAMETER)
        cjkFont.size = fontSize
        val centers = fittedDottedLineCenters(
            segment.left, segment.right, segment.left, segment.right, DOT_DIAMETER, DOT_GAP,
        )
        val narrowSkips = result.lineInkSkipIntervals(
            result.lines.single(), cjkFont, serifFont, shaper,
            lineY - radius, lineY + radius, spans,
        )
        val wideSkips = result.lineInkSkipIntervals(
            result.lines.single(), cjkFont, serifFont, shaper,
            lineY - DOT_DIAMETER, lineY + DOT_DIAMETER, spans,
        )
        serifFont.close()
        var rendered: LayoutResult? = null
        val pixels = ImageComposeScene(width = 400, height = 120, density = density) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    text = annotated,
                    modifier = Modifier.width(320.dp),
                    textStyle = fixtureStyle,
                    inlineDecorations = listOf(decoration),
                    precomputedLayout = result,
                    onTextLayout = { rendered = it },
                )
            }
        }.use { scene -> scene.render().toComposeImageBitmap().toPixelMap() }
        assertTrue(rendered === result, "the production renderer must use the prepared layout")
        assertEquals(1, result.lines.size)
        assertTrue(
            (0 until pixels.height).any { y ->
                (0 until pixels.width).any { x ->
                    val color = pixels[x, y]
                    color.red < 0.4f && color.green < 0.4f && color.blue < 0.4f
                }
            },
            "the production renderer must paint the fixture glyph",
        )
        return DottedFixture(pixels, lineY, centers, narrowSkips, wideSkips)
    }

    private fun overlapsInk(center: Float, skips: FloatArray, padding: Float): Boolean =
        (0 until skips.size / 2).any { index ->
            center >= skips[index * 2] - padding && center <= skips[index * 2 + 1] + padding
        }

    private fun PixelMap.hasDotAt(center: Float, lineY: Float): Boolean {
        val x = floor(center).toInt()
        val y = floor(lineY).toInt()
        require(x in 0 until width && y in 0 until height) { "dot is outside the image: ($center, $lineY)" }
        val color = this[x, y]
        return color.red > 0.7f && color.blue > 0.7f && color.green < 0.45f
    }

    private companion object {
        const val DOT_DIAMETER = 4f
        const val DOT_GAP = 6f
    }
}
