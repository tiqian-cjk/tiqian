import Foundation
import TiqianCoreText
import TiqianEngine

/// Assembles authored blocks into a `Document`. Obtain one from `Typesetter.documentBuilder()`, add
/// blocks, then call `layout(width:)` at each column width. The builder keeps the authored content,
/// so a reflow at a new width does not re-lower it.
public final class DocBuilder {
    private let typesetter: Typesetter
    private var blocks: [AuthoredBlock] = []

    init(typesetter: Typesetter) {
        self.typesetter = typesetter
    }

    /// A body paragraph with the CLREQ measure-adaptive first-line indent.
    @discardableResult
    public func paragraph(_ content: ParagraphContent) -> DocBuilder { append(.paragraph(content, .firstLine)) }

    /// A paragraph without indent (titles, lead-ins).
    @discardableResult
    public func flushParagraph(_ content: ParagraphContent) -> DocBuilder { append(.paragraph(content, .flush)) }

    /// A quote block: the whole paragraph indents `amount` 字.
    @discardableResult
    public func quote(_ content: ParagraphContent, amount: Float = 2) -> DocBuilder {
        append(.paragraph(content, .quote(amount: amount, firstLine: 0)))
    }

    /// 凸排: the first line is flush and later lines indent `amount` 字.
    @discardableResult
    public func hangingParagraph(_ content: ParagraphContent, amount: Float = 2) -> DocBuilder {
        append(.paragraph(content, .hanging(amount)))
    }

    /// One blank line of vertical space (CLREQ 节).
    @discardableResult
    public func section() -> DocBuilder { append(.section) }

    /// 编号列表 with 汉字数字 markers (一、二、…), bodies aligned in one 凸排 column.
    @discardableResult
    public func numberedList(_ items: [ParagraphContent]) -> DocBuilder { append(.list(items, .cjkNumber(suffix: "、"))) }

    /// 编号列表 with Arabic markers (1. 2. …).
    @discardableResult
    public func decimalList(_ items: [ParagraphContent]) -> DocBuilder { append(.list(items, .decimal)) }

    /// 项目符号列表 (• …).
    @discardableResult
    public func bulletList(_ items: [ParagraphContent]) -> DocBuilder { append(.list(items, .bullet("•"))) }

    /// Lays every block out at `width` points and stacks the blocks into a drawable `Document`.
    public func layout(width: Float) -> Document {
        EngineInvariant.call("DocBuilder.layout") {
            try DocumentLayout(typesetter: typesetter, width: width).layout(blocks)
        }
    }

    private func append(_ block: AuthoredBlock) -> DocBuilder {
        blocks.append(block)
        return self
    }
}

/// A block the caller has authored but not yet laid out.
enum AuthoredBlock {
    case paragraph(ParagraphContent, BlockIndent)
    case list([ParagraphContent], ListMarkerFormat)
    case section
}

/// 段首缩排 (CLREQ §6.2.1), resolved to the engine's `(blockIndent, firstLineIndent)`.
enum BlockIndent {
    case firstLine
    case flush
    case hanging(Float)
    case quote(amount: Float, firstLine: Float)

    /// A nil first-line indent selects the engine's measure-adaptive default.
    func resolve() -> (block: Ic, firstLine: Ic?) {
        switch self {
        case .firstLine: (Ic.Zero, nil)
        case .flush: (Ic.Zero, Ic.Zero)
        case let .hanging(amount): (FloatIc.ic(amount), FloatIc.ic(-amount))
        case let .quote(amount, firstLine): (FloatIc.ic(amount), FloatIc.ic(firstLine))
        }
    }
}

/// A list item's marker text (CLREQ 凸排).
enum ListMarkerFormat {
    case decimal
    case cjkNumber(suffix: String)
    case bullet(String)

    func format(_ n: Int) -> String {
        switch self {
        case .decimal: "\(n)."
        case let .cjkNumber(suffix): Self.cjkNumeral(n) + suffix
        case let .bullet(glyph): glyph
        }
    }

    private static let cjkDigits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 0–99 to 汉字数字 (十、二十一…); other values stay Arabic.
    static func cjkNumeral(_ n: Int) -> String {
        switch n {
        case 0...9: cjkDigits[n]
        case 10...19: "十" + (n == 10 ? "" : cjkDigits[n - 10])
        case 20...99: cjkDigits[n / 10] + "十" + (n % 10 == 0 ? "" : cjkDigits[n % 10])
        default: String(n)
        }
    }
}

/// Lays authored blocks out and stacks them vertically; a marker column offsets list bodies
/// (CLREQ 凸排). This is generic document layout, not sample content.
private struct DocumentLayout {
    let typesetter: Typesetter
    let width: Float

    private var baseSize: Float { typesetter.fontSize }

    /// `DocumentSectionGap`: one blank line of 中文正文 leading (1.5 em).
    private var sectionGap: Float { baseSize * 1.5 }

