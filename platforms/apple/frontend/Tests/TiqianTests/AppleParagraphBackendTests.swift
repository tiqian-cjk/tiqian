import TiqianCoreText
import TiqianEngine
import XCTest
@testable import Tiqian

/// End-to-end runs of the Apple backend (Core Text metrics, Core Text shaping, line breaking,
/// LayoutResult) with real system fonts, plus CLREQ conformance driven by those measurements. The
/// CLREQ rules themselves are covered by the engine's own suites; these tests prove that real Core
/// Text measurements produce conformant layout.
final class AppleParagraphBackendTests: XCTestCase {
    private typealias Probe = RenderingProbe

    func testLaysOutCJKParagraphEndToEndWithCoreText() throws {
        let result = try Probe.layout("你好，世界！这是提椠中文排版引擎的一段测试文字。", maxWidth: 200)
        XCTAssertFalse(result.clusters.isEmpty)
        XCTAssertFalse(result.glyphRuns.isEmpty)
        XCTAssertFalse(result.lines.isEmpty)
        XCTAssertGreaterThan(result.size.width, 0)
        XCTAssertGreaterThan(result.size.height, 0)
        XCTAssertTrue(result.presentation.shapingDecisions.contains { String(engineText: $0.source) == "CoreText" })
    }

    func testWrapsToMultipleLinesUnderNarrowWidth() throws {
        let result = try Probe.layout("这是一段足够长的中文文字用来测试在窄宽度下的自动换行行为是否正确无误。", maxWidth: 96)
        XCTAssertGreaterThanOrEqual(result.lines.count, 2)
    }

    /// 行首禁则: pause, stop and closing marks never start a line.
    func testKinsokuNoLineStartsWithForbiddenPunctuation() throws {
        let forbidden = Set("。，、！？；：）」』】》".utf16)
        let text = "春眠不觉晓，处处闻啼鸟，夜来风雨声，花落知多少，问君能有几多愁，恰似一江春水向东流。"
        let result = try Probe.layout(text, maxWidth: 100)
        XCTAssertGreaterThanOrEqual(result.lines.count, 3)
        for (index, line) in result.lines.enumerated() {
            let clusterIndex = Int(line.clusterRange.first)
            guard clusterIndex < result.clusters.count else { continue }
            let cluster = result.clusters[clusterIndex]
            guard let first = cluster.displayText.first ?? cluster.text.first else { continue }
            XCTAssertFalse(forbidden.contains(first), "line \(index) starts with forbidden punctuation")
        }
        XCTAssertTrue(result.debug.kinsokuDecision != nil || !result.debug.contextualKinsokuDecisions.isEmpty)
    }

    func testJustificationFillsNonLastLines() throws {
        let text = "这是一段用于测试两端对齐的足够长的中文正文它应当在窄宽度下被引擎按 CLREQ 两端对齐处理。"
        let width: Float = 120
        let result = try Probe.layout(text, maxWidth: width)
        XCTAssertGreaterThanOrEqual(result.lines.count, 2)
        XCTAssertFalse(result.debug.justificationDecisions.isEmpty)
        for (index, line) in result.lines.dropLast().enumerated() {
            XCTAssertGreaterThanOrEqual(line.visualWidth, width * 0.8, "non-last line \(index)")
        }
    }

    func testAutospaceRunsAtCJKLatinBoundaries() throws {
        let result = try Probe.layout("中文Abc漢字123你好World", maxWidth: 400)
        XCTAssertFalse(result.presentation.autoSpaceDecisions.isEmpty)
    }

    func testPunctuationCompressionCarriesCompressibleGlue() throws {
        let result = try Probe.layout("他说：「你好。」然后离开了，真的。", maxWidth: 400)
        XCTAssertFalse(result.presentation.punctuationDecisions.isEmpty)
        // CLREQ 标点挤压 works through the mark's compressible glue; the glyph advance stays 1 em.
        XCTAssertTrue(result.presentation.punctuationDecisions.contains { $0.leadingGlueNatural > 0 || $0.trailingGlueNatural > 0 })
    }
}
