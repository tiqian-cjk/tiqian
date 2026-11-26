import CoreGraphics
import TiqianCoreText
import TiqianEngine

/// One laid-out block placed at (`x`, `yTop`) in a `Document` (points, y-down from the top).
struct PlacedBlock {
    let result: LayoutResult
    let spans: [TextSpan]
    let colorSpans: [ColorSpan]
    let richTextSpans: [RichTextSpan]
    let x: Double
    let yTop: Double
    /// Logical source separator before this block; a list body continues its marker row.
    let sourceSeparatorBefore: [UInt16]

    init(result: LayoutResult, lowered: LoweredParagraph?, x: Double, yTop: Double, sourceSeparatorBefore: String = "\n") {
        self.result = result
        spans = lowered?.spans ?? []
        colorSpans = lowered?.colorSpans ?? []
        richTextSpans = lowered?.richTextSpans ?? []
        self.x = x
        self.yTop = yTop
        self.sourceSeparatorBefore = sourceSeparatorBefore.engineText
    }

    var sourceLength: Int { result.input.content.text.count }
}

/// A UTF-16 source range in document offsets.
public struct SelectionRange: Equatable {
    public let start: Int
    public let end: Int
    public var isEmpty: Bool { start == end }
}

/// One line-local occupied box in document coordinates (top-left origin, y-down).
public struct SelectionBox: Equatable {
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
}

/// One visual fragment of a link in document coordinates (top-left origin, y-down).
public struct LinkBox: Equatable {
    public let target: String
    public let start: Int
    public let end: Int
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
}

/// A laid-out, drawable multi-block document, the result of `DocBuilder.layout(width:)`. Each
/// block is an engine `LayoutResult`; the document only stacks blocks and offsets list bodies into
/// their marker column. All offsets are UTF-16 offsets into `text`.
public final class Document {
    private struct IndexedBlock {
        let placed: PlacedBlock
        let sourceStart: Int
        let sourceEnd: Int
    }

    public let width: Double
    public let height: Double
    let blocks: [PlacedBlock]
    private let indexedBlocks: [IndexedBlock]
    private let sourceUnits: [UInt16]
    private let renderer: CoreTextLayoutRenderer

    /// The document's plain source text, each block joined with its logical separator. Hosts expose
    /// it as the accessibility value so source and accessibility offsets stay faithful (AGENTS.md
    /// implementation constraint 4).
    public let text: String

    init(blocks: [PlacedBlock], width: Double, height: Double, renderer: CoreTextLayoutRenderer) {
        var source: [UInt16] = []
        var indexed: [IndexedBlock] = []
        for (index, block) in blocks.enumerated() {
            if index > 0 { source += block.sourceSeparatorBefore }
            let start = source.count
            source += block.result.input.content.text
            indexed.append(IndexedBlock(placed: block, sourceStart: start, sourceEnd: source.count))
        }
        self.blocks = blocks
        indexedBlocks = indexed
        sourceUnits = source
        text = String(engineText: source)
        self.width = width
        self.height = height
        self.renderer = renderer
    }

    /// Number of laid-out blocks (paragraphs plus list marker and body rows).
    public var blockCount: Int { blocks.count }

    /// The safe UTF-16 insertion offset at a document point. The block is chosen by its placed
    /// rectangle, so list markers and bodies sharing one row need no host-side layout model.
    public func selectionOffset(x: Double, y: Double) -> Int {
        guard let indexed = nearestBlock(x: x, y: y) else { return 0 }
        let block = indexed.placed
        let local = EngineInvariant.call("LayoutResult.getSelectionOffsetForPosition") {
            try block.result.getSelectionOffsetForPosition(Float(x - block.x), Float(y - block.yTop))
        }
        return indexed.sourceStart + Int(local)
    }

    /// The source word or unit under a point, from the engine's selection policy.
    public func selectionWord(x: Double, y: Double) -> SelectionRange? {
        guard let indexed = nearestBlock(x: x, y: y) else { return nil }
        let block = indexed.placed
        let local = EngineInvariant.call("LayoutResult.getSelectionWordBoundaryForPosition") {
            try block.result.getSelectionWordBoundaryForPosition(Float(x - block.x), Float(y - block.yTop))
        }
        guard let local else { return nil }
        return SelectionRange(start: indexed.sourceStart + Int(local.start), end: indexed.sourceStart + Int(local.end))
    }

