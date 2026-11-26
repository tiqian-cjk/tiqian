import TiqianCoreText
import TiqianEngine
import XCTest
@testable import Tiqian

/// Runtime checks that the Core Text renderer draws glyph ink, distributes lines vertically and
/// paints the engine's decoration and annotation geometry. The band test guards against drawing
/// the pre-line-break glyph run, which collapses every line onto one baseline.
final class CoreTextLayoutRendererTests: XCTestCase {
    private typealias Probe = RenderingProbe

    func testRendersGlyphInkForCJKParagraph() throws {
        let result = try Probe.layout("中文渲染测试提椠", maxWidth: 240)
        let bands = try Probe.inkBands(result, width: 256, bands: 1)
        XCTAssertGreaterThan(bands[0], 30, "lines=\(result.lines.count)")
    }

    func testDistributesLinesAcrossVerticalBands() throws {
        let text = "这是一段足够长的中文正文，用来验证多行文本在垂直方向被正确铺开，"
            + "而不是全部塌在同一条基线上；它应当产生很多行，墨迹从顶部一直分布到底部。"
        let result = try Probe.layout(text, fontSize: 20, maxWidth: 120)
        XCTAssertGreaterThanOrEqual(result.lines.count, 5)
        let bands = try Probe.inkBands(result, width: 160, bands: 4)
        XCTAssertGreaterThanOrEqual(bands.filter { $0 > 5 }.count, 3, "per-band ink=\(bands)")
    }

    func testDrawsRubyAndEmphasisDecorations() throws {
        let plain = try Probe.layout("提椠很好", fontSize: 28, maxWidth: 400)
        let rich = try Probe.layout(
            "提椠很好",
            fontSize: 28,
            maxWidth: 400,
            decorations: [DecorationSpan(Probe.range(3, 4), .emphasis)],
            rubySpans: [RubySpan(Probe.range(0, 2), "tíqiàn".engineText, BoringArray(), .pinyin)],
        )
        XCTAssertFalse(rich.presentation.rubyDecisions.isEmpty, "expected 拼音 ruby geometry")
        XCTAssertTrue(rich.presentation.rubyDecisions.allSatisfy { !$0.glyphs.isEmpty })
        XCTAssertTrue(rich.presentation.decorationDecisions.contains { $0.applied && $0.dotDiameter > 0 })

        let plainInk = try Probe.inkBands(plain, width: 240, bands: 1)[0]
        let richInk = try Probe.inkBands(rich, width: 240, bands: 1)[0]
        XCTAssertGreaterThan(richInk, plainInk + 20, "decorations added no ink")
    }

    func testBopomofoRendersInk() throws {
        let plain = try Probe.layout("好", fontSize: 30, locale: "zh-TW", maxWidth: 400)
        let zhuyin = try Probe.layout(
            "好",
            fontSize: 30,
            locale: "zh-TW",
            maxWidth: 400,
            rubySpans: [RubySpan(Probe.range(0, 1), "ㄏㄠˇ".engineText, BoringArray(), .bopomofo)],
        )
        let placements = try XCTUnwrap(zhuyin.presentation.bopomofoDecisions.first).placements
        let tone = try XCTUnwrap(placements.first { $0.role == .tone })
        let symbol = try XCTUnwrap(placements.first { $0.role == .symbol })
        XCTAssertEqual(symbol.fontSize, tone.fontSize, accuracy: 0.001, "tone marks share the annotation size")

        let plainInk = try Probe.inkBands(plain, width: 240, bands: 1)[0]
        let zhuyinInk = try Probe.inkBands(zhuyin, width: 240, bands: 1)[0]
        XCTAssertGreaterThan(zhuyinInk, plainInk + 10)
    }

    func testBopomofoToneInkIsCenteredInItsSlot() throws {
        let result = try Probe.layout(
            "好",
            fontSize: 30,
            locale: "zh-TW",
            maxWidth: 400,
            rubySpans: [RubySpan(Probe.range(0, 1), "ㄏㄠˇ".engineText, BoringArray(), .bopomofo)],
        )
        let decision = try XCTUnwrap(result.presentation.bopomofoDecisions.first)
        let tone = try XCTUnwrap(decision.placements.first { $0.role == .tone })
        let toneOnly = Probe.annotationsOnly(result, bopomofo: [Probe.bopomofo(decision, placements: [tone])])
        let columns = try XCTUnwrap(try Probe.inkColumns(toneOnly, width: 96), "rendered no ink")
        let inkCenter = Float(columns.lowerBound + columns.upperBound + 1) / 2
        XCTAssertEqual(tone.left + tone.width / 2, inkCenter, accuracy: 1, "ink=\(columns)")
    }

