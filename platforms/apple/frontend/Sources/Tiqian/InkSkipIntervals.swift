import TiqianEngine

/// One horizontal glyph-ink interval on a line, in layout coordinates.
struct CoreTextInkInterval: Equatable {
    let left: Float
    let right: Float
}

extension LayoutResult {
    /// `CoreTextRecordedInkSkipIntervals`: skip-ink evidence derived from glyph bounds that the
    /// `LayoutResult` already carries. The renderer does not re-shape or estimate ink, so no second
    /// geometry source exists.
    func coreTextInkSkipIntervals(lineIndex: Int32, bandTop: Float, bandBottom: Float) -> [CoreTextInkInterval] {
        var positioned: [TextRange: PositionedCluster] = [:]
        for cluster in positionedClusters() where cluster.lineIndex == lineIndex {
            positioned[cluster.range] = cluster
        }
        var intervals: [CoreTextInkInterval] = []
        for run in glyphRuns {
            for glyph in run.glyphs {
                guard let bounds = glyph.bounds, let cluster = positioned[glyph.clusterRange] else { continue }
                let top = cluster.baseline + glyph.y + bounds.top
                let bottom = cluster.baseline + glyph.y + bounds.bottom
                if bottom < bandTop || top > bandBottom { continue }
                intervals.append(CoreTextInkInterval(
                    left: cluster.drawX + glyph.x + bounds.left,
                    right: cluster.drawX + glyph.x + bounds.right,
                ))
            }
        }
        return intervals
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