    /// Snaps an external UTF-16 offset away from surrogate, combining-mark and grapheme interiors.
    public func selectionBoundary(offset: Int, forward: Bool) -> Int {
        let clamped = offset.clamped(0, sourceUnits.count)
        // A separator between two blocks is already a safe boundary.
        guard let indexed = indexedBlocks.first(where: { clamped >= $0.sourceStart && clamped <= $0.sourceEnd }) else {
            return clamped
        }
        let local = (clamped - indexed.sourceStart).clamped(0, indexed.placed.sourceLength)
        let snapped = EngineInvariant.call("LayoutResult.coerceSelectionOffset") {
            try indexed.placed.result.coerceSelectionOffset(Int32(local), forward ? .forward : .backward)
        }
        return indexed.sourceStart + Int(snapped)
    }

    /// The source-faithful text of a UTF-16 range, for text input and accessibility.
    public func textInRange(start: Int, end: Int) -> String {
        let safeStart = start.clamped(0, sourceUnits.count)
        let safeEnd = end.clamped(safeStart, sourceUnits.count)
        return String(engineText: Array(sourceUnits[safeStart..<safeEnd]))
    }

    /// Clipboard text for a source range. Selection and VoiceOver keep `textInRange`'s exact
    /// offsets; only the pasteboard export adds the Web-compatible parenthesized ruby / 注音 readings.
    public func clipboardTextInRange(start: Int, end: Int) -> String {
        let safeStart = start.clamped(0, sourceUnits.count)
        let safeEnd = end.clamped(safeStart, sourceUnits.count)
        guard safeStart < safeEnd else { return "" }
        var out: [UInt16] = []
        var cursor = safeStart
        for indexed in indexedBlocks {
            if indexed.sourceEnd <= safeStart { continue }
            if indexed.sourceStart >= safeEnd { break }
            let separatorEnd = min(safeEnd, indexed.sourceStart)
            if cursor < separatorEnd {
                out += sourceUnits[cursor..<separatorEnd]
                cursor = separatorEnd
            }
            let overlapStart = max(safeStart, indexed.sourceStart)
            let overlapEnd = min(safeEnd, indexed.sourceEnd)
            if overlapStart < overlapEnd {
                out += EngineInvariant.call("LayoutResult.getTextForCopy") {
                    try indexed.placed.result.getTextForCopy(TextRange(
                        Int32(overlapStart - indexed.sourceStart),
                        Int32(overlapEnd - indexed.sourceStart),
                    ))
                }
                cursor = overlapEnd
            }
        }
        if cursor < safeEnd { out += sourceUnits[cursor..<safeEnd] }
        return String(engineText: out)
    }

    /// Link fragments, from the same occupied source geometry as selection and hit testing.
    public func linkBoxes() -> [LinkBox] {
        var boxes: [LinkBox] = []
        for indexed in indexedBlocks {
            let block = indexed.placed
            for span in block.richTextSpans {
                guard let link = span.role as? Link else { continue }
                let target = String(engineText: link.target)
                for rect in block.result.getBoundingBoxes(span.range) {
                    boxes.append(LinkBox(
                        target: target,
                        start: indexed.sourceStart + Int(span.range.start),
                        end: indexed.sourceStart + Int(span.range.end),
                        left: block.x + Double(rect.left),
                        top: block.yTop + Double(rect.top),
                        right: block.x + Double(rect.right),
                        bottom: block.yTop + Double(rect.bottom),
                    ))
                }
            }
        }
        return boxes
    }

    /// The link target under a document point, or nil outside the occupied link boxes.
    public func linkAt(x: Double, y: Double) -> String? {
        linkBoxes().first { x >= $0.left && x <= $0.right && y >= $0.top && y <= $0.bottom }?.target
    }

