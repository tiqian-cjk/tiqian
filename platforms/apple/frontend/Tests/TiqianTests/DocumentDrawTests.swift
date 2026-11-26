import CoreGraphics
import XCTest
@testable import Tiqian

/// Coverage for `Document`'s cached display lists and visible-rect culling: the recorded paint
/// bounds must contain every inked pixel, a cached replay must reproduce the first draw exactly, and
/// blocks outside the visible rect must not paint.
final class DocumentDrawTests: XCTestCase {
    /// A document whose two paragraphs exercise every primitive kind: glyph runs (base text, 拼音,
    /// 注音, italic), filled ellipses (着重号), filled rects (专名号, 示亡号, link underline) and
    /// filled paths (书名号).
    private func richDocument() -> Document {
        Typesetter(fontSize: 24).documentBuilder()
            .flushParagraph(
                ParagraphContent()
                    .pinyin("提椠", reading: "tíqiàn")
                    .piece("着重", decorations: [.emphasis])
                    .piece("专名", decorations: [.properNoun])
                    .piece("书名", decorations: [.bookTitle])
                    .piece("示亡", decorations: [.mourning])
                    .piece("斜体", italic: true)
                    .piece("link", linkTarget: "https://example.com"),
            )
            .flushParagraph(ParagraphContent().text("请").bopomofo("坐", reading: "ㄗㄨㄛˋ"))
            .layout(width: 400)
    }

    private func render(_ document: Document, visibleRect: CGRect? = nil) -> RenderingProbe.Bitmap {
        let bitmap = RenderingProbe.Bitmap(width: 440, height: Int(document.height) + 40)
        // The document top sits 20 px below the bitmap top and 20 px right of its left edge.
        bitmap.context.translateBy(x: 20, y: 0)
        document.draw(in: bitmap.context, canvasHeight: Double(bitmap.height) - 20, visibleRect: visibleRect)
        return bitmap
    }

    /// Inked pixels (red channel below 250) as a rect in document coordinates.
    private func inkBounds(_ bitmap: RenderingProbe.Bitmap) -> CGRect {
        var ink = CGRect.null
        for row in 0..<bitmap.height {
            for column in 0..<bitmap.width where bitmap.pixel(row: row, column: column).r < 250 {
                ink = ink.union(CGRect(x: column - 20, y: row - 20, width: 1, height: 1))
            }
        }
        return ink
    }

    func testPaintBoundsContainEveryInkedPixel() {
        let document = richDocument()
        let lists = document.resolvedDisplayLists()
        var painted = CGRect.null
        for (block, list) in zip(document.blocks, lists) {
            painted = painted.union(list.paintBounds.offsetBy(dx: block.x, dy: block.yTop))
        }
        let ink = inkBounds(render(document))
        XCTAssertFalse(ink.isNull)
        // One pixel of antialiasing may fall just outside the analytic bounds.
        XCTAssertTrue(painted.insetBy(dx: -1, dy: -1).contains(ink), "painted=\(painted) ink=\(ink)")
    }

    func testCachedReplayReproducesTheFirstDraw() {
        let document = richDocument()
        let first = render(document)
        let second = render(document)
        let bytes = first.width * first.height * 4
        let a = first.context.data!.assumingMemoryBound(to: UInt8.self)
        let b = second.context.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertTrue((0..<bytes).allSatisfy { a[$0] == b[$0] })
    }

    func testBlocksOutsideTheVisibleRectDoNotPaint() throws {
        let document = richDocument()
        XCTAssertEqual(document.blocks.count, 2)
        let second = document.blocks[1]
        let secondPaint = document.resolvedDisplayLists()[1].paintBounds.offsetBy(dx: second.x, dy: second.yTop)
        let firstPaint = document.resolvedDisplayLists()[0].paintBounds.offsetBy(dx: document.blocks[0].x, dy: document.blocks[0].yTop)
        // A visible rect covering only the second block's lower half, below the first block's paint.
        let visible = CGRect(x: 0, y: max(secondPaint.midY, firstPaint.maxY + 1), width: 400, height: secondPaint.maxY)
        XCTAssertFalse(firstPaint.intersects(visible))

        let ink = inkBounds(render(document, visibleRect: visible))
        XCTAssertFalse(ink.isNull, "the second block still paints")
        XCTAssertGreaterThanOrEqual(ink.minY, secondPaint.minY - 1, "no ink from the first block")
        XCTAssertTrue(inkBounds(render(document, visibleRect: CGRect(x: 0, y: -500, width: 400, height: 10))).isNull)
    }
}
