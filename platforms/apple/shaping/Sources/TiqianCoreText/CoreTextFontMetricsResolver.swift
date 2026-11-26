import CoreText
import Foundation
import TiqianEngine

/// Core Text font-metrics resolver (ADR 0002 amendment), the Apple peer of `SkiaFontMetricsResolver`.
///
/// - hhea-style ascent / descent / leading come from the resolved `CTFont`;
/// - the CJK ideographic em box (字身框) comes from the font's `OS/2` sTypoAscender /
///   sTypoDescender and is returned as `typoAscent` / `typoDescent`, which
///   `ScriptAwareFontMetricsNormalizer` uses to place the CJK line box.
///
/// `FontMetricsRequest.faceSelectionText` selects the concrete Core Text fallback face before the
/// metrics are read (`CoreTextFallbackFaceMetrics`), so a family that lacks the requested characters
/// reports the metrics of the face that is drawn.
public final class CoreTextFontMetricsResolver: FontMetricsResolver {
    /// `CoreTextMetricsReferenceSize`: point size at which per-em ratios are read and normalized.
    static let referenceSize: Double = 128

    private let cjkFamily: String
    private let latinFamily: String

    public init(
        cjkFamily: String = CoreTextSupport.defaultCJKFamily,
        latinFamily: String = CoreTextSupport.defaultLatinFamily,
    ) {
        self.cjkFamily = cjkFamily
        self.latinFamily = latinFamily
    }

    public func resolve(_ request: FontMetricsRequest) -> RawFontMetrics {
        let family = request.fontFamilies.first.map { String(engineText: $0) }
            ?? (request.role.usesLatinFace() ? latinFamily : cjkFamily)
        let baseFont = CoreTextSupport.font(
            family: family,
            size: Self.referenceSize,
            weight: Int(request.fontWeight),
            italic: request.italic,
        )
        let resolvedFont = CoreTextSupport.resolvedRunFont(
            text: request.faceSelectionText,
            font: baseFont,
            language: String(engineText: request.locale),
        )
        let ratios = CoreTextSupport.ratios(for: resolvedFont) { Self.readRatios(resolvedFont) }
        let size = Double(request.fontSize)
        return RawFontMetrics(
            Float(ratios.ascent * size),
            Float(ratios.descent * size),
            Float(ratios.leading * size),
            .rawTables,
            ratios.typoAscent.map { Float($0 * size) },
            ratios.typoDescent.map { Float($0 * size) },
        )
    }

    /// Reads the size-independent metric ratios once at `referenceSize`. Core Text scales these
    /// metrics linearly with point size, so `ratio * size` equals a per-size read.
    static func readRatios(_ font: CTFont) -> CoreTextSupport.MetricRatios {
        let unitsPerEm = Double(CTFontGetUnitsPerEm(font))
        let upm = unitsPerEm > 0 ? unitsPerEm : 1000
        let typo = readOS2Typo(font)
        return CoreTextSupport.MetricRatios(
            ascent: Double(CTFontGetAscent(font)) / referenceSize,
            descent: Double(CTFontGetDescent(font)) / referenceSize,
            leading: Double(CTFontGetLeading(font)) / referenceSize,
            typoAscent: typo.map { Double($0.ascender) / upm },
            // sTypoDescender is a negative FUnit value below the baseline; the engine stores a
            // positive descent.
            typoDescent: typo.map { -Double($0.descender) / upm },
        )
    }

    /// `OS/2` sTypoAscender (byte offset 68) and sTypoDescender (offset 70), big-endian int16 FUnits.
    static func readOS2Typo(_ font: CTFont) -> (ascender: Int16, descender: Int16)? {
        let tag = CTFontTableTag(kCTFontTableOS2)
        guard let table = CTFontCopyTable(font, tag, []) else { return nil }
        let data = table as Data
        guard data.count >= 72 else { return nil }
        func int16(at offset: Int) -> Int16 {
            Int16(bitPattern: UInt16(data[data.startIndex + offset]) << 8 | UInt16(data[data.startIndex + offset + 1]))
        }
        return (int16(at: 68), int16(at: 70))
    }
}