    func testBopomofoVerticalSymbolsStayInsideTheirNinePartBoxes() throws {
        let result = try Probe.layout(
            "中",
            fontSize: 30,
            locale: "zh-TW",
            maxWidth: 400,
            rubySpans: [RubySpan(Probe.range(0, 1), "ㄓㄨㄥ".engineText, BoringArray(), .bopomofo)],
        )
        let symbols = try XCTUnwrap(result.presentation.bopomofoDecisions.first).placements.filter { $0.role == .symbol }
        XCTAssertEqual(symbols.count, 3)
        for symbol in symbols {
            // The Core Text vertical-run pen is the top centre of the ideographic box.
            let originX = symbol.left + symbol.width / 2
            let ink = symbol.glyphs.compactMap { glyph -> [Float]? in
                guard let bounds = glyph.bounds else { return nil }
                return [
                    originX + glyph.x + bounds.left,
                    symbol.top + glyph.y + bounds.top,
                    originX + glyph.x + bounds.right,
                    symbol.top + glyph.y + bounds.bottom,
                ]
            }
            let label = String(engineText: symbol.text)
            XCTAssertFalse(ink.isEmpty)
            XCTAssertGreaterThanOrEqual(ink.map { $0[0] }.min()!, symbol.left - 0.1, "\(label) shifted left")
            XCTAssertLessThanOrEqual(ink.map { $0[2] }.max()!, symbol.left + symbol.width + 0.1, "\(label) shifted right")
            XCTAssertGreaterThanOrEqual(ink.map { $0[1] }.min()!, symbol.top - 0.1, "\(label) shifted up")
            XCTAssertLessThanOrEqual(ink.map { $0[3] }.max()!, symbol.top + symbol.height + 0.1, "\(label) shifted down")
        }
    }

    func testBopomofoRendererReplaysRecordedInkForEveryPlacement() throws {
        let result = try Probe.layout(
            "好",
            fontSize: 30,
            locale: "zh-TW",
            maxWidth: 400,
            rubySpans: [RubySpan(Probe.range(0, 1), "ㄏㄠˇ".engineText, BoringArray(), .bopomofo)],
        )
        let decision = try XCTUnwrap(result.presentation.bopomofoDecisions.first)
        for placement in decision.placements {
            let recorded = placement.glyphs.compactMap { glyph in
                glyph.bounds.map { (glyph.x + $0.left, glyph.x + $0.right) }
            }
            XCTAssertFalse(recorded.isEmpty, "\(String(engineText: placement.text)) must carry recorded ink")
            // Symbols draw from the box top centre; ink-positioned marks replay the recorded origin.
            let originX = placement.role == .symbol ? placement.left + placement.width / 2 : placement.drawX
            let recordedCenter = originX + (recorded.map(\.0).min()! + recorded.map(\.1).max()!) / 2
            let isolated = Probe.annotationsOnly(result, bopomofo: [Probe.bopomofo(decision, placements: [placement])])
            let columns = try XCTUnwrap(try Probe.inkColumns(isolated, width: 96), "rendered no ink")
            let renderedCenter = Float(columns.lowerBound + columns.upperBound + 1) / 2
            XCTAssertEqual(recordedCenter, renderedCenter, accuracy: 1, "\(placement.role) renderer drift: \(columns)")
        }
    }

    func testBopomofoNeutralToneRendersInk() throws {
        // 轻声: a leading ˙ (U+02D9) becomes a Neutral placement with its own render branch.
        let plain = try Probe.layout("吗", fontSize: 30, locale: "zh-TW", maxWidth: 400)
        let zhuyin = try Probe.layout(
            "吗",
            fontSize: 30,
            locale: "zh-TW",
            maxWidth: 400,
            rubySpans: [RubySpan(Probe.range(0, 1), "˙ㄇㄚ".engineText, BoringArray(), .bopomofo)],
        )
        XCTAssertTrue(zhuyin.presentation.bopomofoDecisions.contains { $0.placements.contains { $0.role == .neutral } })
        let plainInk = try Probe.inkBands(plain, width: 240, bands: 1)[0]
        let zhuyinInk = try Probe.inkBands(zhuyin, width: 240, bands: 1)[0]
        XCTAssertGreaterThan(zhuyinInk, plainInk + 10)
    }

    func testRendersSameResultTwiceConsistently() throws {
        let result = try Probe.layout("重复渲染同一结果两次", fontSize: 22, maxWidth: 200)
        let first = try Probe.inkBands(result, width: 220, bands: 1)[0]
        let second = try Probe.inkBands(result, width: 220, bands: 1)[0]
        XCTAssertGreaterThan(first, 30)
        XCTAssertEqual(first, second, "the second render reuses cached fonts and lines")
    }

