import TiqianCoreText
import TiqianEngine
import XCTest
@testable import Tiqian

/// Coverage for the facade that TiqianUI consumes: authoring, lowering, document layout, selection
/// and clipboard queries, run end to end through the engine and Core Text.
final class TypesetterTests: XCTestCase {
    func testLowersCombinedNativeAttributesWithoutDuplicatingSource() throws {
        let lowered = try ParagraphContent().piece(
            "重",
            bold: true,
            italic: true,
            sizeEm: 1.25,
            family: "PingFang SC",
            argb: 0xFFB0_0020,
            rubyReading: "zhòng",
            decorations: [.emphasis, .bookTitle],
        ).lowered(baseSize: 20)

        let whole = try TextRange(0, 1)
        XCTAssertEqual(String(engineText: lowered.text), "重")
        XCTAssertEqual(lowered.spans.map(\.range), [whole])
        XCTAssertEqual(lowered.spans.map(\.style.fontSize), [25])
        XCTAssertEqual(lowered.colorSpans.map { [$0.start, $0.end] }, [[0, 1]])
        XCTAssertEqual(lowered.rubySpans.map(\.baseRange), [whole])
        XCTAssertEqual(lowered.rubySpans.map(\.kind), [.pinyin])
        XCTAssertEqual(lowered.decorations.map(\.kind), [.emphasis, .bookTitle])
        XCTAssertEqual(lowered.sourceBoundaries, [0, 1])
    }

    func testKeepsSimplifiedBaseLocaleWhileBopomofoUsesTraditionalLocale() throws {
        let lowered = try ParagraphContent().text("请").bopomofo("坐", reading: "ㄗㄨㄛˋ").lowered(baseSize: 20)
        XCTAssertEqual(lowered.locale, "zh-Hans")
        XCTAssertEqual(lowered.rubySpans.first?.locale.map { String(engineText: $0) }, "zh-TW")
        XCTAssertEqual(lowered.rubySpans.first?.kind, .bopomofo)
    }

    func testLaysOutPlainTextToPositiveGeometry() {
        let paragraph = Typesetter(fontSize: 18).layout("提椠中文排版示例，验证 Swift 门面能真正跑通真实布局。", width: 240)
        XCTAssertGreaterThan(paragraph.height, 0)
        XCTAssertGreaterThan(paragraph.width, 0)
        XCTAssertGreaterThanOrEqual(paragraph.lineCount, 2)
    }

    func testBuildsAndLaysOutARichDocument() {
        let document = Typesetter(fontSize: 18).documentBuilder()
            .flushParagraph(ParagraphContent().piece("标题", bold: true, sizeEm: 1.6))
            .paragraph(
                ParagraphContent()
                    .text("正文一段，含")
                    .pinyin("提椠", reading: "tíqiàn")
                    .text("、")
                    .piece("着重", decorations: [.emphasis])
                    .text("与")
                    .piece("红字", argb: 0xFFB0_0020)
                    .text("。"),
            )
            .section()
            .numberedList([
                ParagraphContent().text("第一条，续行也应与正文同列对齐，所以要写得足够长以触发换行换行换行。"),
                ParagraphContent().text("第二条。"),
            ])
            .bulletList([ParagraphContent().text("要点甲"), ParagraphContent().text("要点乙")])
            .layout(width: 320)

        XCTAssertGreaterThan(document.height, 0)
        // title + paragraph + 2 × (marker + body) + 2 × (marker + body) = 10 blocks.
        XCTAssertEqual(document.blockCount, 10)
    }

    func testAlignsListMarkerAndBodyOnTheirFirstBaselines() throws {
        let document = Typesetter(fontSize: 18).documentBuilder()
            .bulletList([ParagraphContent().text("列表正文")])
            .decimalList([ParagraphContent().text("另一项正文")])
            .layout(width: 240)

        for row in stride(from: 0, to: document.blocks.count, by: 2) {
            let marker = document.blocks[row]
            let body = document.blocks[row + 1]
            let markerBaseline = marker.yTop + Double(try XCTUnwrap(marker.result.lines.first).baseline)
            let bodyBaseline = body.yTop + Double(try XCTUnwrap(body.result.lines.first).baseline)
            XCTAssertEqual(bodyBaseline, markerBaseline, accuracy: 0.01)
        }
    }

    func testListMarkersStayFlushAndDoNotAddTheBodyFirstLineIndentToTheGutter() throws {
        let fontSize: Float = 18
        let document = Typesetter(fontSize: fontSize).documentBuilder()
            .bulletList([ParagraphContent().text("项目符号正文")])
            .decimalList([ParagraphContent().text("十进制正文")])
            .numberedList([ParagraphContent().text("汉字编号正文")])
            .layout(width: 240)

        let blocks = document.blocks
        XCTAssertEqual(blocks.count, 6)
        for row in stride(from: 0, to: blocks.count, by: 2) {
            XCTAssertEqual(try XCTUnwrap(blocks[row].result.lines.first).indent, 0, accuracy: 0.01)
        }
        XCTAssertEqual(blocks[0].x + Double(try XCTUnwrap(blocks[0].result.lines.first).indent), 0, accuracy: 0.01)
        XCTAssertEqual(blocks[1].x, Double(fontSize), accuracy: 0.01, "the bullet gutter is one 字")
        XCTAssertLessThanOrEqual(blocks[3].x, Double(fontSize) * 2, "the decimal gutter has no body indent")
        XCTAssertLessThanOrEqual(blocks[5].x, Double(fontSize) * 2, "the CJK marker gutter has no body indent")
    }

