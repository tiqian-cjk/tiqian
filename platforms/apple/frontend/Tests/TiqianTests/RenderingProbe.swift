import CoreGraphics
import TiqianCoreText
import TiqianEngine
@testable import Tiqian

/// Test helpers: build engine inputs, rebuild generated value objects through their initializers
/// (the generated Swift classes have no `copy`), and render a `LayoutResult` into an offscreen
/// black-on-white RGBA bitmap.
enum RenderingProbe {
    static let engine = appleParagraphEngine()

    static func layout(
        _ text: String,
        fontSize: Float = 16,
        locale: String = "zh-Hans",
        maxWidth: Float,
        spans: [TextSpan] = [],
        sourceBoundaries: [Int32] = [],
        decorations: [DecorationSpan] = [],
        rubySpans: [RubySpan] = [],
    ) throws -> LayoutResult {
        try engine.layout(LayoutInput(
            TiqianTextContent(text.engineText, spans.boringArray, sourceBoundaries.boringArray),
            TextStyle(BoringArray(), fontSize, locale.engineText),
            ParagraphStyle(),
            try LayoutConstraints(maxWidth),
            BuiltInLayoutProfiles.ClreqHorizontal,
            decorations.readOnlyArray,
            rubySpans.readOnlyArray,
        ))
    }

    static func range(_ start: Int32, _ end: Int32) throws -> TextRange { try TextRange(start, end) }

    /// `result` with every base cluster blanked, no glyph runs, and only `bopomofo` annotations,
    /// so a render shows the annotation ink alone.
    static func annotationsOnly(_ result: LayoutResult, bopomofo: [BopomofoDecisionInfo]) -> LayoutResult {
        let clusters = result.clusters.map {
            Cluster($0.range, $0.text, $0.fontKey, $0.advance, [], $0.baselineShift, $0.leadingLayoutAdvance, $0.glyphInlineShift)
        }
        let debug = LayoutDebugInfo(
            result.debug.maxLinesDecision,
            BoringArray(), BoringArray(), BoringArray(),
            BoringArray(),
            bopomofo.boringArray,
            BoringArray(result.debug.fontDecisions.array),
        )
        return LayoutResult(result.input, result.size, clusters.readOnlyArray, ReadOnlyArray(), result.lines, debug)
    }

    static func bopomofo(_ decision: BopomofoDecisionInfo, placements: [BopomofoGlyphPlacement]) -> BopomofoDecisionInfo {
        BopomofoDecisionInfo(
            decision.baseRange,
            decision.text,
            decision.lineIndex,
            placements.boringArray,
            BoringArray(decision.fontFamilies.array),
            decision.fontWeight,
            decision.locale,
        )
    }

    /// `result` with every line's reserved hyphen advance removed, which suppresses the hyphen.
    static func withoutHyphens(_ result: LayoutResult) -> LayoutResult {
        let lines = result.lines.map {
            LineBox(
                $0.range, $0.clusterRange, $0.baseline, $0.top, $0.bottom, $0.naturalWidth,
                $0.adjustedWidth, $0.visualWidth, $0.hangingPunctuationAdvance, $0.indent, $0.endReason,
                0, BoringArray($0.hyphenGlyphs.array), $0.debug,
            )
        }
        return LayoutResult(result.input, result.size, result.clusters, result.glyphRuns, lines.readOnlyArray, result.debug)
    }

    /// An RGBA8 premultiplied bitmap filled white, with black as the inherited fill color.
    struct Bitmap {
        let width: Int
        let height: Int
        let context: CGContext

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )!
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        }

        /// The RGBA bytes of the pixel at image row `row` (0 = top) and column `column`.
        func pixel(row: Int, column: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            let offset = row * width * 4 + column * 4
            return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
        }
    }

    static func render(
        _ result: LayoutResult,
        width: Int,
        height: Int,
        spans: [TextSpan] = [],
        colorSpans: [ColorSpan] = [],
        richTextSpans: [RichTextSpan] = [],
    ) throws -> Bitmap {
        let bitmap = Bitmap(width: width, height: height)
        try CoreTextLayoutRenderer().draw(
            result,
            in: bitmap.context,
            canvasHeight: Double(height),
            spans: spans,
            colorSpans: colorSpans,
            richTextSpans: richTextSpans,
        )
        return bitmap
    }

    /// Ink pixel counts (red channel below 200) per horizontal band, top to bottom.
    static func inkBands(_ result: LayoutResult, width: Int, bands: Int, richTextSpans: [RichTextSpan] = []) throws -> [Int] {
        let height = max(48, Int(result.size.height) + 12)
        let bitmap = try render(result, width: width, height: height, richTextSpans: richTextSpans)
        var counts = [Int](repeating: 0, count: bands)
        for row in 0..<height {
            for column in 0..<width where bitmap.pixel(row: row, column: column).r < 200 {
                counts[row * bands / height] += 1
            }
        }
        return counts
    }

    /// The inclusive column range holding ink (red channel below 128), or nil for a blank render.
    static func inkColumns(_ result: LayoutResult, width: Int) throws -> ClosedRange<Int>? {
        let height = max(96, Int(result.size.height) + 24)
        let bitmap = try render(result, width: width, height: height)
        var low = width
        var high = -1
        for row in 0..<height {
            for column in 0..<width where bitmap.pixel(row: row, column: column).r < 128 {
                low = min(low, column)
                high = max(high, column)
            }
        }
        return high >= low ? low...high : nil
    }

    /// Horizontal ink centroid of the upper half of the inked rows minus that of the lower half
    /// (positive = the top leans right), with the inked row count, replaying the input's own text
    /// spans. Nil for a blank render.
    static func inkSkew(_ result: LayoutResult) throws -> (skew: Double, inkHeight: Int)? {
        let width = 200
        let height = max(96, Int(result.size.height) + 16)
        let bitmap = try render(result, width: width, height: height, spans: result.input.content.spans.array)
        var rows: [(row: Int, columnSum: Int, count: Int)] = []
        for row in 0..<height {
            var columnSum = 0
            var count = 0
            for column in 0..<width where bitmap.pixel(row: row, column: column).r < 128 {
                columnSum += column
                count += 1
            }
            if count > 0 { rows.append((row, columnSum, count)) }
        }
        guard let top = rows.first?.row, let bottom = rows.last?.row else { return nil }
        let middle = (top + bottom) / 2
        func centroid(_ part: [(row: Int, columnSum: Int, count: Int)]) -> Double {
            Double(part.map(\.columnSum).reduce(0, +)) / Double(part.map(\.count).reduce(0, +))
        }
        // Image rows grow downward, so rows at or above `middle` are the upper half of the glyph.
        let upper = centroid(rows.filter { $0.row <= middle })
        let lower = centroid(rows.filter { $0.row > middle })
        return (upper - lower, bottom - top + 1)
    }

    /// Count of reddish pixels (R > 120, G and B < 80) with black as the base fill.
    static func redInk(_ result: LayoutResult, colorSpans: [ColorSpan]) throws -> Int {
        let width = 96
        let height = max(56, Int(result.size.height) + 12)
        let bitmap = try render(result, width: width, height: height, colorSpans: colorSpans)
        var reds = 0
        for row in 0..<height {
            for column in 0..<width {
                let p = bitmap.pixel(row: row, column: column)
                if p.r > 120, p.g < 80, p.b < 80 { reds += 1 }
            }
        }
        return reds
    }
}