    /// Continuous, line-local selection boxes for a UTF-16 source range. Adjacent cluster boxes on
    /// one line are merged so the native highlight has no seams.
    public func selectionBoxes(start: Int, end: Int) -> [SelectionBox] {
        let safeStart = min(start, end).clamped(0, sourceUnits.count)
        let safeEnd = max(start, end).clamped(safeStart, sourceUnits.count)
        guard safeStart < safeEnd else { return [] }
        var boxes: [SelectionBox] = []
        for indexed in indexedBlocks {
            let block = indexed.placed
            let localStart = (safeStart - indexed.sourceStart).clamped(0, block.sourceLength)
            let localEnd = (safeEnd - indexed.sourceStart).clamped(localStart, block.sourceLength)
            if localStart == localEnd { continue }
            let rects = EngineInvariant.call("LayoutResult.getBoundingBoxes") {
                block.result.getBoundingBoxes(try TextRange(Int32(localStart), Int32(localEnd)))
            }
            for rect in rects {
                boxes.append(SelectionBox(
                    left: block.x + Double(rect.left),
                    top: block.yTop + Double(rect.top),
                    right: block.x + Double(rect.right),
                    bottom: block.yTop + Double(rect.bottom),
                ))
            }
        }
        return Self.mergeLineLocalBoxes(boxes)
    }

    /// The caret box for a UTF-16 source offset.
    public func caretBox(offset: Int) -> SelectionBox {
        let clamped = offset.clamped(0, sourceUnits.count)
        guard let indexed = indexedBlocks.last(where: { clamped >= $0.sourceStart }) else {
            return SelectionBox(left: 0, top: 0, right: 1, bottom: 0)
        }
        let block = indexed.placed
        let local = (clamped - indexed.sourceStart).clamped(0, block.sourceLength)
        let rect = EngineInvariant.call("LayoutResult.getCursorRect") {
            try block.result.getCursorRect(Int32(local))
        }
        return SelectionBox(
            left: block.x + Double(rect.left),
            top: block.yTop + Double(rect.top),
            right: block.x + Double(rect.right),
            bottom: block.yTop + Double(rect.bottom),
        )
    }

    /// Draws the document into a y-up `context` whose height is `canvasHeight`, with the document
    /// top at that height (callers fold a top inset into it). Each block draws at
    /// `canvasHeight - yTop`; list bodies translate the context by the marker-column width. Text
    /// inherits the context fill color; color spans override it per cluster.
    public func draw(in context: CGContext, canvasHeight: Double) {
        for block in blocks {
            let blockCanvasHeight = canvasHeight - block.yTop
            if blockCanvasHeight <= 0 { continue }
            context.saveGState()
            if block.x != 0 { context.translateBy(x: block.x, y: 0) }
            EngineInvariant.call("CoreTextLayoutRenderer.draw") {
                try renderer.draw(
                    block.result,
                    in: context,
                    canvasHeight: blockCanvasHeight,
                    spans: block.spans,
                    colorSpans: block.colorSpans,
                    richTextSpans: block.richTextSpans,
                )
            }
            context.restoreGState()
        }
    }

    private func nearestBlock(x: Double, y: Double) -> IndexedBlock? {
        indexedBlocks.min { distanceSquared($0, x, y) < distanceSquared($1, x, y) }
    }

    private func distanceSquared(_ indexed: IndexedBlock, _ x: Double, _ y: Double) -> Double {
        let block = indexed.placed
        let left = block.x
        let top = block.yTop
        let right = left + Double(block.result.size.width)
        let bottom = top + Double(block.result.size.height)
        let dx = x < left ? left - x : (x > right ? x - right : 0)
        let dy = y < top ? top - y : (y > bottom ? y - bottom : 0)
        return dx * dx + dy * dy
    }

    /// `SelectionBoxLineMerge`: merges consecutive boxes whose top and bottom agree within half a
    /// point, which are slices of one line.
    static func mergeLineLocalBoxes(_ boxes: [SelectionBox]) -> [SelectionBox] {
        var merged: [SelectionBox] = []
        for next in boxes {
            if let previous = merged.last, abs(previous.top - next.top) < 0.5, abs(previous.bottom - next.bottom) < 0.5 {
                merged[merged.count - 1] = SelectionBox(
                    left: min(previous.left, next.left),
                    top: min(previous.top, next.top),
                    right: max(previous.right, next.right),
                    bottom: max(previous.bottom, next.bottom),
                )
            } else {
                merged.append(next)
            }
        }
        return merged
    }
}

extension Int {
    func clamped(_ lower: Int, _ upper: Int) -> Int { Swift.min(Swift.max(self, lower), upper) }
}
