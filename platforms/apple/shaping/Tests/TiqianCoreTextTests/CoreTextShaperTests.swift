import TiqianEngine
import XCTest
@testable import TiqianCoreText

/// Runtime checks that the Core Text adapter shapes real CJK / Latin text and reads real font
/// metrics from the system families PingFang SC and Helvetica Neue.
final class CoreTextShaperTests: XCTestCase {
    private let shaper = CoreTextShaper()
    private let metrics = CoreTextFontMetricsResolver()

    func testShapesCJKRunWithRealAdvance() throws {
        let result = try shaper.shape(input("中文", role: .cjkText))
        XCTAssertEqual(result.clusters.count, 1)
        XCTAssertGreaterThan(result.clusters[0].advance, 0)
        XCTAssertFalse(result.glyphRuns[0].glyphs.isEmpty)
        XCTAssertEqual(String(engineText: result.decisions[0].source), "CoreText")
    }

    func testGlyphAdvancesSumToClusterAdvance() throws {
        let result = try shaper.shape(input("中文书", role: .cjkText))
        let glyphSum = result.glyphRuns[0].glyphs.reduce(Float(0)) { $0 + $1.advance }
        XCTAssertEqual(result.clusters[0].advance, glyphSum, accuracy: 0.5)
    }

    func testShapesLatinRunWithRealAdvance() throws {
        let result = try shaper.shape(input("Tiqian", role: .latinText))
        XCTAssertGreaterThan(result.clusters[0].advance, 0)
        XCTAssertFalse(result.glyphRuns[0].glyphs.isEmpty)
    }

    func testExposesInkBoundsForIdeographicStop() throws {
        let result = try shaper.shape(input("。", role: .cjkPunctuation))
        let glyph = try XCTUnwrap(result.glyphRuns[0].glyphs.first)
        XCTAssertGreaterThan(glyph.advance, 0)
        XCTAssertNotNil(glyph.bounds, "。 should carry ink bounds")
    }

    func testResolvesCJKMetricsWithTypoBox() throws {
        let m = metrics.resolve(FontMetricsRequest("cjk".engineText, 16, .cjkText, "zh-Hans".engineText))
        XCTAssertGreaterThan(m.ascent, 0)
        XCTAssertGreaterThan(m.descent, 0)
        XCTAssertGreaterThan(try XCTUnwrap(m.typoAscent), 0, "a CJK font exposes OS/2 sTypoAscender")
        XCTAssertGreaterThan(try XCTUnwrap(m.typoDescent), 0)
    }

    func testResolvesLatinMetrics() {
        let m = metrics.resolve(FontMetricsRequest("latin".engineText, 16, .latinText, "en".engineText))
        XCTAssertGreaterThan(m.ascent, 0)
        XCTAssertGreaterThan(m.descent, 0)
    }

    func testCJKMetricsFollowTheActualCoreTextFallbackRun() throws {
        let defaultCJK = metrics.resolve(FontMetricsRequest(
            "cjk".engineText, 18, .cjkText, "zh-Hans".engineText,
            BoringArray(), 400, false, "宋".engineText,
        ))
        let latinOnlyRequested = metrics.resolve(FontMetricsRequest(
            "latin-only-cjk".engineText, 18, .cjkText, "zh-Hans".engineText,
            [CoreTextSupport.defaultLatinFamily.engineText].boringArray, 400, false, "宋".engineText,
        ))
        XCTAssertEqual(defaultCJK.ascent, latinOnlyRequested.ascent, accuracy: 0.01)
        XCTAssertEqual(defaultCJK.descent, latinOnlyRequested.descent, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(defaultCJK.typoAscent), try XCTUnwrap(latinOnlyRequested.typoAscent), accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(defaultCJK.typoDescent), try XCTUnwrap(latinOnlyRequested.typoDescent), accuracy: 0.01)
    }