    func layout(_ blocks: [AuthoredBlock]) throws -> Document {
        var placed: [PlacedBlock] = []
        var cursorY: Float = 0
        for block in blocks {
            switch block {
            case .section:
                cursorY += sectionGap
            case let .paragraph(content, indent):
                let (result, lowered) = try layoutParagraph(content, indent: indent, columnWidth: width)
                placed.append(PlacedBlock(result: result, lowered: lowered, x: 0, yTop: Double(cursorY)))
                cursorY += result.size.height
            case let .list(items, marker):
                try layoutList(items, marker: marker, cursorY: &cursorY, placed: &placed)
            }
        }
        return Document(blocks: placed, width: Double(width), height: Double(cursorY), renderer: typesetter.renderer)
    }

    private func layoutParagraph(
        _ content: ParagraphContent,
        indent: BlockIndent,
        columnWidth: Float,
    ) throws -> (LayoutResult, LoweredParagraph) {
        let lowered = try content.lowered(baseSize: baseSize)
        let (blockIndent, firstLineIndent) = indent.resolve()
        let result = typesetter.layout(LayoutInput(
            TiqianTextContent(lowered.text, lowered.spans.boringArray, lowered.sourceBoundaries.boringArray),
            TextStyle(BoringArray(), baseSize, lowered.locale.engineText),
            Self.paragraphStyle(firstLineIndent: firstLineIndent, blockIndent: blockIndent),
            try LayoutConstraints(columnWidth),
            BuiltInLayoutProfiles.ClreqHorizontal,
            lowered.decorations.readOnlyArray,
            lowered.rubySpans.readOnlyArray,
        ))
        return (result, lowered)
    }

    /// The engine's default paragraph style with the given indents. The generated initializer has
    /// unlabeled parameters, so the leading defaults are copied from `ParagraphStyle()`.
    private static func paragraphStyle(firstLineIndent: Ic?, blockIndent: Ic) -> ParagraphStyle {
        let defaults = ParagraphStyle()
        return ParagraphStyle(
            defaults.lastLineAlignment,
            defaults.writingMode,
            defaults.lineHeight,
            firstLineIndent,
            blockIndent,
        )
    }

    private func layoutList(
        _ items: [ParagraphContent],
        marker: ListMarkerFormat,
        cursorY: inout Float,
        placed: inout [PlacedBlock],
    ) throws {
        // The marker column already is the list's indent, so marker paragraphs never take the
        // adaptive body first-line indent; with it, the measured marker width would grow by two 字
        // and shift the whole body column.
        let defaults = ParagraphStyle()
        let markerStyle = ParagraphStyle(
            defaults.lastLineAlignment,
            defaults.writingMode,
            defaults.lineHeight,
            Ic.Zero,
            Ic.Zero,
            defaults.firstLineIndentPolicy,
            LineLengthGrid(false),
        )
        let markerResults = try items.indices.map { index in
            typesetter.layout(LayoutInput(
                TiqianTextContent(marker.format(index + 1).engineText),
                TextStyle(BoringArray(), baseSize),
                markerStyle,
                try LayoutConstraints(width),
            ))
        }
        // `ListMarkerColumnWidth`: the widest marker rounded up to whole 字, so every body and its
        // continuation lines align in one column.
        let widest = markerResults.map(\.size.width).max() ?? 0
        let gutter = Float(max(1, Int(ceil(widest / baseSize)))) * baseSize
        for (index, item) in items.enumerated() {
            let markerResult = markerResults[index]
            // `ListBodyMinimumMeasure`: a native view narrower than its marker column keeps the
            // gutter and lets the body overflow; the engine never receives a non-positive width.
            let bodyWidth = max(width - gutter, 1)
            let (bodyResult, lowered) = try layoutParagraph(item, indent: .flush, columnWidth: bodyWidth)
            // `ListFirstBaselineAlignment`: marker and body are separate paragraphs whose first-line
            // boxes may differ (•/decimal vs CJK). Align their baselines, then grow the row around
            // whichever block extends farther.
            let markerBaseline = markerResult.lines.first?.baseline ?? 0
            let bodyBaseline = bodyResult.lines.first?.baseline ?? 0
            let markerOffset = bodyBaseline - markerBaseline
            let rowTopOffset = min(0, markerOffset)
            // Marker alignment follows its occupied typographic box; the glyph's side bearings are
            // content, so no ink-edge correction applies.
            placed.append(PlacedBlock(
                result: markerResult,
                lowered: nil,
                x: 0,
                yTop: Double(cursorY + markerOffset - rowTopOffset),
            ))
            placed.append(PlacedBlock(
                result: bodyResult,
                lowered: lowered,
                x: Double(gutter),
                yTop: Double(cursorY - rowTopOffset),
                sourceSeparatorBefore: "",
            ))
            cursorY += max(markerOffset - rowTopOffset + markerResult.size.height, -rowTopOffset + bodyResult.size.height)
        }
    }
}
