import CoreGraphics
import CoreText

/// `CoreTextDisplayList`: every primitive the renderer paints for one `LayoutResult`, resolved once
/// and replayed on each draw. Glyph runs carry their Core Text font, glyph ids and positions, so a
/// replay calls `CTFontDrawGlyphs` without reshaping, re-querying the engine or rebuilding lookup
/// tables. A `LayoutResult` is immutable, so its display list stays valid for the result's lifetime.
///
/// Coordinates: primitives are stored in a y-up space whose origin is the layout's top-left
/// corner, so layout y maps to `-y`. `replay(in:canvasHeight:)` translates the context by
/// `canvasHeight`, which reproduces the renderer's `canvasHeight - y` mapping.
struct CoreTextDisplayList {
    struct GlyphRunOp {
        let font: CTFont
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
    }

    enum Primitive {
        case glyphs([GlyphRunOp])
        case fillRect(CGRect)
        case fillEllipse(CGRect)
        case fillPath(CGPath)
    }

    struct Op {
        let primitive: Primitive
        /// `0xAARRGGBB` fill, or nil to inherit the context's current fill color.
        let argb: UInt32?
    }

    private(set) var ops: [Op] = []

    /// Union of every primitive's painted area in layout coordinates (top-left origin, y-down);
    /// `.null` when nothing paints. Hosts compare it with their visible rectangle to skip blocks.
    private(set) var paintBounds: CGRect = .null

    mutating func append(_ primitive: Primitive, argb: UInt32?) {
        let bounds = Self.bounds(of: primitive)
        if bounds.isNull { return }
        ops.append(Op(primitive: primitive, argb: argb))
        // Stored space is y-up from the layout top; flip back to layout's y-down for the bounds.
        paintBounds = paintBounds.union(CGRect(x: bounds.minX, y: -bounds.maxY, width: bounds.width, height: bounds.height))
    }

    /// Draws every primitive in order. Consecutive primitives with the same explicit color share one
    /// saved graphics state; primitives without a color inherit the caller's fill color.
    func replay(in context: CGContext, canvasHeight: Double) {
        context.saveGState()
        context.translateBy(x: 0, y: canvasHeight)
        var activeColor: UInt32?
        for op in ops {
            if op.argb != activeColor {
                if activeColor != nil { context.restoreGState() }
                if let argb = op.argb {
                    context.saveGState()
                    context.setFillColor(
                        red: CGFloat((argb >> 16) & 0xFF) / 255,
                        green: CGFloat((argb >> 8) & 0xFF) / 255,
                        blue: CGFloat(argb & 0xFF) / 255,
                        alpha: CGFloat((argb >> 24) & 0xFF) / 255,
                    )
                }
                activeColor = op.argb
            }
            switch op.primitive {
            case let .glyphs(runs):
                for run in runs {
                    CTFontDrawGlyphs(run.font, run.glyphs, run.positions, run.glyphs.count, context)
                }
            case let .fillRect(rect):
                context.fill(rect)
            case let .fillEllipse(rect):
                context.fillEllipse(in: rect)
            case let .fillPath(path):
                context.addPath(path)
                context.fillPath()
            }
        }
        if activeColor != nil { context.restoreGState() }
        context.restoreGState()
    }

    /// The painted area of one primitive in the stored y-up space.
    private static func bounds(of primitive: Primitive) -> CGRect {
        switch primitive {
        case let .glyphs(runs):
            var union = CGRect.null
            for run in runs where !run.glyphs.isEmpty {
                var rects = [CGRect](repeating: .zero, count: run.glyphs.count)
                CTFontGetBoundingRectsForGlyphs(run.font, .horizontal, run.glyphs, &rects, run.glyphs.count)
                // A synthetic-oblique font carries a shear matrix. The union with the sheared rect
                // keeps the bounds covering the drawn ink whether or not the glyph rects include it.
                let matrix = CTFontGetMatrix(run.font)
                for (index, rect) in rects.enumerated() where !rect.isEmpty {
                    let ink = rect.union(rect.applying(matrix))
                    union = union.union(ink.offsetBy(dx: run.positions[index].x, dy: run.positions[index].y))
                }
            }
            return union
        case let .fillRect(rect), let .fillEllipse(rect):
            return rect.isEmpty ? .null : rect
        case let .fillPath(path):
            return path.boundingBoxOfPath
        }
    }
}
