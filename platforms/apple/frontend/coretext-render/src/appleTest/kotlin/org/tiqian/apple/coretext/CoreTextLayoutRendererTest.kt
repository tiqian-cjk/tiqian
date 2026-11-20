package org.tiqian.apple.coretext

import kotlinx.cinterop.convert
import kotlinx.cinterop.get
import kotlinx.cinterop.reinterpret
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.Link
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import platform.CoreGraphics.CGBitmapContextCreate
import platform.CoreGraphics.CGBitmapContextGetData
import platform.CoreGraphics.CGColorSpaceCreateDeviceRGB
import platform.CoreGraphics.CGColorSpaceRelease
import platform.CoreGraphics.CGContextFillRect
import platform.CoreGraphics.CGContextRelease
import platform.CoreGraphics.CGContextSetRGBFillColor
import platform.CoreGraphics.CGImageAlphaInfo
import platform.CoreGraphics.CGRectMake
import kotlinx.cinterop.UByteVar
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Runtime validation that the Core Text renderer draws glyph ink AND distributes lines
 * vertically. The band test is the regression guard for the "all lines collapsed onto
 * one baseline" bug (drawing the pre-line-break glyph run instead of re-shaping per
 * positioned cluster): a collapse concentrates all ink in a single band.
 */
class CoreTextLayoutRendererTest {

