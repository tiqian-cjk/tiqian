import CoreText
import XCTest
@testable import TiqianCoreText

/// Coverage for the shared Core Text font and line cache that the shaper, the metrics resolver and
/// the renderer rely on for measure == draw.
final class CoreTextSupportTests: XCTestCase {
    func testResolvesRealSystemFamilies() {
        let cjk = CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 16)
        let latin = CoreTextSupport.font(family: CoreTextSupport.defaultLatinFamily, size: 16)
        XCTAssertEqual(CTFontCopyFamilyName(cjk) as String, CoreTextSupport.defaultCJKFamily)
        XCTAssertEqual(CTFontCopyFamilyName(latin) as String, CoreTextSupport.defaultLatinFamily)
    }

    func testWeightedFontIsCachedByIdentity() {
        // weight != 400 takes the weight-trait descriptor path.
        let heavy = CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 16, weight: 700)
        XCTAssertTrue(heavy === CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 16, weight: 700))
    }

    func testItalicFontIsCachedByIdentityAndSheared() {
        let oblique = CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 16, italic: true)
        XCTAssertTrue(oblique === CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 16, italic: true))
        XCTAssertEqual(CTFontGetMatrix(oblique).c, CoreTextSupport.obliqueShear, accuracy: 1e-9)
    }

    func testRepeatLineRequestReturnsTheCachedLine() throws {
        let font = CoreTextSupport.font(family: CoreTextSupport.defaultCJKFamily, size: 18)
        let a = try XCTUnwrap(CoreTextSupport.line(text: "中文".engineText, font: font, language: "zh-Hans"))
        let b = try XCTUnwrap(CoreTextSupport.line(text: "中文".engineText, font: font, language: "zh-Hans"))
        XCTAssertTrue(a === b)
    }

    func testParsesOpenTypeFeatureSyntax() {
        XCTAssertEqual(CoreTextSupport.canonicalOpenTypeFeatures(["liga", "fwid=1", "palt=0"]), ["liga=1", "fwid=1", "palt=0"])
        XCTAssertNil(CoreTextSupport.canonicalOpenTypeFeatures(["toolong"]))
        XCTAssertNil(CoreTextSupport.canonicalOpenTypeFeatures(["liga=1=2"]))
        XCTAssertNil(CoreTextSupport.canonicalOpenTypeFeatures(["liga=-1"]))
        XCTAssertNil(CoreTextSupport.canonicalOpenTypeFeatures(["liga=x"]))
    }

    func testInsertionOrderedCacheEvictsOldestEntry() {
        var cache = InsertionOrderedCache<Int, String>(maxEntries: 2)
        cache.insert("a", for: 1)
        cache.insert("b", for: 2)
        cache.insert("c", for: 3)
        XCTAssertNil(cache.value(for: 1))
        XCTAssertEqual(cache.value(for: 2), "b")
        XCTAssertEqual(cache.value(for: 3), "c")
    }
}