    func testExtremelyNarrowListDoesNotPassANegativeBodyWidthToTheCore() {
        let document = Typesetter(fontSize: 18).documentBuilder()
            .numberedList([ParagraphContent().text("正文")])
            .layout(width: 18)
        XCTAssertGreaterThan(document.height, 0)
        XCTAssertEqual(document.blockCount, 2)
    }

    func testClipboardTextMatchesWebRubyAndListSemantics() {
        let document = Typesetter(fontSize: 18).documentBuilder()
            .numberedList([
                ParagraphContent().pinyin("提椠", reading: "tíqiàn").text("与").bopomofo("您", reading: "ㄋㄧㄣˊ"),
                ParagraphContent().text("正文"),
            ])
            .layout(width: 240)

        XCTAssertEqual(document.text, "一、提椠与您\n二、正文")
        XCTAssertEqual(
            document.clipboardTextInRange(start: 0, end: document.text.utf16.count),
            "一、提椠（tíqiàn）与您（ㄋㄧㄣˊ）\n二、正文",
        )
        XCTAssertEqual(document.clipboardTextInRange(start: 2, end: 3), "提", "a partial ruby base emits no detached reading")
        XCTAssertEqual(document.clipboardTextInRange(start: 2, end: 4), "提椠（tíqiàn）")
    }

    func testNativeLinkUsesExactSourceGeometryWithoutChangingText() throws {
        let target = "https://www.w3.org/TR/clreq/"
        let document = Typesetter(fontSize: 20).documentBuilder()
            .flushParagraph(
                ParagraphContent()
                    .text("读「")
                    .piece("CLREQ", argb: 0xFF00_7AFF, linkTarget: target)
                    .text("」。"),
            )
            .layout(width: 240)

        XCTAssertEqual(document.text, "读「CLREQ」。")
        XCTAssertEqual(document.clipboardTextInRange(start: 0, end: document.text.utf16.count), document.text)
        let boxes = document.linkBoxes()
        XCTAssertEqual(boxes.count, 1)
        let box = try XCTUnwrap(boxes.first)
        XCTAssertEqual(box.start, 2)
        XCTAssertEqual(box.end, 7)
        XCTAssertEqual(document.linkAt(x: (box.left + box.right) / 2, y: (box.top + box.bottom) / 2), target)
        XCTAssertNil(document.linkAt(x: document.width + 1, y: document.height + 1))
    }

    func testExposesSourceFaithfulSelectionQueriesForNativeViews() throws {
        let document = Typesetter(fontSize: 20).documentBuilder()
            .flushParagraph(ParagraphContent().text("提椠中文"))
            .flushParagraph(ParagraphContent().text("second line"))
            .layout(width: 220)

        XCTAssertEqual(document.text, "提椠中文\nsecond line")
        let caret = document.caretBox(offset: 0)
        let hit = document.selectionOffset(x: caret.left + 5, y: (caret.top + caret.bottom) / 2)
        XCTAssertTrue((0...1).contains(hit), "a first-glyph hit resolves to one of its insertion edges")

        let word = try XCTUnwrap(document.selectionWord(x: caret.left + 5, y: caret.top + 5))
        XCTAssertEqual(word.start, 0)
        XCTAssertEqual(word.end, 1, "Han selection expands to exactly one source unit")

        let boxes = document.selectionBoxes(start: 0, end: document.text.utf16.count)
        XCTAssertGreaterThanOrEqual(boxes.count, 2)
        XCTAssertTrue(boxes.allSatisfy { $0.right > $0.left && $0.bottom > $0.top })
        XCTAssertEqual(document.textInRange(start: 1, end: 11), "椠中文\nsecond")
    }

    func testSelectionBoundaryNeverSplitsASurrogatePair() {
        let document = Typesetter(fontSize: 20).documentBuilder()
            .flushParagraph(ParagraphContent().text("😀a"))
            .layout(width: 220)
        XCTAssertEqual(document.selectionBoundary(offset: 1, forward: false), 0)
        XCTAssertEqual(document.selectionBoundary(offset: 1, forward: true), 2)
    }

    func testCJKNumeralFormatting() {
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(0), "零")
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(10), "十")
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(11), "十一")
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(20), "二十")
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(99), "九十九")
        XCTAssertEqual(ListMarkerFormat.cjkNumeral(100), "100")
    }
}
