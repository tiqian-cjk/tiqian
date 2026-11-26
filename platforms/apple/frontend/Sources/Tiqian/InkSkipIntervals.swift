import TiqianEngine

/// One horizontal glyph-ink interval on a line, in layout coordinates.
struct CoreTextInkInterval: Equatable {
    let left: Float
    let right: Float
}

/// `CoreTextRecordedInkSkipIntervals`: skip-ink evidence derived from glyph bounds that the
/// `LayoutResult` already carries. The renderer does not re-shape or estimate ink, so no second
/// geometry source exists. The index groups positioned clusters by line once and computes each
/// line's glyph ink on first use, so every decoration segment of a paragraph shares one pass.
final class CoreTextInkIndex {
    private struct InkRect {
        let left: Float
        let top: Float
        let right: Float
        let bottom: Float
    }

    private let glyphRuns: ReadOnlyArray<GlyphRun>
    private let positionedByLine: [Int32: [TextRange: PositionedCluster]]
    private var inkByLine: [Int32: [InkRect]] = [:]

    init(result: LayoutResult, positioned: [PositionedCluster]) {
        glyphRuns = result.glyphRuns
        var byLine: [Int32: [TextRange: PositionedCluster]] = [:]
        for cluster in positioned {
            byLine[cluster.lineIndex, default: [:]][cluster.range] = cluster
        }
        positionedByLine = byLine
    }

    /// Ink intervals on `lineIndex` whose vertical extent meets `bandTop...bandBottom`, in glyph-run
    /// order.
    func intervals(lineIndex: Int32, bandTop: Float, bandBottom: Float) -> [CoreTextInkInterval] {
        ink(onLine: lineIndex)
            .filter { !($0.bottom < bandTop || $0.top > bandBottom) }
            .map { CoreTextInkInterval(left: $0.left, right: $0.right) }
    }

    private func ink(onLine lineIndex: Int32) -> [InkRect] {
        if let cached = inkByLine[lineIndex] { return cached }
        var rects: [InkRect] = []
        if let positioned = positionedByLine[lineIndex] {
            for run in glyphRuns {
                for glyph in run.glyphs {
                    guard let bounds = glyph.bounds, let cluster = positioned[glyph.clusterRange] else { continue }
                    rects.append(InkRect(
                        left: cluster.drawX + glyph.x + bounds.left,
                        top: cluster.baseline + glyph.y + bounds.top,
                        right: cluster.drawX + glyph.x + bounds.right,
                        bottom: cluster.baseline + glyph.y + bounds.bottom,
                    ))
                }
            }
        }
        inkByLine[lineIndex] = rects
        return rects
    }
}

extension LayoutResult {
    /// Skip-ink intervals of one line, built from a fresh `CoreTextInkIndex`.
    func coreTextInkSkipIntervals(lineIndex: Int32, bandTop: Float, bandBottom: Float) -> [CoreTextInkInterval] {
        CoreTextInkIndex(result: self, positioned: Array(positionedClusters()))
            .intervals(lineIndex: lineIndex, bandTop: bandTop, bandBottom: bandBottom)
    }
}

/// Calls `draw` for each part of `left...right` that stays outside the skip intervals widened by
/// `clearance`. Parts narrower than half a point are dropped.
func keptIntervals(
    left: Double,
    right: Double,
    skips: [CoreTextInkInterval],
    clearance: Double,
    draw: (Double, Double) -> Void,
) {
    let widened = skips
        .map { (max(left, Double($0.left) - clearance), min(right, Double($0.right) + clearance)) }
        .filter { $0.1 > $0.0 }
        .sorted { $0.0 < $1.0 }
    var merged: [(Double, Double)] = []
    for interval in widened {
        if let previous = merged.last, interval.0 <= previous.1 {
            merged[merged.count - 1] = (previous.0, max(previous.1, interval.1))
        } else {
            merged.append(interval)
        }
    }
    var cursor = left
    for (start, end) in merged {
        if start > cursor + 0.5 { draw(cursor, start) }
        cursor = max(cursor, end)
    }
    if cursor < right - 0.5 { draw(cursor, right) }
}