    func testEmptyDisplayTextProducesDegenerateCluster() throws {
        // A layout-decided empty display cluster (a fully compressed space) shapes no glyphs but
        // still emits one zero-advance cluster and run so downstream indices stay aligned.
        let result = try shaper.shape(input("空", role: .cjkText, displayText: ""))
        XCTAssertEqual(result.clusters[0].advance, 0)
        XCTAssertTrue(result.glyphRuns[0].glyphs.isEmpty)
        XCTAssertEqual(result.decisions[0].glyphCount, 0)
        XCTAssertTrue(String(engineText: result.decisions[0].reason).contains("empty"))
    }

    func testShapesSameInputConsistentlyAcrossCalls() throws {
        let a = try shaper.shape(input("中文书", role: .cjkText))
        let b = try shaper.shape(input("中文书", role: .cjkText))
        XCTAssertEqual(a.clusters[0].advance, b.clusters[0].advance)
        XCTAssertEqual(a.glyphRuns[0].glyphs.count, b.glyphRuns[0].glyphs.count)
    }

    func testAppliesOpenTypeFeaturesThroughCoreText() throws {
        let enabled = try shaper.shape(input("fi", role: .latinText, features: ["liga=1"]))
        let disabled = try shaper.shape(input("fi", role: .latinText, features: ["liga=0"]))

        XCTAssertEqual(enabled.glyphRuns[0].openTypeFeatures.map { String(engineText: $0) }, ["liga=1"])
        XCTAssertEqual(disabled.glyphRuns[0].openTypeFeatures.map { String(engineText: $0) }, ["liga=0"])
        XCTAssertEqual(enabled.decisions[0].featureEvidence.map { String(engineText: $0) }, "CoreTextFontDescriptor:liga=1")
        XCTAssertNil(enabled.decisions[0].capabilityIssue)
        XCTAssertNotEqual(
            enabled.glyphRuns[0].glyphs.map(\.id),
            disabled.glyphRuns[0].glyphs.map(\.id),
            "Helvetica Neue's fi ligature must respond to the explicit Core Text feature setting",
        )
    }

    func testVertFeatureSelectsTheBopomofoVerticalToneGlyph() throws {
        let horizontal = try shaper.shape(input("ˇ", role: .cjkText))
        let vertical = try shaper.shape(input("ˇ", role: .cjkText, features: ["vert=1"]))
        XCTAssertNotEqual(
            horizontal.glyphRuns[0].glyphs[0].id,
            vertical.glyphRuns[0].glyphs[0].id,
            "vert=1 must select Core Text's Bopomofo vertical tone, not the western caron glyph",
        )
        XCTAssertNotEqual(vertical.glyphRuns[0].glyphs[0].y, 0)
    }

    func testReportsInvalidOpenTypeFeatureInsteadOfClaimingItWasApplied() throws {
        let result = try shaper.shape(input("fi", role: .latinText, features: ["invalid-tag"]))
        XCTAssertGreaterThan(result.clusters[0].advance, 0, "the explicit degrade still shapes source text")
        XCTAssertTrue(result.glyphRuns[0].openTypeFeatures.isEmpty)
        XCTAssertEqual(
            result.decisions[0].capabilityIssue.map { String(engineText: $0) },
            CoreTextShaper.openTypeFeatureUnavailable,
        )
        XCTAssertNil(result.decisions[0].featureEvidence)
    }

    private func input(
        _ text: String,
        role: FontRole,
        displayText: String? = nil,
        features: [String] = [],
    ) throws -> ShapingInput {
        let units = text.engineText
        let range = try TextRange(0, Int32(units.count))
        let key = "test-\(role.rawValue)".engineText
        return ShapingInput(
            units,
            range,
            TextStyle(BoringArray(), 16),
            FontDecision(range, FontCandidate(key, key, role), role, "test".engineText),
            (displayText ?? text).engineText,
            features.map(\.engineText).readOnlyArray,
        )
    }
}