    @Test
    fun rendersGlyphInkForCjkParagraph() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文渲染测试提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )
        val bands = renderInkBands(result, width = 256, bands = 1)
        assertTrue(bands[0] > 30, "expected glyph ink, got ${bands[0]} (lines=${result.lines.size})")
    }

    @Test
    fun distributesLinesAcrossVerticalBands() {
        // Long text at a narrow measure → many lines. Correct rendering spreads ink down
        // the whole column; the collapse bug would pile every line into one band.
        val text = "这是一段足够长的中文正文，用来验证多行文本在垂直方向被正确铺开，" +
            "而不是全部塌在同一条基线上；它应当产生很多行，墨迹从顶部一直分布到底部。"
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = TextStyle(fontSize = 20f),
                constraints = LayoutConstraints(maxWidth = 120f),
            ),
        )
        assertTrue(result.lines.size >= 5, "need many lines for the band test, got ${result.lines.size}")

        val bands = renderInkBands(result, width = 160, bands = 4)
        val bandsWithInk = bands.count { it > 5 }
        assertTrue(
            bandsWithInk >= 3,
            "lines collapsed: only $bandsWithInk/4 vertical bands have ink " +
                "(per-band ink=${bands.toList()}, lines=${result.lines.size})",
        )
    }

    @Test
    fun drawsRubyAndEmphasisDecorations() {
        val text = "提椠很好"
        val engine = appleParagraphEngine()
        val style = TextStyle(fontSize = 28f)
        val constraints = LayoutConstraints(maxWidth = 400f)

        val plain = engine.layout(LayoutInput(content = TiqianTextContent(text), textStyle = style, constraints = constraints))
        val rich = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                textStyle = style,
                constraints = constraints,
                rubySpans = listOf(RubySpan(TextRange(0, 2), "tíqiàn", kind = RubyKind.Pinyin)),
                decorations = listOf(DecorationSpan(TextRange(3, 4), DecorationKind.Emphasis)),
            ),
        )

        // The engine must have produced the annotation geometry the renderer draws from.
        assertTrue(rich.debug.rubyDecisions.isNotEmpty(), "expected 拼音 ruby geometry")
        assertTrue(rich.debug.rubyDecisions.all { it.glyphs.isNotEmpty() }, "ruby geometry should carry shape-once glyphs")
        assertTrue(rich.debug.decorationDecisions.any { it.applied && it.dotDiameter > 0f }, "expected an applied 着重号 dot")

        // Drawing the ruby glyphs + the dot must add ink over the plain baseline render.
        val plainInk = renderInkBands(plain, width = 240, bands = 1)[0]
        val richInk = renderInkBands(rich, width = 240, bands = 1)[0]
        assertTrue(
            richInk > plainInk + 20,
            "decorations added no ink: plain=$plainInk rich=$richInk " +
                "(ruby=${rich.debug.rubyDecisions.size}, dots=${rich.debug.decorationDecisions.count { it.applied }})",
        )
    }

    @Test
    fun bopomofoRendersInk() {
        val engine = appleParagraphEngine()
        val style = TextStyle(fontSize = 30f, locale = "zh-TW")
        val constraints = LayoutConstraints(maxWidth = 400f)

        val plain = engine.layout(LayoutInput(content = TiqianTextContent("好"), textStyle = style, constraints = constraints))
        val zhuyin = engine.layout(
            LayoutInput(
                content = TiqianTextContent("好"),
                textStyle = style,
                constraints = constraints,
                rubySpans = listOf(RubySpan(TextRange(0, 1), "ㄏㄠˇ", kind = RubyKind.Bopomofo)),
            ),
        )
        assertTrue(zhuyin.debug.bopomofoDecisions.isNotEmpty(), "expected 注音 geometry")
        val tone = zhuyin.debug.bopomofoDecisions.single().placements.single {
            it.role == BopomofoGlyphRole.Tone
        }
        val symbol = zhuyin.debug.bopomofoDecisions.single().placements.first {
            it.role == BopomofoGlyphRole.Symbol
        }
        assertEquals(
            symbol.fontSize,
            tone.fontSize,
            0.001f,
            "ordinary tone marks must share the stable annotation size on Core Text",
        )

        // Re-shaping the vertical ㄅㄆㄇ + tone must add ink beside the base character.
        val plainInk = renderInkBands(plain, width = 240, bands = 1)[0]
        val zhuyinInk = renderInkBands(zhuyin, width = 240, bands = 1)[0]
        assertTrue(zhuyinInk > plainInk + 10, "注音 should add ink: plain=$plainInk zhuyin=$zhuyinInk")
    }

    @Test
    fun bopomofoToneInkIsCenteredInItsSlot() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("好"),
                textStyle = TextStyle(fontSize = 30f, locale = "zh-TW"),
                constraints = LayoutConstraints(maxWidth = 400f),
                rubySpans = listOf(RubySpan(TextRange(0, 1), "ㄏㄠˇ", kind = RubyKind.Bopomofo)),
            ),
        )
        val decision = result.debug.bopomofoDecisions.single()
        val tone = decision.placements.single { it.role == BopomofoGlyphRole.Tone }
        val toneOnly = result.copy(
            clusters = result.clusters.map { it.copy(displayText = "") },
            glyphRuns = emptyList(),
            debug = result.debug.copy(
                rubyDecisions = emptyList(),
                bopomofoDecisions = listOf(decision.copy(placements = mutableListOf(tone))),
                decorationDecisions = emptyList(),
                decorationSegments = emptyList(),
            ),
        )

        val inkColumns = renderInkColumns(toneOnly, width = 96)
        val inkCenter = (inkColumns.first + inkColumns.last + 1) / 2f
        val slotCenter = tone.left + tone.width / 2f
        assertEquals(
            slotCenter,
            inkCenter,
            1f,
            "Core Text tone ink must centre on its 5×5 body box: slot=$slotCenter ink=$inkColumns " +
                "drawX=${tone.drawX} baseline=${tone.baselineY} size=${tone.fontSize}",
        )
    }

    @Test
    fun bopomofoVerticalSymbolsStayInsideTheirNinePartBoxes() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中"),
                textStyle = TextStyle(fontSize = 30f, locale = "zh-TW"),
                constraints = LayoutConstraints(maxWidth = 400f),
                rubySpans = listOf(RubySpan(TextRange(0, 1), "ㄓㄨㄥ", kind = RubyKind.Bopomofo)),
            ),
        )

        val symbols = result.debug.bopomofoDecisions.single().placements.filter {
            it.role == BopomofoGlyphRole.Symbol
        }
        assertEquals(3, symbols.size)
        for (symbol in symbols) {
            // Core Text's vertical run pen is the 字身框 top centre (CoreTextLayoutRenderer),
            // not the horizontal-baseline origin the engine records for Skia/Android replay.
            val originX = symbol.left + symbol.width / 2f
            val originTop = symbol.top
            val ink = symbol.glyphs.mapNotNull { glyph ->
                glyph.bounds?.let { bounds ->
                    floatArrayOf(
                        originX + glyph.x + bounds.left,
                        originTop + glyph.y + bounds.top,
                        originX + glyph.x + bounds.right,
                        originTop + glyph.y + bounds.bottom,
                    )
                }
            }
            assertTrue(ink.isNotEmpty())
            assertTrue(ink.minOf { it[0] } >= symbol.left - 0.1f, "${symbol.text} shifted left: $ink")
            assertTrue(ink.maxOf { it[2] } <= symbol.left + symbol.width + 0.1f, "${symbol.text} shifted right: $ink")
            assertTrue(ink.minOf { it[1] } >= symbol.top - 0.1f, "${symbol.text} shifted up: $ink")
            assertTrue(ink.maxOf { it[3] } <= symbol.top + symbol.height + 0.1f, "${symbol.text} shifted down: $ink")
        }
    }

    @Test
    fun bopomofoRendererReplaysRecordedInkForEveryPlacement() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("好"),
                textStyle = TextStyle(fontSize = 30f, locale = "zh-TW"),
                constraints = LayoutConstraints(maxWidth = 400f),
                rubySpans = listOf(RubySpan(TextRange(0, 1), "ㄏㄠˇ", kind = RubyKind.Bopomofo)),
            ),
        )
        val decision = result.debug.bopomofoDecisions.single()
        for (placement in decision.placements) {
            val recordedBounds = placement.glyphs.mapNotNull { glyph ->
                glyph.bounds?.let { bounds ->
                    (glyph.x + bounds.left) to (glyph.x + bounds.right)
                }
            }
            assertTrue(recordedBounds.isNotEmpty(), "${placement.text} must carry recorded ink")
            // Symbols draw from the box top centre; ink-positioned marks replay the recorded origin.
            val originX = if (placement.role == BopomofoGlyphRole.Symbol) {
                placement.left + placement.width / 2f
            } else {
                placement.drawX
            }
            val recordedCenter = originX +
                (recordedBounds.minOf { it.first } + recordedBounds.maxOf { it.second }) / 2f
            val isolated = result.copy(
                clusters = result.clusters.map { it.copy(displayText = "") },
                glyphRuns = emptyList(),
                debug = result.debug.copy(
                    rubyDecisions = emptyList(),
                    bopomofoDecisions = listOf(decision.copy(placements = mutableListOf(placement))),
                    decorationDecisions = emptyList(),
                    decorationSegments = emptyList(),
                ),
            )
            val inkColumns = renderInkColumns(isolated, width = 96)
            val renderedCenter = (inkColumns.first + inkColumns.last + 1) / 2f
            assertEquals(
                recordedCenter,
                renderedCenter,
                1f,
                "${placement.role} ${placement.text} renderer drift: recorded=$recordedCenter rendered=$inkColumns",
            )
        }
    }

    @Test
    fun bopomofoNeutralToneRendersInk() {
        // 轻声: a leading ˙ (U+02D9) → BopomofoTone.Neutral → a full-width vert-alt dot placed
        // at the top of the symbol column (its own render branch, distinct from Symbol/Tone).
        val engine = appleParagraphEngine()
        val style = TextStyle(fontSize = 30f, locale = "zh-TW")
        val constraints = LayoutConstraints(maxWidth = 400f)

        val plain = engine.layout(LayoutInput(content = TiqianTextContent("吗"), textStyle = style, constraints = constraints))
        val zhuyin = engine.layout(
            LayoutInput(
                content = TiqianTextContent("吗"),
                textStyle = style,
                constraints = constraints,
                rubySpans = listOf(RubySpan(TextRange(0, 1), "˙ㄇㄚ", kind = RubyKind.Bopomofo)),
            ),
        )
        val neutralPlacements = zhuyin.debug.bopomofoDecisions
            .flatMap { it.placements }
            .filter { it.role == BopomofoGlyphRole.Neutral }
        assertTrue(neutralPlacements.isNotEmpty(), "expected a 轻声 (Neutral) placement for ˙ㄇㄚ")

        val plainInk = renderInkBands(plain, width = 240, bands = 1)[0]
        val zhuyinInk = renderInkBands(zhuyin, width = 240, bands = 1)[0]
        assertTrue(zhuyinInk > plainInk + 10, "轻声 注音 should add ink: plain=$plainInk zhuyin=$zhuyinInk")
    }

    @Test
    fun rendersSameResultTwiceConsistently() {
        // Regression guard for the borrowed-font cache (CoreTextSupport): the renderer no longer
        // CFReleases cached fonts, so a second render must reuse them intact. A double-free /
        // use-after-free would crash here or blank the second pass.
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("重复渲染同一结果两次"),
                textStyle = TextStyle(fontSize = 22f),
                constraints = LayoutConstraints(maxWidth = 200f),
            ),
        )
        val first = renderInkBands(result, width = 220, bands = 1)[0]
        val second = renderInkBands(result, width = 220, bands = 1)[0]
        assertTrue(first > 30, "expected ink on the first render, got $first")
        assertEquals(first, second, "second render (cached fonts reused) must match the first")
    }

    @Test
    fun colorSpanPaintsRequestedColor() {
        // Rich-text 颜色 (ADR 0030): a ColorSpan must paint its cluster in that ARGB, while the base
        // text stays the context's (black) fill. Red ink appears only when the span is applied.
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("红", sourceBoundaries = listOf(0, 1)),
                textStyle = TextStyle(fontSize = 44f),
                constraints = LayoutConstraints(maxWidth = 200f),
            ),
        )
        val red = 0xFFB00020.toInt()
        val colored = renderRedInk(result, listOf(ColorSpan(0, 1, red)))
        val plain = renderRedInk(result, emptyList())
        assertTrue(colored > 20, "colored span should paint red ink, got $colored red px")
        assertEquals(0, plain, "black base text must have no red ink, got $plain")
    }

    @Test
    fun nativeLinkRoleDrawsItsFrontendUnderline() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("链接", sourceBoundaries = listOf(0, 2)),
                textStyle = TextStyle(fontSize = 44f),
                constraints = LayoutConstraints(maxWidth = 200f),
            ),
        )
        val link = RichTextSpan(TextRange(0, 2), Link("https://example.com"))

        val plainInk = renderInkBands(result, width = 120, bands = 1)[0]
        val linkedInk = renderInkBands(result, width = 120, bands = 1, richTextSpans = listOf(link))[0]

        assertTrue(linkedInk > plainInk, "link underline should add ink: plain=$plainInk linked=$linkedInk")
    }

    @Test
    fun decorationInheritsItsSourceColor() {
        val style = TextStyle(fontSize = 44f)
        val constraints = LayoutConstraints(maxWidth = 200f)
        val plain = appleParagraphEngine().layout(
            LayoutInput(content = TiqianTextContent("重"), textStyle = style, constraints = constraints),
        )
        val decorated = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("重"),
                textStyle = style,
                constraints = constraints,
                decorations = listOf(DecorationSpan(TextRange(0, 1), DecorationKind.Emphasis)),
            ),
        )
        val red = listOf(ColorSpan(0, 1, 0xFFB00020.toInt()))

        val plainRed = renderRedInk(plain, red)
        val decoratedRed = renderRedInk(decorated, red)
        assertTrue(
            decoratedRed > plainRed,
            "the emphasis dot must inherit red from its source span: plain=$plainRed decorated=$decoratedRed",
        )
    }

    @Test
    fun interlinearLineUsesRecordedGlyphInkForSkipIntervals() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("g"),
                textStyle = TextStyle(fontSize = 64f),
                constraints = LayoutConstraints(maxWidth = 200f),
                decorations = listOf(DecorationSpan(TextRange(0, 1), DecorationKind.BookTitle)),
            ),
        )
        val segment = result.debug.decorationSegments.single()
        val skips = result.coreTextInkSkipIntervals(
            lineIndex = segment.lineIndex,
            bandTop = segment.top - 4f,
            bandBottom = segment.top + 4f,
        )

        assertTrue(skips.isNotEmpty(), "Latin descender ink crossing the wave band must create a skip interval")
        assertTrue(skips.all { it.right > it.left }, "skip intervals must carry positive recorded ink width: $skips")
    }

    @Test
    fun italicShearsGlyphInk() {
        // Synthetic-oblique italic (ADR 0030 B 档) must actually slant CJK glyphs — PingFang has no
        // italic face, so it's a shear carried by TextStyle.italic. The shear pushes the top of the
        // ink rightward, so the italic glyph's ink reaches a further-right column than upright.
        val engine = appleParagraphEngine()
        val style = TextStyle(fontSize = 64f)
        val constraints = LayoutConstraints(maxWidth = 400f)
        val plain = engine.layout(LayoutInput(content = TiqianTextContent("永"), textStyle = style, constraints = constraints))
        val italic = engine.layout(
            LayoutInput(
                content = TiqianTextContent(
                    "永",
                    spans = listOf(TextSpan(TextRange(0, 1), TextStyle(fontSize = 64f, italic = true))),
                    sourceBoundaries = listOf(0, 1),
                ),
                textStyle = style,
                constraints = constraints,
            ),
        )
        val plainRight = rightmostInkColumn(plain)
        val italicRight = rightmostInkColumn(italic)
        assertTrue(italicRight > plainRight + 4, "italic should shear ink rightward: plain=$plainRight italic=$italicRight")
    }

    @Test
    fun drawsLineEndHyphenForWesternHyphenation() {
        // Narrow measure forces the engine to hyphenate the word and reserve a hanging hyphen
        // (LineBox.hyphenAdvance, ADR 0029). The renderer must actually PAINT it — a bitmap regression,
        // not just a line-count check (the reviewer's ask). Isolate the hyphen's ink by re-rendering
        // the same layout with hyphenAdvance zeroed (which suppresses the hyphen) and comparing.
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("hyphenation"),
                textStyle = TextStyle(fontSize = 24f),
                constraints = LayoutConstraints(maxWidth = 80f),
            ),
        )
        assertTrue(
            result.lines.any { it.hyphenAdvance > 0f },
            "expected a hyphenated line, got hyphenAdvances=${result.lines.map { it.hyphenAdvance }}",
        )

        val withHyphen = renderInkBands(result, width = 128, bands = 1)[0]
        val noHyphen = renderInkBands(result.copy(lines = result.lines.map { it.copy(hyphenAdvance = 0f) }), width = 128, bands = 1)[0]
        assertTrue(withHyphen > noHyphen, "the line-end hyphen should add ink: withHyphen=$withHyphen noHyphen=$noHyphen")
    }

    @Test
    fun demoLongEnglishWordUsesAppleHyphenationAtPhoneMeasure() {
        val result = appleParagraphEngine().layout(
            LayoutInput(
                content = TiqianTextContent("pneumonoultramicroscopicsilicovolcanoconiosis"),
                textStyle = TextStyle(fontSize = 18f),
                constraints = LayoutConstraints(maxWidth = 306f),
            ),
        )

        assertTrue(result.lines.size > 1, "the demo word should exceed a phone-width measure")
        assertTrue(
            result.lines.dropLast(1).any { it.hyphenAdvance > 0f },
            "Apple's default en-US hyphenator should expose a visible line-end hyphen",
        )
    }

    /** Renders [result] (replaying its own spans) and returns the rightmost column holding glyph ink. */
    private fun rightmostInkColumn(result: LayoutResult): Int {
        val width = 200
        val height = maxOf(96, result.size.height.toInt() + 16)
        val bytesPerRow = width * 4
        val colorSpace = CGColorSpaceCreateDeviceRGB()
        val ctx = CGBitmapContextCreate(
            null, width.convert(), height.convert(), 8u, bytesPerRow.convert(), colorSpace,
            CGImageAlphaInfo.kCGImageAlphaPremultipliedLast.value,
        ) ?: error("could not create bitmap context")
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0)
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width.toDouble(), height.toDouble()))
        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0)
        CoreTextLayoutRenderer().draw(result, ctx, height.toDouble(), spans = result.input.content.spans)

        val data = CGBitmapContextGetData(ctx)?.reinterpret<UByteVar>() ?: error("no bitmap data")
        var maxCol = -1
        for (row in 0 until height) {
            for (col in 0 until width) {
                if (data[(row * bytesPerRow) + (col * 4)] < 128u && col > maxCol) maxCol = col
            }
        }
        CGContextRelease(ctx)
        CGColorSpaceRelease(colorSpace)
        return maxCol
    }

    /** Renders [result] and returns the inclusive horizontal pixel range containing ink. */
    private fun renderInkColumns(result: LayoutResult, width: Int): IntRange {
        val height = maxOf(96, result.size.height.toInt() + 24)
        val bytesPerRow = width * 4
        val colorSpace = CGColorSpaceCreateDeviceRGB()
        val ctx = CGBitmapContextCreate(
            null, width.convert(), height.convert(), 8u, bytesPerRow.convert(), colorSpace,
            CGImageAlphaInfo.kCGImageAlphaPremultipliedLast.value,
        ) ?: error("could not create bitmap context")
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0)
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width.toDouble(), height.toDouble()))
        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0)
        CoreTextLayoutRenderer().draw(result, ctx, height.toDouble())

        val data = CGBitmapContextGetData(ctx)?.reinterpret<UByteVar>() ?: error("no bitmap data")
        var minCol = width
        var maxCol = -1
        for (row in 0 until height) {
            for (col in 0 until width) {
                if (data[(row * bytesPerRow) + (col * 4)] < 128u) {
                    minCol = minOf(minCol, col)
                    maxCol = maxOf(maxCol, col)
                }
            }
        }
        CGContextRelease(ctx)
        CGColorSpaceRelease(colorSpace)
        check(maxCol >= minCol) { "rendered no ink" }
        return minCol..maxCol
    }

    /** Renders [result] (black base fill) with [colorSpans] and counts reddish pixels (R high, G/B low). */
    private fun renderRedInk(result: LayoutResult, colorSpans: List<ColorSpan>): Int {
        val width = 96
        val height = maxOf(56, result.size.height.toInt() + 12)
        val bytesPerRow = width * 4
        val colorSpace = CGColorSpaceCreateDeviceRGB()
        val ctx = CGBitmapContextCreate(
            null, width.convert(), height.convert(), 8u, bytesPerRow.convert(), colorSpace,
            CGImageAlphaInfo.kCGImageAlphaPremultipliedLast.value,
        ) ?: error("could not create bitmap context")
        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0)
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width.toDouble(), height.toDouble()))
        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0) // base fill = black; colored spans override
        CoreTextLayoutRenderer().draw(result, ctx, height.toDouble(), colorSpans = colorSpans)

        val data = CGBitmapContextGetData(ctx)?.reinterpret<UByteVar>() ?: error("no bitmap data")
        var reds = 0
        for (row in 0 until height) {
            for (col in 0 until width) {
                val o = (row * bytesPerRow) + (col * 4)
                val r = data[o].toInt(); val g = data[o + 1].toInt(); val b = data[o + 2].toInt()
                if (r > 120 && g < 80 && b < 80) reds++
            }
        }
        CGContextRelease(ctx)
        CGColorSpaceRelease(colorSpace)
        return reds
    }

    /** Renders [result] into an offscreen black-on-white bitmap and returns ink pixel counts per horizontal band (top→bottom in image space). */
    private fun renderInkBands(
        result: LayoutResult,
        width: Int,
        bands: Int,
        richTextSpans: List<RichTextSpan> = emptyList(),
    ): IntArray {
        val height = maxOf(48, result.size.height.toInt() + 12)
        val bytesPerRow = width * 4
        val colorSpace = CGColorSpaceCreateDeviceRGB()
        val ctx = CGBitmapContextCreate(
            data = null,
            width = width.convert(),
            height = height.convert(),
            bitsPerComponent = 8u,
            bytesPerRow = bytesPerRow.convert(),
            space = colorSpace,
            bitmapInfo = CGImageAlphaInfo.kCGImageAlphaPremultipliedLast.value,
        ) ?: error("could not create bitmap context")

        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0)
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width.toDouble(), height.toDouble()))
        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0) // renderer inherits this fill color
        CoreTextLayoutRenderer().draw(result, ctx, height.toDouble(), richTextSpans = richTextSpans)

        val data = CGBitmapContextGetData(ctx)?.reinterpret<UByteVar>() ?: error("no bitmap data")
        val counts = IntArray(bands)
        for (row in 0 until height) {
            val band = (row * bands) / height
            var col = 0
            while (col < width) {
                if (data[(row * bytesPerRow) + (col * 4)] < 200u) counts[band]++
                col++
            }
        }
        CGContextRelease(ctx)
        CGColorSpaceRelease(colorSpace)
        return counts
    }
}