    func testColorSpanPaintsRequestedColor() throws {
        let result = try Probe.layout("红", fontSize: 44, maxWidth: 200, sourceBoundaries: [0, 1])
        let red = ColorSpan(0, 1, Int32(bitPattern: 0xFFB0_0020))
        XCTAssertGreaterThan(try Probe.redInk(result, colorSpans: [red]), 20)
        XCTAssertEqual(try Probe.redInk(result, colorSpans: []), 0, "black base text has no red ink")
    }

    func testNativeLinkRoleDrawsItsFrontendUnderline() throws {
        let result = try Probe.layout("链接", fontSize: 44, maxWidth: 200, sourceBoundaries: [0, 2])
        let link = RichTextSpan(try Probe.range(0, 2), Link("https://example.com".engineText))
        let plainInk = try Probe.inkBands(result, width: 120, bands: 1)[0]
        let linkedInk = try Probe.inkBands(result, width: 120, bands: 1, richTextSpans: [link])[0]
        XCTAssertGreaterThan(linkedInk, plainInk, "the link underline adds ink")
    }

    func testDecorationInheritsItsSourceColor() throws {
        let plain = try Probe.layout("重", fontSize: 44, maxWidth: 200)
        let decorated = try Probe.layout(
            "重",
            fontSize: 44,
            maxWidth: 200,
            decorations: [DecorationSpan(Probe.range(0, 1), .emphasis)],
        )
        let red = [ColorSpan(0, 1, Int32(bitPattern: 0xFFB0_0020))]
        XCTAssertGreaterThan(try Probe.redInk(decorated, colorSpans: red), try Probe.redInk(plain, colorSpans: red))
    }

    func testInterlinearLineUsesRecordedGlyphInkForSkipIntervals() throws {
        let result = try Probe.layout(
            "g",
            fontSize: 64,
            maxWidth: 200,
            decorations: [DecorationSpan(Probe.range(0, 1), .bookTitle)],
        )
        let segment = try XCTUnwrap(result.presentation.decorationSegments.first)
        let skips = result.coreTextInkSkipIntervals(
            lineIndex: segment.lineIndex,
            bandTop: segment.top - 4,
            bandBottom: segment.top + 4,
        )
        XCTAssertFalse(skips.isEmpty, "descender ink crossing the wave band creates a skip interval")
        XCTAssertTrue(skips.allSatisfy { $0.right > $0.left })
    }

    func testItalicShearsGlyphInk() throws {
        // Synthetic oblique (ADR 0030) slants PingFang SC, which has no italic face. The shear moves
        // ink right in proportion to its height above the baseline, so the upper half of the glyph
        // shifts right relative to the lower half by about shear × (ink height / 2). The rightmost
        // ink column is not a usable signal: 永's rightmost ink is the 捺 stroke near the baseline.
        let plain = try Probe.layout("永", fontSize: 64, maxWidth: 400)
        let italicStyle = TextStyle(BoringArray(), 64, "zh-Hans".engineText, 400, true)
        let italic = try Probe.layout(
            "永",
            fontSize: 64,
            maxWidth: 400,
            spans: [TextSpan(Probe.range(0, 1), italicStyle)],
            sourceBoundaries: [0, 1],
        )
        let plainSkew = try XCTUnwrap(try Probe.inkSkew(plain))
        let italicSkew = try XCTUnwrap(try Probe.inkSkew(italic))
        let expected = Double(CoreTextSupport.obliqueShear) * Double(italicSkew.inkHeight) / 2
        XCTAssertEqual(italicSkew.skew - plainSkew.skew, expected, accuracy: expected * 0.5)
    }

    func testDrawsLineEndHyphenForWesternHyphenation() throws {
        let result = try Probe.layout("hyphenation", fontSize: 24, maxWidth: 80)
        XCTAssertTrue(result.lines.contains { $0.hyphenAdvance > 0 }, "expected a hyphenated line")
        let withHyphen = try Probe.inkBands(result, width: 128, bands: 1)[0]
        let noHyphen = try Probe.inkBands(Probe.withoutHyphens(result), width: 128, bands: 1)[0]
        XCTAssertGreaterThan(withHyphen, noHyphen, "the line-end hyphen adds ink")
    }

    func testDemoLongEnglishWordHyphenatesAtPhoneMeasure() throws {
        let result = try Probe.layout("pneumonoultramicroscopicsilicovolcanoconiosis", fontSize: 18, maxWidth: 306)
        XCTAssertGreaterThan(result.lines.count, 1)
        XCTAssertTrue(result.lines.dropLast().contains { $0.hyphenAdvance > 0 })
    }
}
